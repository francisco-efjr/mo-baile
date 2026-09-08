"""Servidor JSON-RPC do motor.

Uma unica classe concentra a sessao (dispositivo ativo, plataforma, gerador de
codigo, proxy, analytics) e expoe metodos nomeados. A camada de apresentacao,
seja o SwiftUI ou o Tk, nao toca em adapter nenhum: fala so este contrato.

Concorrencia: stdin e lido na thread principal, e cada notificacao empurrada
por callback de outra thread passa pelo mesmo lock de escrita. Duas linhas
nunca se intercalam no stdout, que e a unica invariante que o protocolo exige.
"""

from __future__ import annotations

import base64
import io
import logging
import pathlib
import re
import sys
import threading
import traceback
from collections.abc import Callable
from typing import Any

from mobaile import __version__
from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.analytics_logcat import FirebaseAnalyticsListener
from mobaile.adapters.appium import AppiumBridge
from mobaile.adapters.input_events import AndroidPassiveListener, IOSPassiveListener
from mobaile.adapters.ios_wda import IOSBridge
from mobaile.adapters.proxy import MobileNetworkProxy
from mobaile.adapters.scrcpy import ScrcpyManager
from mobaile.adapters.screen_recorder import ScreenRecorder
from mobaile.config import settings
from mobaile.domain.errors import EngineError, InvalidInputError, ToolNotFoundError
from mobaile.domain.models import LocatorStrategy, Platform, UIElement
from mobaile.rpc import protocol
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


class EngineServer:
    """Estado da sessao e tabela de metodos."""

    def __init__(self, out=None) -> None:
        self._out = out or sys.stdout
        self._write_lock = threading.Lock()
        self._running = True

        self.adb = ADBBridge()
        self.ios = IOSBridge()
        self.scrcpy = ScrcpyManager()
        self.proxy = MobileNetworkProxy()
        self.recorder = ScreenRecorder(self.adb, self.ios)
        self.analytics = FirebaseAnalyticsListener(adb_bridge=self.adb)
        self.codegen = CodeGenerator()
        self.appium = AppiumBridge()
        self.diagnostics = DiagnosticsService(adb=self.adb, ios=self.ios, appium=self.appium)

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

        self.methods: dict[str, Callable[[dict[str, Any]], Any]] = {
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
            "proxy.start": self.proxy_start,
            "proxy.stop": self.proxy_stop,
            "proxy.events": self.proxy_events,
            "proxy.clear": self.proxy_clear,
            "analytics.start": self.analytics_start,
            "analytics.stop": self.analytics_stop,
            "analytics.events": self.analytics_events,
            "analytics.clear": self.analytics_clear,
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

    # ------------------------------------------------------------------ helpers

    def _require_device(self) -> str:
        if not self.device_id:
            raise InvalidInputError("Nenhum dispositivo selecionado nesta sessao.")
        return self.device_id

    def _bridge_for_capture(self):
        return self.ios if self.platform is Platform.IOS else self.adb

    def _capture_image(self):
        device = self._require_device()
        if self.platform is Platform.IOS:
            return self.ios.take_screenshot(device)
        return self.adb.take_screenshot(device)

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

    def engine_info(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {
            "version": __version__,
            "platform": self.platform.value,
            "device_id": self.device_id,
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
        self.shutdown()
        return {"stopped": True}

    def session_select_device(self, params: dict[str, Any]) -> dict[str, Any]:
        platform_raw = str(params.get("platform", self.platform.value)).lower()
        if platform_raw not in ("ios", "android"):
            raise InvalidInputError(f"Plataforma invalida: {platform_raw!r}")
        self.platform = Platform(platform_raw)
        if self._watcher:
            self._watcher.set_platform(self.platform.value)
        device_id = params.get("device_id")
        self.device_id = validate_device_id(device_id) if device_id else None
        self.current_xml = None
        return {"platform": self.platform.value, "device_id": self.device_id}

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
            if platform == "none":
                self.device_id = None
                self.current_xml = None
            else:
                self.device_id = device_id
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
        escritos no codigo.
        """
        return self.diagnostics.run()

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
            disponiveis = self.ios.list_all_simulators()
            if not disponiveis:
                raise EngineError("Nenhum simulador instalado neste Mac.")
            ja_ligado = next((s for s in disponiveis if s["booted"]), None)
            udid = (ja_ligado or disponiveis[0])["udid"]

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
            avds = self.adb.list_avds()
            if not avds:
                raise EngineError("Nenhum AVD criado. Crie um pelo Android Studio.")
            nome = avds[0]
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
        return self.recorder.start(self.platform, self._require_device())

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
            ligados = [s for s in self.ios.list_all_simulators() if s["booted"]]
            if not ligados:
                raise EngineError("Nenhum simulador ligado. Abra um simulador antes de iniciar o WDA.")
            udid = ligados[0]["udid"]

        ok, mensagem = self.appium.ensure_wda(udid, params.get("platform_version"))
        if not ok:
            raise EngineError(mensagem)
        return {"udid": udid, "message": mensagem, "wda_running": True}

    def screen_capture(self, params: dict[str, Any]) -> dict[str, Any]:
        image = self._capture_image()
        if image is None:
            raise EngineError("Nao foi possivel capturar a tela do dispositivo.")
        max_width = params.get("max_width")
        return self._encode_png(image, int(max_width) if max_width else None)

    def screen_size(self, _params: dict[str, Any]) -> dict[str, Any]:
        device = self._require_device()
        if self.platform is Platform.IOS:
            image = self.ios.take_screenshot(device)
            if image is None:
                raise EngineError("Simulador nao respondeu a captura.")
            width, height = image.size
        else:
            width, height = self.adb.get_screen_size(device)
        return {"width": width, "height": height}

    def hierarchy_dump(self, _params: dict[str, Any]) -> dict[str, Any]:
        device = self._require_device()
        xml = self.ios.get_ui_hierarchy() if self.platform is Platform.IOS else self._android_hierarchy(device)
        if not xml:
            raise EngineError(self._motivo_de_hierarquia_indisponivel())
        self.current_xml = xml
        elements = UIHierarchyParser.parse_xml(xml)
        return {"count": len(elements), "elements": [element.to_dict() for element in elements]}

    def _android_hierarchy(self, device: str) -> str | None:
        """Hierarquia do Android, com o WebDriver como segunda tentativa.

        `uiautomator dump` e o caminho rapido e nao exige sessao, mas falha em
        parte dos aparelhos: em Motorola com Android 14 ele e morto com SIGKILL
        e volta vazio. Quando isso acontece, o mesmo servico e alcancado pela
        sessao UiAutomator2 do Appium, que e o equivalente Android do WDA.
        """
        xml = self.adb.get_ui_hierarchy(device)
        if xml:
            return xml

        logger.info("uiautomator dump vazio para %s; tentando pelo Appium.", device)
        ok, mensagem = self.appium.ensure_android_session(device)
        if not ok:
            self._ultima_falha_de_hierarquia = mensagem
            logger.warning("Sessao Android do Appium indisponivel: %s", mensagem)
            return None
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
        if not self.current_xml:
            raise InvalidInputError("Nenhuma hierarquia carregada. Chame hierarchy.dump antes.")
        x = validate_coordinate(params.get("x"), "x")
        y = validate_coordinate(params.get("y"), "y")
        element = UIHierarchyParser.find_element_at(self.current_xml, x, y)
        return {"element": element.to_dict() if element else None}

    def input_tap(self, params: dict[str, Any]) -> dict[str, Any]:
        device = self._require_device()
        x = validate_coordinate(params.get("x"), "x")
        y = validate_coordinate(params.get("y"), "y")
        ok = self.ios.tap(x, y) if self.platform is Platform.IOS else self.adb.tap(device, x, y)
        return {"ok": bool(ok)}

    def input_text(self, params: dict[str, Any]) -> dict[str, Any]:
        device = self._require_device()
        text = params.get("text", "")
        if self.platform is Platform.IOS:
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

        def on_frame(image) -> None:
            try:
                payload = self._encode_png(image, max_width)
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
            get_frame_fn=self._capture_image,
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

    # ------------------------------------------------------------------ proxy

    def proxy_start(self, params: dict[str, Any]) -> dict[str, Any]:
        self.proxy.add_event_callback(lambda event: self.notify("proxy.event", event.to_dict()))
        started = self.proxy.start()
        configured = False
        if started and params.get("configure_device") and self.platform is Platform.ANDROID and self.device_id:
            configured = self.adb.setup_reverse_proxy(self.device_id, self.proxy.port)
        return {"running": self.proxy.is_running(), "started": started, "device_configured": configured}

    def proxy_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        if self.platform is Platform.ANDROID and self.device_id:
            self.adb.teardown_reverse_proxy(self.device_id, self.proxy.port)
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

    def analytics_start(self, _params: dict[str, Any]) -> dict[str, Any]:
        ok = self.analytics.start(platform=self.platform.value, device_id=self.device_id)
        return {"running": ok}

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
        if not self.current_xml:
            raise InvalidInputError("Nenhuma hierarquia carregada. Chame hierarchy.dump antes.")
        x = validate_coordinate(params.get("x"), "x")
        y = validate_coordinate(params.get("y"), "y")
        element = UIHierarchyParser.find_element_at(self.current_xml, x, y)
        if element is None:
            element = self._elemento_por_posicao(x, y)
        strategy_raw = str(params.get("strategy") or settings.default_strategy).lower()

        # "auto" deixa o motor escolher pelo que e mais robusto e unico nesta
        # tela, em vez de aplicar uma estrategia fixa a todos os elementos.
        alternativas: list[dict] = []
        if strategy_raw == "auto":
            na_tela = UIHierarchyParser.parse_xml(self.current_xml)
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

    def _elemento_por_posicao(self, x: int, y: int) -> UIElement:
        """Elemento sintetico para clique em area sem no na arvore.

        Recusar a gravacao aqui parece rigor e na pratica trava o trabalho:
        area vazia, canvas de jogo e componente desenhado a mao nao aparecem na
        arvore de acessibilidade, e o passo por coordenada e exatamente o que
        resta. A interface Tk ja fazia isso; a regra estava so la, o que
        deixava o front nativo falhando em silencio no mesmo clique.
        """
        tag = "XCUIElementTypeOther" if self.platform is Platform.IOS else "android.view.View"
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
            platform=self.platform.value,
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
        if self._passive is not None:
            raise InvalidInputError("A escuta passiva ja esta ligada.")

        device = self._require_device()

        if self.platform is Platform.IOS:
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

        ouvinte.start()
        self._passive = ouvinte
        logger.info("Escuta passiva ligada para %s (%sx%s)", device, largura, altura)
        return {"listening": True, "platform": self.platform.value, "screen": [largura, altura]}

    def _tamanho_logico_ios(self) -> tuple[int, int]:
        """Tamanho da tela do iOS em pontos, que e o espaco do WDA.

        Nao serve usar `screen.size` aqui: ele mede a captura, em pixels. Medido
        num iPhone 16e, a captura da 1170x2532 e o WDA reporta 390x844 — fator
        3. Gravar com o valor errado poe todo passo a tres vezes a distancia.

        A verdade esta na raiz da arvore do proprio WDA.
        """
        xml = self.current_xml or self.ios.get_ui_hierarchy()
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
        if self.platform is not Platform.ANDROID:
            return False
        try:
            _, saida, _ = self.adb._run_cmd(
                self.adb._device_args(self.device_id or "", "shell", "dumpsys", "input_method"),
                timeout=4,
            )
            return b"mInputShown=true" in saida
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

        xml = self._android_hierarchy(self.device_id or "") if self.platform is Platform.ANDROID else self.ios.get_ui_hierarchy()
        if not xml:
            return
        self.current_xml = xml

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

            if not self.current_xml:
                self.notify("passive.skipped", {"x": x, "y": y, "reason": "sem hierarquia carregada"})
                return
            resultado = self.codegen_record({"x": x, "y": y, "strategy": "auto"})
            if resultado["element"].get("resource_id"):
                self._campo_digitado = resultado["element"]["resource_id"]
            self.notify("passive.step", resultado)
        except EngineError as exc:
            logger.warning("Toque passivo em (%s,%s) nao virou passo: %s", x, y, exc)
            self.notify("passive.skipped", {"x": x, "y": y, "reason": str(exc)})

    # ------------------------------------------------------- execucao de fluxo

    def flow_run(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Executa os passos gravados no aparelho.

        O servico ja existia e era testado, mas so a interface Tk o usava: o
        front nativo nao tinha como rodar automacao nenhuma. O andamento sai por
        `flow.log`, linha a linha, como o espelho faz com `stream.frame`.
        """
        if self._flow_running:
            raise InvalidInputError("Ja existe uma execucao em andamento.")

        passos = self.codegen.get_steps()
        if not passos:
            raise InvalidInputError("Nenhum passo gravado para executar.")

        device = self._require_device()
        ok, motivo = flows.verify_preconditions(
            platform=self.platform.value, device_id=device, adb_path=self.adb.adb_path
        )
        if not ok:
            raise EngineError(motivo)

        script = flows.generate_hidden_runner_script(
            steps=passos,
            platform=self.platform.value,
            device_id=device,
            wda_url=settings.wda_url,
            adb_path=self.adb.adb_path,
        )

        self._flow_running = True
        self._flow_cancelled = False

        def ao_sair(linha: str) -> None:
            self.notify("flow.log", {"line": linha})

        def ao_terminar(sucesso: bool, mensagem: str) -> None:
            self._flow_running = False
            self.notify(
                "flow.finished",
                {"success": sucesso and not self._flow_cancelled, "message": mensagem},
            )

        self._flow_thread = flows.run_flow_in_background(script, ao_sair, ao_terminar)
        return {"running": True, "steps": len(passos), "script": script}

    def flow_stop(self, _params: dict[str, Any]) -> dict[str, Any]:
        """Pede a interrupcao. Idempotente.

        O script roda em processo proprio; marcar a intencao e avisar a interface
        e o que o motor pode fazer sem matar o processo no meio de um toque.
        """
        if not self._flow_running:
            return {"running": False, "stopped": False}
        self._flow_cancelled = True
        self.notify("flow.log", {"line": "Interrupcao pedida; encerrando apos o passo atual."})
        return {"running": True, "stopped": True}

    def flow_status(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {"running": self._flow_running, "cancelled": self._flow_cancelled}

    def codegen_steps(self, _params: dict[str, Any]) -> dict[str, Any]:
        return {"steps": [step.to_dict() for step in self.codegen.get_steps()]}

    def codegen_reset(self, _params: dict[str, Any]) -> dict[str, Any]:
        self.codegen.reset()
        return {"steps": 0}

    # ------------------------------------------------------------------- loop

    def handle_message(self, raw: str) -> dict[str, Any] | None:
        """Processa uma linha. Devolve a resposta ou `None` para notificacao."""
        import json

        try:
            message = json.loads(raw)
        except json.JSONDecodeError as exc:
            return protocol.error(None, protocol.PARSE_ERROR, "JSON invalido.", str(exc))

        if not isinstance(message, dict) or message.get("jsonrpc") != protocol.JSONRPC_VERSION:
            return protocol.error(message.get("id") if isinstance(message, dict) else None,
                                  protocol.INVALID_REQUEST, "Envelope JSON-RPC 2.0 esperado.")

        request_id = message.get("id")
        method = message.get("method")
        params = message.get("params") or {}
        if not isinstance(params, dict):
            return protocol.error(request_id, protocol.INVALID_PARAMS, "params deve ser objeto.")

        handler = self.methods.get(method)
        if handler is None:
            return protocol.error(request_id, protocol.METHOD_NOT_FOUND, f"Metodo desconhecido: {method}")

        try:
            payload = handler(params)
        except EngineError as exc:
            return protocol.error(request_id, protocol.ENGINE_ERROR, exc.message, exc.to_dict())
        except Exception as exc:
            logger.exception("Erro interno em %s", method)
            return protocol.error(
                request_id, protocol.INTERNAL_ERROR, "Erro interno no motor.",
                {"exception": type(exc).__name__, "trace": traceback.format_exc(limit=3)},
            )

        # Sem id, e notificacao: o cliente nao espera resposta.
        return protocol.result(request_id, payload) if request_id is not None else None

    def shutdown(self) -> None:
        """Encerra tudo que segura recurso externo. Idempotente."""
        self._running = False
        self.stream_stop({})
        self.devices_watch_stop({})
        try:
            if self.platform is Platform.ANDROID and self.device_id and self.proxy.is_running():
                # Deixar o aparelho com proxy apontando para porta morta o
                # deixaria sem rede depois que o app fecha.
                self.adb.teardown_reverse_proxy(self.device_id, self.proxy.port)
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

    def serve_forever(self, stream=None) -> None:
        source = stream or sys.stdin
        for line in source:
            if not self._running:
                break
            line = line.strip()
            if not line:
                continue
            response = self.handle_message(line)
            if response is not None:
                self.send(response)
        self.shutdown()


def serve() -> None:
    logging.basicConfig(
        level=logging.INFO,
        # Log vai para stderr: stdout e canal exclusivo do protocolo.
        stream=sys.stderr,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    EngineServer().serve_forever()
