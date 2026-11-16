"""Regressões da revisão independente da B1 (CR-01..11, SEC-B1-01..10, D-O1..D-O6).

Cada teste é uma prova dos relatórios em `docs/melhorias/2026-11-12-execucao-
projeto/revisao/` virada do avesso: passava quando o defeito existia e agora
confere a correção.
"""

from __future__ import annotations

import base64
import errno
import json
import os
import shutil
import sys
import textwrap
import time
from pathlib import Path

import pytest

from mobaile.adapters.scrcpy import ScrcpyRecording
from mobaile.domain.errors import InvalidInputError
from mobaile.services import project_run, projects
from mobaile.services.project_doctor import ProjectDoctor
from mobaile.services.project_run import BehaveSummary, ProjectRun
from mobaile.services.projects import ProjectService, ProjectStore

EXEMPLO = Path(__file__).resolve().parents[1] / "fixtures" / "projeto_exemplo_behave"

MAIN_PADRAO = """
from configs import *

def main_sem_args():
    init({cfg})

if __name__ == "__main__":
    main_sem_args()
"""


def _projeto(tmp: Path, main: str, configs: str | None = None, extra: dict[str, str] | None = None) -> Path:
    raiz = tmp / "proj"
    raiz.mkdir()
    (raiz / "main.py").write_text(textwrap.dedent(main), encoding="utf-8")
    if configs is not None:
        (raiz / "configs.py").write_text(textwrap.dedent(configs), encoding="utf-8")
    for rel, texto in (extra or {}).items():
        caminho = raiz / rel
        caminho.parent.mkdir(parents=True, exist_ok=True)
        caminho.write_text(textwrap.dedent(texto), encoding="utf-8")
    return raiz


def _servico(tmp: Path) -> ProjectService:
    return ProjectService(ProjectStore(tmp / "dados" / "projetos.json"), pycharm_options=tmp / "jb",
                          candidates=list)


def _plano(tmp: Path, raiz: Path):
    servico = _servico(tmp)
    return servico, servico.analyze(servico.open(str(raiz))["id"])


class _AdbFalso:
    def list_devices(self):
        return []


class _AppiumFalso:
    def locate_appium(self):
        return None

    def owns_server_on(self, _porta):
        return False


def _rc(sdk: str, envs: dict[str, str] | None = None) -> str:
    linhas = "".join(f'<env name="{n}" value="{v}" />' for n, v in (envs or {}).items())
    return (
        '<component name="ProjectRunConfigurationManager">'
        '<configuration name="main" type="PythonConfigurationType">'
        f"<envs>{linhas}</envs>"
        f'<option name="SDK_HOME" value="{sdk}" />'
        '<option name="SCRIPT_NAME" value="$PROJECT_DIR$/main.py" />'
        "</configuration></component>"
    )


CONFIG_LOCAL = 'config_local = {"url": "http://127.0.0.1:4723", "platformName": "Android"}\n'


# ------------------------------------------------- SEC-B1-01 / CR-02 / D-O1


class TestDoctorSemConfianca:
    def _python_falso(self, caminho: Path, marcador: Path) -> None:
        caminho.parent.mkdir(parents=True, exist_ok=True)
        caminho.write_text(f"#!/bin/sh\necho pwned > '{marcador}'\nexec {sys.executable} \"$@\"\n")
        caminho.chmod(0o755)

    def test_sdk_home_do_projeto_nao_roda_antes_da_confianca(self, tmp_path):
        marcador = tmp_path / "EXECUTOU.txt"
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), CONFIG_LOCAL,
                        {".idea/runConfigurations/main.xml": _rc("$PROJECT_DIR$/tools/python")})
        self._python_falso(raiz / "tools" / "python", marcador)
        servico, plano = _plano(tmp_path, raiz)
        doctor = ProjectDoctor(adb=_AdbFalso(), appium=_AppiumFalso(), port_open=lambda *_: False)
        resultado = doctor.run(plano)
        assert not marcador.exists()
        assert resultado["trusted"] is False
        por_id = {c["id"]: c for c in resultado["checks"]}
        for cid in ("interpreter", "packages", "requirements", "pip_check"):
            assert por_id[cid]["state"] == "skip", por_id[cid]
            assert por_id[cid]["needs_trust"] is True
            assert "Confiar" in por_id[cid]["hint"]
        assert por_id["features"]["needs_trust"] is False

        servico.trust(plano.project["id"])
        doctor.run(servico.analyze(plano.project["id"]))
        assert marcador.read_text().strip() == "pwned"

    def test_venv_do_projeto_tambem_nao_roda(self, tmp_path):
        marcador = tmp_path / "EXECUTOU-VENV.txt"
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), CONFIG_LOCAL,
                        {".venv/pyvenv.cfg": "home = /usr/bin\n"})
        self._python_falso(raiz / ".venv" / "bin" / "python", marcador)
        _, plano = _plano(tmp_path, raiz)
        assert plano.interpreter_source == "venv"
        ProjectDoctor(adb=_AdbFalso(), appium=_AppiumFalso(), port_open=lambda *_: False).run(plano)
        assert not marcador.exists()

    def test_doctor_nao_repassa_as_envs_do_projeto(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), CONFIG_LOCAL,
                        {".idea/runConfigurations/main.xml": _rc(sys.executable, {"DYLD_INSERT_LIBRARIES": "/x.dylib"})})
        servico, plano = _plano(tmp_path, raiz)
        servico.trust(plano.project["id"])
        vistos = []

        def executor(args, timeout, env=None):
            vistos.append(env or {})
            return 0, "3.14.0\n", ""

        ProjectDoctor(adb=_AdbFalso(), appium=_AppiumFalso(), run=executor,
                      port_open=lambda *_: False).run(servico.analyze(plano.project["id"]))
        assert vistos
        assert all("DYLD_INSERT_LIBRARIES" not in env for env in vistos)

    def test_saida_do_python_do_projeto_passa_pela_mascara(self, tmp_path):
        """SEC-B1-10: stderr do Python do projeto com segredo da config."""
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"),
                        'config_local = {"url": "http://127.0.0.1:4723", "senha": "SEGREDO-123"}\n',
                        {".idea/runConfigurations/main.xml": _rc(sys.executable)})
        servico, plano = _plano(tmp_path, raiz)
        servico.trust(plano.project["id"])

        def executor(args, timeout, env=None):
            return 1, "", "sitecustomize: SEGREDO-123\n"

        resultado = ProjectDoctor(adb=_AdbFalso(), appium=_AppiumFalso(), run=executor,
                                  port_open=lambda *_: False).run(servico.analyze(plano.project["id"]))
        assert "SEGREDO-123" not in json.dumps(resultado)


# ------------------------------------------------- SEC-B1-02 / CR-05 / CR-08 / D-O3


class TestHub:
    def test_hub_dinamico_e_desconhecido(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_remota_hlg"), """
            import os
            config_remota_hlg = {"url": os.environ.get("HUB_URL"), "platformName": "Android"}
        """)
        _, plano = _plano(tmp_path, raiz)
        assert plano.active_config.hub_state == "unknown"
        assert plano.hub_state == "unknown"
        assert plano.to_dict()["hub_reason"]

    def test_url_concatenada_e_desconhecida(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_hlg"), """
            HOST = "api.cloud-exemplo.com"
            config_hlg = {"url": "https://" + HOST + "/wd/hub", "platformName": "Android"}
        """)
        _, plano = _plano(tmp_path, raiz)
        assert plano.hub_state == "unknown"

    def test_url_de_nuvem_em_qualquer_chave_e_nuvem_e_o_hub_e_o_da_chave_de_hub(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_hlg"), """
            config_hlg = {
                "appium:proxy": "http://127.0.0.1:8888",
                "url": "https://u:k@api.cloud-exemplo.com/wd/hub",
                "platformName": "Android",
            }
        """)
        _, plano = _plano(tmp_path, raiz)
        assert plano.active_config.hub == "api.cloud-exemplo.com:443"
        assert plano.active_config.cloud is True
        assert plano.hub_state == "cloud"

    def test_alias_para_config_kobiton_e_nuvem(self, tmp_path):
        raiz = _projeto(tmp_path, """
            from configs import *

            def main_sem_args():
                cfg = config_kobiton_android_HLG
                init(cfg)
        """, 'config_kobiton_android_HLG = {"url": "https://u:k@api.kobiton.com/wd/hub"}\n')
        _, plano = _plano(tmp_path, raiz)
        assert plano.active_config.name == "config_kobiton_android_HLG"
        assert plano.hub_state == "cloud"

    def test_alias_para_config_local_e_desconhecido(self, tmp_path):
        raiz = _projeto(tmp_path, """
            from configs import *

            def main_sem_args():
                cfg = config_local
                init(cfg)
        """, CONFIG_LOCAL)
        _, plano = _plano(tmp_path, raiz)
        assert plano.hub_state == "unknown"

    def test_init_condicional_lista_os_dois_e_nuvem_ganha(self, tmp_path):
        raiz = _projeto(tmp_path, """
            import os
            from configs import *

            def main_sem_args():
                if os.environ.get("RODAR_LOCAL"):
                    init(config_android_local)
                else:
                    init(config_kobiton_android)
        """, """
            config_android_local = {"url": "http://127.0.0.1:4723", "platformName": "Android"}
            config_kobiton_android = {"url": "https://u:k@api.kobiton.com/wd/hub", "platformName": "Android"}
        """)
        _, plano = _plano(tmp_path, raiz)
        assert [(c.name, c.active) for c in plano.configs] == [
            ("config_android_local", True), ("config_kobiton_android", True)]
        assert plano.hub_state == "cloud"
        assert any("2 init" in p["message"] for p in plano.problems)

    def test_init_no_try_com_fallback_local_e_desconhecido(self, tmp_path):
        raiz = _projeto(tmp_path, """
            from configs import *

            def main_sem_args():
                try:
                    init(config_local)
                except Exception:
                    pass
        """, CONFIG_LOCAL)
        _, plano = _plano(tmp_path, raiz)
        assert plano.hub_state == "unknown"

    def test_config_nao_encontrada_e_desconhecida(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_sumida"), CONFIG_LOCAL)
        _, plano = _plano(tmp_path, raiz)
        assert plano.hub_state == "unknown"

    def test_um_init_simples_com_hub_local_e_local(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), CONFIG_LOCAL)
        _, plano = _plano(tmp_path, raiz)
        assert plano.hub_state == "local"

    def test_exemplo_continua_local(self, tmp_path):
        servico = _servico(tmp_path)
        resultado = servico.inspect(servico.open(str(EXEMPLO))["id"])
        assert resultado["hub_state"] == "local"
        assert resultado["hub_reason"] is None
        estados = {c["name"]: c["hub_state"] for c in resultado["configs"]}
        assert estados["config_kobiton_ios_HLG"] == "cloud"


# ------------------------------------------------- SEC-B1-03 (máscara)


class TestMascara:
    @pytest.mark.parametrize("chave", ["pwd", "pass", "passwd", "bs_pass", "kobiton:pwd", "apiSegredo", "sessionId",
                                       "session", "bearer", "apikey", "authorization", "Cookie"])
    def test_chaves_sensiveis(self, chave):
        assert projects._sensitive(chave) is True

    def test_env_curta_com_nome_sensivel_e_mascarada(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), CONFIG_LOCAL,
                        {".idea/runConfigurations/main.xml": _rc(sys.executable, {"KOBITON_PWD": "Ab#12"})})
        _, plano = _plano(tmp_path, raiz)
        assert project_run.mask_line("senha=Ab#12", plano.masks) == "senha=***"

    def test_basic_base64_e_repr_sao_mascarados(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_kobiton"), r"""
            config_kobiton = {
                "url": "https://usuario-falso:FAKE-KEY-0000@api.kobiton.com/wd/hub",
                "kobiton:username": "outro-usuario",
                "kobiton:accessKey": "a\\b-SEGREDO",
            }
        """)
        _, plano = _plano(tmp_path, raiz)
        basic = base64.b64encode(b"usuario-falso:FAKE-KEY-0000").decode()
        assert basic not in project_run.mask_line(f"Authorization: Basic {basic}", plano.masks)
        basic2 = base64.b64encode(b"outro-usuario:a\\b-SEGREDO").decode()
        assert basic2 not in project_run.mask_line(f"Basic {basic2}", plano.masks)
        linha = repr({"k": "a\\b-SEGREDO"})
        assert "SEGREDO" not in project_run.mask_line(linha, plano.masks)

    def test_constante_sensivel_do_arquivo_de_config_e_mascarada(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), """
            KOBITON_API_KEY = "FAKE-KEY-9999"
            config_local = {"url": "http://127.0.0.1:4723", "platformName": "Android"}
        """)
        _, plano = _plano(tmp_path, raiz)
        assert "FAKE-KEY-9999" in plano.masks


# ------------------------------------------------- SEC-B1-04 / CR-09, SEC-B1-05, SEC-B1-06


class TestAnaliseRobusta:
    def test_expressao_enorme_nao_derruba_a_analise(self, tmp_path):
        termos = " + ".join(["a"] * 5000)
        raiz = _projeto(tmp_path, f"""
from configs import *

def main_sem_args():
    init(config_local)
    x = f({termos})
""", CONFIG_LOCAL)
        _, plano = _plano(tmp_path, raiz)
        assert plano.active_config.name == "config_local"

    def test_recursion_error_vira_problema(self, tmp_path, monkeypatch):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), CONFIG_LOCAL)

        def estoura(*_a, **_k):
            raise RecursionError("maximum recursion depth exceeded")

        monkeypatch.setattr(ProjectService, "_read_main", estoura)
        servico = _servico(tmp_path)
        resultado = servico.inspect(servico.open(str(raiz))["id"])
        assert any("complexo" in p["message"] for p in resultado["problems"])

    def test_doctype_no_workspace_xml_e_ignorado(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), CONFIG_LOCAL, {
            ".idea/workspace.xml": """<?xml version="1.0"?>
<!DOCTYPE p [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]>
<project><component name="RunManager">&b;</component></project>
""",
        })
        servico = _servico(tmp_path)
        resultado = servico.inspect(servico.open(str(raiz))["id"])
        assert resultado["active_config"] == "config_local"

    def test_pasta_trocada_por_link_entre_conferir_e_abrir_nao_e_atravessada(self, tmp_path, monkeypatch):
        raiz = tmp_path / "proj"
        (raiz / "pkg").mkdir(parents=True)
        (raiz / "pkg" / "conf.py").write_text("x = 'DE DENTRO'\n")
        fora = tmp_path / "fora"
        fora.mkdir()
        (fora / "conf.py").write_text("x = 'DE FORA DO PROJETO'\n")
        abrir_real = os.open

        def abrir_com_corrida(caminho, flags, *a, **k):
            if caminho == "pkg" and not (raiz / "pkg.velho").exists():
                # Outro processo troca a pasta por um link no meio da leitura.
                os.rename(raiz / "pkg", raiz / "pkg.velho")
                os.symlink(fora, raiz / "pkg")
            return abrir_real(caminho, flags, *a, **k)

        monkeypatch.setattr(projects.os, "open", abrir_com_corrida)
        with pytest.raises(projects.ProjectFileError):
            projects.read_project_text(raiz, "pkg/conf.py")


# ------------------------------------------------- D-O2 (impressão da confiança), D-O6


class TestConfianca:
    def _copia(self, tmp_path):
        destino = tmp_path / "projeto"
        shutil.copytree(EXEMPLO, destino)
        return destino

    def test_mudar_o_sdk_da_run_configuration_zera_a_confianca(self, tmp_path):
        destino = self._copia(tmp_path)
        servico = _servico(tmp_path)
        pid = servico.open(str(destino))["id"]
        assert servico.trust(pid)["trusted"] is True
        assert servico.analyze(pid).project["trusted"] is True
        xml = destino / ".idea" / "runConfigurations" / "main.xml"
        xml.write_text(xml.read_text(encoding="utf-8").replace("$PROJECT_DIR$/.venv/bin/python", "/outro/python"),
                       encoding="utf-8")
        plano = servico.analyze(pid)
        assert plano.project["trusted"] is False
        assert servico.get(pid)["trusted"] is False
        assert any("interpretador" in p["message"] for p in plano.problems)

    def test_nova_env_e_configure_tambem_zeram(self, tmp_path):
        destino = self._copia(tmp_path)
        servico = _servico(tmp_path)
        pid = servico.open(str(destino))["id"]
        servico.trust(pid)
        assert servico.configure(pid, interpreter=sys.executable)["project"]["trusted"] is False
        servico.trust(pid)
        xml = destino / ".idea" / "runConfigurations" / "main.xml"
        xml.write_text(xml.read_text(encoding="utf-8").replace(
            '<env name="AMBIENTE" value="HLG" />', '<env name="AMBIENTE" value="HLG" /><env name="NOVA" value="1" />'),
            encoding="utf-8")
        assert servico.inspect(pid)["project"]["trusted"] is False

    def test_impressao_nao_sai_no_rpc(self, tmp_path):
        servico = _servico(tmp_path)
        pid = servico.open(str(EXEMPLO))["id"]
        projeto = servico.trust(pid)
        assert "trusted_with" not in projeto
        assert "trusted_with" not in servico.inspect(pid)["project"]
        assert all("trusted_with" not in p for p in servico.list())

    def test_project_dir_nas_envs(self, tmp_path):
        raiz = _projeto(tmp_path, MAIN_PADRAO.format(cfg="config_local"), CONFIG_LOCAL,
                        {".idea/runConfigurations/main.xml": _rc(sys.executable, {"DADOS": "$PROJECT_DIR$/dados"})})
        _, plano = _plano(tmp_path, raiz)
        assert plano.env["DADOS"] == f"{raiz.resolve()}/dados"


# ------------------------------------------------- CR-01 / D-O4 (resultado)


class TestResultado:
    RESUMO_OK = ("1 feature passed, 0 failed, 0 skipped", "2 scenarios passed, 0 failed, 0 skipped",
                 "2 steps passed, 0 failed, 0 skipped, 0 undefined")

    def _status(self, linhas):
        resumo = BehaveSummary()
        for linha in linhas:
            resumo.feed(linha)
        return resumo.status()

    def test_hook_error_no_after_all_falha(self):
        assert self._status(["HOOK-ERROR in after_all: RuntimeError: driver.quit falhou", "ABORTED: By user.",
                             *self.RESUMO_OK]) == "failed"

    def test_cleanup_error_falha(self):
        assert self._status(["CLEANUP-ERROR in boom: RuntimeError: limpeza falhou", *self.RESUMO_OK]) == "failed"

    def test_errored_no_resumo_falha(self):
        assert self._status(["1 feature passed, 0 failed, 0 skipped", "1 scenario passed, 0 failed, 1 errored",
                             "2 steps passed, 0 failed"]) == "failed"

    def test_palavra_desconhecida_no_resumo_e_indeterminado(self):
        assert self._status(["1 feature passed, 0 failed, 0 skipped, 0 hook_error", *self.RESUMO_OK[1:]]) \
            == "indeterminate"

    def test_aborted_sozinho_e_indeterminado(self):
        assert self._status(["ABORTED: By user.", *self.RESUMO_OK]) == "indeterminate"

    def test_resumo_lido_cru_antes_da_mascara(self, tmp_path):
        corpo = "".join(f"print({linha!r})\n" for linha in (
            "0 features passed, 1 failed, 0 skipped", "0 scenarios passed, 100 failed, 0 skipped",
            "0 steps passed, 100 failed, 0 skipped, 0 undefined"))
        _, linhas, fim, _ = _rodar(tmp_path, corpo, masks=["100"])
        assert fim[0]["status"] == "failed"
        assert all("100 failed" not in linha for linha in linhas)


# ------------------------------------------------- execução: CR-04, CR-07, CR-10, CR-11


def _rodar(tmp_path, corpo, *, masks=(), esperar=True, pasta_nome="execucao"):
    entrada = tmp_path / f"{pasta_nome}.py"
    entrada.write_text(textwrap.dedent(corpo), encoding="utf-8")
    pasta = tmp_path / pasta_nome
    pasta.mkdir()
    linhas: list[str] = []
    fim: list[dict] = []
    execucao = ProjectRun(
        run_id="r1", project={"id": "abc", "name": "exemplo"}, command=[sys.executable, str(entrada)],
        cwd=tmp_path, env={**os.environ, "PYTHONUNBUFFERED": "1"}, folder=pasta, masks=list(masks), video=None,
        on_line=lambda rid, linha: linhas.append(linha), on_finished=fim.append,
    )
    execucao.start()
    if esperar:
        assert execucao.wait(60), "a execucao nao terminou"
    return execucao, linhas, fim, pasta


class _ConsoleCheio:
    def write(self, _dados):
        raise OSError(errno.ENOSPC, "No space left on device")

    def flush(self):
        pass

    def close(self):
        pass


class TestExecucaoRobusta:
    def test_disco_cheio_no_console_nao_trava_nem_impede_o_stop(self, tmp_path):
        corpo = """
            import sys, time
            for i in range(20000):
                print("linha", i, "x" * 40)
            sys.stdout.flush()
            time.sleep(60)
        """
        execucao, linhas, fim, _ = _rodar(tmp_path, corpo, esperar=False)
        execucao._console = _ConsoleCheio()
        limite = time.monotonic() + 20
        while not any(linha.startswith("linha 19999") for linha in linhas):
            assert time.monotonic() < limite, "a leitora parou de drenar o pipe"
            time.sleep(0.05)
        assert any("Não consegui gravar o console.log" in linha for linha in linhas)
        assert execucao.stop() is True
        assert execucao.wait(15)
        assert fim[0]["status"] == "cancelled"

    def test_stop_depois_que_o_processo_saiu_nao_vira_cancelled(self, tmp_path, monkeypatch):
        monkeypatch.setattr(project_run, "DRAIN_AFTER_EXIT_S", 2.0)
        corpo = """
            import subprocess
            subprocess.Popen(["sleep", "30"])
            print("0 features passed, 1 failed, 0 skipped", flush=True)
            print("0 scenarios passed, 1 failed, 0 skipped", flush=True)
            print("2 steps passed, 1 failed, 0 skipped, 0 undefined", flush=True)
        """
        execucao, _, fim, _ = _rodar(tmp_path, corpo, esperar=False)
        limite = time.monotonic() + 10
        while execucao._process.poll() is None:
            assert time.monotonic() < limite
            time.sleep(0.02)
        assert execucao.stop() is False
        assert execucao.wait(20)
        assert fim[0]["status"] == "failed"
        assert fim[0]["counts"]["scenarios"]["failed"] == 1

    def test_console_volumoso_e_lido_com_buffer(self, tmp_path):
        corpo = """
            import sys
            for i in range(100000):
                sys.stdout.write("linha %d %s\\n" % (i, "y" * 60))
        """
        inicio = time.monotonic()
        _, linhas, fim, _ = _rodar(tmp_path, corpo)
        assert time.monotonic() - inicio < 20
        assert fim[0]["exit_code"] == 0
        assert sum(1 for linha in linhas if linha.startswith("linha ")) == 100000

    def test_gravacao_do_scrcpy_mora_no_adapter_e_valida_o_serial(self, tmp_path):
        gravacao = ScrcpyRecording("/usr/local/bin/scrcpy", "emulator-5554", tmp_path / "video.mp4")
        assert gravacao.command()[:3] == ["/usr/local/bin/scrcpy", "-s", "emulator-5554"]
        with pytest.raises(InvalidInputError):
            ScrcpyRecording("/usr/local/bin/scrcpy", "-x; reboot", tmp_path / "video.mp4")


# ------------------------------------------------- B1-6: início do vídeo pelo servidor do scrcpy


def _scrcpy_falso(tmp_path: Path, atraso: float | None, sair: bool = False) -> str:
    """Executável que imita o scrcpy: anuncia o servidor (ou não) e grava o MP4 no SIGINT."""
    anuncio = (f'sleep {atraso}; echo "[server] INFO: Device: [Google] falso (Android 15)"'
               if atraso is not None else ":")
    corpo = f"""#!/bin/sh
for a; do case "$a" in --record=*) f="${{a#--record=}}";; esac; done
{"echo 'ERROR: Could not find any ADB device' >&2; exit 1" if sair else ""}
trap 'echo mp4 > "$f"; exit 0' INT
{anuncio}
while true; do sleep 0.05; done
"""
    caminho = tmp_path / "scrcpy-falso"
    caminho.write_text(corpo)
    caminho.chmod(0o755)
    return str(caminho)


class TestInicioDoVideo:
    def test_espera_o_servidor_conectar_e_nao_um_tempo_fixo(self, tmp_path):
        gravacao = ScrcpyRecording(_scrcpy_falso(tmp_path, 0.8), "emulator-5554", tmp_path / "video.mp4")
        antes = time.time()
        gravacao.start()
        assert gravacao.warning is None
        # Depois do anúncio (0,8 s) e da folga de 0,2 s; um sleep fixo de 0,5 s erraria.
        assert gravacao.started_at - antes >= 0.95
        assert gravacao.stop() == tmp_path / "video.mp4"

    def test_sem_o_anuncio_segue_com_aviso(self, tmp_path, monkeypatch):
        from mobaile.adapters import scrcpy

        monkeypatch.setattr(scrcpy, "RECORD_READY_TIMEOUT_S", 0.5)
        gravacao = ScrcpyRecording(_scrcpy_falso(tmp_path, None), "emulator-5554", tmp_path / "video.mp4")
        gravacao.start()
        assert "não confirmou o início" in gravacao.warning
        assert gravacao.started_at is not None
        assert gravacao.stop() == tmp_path / "video.mp4"
        assert "não confirmou o início" in gravacao.warning

    def test_scrcpy_que_sai_na_hora_e_erro_com_o_motivo(self, tmp_path):
        from mobaile.domain.errors import EngineError

        gravacao = ScrcpyRecording(_scrcpy_falso(tmp_path, None, sair=True), "emulator-5554", tmp_path / "v.mp4")
        with pytest.raises(EngineError, match="Could not find any ADB device"):
            gravacao.start()

    def test_resumo_grava_video_started_at(self, tmp_path):
        alvo = tmp_path / "execucao" / "video.mp4"

        class VideoFalso:
            mode = "scrcpy"
            warning = None
            started_at = None

            def start(self):
                self.started_at = 1757030001.5

            def stop(self):
                alvo.write_bytes(b"mp4")
                return alvo

        entrada = tmp_path / "main.py"
        entrada.write_text("print('ok')\n")
        pasta = tmp_path / "execucao"
        pasta.mkdir()
        execucao = ProjectRun(
            run_id="r", project={"id": "a", "name": "x"}, command=[sys.executable, str(entrada)], cwd=tmp_path,
            env=dict(os.environ), folder=pasta, masks=[], video=VideoFalso(),
            on_line=lambda *_: None, on_finished=lambda _: None,
        )
        execucao.start()
        assert execucao.wait(30)
        resumo = json.loads((pasta / "resumo.json").read_text(encoding="utf-8"))
        assert resumo["video_started_at"] == 1757030001.5
