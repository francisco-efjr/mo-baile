#!/usr/bin/env python3
"""Regera as fixtures do contrato consumidas pela suite Swift.

Rode sempre que o formato de uma resposta do motor mudar:

    make fixtures

As fixtures nao sao escritas a mao: saem do proprio motor, com os mesmos
serializadores que rodam em producao. E o que torna o contrato entre Python e
Swift verificavel dos dois lados.
"""

from __future__ import annotations

import base64
import contextlib
import io
import json
import pathlib
import sys
import tempfile
import threading
from typing import Any
from unittest.mock import patch

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "engine" / "src"))
# Cenario sintetico da aba Relatorio: o mesmo dos testes do motor, para a
# fixture e a suite Python falarem do mesmo relatorio.
sys.path.insert(0, str(REPO_ROOT / "engine" / "tests" / "unit"))

from PIL import Image  # noqa: E402
from relatorio_dados import SPEC, gravar  # noqa: E402
from relatorio_ocr import CARD_CHECKOUT, CARD_INTERACTION  # noqa: E402

from mobaile.domain.models import AnalyticsEvent, NetworkEvent  # noqa: E402
from mobaile.rpc import contract, protocol  # noqa: E402
from mobaile.rpc.server import EngineServer  # noqa: E402
from mobaile.services.report import ReportService  # noqa: E402

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


def cancelamento() -> dict:
    """Erro de cancelamento pelo caminho real: fila, `$/cancelRequest` e descarte.

    Sobe o laco de producao (`serve_forever`) com um `wda.start` que so espera,
    cancela o pedido e confere que saiu uma resposta so, a de erro. Montar esse
    JSON a mao seria justamente a divergencia que as fixtures existem para pegar.
    """
    saida = io.StringIO()
    server = EngineServer(out=saida)
    liberar = threading.Event()

    def wda_que_espera(_params):
        liberar.wait(5)
        return {"wda_running": True}

    server.methods["wda.start"] = wda_que_espera

    def entrada():
        yield json.dumps({"jsonrpc": "2.0", "id": 7, "method": "wda.start", "params": {}})
        yield json.dumps({"jsonrpc": "2.0", "method": contract.CANCEL_REQUEST, "params": {"id": 7}})
        liberar.set()

    server.serve_forever(entrada())
    (resposta,) = [json.loads(linha) for linha in saida.getvalue().splitlines() if linha.strip()]
    return resposta


# Onde os arquivos do relatorio "moram" na fixture. O motor grava de verdade
# numa pasta temporaria; o caminho dela muda a cada execucao e de maquina para
# maquina, entao sai da fixture trocado por este.
PASTA_RELATORIO = "/Users/qa/Documents/Mo baile/Demanda"
PNG_1X1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="


class _OcrFalso:
    """OCR com as linhas sinteticas dos testes: o Vision so existe no macOS."""

    def read(self, paths):
        cards = [CARD_INTERACTION, CARD_CHECKOUT]
        return {str(p): cards[i % 2] for i, p in enumerate(paths)}


def _trocar_caminhos(valor: Any, de: tuple[str, ...], para: str) -> Any:
    if isinstance(valor, str):
        for origem in de:
            valor = valor.replace(origem, para)
        return valor
    if isinstance(valor, list):
        return [_trocar_caminhos(v, de, para) for v in valor]
    if isinstance(valor, dict):
        return {k: _trocar_caminhos(v, de, para) for k, v in valor.items()}
    return valor


def relatorio(server: EngineServer, call) -> dict:
    """`report.*` pelo servidor de verdade, sobre arquivos de verdade."""
    with tempfile.TemporaryDirectory() as tmp:
        pasta = pathlib.Path(tmp).resolve()
        server.report = ReportService(ocr=_OcrFalso(), documents_dir=pasta / "Mo baile")
        prints = pasta / "prints"
        prints.mkdir()
        # Bytes fixos, e nao `Image.save`: o encoder do Pillow muda entre
        # versoes, e o tamanho do board exportado entra na fixture.
        (prints / "home.png").write_bytes(base64.b64decode(PNG_1X1))
        (prints / "simulacao.png").write_bytes(b"nao e imagem")
        cards = [dict(SPEC["cards"][0], print="home.png"), *SPEC["cards"][1:]]
        spec_path, log_path = gravar(pasta, spec={**SPEC, "prints_dir": "prints", "cards": cards})

        saida = {
            "report.spec": call("report.spec", {"path": str(spec_path)}),
            "report.audit": call("report.audit", {
                "spec_path": str(spec_path), "source": "file", "log_path": str(log_path),
            }),
            "report.export": call("report.export", {"directory": str(pasta / "saida")}),
            "report.import": call("report.import", {
                "prints_dir": str(prints), "projeto": "Demanda", "platform": "android",
            }),
            "erro_report_sessao_vazia": call("report.audit", {"spec_path": str(spec_path), "source": "session"}),
        }
        return _trocar_caminhos(saida, (str(pasta), tmp), PASTA_RELATORIO)


def build() -> dict:
    out = io.StringIO()
    server = EngineServer(out=out)

    def call(method, params=None):
        return server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )

    with ambiente_fixo(server):
        fixtures = {"engine.info": call("engine.info")}
        fixtures["engine.hello"] = call(
            "engine.hello", {"protocol_version": contract.PROTOCOL_VERSION, "client": "MoBaile/0.1"}
        )
        fixtures["erro_incompatible_protocol"] = call(
            "engine.hello", {"protocol_version": contract.PROTOCOL_VERSION - 1, "client": "MoBaile/0.0"}
        )
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

        # `$/progress` sai do mesmo `wda.start`, agora com token. Fica o
        # primeiro aviso, o de `percent` nulo, que e o caso que o front precisa
        # decodificar sem inventar numero.
        out.seek(0)
        out.truncate()
        call("wda.start", {"udid": SIMULADORES[0]["udid"], "progress_token": "wda-1"})
        avisos = [json.loads(linha) for linha in out.getvalue().splitlines() if linha.strip()]
        fixtures["notif_$/progress"] = next(m for m in avisos if m.get("method") == contract.PROGRESS)

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

    fixtures.update(relatorio(server, call))

    server.shutdown()
    fixtures["erro_request_cancelled"] = cancelamento()
    return fixtures


def main() -> None:
    destination = REPO_ROOT / "apps/MoBaile/Tests/MoBaileTests/Fixtures/engine_payloads.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(build(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"fixtures gravadas em {destination.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
