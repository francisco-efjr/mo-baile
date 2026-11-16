#!/usr/bin/env python3
"""Regera as fixtures do contrato consumidas pela suite Swift.

Rode sempre que o formato de uma resposta do motor mudar:

    make fixtures

Para so conferir, sem escrever (o `make check` faz isto, alvo
`fixtures-check`): gera em memoria, compara com o arquivo e sai com erro se
houver diferenca.

    python tools/generate_fixtures.py --check

As fixtures nao sao escritas a mao: saem do proprio motor, com os mesmos
serializadores que rodam em producao. E o que torna o contrato entre Python e
Swift verificavel dos dois lados.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import datetime
import io
import json
import os
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
from mobaile.services.home import RecentStore  # noqa: E402
from mobaile.services.project_doctor import ProjectDoctor  # noqa: E402
from mobaile.services.projects import ProjectService, ProjectStore  # noqa: E402
from mobaile.services.report import ReportService  # noqa: E402
from mobaile.services.setup import Probe, SetupService  # noqa: E402

FIXTURE_PATH = REPO_ROOT / "apps/MoBaile/Tests/MoBaileTests/Fixtures/engine_payloads.json"
# Projeto de exemplo da aba Execucao, no formato do `main` do dono (B1).
PROJETO_EXEMPLO = REPO_ROOT / "engine/tests/fixtures/projeto_exemplo_behave"
PASTA_PROJETO = "/Users/qa/Projetos/projeto_exemplo_behave"
ID_PROJETO = "0a1b2c3d4e5f"
PASTA_EXECUCOES = "/Users/qa/Documents/Mo baile/Execuções/projeto-exemplo-behave"
RUN_ID = "20250905-000000-0a1b2c"

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


CHANGELOG_EXEMPLO = """# Changelog

## [9.9.0] - 2026-10-24

### Adicionado

- **Tela Início nova.** Boas-vindas, aparelho e recentes.
- **Tela Ambiente.** O diagnóstico de instalação, à parte.

## [9.8.0] - 2026-10-01

- **Antiga.** Não aparece.
"""


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
    # O gerador nao chama `configure_logging`: o caminho do log e o de um Mac
    # de referencia, para a suite Swift decodificar o campo preenchido.
    server.log_path = "/Users/qa/Library/Logs/Mo baile/engine.log"
    server.adb.emulator_path = "/Users/qa/Library/Android/sdk/emulator/emulator"
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
        # Tela Inicio: Android pronto e iOS sem o driver XCUITest, o caso que
        # mostra item faltando, proximo passo e area parcial de uma vez.
        server.setup = SetupService(
            adb=server.adb, appium=server.appium, scrcpy=server.scrcpy, system="macos",
            probe=Probe(
                which=lambda nome: f"/opt/homebrew/bin/{nome}" if nome in ("xcrun", "node", "swiftc") else None,
                is_file=lambda caminho: caminho.endswith("/usr/bin/simctl"),
                realpath=lambda c: "/opt/homebrew/lib/node_modules/appium/index.js" if c.endswith("/appium") else c,
                find_spec=lambda nome: object() if nome == "Quartz" else None,
                version_of={"Pillow": "11.3.0", "requests": "2.32.3"}.get,
                read_text=lambda caminho: '{"version": "2.11.0"}' if caminho.endswith("appium/package.json") else None,
                home="/Users/qa",
                environ={},
                python_version="3.12.7",
                python_path="/opt/homebrew/bin/python3",
            ),
        )
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


def arvore_projeto(call) -> dict:
    """`workspace.*` (PO-5) numa pasta de trabalho descartavel."""
    with tempfile.TemporaryDirectory() as tmp:
        home = pathlib.Path(tmp).resolve()
        raiz = home / "Documents" / "Mo baile"
        (raiz / "pages").mkdir(parents=True)
        (raiz / "flows").mkdir()
        (raiz / "pages" / "feature.py").write_bytes(b"def tocar(self):\r\n    pass\r\n")
        (raiz / "flows" / "login.yaml").write_bytes(b"appId: br.app\n")
        # mtime fixo na leitura; o da gravacao e o relogio, trocado abaixo.
        os.utime(raiz / "pages" / "feature.py", ns=(1757030000_000000000, 1757030000_000000000))
        with patch.dict(os.environ, {"HOME": str(home)}):
            saida = {
                "workspace.tree": call("workspace.tree"),
                "workspace.read": call("workspace.read", {"path": "pages/feature.py"}),
                "workspace.write": call("workspace.write", {
                    "path": "pages/feature.py", "text": "def tocar(self):\n    pass\n", "line_separator": "CRLF",
                    "expected_mtime_ns": 1757030000_000000000,
                }),
                "erro_workspace_file_changed": call("workspace.write", {
                    "path": "pages/feature.py", "text": "x", "expected_mtime_ns": 1,
                }),
            }
        saida["workspace.write"]["result"]["mtime_ns"] = 1757030001_000000000
        return _trocar_caminhos(saida, (str(raiz),), "/Users/qa/Documents/Mo baile")


def relatorio(server: EngineServer, call) -> dict:
    """`report.*` pelo servidor de verdade, sobre arquivos de verdade."""
    with tempfile.TemporaryDirectory() as tmp:
        pasta = pathlib.Path(tmp).resolve()
        server.report = ReportService(
            ocr=_OcrFalso(), documents_dir=pasta / "Mo baile", now=lambda: datetime.datetime(2026, 10, 8, 21, 30, 5)
        )
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
            # Depois da auditoria e do export: a edição regrava a spec.
            "report.card": call("report.card", {"spec_path": str(spec_path), "card_index": 2}),
            "report.card_update": call("report.card_update", {
                "spec_path": str(spec_path), "card_index": 1,
                "card": {"titulo": "Parcelas", "obs": "Conferido com produto"},
            }),
            "report.cards": call("report.cards", {"spec_path": str(spec_path)}),
            "report.cards_update": call("report.cards_update", {
                "spec_path": str(spec_path),
                "cards": [{"card_index": 0, "card": {"secao": "Home"}}],
            }),
        }
        importado = saida["report.import"].get("result") or {}
        saida["report.checklist_export"] = call("report.checklist_export", {
            "checklist_path": importado.get("checklist_path", ""),
        })
        return _trocar_caminhos(saida, (str(pasta), tmp), PASTA_RELATORIO)


class _AdbDoDoctor:
    """Aparelho falso do doctor: o emulador da config, com o app instalado."""

    def list_devices(self):
        return [("emulator-5554", "device")]

    def get_prop(self, serial, nome):
        return "14"

    def package_installed(self, serial, pacote):
        return True

    def uiautomation_holder(self, serial):
        return None


class _AppiumDoDoctor:
    # Caminho que nao existe: a versao e os drivers nao dependem do Mac de quem gera.
    def locate_appium(self):
        return "/opt/mobaile-fixture/bin/appium"

    def owns_server_on(self, porta):
        return True


def _python_do_projeto(args, timeout, env=None):
    """Python do projeto falso: versoes fixas, sem depender do Mac de quem gera."""
    if args[-3:] == ["-m", "pip", "check"]:
        return 0, "No broken requirements found.\n", ""
    if "importlib.metadata" in args[-1]:
        nomes = json.loads(args[-1].split("NOMES = ", 1)[1].split("\n", 1)[0])
        versoes = {"behave": "1.2.6", "Appium-Python-Client": "5.1.3", "selenium": "4.34.2"}
        return 0, json.dumps({n: versoes.get(n) for n in nomes}), ""
    return 0, "3.14.0\n", ""


def execucao(server: EngineServer, call) -> dict:
    """`project.*` (aba Execucao) sobre uma copia do projeto de exemplo.

    A copia mora numa pasta temporaria, entao o caminho e o id (sha1 do
    caminho) mudam a cada geracao: os dois sao trocados por valores fixos.
    """
    import shutil

    with tempfile.TemporaryDirectory() as tmp:
        pasta = pathlib.Path(tmp).resolve()
        raiz = pasta / "projeto_exemplo_behave"
        shutil.copytree(PROJETO_EXEMPLO, raiz, ignore=shutil.ignore_patterns("__pycache__"))
        server.projects = ProjectService(
            store=ProjectStore(pasta / "dados" / "projetos.json", clock=lambda: 1757030000.0),
            pycharm_options=pasta / "JetBrains",
            candidates=lambda: [{"path": "/usr/local/bin/python3", "version": "3.14.0", "behave": "1.2.6"}],
        )
        server.project_doctor = ProjectDoctor(
            adb=_AdbDoDoctor(), appium=_AppiumDoDoctor(), run=_python_do_projeto,
            port_open=lambda host, porta: True, appium_home=pasta / "appium",
        )
        projeto = call("project.open", {"path": str(raiz)})
        pid = projeto["result"]["project"]["id"]
        saida = {
            "project.open": projeto,
            "project.list": call("project.list"),
            "project.inspect": call("project.inspect", {"project_id": pid}),
            "project.doctor": call("project.doctor", {"project_id": pid, "device_id": "emulator-5554"}),
        }
        # Agora o interpretador da run configuration existe (um executavel
        # vazio): sem confianca, o doctor pula o que rodaria o Python do projeto.
        python_do_projeto = raiz / ".venv" / "bin" / "python"
        python_do_projeto.parent.mkdir(parents=True)
        python_do_projeto.write_text("#!/bin/sh\n")
        python_do_projeto.chmod(0o755)
        saida.update({
            "project.doctor_sem_confianca": call("project.doctor", {"project_id": pid, "device_id": "emulator-5554"}),
            "project.trust": call("project.trust", {"project_id": pid}),
            "project.doctor_confiavel": call("project.doctor", {"project_id": pid, "device_id": "emulator-5554"}),
        })
        saida["erro_hub_unknown"] = _hub_desconhecido(call, pasta)
        saida.update(_configuracao(call, pasta, raiz, pid))
        saida.update(_execucao_do_main(server, call, pasta, raiz, pid))
        saida["project.forget"] = call("project.forget", {"project_id": pid})
        saida = _trocar_caminhos(saida, (str(raiz),), PASTA_PROJETO)
        return _trocar_caminhos(saida, (pid,), ID_PROJETO)


def _hub_desconhecido(call, pasta: pathlib.Path) -> dict:
    """`run.start` de um projeto com o hub montado em tempo de execucao (B1-5)."""
    raiz = pasta / "projeto_hub_dinamico"
    (raiz / ".idea" / "runConfigurations").mkdir(parents=True)
    (raiz / "main.py").write_text(
        "import os\n\n"
        "config_android_HLG = {'platformName': 'Android', 'url': os.environ.get('HUB_URL')}\n\n\n"
        "def main_sem_args():\n    init(config_android_HLG)\n\n\n"
        "if __name__ == '__main__':\n    main_sem_args()\n", encoding="utf-8",
    )
    (raiz / ".idea" / "runConfigurations" / "main.xml").write_text(
        '<component name="ProjectRunConfigurationManager"><configuration name="main" '
        'type="PythonConfigurationType">'
        f'<option name="SDK_HOME" value="{sys.executable}" />'
        '<option name="SCRIPT_NAME" value="$PROJECT_DIR$/main.py" /></configuration></component>',
        encoding="utf-8",
    )
    pid = call("project.open", {"path": str(raiz)})["result"]["project"]["id"]
    erro = call("run.start", {"project_id": pid, "record_video": False, "trusted": True})
    call("project.forget", {"project_id": pid})
    return erro


def _configuracao(call, pasta: pathlib.Path, raiz: pathlib.Path, pid: str) -> dict:
    """`project.configure` (B1-4): sem interpretador, com `candidates`; depois o override manual.

    A run configuration sai de cena para o `inspect` cair no "nada achado". O
    interpretador escolhido e um executavel da pasta temporaria, trocado por
    um caminho fixo.
    """
    import shutil

    rc = raiz / ".idea" / "runConfigurations"
    guardada = pasta / "rc-guardada"
    shutil.move(str(rc), str(guardada))
    python = pasta / "venv-exemplo" / "bin" / "python"
    python.parent.mkdir(parents=True)
    python.write_text("#!/bin/sh\n")
    python.chmod(0o755)
    saida = {
        "project.inspect_sem_interpretador": call("project.inspect", {"project_id": pid}),
        "project.configure": call("project.configure", {"project_id": pid, "interpreter": str(python)}),
    }
    call("project.configure", {"project_id": pid, "interpreter": None})
    shutil.move(str(guardada), str(rc))
    return _trocar_caminhos(saida, (str(python),), "/Users/qa/.virtualenvs/exemplo/bin/python")


def _execucao_do_main(server: EngineServer, call, pasta: pathlib.Path, raiz: pathlib.Path, pid: str) -> dict:
    """`run.*` e as notificacoes `run.log`/`run.finished`, pelos caminhos de producao.

    `run.start` passa pelo servidor inteiro com o processo trocado por nada
    (o filho de verdade dependeria do Python de quem gera). As notificacoes
    saem de um `ProjectRun` real rodando um script que imprime o resumo do
    behave; a pasta, o relogio e o interpretador viram valores fixos.
    """
    from mobaile.services import project_run

    execucoes = pasta / "execucoes"
    interpretador_fixo = f"{PASTA_PROJETO}/.venv/bin/python"
    saida: dict[str, Any] = {"run.status": call("run.status"), "run.stop": call("run.stop")}
    saida["erro_project_not_trusted"] = call("run.start", {"project_id": pid, "record_video": False})

    xml = raiz / ".idea" / "runConfigurations" / "main.xml"
    xml.write_text(xml.read_text(encoding="utf-8").replace("$PROJECT_DIR$/.venv/bin/python", sys.executable),
                   encoding="utf-8")
    with patch.dict(os.environ, {"MOBAILE_RUNS_DIR": str(execucoes)}), \
            patch.object(project_run.ProjectRun, "start", lambda self: setattr(self, "started_at", 1757030000.0)):
        inicio = call("run.start", {"project_id": pid, "record_video": False, "trusted": True})
    resultado = inicio.get("result") or {}
    pasta_execucao = resultado.get("folder", "")
    run_id = resultado.get("run_id", "")
    inicio = _trocar_caminhos(inicio, (pasta_execucao,), f"{PASTA_EXECUCOES}/20250905-000000")
    inicio = _trocar_caminhos(inicio, (sys.executable,), interpretador_fixo)
    saida["run.start"] = _trocar_caminhos(inicio, (run_id,), RUN_ID)

    # Notificacoes de uma execucao real (script que imprime o resumo do behave).
    out = server._out
    out.seek(0)
    out.truncate()
    destino = execucoes / "notificacoes"
    destino.mkdir(parents=True)
    script = "; ".join(f"print({linha!r})" for linha in (
        "  Cenário: Abrir a home", "0 features passed, 1 failed, 0 skipped",
        "1 scenario passed, 1 failed, 0 skipped", "5 steps passed, 1 failed, 0 skipped, 0 undefined",
    ))
    execucao = project_run.ProjectRun(
        run_id=RUN_ID, project={"id": pid, "name": "projeto_exemplo_behave", "root": str(raiz)},
        command=[sys.executable, "-c", script], cwd=raiz, env=dict(os.environ), folder=destino, masks=[],
        video=project_run.NoVideo("Sem aparelho alvo: a execução segue sem vídeo."),
        on_line=lambda rid, linha: server.notify("run.log", {"run_id": rid, "line": linha}),
        on_finished=server._on_run_finished, expected_runs=1,
    )
    execucao.start()
    execucao.wait(30)
    avisos = [json.loads(linha) for linha in out.getvalue().splitlines() if linha.strip()]
    saida["notif_run.log"] = next(m for m in avisos if m.get("method") == "run.log"
                                  and m["params"]["line"].strip().startswith("Cenário"))
    fim = next(m for m in avisos if m.get("method") == "run.finished")
    fim["params"]["duration_s"] = 1.2
    saida["notif_run.finished"] = _trocar_caminhos(fim, (str(destino),), f"{PASTA_EXECUCOES}/20250905-000000")
    return saida


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
        # Hora de gravacao fixa: `recorded_at` e relogio, nao contrato.
        from types import SimpleNamespace

        from mobaile.services import codegen as codegen_mod

        with patch.object(codegen_mod, "time", SimpleNamespace(time=lambda: 1757030000.0)):
            fixtures["codegen.record"] = call("codegen.record", {"x": 60, "y": 45, "strategy": "position"})
        fixtures["codegen.steps"] = call("codegen.steps")
        fixtures["session.correlate"] = call("session.correlate", {"step_num": 1})
        with patch.object(server.adb, "take_screenshot", return_value=Image.new("RGB", (60, 120), "black")):
            fixtures["screen.capture"] = call("screen.capture", {"max_width": 30})
        with patch.object(server.adb, "get_screen_size", return_value=(1080, 2400)):
            fixtures["screen.size"] = call("screen.size")
        fixtures["stream.stats"] = call("stream.stats")
        fixtures["stream.pause"] = call("stream.pause")
        fixtures["stream.resume"] = call("stream.resume")
        # Perfis de desempenho (PERF-3): o estado inicial, um sinal quente que
        # leva ao leve (com a notificacao), e a volta ao automatico.
        fixtures["perf.status"] = call("perf.status")
        out.seek(0)
        out.truncate()
        fixtures["perf.signals"] = call("perf.signals", {
            "thermal": "serious", "low_power": False, "memory_pressure": "normal",
            "physical_memory_gb": 16, "arch": "arm64", "translated": False,
        })
        avisos = [json.loads(linha) for linha in out.getvalue().splitlines() if linha.strip()]
        fixtures["notif_perf.profile"] = next(m for m in avisos if m.get("method") == "perf.profile")
        fixtures["perf.set_preference"] = call("perf.set_preference", {"preference": "leve"})
        call("perf.set_preference", {"preference": "auto"})
        call("perf.signals", {"thermal": "nominal"})
        # Governador zerado e knobs do completo de volta, para o resto das
        # fixtures nao depender da ordem.
        server.perf = type(server.perf)()
        server._aplicar_knobs()
        fixtures["proxy.events"] = call("proxy.events")
        with patch.object(server.adb, "is_proxy_configured", return_value=False):
            fixtures["proxy.diagnose"] = call("proxy.diagnose")
        # Carimbo de relogio nao e contrato: fixo, para a conferencia nao oscilar.
        fixtures["proxy.diagnose"]["result"]["checked_at"] = 0
        fixtures["devices.list"] = call("devices.list")
        fixtures["erro_dominio"] = call("input.tap", {"x": -1, "y": 0})

        # Ambiente e inicializacao. Estes sete decodificam nos DTOs novos do
        # front, que ate agora compilavam sem nunca terem visto saida do motor.
        fixtures["diagnostics.check"] = call("diagnostics.check")
        fixtures["setup.check"] = call("setup.check")
        # Tela Inicio: recentes num arquivo descartavel com relogio fixo, e as
        # novidades de um CHANGELOG de exemplo, para a fixture nao mudar a cada
        # versao nem depender do historico de quem gera.
        with tempfile.TemporaryDirectory() as pasta_home:
            pasta_home = pathlib.Path(pasta_home)
            (pasta_home / "CHANGELOG.md").write_text(CHANGELOG_EXEMPLO, encoding="utf-8")
            server.home.recents = RecentStore(pasta_home / "recentes.json", clock=lambda: 1757030000.0)
            server.home.recents.record(
                "report", "Relatório · Demanda", "2 divergências · 42,9% conforme",
                "/Users/qa/Documents/Mo baile/specs/demanda.json",
            )
            server.home._changelog = lambda: pasta_home / "CHANGELOG.md"
            server.home._version = "9.9.0"
            fixtures["home.summary"] = call("home.summary")
        fixtures.update(arvore_projeto(call))
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

        # `stream.frame` capturado da emissao real do espelho, em PNG: o JPEG
        # muda de bytes entre versoes da libjpeg e a conferencia e por pixel.
        out.seek(0)
        out.truncate()
        with patch.object(server.adb, "take_screenshot", return_value=Image.new("RGB", (60, 120), "black")):
            call("stream.start", {"fps": 30, "max_width": 30, "format": "png"})
            import time as _time

            prazo = _time.monotonic() + 3
            quadro = None
            while quadro is None and _time.monotonic() < prazo:
                _time.sleep(0.05)
                quadro = next(
                    (json.loads(linha) for linha in out.getvalue().splitlines() if linha.strip() and '"stream.frame"' in linha),
                    None,
                )
            call("stream.stop")
        if quadro is None:
            raise RuntimeError("o espelho nao emitiu quadro para a fixture")
        for chave in ("fps", "capture_ms", "skipped"):
            quadro["params"][chave] = 0
        fixtures["notif_stream.frame"] = quadro

        # Execucao de fluxo, pelos mesmos helpers que os dois runners usam. Fica
        # o `flow.finished` de uma parada, que e o caso que o front antigo
        # confundia com falha (3.12.0).
        out.seek(0)
        out.truncate()
        server._notify_flow_step(2, 3)
        server._notify_flow_finished(False, "Automação cancelada.", True)
        avisos = [json.loads(linha) for linha in out.getvalue().splitlines() if linha.strip()]
        fixtures["notif_flow.step"] = next(m for m in avisos if m.get("method") == "flow.step")
        fixtures["notif_flow.finished"] = next(m for m in avisos if m.get("method") == "flow.finished")

    traffic = NetworkEvent(
        id=7, timestamp=1757030000.5, time_str="14:32:10.123", method="POST",
        url="https://api.exemplo.com.br/v2/pedido/simulacao", host="api.exemplo.com.br",
        path="/v2/pedido/simulacao", status_code=200, status_text="OK",
        request_headers={"Content-Type": "application/json", "Authorization": "«redigido» (32 chars)"},
        request_body='{"valor":1000}', response_headers={"Content-Type": "application/json"},
        response_body='{"parcelas":12}', duration_ms=182.7, protocol="HTTP/1.1",
        is_tunnel=False, error=None, request_bytes=14, response_bytes=15, body_truncated=False,
    )
    fixtures["notif_proxy.event"] = protocol.notification("proxy.event", traffic.to_dict())

    analytics = AnalyticsEvent(
        id=3, timestamp=1757030001.0, time_str="14:32:11.001", tag="FA", event_name="screen_view",
        params={"screen_name": "cadastro_demo", "step": 2, "first_open": True},
        raw_log="Logging event: screen_view", platform="android",
    )
    fixtures["notif_analytics.event"] = protocol.notification("analytics.event", analytics.to_dict())

    fixtures.update(relatorio(server, call))
    fixtures.update(execucao(server, call))

    server.shutdown()
    fixtures["erro_request_cancelled"] = cancelamento()
    return fixtures


def _render(fixtures: dict) -> str:
    return json.dumps(fixtures, ensure_ascii=False, indent=2) + "\n"


def _nome(caminho: pathlib.Path) -> str:
    try:
        return str(caminho.relative_to(REPO_ROOT))
    except ValueError:
        return str(caminho)


def _pixels(valor: str) -> str:
    """Identidade do PNG pelo conteudo: tamanho, modo e pixels.

    Os bytes do PNG mudam com a versao do Pillow/zlib (compressao), sem mudar
    a imagem; comparar bytes dava "desatualizado" so por trocar de maquina.
    """
    import base64
    import hashlib
    import io

    from PIL import Image

    with Image.open(io.BytesIO(base64.b64decode(valor))) as img:
        img.load()
        digest = hashlib.sha256(img.tobytes()).hexdigest()
        return f"png:{img.size[0]}x{img.size[1]}:{img.mode}:{digest}"


def _normalizar(valor):
    if isinstance(valor, dict):
        return {
            k: _pixels(v) if k in ("png_base64", "image_base64") and isinstance(v, str) and v else _normalizar(v)
            for k, v in valor.items()
        }
    if isinstance(valor, list):
        return [_normalizar(v) for v in valor]
    return valor


def check(destination: pathlib.Path) -> int:
    """0 se o arquivo e igual ao que o motor gera agora; 1 se nao."""
    gerado = build()
    try:
        atual = json.loads(destination.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"fixtures ausentes ou ilegiveis em {_nome(destination)}: {exc}", file=sys.stderr)
        print("Rode 'make fixtures' e faca o commit.", file=sys.stderr)
        return 1
    atual, gerado = _normalizar(atual), _normalizar(gerado)
    # O checklist em HTML traz a pasta dos prints, que fica num temporário
    # (`/var/folders/...` no Mac, `/tmp/...` no Linux): o tamanho em bytes muda
    # com o sistema, sem mudar o contrato. O resto do payload continua conferido.
    for dados in (atual, gerado):
        resultado = (dados.get("report.checklist_export") or {}).get("result")
        if isinstance(resultado, dict):
            resultado.pop("bytes", None)
    if _render(atual) == _render(gerado):
        print(f"fixtures em dia: {_nome(destination)}")
        return 0
    mudaram = sorted(k for k in atual.keys() | gerado.keys() if atual.get(k) != gerado.get(k))
    print(f"As fixtures do contrato estao desatualizadas em {_nome(destination)}.", file=sys.stderr)
    print(f"Chaves diferentes: {', '.join(mudaram)}", file=sys.stderr)
    print("Rode 'make fixtures' e faca o commit.", file=sys.stderr)
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="so confere; nao escreve")
    args = parser.parse_args(argv)
    # Gerar as fixtures salva Page Object e audita relatorio: os recentes da
    # tela Inicio iriam para o Mac de quem gera. Vao para uma pasta descartavel.
    os.environ["MOBAILE_DATA_DIR"] = tempfile.mkdtemp(prefix="mobaile-fixtures-")
    destination = FIXTURE_PATH
    if args.check:
        return check(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(_render(build()), encoding="utf-8")
    print(f"fixtures gravadas em {_nome(destination)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
