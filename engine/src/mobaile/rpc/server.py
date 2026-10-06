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
import io
import json
import logging
import pathlib
import queue
import re
import signal
import sys
import threading
import time
import traceback
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any, NamedTuple

from mobaile import __version__
from mobaile.adapters import ios_device_log
from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.analytics_logcat import FirebaseAnalyticsListener
from mobaile.adapters.appium import AppiumBridge
from mobaile.adapters.ios_wda import IOSBridge
from mobaile.adapters.proxy import MobileNetworkProxy
from mobaile.adapters.scrcpy import ScrcpyManager
from mobaile.adapters.screen_recorder import ScreenRecorder
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
    validate_coordinate,
    validate_device_id,
)
from mobaile.services import flows
from mobaile.services.codegen import CodeGenerator
from mobaile.services.devices import DeviceWatcher
from mobaile.services.diagnostics import DiagnosticsService
from mobaile.services.hierarchy import UIHierarchyParser
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


class EngineServer:
    """Estado da sessao e tabela de metodos."""

    def __init__(self, out=None) -> None:
        self._out = out or sys.stdout
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
        self.recorder = ScreenRecorder(self.adb, self.ios)
        self.analytics = FirebaseAnalyticsListener(adb_bridge=self.adb)
        # Uma vez so: registrar a cada analytics.start duplicava cada evento
        # na UI apos parar e reiniciar a escuta.
        self.analytics.add_event_callback(lambda event: self.notify("analytics.event", event.to_dict()))
        self.codegen = CodeGenerator()
        self.appium = AppiumBridge()
        self.diagnostics = DiagnosticsService(adb=self.adb, ios=self.ios, appium=self.appium)

        # Estado de sessao. Escrito pelas filas, pelo vigia de dispositivos e
        # pelas threads da escuta passiva, sempre sob `_state_lock`. A epoca
        # sobe a cada troca de alvo; ver `_store_hierarchy`.
        self._state_lock = threading.RLock()
        self._session_epoch = 0
        self.platform: Platform = Platform.ANDROID
        self.device_id: str | None = None
        self.current_xml: str | None = None
        self._stream: RealTimeStreamEngine | None = None
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
            "devices.list": self.devices_list,
            "devices.watch_start": self.devices_watch_start,
            "devices.watch_stop": self.devices_watch_stop,
            "diagnostics.check": self.diagnostics_check,
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
            "passive.start": self.passive_start,
            "passive.stop": self.passive_stop,
            "passive.status": self.passive_status,
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
        return contract.hello_payload(__version__)

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
        watcher = self._watcher
        if watcher:
            watcher.set_platform(platform.value)
        return {"platform": platform.value, "device_id": device_id}

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
        interval = float(params.get("poll_interval") or settings.poll_interval)

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

        self._watcher = DeviceWatcher(
            adb_bridge=self.adb,
            ios_bridge=self.ios,
            on_device_changed=on_changed,
            target_platform=self.platform.value,
            poll_interval=interval,
        )
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
        payload = self._encode_png(image, int(max_width) if max_width else None)
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

        logger.info("uiautomator dump vazio para %s; memorizando backend Appium.", device)
        self._android_backend[device] = "appium"
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

    def stream_start(self, params: dict[str, Any]) -> dict[str, Any]:
        self.stream_stop({})
        fps = float(params.get("fps") or settings.stream_fps)
        max_width = int(params.get("max_width") or STREAM_MAX_WIDTH)
        # Retrato da sessao usado na ultima captura. Captura e emissao rodam em
        # sequencia na mesma thread do espelho, entao uma variavel basta.
        retrato: list[_Sessao] = []

        def capturar():
            sessao = self._require_session()
            retrato[:] = [sessao]
            return self._capture_image(sessao)

        def on_frame(image) -> None:
            try:
                sessao = retrato[0]
                # Quadro de um aparelho que deixou de ser o alvo nao sai: o
                # front o desenharia sob o aparelho novo.
                if sessao.epoch != self._sessao().epoch:
                    return
                payload = self._encode_png(image, max_width)
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
        return {"started": True, "fps": fps, "max_width": max_width}

    def stream_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
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
        fps = int(params.get("fps") or 60)
        max_size = int(params.get("max_size") or 1080)
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

    def proxy_start(self, params: dict[str, Any]) -> dict[str, Any]:
        self.proxy.add_event_callback(lambda event: self.notify("proxy.event", event.to_dict()))
        started = self.proxy.start()
        configured = False
        sessao = self._sessao()
        if started and params.get("configure_device") and sessao.platform is Platform.ANDROID and sessao.device_id:
            configured = self.adb.setup_reverse_proxy(sessao.device_id, self.proxy.port)
        return {"running": self.proxy.is_running(), "started": started, "device_configured": configured}

    def proxy_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        sessao = self._sessao()
        if sessao.platform is Platform.ANDROID and sessao.device_id:
            self.adb.teardown_reverse_proxy(sessao.device_id, self.proxy.port)
        self.proxy.stop()
        return {"running": self.proxy.is_running()}

    def proxy_events(self, params: dict[str, Any]) -> dict[str, Any]:
        limit = int(params.get("limit") or 200)
        events = self.proxy.events_history[-limit:]
        return {"events": [event.to_dict() for event in events], "total": len(self.proxy.events_history)}

    def proxy_clear(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.proxy.clear_history()
        return {"cleared": True}

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
        limit = int(params.get("limit") or 200)
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
        if element is None:
            element = self._elemento_por_posicao(x, y, platform)
        strategy_raw = str(params.get("strategy") or settings.default_strategy).lower()

        # "auto" deixa o motor escolher pelo que e mais robusto e unico nesta
        # tela, em vez de aplicar uma estrategia fixa a todos os elementos.
        alternativas: list[dict] = []
        if strategy_raw == "auto":
            na_tela = UIHierarchyParser.parse_xml(xml)
            alternativas = self.codegen.rank_locators(element, na_tela)
            escolhido = alternativas[0]["strategy"]
            strategy_raw = {"accessibility_id": "id", "text": "xpath"}.get(escolhido, escolhido)

        try:
            strategy = LocatorStrategy(strategy_raw)
        except ValueError as exc:
            raise InvalidInputError(f"Estrategia invalida: {strategy_raw!r}") from exc
        var_name, object_code, action_code = self.codegen.generate_entry(
            element, strategy=strategy, click_coord=(x, y)
        )
        return {
            "var_name": var_name,
            "object_code": object_code,
            "action_code": action_code,
            "element": element.to_dict(),
            "step_count": len(self.codegen.get_steps()),
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

        destino = pathlib.Path(params.get("directory") or (pathlib.Path.home() / "Documents" / "Mo baile"))
        acoes = str(params.get("actions_code") or "")
        locators = str(params.get("locators_code") or "")
        if not acoes.strip() and not locators.strip():
            raise InvalidInputError("Nada para salvar: os dois editores estao vazios.")

        escritos = []
        for subpasta, conteudo in (("pages", acoes), ("locators", locators)):
            pasta = destino / subpasta
            pasta.mkdir(parents=True, exist_ok=True)
            arquivo = pasta / f"{chave}.py"
            arquivo.write_text(conteudo, encoding="utf-8")
            escritos.append(str(arquivo))

        logger.info("Page Object gravado em %s", destino)
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
        except (InvalidInputError, ToolNotFoundError) as exc:
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

    def flow_run(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Executa os passos gravados no aparelho.

        O servico ja existia e era testado, mas so a interface Tk o usava: o
        front nativo nao tinha como rodar automacao nenhuma. O andamento sai por
        `flow.log`, linha a linha, como o espelho faz com `stream.frame`.
        """
        passos = self.codegen.get_steps()
        if not passos:
            raise InvalidInputError("Nenhum passo gravado para executar.")

        sessao = self._require_session()
        device = sessao.device_id
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
            with self._state_lock:
                self._flow_running = False
                self._flow_thread = None
                cancelado = self._flow_cancelled
            self.notify(
                "flow.finished",
                {"success": sucesso and not cancelado, "message": mensagem},
            )

        try:
            ok, motivo = flows.verify_preconditions(
                platform=sessao.platform.value, device_id=device, adb_path=self.adb.adb_path
            )
            if not ok:
                raise EngineError(motivo)
            self._check_cancelled()
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
                )
        except Exception:
            with self._state_lock:
                self._flow_running = False
                self._flow_thread = None
            raise
        return {"running": True, "steps": len(passos), "script": script}

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

    def codegen_steps(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {"steps": [step.to_dict() for step in self.codegen.get_steps()]}

    def codegen_reset(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.codegen.reset()
        return {"steps": 0}

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
            if sessao.platform is Platform.ANDROID and sessao.device_id and self.proxy.is_running():
                # Deixar o aparelho com proxy apontando para porta morta o
                # deixaria sem rede depois que o app fecha.
                self.adb.teardown_reverse_proxy(sessao.device_id, self.proxy.port)
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


def serve() -> None:
    logging.basicConfig(
        level=logging.INFO,
        # Log vai para stderr: stdout e canal exclusivo do protocolo.
        stream=sys.stderr,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    server = EngineServer()

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
