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
import sys
import threading
import traceback
from collections.abc import Callable
from typing import Any

from mobaile import __version__
from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.analytics_logcat import FirebaseAnalyticsListener
from mobaile.adapters.appium import AppiumBridge
from mobaile.adapters.ios_wda import IOSBridge
from mobaile.adapters.proxy import MobileNetworkProxy
from mobaile.adapters.scrcpy import ScrcpyManager
from mobaile.config import settings
from mobaile.domain.errors import EngineError, InvalidInputError
from mobaile.domain.models import LocatorStrategy, Platform
from mobaile.rpc import protocol
from mobaile.security import validate_coordinate, validate_device_id
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
        self.analytics = FirebaseAnalyticsListener(adb_bridge=self.adb)
        self.codegen = CodeGenerator()
        self.appium = AppiumBridge()
        self.diagnostics = DiagnosticsService(adb=self.adb, ios=self.ios, appium=self.appium)

        self.platform: Platform = Platform.ANDROID
        self.device_id: str | None = None
        self.current_xml: str | None = None
        self._stream: RealTimeStreamEngine | None = None
        self._watcher: DeviceWatcher | None = None

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
        xml = self.ios.get_ui_hierarchy() if self.platform is Platform.IOS else self.adb.get_ui_hierarchy(device)
        if not xml:
            raise EngineError("Hierarquia de UI indisponivel para o alvo atual.")
        self.current_xml = xml
        elements = UIHierarchyParser.parse_xml(xml)
        return {"count": len(elements), "elements": [element.to_dict() for element in elements]}

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
        return {"ok": bool(self.adb.type_text(device, text))}

    # -------------------------------------------------------------- streaming

    def stream_start(self, params: dict[str, Any]) -> dict[str, Any]:
        self.stream_stop({})
        fps = float(params.get("fps") or settings.stream_fps)
        max_width = int(params.get("max_width") or STREAM_MAX_WIDTH)

        def on_frame(image) -> None:
            try:
                self.notify("stream.frame", self._encode_png(image, max_width))
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
            raise EngineError("Nenhum elemento encontrado nessa coordenada.")
        strategy_raw = str(params.get("strategy") or settings.default_strategy).lower()
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
        }

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
