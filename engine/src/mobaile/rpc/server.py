"""Servidor JSON-RPC do motor.

Uma unica classe concentra a sessao (dispositivo ativo, plataforma, gerador de
codigo, proxy, analytics) e expoe metodos nomeados. A camada de apresentacao,
seja o SwiftUI ou o Tk, nao toca em adapter nenhum: fala so este contrato.

Concorrencia:

- stdin e lido na thread principal. Cada requisicao vai para a fila serial do
  seu dominio (`contract.METHODS[...]["lane"]`), cada fila com a sua thread:
  um `wda.start` de minutos nao atrasa toque, parada de espelho nem
  encerramento. Metodos `inline` respondem na propria thread de leitura.
- Toda escrita no stdout, de resposta ou de notificacao, passa pelo mesmo lock.
  Duas linhas nunca se intercalam, que e a invariante que o protocolo exige.
- O estado de sessao (plataforma, alvo, arvore carregada) e protegido por
  `_state_lock` e carrega uma epoca. Leitura longa tira um retrato sob o lock,
  faz o I/O fora dele e so grava o resultado se a epoca nao mudou: uma arvore
  lida do aparelho anterior nunca sobrescreve a do aparelho novo.
"""

from __future__ import annotations

import base64
import faulthandler
import io
import json
import logging
import logging.handlers
import os
import pathlib
import queue
import re
import signal
import subprocess
import sys
import threading
import time
import traceback
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any, NamedTuple

from PIL import Image

from mobaile import __version__
from mobaile.adapters import ios_device_log
from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.analytics_logcat import FirebaseAnalyticsListener
from mobaile.adapters.android_okhttp_log import AndroidDebugNetworkCapture
from mobaile.adapters.appium import AppiumBridge
from mobaile.adapters.flow_devices import AndroidFlowDevice, IOSFlowDevice
from mobaile.adapters.ios_cfnetwork import IOSDebugNetworkCapture, raw_log_path
from mobaile.adapters.ios_wda import IOSBridge
from mobaile.adapters.mjpeg import MJPEGReader
from mobaile.adapters.proxy import MobileNetworkProxy
from mobaile.adapters.scrcpy import ScrcpyManager
from mobaile.adapters.screen_recorder import ScreenRecorder
from mobaile.adapters.vision_ocr import VisionOCR
from mobaile.config import settings
from mobaile.domain.errors import (
    DeviceNotFoundError,
    DeviceNotReadyError,
    EngineError,
    IncompatibleProtocolError,
    InvalidInputError,
    RequestCancelledError,
    ToolNotFoundError,
)
from mobaile.domain.models import LocatorStrategy, Platform, UIElement
from mobaile.rpc import contract, protocol
from mobaile.security import (
    build_adb_input_text_args,
    logs_dir,
    redact_urls_in_text,
    validate_coordinate,
    validate_device_id,
    validate_integer,
    validate_number,
)
from mobaile.services import flows, maestro_flow
from mobaile.services.codegen import CodeGenerator
from mobaile.services.devices import DeviceWatcher
from mobaile.services.diagnostics import DiagnosticsService
from mobaile.services.hierarchy import UIHierarchyParser
from mobaile.services.home import HomeService
from mobaile.services.report import ReportService
from mobaile.services.setup import SetupService
from mobaile.services.streaming import RealTimeStreamEngine

logger = logging.getLogger(__name__)

# PNG cru de aparelho moderno passa de 1 MB por quadro. O espelho e reduzido
# antes de virar base64: a fidelidade que importa e a de layout, nao a de pixel,
# e o inspetor continua usando a captura em resolucao cheia quando precisa.
STREAM_MAX_WIDTH = 900

# Quanto o encerramento espera as filas terminarem o que ja estava nelas. Passado
# isso o motor encerra assim mesmo: as threads das filas sao daemon, e uma
# chamada presa num `xcodebuild` nao pode segurar o fechamento do app.
LANE_DRAIN_TIMEOUT_S = 2.0
# Com que frequencia o laco de leitura confere se alguem pediu a parada (SIGTERM).
STOP_POLL_S = 0.1


class _Sessao(NamedTuple):
    """Retrato do alvo da sessao, tirado sob `_state_lock`.

    Quem faz I/O trabalha sobre o retrato, e nao sobre `self.platform` e
    `self.device_id`: ler os dois em momentos diferentes podia combinar a
    plataforma nova com o aparelho antigo no meio de uma troca.
    """

    platform: Platform
    device_id: str | None
    epoch: int


@dataclass(eq=False)
class _Request:
    """Requisicao ja validada, pronta para rodar em qualquer fila.

    `eq=False` porque a fila remove por identidade: dois pedidos iguais em
    conteudo continuam sendo pedidos diferentes.
    """

    request_id: Any
    method: str
    params: dict[str, Any]
    handler: Callable[[dict[str, Any]], Any] | None
    progress_token: str | int | float | None = None
    cancelled: threading.Event = field(default_factory=threading.Event)
    # Protegido por `EngineServer._requests_lock`. Quem marca primeiro, a
    # execucao ou o cancelamento, e quem responde: um id nunca recebe duas
    # respostas.
    answered: bool = False


class _Lane:
    """Fila serial com thread propria.

    Serial de proposito: dentro de um dominio a ordem de chegada e a ordem de
    execucao, e dois `hierarchy.dump` nunca disputam o mesmo `uiautomator`.
    """

    def __init__(self, name: str, run: Callable[[_Request], None]) -> None:
        self.name = name
        self._run = run
        self._pending: deque[_Request] = deque()
        self._cond = threading.Condition()
        self._closed = False
        self._thread = threading.Thread(target=self._loop, daemon=True, name=f"mobaile-lane-{name}")

    def start(self) -> None:
        self._thread.start()

    def put(self, request: _Request) -> None:
        with self._cond:
            self._pending.append(request)
            self._cond.notify()

    def remove(self, request: _Request) -> bool:
        """Tira da fila um pedido que ainda nao comecou."""
        with self._cond:
            try:
                self._pending.remove(request)
            except ValueError:
                return False
            return True

    def close(self) -> None:
        """Para de esperar trabalho novo. O que ja esta na fila ainda roda."""
        with self._cond:
            self._closed = True
            self._cond.notify()

    def join(self, timeout: float) -> bool:
        """Espera a fila esvaziar. Devolve se a thread terminou no prazo."""
        self._thread.join(timeout)
        return not self._thread.is_alive()

    def _loop(self) -> None:
        while True:
            with self._cond:
                while not self._pending and not self._closed:
                    self._cond.wait()
                if not self._pending:
                    return
                request = self._pending.popleft()
            self._run(request)


def _dentro_de(caminho: pathlib.Path, raiz: pathlib.Path) -> bool:
    """`caminho`, com links simbolicos e `..` resolvidos, fica sob `raiz`?"""
    return caminho.resolve().is_relative_to(raiz.resolve())


class EngineServer:
    """Estado da sessao e tabela de metodos."""

    def __init__(self, out=None, log_path: str | None = None) -> None:
        self._out = out or sys.stdout
        # Arquivo de log deste motor, ou `None` se ele subiu só com stderr.
        # Vai no `engine.hello` e no `engine.info` para o front citar na queda.
        self.log_path = log_path
        self._write_lock = threading.Lock()
        self._running = True
        self._shutdown_done = False

        # Despacho. As filas so nascem em `serve_forever`: quem usa
        # `handle_message` direto, como os testes de contrato e o gerador de
        # fixtures, continua sincrono e sem thread nenhuma.
        self._lanes: dict[str, _Lane] = {}
        self._requests_lock = threading.Lock()
        self._in_flight: dict[Any, _Request] = {}
        # Requisicao em execucao nesta thread. Thread-local, e nao contextvar,
        # para uma thread criada por um metodo (escuta passiva, fluxo) nunca
        # herdar o cancelamento ou o progresso de quem a criou.
        self._local = threading.local()

        self.adb = ADBBridge()
        self.ios = IOSBridge()
        self.scrcpy = ScrcpyManager()
        self.proxy = MobileNetworkProxy()
        # Mesmo historico e mesma notificacao do proxy: para o front, e so
        # outra origem de requisicoes.
        self.ios_netlog = IOSDebugNetworkCapture(emit=self.proxy.emit_event, next_id=self.proxy.get_next_event_id)
        # O par no Android: o log do OkHttp de um app em debug, pelo logcat.
        self.android_netlog = AndroidDebugNetworkCapture(
            adb_path=lambda: self.adb.adb_path, emit=self.proxy.emit_event, next_id=self.proxy.get_next_event_id,
        )
        self.recorder = ScreenRecorder(self.adb, self.ios)
        self.analytics = FirebaseAnalyticsListener(adb_bridge=self.adb)
        # Uma vez so: registrar a cada analytics.start duplicava cada evento
        # na UI apos parar e reiniciar a escuta.
        self.analytics.add_event_callback(lambda event: self.notify("analytics.event", event.to_dict()))
        self.codegen = CodeGenerator()
        self.appium = AppiumBridge()
        self.diagnostics = DiagnosticsService(adb=self.adb, ios=self.ios, appium=self.appium)
        self.setup = SetupService(adb=self.adb, appium=self.appium, scrcpy=self.scrcpy)
        # Lê `self.setup` a cada chamada: o gerador de fixtures troca o serviço.
        self.home = HomeService(setup=lambda: self.setup, ios=self.ios, adb=self.adb)
        self.report = ReportService(ocr=VisionOCR())

        # Estado de sessao. Escrito pelas filas, pelo vigia de dispositivos e
        # pelas threads da escuta passiva, sempre sob `_state_lock`. A epoca
        # sobe a cada troca de alvo; ver `_store_hierarchy`.
        self._state_lock = threading.RLock()
        self._session_epoch = 0
        self.platform: Platform = Platform.ANDROID
        self.device_id: str | None = None
        # Ultima auditoria (titulo, subtitulo, spec): o export atualiza o recente dela.
        self._ultimo_relatorio: tuple[str, str, str] | None = None
        self.current_xml: str | None = None
        # (serial, porta) do aparelho Android em que `proxy.start` ligou o
        # proxy global e o `adb reverse`. O desmonte usa este registro, e nao o
        # aparelho atual da sessao, que pode ter mudado (ARQ-1).
        self._proxy_device: tuple[str, int] | None = None
        # Este motor ja configurou algum aparelho? Se nao, um `proxy.stop`
        # sem registro e a recuperacao do front depois de o motor anterior
        # cair, e a limpeza vai para o aparelho da sessao.
        self._proxy_configured_once = False
        # Desmontes que nao se confirmaram (cabo solto, adb sem resposta):
        # serial -> porta. Retentados quando o serial reaparece e no
        # encerramento, em vez de esquecidos.
        self._proxy_pending: dict[str, int] = {}
        self._proxy_retrying: set[str] = set()
        self._proxy_retry_threads: list[threading.Thread] = []
        # Seriais Android presentes na ultima listagem: a retentativa so roda
        # na transicao ausente -> presente, e nao a cada varredura.
        self._proxy_seen: set[str] | None = None
        # Um desmonte por vez: duas chamadas seguidas no mesmo serial apagariam
        # o valor que a primeira acabou de restaurar (adb.py guarda o original
        # uma vez so).
        self._proxy_teardown_lock = threading.Lock()
        self._stream: RealTimeStreamEngine | None = None
        # Leitor do MJPEG do WDA, so enquanto o espelho iOS estiver ligado.
        self._mjpeg: MJPEGReader | None = None
        self._watcher: DeviceWatcher | None = None
        self._flow_thread = None
        self._flow_running = False
        self._flow_cancelled = False
        self._passive = None
        self._digitando = False
        self._campo_digitado: str | None = None
        self._last_hierarchy_time: float = 0.0
        self._android_backend: dict[str, str] = {}
        self._keyboard_cache: tuple[float, bool] | None = None

        self.methods: dict[str, Callable[[dict[str, Any]], Any]] = {
            "engine.hello": self.engine_hello,
            "engine.info": self.engine_info,
            "engine.shutdown": self.engine_shutdown,
            "session.select_device": self.session_select_device,
            "session.correlate": self.session_correlate,
            "devices.list": self.devices_list,
            "devices.watch_start": self.devices_watch_start,
            "devices.watch_stop": self.devices_watch_stop,
            "diagnostics.check": self.diagnostics_check,
            "setup.check": self.setup_check,
            "home.summary": self.home_summary,
            "home.forget_recent": self.home_forget_recent,
            "simulators.list": self.simulators_list,
            "simulators.boot": self.simulators_boot,
            "simulators.shutdown": self.simulators_shutdown,
            "emulators.list": self.emulators_list,
            "emulators.boot": self.emulators_boot,
            "wda.start": self.wda_start,
            "wda.status": self.wda_status,
            "recording.start": self.recording_start,
            "recording.stop": self.recording_stop,
            "recording.status": self.recording_status,
            "screen.capture": self.screen_capture,
            "screen.size": self.screen_size,
            "hierarchy.dump": self.hierarchy_dump,
            "hierarchy.element_at": self.hierarchy_element_at,
            "input.tap": self.input_tap,
            "input.text": self.input_text,
            "stream.start": self.stream_start,
            "stream.stop": self.stream_stop,
            "stream.stats": self.stream_stats,
            "scrcpy.start": self.scrcpy_start,
            "scrcpy.stop": self.scrcpy_stop,
            "scrcpy.status": self.scrcpy_status,
            "proxy.start": self.proxy_start,
            "proxy.stop": self.proxy_stop,
            "proxy.events": self.proxy_events,
            "proxy.clear": self.proxy_clear,
            "proxy.diagnose": self.proxy_diagnose,
            "netlog.start": self.netlog_start,
            "netlog.stop": self.netlog_stop,
            "analytics.start": self.analytics_start,
            "analytics.stop": self.analytics_stop,
            "analytics.events": self.analytics_events,
            "analytics.clear": self.analytics_clear,
            "analytics.ios_devices": self.analytics_ios_devices,
            "codegen.record": self.codegen_record,
            "codegen.steps": self.codegen_steps,
            "codegen.reset": self.codegen_reset,
            "codegen.save": self.codegen_save,
            "flow.run": self.flow_run,
            "flow.stop": self.flow_stop,
            "flow.status": self.flow_status,
            "flow.maestro_check": self.flow_maestro_check,
            "flow.maestro_export": self.flow_maestro_export,
            "flow.maestro_run": self.flow_maestro_run,
            "passive.start": self.passive_start,
            "passive.stop": self.passive_stop,
            "passive.status": self.passive_status,
            "report.spec": self.report_spec,
            "report.audit": self.report_audit,
            "report.export": self.report_export,
            "report.import": self.report_import,
            "report.card": self.report_card,
            "report.card_update": self.report_card_update,
        }

    # -------------------------------------------------------------- transporte

    def send(self, message: dict[str, Any]) -> None:
        with self._write_lock:
            self._out.write(protocol.encode(message))
            self._out.flush()

    def notify(self, method: str, params: Any) -> None:
        self.send(protocol.notification(method, params))

    # ------------------------------------------------ cancelamento e progresso

    def _current_request(self) -> _Request | None:
        return getattr(self._local, "request", None)

    def _cancelled(self) -> bool:
        """O cliente desistiu da requisicao que esta rodando nesta thread?"""
        request = self._current_request()
        return request is not None and request.cancelled.is_set()

    def _check_cancelled(self) -> None:
        """Para cedo entre etapas de um metodo longo.

        O handler nao e interrompido a forca: Python nao mata thread. Ele checa
        aqui nos pontos em que parar e seguro, e o erro levantado so encerra a
        execucao, porque o cliente ja recebeu a resposta de cancelamento.
        """
        if self._cancelled():
            raise RequestCancelledError()

    def _progress(self, message: str, percent: float | None = None) -> None:
        """Emite `$/progress` se a requisicao atual pediu, com `progress_token`."""
        request = self._current_request()
        if request is None or request.progress_token is None or request.cancelled.is_set():
            return
        self.notify(contract.PROGRESS, {"token": request.progress_token, "message": message, "percent": percent})

    # ------------------------------------------------------------------ helpers

    def _sessao(self) -> _Sessao:
        with self._state_lock:
            return _Sessao(self.platform, self.device_id, self._session_epoch)

    def _require_session(self) -> _Sessao:
        sessao = self._sessao()
        if not sessao.device_id:
            raise InvalidInputError("Nenhum dispositivo selecionado nesta sessao.")
        return sessao

    def _require_device(self) -> str:
        return self._require_session().device_id

    def _capture_image(self, sessao: _Sessao):
        """Captura a tela do alvo do retrato. Faz I/O: nunca chamar segurando o lock."""
        if sessao.platform is Platform.IOS:
            return self.ios.take_screenshot(sessao.device_id)
        return self.adb.take_screenshot(sessao.device_id)

    def _fetch_hierarchy(self, sessao: _Sessao) -> str | None:
        """Le a arvore do alvo do retrato. Faz I/O: nunca chamar segurando o lock."""
        if sessao.platform is Platform.IOS:
            return self.ios.get_ui_hierarchy()
        return self._android_hierarchy(sessao.device_id or "")

    def _store_hierarchy(self, xml: str, epoch: int) -> bool:
        """Grava a arvore so se o alvo nao mudou enquanto ela era lida.

        Um dump leva segundos. Se no meio dele o usuario trocou de aparelho, a
        arvore que chega descreve o aparelho anterior, e grava-la faria o
        proximo `codegen.record` resolver o toque contra a tela errada.
        """
        with self._state_lock:
            if epoch != self._session_epoch:
                logger.info("Hierarquia descartada: o alvo da sessao mudou durante a leitura.")
                return False
            self.current_xml = xml
            self._last_hierarchy_time = time.time()
            return True

    @staticmethod
    def _encode_png(image, max_width: int | None = None) -> dict[str, Any]:
        width, height = image.size
        if max_width and width > max_width:
            ratio = max_width / float(width)
            image = image.resize((max_width, int(height * ratio)))
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=False, compress_level=1)
        return {
            "png_base64": base64.b64encode(buffer.getvalue()).decode("ascii"),
            "width": image.size[0],
            "height": image.size[1],
            "source_width": width,
            "source_height": height,
        }

    @staticmethod
    def _encode_frame(image, max_width: int | None, fmt: str, quality: int) -> dict[str, Any]:
        """Quadro do espelho: JPEG por padrao, PNG a pedido.

        `format` e `image_base64` sao os campos novos; `png_base64` continua
        quando o formato e PNG, para front anterior a 3.6 seguir funcionando.
        Um quadro que ja chegou como JPEG (MJPEG do WDA, em `info`) e repassado
        sem reencodar quando cabe no `max_width`.
        """
        width, height = image.size
        if fmt == "png":
            payload = EngineServer._encode_png(image, max_width)
            payload["format"] = "png"
            payload["image_base64"] = payload["png_base64"]
            return payload
        original = image.info.get("mobaile_jpeg") if isinstance(image.info, dict) else None
        if original and not (max_width and width > max_width):
            data = original
            out_w, out_h = width, height
        else:
            if max_width and width > max_width:
                ratio = max_width / float(width)
                image = image.resize((max_width, int(height * ratio)))
            if image.mode not in ("RGB", "L"):
                image = image.convert("RGB")
            buffer = io.BytesIO()
            image.save(buffer, format="JPEG", quality=quality, optimize=False)
            data = buffer.getvalue()
            out_w, out_h = image.size
        return {
            "format": "jpeg",
            "image_base64": base64.b64encode(data).decode("ascii"),
            "width": out_w,
            "height": out_h,
            "source_width": width,
            "source_height": height,
        }

    # ------------------------------------------------------------------ metodos

    def engine_hello(self, params: dict[str, Any]) -> dict[str, Any]:
        """Aperto de mao: confere a versao do contrato e entrega a tabela.

        Opcional para o motor atender, obrigatorio para o front novo: e dele
        que o front tira o prazo de cada metodo, em vez de manter uma tabela
        propria que envelheceria separada desta.
        """
        cliente = params.get("protocol_version")
        if cliente != contract.PROTOCOL_VERSION:
            raise IncompatibleProtocolError(
                f"Protocolo incompativel: o front fala a versao {cliente} e o motor, a versao "
                f"{contract.PROTOCOL_VERSION}. Atualize o Mo baile para que os dois andem juntos."
            )
        return contract.hello_payload(__version__, log_path=self.log_path)

    def engine_info(self, _params: dict[str, Any]) -> dict[str, Any]:
        sessao = self._sessao()
        return {
            "version": __version__,
            "platform": sessao.platform.value,
            "device_id": sessao.device_id,
            "adb_path": self.adb.adb_path,
            "adb_available": self.adb.is_available(),
            "scrcpy_available": self.scrcpy.is_available(),
            "wda_url": settings.wda_url,
            # A interface mostra o nome do arquivo que o Salvar vai escrever;
            # sem isto ela exibia "feature.py" fixo, que nao correspondia.
            "page_objects_key": settings.page_objects_key,
            "proxy": {"host": settings.proxy_host, "port": settings.proxy_port, "running": self.proxy.is_running()},
            "methods": sorted(self.methods),
            "log_path": self.log_path,
        }

    def engine_shutdown(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Pede o encerramento e responde na hora.

        O desmonte de verdade (proxy do aparelho, gravacao, Appium) pode levar
        segundos, e o front espera esta resposta para fechar. Por isso ele roda
        depois, quando o laco de leitura termina. Quem usa `handle_message`
        direto e dono do ciclo de vida e chama `shutdown()` por conta propria.
        """
        self._running = False
        return {"stopped": True}

    def session_select_device(self, params: dict[str, Any]) -> dict[str, Any]:
        platform_raw = str(params.get("platform", self.platform.value)).lower()
        if platform_raw not in ("ios", "android"):
            raise InvalidInputError(f"Plataforma invalida: {platform_raw!r}")
        platform = Platform(platform_raw)
        # Valida antes de mexer no estado: um serial recusado nao pode deixar a
        # sessao com a plataforma nova e o aparelho antigo.
        device_id = params.get("device_id")
        device_id = validate_device_id(device_id) if device_id else None
        with self._state_lock:
            self.platform = platform
            self.device_id = device_id
            self.current_xml = None
            self._last_hierarchy_time = 0.0
            self._session_epoch += 1
            proxy_anterior = self._proxy_device
            if proxy_anterior and proxy_anterior[0] != device_id:
                self._proxy_device = None
            else:
                proxy_anterior = None
        if proxy_anterior:
            # O aparelho que sai da sessao nao pode ficar com proxy apontando
            # para ca: quando o motor parar, ele fica sem rede.
            self._teardown_proxy_device(*proxy_anterior)
        watcher = self._watcher
        if watcher:
            # Informa o alvo escolhido, e nao so a plataforma: senao a varredura
            # seguinte elegia o primeiro alvo e desfazia a escolha (M1).
            watcher.set_target(platform.value, device_id)
        return {"platform": platform.value, "device_id": device_id}

    # Janela padrao em volta do toque: um pouco antes (o app ja pode ter
    # disparado algo ao pressionar) e alguns segundos depois (resposta e evento).
    _CORRELATE_BEFORE_S = 1.0
    _CORRELATE_AFTER_S = 4.0

    def session_correlate(self, params: dict[str, Any]) -> dict[str, Any]:
        """Requisicoes e eventos de analytics na janela de tempo de um passo.

        Atribuicao por tempo, nao causal: por isso `probable` e sempre `true`.
        Todos os carimbos sao do relogio do Mac na recepcao (proxy, logcat e
        gravacao do passo), entao nao ha relogio do aparelho a corrigir. A
        janela termina no passo seguinte, se ele vier antes do prazo.
        """
        step_num = validate_integer(params.get("step_num"), "step_num", minimum=0, maximum=1_000_000)
        before = validate_number(params.get("before_s", self._CORRELATE_BEFORE_S), "before_s", minimum=0, maximum=60)
        after = validate_number(params.get("after_s", self._CORRELATE_AFTER_S), "after_s", minimum=0, maximum=60)

        passos = self.codegen.get_steps()
        passo = next((p for p in passos if p.step_num == step_num), None)
        if passo is None:
            raise InvalidInputError(f"Nao ha passo {step_num}.")
        if not passo.recorded_at:
            raise InvalidInputError(f"O passo {step_num} nao tem hora de gravacao.")

        inicio = passo.recorded_at - before
        fim = passo.recorded_at + after
        proximo = next((p.recorded_at for p in passos if p.step_num > step_num and p.recorded_at), None)
        if proximo is not None:
            fim = min(fim, proximo)

        requisicoes = [e.id for e in self.proxy.events_history if inicio <= e.timestamp <= fim]
        eventos = [e.id for e in self.analytics.history_events() if inicio <= e.timestamp <= fim]
        return {
            "step_num": step_num,
            "recorded_at": passo.recorded_at,
            "window": [inicio, fim],
            "requests": requisicoes,
            "events": eventos,
            "probable": True,
        }

    def devices_list(self, params: dict[str, Any]) -> dict[str, Any]:
        platform_raw = str(params.get("platform", self.platform.value)).lower()
        if platform_raw == "ios":
            devices = [
                {"id": udid, "name": name, "platform": "ios", "state": "device", "ready": True}
                for udid, name in self.ios.list_booted_simulators()
            ]
        else:
            devices = [device.to_dict() for device in self.adb.list_devices_typed()]
        return {"devices": devices}

    def devices_watch_start(self, params: dict[str, Any]) -> dict[str, Any]:
        """Liga a deteccao automatica.

        A cada mudanca o motor empurra a notificacao `device.changed`. A
        interface nao faz polling, e o aparelho aparece sozinho ao ser plugado.
        """
        self.devices_watch_stop({})
        interval = validate_number(
            params.get("poll_interval") or settings.poll_interval, "poll_interval", minimum=0.01, maximum=3600,
        )

        def on_changed(platform: str, device_id: str) -> None:
            # Selecao implicita: se o alvo detectado e o unico, ele vira o alvo
            # da sessao. Sem isso o usuario plugaria o cabo e ainda teria que
            # escolher o aparelho num menu de um item so.
            with self._state_lock:
                if platform == "none":
                    self.device_id = None
                    self.current_xml = None
                    self._session_epoch += 1
                elif platform != self.platform.value:
                    # Deteccao atrasada da plataforma anterior, que chegou entre
                    # a troca de plataforma e o vigia ser avisado dela. Aplicar
                    # poria um serial Android numa sessao iOS.
                    return
                elif device_id != self.device_id:
                    self.device_id = device_id
                    self.current_xml = None
                    self._session_epoch += 1
            self.notify("device.changed", {"platform": platform, "device_id": device_id or None})
            self.notify("home.changed", {"reason": "device"})

        self._watcher = DeviceWatcher(
            adb_bridge=self.adb,
            ios_bridge=self.ios,
            on_device_changed=on_changed,
            target_platform=self.platform.value,
            poll_interval=interval,
            on_targets_listed=self._on_targets_listed,
        )
        # Se a sessao ja tem alvo, o vigia parte dele em vez de eleger o primeiro.
        self._watcher.set_target(self.platform.value, self.device_id)
        self._watcher.start()
        return {"watching": True, "platform": self.platform.value, "poll_interval": interval}

    def devices_watch_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        if self._watcher:
            self._watcher.stop()
            self._watcher = None
        return {"watching": False}

    # ------------------------------------------------- ambiente e inicializacao

    def diagnostics_check(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Estado real do ambiente nas duas plataformas.

        Substitui o cartao de diagnostico que o front desenhava com valores
        escritos no codigo. Mesmo formato de `DiagnosticsService.run`, mas uma
        plataforma de cada vez: entre as duas da para avisar o progresso e
        parar se o front desistiu.
        """
        self._progress("Verificando o ambiente iOS", 0)
        ios = self.diagnostics.ios_diagnostics().to_dict()
        self._check_cancelled()
        self._progress("Verificando o ambiente Android", 50)
        android = self.diagnostics.android_diagnostics().to_dict()
        return {"ios": ios, "android": android}

    def setup_check(self, _params: dict[str, Any]) -> dict[str, Any]:
        """O que esta instalado e o que cada area precisa (tela Inicio).

        A plataforma da sessao vai primeiro no proximo passo: quem esta no
        Android ve o que falta para o Android antes do que falta para o iOS.
        """
        with self._state_lock:
            plataforma = self.platform.value
        return self.setup.run(platform_in_use=plataforma)

    def home_summary(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Tela Inicio: primeira vez ou dia a dia, alvos, recentes e novidades."""
        with self._state_lock:
            plataforma = self.platform.value
            device_id = self.device_id
        return self.home.summary(platform_in_use=plataforma, device_id=device_id)

    def home_forget_recent(self, params: dict[str, Any]) -> dict[str, Any]:
        """Tira um item do "Continuar de onde parou" (o arquivo sumiu)."""
        caminho = params.get("path")
        if not isinstance(caminho, str) or not caminho.strip():
            raise InvalidInputError("Passe `path`, o caminho do item.")
        removido = self.home.recents.forget(caminho)
        if removido:
            self.notify("home.changed", {"reason": "recent"})
        return {"removed": removido}

    def _remember(self, kind: str, title: str, subtitle: str, path: str) -> None:
        """Guarda o item nos recentes da Inicio e avisa a interface."""
        if self.home.recents.record(kind, title, subtitle, path):
            self.notify("home.changed", {"reason": "recent"})

    def simulators_list(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Todos os simuladores instalados, e nao so os que ja estao ligados."""
        return {"simulators": self.ios.list_all_simulators()}

    def simulators_boot(self, params: dict[str, Any]) -> dict[str, Any]:
        """Liga um simulador e traz a janela do Simulator para a frente.

        Sem `udid`, escolhe o primeiro disponivel: e o caso comum de quem so
        quer comecar a trabalhar.
        """
        udid = params.get("udid")
        if not udid:
            self._progress("Procurando um simulador instalado")
            disponiveis = self.ios.list_all_simulators()
            if not disponiveis:
                raise EngineError("Nenhum simulador instalado neste Mac.")
            ja_ligado = next((s for s in disponiveis if s["booted"]), None)
            udid = (ja_ligado or disponiveis[0])["udid"]

        # Listar leva segundos com muitos runtimes; se o front desistiu nesse
        # meio tempo, nao faz sentido ligar um simulador que ninguem espera.
        self._check_cancelled()
        self._progress(f"Ligando o simulador {udid}")
        ok, mensagem = self.ios.boot_simulator(udid, open_app=bool(params.get("open_app", True)))
        if not ok:
            raise EngineError(f"Nao foi possivel iniciar o simulador: {mensagem}")
        return {"udid": udid, "message": mensagem, "booted": True}

    def simulators_shutdown(self, params: dict[str, Any]) -> dict[str, Any]:
        udid = params.get("udid")
        if not udid:
            raise InvalidInputError("Informe o udid do simulador a desligar.")
        return {"ok": self.ios.shutdown_simulator(udid)}

    def emulators_list(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {"avds": self.adb.list_avds()}

    def emulators_boot(self, params: dict[str, Any]) -> dict[str, Any]:
        """Liga um AVD do Android. Sem `name`, usa o primeiro da lista."""
        nome = params.get("name")
        if not nome:
            self._progress("Procurando um AVD criado")
            avds = self.adb.list_avds()
            if not avds:
                raise EngineError("Nenhum AVD criado. Crie um pelo Android Studio.")
            nome = avds[0]
        self._check_cancelled()
        self._progress(f"Iniciando o AVD {nome}")
        if not self.adb.start_avd(nome):
            raise EngineError(f"Nao foi possivel iniciar o AVD '{nome}'.")
        return {"name": nome, "starting": True}

    # ------------------------------------------------------- gravacao de tela

    def recording_start(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Grava video da tela do alvo ativo.

        Android usa `screenrecord`, iOS usa `simctl io recordVideo`. A escolha
        e do motor: a interface so pede "grava", e nao precisa saber qual das
        duas ferramentas existe em cada plataforma.
        """
        sessao = self._require_session()
        return self.recorder.start(sessao.platform, sessao.device_id)

    def recording_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Encerra e devolve o arquivo. Idempotente."""
        return self.recorder.stop()

    def recording_status(self, _params: dict[str, Any]) -> dict[str, Any]:
        return self.recorder.status()

    def wda_status(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {
            "wda_running": self.ios.is_wda_running(),
            "appium_installed": self.appium.is_installed,
            "appium_running": self.appium.is_running(),
            "appium_url": self.appium.base_url,
            "wda_url": self.appium.wda_url,
        }

    def wda_start(self, params: dict[str, Any]) -> dict[str, Any]:
        """Sobe o WebDriverAgent pedindo ao Appium.

        Sem `udid`, usa o simulador ligado. Compilar o WDA na primeira execucao
        leva minutos, por isso o timeout desta chamada e generoso: o front deve
        mostrar progresso em vez de desistir.
        """
        udid = params.get("udid")
        if not udid:
            self._progress("Procurando o simulador ligado")
            ligados = [s for s in self.ios.list_all_simulators() if s["booted"]]
            if not ligados:
                raise EngineError("Nenhum simulador ligado. Abra um simulador antes de iniciar o WDA.")
            udid = ligados[0]["udid"]

        # Ultimo ponto barato para desistir: dali em diante o Appium pode
        # passar minutos compilando o WDA.
        self._check_cancelled()
        self._progress("Subindo o WebDriverAgent pelo Appium. Na primeira vez ele compila, o que leva minutos.")
        ok, mensagem = self.appium.ensure_wda(udid, params.get("platform_version"))
        if not ok:
            raise EngineError(mensagem)
        self._progress("WebDriverAgent no ar", 100)
        return {"udid": udid, "message": mensagem, "wda_running": True}

    def screen_capture(self, params: dict[str, Any]) -> dict[str, Any]:
        sessao = self._require_session()
        image = self._capture_image(sessao)
        if image is None:
            raise EngineError("Nao foi possivel capturar a tela do dispositivo.")
        max_width = params.get("max_width")
        payload = self._encode_png(
            image, validate_integer(max_width, "max_width", minimum=16, maximum=16384) if max_width else None,
        )
        # A captura leva segundos; se o alvo mudou no meio, o front precisa
        # saber de qual aparelho a imagem veio para nao mostra-la no lugar errado.
        payload["device_id"] = sessao.device_id
        return payload

    def screen_size(self, _params: dict[str, Any]) -> dict[str, Any]:
        sessao = self._require_session()
        if sessao.platform is Platform.IOS:
            image = self.ios.take_screenshot(sessao.device_id)
            if image is None:
                raise EngineError("Simulador nao respondeu a captura.")
            width, height = image.size
        else:
            width, height = self.adb.get_screen_size(sessao.device_id)
        return {"width": width, "height": height}

    @staticmethod
    def _elements_payload(xml: str) -> dict[str, Any]:
        elements = UIHierarchyParser.parse_xml(xml)
        return {"count": len(elements), "elements": [element.to_dict() for element in elements]}

    def hierarchy_dump(self, params: dict[str, Any]) -> dict[str, Any]:
        sessao = self._require_session()
        force = bool(params.get("force", False))
        with self._state_lock:
            recente = time.time() - self._last_hierarchy_time < 1.2
            em_cache = self.current_xml if (not force and recente) else None
        if em_cache:
            return self._elements_payload(em_cache)

        xml = self._fetch_hierarchy(sessao)
        if not xml:
            raise EngineError(self._motivo_de_hierarquia_indisponivel())
        # Se o alvo mudou durante a leitura a arvore nao vira estado, mas a
        # resposta sai: e o que este pedido perguntou, e o front casa pelo id.
        self._store_hierarchy(xml, sessao.epoch)
        return self._elements_payload(xml)

    def _android_hierarchy(self, device: str) -> str | None:
        """Hierarquia do Android, com o WebDriver como segunda tentativa.

        `uiautomator dump` e o caminho rapido e nao exige sessao, mas falha em
        parte dos aparelhos: em Motorola com Android 14 ele e morto com SIGKILL
        e volta vazio. Quando isso acontece, o mesmo servico e alcancado pela
        sessao UiAutomator2 do Appium, que e o equivalente Android do WDA.
        """
        # Se este aparelho já foi identificado como dependente do Appium, tenta
        # direto a sessão ativa para não perder segundos repetindo um uiautomator
        # dump que sempre falhará.
        if self._android_backend.get(device) == "appium":
            self._progress("Lendo a hierarquia pela sessao do Appium")
            if self.appium.session_id and self.appium.session_platform == "android" and self.appium.session_udid == device:
                xml = self.appium.get_page_source()
                if xml:
                    return xml
            ok, mensagem = self.appium.ensure_android_session(device)
            if ok:
                xml = self.appium.get_page_source()
                if xml:
                    return xml
            self._android_backend.pop(device, None)

        xml = self.adb.get_ui_hierarchy(device)
        if xml:
            self._android_backend[device] = "adb"
            return xml

        bloqueio = self.adb.dump_blocked_by.get(device)
        if bloqueio:
            # O Appium esbarraria na mesma instrumentacao depois de dezenas de
            # segundos, e memoriza-lo deixaria o aparelho preso a ele depois
            # que a outra ferramenta saisse.
            self._android_backend.pop(device, None)
            self._ultima_falha_de_hierarquia = self._mensagem_de_bloqueio(device, bloqueio)
            logger.warning("Hierarquia de %s bloqueada pela instrumentacao %s.", device, bloqueio)
            return None

        # So o SIGKILL prova que o aparelho nao tem dump. Um vazio por tela sem
        # ocio ou por corrida com outra leitura abre o Appium para esta leitura,
        # mas nao troca o backend do aparelho para sempre.
        if self.adb.dump_killed.get(device):
            logger.info("uiautomator dump morto para %s; memorizando backend Appium.", device)
            self._android_backend[device] = "appium"
        else:
            logger.info("uiautomator dump vazio para %s; tentando o Appium nesta leitura.", device)
        # Entre o dump rapido e o Appium, que na primeira vez leva dezenas de
        # segundos: e o ponto natural para parar se o front ja desistiu.
        self._check_cancelled()
        self._progress("uiautomator dump vazio; abrindo sessao do Appium, o que pode levar dezenas de segundos")
        ok, mensagem = self.appium.ensure_android_session(device)
        if not ok:
            self._ultima_falha_de_hierarquia = mensagem
            logger.warning("Sessao Android do Appium indisponivel: %s", mensagem)
            return None
        self._progress("Lendo a hierarquia pelo Appium")
        return self.appium.get_page_source()

    @staticmethod
    def _mensagem_de_bloqueio(device: str, pacote: str) -> str:
        """Diz quem segura o UiAutomation e o comando que o libera."""
        app = pacote.removesuffix(".test")
        dono = "O driver do Maestro" if app == "dev.mobile.maestro" else f"A instrumentacao {pacote}"
        return (
            f"{dono} esta rodando no aparelho e ocupa o UiAutomation, que so aceita um "
            "cliente por vez: nem o 'uiautomator dump' nem o Appium conseguem ler a tela. "
            "Encerre a ferramenta que o abriu ou, se ela ja foi fechada, libere o aparelho "
            f"com: adb -s {device} shell am force-stop {app}"
        )

    def _sessao_appium_aberta(self, device: str) -> bool:
        return bool(self.appium.session_id and self.appium.session_platform == "android"
                    and self.appium.session_udid == device)

    _SEM_SESSAO_APPIUM = (
        "Este aparelho so devolve a tela pelo Appium, e a sessao nao esta aberta. Atualize a "
        "hierarquia no inspetor, que abre a sessao, e rode de novo."
    )

    def _conferir_leitura_do_flow(self, device: str) -> None:
        """Recusa o flow antes de ocupar o aparelho quando ele nao tera como ler a tela.

        O aparelho que so le pelo Appium precisa da sessao aberta. Abri-la aqui
        levaria ate minutos dentro de um pedido de 30 s, sem progresso; o
        inspetor faz isso com progresso e cancelamento.
        """
        if self._android_backend.get(device) == "appium" and not self._sessao_appium_aberta(device):
            raise EngineError(self._SEM_SESSAO_APPIUM)

    def _leitor_do_flow(self, device: str) -> tuple[Callable[[], str | None], Callable[[], str | None]]:
        """Leitor da arvore para a thread do flow e o backend da ultima leitura.

        Uma sessao UiAutomator2 ja aberta le em centesimos de segundo, contra
        cerca de 2 s do `uiautomator dump`, e e usada sempre que existir. O
        leitor nunca abre sessao nem muda o backend memorizado do aparelho. A
        arvore lida vira a atual, para o inspetor do espelho, que pede a sua a
        cada tela assentada, achar a leitura pronta em vez de disputar o dump.
        """
        with self._state_lock:
            epoch = self._session_epoch
        estado: dict[str, str | None] = {"backend": None}

        def ler() -> str | None:
            xml, backend = None, None
            if self._sessao_appium_aberta(device):
                xml, backend = self.appium.get_page_source(), "appium"
            if not xml and self._android_backend.get(device) != "appium":
                xml, backend = self.adb.get_ui_hierarchy(device), "adb"
                bloqueio = None if xml else self.adb.dump_blocked_by.get(device)
                if bloqueio:
                    raise EngineError(self._mensagem_de_bloqueio(device, bloqueio))
                if not xml and self.adb.dump_killed.get(device):
                    # Dump morto (137) num aparelho que o motor ainda nao conhecia:
                    # sem isto o flow falharia em 17 s dizendo so que nao leu nada.
                    raise EngineError(self._SEM_SESSAO_APPIUM)
            estado["backend"] = backend if xml else None
            if xml:
                self._store_hierarchy(xml, epoch)
            return xml

        return ler, lambda: estado["backend"]

    def _motivo_de_hierarquia_indisponivel(self) -> str:
        """Erro que diz o que fazer, e nao so que falhou.

        A mensagem generica anterior deixava o usuario sem hierarquia, sem
        codigo gerado e sem pista do motivo.
        """
        if self.platform is Platform.IOS:
            return (
                "Hierarquia indisponivel: o WebDriverAgent nao respondeu. "
                "Use 'Iniciar WebDriverAgent' na tela inicial."
            )
        detalhe = getattr(self, "_ultima_falha_de_hierarquia", None)
        if detalhe and "ocupa o UiAutomation" in detalhe:
            return f"Hierarquia indisponivel no Android. {detalhe}"
        base = (
            "Hierarquia indisponivel no Android. O 'uiautomator dump' nao devolveu nada "
            "e a sessao do Appium tambem nao abriu."
        )
        if detalhe and "UiAutomation not connected" in detalhe:
            return (
                base + " O servico UiAutomation do aparelho esta travado — isso costuma "
                "ser resolvido reiniciando o aparelho, ou reconectando o cabo USB."
            )
        return base + (f" Detalhe: {detalhe}" if detalhe else "")

    def hierarchy_element_at(self, params: dict[str, Any]) -> dict[str, Any]:
        with self._state_lock:
            xml = self.current_xml
        if not xml:
            raise InvalidInputError("Nenhuma hierarquia carregada. Chame hierarchy.dump antes.")
        x = validate_coordinate(params.get("x"), "x")
        y = validate_coordinate(params.get("y"), "y")
        element = UIHierarchyParser.find_element_at(xml, x, y)
        return {"element": element.to_dict() if element else None}

    def input_tap(self, params: dict[str, Any]) -> dict[str, Any]:
        sessao = self._require_session()
        x = validate_coordinate(params.get("x"), "x")
        y = validate_coordinate(params.get("y"), "y")
        ok = self.ios.tap(x, y) if sessao.platform is Platform.IOS else self.adb.tap(sessao.device_id, x, y)
        return {"ok": bool(ok)}

    def input_text(self, params: dict[str, Any]) -> dict[str, Any]:
        sessao = self._require_session()
        device = sessao.device_id
        text = params.get("text", "")
        if sessao.platform is Platform.IOS:
            raise InvalidInputError("Digitacao via WDA ainda nao exposta nesta versao.")

        # A fronteira valida a propria entrada, como ja faz com coordenada.
        # Sem isto, o adapter recusava o texto internamente e devolvia False, e
        # a interface recebia {"ok": false} sem motivo: o usuario via "digitei e
        # nao aconteceu nada". Aqui a recusa vira erro tipado com explicacao.
        build_adb_input_text_args(text)
        return {"ok": bool(self.adb.type_text(device, text))}

    # -------------------------------------------------------------- streaming

    def _mjpeg_url(self) -> str:
        """`http://<host do WDA>:<porta MJPEG>/`."""
        from urllib.parse import urlsplit

        partes = urlsplit(settings.wda_url)
        host = partes.hostname or "localhost"
        return f"http://{host}:{settings.wda_mjpeg_port}/"

    def _start_mjpeg_if_available(self, sessao: _Sessao, max_width: int, quality: int) -> MJPEGReader | None:
        """No iOS, tenta o MJPEG do WDA; sem resposta em 2 s, fica o simctl.

        Antes de ler, pede ao WDA quadros reduzidos para caberem no `max_width`
        (o espelho pede 900 e o simulador entrega mais de 1100 de largura):
        so assim o JPEG e repassado sem reencodar. Melhor esforco.
        """
        if sessao.platform is not Platform.IOS:
            return None
        largura = None
        try:
            largura = self.ios.take_screenshot(sessao.device_id).size[0]
        except Exception:
            largura = None
        if largura and max_width and largura > max_width:
            self.ios.set_mjpeg_scaling(int(100 * max_width / largura), quality)
        reader = MJPEGReader(self._mjpeg_url(), connect_timeout=2.0)
        if not reader.start():
            return None
        logger.info("Espelho iOS pelo MJPEG do WebDriverAgent em %s", reader.url)
        return reader

    def stream_start(self, params: dict[str, Any]) -> dict[str, Any]:
        self.stream_stop({})
        fps = validate_number(params.get("fps") or settings.stream_fps, "fps", minimum=0.1, maximum=120)
        max_width = validate_integer(params.get("max_width") or STREAM_MAX_WIDTH, "max_width", minimum=16, maximum=16384)
        fmt = str(params.get("format") or settings.stream_format).lower()
        if fmt not in ("jpeg", "png"):
            raise InvalidInputError(f"Formato de quadro invalido: {fmt!r}")
        quality = validate_integer(params.get("quality") or settings.stream_quality, "quality", minimum=10, maximum=95)
        # Retrato da sessao usado na ultima captura. Captura e emissao rodam em
        # sequencia na mesma thread do espelho, entao uma variavel basta.
        retrato: list[_Sessao] = []
        self._mjpeg = self._start_mjpeg_if_available(self._require_session(), max_width, quality)
        ultimo_seq = [0]

        def capturar():
            sessao = self._require_session()
            retrato[:] = [sessao]
            reader = self._mjpeg
            if reader is not None and sessao.platform is Platform.IOS:
                if not reader.is_running():
                    # O fluxo caiu (WDA reiniciado): volta ao simctl ate o
                    # proximo stream.start. Troca atomica e fecha o socket.
                    with self._state_lock:
                        if self._mjpeg is reader:
                            self._mjpeg = None
                    reader.stop()
                    logger.info("MJPEG do WDA caiu; espelho iOS volta ao simctl.")
                    return self._capture_image(sessao)
                quadro = reader.latest()
                if quadro is None or quadro[1] == ultimo_seq[0]:
                    return None
                data, ultimo_seq[0] = quadro
                image = Image.open(io.BytesIO(data))
                image.load()
                image.info["mobaile_jpeg"] = data
                return image
            return self._capture_image(sessao)

        def on_frame(image) -> None:
            try:
                sessao = retrato[0]
                # Quadro de um aparelho que deixou de ser o alvo nao sai: o
                # front o desenharia sob o aparelho novo.
                if sessao.epoch != self._sessao().epoch:
                    return
                payload = self._encode_frame(image, max_width, fmt, quality)
                payload["device_id"] = sessao.device_id
                # As metricas vao junto com o quadro de proposito.
                #
                # Antes o front chamava `stream.stats` a cada quadro recebido
                # para atualizar fps e latencia. Isso e uma ida e volta completa
                # por quadro, e enquanto ela nao volta o laco de notificacoes do
                # cliente fica parado, empilhando os quadros seguintes. Custa
                # zero mandar dois numeros junto com o que ja esta indo.
                stream = self._stream
                if stream is not None:
                    payload["fps"] = round(stream.stats.effective_fps, 2)
                    payload["capture_ms"] = round(stream.stats.last_capture_ms, 1)
                    payload["skipped"] = stream.stats.frames_skipped
                self.notify("stream.frame", payload)
            except Exception:
                logger.exception("Falha ao serializar quadro.")

        self._stream = RealTimeStreamEngine(
            get_frame_fn=capturar,
            on_frame_callback=on_frame,
            on_screen_settled_callback=lambda: self.notify("stream.settled", {}),
            fps=fps,
        )
        self._stream.start()
        return {
            "started": True, "fps": fps, "max_width": max_width, "format": fmt, "quality": quality,
            "source": "wda_mjpeg" if self._mjpeg is not None else "capture",
        }

    def stream_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        # Primeiro o espelho, depois o leitor MJPEG: na ordem inversa, enquanto
        # o leitor fechava, a thread do espelho via `_mjpeg` nulo e caia no
        # simctl por alguns quadros.
        if self._stream:
            self._stream.stop()
        with self._state_lock:
            reader, self._mjpeg = self._mjpeg, None
        if reader is not None:
            reader.stop()
        if self._stream:
            self._stream.stop()
            self._stream = None
        return {"stopped": True}

    def stream_stats(self, _params: dict[str, Any]) -> dict[str, Any]:
        if not self._stream:
            return {"running": False}
        stats = self._stream.stats
        return {
            "running": True,
            "frames_captured": stats.frames_captured,
            "frames_emitted": stats.frames_emitted,
            "frames_skipped": stats.frames_skipped,
            "skip_ratio": round(stats.skip_ratio, 3),
            "effective_fps": round(stats.effective_fps, 2),
            "last_capture_ms": round(stats.last_capture_ms, 1),
        }

    # ----------------------------------------------------------------- scrcpy

    def scrcpy_start(self, params: dict[str, Any]) -> dict[str, Any]:
        """Inicia espelhamento nativo a 60 FPS via scrcpy."""
        if not self.scrcpy.is_available():
            raise EngineError("Binário do scrcpy não encontrado. Instale com 'brew install scrcpy'.")

        device = self._require_device()
        fps = validate_integer(params.get("fps") or 60, "fps", minimum=1, maximum=240)
        max_size = validate_integer(params.get("max_size") or 1080, "max_size", minimum=16, maximum=16384)
        always_on_top = bool(params.get("always_on_top", True))
        title = str(params.get("title") or f"Mo baile — {device}")

        ok = self.scrcpy.start_mirror(
            device_id=device,
            title=title,
            max_fps=fps,
            max_size=max_size,
            always_on_top=always_on_top,
        )
        return {
            "started": ok,
            "running": self.scrcpy.is_running(),
            "device_id": device,
        }

    def scrcpy_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.scrcpy.stop_mirror()
        return {"stopped": True, "running": False}

    def scrcpy_status(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {
            "available": self.scrcpy.is_available(),
            "running": self.scrcpy.is_running(),
        }

    # ------------------------------------------------------------------ proxy

    def _ensure_proxy_notify(self) -> None:
        # Uma vez so: registrar a cada start duplicava cada evento no front.
        if not getattr(self, "_proxy_notify_on", False):
            self.proxy.add_event_callback(lambda event: self.notify("proxy.event", event.to_dict()))
            self._proxy_notify_on = True

    def _teardown_proxy_device(self, serial: str, port: int, only_if_pending: bool = False) -> bool:
        """Desfaz o proxy do aparelho. Se nao confirmar, fica pendente.

        Serializado: o adapter guarda o valor original uma vez so, e um segundo
        desmonte logo apos o primeiro apagaria o que ele restaurou. Com
        `only_if_pending`, a chamada e uma retentativa e so roda se o serial
        ainda estiver pendente e nao tiver sido reconfigurado por um
        `proxy.start` nesse meio tempo.
        """
        with self._proxy_teardown_lock:
            if only_if_pending:
                with self._state_lock:
                    pendente = serial in self._proxy_pending
                    reconfigurado = bool(self._proxy_device and self._proxy_device[0] == serial)
                if not pendente or reconfigurado:
                    return True
            try:
                ok = bool(self.adb.teardown_reverse_proxy(serial, port))
            except Exception:
                logger.exception("Falha ao desfazer o proxy no aparelho %s.", serial)
                ok = False
            with self._state_lock:
                if ok:
                    self._proxy_pending.pop(serial, None)
                else:
                    self._proxy_pending[serial] = port
            return ok

    def _retry_pending_proxy(self, serial: str) -> None:
        """Nova tentativa, em segundo plano, do desmonte pendente de `serial`."""
        with self._state_lock:
            port = self._proxy_pending.get(serial)
            if port is None or serial in self._proxy_retrying or self._shutdown_done:
                return
            self._proxy_retrying.add(serial)

        def tentar() -> None:
            try:
                self._teardown_proxy_device(serial, port, only_if_pending=True)
            finally:
                with self._state_lock:
                    self._proxy_retrying.discard(serial)

        thread = threading.Thread(target=tentar, daemon=True, name="mobaile-proxy-retry")
        with self._state_lock:
            self._proxy_retry_threads = [t for t in self._proxy_retry_threads if t.is_alive()]
            self._proxy_retry_threads.append(thread)
        thread.start()

    def _on_targets_listed(self, platform: str, ids: list[str]) -> None:
        """Retenta o desmonte pendente quando o aparelho volta a aparecer.

        So na transicao ausente -> presente: retentar a cada varredura num
        aparelho que recusa o `settings put` geraria seis comandos adb e um
        aviso por intervalo, sem fim. Com a sessao em iOS o vigia lista
        simuladores; se ha pendencia Android, o adb e consultado aqui, senao
        o aparelho que volta nunca seria visto.
        """
        with self._state_lock:
            pendentes = set(self._proxy_pending)
        if platform != "android":
            if not pendentes:
                return
            try:
                ids = [serial for serial, state in self.adb.list_devices() if state == "device"]
            except (EngineError, OSError) as exc:
                logger.debug("Sem listagem Android para retentar o proxy: %s", exc)
                return
        presentes = set(ids)
        with self._state_lock:
            vistos = self._proxy_seen if self._proxy_seen is not None else set()
            apareceram = [serial for serial in pendentes if serial in presentes and serial not in vistos]
            self._proxy_seen = presentes
        for serial in apareceram:
            self._retry_pending_proxy(serial)

    def _join_proxy_retries(self, timeout: float = 5.0) -> None:
        """Espera as retentativas em voo antes do desmonte final do encerramento."""
        with self._state_lock:
            threads = list(self._proxy_retry_threads)
        prazo = time.monotonic() + timeout
        for thread in threads:
            restante = prazo - time.monotonic()
            if restante <= 0:
                break
            thread.join(timeout=restante)

    def _release_proxy_device(self, fallback: str | None) -> None:
        """Desfaz o proxy do aparelho em que ele foi ligado.

        Sem registro num motor que nunca configurou aparelho (o anterior caiu),
        limpa o `fallback`, que e o aparelho Android da sessao: e o que a
        recuperacao do front espera de um `proxy.stop`. Se este motor ja
        desfez o que configurou, nao mexe em mais nenhum aparelho.
        """
        with self._state_lock:
            registro, self._proxy_device = self._proxy_device, None
            ja_configurou = self._proxy_configured_once
        if registro:
            self._teardown_proxy_device(*registro)
        elif fallback and not ja_configurou:
            self._teardown_proxy_device(fallback, self.proxy.port)

    def proxy_start(self, params: dict[str, Any]) -> dict[str, Any]:
        self._ensure_proxy_notify()
        started = self.proxy.start()
        configured = False
        sessao = self._sessao()
        if started and params.get("configure_device") and sessao.platform is Platform.ANDROID and sessao.device_id:
            with self._state_lock:
                anterior = self._proxy_device
            if anterior and anterior[0] != sessao.device_id:
                self._release_proxy_device(None)
            configured = self.adb.setup_reverse_proxy(sessao.device_id, self.proxy.port)
            if configured:
                with self._state_lock:
                    self._proxy_device = (sessao.device_id, self.proxy.port)
                    self._proxy_configured_once = True
                    # A configuracao nova substitui o desmonte que estava pendente.
                    self._proxy_pending.pop(sessao.device_id, None)
        return {"running": self.proxy.is_running(), "started": started, "device_configured": configured}

    def proxy_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        sessao = self._sessao()
        self._release_proxy_device(sessao.device_id if sessao.platform is Platform.ANDROID else None)
        self.proxy.stop()
        return {"running": self.proxy.is_running()}

    def netlog_start(self, params: dict[str, Any]) -> dict[str, Any]:
        """Trafego HTTPS de app em debug, sem proxy, pela plataforma da sessao.

        Android: o log do `HttpLoggingInterceptor` do OkHttp, lido do logcat do
        aparelho da sessao (ou de `device_id`). iOS: o log `CFNETWORK_DIAGNOSTICS`
        do iPhone por cabo; `udid` opcional, sem ele vale o primeiro confiado.
        """
        self._ensure_proxy_notify()
        sessao = self._sessao()
        if sessao.platform is Platform.ANDROID:
            serial = params.get("device_id") or sessao.device_id
            if not serial:
                raise DeviceNotFoundError("Selecione um aparelho Android para ler o tráfego do app em debug.")
            self.android_netlog.start(validate_device_id(serial))
            return {"running": self.android_netlog.is_running(), "device_id": self.android_netlog.device_id,
                    "raw_log": None, "source": "okhttp_logcat"}
        udid = params.get("udid") if isinstance(params, dict) else None
        if udid:
            udid = validate_device_id(udid)
        else:
            if not ios_device_log.is_available():
                raise DeviceNotFoundError(
                    "Para ler o trafego do iPhone por cabo, instale o pymobiledevice3.",
                    detail=ios_device_log.INSTALL_HINT,
                )
            devices = ios_device_log.list_devices()
            if not devices:
                raise DeviceNotFoundError("Nenhum iPhone conectado por cabo.")
            usable = [d for d in devices if not d.get("problem")]
            if not usable:
                raise DeviceNotReadyError(devices[0]["problem"])
            udid = usable[0]["udid"]
        self.ios_netlog.start(udid)
        try:
            raw_log: str | None = str(raw_log_path())
        except OSError:
            raw_log = None  # pasta dos logs recusada: os blocos brutos nao sao gravados
        return {"running": self.ios_netlog.is_running(), "device_id": udid, "raw_log": raw_log,
                "source": "cfnetwork"}

    def netlog_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.ios_netlog.stop()
        self.android_netlog.stop()
        return {"running": self.ios_netlog.is_running() or self.android_netlog.is_running()}

    def proxy_events(self, params: dict[str, Any]) -> dict[str, Any]:
        limit = validate_integer(params.get("limit") or 200, "limit", minimum=1, maximum=1_000_000)
        events = self.proxy.events_history[-limit:]
        return {"events": [event.to_dict() for event in events], "total": len(self.proxy.events_history)}

    def proxy_clear(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.proxy.clear_history()
        return {"cleared": True}

    # Janela sem trafego que ja conta como "nada chega".
    _DIAGNOSE_QUIET_S = 30.0

    def proxy_diagnose(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Por que nao vejo trafego? Causas prováveis, da mais a menos provável.

        Cada causa so entra quando ha evidencia para ela: proxy parado, aparelho
        sem o proxy aplicado, nenhuma conexao chegando (app que ignora o proxy do
        sistema), so tuneis CONNECT (HTTPS sem MITM, ADR 0004), tuneis falhando
        (rede do Mac), sessao iOS com proxy, ou "App em Debug" ligado sem eventos.
        """
        sessao = self._sessao()
        agora = time.time()
        eventos = self.proxy.events_history
        running = self.proxy.is_running()
        android = sessao.platform is Platform.ANDROID
        netlog_running = bool(self.android_netlog.is_running() or self.ios_netlog.is_running())
        device_configured: bool | None = None
        if android and sessao.device_id and running:
            device_configured = bool(self.adb.is_proxy_configured(sessao.device_id))

        requests_total = sum(1 for e in eventos if not e.is_tunnel)
        tunnels = [e for e in eventos if e.is_tunnel]
        # Tunel com `error` e o proxy que nao alcancou o servidor (DNS, rede):
        # o CONNECT e repassado sem abrir o TLS (ADR 0004), entao pinning nao
        # derruba o tunel e nao se le daqui.
        tunnels_failed = sum(1 for e in tunnels if e.error)
        tunnels_active = int(getattr(self.proxy, "active_tunnels", 0) or 0)
        last_age = (agora - max(e.timestamp for e in eventos)) if eventos else None
        quiet = last_age is None or last_age > self._DIAGNOSE_QUIET_S
        porta = self.proxy.port

        causes: list[dict[str, str]] = []

        def causa(code: str, title: str, detail: str, fix: str) -> None:
            causes.append({"code": code, "title": title, "detail": detail, "fix": fix})

        if not running and not netlog_running:
            causa(
                "proxy_stopped", "O proxy está desligado",
                "Nenhuma captura ligada: nem o proxy nem o App em Debug.",
                "Clique em Configurar Proxy. No iOS, ou em app que ignora o proxy, use o App em Debug.",
            )
        if running and not android:
            causa(
                "ios_no_proxy_support", "O proxy só configura aparelhos Android",
                "A sessão está no iOS: o simulador não é apontado para o proxy automaticamente.",
                "No iOS, leia o tráfego do app em debug pelo cabo (CFNETWORK_DIAGNOSTICS=3 no scheme) com o botão iPhone em Debug.",
            )
        if device_configured is False:
            causa(
                "proxy_not_on_device", "O aparelho não está apontando para o proxy",
                "settings get global http_proxy não devolveu um proxy (ou o adb não respondeu à consulta).",
                "Clique em Configurar Proxy de novo. Se o aparelho recusar, rode: "
                f"adb shell settings put global http_proxy 127.0.0.1:{porta}",
            )
        if (running and android and device_configured is True and quiet
                and not tunnels and tunnels_active == 0 and requests_total == 0):
            causa(
                "no_connections", "Nenhuma conexão chegou ao proxy",
                f"O aparelho aponta para o proxy, mas nenhuma conexão foi aberta nos últimos {int(self._DIAGNOSE_QUIET_S)} s.",
                "O app pode ignorar o proxy do sistema (Flutter/Dart, OkHttp com proxy próprio, WebSocket, gRPC). "
                "Use o App em Debug (log do OkHttp) ou confirme no app que ele respeita o proxy do Android.",
            )
        if len(tunnels) >= 3 and requests_total == 0 and tunnels_failed / len(tunnels) >= 0.8:
            erros = sorted({e.error for e in tunnels if e.error})
            causa(
                "tunnels_failing", "O proxy não está alcançando os servidores",
                f"{tunnels_failed} de {len(tunnels)} túneis CONNECT falharam ao conectar ({', '.join(erros)}).",
                "O Mac não resolve ou não alcança o host: confira DNS, VPN e rede do Mac. "
                "Pinning não aparece aqui: o proxy repassa o TLS sem abrir (ADR 0004).",
            )
        elif tunnels and requests_total == 0:
            causa(
                "only_tunnels", "Só túneis HTTPS, sem conteúdo",
                f"{len(tunnels)} túneis CONNECT e nenhuma requisição decodificada.",
                "O proxy não abre HTTPS (não há MITM, ADR 0004): você vê host e tamanho, não o conteúdo. "
                "Para ver o conteúdo, use o App em Debug.",
            )
        if netlog_running and quiet:
            causa(
                "netlog_running_no_events", "App em Debug ligado, mas sem eventos",
                f"A leitura do log está ativa e nada chegou nos últimos {int(self._DIAGNOSE_QUIET_S)} s.",
                "Android: o build de debug precisa do HttpLoggingInterceptor do OkHttp (nível BASIC ou mais). "
                "iOS: o app precisa rodar com CFNETWORK_DIAGNOSTICS=3 no scheme.",
            )

        return {
            "checked_at": agora,
            "platform": sessao.platform.value,
            "proxy_running": running,
            "device_configured": device_configured,
            "netlog_running": netlog_running,
            "requests_total": requests_total,
            "tunnels_total": len(tunnels),
            "tunnels_failed": tunnels_failed,
            "tunnels_active": tunnels_active,
            "last_event_age_s": round(last_age, 1) if last_age is not None else None,
            "causes": causes,
        }

    # -------------------------------------------------------------- analytics

    def analytics_start(self, params: dict[str, Any]) -> dict[str, Any]:
        package = params.get("package") if isinstance(params, dict) else None
        sessao = self._sessao()
        if sessao.platform is Platform.IOS:
            udid = self._analytics_ios_device(params, sessao)
            if udid:
                ok = self.analytics.start(platform="ios", device_id=udid, ios_physical=True)
                return {"running": ok, "source": "ios_device", "device_id": udid}
        ok = self.analytics.start(platform=sessao.platform.value, device_id=sessao.device_id, package_name=package)
        return {"running": ok, "source": self.analytics.active_source, "device_id": sessao.device_id}

    def _analytics_ios_device(self, params: dict[str, Any], sessao: _Sessao) -> str | None:
        """UDID do iPhone fisico a escutar, ou `None` para usar o simulador.

        `ios_source`: "simulator", um UDID, ou "auto" (padrao). No automatico o
        simulador da sessao vence; sem simulador, vale o primeiro iPhone por
        cabo. O tagueamento nao depende do espelho, entao o iPhone fisico serve
        aqui mesmo sem ser o alvo da sessao.
        """
        source = str(params.get("ios_source") or "auto")
        if source == "simulator":
            return None
        if source != "auto":
            return validate_device_id(source)
        if sessao.device_id:
            return None
        if not ios_device_log.is_available():
            raise DeviceNotFoundError(
                "Nenhum simulador ligado. Para escutar um iPhone por cabo, instale o pymobiledevice3.",
                detail=ios_device_log.INSTALL_HINT,
            )
        devices = ios_device_log.list_devices()
        if not devices:
            raise DeviceNotFoundError("Nenhum simulador ligado nem iPhone conectado por cabo.")
        usable = [d for d in devices if not d.get("problem")]
        if not usable:
            raise DeviceNotReadyError(devices[0]["problem"])
        return usable[0]["udid"]

    def analytics_ios_devices(self, _params: dict[str, Any]) -> dict[str, Any]:
        """iPhones fisicos que a escuta de tagueamento pode usar."""
        if not ios_device_log.is_available():
            return {"available": False, "devices": [], "hint": ios_device_log.INSTALL_HINT}
        return {"available": True, "devices": ios_device_log.list_devices()}

    def analytics_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.analytics.stop()
        return {"running": self.analytics.is_running()}

    def analytics_events(self, params: dict[str, Any]) -> dict[str, Any]:
        limit = validate_integer(params.get("limit") or 200, "limit", minimum=1, maximum=1_000_000)
        events = list(self.analytics.events_history)[-limit:]
        return {"events": [event.to_dict() for event in events]}

    def analytics_clear(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.analytics.clear_history()
        return {"cleared": True}

    # ---------------------------------------------------------------- codegen

    def codegen_record(self, params: dict[str, Any]) -> dict[str, Any]:
        # Arvore e plataforma lidas juntas: resolver o toque na arvore de um
        # aparelho e sintetizar o elemento com a classe do outro geraria codigo
        # que nao roda em nenhum dos dois.
        with self._state_lock:
            xml, platform = self.current_xml, self.platform
        if not xml:
            raise InvalidInputError("Nenhuma hierarquia carregada. Chame hierarchy.dump antes.")
        x = validate_coordinate(params.get("x"), "x")
        y = validate_coordinate(params.get("y"), "y")
        element = UIHierarchyParser.find_element_at(xml, x, y)
        sintetico = element is None
        if sintetico:
            element = self._elemento_por_posicao(x, y, platform)
        strategy_raw = str(params.get("strategy") or settings.default_strategy).lower()
        if sintetico and strategy_raw == "auto":
            # O `pos_x_y` do elemento sintetico nao existe na tela: um xpath com
            # ele venceria a coordenada no ranking e nunca casaria na reproducao.
            strategy_raw = "position"

        # "auto" deixa o motor escolher pelo que e mais robusto e unico nesta
        # tela, em vez de aplicar uma estrategia fixa a todos os elementos.
        alternativas: list[dict] = []
        valor_escolhido: str | None = None
        if strategy_raw == "auto":
            na_tela = UIHierarchyParser.parse_xml(xml)
            alternativas = self.codegen.rank_locators(element, na_tela)
            escolhido = alternativas[0]["strategy"]
            # O passo grava o valor do candidato escolhido. Reconstruir pela
            # estrategia trocava "texto unico" por "resource-id repetido".
            valor_escolhido = alternativas[0]["value"]
            strategy_raw = {"accessibility_id": "id", "text": "xpath"}.get(escolhido, escolhido)

        try:
            strategy = LocatorStrategy(strategy_raw)
        except ValueError as exc:
            raise InvalidInputError(f"Estrategia invalida: {strategy_raw!r}") from exc
        var_name, object_code, action_code = self.codegen.generate_entry(
            element, strategy=strategy, click_coord=(x, y), locator_value=valor_escolhido
        )
        passos = self.codegen.get_steps()
        return {
            "var_name": var_name,
            "object_code": object_code,
            "action_code": action_code,
            "element": element.to_dict(),
            "step_count": len(passos),
            "step_num": passos[-1].step_num if passos else None,
            "recorded_at": passos[-1].recorded_at if passos else None,
            "strategy": strategy.value,
            # Vazio quando a estrategia foi imposta pela interface; preenchido
            # no modo "auto", para a tela poder mostrar o que foi descartado e
            # por que.
            "alternatives": alternativas,
        }

    @staticmethod
    def _elemento_por_posicao(x: int, y: int, platform: Platform) -> UIElement:
        """Elemento sintetico para clique em area sem no na arvore.

        Recusar a gravacao aqui parece rigor e na pratica trava o trabalho:
        area vazia, canvas de jogo e componente desenhado a mao nao aparecem na
        arvore de acessibilidade, e o passo por coordenada e exatamente o que
        resta. A interface Tk ja fazia isso; a regra estava so la, o que
        deixava o front nativo falhando em silencio no mesmo clique.
        """
        tag = "XCUIElementTypeOther" if platform is Platform.IOS else "android.view.View"
        return UIElement(
            tag=tag,
            class_name=tag,
            resource_id="",
            text=f"pos_{x}_{y}",
            content_desc="",
            clickable=True,
            bounds=(x, y, x, y),
            area=1,
            package="",
            platform=platform.value,
        )

    def codegen_save(self, params: dict[str, Any]) -> dict[str, Any]:
        """Grava os dois arquivos do Page Object em disco.

        A convencao de nome e de pasta e regra do produto, entao mora aqui: as
        duas interfaces precisam produzir o mesmo layout, e nao cada uma o seu.
        O conteudo vem da interface porque o editor e editavel — o que esta na
        tela e o que vale, inclusive ajuste feito a mao depois de gravar.
        """
        chave = str(params.get("key") or settings.page_objects_key)
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", chave):
            raise InvalidInputError(f"Chave invalida para nome de arquivo: {chave!r}")

        # So dentro da pasta de trabalho (SEC-5): o RPC nao escreve codigo em
        # pasta arbitraria, nem seguindo link simbolico para fora dela.
        raiz = pathlib.Path.home() / "Documents" / "Mo baile"
        destino = pathlib.Path(str(params.get("directory") or raiz)).expanduser()
        if not destino.is_absolute():
            destino = raiz / destino
        if not _dentro_de(destino, raiz):
            raise InvalidInputError(f"A pasta precisa ficar dentro de {raiz}.")
        acoes = str(params.get("actions_code") or "")
        locators = str(params.get("locators_code") or "")
        if not acoes.strip() and not locators.strip():
            raise InvalidInputError("Nada para salvar: os dois editores estao vazios.")

        escritos = []
        for subpasta, conteudo in (("pages", acoes), ("locators", locators)):
            pasta = destino / subpasta
            arquivo = pasta / f"{chave}.py"
            if not _dentro_de(arquivo, raiz):
                raise InvalidInputError(f"O arquivo precisa ficar dentro de {raiz}.")
            pasta.mkdir(parents=True, exist_ok=True)
            arquivo.write_text(conteudo, encoding="utf-8")
            escritos.append(str(arquivo))

        logger.info("Page Object gravado em %s", destino)
        self._remember("page_object", f"{chave}.py", "Page Object · Python/Appium", escritos[0])
        return {"saved": True, "paths": escritos, "directory": str(destino)}

    # ------------------------------------------------------- escuta passiva

    def passive_start(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Grava o que a pessoa faz direto no aparelho, sem passar pelo espelho.

        No Android le `/dev/input` pelo `getevent`. O digitizer costuma ter
        resolucao diferente da tela — neste Motorola vai a 4320x9600 para uma
        tela de 1080x2400, ou seja, 4x — e sem essa conversao todo toque sai na
        coordenada errada. Os limites vem do proprio aparelho.

        No iOS observa o clique do mouse sobre a janela do Simulator. Isso vale
        so para simulador: nao ha como observar toque em iPhone fisico.
        """
        # Import tardio: `input_events` carrega o Quartz (pyobjc), mais de
        # 100 ms que toda subida do motor pagava sem nunca ligar a escuta.
        from mobaile.adapters.input_events import AndroidPassiveListener, IOSPassiveListener

        if self._passive is not None:
            raise InvalidInputError("A escuta passiva ja esta ligada.")

        sessao = self._require_session()
        device = sessao.device_id

        if sessao.platform is Platform.IOS:
            largura, altura = self._tamanho_logico_ios()
            ouvinte = IOSPassiveListener(
                on_tap_callback=self._on_passive_tap,
                ios_logical_size=(largura, altura),
            )
        else:
            largura, altura = self.adb.get_screen_size(device)
            ouvinte = AndroidPassiveListener(
                adb_path=self.adb.adb_path,
                device_id=device,
                on_tap_callback=self._on_passive_tap,
                screen_size=(largura, altura),
            )
            # Pré-aquece a hierarquia se estiver vazia para o primeiro toque não falhar
            with self._state_lock:
                carregada = bool(self.current_xml)
            if not carregada:
                try:
                    xml = self._android_hierarchy(device)
                    if xml:
                        self._store_hierarchy(xml, sessao.epoch)
                except RequestCancelledError:
                    raise
                except Exception:
                    logger.debug("Falha ao pré-aquecer hierarquia no passive_start.", exc_info=True)

        # O front que ja desistiu nao pode ficar com uma escuta ligada que ele
        # acha que falhou.
        self._check_cancelled()
        ouvinte.start()
        # Um `passive.start` lento pode terminar depois que o encerramento
        # desistiu de esperar a fila. Decidido sob o mesmo lock que o
        # `shutdown()` usa: ou ele ve este ouvinte e o desliga, ou este ve o
        # encerramento e desliga sozinho. Sem isso o `adb getevent` ficava orfao.
        with self._state_lock:
            encerrando = self._shutdown_done
            if not encerrando:
                self._passive = ouvinte
        if encerrando:
            ouvinte.stop()
            raise EngineError("O motor esta encerrando; a escuta passiva nao foi ligada.")
        logger.info("Escuta passiva ligada para %s (%sx%s)", device, largura, altura)
        return {"listening": True, "platform": sessao.platform.value, "screen": [largura, altura]}

    def _tamanho_logico_ios(self) -> tuple[int, int]:
        """Tamanho da tela do iOS em pontos, que e o espaco do WDA.

        Nao serve usar `screen.size` aqui: ele mede a captura, em pixels. Medido
        num iPhone 16e, a captura da 1170x2532 e o WDA reporta 390x844 — fator
        3. Gravar com o valor errado poe todo passo a tres vezes a distancia.

        A verdade esta na raiz da arvore do proprio WDA.
        """
        with self._state_lock:
            xml = self.current_xml
        xml = xml or self.ios.get_ui_hierarchy()
        if xml:
            elementos = UIHierarchyParser.parse_xml(xml)
            if elementos:
                _, _, direita, base = elementos[0].bounds
                if direita > 0 and base > 0:
                    return int(direita), int(base)
        raise EngineError(
            "Nao foi possivel medir a tela do simulador. Carregue a hierarquia antes de "
            "ligar a escuta passiva."
        )

    def passive_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Idempotente."""
        if self._passive is None:
            return {"listening": False}
        try:
            self._passive.stop()
        finally:
            self._passive = None
        return {"listening": False}

    def passive_status(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {"listening": self._passive is not None}

    def _teclado_aberto(self) -> bool:
        """O teclado do sistema esta na tela?

        Enquanto ele esta aberto, cada toque e uma tecla — nao um passo. Sem
        esta checagem, digitar "joao" numa busca gerava quatro passos de clique
        em coordenada de teclado, que e lixo que nao reexecuta.
        """
        sessao = self._sessao()
        if sessao.platform is not Platform.ANDROID:
            return False
        now = time.time()
        if self._keyboard_cache is not None:
            cache_time, is_open = self._keyboard_cache
            if now - cache_time < 0.4:
                return is_open
        try:
            _, saida, _ = self.adb._run_cmd(
                self.adb._device_args(sessao.device_id or "", "shell", "dumpsys", "input_method"),
                timeout=4,
            )
            is_open = b"mInputShown=true" in saida
            self._keyboard_cache = (now, is_open)
            return is_open
        except (InvalidInputError, ToolNotFoundError, subprocess.TimeoutExpired) as exc:
            # Um `dumpsys` acima do prazo (aparelho ocupado) nao pode derrubar a
            # escuta passiva: o toque so segue como passo, sem a checagem.
            logger.debug("Nao foi possivel checar o teclado: %s", exc)
            return False

    def _fechar_digitacao(self) -> None:
        """Le o que foi digitado e guarda no passo de entrada."""
        self._digitando = False
        campo = self._campo_digitado
        self._campo_digitado = None
        if not campo:
            return

        sessao = self._sessao()
        xml = self._fetch_hierarchy(sessao)
        if not xml:
            return
        self._store_hierarchy(xml, sessao.epoch)

        for elemento in UIHierarchyParser.parse_xml(xml):
            if elemento.resource_id == campo and elemento.text:
                if self.codegen.set_last_input_text(elemento.text):
                    self.notify("passive.text", {"field": campo, "text": elemento.text})
                return

    def _on_passive_tap(self, x: int, y: int) -> None:
        """Um toque no aparelho vira passo gravado.

        Resolve contra `current_xml`, que e a arvore de antes do toque — que e
        justamente a que descreve o que foi tocado. Fazer um dump aqui seria
        errado alem de lento: leria a tela seguinte, ja depois da navegacao.
        """
        try:
            if self._teclado_aberto():
                # Toque com teclado aberto e tecla, nao passo.
                self._digitando = True
                return
            if self._digitando:
                self._fechar_digitacao()

            with self._state_lock:
                carregada = bool(self.current_xml)
            if not carregada:
                # Tenta recuperar a hierarquia imediatamente se estiver vazia
                sessao = self._sessao()
                if sessao.device_id:
                    xml = self._fetch_hierarchy(sessao)
                    if xml:
                        self._store_hierarchy(xml, sessao.epoch)

            with self._state_lock:
                carregada = bool(self.current_xml)
            if not carregada:
                self.notify("passive.skipped", {"x": x, "y": y, "reason": "sem hierarquia carregada"})
                return
            resultado = self.codegen_record({"x": x, "y": y, "strategy": "auto"})
            if resultado["element"].get("resource_id"):
                self._campo_digitado = resultado["element"]["resource_id"]
            self.notify("passive.step", resultado)

            # Dispara atualização assíncrona da hierarquia da nova tela
            threading.Thread(target=self._async_prefetch_hierarchy, daemon=True, name="mobaile-prefetch").start()
        except EngineError as exc:
            logger.warning("Toque passivo em (%s,%s) nao virou passo: %s", x, y, exc)
            self.notify("passive.skipped", {"x": x, "y": y, "reason": str(exc)})
        except Exception as exc:
            # Rede final: roda na thread do `getevent`. Uma excecao solta aqui
            # encerrava a gravacao sem aviso, com a tela ainda em "Gravando".
            logger.exception("Erro inesperado no toque passivo em (%s,%s).", x, y)
            self.notify("passive.skipped", {"x": x, "y": y, "reason": f"erro inesperado: {exc}"})

    def _async_prefetch_hierarchy(self) -> None:
        """Pré-carrega a hierarquia da nova tela após um toque no aparelho.

        Aguarda o início da transição visual e roda o dump em segundo plano para
        que o XML da próxima tela já esteja pronto e em cache antes mesmo de a
        interface pedir, reduzindo a latência percebida para menos de 50ms.
        """
        time.sleep(0.35)
        try:
            sessao = self._sessao()
            if not sessao.device_id:
                return
            xml = self._fetch_hierarchy(sessao)
            # So avisa que a tela assentou se a arvore ainda e do alvo atual.
            if xml and self._store_hierarchy(xml, sessao.epoch):
                self.notify("stream.settled", {})
        except Exception:
            logger.debug("Falha na busca assíncrona de hierarquia pós-toque.", exc_info=True)

    # ------------------------------------------------------- execucao de fluxo

    def flow_run(self, params: dict[str, Any]) -> dict[str, Any]:
        """Executa os passos gravados no aparelho.

        No Android, por padrao, cada passo e procurado pelo localizador gravado,
        com as esperas do Maestro (`runner: "locator"`): o toque segue o elemento
        quando o layout muda. `runner: "coordinates"` (ou `MOBAILE_FLOW_RUNNER`)
        roda o script de coordenadas de antes, o caminho de aparelho sem arvore
        nenhuma; o iOS segue nele ate o `/source` do WDA ser medido no runner. O
        andamento sai por `flow.log` e `flow.step`, igual nos dois.
        """
        passos = self.codegen.get_steps()
        if not passos:
            raise InvalidInputError("Nenhum passo gravado para executar.")

        sessao = self._require_session()
        device = sessao.device_id
        runner = str(params.get("runner") or settings.flow_runner).lower()
        if runner not in ("locator", "coordinates"):
            raise InvalidInputError(f"runner invalido: {runner!r}. Use locator ou coordinates.")
        if sessao.platform is Platform.IOS:
            runner = "coordinates"
        flow = maestro_flow.flow_from_steps(passos) if runner == "locator" else None
        if flow is not None:
            self._conferir_leitura_do_flow(device or "")
        with self._state_lock:
            if self._shutdown_done:
                raise InvalidInputError("O motor esta encerrando.")
            if self._flow_running:
                raise InvalidInputError("Ja existe uma execucao em andamento.")
            self._flow_running = True
            self._flow_cancelled = False
            self._flow_thread = None

        def ao_sair(linha: str) -> None:
            self.notify("flow.log", {"line": linha})

        def ao_terminar(sucesso: bool, mensagem: str) -> None:
            self._notify_flow_finished(sucesso, mensagem, self._release_flow())

        try:
            ok, motivo = flows.verify_preconditions(
                platform=sessao.platform.value, device_id=device, adb_path=self.adb.adb_path
            )
            if not ok:
                raise EngineError(motivo)
            self._check_cancelled()
            if flow is not None:
                ler, backend = self._leitor_do_flow(device or "")
                execucao = maestro_flow.FlowThread(
                    flow, AndroidFlowDevice(self.adb, device or "", hierarchy=ler, backend=backend),
                    ao_sair, lambda sucesso, mensagem: ao_terminar(sucesso, mensagem),
                    on_step=self._notify_flow_step,
                )
                with self._state_lock:
                    if self._flow_cancelled or self._shutdown_done:
                        raise RequestCancelledError("Execucao cancelada antes de iniciar.")
                    self._flow_thread = execucao
                execucao.start()
                return {"running": True, "steps": len(passos), "runner": "locator"}
            script = flows.generate_hidden_runner_script(
                steps=passos,
                platform=sessao.platform.value,
                device_id=device,
                wda_url=settings.wda_url,
                adb_path=self.adb.adb_path,
            )
            self._check_cancelled()
            with self._state_lock:
                if self._flow_cancelled or self._shutdown_done:
                    raise RequestCancelledError("Execucao cancelada antes de iniciar.")
                self._flow_thread = flows.run_flow_in_background(
                    script, ao_sair, ao_terminar,
                    sensitive_texts=[p.input_text for p in passos if p.input_text],
                    on_step=self._notify_flow_step,
                )
        except Exception:
            with self._state_lock:
                self._flow_running = False
                self._flow_thread = None
            raise
        return {"running": True, "steps": len(passos), "runner": "coordinates", "script": script}

    def _release_flow(self) -> bool:
        """Solta a trava de execucao. Devolve se a execucao tinha sido cancelada."""
        with self._state_lock:
            self._flow_running = False
            self._flow_thread = None
            return self._flow_cancelled

    def _notify_flow_step(self, index: int, total: int) -> None:
        """Inicio de um passo de nivel superior; `index` comeca em 1."""
        self.notify("flow.step", {"index": index, "total": total})

    def _notify_flow_finished(self, success: bool, message: str, cancelled: bool) -> None:
        """Fim da execucao, igual para `flow.run` e `flow.maestro_run`.

        Parar nao e falhar: `cancelled` deixa o front mostrar a parada como
        parada. `success` continua falso numa execucao cancelada, para o front
        antigo, que nao le `cancelled`, nao contar como aprovada.
        """
        self.notify(
            "flow.finished",
            {"success": success and not cancelled, "message": message, "cancelled": cancelled},
        )

    def flow_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Pede a interrupcao. Idempotente.

        SIGTERM pede ao script que termine apos a acao atual, antes de iniciar
        outro passo. Tambem impede iniciar um processo ainda em preparacao.
        """
        with self._state_lock:
            if not self._flow_running:
                return {"running": False, "stopped": False}
            if self._flow_cancelled:
                return {"running": True, "stopped": True}
            self._flow_cancelled = True
            execution = self._flow_thread
        if execution is not None:
            execution.cancel()
        self.notify("flow.log", {"line": "Interrupcao pedida; encerrando apos o passo atual."})
        return {"running": True, "stopped": True}

    def flow_status(self, _params: dict[str, Any]) -> dict[str, Any]:
        with self._state_lock:
            return {"running": self._flow_running, "cancelled": self._flow_cancelled}

    # ------------------------------------------ flow declarativo (formato Maestro)

    @staticmethod
    def _ler_flow_maestro(params: dict[str, Any]) -> maestro_flow.Flow:
        env = params.get("env") or {}
        if not isinstance(env, dict):
            raise InvalidInputError("`env` precisa ser um mapa NOME: valor.")
        if params.get("yaml"):
            return maestro_flow.parse_flow(str(params["yaml"]), env=env)
        if params.get("path"):
            return maestro_flow.load_flow(str(params["path"]), env=env)
        raise InvalidInputError("Passe `yaml` (o texto do flow) ou `path` (um arquivo .yaml).")

    def flow_maestro_check(self, params: dict[str, Any]) -> dict[str, Any]:
        """Valida um flow no formato do Maestro sem tocar o aparelho."""
        return {"valid": True, **self._ler_flow_maestro(params).summary()}

    def flow_maestro_export(self, params: dict[str, Any]) -> dict[str, Any]:
        """Os passos gravados como flow do Maestro. Texto digitado vira `${VARIAVEL}`.

        Com `save: true`, grava em `~/Documents/Mo baile/flows/`, a mesma raiz
        do `codegen.save`, sem sobrescrever arquivo existente.
        """
        passos = self.codegen.get_steps()
        if not passos:
            raise InvalidInputError("Nenhum passo gravado para exportar.")
        nome = params.get("name")
        yaml_texto, variaveis = maestro_flow.export_steps(
            passos, app_id=params.get("app_id") or None, name=str(nome) if nome else None,
        )
        resultado: dict[str, Any] = {"yaml": yaml_texto, "variables": variaveis, "steps": len(passos)}
        if params.get("save"):
            raiz = pathlib.Path.home() / "Documents" / "Mo baile"
            pasta = raiz / "flows"
            base = re.sub(r"[^A-Za-z0-9_-]+", "_", str(nome or "flow")).strip("_")[:64] or "flow"
            pasta.mkdir(parents=True, exist_ok=True)
            contador = 1
            while True:
                arquivo = pasta / (f"{base}.yaml" if contador == 1 else f"{base}_{contador}.yaml")
                if not _dentro_de(arquivo, raiz):
                    raise InvalidInputError(f"O arquivo precisa ficar dentro de {raiz}.")
                # "x" cria ou falha: entre conferir e gravar, outra exportacao
                # nao consegue ocupar o mesmo nome e ter o arquivo sobrescrito.
                try:
                    with arquivo.open("x", encoding="utf-8") as saida:
                        saida.write(yaml_texto)
                    break
                except FileExistsError:
                    contador += 1
            resultado["path"] = str(arquivo)
            self._remember("maestro", arquivo.name, f"Flow do Maestro · {len(passos)} passos", str(arquivo))
        return resultado

    def flow_maestro_run(self, params: dict[str, Any]) -> dict[str, Any]:
        """Roda um flow do Maestro no alvo ativo, com as esperas do Maestro.

        Divide com `flow.run` a trava de execucao, `flow.stop` e as
        notificacoes `flow.log`/`flow.finished`: para a interface e o mesmo
        "fluxo rodando". Validacao vem antes da trava, para erro de YAML nao
        ocupar o aparelho.
        """
        flow = self._ler_flow_maestro(params)
        sessao = self._require_session()
        device_id = sessao.device_id or ""
        if sessao.platform is Platform.IOS:
            aparelho = IOSFlowDevice(self.ios, device_id)
        else:
            self._conferir_leitura_do_flow(device_id)
            ler, backend = self._leitor_do_flow(device_id)
            aparelho = AndroidFlowDevice(self.adb, device_id, hierarchy=ler, backend=backend)
        with self._state_lock:
            if self._shutdown_done:
                raise InvalidInputError("O motor esta encerrando.")
            if self._flow_running:
                raise InvalidInputError("Ja existe uma execucao em andamento.")
            self._flow_running = True
            self._flow_cancelled = False

        caminho_flow = str(params["path"]) if params.get("path") and not params.get("yaml") else None

        def ao_terminar(sucesso: bool, mensagem: str) -> None:
            cancelado = self._release_flow()
            self._notify_flow_finished(sucesso, mensagem, cancelado)
            if caminho_flow and not cancelado:
                estado = "passou" if sucesso else "falhou"
                self._remember("maestro", pathlib.Path(caminho_flow).name,
                               f"Flow do Maestro · última execução {estado}", caminho_flow)

        execucao = maestro_flow.FlowThread(
            flow, aparelho, lambda linha: self.notify("flow.log", {"line": linha}), ao_terminar,
            on_step=self._notify_flow_step,
        )
        with self._state_lock:
            self._flow_thread = execucao
            if self._flow_cancelled:
                # `flow.stop` chegou entre a trava e aqui: o flow nem comeca.
                execucao.cancel()
        execucao.start()
        return {"running": True, **flow.summary()}

    def codegen_steps(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {"steps": [step.to_dict() for step in self.codegen.get_steps()]}

    def codegen_reset(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.codegen.reset()
        return {"steps": 0}

    # ------------------------------------------------------------- relatorio

    def report_spec(self, params: dict[str, Any]) -> dict[str, Any]:
        """Le e valida a spec-modelo; devolve o resumo para a aba Relatorio."""
        return self.report.spec(params.get("path"))

    def report_audit(self, params: dict[str, Any]) -> dict[str, Any]:
        """Audita a spec contra um arquivo de log ou contra o que a escuta capturou.

        `source: "session"` usa o historico da escuta de Analytics deste motor:
        o mesmo conteudo que "Exportar JSON" gravaria, sem passar por arquivo.
        """
        source = params.get("source") or "session"
        platform = params.get("platform")
        if platform is not None and not isinstance(platform, str):
            raise InvalidInputError("platform precisa ser android ou ios.")
        log_path = None
        if source == "session":
            items = self.analytics.history_snapshot()
            if not items:
                raise InvalidInputError(
                    "Nenhum evento capturado nesta sessão. Inicie a escuta em Analytics "
                    "ou escolha um arquivo de log."
                )
        elif source == "file":
            items, log_path = self.report.read_log(params.get("log_path"))
            if not items:
                raise InvalidInputError(f"O log {log_path.name} não tem eventos do Firebase Analytics.")
        else:
            raise InvalidInputError(f"Origem do log desconhecida: {source!r}. Use session ou file.")
        resultado = self.report.audit(
            params.get("spec_path"), items, source=source, log_path=log_path, platform=platform,
            progress=self._progress,
        )
        resumo = resultado["summary"]
        divergencias = resumo["divergent"] + resumo["missing"]
        conformidade = f"{resumo['compliance_rate']:.1f}".replace(".", ",")
        self._ultimo_relatorio = (
            f"Relatório · {resultado['spec']['projeto']}",
            f"{divergencias} {'divergência' if divergencias == 1 else 'divergências'} · {conformidade}% conforme",
            resultado["spec"]["path"],
        )
        self._remember("report", *self._ultimo_relatorio)
        return resultado

    def report_export(self, params: dict[str, Any]) -> dict[str, Any]:
        """Grava board, HTML, Markdown e TSV do ultimo relatorio."""
        resultado = self.report.export(
            params.get("directory"), progress=self._progress, check_cancelled=self._check_cancelled,
        )
        if self._ultimo_relatorio:
            titulo, subtitulo, caminho = self._ultimo_relatorio
            self._remember("report", titulo, f"{subtitulo} · exportado em HTML", caminho)
        return resultado

    def report_import(self, params: dict[str, Any]) -> dict[str, Any]:
        """OCR dos prints dos cards do Figma: grava o rascunho da spec e a revisao."""
        projeto = params.get("projeto")
        if projeto is not None and not isinstance(projeto, str):
            raise InvalidInputError("projeto precisa ser texto.")
        platform = params.get("platform") or "android"
        if not isinstance(platform, str):
            raise InvalidInputError("platform precisa ser android ou ios.")
        return self.report.import_prints(
            params.get("prints_dir"), projeto=projeto, platform=platform, spec_path=params.get("spec_path"),
            progress=self._progress, check_cancelled=self._check_cancelled,
        )

    def report_card(self, params: dict[str, Any]) -> dict[str, Any]:
        """Um card da spec como está no JSON, para editar no app."""
        return self.report.card(params.get("spec_path"), params.get("card_index"))

    def report_card_update(self, params: dict[str, Any]) -> dict[str, Any]:
        """Grava os textos editados de um card na spec e devolve o resumo relido."""
        return self.report.update_card(params.get("spec_path"), params.get("card_index"), params.get("card"))

    # ------------------------------------------------------------------- loop

    def _parse(self, raw: str) -> tuple[_Request | None, dict[str, Any] | None]:
        """Valida uma linha. Devolve a requisicao pronta ou a resposta de erro.

        Separado da execucao para o laco concorrente e o `handle_message`
        sincrono validarem do mesmo jeito: os testes de contrato exercitam um
        e a producao roda o outro.
        """
        try:
            message = json.loads(raw)
        except json.JSONDecodeError as exc:
            return None, protocol.error(None, protocol.PARSE_ERROR, "JSON invalido.", str(exc))

        if not isinstance(message, dict) or message.get("jsonrpc") != protocol.JSONRPC_VERSION:
            return None, protocol.error(message.get("id") if isinstance(message, dict) else None,
                                        protocol.INVALID_REQUEST, "Envelope JSON-RPC 2.0 esperado.")

        request_id = message.get("id")
        # O id vira chave da tabela de pedidos em andamento, que e por onde o
        # cancelamento os acha. A especificacao so admite texto, numero ou nulo.
        if isinstance(request_id, bool) or not isinstance(request_id, (str, int, float, type(None))):
            return None, protocol.error(None, protocol.INVALID_REQUEST, "id deve ser texto, numero ou nulo.")

        method = message.get("method")
        if not isinstance(method, str):
            return None, protocol.error(request_id, protocol.INVALID_REQUEST, "method deve ser texto.")
        params = message.get("params", {})
        if not isinstance(params, dict):
            return None, protocol.error(request_id, protocol.INVALID_PARAMS, "params deve ser objeto.")

        token = params.get("progress_token")
        if token is not None and (isinstance(token, bool) or not isinstance(token, (str, int, float))):
            return None, protocol.error(request_id, protocol.INVALID_PARAMS, "progress_token deve ser texto ou numero.")

        if method == contract.CANCEL_REQUEST:
            return _Request(request_id, method, params, None), None

        handler = self.methods.get(method)
        if handler is None:
            return None, protocol.error(request_id, protocol.METHOD_NOT_FOUND, f"Metodo desconhecido: {method}")
        return _Request(request_id, method, params, handler, token), None

    def _execute(self, request: _Request) -> dict[str, Any] | None:
        """Roda o metodo nesta thread e monta a resposta."""
        anterior = self._current_request()
        self._local.request = request
        try:
            payload = request.handler(request.params)
        except RequestCancelledError as exc:
            return protocol.error(request.request_id, protocol.REQUEST_CANCELLED, exc.message, exc.to_dict())
        except EngineError as exc:
            return protocol.error(request.request_id, protocol.ENGINE_ERROR, exc.message, exc.to_dict())
        except Exception as exc:
            logger.exception("Erro interno em %s", request.method)
            return protocol.error(
                request.request_id, protocol.INTERNAL_ERROR, "Erro interno no motor.",
                {"exception": type(exc).__name__, "trace": traceback.format_exc(limit=3)},
            )
        finally:
            self._local.request = anterior

        # Sem id, e notificacao: o cliente nao espera resposta.
        return protocol.result(request.request_id, payload) if request.request_id is not None else None

    def handle_message(self, raw: str) -> dict[str, Any] | None:
        """Processa uma linha na hora, sem fila. Devolve a resposta ou `None`."""
        request, erro = self._parse(raw)
        if request is None:
            return erro
        if request.method == contract.CANCEL_REQUEST:
            self._cancel(request.params.get("id"))
            return None
        return self._execute(request)

    def _respond(self, request: _Request, response: dict[str, Any] | None) -> None:
        """Envia a resposta, a menos que o cancelamento ja tenha respondido."""
        if response is None:
            return
        if request.request_id is not None:
            with self._requests_lock:
                if request.answered:
                    return
                request.answered = True
                if self._in_flight.get(request.request_id) is request:
                    del self._in_flight[request.request_id]
        self.send(response)

    def _cancel(self, target_id: Any) -> None:
        """`$/cancelRequest`: responde erro na hora e descarta o que vier depois.

        Pedido ainda na fila sai dela e nunca roda. Pedido em execucao continua
        ate o proximo `_check_cancelled` ou ate o fim, e o resultado dele e
        jogado fora. Id desconhecido ou ja respondido e ignorado, como no LSP.
        """
        if isinstance(target_id, bool) or not isinstance(target_id, (str, int, float)):
            return
        with self._requests_lock:
            request = self._in_flight.pop(target_id, None)
            if request is None or request.answered:
                return
            request.answered = True
            request.cancelled.set()
        lane = self._lanes.get(contract.lane_of(request.method))
        na_fila = lane.remove(request) if lane else False
        logger.info("Requisicao %s (%s) cancelada %s.", target_id, request.method,
                    "na fila" if na_fila else "em execucao")
        erro = RequestCancelledError()
        self.send(protocol.error(target_id, protocol.REQUEST_CANCELLED, erro.message, erro.to_dict()))

    def _run_in_lane(self, request: _Request) -> None:
        # Depois do desmonte nada novo comeca: um `stream.start` ou `proxy.start`
        # que rodasse agora ligaria recurso que ninguem mais vai desligar.
        if request.cancelled.is_set() or self._shutdown_done:
            return
        try:
            self._respond(request, self._execute(request))
        except Exception:
            # Sem isto um stdout fechado mataria a thread da fila, e todo
            # pedido seguinte do dominio ficaria sem resposta para sempre.
            logger.exception("Falha ao responder %s", request.method)

    def _dispatch(self, raw: str) -> None:
        """Encaminha uma linha lida do stdin para a fila do seu dominio."""
        request, erro = self._parse(raw)
        if request is None:
            self.send(erro)
            return
        if request.method == contract.CANCEL_REQUEST:
            self._cancel(request.params.get("id"))
            return
        lane = self._lanes.get(contract.lane_of(request.method))
        if lane is None:
            self._respond(request, self._execute(request))
            return
        if request.request_id is not None:
            with self._requests_lock:
                self._in_flight[request.request_id] = request
        lane.put(request)

    def _start_lanes(self) -> None:
        self._lanes = {name: _Lane(name, self._run_in_lane) for name in contract.WORKER_LANES}
        for lane in self._lanes.values():
            lane.start()

    def _drain_lanes(self) -> None:
        """Deixa as filas terminarem o que ja tinham, com prazo curto."""
        prazo = time.monotonic() + LANE_DRAIN_TIMEOUT_S
        for lane in self._lanes.values():
            lane.close()
        for lane in self._lanes.values():
            if not lane.join(max(0.0, prazo - time.monotonic())):
                logger.warning("Fila %s ainda ocupada no encerramento; o motor segue sem ela.", lane.name)

    def shutdown(self) -> None:
        """Encerra tudo que segura recurso externo. Idempotente: roda uma vez so."""
        with self._state_lock:
            if self._shutdown_done:
                return
            self._shutdown_done = True
        self._running = False
        self.flow_stop({})
        self.stream_stop({})
        self.devices_watch_stop({})
        sessao = self._sessao()
        try:
            # Deixar o aparelho com proxy apontando para porta morta o deixaria
            # sem rede depois que o app fecha. Vale o aparelho em que o proxy
            # foi ligado, mesmo que a sessao tenha trocado de aparelho.
            fallback = None
            if sessao.platform is Platform.ANDROID and sessao.device_id and self.proxy.is_running():
                fallback = sessao.device_id
            self._release_proxy_device(fallback)
            # Ultima tentativa nos aparelhos cujo desmonte nao se confirmou,
            # depois que as retentativas em voo terminam: senao o mesmo serial
            # seria desmontado duas vezes, e a segunda apagaria o restaurado.
            self._join_proxy_retries()
            with self._state_lock:
                pendentes = list(self._proxy_pending.items())
            for serial, port in pendentes:
                self._teardown_proxy_device(serial, port, only_if_pending=True)
        except Exception:
            logger.exception("Falha ao desfazer a configuracao de proxy do dispositivo.")
        try:
            if self.recorder.is_recording:
                # Sem isto o MP4 fica sem indice final e nao abre em lugar
                # nenhum: o trabalho gravado seria perdido no fechamento.
                self.recorder.stop()
        except EngineError:
            logger.exception("Falha ao encerrar a gravacao de tela.")
        if self._passive is not None:
            self.passive_stop({})
        self.proxy.stop()
        self.ios_netlog.stop()
        self.android_netlog.stop()
        self.analytics.stop()
        self.scrcpy.stop_mirror()
        # Encerra apenas o servidor Appium que este processo iniciou. Um Appium
        # que ja estava no ar e do usuario, e derruba-lo quebraria a sessao dele.
        self.appium.stop_server()
        logger.info("Motor encerrado.")

    def request_stop(self) -> None:
        """Pede o fim do laco de leitura sem interromper nada no meio.

        Seguro dentro de tratador de sinal: so troca um booleano. O laco
        percebe em ate `STOP_POLL_S` e segue pelo caminho ordenado de sempre.
        """
        self._running = False

    @staticmethod
    def _read_lines(source, linhas: queue.Queue) -> None:
        """Le o stdin numa thread propria e entrega linha a linha.

        A leitura fica fora da thread principal para que nada precise
        interrompe-la: o SIGTERM so pede a parada, e a thread principal, que
        nunca fica presa num `read`, percebe e desmonta ate o fim.
        """
        try:
            for line in source:
                linhas.put(line)
        except (OSError, ValueError):
            logger.debug("Leitura do stdin terminou com erro.", exc_info=True)
        finally:
            linhas.put(None)

    def serve_forever(self, stream=None) -> None:
        """Le o stdin ate o fim, `engine.shutdown` ou SIGTERM, e encerra em ordem.

        As tres saidas passam pelo mesmo caminho: as filas terminam o que ja
        tinham dentro de `LANE_DRAIN_TIMEOUT_S`, e so entao `shutdown()` roda.
        Uma fila presa numa chamada lenta nao segura o fechamento.
        """
        source = stream or sys.stdin
        linhas: queue.Queue[str | None] = queue.Queue()
        threading.Thread(
            target=self._read_lines, args=(source, linhas), daemon=True, name="mobaile-stdin"
        ).start()
        self._start_lanes()
        try:
            while self._running:
                try:
                    line = linhas.get(timeout=STOP_POLL_S)
                except queue.Empty:
                    continue
                if line is None:
                    break
                line = line.strip()
                if line:
                    self._dispatch(line)
        finally:
            self._drain_lanes()
            self.shutdown()


LOG_FORMAT = "%(asctime)s %(levelname)s %(name)s: %(message)s"
LOG_FILE_NAME = "engine.log"
# Despejo do faulthandler (queda no C, travamento fatal). Arquivo proprio, e
# nao o `engine.log`: a rotacao fecha o descritor do log, e o faulthandler
# escreveria num numero de descritor que o sistema ja pode ter dado a outro
# arquivo.
FAULT_FILE_NAME = "engine-faults.log"
LOG_MAX_BYTES = 1024 * 1024
LOG_BACKUPS = 3

# O que `configure_logging` instalou, para reconfigurar sem duplicar.
_log_handlers: list[logging.Handler] = []
# Mantido aberto pela vida do processo: o faulthandler guarda so o numero do
# descritor e escreve nele no meio de uma queda, sem Python para reabrir nada.
_fault_file = None


def _open_private(path: pathlib.Path, *, truncate: bool = False):
    """Abre para acrescentar, so para o dono (0600), sem seguir symlink."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | (os.O_TRUNC if truncate else os.O_APPEND)
    fd = os.open(path, flags, 0o600)
    try:
        # Arquivo de versao anterior, ou criado sob outro umask, fica so com o dono.
        os.fchmod(fd, 0o600)
        return os.fdopen(fd, "w" if truncate else "a", encoding="utf-8")
    except OSError:
        os.close(fd)
        raise


class _PrivateRotatingFileHandler(logging.handlers.RotatingFileHandler):
    """`RotatingFileHandler` cujo arquivo, inclusive o recriado na rotacao, e 0600.

    O `open()` padrao obedece ao umask e deixaria o log legivel por todos.
    """

    def _open(self):
        return _open_private(pathlib.Path(self.baseFilename))


class _RedactingFilter(logging.Filter):
    """Passa a mensagem, os argumentos e o traceback por `redact_url`.

    Fica nos handlers, e nao num logger: filtro de logger nao ve o que sobe
    dos loggers filhos. A mensagem ja sai formatada e sem argumentos, para
    nenhum handler voltar a montar o texto original.
    """

    def filter(self, record: logging.LogRecord) -> bool:
        try:
            mensagem = record.getMessage()
        except Exception:
            # Argumento que nao casa com o formato: o `handleError` do logging
            # imprimiria a mensagem e os argumentos crus no stderr. Vai o par
            # redigido, sem montar.
            mensagem = f"{record.msg} {record.args!r}"
        record.msg = redact_urls_in_text(mensagem)
        record.args = None
        if record.exc_info and not record.exc_text:
            record.exc_text = logging.Formatter().formatException(record.exc_info)
        if record.exc_text:
            # O Formatter reaproveita `exc_text` quando ja esta preenchido, e
            # um handler que formatou antes deste pode te-lo deixado em claro.
            record.exc_text = redact_urls_in_text(record.exc_text)
        if record.stack_info:
            record.stack_info = redact_urls_in_text(record.stack_info)
        return True


def shutdown_logging() -> None:
    """Desfaz o que `configure_logging` instalou (testes e reconfiguracao)."""
    global _fault_file
    raiz = logging.getLogger()
    for handler in _log_handlers:
        raiz.removeHandler(handler)
        handler.close()
    _log_handlers.clear()
    if _fault_file is not None:
        faulthandler.disable()
        _fault_file.close()
        _fault_file = None


def configure_logging(stream=None) -> str | None:
    """Log do motor no stderr e em `logs_dir()/engine.log`.

    O stderr continua: quem roda o motor no terminal, e o front, leem por ali.
    O arquivo e o que sobra quando o app foi aberto pelo Finder, onde o
    stderr do app nao vai para lugar nenhum. Arquivo 0600 em pasta 0700,
    1 MB x 3 copias, URLs redigidas nos dois destinos. Texto digitado nao
    entra em log nenhum: os adapters nao o passam ao `logger`.

    Sem pasta de logs (symlink, arquivo no lugar, sem permissao), o motor
    sobe so com o stderr e devolve `None`, que vira `log_path: null`.
    """
    global _fault_file
    shutdown_logging()
    raiz = logging.getLogger()
    raiz.setLevel(logging.INFO)
    formato = logging.Formatter(LOG_FORMAT)
    filtro = _RedactingFilter()

    # Log vai para stderr: stdout e canal exclusivo do protocolo.
    saida = logging.StreamHandler(stream or sys.stderr)
    saida.setFormatter(formato)
    saida.addFilter(filtro)
    raiz.addHandler(saida)
    _log_handlers.append(saida)

    try:
        pasta = logs_dir()
        caminho = pasta / LOG_FILE_NAME
        arquivo = _PrivateRotatingFileHandler(
            caminho, maxBytes=LOG_MAX_BYTES, backupCount=LOG_BACKUPS, encoding="utf-8"
        )
    except OSError as exc:
        logger.warning("Log do motor so no stderr: %s", exc)
        return None
    arquivo.setFormatter(formato)
    arquivo.addFilter(filtro)
    raiz.addHandler(arquivo)
    _log_handlers.append(arquivo)

    despejo = pasta / FAULT_FILE_NAME
    try:
        # Despejo nao tem rotacao: so cresce numa queda. Passou do teto do
        # log, recomeca do zero na subida seguinte.
        grande = despejo.is_file() and despejo.stat().st_size > LOG_MAX_BYTES
        _fault_file = _open_private(despejo, truncate=grande)
        faulthandler.enable(file=_fault_file, all_threads=True)
    except OSError as exc:
        logger.warning("Despejo de queda desligado: %s", exc)
    logger.info("Motor %s, log em %s", __version__, caminho)
    return str(caminho)


def serve() -> None:
    log_path = configure_logging()
    server = EngineServer(log_path=log_path)

    def ao_receber_sigterm(_signum, _frame) -> None:
        """SIGTERM vira pedido de parada, nunca excecao.

        O front manda `engine.shutdown` e logo depois SIGTERM. O tratador
        padrao mataria o processo no meio do desmonte, e levantar `SystemExit`
        tambem: a excecao cai onde a thread principal estiver, inclusive dentro
        do `shutdown()`, e o proxy do aparelho, o `adb reverse` e o MP4 ficavam
        pela metade. Aqui o sinal so pede a parada, e os seguintes sao ignorados
        para que nada interrompa o desmonte.
        """
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        server.request_stop()

    signal.signal(signal.SIGTERM, ao_receber_sigterm)
    server.serve_forever()
