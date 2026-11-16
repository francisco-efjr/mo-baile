"""`run.*` pela fronteira: confiança, nuvem, trava do aparelho e behave real.

Duas famílias:

- Projeto mínimo, só com a biblioteca padrão, rodado pelo Python da suíte:
  confiança, recusa de nuvem, execução simultânea, trava do aparelho,
  `run.status`, `run.stop` e as notificações.
- O projeto de exemplo com o behave de verdade (`behave 1.2.6`), sem aparelho:
  passa, falha e `init` que lança. Pulado quando nenhum Python da máquina tem
  o behave (o `.venv` do motor não tem, de propósito).

Nenhum teste grava vídeo (`record_video: false`) nem fala com aparelho: o
emulador da config (`emulator-5554`) não precisa estar ligado.
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import unittest
from unittest.mock import patch

from mobaile.rpc.server import EngineServer

EXEMPLO = pathlib.Path(__file__).resolve().parents[1] / "fixtures" / "projeto_exemplo_behave"
SEGREDOS = ("FAKE-KEY-0000", "FAKE-SENHA-1234", "FAKE-TOKEN-9999")


def _python_com_behave() -> str | None:
    for candidato in ("/usr/local/bin/python3", "/opt/homebrew/bin/python3", shutil.which("python3")):
        if not candidato or not os.path.isfile(candidato):
            continue
        try:
            ret = subprocess.run([candidato, "-E", "-c", "import behave"], capture_output=True, timeout=20,
                                 cwd=tempfile.gettempdir(), check=False).returncode
        except (OSError, subprocess.TimeoutExpired):
            continue
        if ret == 0:
            return candidato
    return None


PYTHON_BEHAVE = _python_com_behave()


def _run_configuration(sdk: str, envs: dict[str, str]) -> str:
    linhas = "".join(f'      <env name="{nome}" value="{valor}" />\n' for nome, valor in envs.items())
    return textwrap.dedent(f"""\
        <component name="ProjectRunConfigurationManager">
          <configuration default="false" name="main" type="PythonConfigurationType" factoryName="Python">
            <envs>
        {linhas}    </envs>
            <option name="SDK_HOME" value="{sdk}" />
            <option name="WORKING_DIRECTORY" value="$PROJECT_DIR$" />
            <option name="SCRIPT_NAME" value="$PROJECT_DIR$/main.py" />
          </configuration>
        </component>
        """)


MAIN_MINIMO = '''\
import os
import time

config_android_local_HLG = {"platformName": "Android", "appium:udid": "emulator-5554",
                            "url": "http://127.0.0.1:4723", "senha": "FAKE-SENHA-1234"}
config_kobiton_android_HLG = {"platformName": "Android", "url": "https://u:FAKE-KEY-0000@api.kobiton.com/wd/hub"}


def init(config):
    print("init", flush=True)


def main_sem_args():
    init(config_android_local_HLG)
    # init(config_kobiton_android_HLG)
    print("token " + os.environ.get("TOKEN_MASSA", ""), flush=True)
    print("senha FAKE-SENHA-1234", flush=True)
    time.sleep(float(os.environ.get("DORMIR", "0")))
    print("1 feature passed, 0 failed, 0 skipped", flush=True)
    print("1 scenario passed, 0 failed, 0 skipped", flush=True)
    print("3 steps passed, 0 failed, 0 skipped, 0 undefined", flush=True)


if __name__ == "__main__":
    main_sem_args()
'''


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = pathlib.Path(self._tmp.name).resolve()
        self.execucoes = self.tmp / "execucoes"
        env = patch.dict(os.environ, {"MOBAILE_DATA_DIR": str(self.tmp / "dados"),
                                      "MOBAILE_RUNS_DIR": str(self.execucoes)})
        env.start()
        self.addCleanup(env.stop)
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.addCleanup(self.server.shutdown)
        self._fim = threading.Event()
        notify = self.server.notify

        def espiar(metodo, params):
            notify(metodo, params)
            if metodo == "run.finished":
                self._fim.set()

        self.server.notify = espiar

    def call(self, method, **params):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
        )

    def ok(self, method, **params):
        resposta = self.call(method, **params)
        self.assertNotIn("error", resposta, resposta)
        return resposta["result"]

    def erro(self, method, **params):
        resposta = self.call(method, **params)
        self.assertIn("error", resposta, resposta)
        return resposta["error"]["data"]

    def notificacoes(self, metodo):
        return [json.loads(linha)["params"] for linha in self.out.getvalue().splitlines()
                if f'"method": "{metodo}"' in linha or f'"method":"{metodo}"' in linha]

    def esperar_fim(self, prazo=60):
        self.assertTrue(self._fim.wait(prazo), "run.finished nao chegou")
        [fim] = self.notificacoes("run.finished")
        return fim

    def projeto_minimo(self, envs=None, main=MAIN_MINIMO):
        raiz = self.tmp / "projeto_minimo"
        (raiz / ".idea" / "runConfigurations").mkdir(parents=True)
        (raiz / "main.py").write_text(main, encoding="utf-8")
        (raiz / ".idea" / "runConfigurations" / "main.xml").write_text(
            _run_configuration(sys.executable, {"TOKEN_MASSA": "FAKE-TOKEN-9999", **(envs or {})}), encoding="utf-8",
        )
        return self.ok("project.open", path=str(raiz))["project"], raiz


class TestRunMinimo(Base):
    def test_projeto_nao_confiavel_e_recusado_com_codigo_proprio(self):
        projeto, _ = self.projeto_minimo()
        erro = self.erro("run.start", project_id=projeto["id"], record_video=False)
        self.assertEqual(erro["code"], "project_not_trusted")
        self.assertFalse(self.ok("run.status")["running"])
        self.assertFalse(self.ok("project.list")["projects"][0]["trusted"])

    def test_confiar_roda_e_marca_o_projeto(self):
        projeto, _ = self.projeto_minimo()
        inicio = self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        self.assertEqual(set(inicio), {"run_id", "project_id", "folder", "device_id", "platform", "config",
                                       "command", "video", "started_at"})
        self.assertEqual(inicio["device_id"], "emulator-5554")
        self.assertEqual(inicio["config"], "config_android_local_HLG")
        self.assertEqual(inicio["video"], {"mode": None, "warning": None})
        self.assertEqual(set(inicio["command"]), {"interpreter", "entry", "working_dir"})
        fim = self.esperar_fim()
        self.assertEqual(fim["status"], "passed")
        self.assertEqual(fim["run_id"], inicio["run_id"])
        self.assertTrue(self.ok("project.list")["projects"][0]["trusted"])
        pasta = pathlib.Path(fim["folder"])
        self.assertTrue(pasta.is_relative_to(self.execucoes))
        self.assertTrue((pasta / "console.log").is_file())
        self.assertTrue((pasta / "resumo.json").is_file())
        linhas = [n["line"] for n in self.notificacoes("run.log")]
        self.assertIn("init", linhas)
        self.assertTrue(all(n["run_id"] == inicio["run_id"] for n in self.notificacoes("run.log")))
        self.assertEqual(self.ok("run.status")["last"]["status"], "passed")

    def test_segredos_e_envs_nunca_saem(self):
        projeto, _ = self.projeto_minimo()
        self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        fim = self.esperar_fim()
        pasta = pathlib.Path(fim["folder"])
        tudo = self.out.getvalue() + (pasta / "console.log").read_text(encoding="utf-8")
        tudo += (pasta / "resumo.json").read_text(encoding="utf-8")
        tudo += (self.tmp / "dados" / "projetos.json").read_text(encoding="utf-8")
        log = pathlib.Path(os.environ["MOBAILE_LOG_DIR"]) / "engine.log"
        if log.exists():
            tudo += log.read_text(encoding="utf-8", errors="replace")
        for segredo in SEGREDOS:
            self.assertNotIn(segredo, tudo)
        self.assertIn("token ***", [n["line"] for n in self.notificacoes("run.log")])

    def test_config_ativa_na_nuvem_e_recusada(self):
        main = MAIN_MINIMO.replace("    init(config_android_local_HLG)\n    # init(config_kobiton_android_HLG)\n",
                                   "    # init(config_android_local_HLG)\n    init(config_kobiton_android_HLG)\n")
        projeto, _ = self.projeto_minimo(main=main)
        erro = self.erro("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        self.assertEqual(erro["code"], "invalid_input")
        self.assertIn("nuvem", erro["message"])
        self.assertIn("api.kobiton.com", erro["message"])
        self.assertNotIn("FAKE-KEY-0000", self.out.getvalue())
        self.assertFalse(self.ok("run.status")["running"])

    def test_trava_do_aparelho_durante_a_execucao_e_parada_com_netos(self):
        projeto, _ = self.projeto_minimo(envs={"DORMIR": "60"})
        self.ok("session.select_device", platform="android", device_id="emulator-5554")
        inicio = self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)

        estado = self.ok("run.status")
        self.assertTrue(estado["running"])
        self.assertEqual(set(estado["run"]), {"run_id", "project_id", "project_name", "device_id", "platform",
                                              "folder", "started_at", "elapsed_s", "lines", "video", "stopping"})

        for metodo, params in (("hierarchy.dump", {}), ("passive.start", {}), ("flow.run", {}),
                               ("flow.maestro_run", {"yaml": "appId: br.app\n---\n- launchApp\n"}),
                               ("codegen.record", {"x": 1, "y": 1}), ("input.tap", {"x": 1, "y": 1}),
                               ("input.text", {"text": "oi"}), ("recording.start", {})):
            with self.subTest(metodo=metodo):
                erro = self.erro(metodo, **params)
                self.assertEqual(erro["code"], "device_busy")
                self.assertIn("projeto_minimo", erro["message"])
        # Outro aparelho segue livre para inspecao.
        self.server._recusar_se_projeto_rodando("ZZ-outro-aparelho")

        segunda = self.erro("run.start", project_id=projeto["id"], record_video=False)
        self.assertEqual(segunda["code"], "device_busy")

        parada = self.ok("run.stop")
        self.assertEqual(parada["run_id"], inicio["run_id"])
        self.assertTrue(parada["stopped"])
        fim = self.esperar_fim(20)
        self.assertEqual(fim["status"], "cancelled")
        self.assertEqual(self.ok("run.stop"), {"running": False, "stopped": False, "run_id": None})
        self.assertFalse(self.ok("run.status")["running"])
        # Trava solta: nada recusa depois do fim.
        self.server._recusar_se_projeto_rodando("emulator-5554")

    def test_flow_rodando_impede_a_execucao(self):
        projeto, _ = self.projeto_minimo()
        self.server._flow_running = True
        try:
            erro = self.erro("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        finally:
            self.server._flow_running = False
        self.assertEqual(erro["code"], "device_busy")

    def test_sem_interpretador_e_recusado_antes_de_criar_pasta(self):
        projeto, raiz = self.projeto_minimo()
        shutil.rmtree(raiz / ".idea")
        erro = self.erro("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        self.assertEqual(erro["code"], "invalid_input")
        self.assertIn("interpretador", erro["message"])
        self.assertFalse(self.execucoes.exists())

    def test_parametros_invalidos(self):
        projeto, _ = self.projeto_minimo()
        for params in ({"record_video": "sim"}, {"trusted": "sim"}, {"device_id": "a b; reboot"}):
            with self.subTest(params=params):
                erro = self.erro("run.start", project_id=projeto["id"], **params)
                self.assertEqual(erro["code"], "invalid_input")
        self.assertEqual(self.erro("run.start", project_id="nao-existe")["code"], "invalid_input")

    def test_encerrar_o_motor_para_a_execucao(self):
        projeto, _ = self.projeto_minimo(envs={"DORMIR": "60"})
        self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        self.server.shutdown()
        fim = self.esperar_fim(20)
        self.assertEqual(fim["status"], "cancelled")


class TestRevisaoRpc(Base):
    """Correções da revisão da B1 vistas pela fronteira (D-O1, D-O3, D-O5, CR-03, CR-06)."""

    def test_project_trust_marca_e_devolve_o_projeto(self):
        projeto, _ = self.projeto_minimo()
        confiado = self.ok("project.trust", project_id=projeto["id"])["project"]
        self.assertTrue(confiado["trusted"])
        self.assertNotIn("trusted_with", confiado)
        self.assertEqual(self.erro("project.trust", project_id="nao-existe")["code"], "invalid_input")

    def test_hub_desconhecido_pede_confirmacao(self):
        main = MAIN_MINIMO.replace('"url": "http://127.0.0.1:4723"', '"url": os.environ.get("HUB")')
        projeto, _ = self.projeto_minimo(main=main)
        erro = self.erro("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        self.assertEqual(erro["code"], "hub_unknown")
        self.assertFalse(self.execucoes.exists())
        self.assertEqual(self.erro("run.start", project_id=projeto["id"], allow_unknown_hub="sim")["code"],
                         "invalid_input")
        self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True, allow_unknown_hub=True)
        self.assertEqual(self.esperar_fim()["status"], "passed")

    def test_aparelho_escolhido_diferente_do_udid_da_config_e_recusado(self):
        projeto, _ = self.projeto_minimo()
        erro = self.erro("run.start", project_id=projeto["id"], record_video=False, trusted=True,
                         device_id="ZZ-outro")
        self.assertEqual(erro["code"], "invalid_input")
        self.assertIn("emulator-5554", erro["message"])

    def test_trava_cobre_simulador_wda_e_scrcpy(self):
        projeto, _ = self.projeto_minimo(envs={"DORMIR": "60"})
        self.ok("session.select_device", platform="android", device_id="emulator-5554")
        self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        self.server.scrcpy.is_available = lambda: True
        for metodo, params in (("simulators.shutdown", {"udid": "emulator-5554"}),
                               ("wda.start", {"udid": "emulator-5554"}), ("scrcpy.start", {})):
            with self.subTest(metodo=metodo):
                self.assertEqual(self.erro(metodo, **params)["code"], "device_busy")
        self.ok("run.stop")
        self.esperar_fim(20)

    def test_trava_liga_antes_de_fechar_a_sessao_do_appium(self):
        """CR-03: um dump que chegasse durante o `delete_session` reabria a sessao do Mo baile."""
        projeto, _ = self.projeto_minimo()
        recusas = []

        def fechar():
            try:
                self.server._recusar_se_projeto_rodando("emulator-5554")
            except Exception as exc:
                recusas.append(type(exc).__name__)
            self.server.appium.session_id = None
            return True

        self.server.appium.session_id = "sessao-do-mo-baile"
        self.server.appium.session_udid = "emulator-5554"
        self.server.appium.delete_session = fechar
        self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        self.esperar_fim()
        self.assertEqual(recusas, ["DeviceBusyError"])
        self.assertIsNone(self.server._run_reserva)

    def test_encerrar_espera_o_fim_da_execucao(self):
        """CR-06: o shutdown espera a thread da execucao fechar o video."""
        projeto, _ = self.projeto_minimo(envs={"DORMIR": "60"})
        self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        execucao = self.server._project_run
        self.server.shutdown()
        self.assertTrue(execucao.wait(0))


def _hash(raiz: pathlib.Path) -> dict[str, str]:
    return {str(p.relative_to(raiz)): hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else "dir"
            for p in sorted(raiz.rglob("*"))}


@unittest.skipUnless(PYTHON_BEHAVE, "nenhum Python desta maquina tem o behave")
class TestRunComBehaveReal(Base):
    def projeto_exemplo(self, **envs):
        raiz = self.tmp / "projeto_exemplo_behave"
        shutil.copytree(EXEMPLO, raiz, ignore=shutil.ignore_patterns("__pycache__"))
        (raiz / ".idea" / "runConfigurations" / "main.xml").write_text(
            _run_configuration(PYTHON_BEHAVE, {"AMBIENTE": "HLG", "TOKEN_MASSA": "FAKE-TOKEN-9999", **envs}),
            encoding="utf-8",
        )
        return self.ok("project.open", path=str(raiz))["project"], raiz

    def rodar(self, **envs):
        projeto, raiz = self.projeto_exemplo(**envs)
        antes = _hash(raiz)
        self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        fim = self.esperar_fim(120)
        self.assertEqual(_hash(raiz), antes, "a execucao gravou algo na pasta do projeto")
        return fim

    def test_cenarios_que_passam_terminam_passed_com_console_ao_vivo(self):
        fim = self.rodar()
        self.assertEqual(fim["status"], "passed", fim)
        self.assertEqual(fim["counts"]["summaries"], 3)
        self.assertEqual(fim["counts"]["scenarios"]["passed"], 5)
        self.assertEqual(fim["exit_code"], 0)
        linhas = [n["line"] for n in self.notificacoes("run.log")]
        self.assertIn("[finish] sessao encerrada", linhas)
        self.assertTrue(any("Cenário: Abrir a home" in linha for linha in linhas))

    def test_cenario_que_falha_termina_failed(self):
        fim = self.rodar(EXEMPLO_CENARIO_FALHA="1")
        self.assertEqual(fim["status"], "failed", fim)
        self.assertEqual(fim["counts"]["scenarios"]["failed"], 1)
        self.assertEqual(fim["exit_code"], 0)

    def test_init_que_lanca_termina_indeterminate(self):
        fim = self.rodar(EXEMPLO_FALHAR_INIT="1")
        self.assertEqual(fim["status"], "indeterminate", fim)
        self.assertIn("Nao foi possivel abrir a sessao do Appium", fim["message"])
        self.assertIsNone(fim["counts"])

    def test_after_all_que_falha_termina_failed(self):
        """CR-01: o behave escreve "passed" no resumo, mas o after_all falhou."""
        fim = self.rodar(EXEMPLO_FALHAR_AFTER_ALL="1")
        self.assertEqual(fim["status"], "failed", fim)
        self.assertIn("HOOK-ERROR", fim["message"])

    def test_config_impressa_pelo_projeto_sai_mascarada(self):
        fim = self.rodar(EXEMPLO_IMPRIMIR_CONFIG="1")
        pasta = pathlib.Path(fim["folder"])
        tudo = self.out.getvalue() + (pasta / "console.log").read_text(encoding="utf-8")
        self.assertIn("senha_usuario_teste", tudo)
        for segredo in SEGREDOS:
            self.assertNotIn(segredo, tudo)

    def test_parar_no_meio_do_behave(self):
        projeto, _ = self.projeto_exemplo(EXEMPLO_DORMIR="2")
        self.ok("run.start", project_id=projeto["id"], record_video=False, trusted=True)
        limite = time.monotonic() + 30
        while not any("app aberto" in n["line"] for n in self.notificacoes("run.log")):
            self.assertLess(time.monotonic(), limite, "o behave nao comecou")
            time.sleep(0.1)
        self.assertTrue(self.ok("run.stop")["stopped"])
        fim = self.esperar_fim(20)
        self.assertEqual(fim["status"], "cancelled")
