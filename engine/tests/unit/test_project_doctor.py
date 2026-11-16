"""Doctor do projeto do dono (B1-2): uma linha por checagem, sem mudar nada.

Os comandos externos (Python do projeto, adb, porta do Appium) são falsos:
o que se confere é a decisão de cada checagem e que nenhuma delas instala,
apaga ou reinicia coisa alguma.
"""

from __future__ import annotations

import json
import pathlib
import shutil
import sys

import pytest

from mobaile.services.project_doctor import CHECK_IDS, ProjectDoctor
from mobaile.services.projects import ProjectService, ProjectStore

EXEMPLO = pathlib.Path(__file__).resolve().parents[1] / "fixtures" / "projeto_exemplo_behave"
INSTALADOS = {"behave": "1.2.6", "pytest-bdd": None, "Appium-Python-Client": "5.1.3", "selenium": "4.34.2",
              "allure-behave": "2.16.0"}


class AdbFalso:
    def __init__(self, aparelhos=(("emulator-5554", "device"),), versao="14", pacotes=("br.com.exemplo.hlg",),
                 instrumentacao=None):
        self.aparelhos = list(aparelhos)
        self.versao = versao
        self.pacotes = set(pacotes)
        self.instrumentacao = instrumentacao
        self.comandos: list[list[str]] = []

    def list_devices(self):
        return self.aparelhos

    def get_prop(self, serial, nome):
        self.comandos.append(["getprop", serial, nome])
        return self.versao

    def package_installed(self, serial, pacote):
        self.comandos.append(["pm", serial, pacote])
        return pacote in self.pacotes

    def uiautomation_holder(self, serial):
        self.comandos.append(["dumpsys", serial])
        return self.instrumentacao


class AppiumFalso:
    def __init__(self, instalado=True, nosso=False):
        self.instalado = instalado
        self.nosso = nosso

    def locate_appium(self):
        return "/usr/local/bin/appium" if self.instalado else None

    def owns_server_on(self, porta):
        return self.nosso


class Executor:
    """Python do projeto falso: responde pelas versões de `INSTALADOS`."""

    def __init__(self, instalados=None, pip_check=(0, "No broken requirements found.\n", ""), versao="3.14.0"):
        self.instalados = dict(INSTALADOS if instalados is None else instalados)
        self.pip_check = pip_check
        self.versao = versao
        self.chamadas: list[list[str]] = []

    def __call__(self, args, timeout, env=None):
        self.chamadas.append(list(args))
        if args[-3:] == ["-m", "pip", "check"]:
            return self.pip_check
        codigo = args[-1]
        if "importlib.metadata" in codigo:
            nomes = json.loads(codigo.split("NOMES = ", 1)[1].split("\n", 1)[0])
            return 0, json.dumps({n: self.instalados.get(n) for n in nomes}), ""
        return 0, self.versao + "\n", ""


@pytest.fixture()
def projeto(tmp_path):
    destino = tmp_path / "projeto"
    shutil.copytree(EXEMPLO, destino)
    # Interpretador que existe: o run configuration aponta para ele.
    xml = destino / ".idea" / "runConfigurations" / "main.xml"
    xml.write_text(xml.read_text(encoding="utf-8").replace("$PROJECT_DIR$/.venv/bin/python", sys.executable),
                   encoding="utf-8")
    servico = ProjectService(store=ProjectStore(tmp_path / "projetos.json"), pycharm_options=tmp_path / "jb",
                             candidates=list)
    pid = servico.open(str(destino))["id"]
    # O doctor só roda o Python do projeto depois da confiança (D-O1).
    servico.trust(pid)
    return servico, pid, destino


def _doctor(adb=None, appium=None, executor=None, porta_aberta=True, appium_home=None):
    return ProjectDoctor(
        adb=adb or AdbFalso(), appium=appium or AppiumFalso(), ios=None,
        run=executor or Executor(), port_open=lambda host, porta: porta_aberta,
        appium_home=appium_home,
    )


def _por_id(resultado):
    return {c["id"]: c for c in resultado["checks"]}


@pytest.fixture()
def appium_home(tmp_path):
    raiz = tmp_path / "appium-home" / "node_modules"
    for nome, versao in (("appium-uiautomator2-driver", "4.2.3"), ("appium-xcuitest-driver", "9.9.0")):
        (raiz / nome).mkdir(parents=True)
        (raiz / nome / "package.json").write_text(json.dumps({"version": versao}))
    return tmp_path / "appium-home"


class TestDoctor:
    def test_todas_as_checagens_em_ordem_estavel(self, projeto, appium_home):
        servico, pid, _ = projeto
        resultado = _doctor(appium_home=appium_home).run(servico.analyze(pid))
        assert [c["id"] for c in resultado["checks"]] == list(CHECK_IDS)
        for checagem in resultado["checks"]:
            assert set(checagem) == {"id", "label", "state", "message", "hint", "needs_trust"}
            assert checagem["state"] in ("ok", "warn", "fail", "skip")
        assert set(resultado) == {"project_id", "checks", "summary", "ready", "trusted"}
        assert resultado["project_id"] == pid

    def test_projeto_de_exemplo_com_tudo_no_lugar_fica_pronto(self, projeto, appium_home):
        servico, pid, _ = projeto
        resultado = _doctor(appium_home=appium_home).run(servico.analyze(pid))
        estados = {c["id"]: c["state"] for c in resultado["checks"]}
        assert estados == {
            "interpreter": "ok", "packages": "ok", "requirements": "ok", "pip_check": "ok", "appium": "ok",
            "appium_port": "ok", "device": "ok", "app": "ok", "uiautomation": "ok", "cloud": "ok",
            "features": "ok",
        }, resultado
        assert resultado["ready"] is True
        assert resultado["summary"] == {"ok": 11, "warn": 0, "fail": 0, "skip": 0}
        assert "behave 1.2.6" in _por_id(resultado)["packages"]["message"]
        assert "Python 3.14.0" in _por_id(resultado)["interpreter"]["message"]

    def test_sem_interpretador_falha_e_pula_o_que_depende_dele(self, projeto, appium_home):
        servico, pid, destino = projeto
        shutil.rmtree(destino / ".idea")
        executor = Executor()
        checks = _por_id(_doctor(executor=executor, appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["interpreter"]["state"] == "fail"
        assert checks["interpreter"]["hint"]
        for dependente in ("packages", "requirements", "pip_check"):
            assert checks[dependente]["state"] == "skip"
        assert executor.chamadas == []

    def test_sem_behave_falha_e_sem_appium_client_avisa(self, projeto, appium_home):
        servico, pid, _ = projeto
        sem = dict(INSTALADOS, behave=None)
        checks = _por_id(_doctor(executor=Executor(sem), appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["packages"]["state"] == "fail"
        sem_cliente = dict(INSTALADOS, **{"Appium-Python-Client": None})
        checks = _por_id(_doctor(executor=Executor(sem_cliente), appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["packages"]["state"] == "warn"

    def test_requirements_com_versao_diferente_ou_ausente_avisa_sem_instalar(self, projeto, appium_home):
        servico, pid, _ = projeto
        executor = Executor(dict(INSTALADOS, behave="1.3.0", selenium=None))
        checks = _por_id(_doctor(executor=executor, appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["requirements"]["state"] == "warn"
        assert "behave" in checks["requirements"]["message"]
        assert "selenium" in checks["requirements"]["message"]
        assert not any("install" in " ".join(c) for c in executor.chamadas)

    def test_pip_check_quebrado_avisa(self, projeto, appium_home):
        servico, pid, _ = projeto
        executor = Executor(pip_check=(1, "selenium 4.34.2 has requirement urllib3<3, but you have urllib3 9.\n", ""))
        checks = _por_id(_doctor(executor=executor, appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["pip_check"]["state"] == "warn"
        assert "urllib3" in checks["pip_check"]["message"]

    def test_appium_ausente_falha_e_driver_ausente_avisa(self, projeto, tmp_path, appium_home):
        servico, pid, _ = projeto
        checks = _por_id(_doctor(appium=AppiumFalso(instalado=False), appium_home=appium_home)
                         .run(servico.analyze(pid)))
        assert checks["appium"]["state"] == "fail"
        checks = _por_id(_doctor(appium_home=tmp_path / "vazio").run(servico.analyze(pid)))
        assert checks["appium"]["state"] == "warn"
        assert "uiautomator2" in checks["appium"]["message"]

    def test_porta_do_appium(self, projeto, appium_home):
        servico, pid, _ = projeto
        plano = servico.analyze(pid)
        fechado = _por_id(_doctor(porta_aberta=False, appium_home=appium_home).run(plano))["appium_port"]
        assert fechado["state"] == "warn"
        assert "127.0.0.1:4723" in fechado["message"]
        nosso = _por_id(_doctor(appium=AppiumFalso(nosso=True), appium_home=appium_home).run(plano))["appium_port"]
        assert nosso["state"] == "ok"
        assert "Mo baile" in nosso["message"]

    def test_aparelho_da_config_desconectado_falha(self, projeto, appium_home):
        servico, pid, _ = projeto
        checks = _por_id(_doctor(adb=AdbFalso(aparelhos=[]), appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["device"]["state"] == "fail"
        assert "emulator-5554" in checks["device"]["message"]
        assert checks["app"]["state"] == "skip"
        assert checks["uiautomation"]["state"] == "skip"

    def test_aparelho_escolhido_diferente_da_config_avisa(self, projeto, appium_home):
        servico, pid, _ = projeto
        adb = AdbFalso(aparelhos=[("emulator-5554", "device"), ("SERIAL0003", "device")])
        checks = _por_id(_doctor(adb=adb, appium_home=appium_home).run(servico.analyze(pid), device_id="SERIAL0003"))
        assert checks["device"]["state"] == "warn"
        assert "emulator-5554" in checks["device"]["message"]

    def test_versao_do_android_diferente_avisa(self, projeto, appium_home):
        servico, pid, _ = projeto
        checks = _por_id(_doctor(adb=AdbFalso(versao="15"), appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["device"]["state"] == "warn"
        assert "15" in checks["device"]["message"]

    def test_app_nao_instalado_falha(self, projeto, appium_home):
        servico, pid, _ = projeto
        checks = _por_id(_doctor(adb=AdbFalso(pacotes=()), appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["app"]["state"] == "fail"

    def test_instrumentacao_de_outro_dono_avisa(self, projeto, appium_home):
        servico, pid, _ = projeto
        adb = AdbFalso(instrumentacao="dev.mobile.maestro.test")
        checks = _por_id(_doctor(adb=adb, appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["uiautomation"]["state"] == "warn"
        assert "force-stop" in checks["uiautomation"]["hint"]

    def test_config_ativa_na_nuvem_falha_e_nao_toca_porta_nem_aparelho(self, projeto, appium_home):
        servico, pid, destino = projeto
        main = (destino / "main.py").read_text(encoding="utf-8")
        main = main.replace("    init(config_android_local_HLG)\n", "    # init(config_android_local_HLG)\n")
        main = main.replace("    # init(config_kobiton_android_HLG)\n", "    init(config_kobiton_android_HLG)\n")
        (destino / "main.py").write_text(main, encoding="utf-8")
        portas = []
        adb = AdbFalso()
        doctor = ProjectDoctor(adb=adb, appium=AppiumFalso(), ios=None, run=Executor(),
                               port_open=lambda h, p: portas.append((h, p)) or True, appium_home=appium_home)
        resultado = doctor.run(servico.analyze(pid))
        checks = _por_id(resultado)
        assert checks["cloud"]["state"] == "fail"
        assert "api.kobiton.com" in checks["cloud"]["message"]
        assert checks["appium_port"]["state"] == "skip"
        assert portas == []
        assert resultado["ready"] is False
        assert "FAKE-KEY-0000" not in json.dumps(resultado)

    def test_feature_nao_encontrada_falha(self, projeto, appium_home):
        servico, pid, destino = projeto
        main = (destino / "main.py").read_text(encoding="utf-8")
        (destino / "main.py").write_text(main.replace("login/login.feature", "x/nao.feature"), encoding="utf-8")
        checks = _por_id(_doctor(appium_home=appium_home).run(servico.analyze(pid)))
        assert checks["features"]["state"] == "fail"
        assert "x/nao.feature" in checks["features"]["message"]

    def test_progresso_e_cancelamento(self, projeto, appium_home):
        servico, pid, _ = projeto
        mensagens = []
        _doctor(appium_home=appium_home).run(servico.analyze(pid), progress=lambda m, p=None: mensagens.append((m, p)))
        assert len(mensagens) == len(CHECK_IDS)
        assert mensagens[-1][1] == pytest.approx(100.0 * (len(CHECK_IDS) - 1) / len(CHECK_IDS))

        class Cancelado(Exception):
            pass

        def cancelar():
            raise Cancelado()

        with pytest.raises(Cancelado):
            _doctor(appium_home=appium_home).run(servico.analyze(pid), check_cancelled=cancelar)

    def test_python_do_projeto_nao_roda_na_pasta_do_projeto(self, projeto, appium_home):
        """`python -c` com cwd no projeto importaria um `json.py` do dono no lugar do da stdlib."""
        servico, pid, _ = projeto
        executor = Executor()
        _doctor(executor=executor, appium_home=appium_home).run(servico.analyze(pid))
        assert executor.chamadas
        for chamada in executor.chamadas:
            assert chamada[1] == "-E"


class TestAdbSoLeitura:
    """Os helpers novos do adb so leem e nao deixam texto livre chegar ao shell do aparelho."""

    def _adb(self, saida=b"", ret=0):
        from mobaile.adapters.adb import ADBBridge

        adb = ADBBridge(adb_path="/bin/false")
        adb.comandos = []

        def run(args, timeout=15):
            adb.comandos.append(args)
            return ret, saida, b""

        adb._run_cmd = run
        return adb

    def test_getprop(self):
        adb = self._adb(b"14\n")
        assert adb.get_prop("emulator-5554", "ro.build.version.release") == "14"
        assert adb.comandos == [["-s", "emulator-5554", "shell", "getprop", "ro.build.version.release"]]

    def test_pacote_instalado_e_exato(self):
        adb = self._adb(b"package:br.com.exemplo.hlg.debug\npackage:br.com.exemplo.hlg\n")
        assert adb.package_installed("emulator-5554", "br.com.exemplo.hlg") is True
        adb = self._adb(b"package:br.com.exemplo.hlg.debug\n")
        assert adb.package_installed("emulator-5554", "br.com.exemplo.hlg") is False
        assert self._adb(ret=1).package_installed("emulator-5554", "br.com.x") is None

    def test_texto_livre_e_recusado(self):
        from mobaile.domain.errors import InvalidInputError

        adb = self._adb()
        with pytest.raises(InvalidInputError):
            adb.get_prop("emulator-5554", "x; reboot")
        with pytest.raises(InvalidInputError):
            adb.package_installed("emulator-5554", "br.app && reboot")
        assert adb.comandos == []
