#!/usr/bin/env python3
"""Regera as fixtures do contrato consumidas pela suite Swift.

Rode sempre que o formato de uma resposta do motor mudar:

    make fixtures

As fixtures nao sao escritas a mao: saem do proprio motor, com os mesmos
serializadores que rodam em producao. E o que torna o contrato entre Python e
Swift verificavel dos dois lados.
"""

from __future__ import annotations

import contextlib
import io
import json
import pathlib
import sys
from unittest.mock import patch

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "engine" / "src"))

from PIL import Image  # noqa: E402

from mobaile.domain.models import AnalyticsEvent, NetworkEvent  # noqa: E402
from mobaile.rpc import protocol  # noqa: E402
from mobaile.rpc.server import EngineServer  # noqa: E402

HIERARCHY_XML = (
    '<hierarchy rotation="0">'
    '<node class="android.widget.Button" text="Continuar" clickable="true"'
    ' bounds="[10,20][110,70]" resource-id="br.app:id/btn_ok"'
    ' content-desc="Botao continuar" package="br.app"/>'
    "</hierarchy>"
)

# Ambiente de referencia. Um simulador ligado e outro parado cobrem os dois
# ramos de `simulators.list`, e o par sem aparelho Android conectado com AVDs
# parados e o estado mais comum de quem abre o app.
SIMULADORES = [
    {
        "udid": "1A2B3C4D-0000-4000-8000-0000000000AA",
        "name": "iPhone 16 Pro",
        "state": "Booted",
        "runtime": "iOS 18.6",
        "booted": True,
    },
    {
        "udid": "1A2B3C4D-0000-4000-8000-0000000000BB",
        "name": "iPad Air 11-inch (M3)",
        "state": "Shutdown",
        "runtime": "iOS 18.6",
        "booted": False,
    },
]
AVDS = ["Pixel_9", "Pixel_9_Pro"]


@contextlib.contextmanager
def ambiente_fixo(server: EngineServer):
    """Congela tudo que o motor le do ambiente da maquina.

    Sem isto a fixture depende de quem a gerou: num Mac com adb e Xcode
    instalados o `engine.info` sai com `/opt/homebrew/bin/adb` e
    `adb_available: true`, enquanto o CI, no Ubuntu, gera `adb` e `false`. O
    portao de frescor compara os dois arquivos e reprova justamente o PR de
    quem seguiu a regra "mudou o contrato, rode make fixtures".

    Congelando o ambiente, a fixture passa a ser funcao apenas do contrato,
    que e o que ela deveria estar medindo.
    """
    server.adb.adb_path = "adb"
    with contextlib.ExitStack() as stack:
        fixar = stack.enter_context
        fixar(patch.object(server.adb, "is_available", return_value=True))
        fixar(patch.object(server.adb, "list_devices", return_value=[]))
        fixar(patch.object(server.adb, "list_avds", return_value=AVDS))
        fixar(patch.object(server.adb, "start_avd", return_value=True))
        fixar(patch.object(server.scrcpy, "is_available", return_value=False))
        fixar(patch.object(server.ios, "is_xcrun_available", return_value=True))
        fixar(patch.object(server.ios, "list_all_simulators", return_value=SIMULADORES))
        fixar(patch.object(server.ios, "is_wda_running", return_value=False))
        fixar(patch.object(
            server.ios, "boot_simulator",
            return_value=(True, "Simulador iniciado e janela trazida para a frente."),
        ))
        # `is_installed` e propriedade: congelar a busca pelo binario evita
        # PropertyMock e mantem o caminho de codigo real.
        fixar(patch.object(server.appium, "locate_appium", return_value="/opt/homebrew/bin/appium"))
        fixar(patch.object(server.appium, "is_running", return_value=False))
        fixar(patch.object(
            server.appium, "ensure_wda",
            return_value=(True, "WebDriverAgent respondendo em http://localhost:8100."),
        ))
        yield


def build() -> dict:
    server = EngineServer(out=io.StringIO())

    def call(method, params=None):
        return server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )

    with ambiente_fixo(server):
        fixtures = {"engine.info": call("engine.info")}
        call("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        fixtures["session.select_device"] = call(
            "session.select_device", {"platform": "android", "device_id": "emulator-5554"}
        )
        with patch.object(server.adb, "get_ui_hierarchy", return_value=HIERARCHY_XML):
            fixtures["hierarchy.dump"] = call("hierarchy.dump")
        fixtures["hierarchy.element_at"] = call("hierarchy.element_at", {"x": 60, "y": 45})
        fixtures["codegen.record"] = call("codegen.record", {"x": 60, "y": 45, "strategy": "position"})
        fixtures["codegen.steps"] = call("codegen.steps")
        with patch.object(server.adb, "take_screenshot", return_value=Image.new("RGB", (60, 120), "black")):
            fixtures["screen.capture"] = call("screen.capture", {"max_width": 30})
        with patch.object(server.adb, "get_screen_size", return_value=(1080, 2400)):
            fixtures["screen.size"] = call("screen.size")
        fixtures["stream.stats"] = call("stream.stats")
        fixtures["proxy.events"] = call("proxy.events")
        fixtures["devices.list"] = call("devices.list")
        fixtures["erro_dominio"] = call("input.tap", {"x": -1, "y": 0})

        # Ambiente e inicializacao. Estes sete decodificam nos DTOs novos do
        # front, que ate agora compilavam sem nunca terem visto saida do motor.
        fixtures["diagnostics.check"] = call("diagnostics.check")
        fixtures["simulators.list"] = call("simulators.list")
        fixtures["simulators.boot"] = call("simulators.boot", {"udid": SIMULADORES[0]["udid"]})
        fixtures["emulators.list"] = call("emulators.list")
        fixtures["emulators.boot"] = call("emulators.boot", {"name": AVDS[0]})
        fixtures["wda.status"] = call("wda.status")
        fixtures["recording.status"] = call("recording.status")
        with patch.object(server.recorder, "start", return_value={
            "recording": True,
            "path": "/Users/qa/Movies/Mo baile/mobaile-android-20260908-101500.mp4",
            "platform": "android",
            "limit_s": 180,
        }):
            fixtures["recording.start"] = call("recording.start")
        with patch.object(server.recorder, "stop", return_value={
            "recording": False,
            "path": "/Users/qa/Movies/Mo baile/mobaile-android-20260908-101500.mp4",
            "size_bytes": 1_482_310,
            "duration_s": 12.4,
        }):
            fixtures["recording.stop"] = call("recording.stop")
        fixtures["wda.start"] = call("wda.start", {"udid": SIMULADORES[0]["udid"]})

    traffic = NetworkEvent(
        id=7, timestamp=1757030000.5, time_str="14:32:10.123", method="POST",
        url="https://api.exemplo.com.br/v2/credito/simulacao", host="api.exemplo.com.br",
        path="/v2/credito/simulacao", status_code=200, status_text="OK",
        request_headers={"Content-Type": "application/json", "Authorization": "«redigido» (32 chars)"},
        request_body='{"valor":1000}', response_headers={"Content-Type": "application/json"},
        response_body='{"parcelas":12}', duration_ms=182.7, protocol="HTTP/1.1",
        is_tunnel=False, error=None, request_bytes=14, response_bytes=15, body_truncated=False,
    )
    fixtures["notif_proxy.event"] = protocol.notification("proxy.event", traffic.to_dict())

    analytics = AnalyticsEvent(
        id=3, timestamp=1757030001.0, time_str="14:32:11.001", tag="FA", event_name="screen_view",
        params={"screen_name": "onboarding_credito", "step": 2, "first_open": True},
        raw_log="Logging event: screen_view", platform="android",
    )
    fixtures["notif_analytics.event"] = protocol.notification("analytics.event", analytics.to_dict())

    server.shutdown()
    return fixtures


def main() -> None:
    destination = REPO_ROOT / "apps/MoBaile/Tests/MoBaileTests/Fixtures/engine_payloads.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(build(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"fixtures gravadas em {destination.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
