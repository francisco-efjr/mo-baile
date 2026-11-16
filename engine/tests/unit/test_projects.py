"""Projetos de automação do dono: registro e análise estática (B1-1).

O Mo baile lê o projeto sem importar nem executar nada dele, e nunca grava na
pasta do projeto. Os testes usam o projeto de exemplo versionado em
`engine/tests/fixtures/projeto_exemplo_behave`, no formato do `main` do dono.
"""

from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import sys

import pytest

from mobaile.domain.errors import InvalidInputError
from mobaile.services import projects
from mobaile.services.projects import ProjectService, ProjectStore

EXEMPLO = pathlib.Path(__file__).resolve().parents[1] / "fixtures" / "projeto_exemplo_behave"
SEGREDOS = ("FAKE-KEY-0000", "FAKE-SENHA-1234", "FAKE-TOKEN-9999", "usuario-falso")


def _hash_da_pasta(raiz: pathlib.Path) -> dict[str, str]:
    resultado = {}
    for caminho in sorted(raiz.rglob("*")):
        rel = str(caminho.relative_to(raiz))
        if caminho.is_symlink():
            resultado[rel] = "link:" + os.readlink(caminho)
        elif caminho.is_file():
            resultado[rel] = hashlib.sha256(caminho.read_bytes()).hexdigest()
        else:
            resultado[rel] = "dir"
    return resultado


CANDIDATOS = [{"path": "/usr/local/bin/python3", "version": "3.14.0", "behave": "1.2.6"}]


@pytest.fixture()
def jetbrains(tmp_path):
    return tmp_path / "JetBrains"


@pytest.fixture()
def servico(tmp_path, jetbrains):
    return ProjectService(store=ProjectStore(tmp_path / "dados" / "projetos.json", clock=lambda: 1757030000.0),
                          pycharm_options=jetbrains, candidates=lambda: [dict(c) for c in CANDIDATOS])


@pytest.fixture()
def copia(tmp_path):
    destino = tmp_path / "projeto"
    shutil.copytree(EXEMPLO, destino)
    return destino


# ---------------------------------------------------------------- registro


class TestRegistro:
    def test_abrir_registra_com_id_estavel_e_entrada_detectada(self, servico):
        projeto = servico.open(str(EXEMPLO))
        assert projeto["root"] == str(EXEMPLO.resolve())
        assert projeto["name"] == "projeto_exemplo_behave"
        assert projeto["entry"] == "main.py"
        assert projeto["trusted"] is False
        assert projeto["opened_at"] == 1757030000.0
        assert len(projeto["id"]) == 12
        assert servico.open(str(EXEMPLO))["id"] == projeto["id"]
        assert [p["id"] for p in servico.list()] == [projeto["id"]]

    def test_registro_persiste_em_projetos_json(self, servico, tmp_path):
        projeto = servico.open(str(EXEMPLO))
        arquivo = tmp_path / "dados" / "projetos.json"
        dados = json.loads(arquivo.read_text(encoding="utf-8"))
        assert dados["projects"][0]["id"] == projeto["id"]
        outro = ProjectService(store=ProjectStore(arquivo))
        assert outro.list()[0]["root"] == projeto["root"]

    def test_confiar_fica_registrado_e_reabrir_nao_desfaz(self, servico):
        projeto = servico.open(str(EXEMPLO))
        servico.trust(projeto["id"])
        assert servico.get(projeto["id"])["trusted"] is True
        assert servico.open(str(EXEMPLO))["trusted"] is True

    def test_esquecer(self, servico):
        projeto = servico.open(str(EXEMPLO))
        assert servico.forget(projeto["id"]) is True
        assert servico.list() == []
        assert servico.forget(projeto["id"]) is False

    def test_pasta_inexistente_ou_arquivo_e_recusada(self, servico, tmp_path):
        with pytest.raises(InvalidInputError):
            servico.open(str(tmp_path / "nao-existe"))
        arquivo = tmp_path / "x.py"
        arquivo.write_text("print(1)\n")
        with pytest.raises(InvalidInputError):
            servico.open(str(arquivo))

    def test_projeto_desconhecido_e_invalid_input(self, servico):
        with pytest.raises(InvalidInputError):
            servico.get("abc")

    def test_pasta_sem_entrada_ainda_abre_mas_inspect_aponta_o_problema(self, servico, tmp_path):
        vazia = tmp_path / "vazio"
        vazia.mkdir()
        projeto = servico.open(str(vazia))
        assert projeto["entry"] is None
        resultado = servico.inspect(projeto["id"])
        assert resultado["entry"]["found"] is False
        assert resultado["problems"]

    def test_entrada_alternativa_pela_funcao_main_sem_args(self, servico, tmp_path):
        pasta = tmp_path / "alt"
        pasta.mkdir()
        (pasta / "rodar_testes.py").write_text("def main_sem_args():\n    pass\n")
        (pasta / "util.py").write_text("X = 1\n")
        assert servico.open(str(pasta))["entry"] == "rodar_testes.py"


# ---------------------------------------------------------- análise estática


class TestAnalise:
    def test_main_config_ativa_e_alternativas_comentadas(self, servico):
        resultado = servico.inspect(servico.open(str(EXEMPLO))["id"])
        assert resultado["entry"] == {"file": "main.py", "function": "main_sem_args", "found": True}
        assert resultado["active_config"] == "config_android_local_HLG"
        nomes = [(c["name"], c["active"]) for c in resultado["configs"]]
        assert nomes == [
            ("config_android_local_HLG", True),
            ("config_ios_local_HLG", False),
            ("config_kobiton_android_HLG", False),
            ("config_kobiton_ios_HLG", False),
        ]

    def test_valores_so_das_chaves_permitidas_e_selo_local_ou_nuvem(self, servico):
        resultado = servico.inspect(servico.open(str(EXEMPLO))["id"])
        por_nome = {c["name"]: c for c in resultado["configs"]}
        android = por_nome["config_android_local_HLG"]
        assert android["found"] is True
        assert android["file"] == "configs.py"
        assert android["platform"] == "android"
        assert android["values"] == {
            "platformName": "Android", "automationName": "UiAutomator2", "udid": "emulator-5554",
            "deviceName": "Pixel 7 (emulador)", "platformVersion": "14",
            "appPackage": "br.com.exemplo.hlg", "appActivity": ".MainActivity",
        }
        assert android["hub"] == "127.0.0.1:4723"
        assert android["cloud"] is False
        assert "senha_usuario_teste" in android["keys"]
        assert "appium:noReset" in android["keys"]

        ios = por_nome["config_ios_local_HLG"]
        assert ios["platform"] == "ios"
        assert ios["hub"] == "localhost:4723"
        assert ios["cloud"] is False
        assert ios["values"]["app"] == "builds/Exemplo-HLG.app"
        assert ios["values"]["bundleId"] == "br.com.exemplo.hlg"

        kobiton = por_nome["config_kobiton_android_HLG"]
        assert kobiton["hub"] == "api.kobiton.com:443"
        assert kobiton["cloud"] is True
        assert "kobiton:accessKey" in kobiton["keys"]
        assert por_nome["config_kobiton_ios_HLG"]["cloud"] is True

    def test_segredos_nunca_saem_na_analise_nem_no_registro(self, servico, tmp_path):
        projeto = servico.open(str(EXEMPLO))
        texto = json.dumps(servico.inspect(projeto["id"]), ensure_ascii=False)
        texto += (tmp_path / "dados" / "projetos.json").read_text(encoding="utf-8")
        for segredo in SEGREDOS:
            assert segredo not in texto

    def test_suites_em_ordem_com_features_e_cenarios(self, servico):
        resultado = servico.inspect(servico.open(str(EXEMPLO))["id"])
        assert [s["name"] for s in resultado["suites"]] == [
            "test_suite_time_01", "test_suite_time_02", "test_suite_time_03",
        ]
        primeira = resultado["suites"][0]
        assert primeira["defined"] is True
        execucao = primeira["runs"][0]
        assert execucao["squad"] == "time_01"
        assert execucao["feature"] == "teste/teste.feature"
        assert execucao["found"] is True
        assert execucao["path"] == "features/teste/teste.feature"
        assert execucao["title"] == "Navegação básica do app de exemplo"
        assert execucao["scenarios"] == ["Abrir a home", "Abrir o extrato"]
        login = resultado["suites"][1]["runs"][0]
        assert login["title"] == "Login no ambiente HLG"
        assert login["scenarios"] == ["Entrar com usuario de teste"]
        assert resultado["unused_suites"] == ["test_suite_canais"]
        assert resultado["problems"] == []

    def test_esquema_do_cenario_em_portugues(self):
        texto = (EXEMPLO / "features" / "canais" / "canais.feature").read_text(encoding="utf-8")
        titulo, cenarios = projects.parse_feature_text(texto)
        assert titulo == "Canais"
        assert cenarios == ["Abrir o canal <canal>"]

    def test_interpretador_e_variaveis_da_run_configuration(self, servico):
        resultado = servico.inspect(servico.open(str(EXEMPLO))["id"])
        raiz = str(EXEMPLO.resolve())
        assert resultado["interpreter"] == {
            "path": f"{raiz}/.venv/bin/python", "source": "run_configuration", "exists": False, "candidates": [],
        }
        assert resultado["working_dir"] == raiz
        assert resultado["run_configuration"] == {
            "name": "main", "file": ".idea/runConfigurations/main.xml",
            "env_names": ["PYTHONUNBUFFERED", "AMBIENTE", "TOKEN_MASSA"],
        }

    def test_valores_das_envs_ficam_so_no_plano_interno(self, servico):
        projeto = servico.open(str(EXEMPLO))
        plano = servico.analyze(projeto["id"])
        assert plano.env["TOKEN_MASSA"] == "FAKE-TOKEN-9999"
        assert "FAKE-TOKEN-9999" in plano.masks
        assert "FAKE-KEY-0000" in plano.masks
        assert "FAKE-SENHA-1234" in plano.masks
        assert "usuario-falso" in plano.masks

    def test_venv_na_pasta_quando_nao_ha_run_configuration(self, servico, copia):
        shutil.rmtree(copia / ".idea")
        (copia / ".venv" / "bin").mkdir(parents=True)
        (copia / ".venv" / "pyvenv.cfg").write_text("home = /usr/bin\n")
        (copia / ".venv" / "bin" / "python").write_text("")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["interpreter"]["source"] == "venv"
        assert resultado["interpreter"]["path"].endswith(".venv/bin/python")
        assert resultado["run_configuration"] is None

    def test_sem_interpretador_nenhum_e_null(self, servico, copia):
        shutil.rmtree(copia / ".idea")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["interpreter"] == {"path": None, "source": None, "exists": False,
                                            "candidates": CANDIDATOS}

    def test_run_configuration_do_workspace_xml(self, servico, copia):
        xml = (copia / ".idea" / "runConfigurations" / "main.xml").read_text(encoding="utf-8")
        shutil.rmtree(copia / ".idea" / "runConfigurations")
        corpo = xml.replace('<component name="ProjectRunConfigurationManager">', "").replace("</component>", "")
        (copia / ".idea" / "workspace.xml").write_text(
            f'<project version="4"><component name="RunManager">{corpo}</component></project>', encoding="utf-8",
        )
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["run_configuration"]["file"] == ".idea/workspace.xml"
        assert resultado["interpreter"]["source"] == "run_configuration"

    def test_feature_que_nao_existe_vira_nao_achei(self, servico, copia):
        main = (copia / "main.py").read_text(encoding="utf-8")
        (copia / "main.py").write_text(main.replace("login/login.feature", "sumiu/sumiu.feature"), encoding="utf-8")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        execucao = resultado["suites"][1]["runs"][0]
        assert execucao["found"] is False
        assert execucao["path"] is None
        assert any("sumiu/sumiu.feature" in p["message"] for p in resultado["problems"])

    def test_valor_nao_literal_e_dinamico(self, servico, copia):
        (copia / "configs.py").write_text(
            "import os\n"
            "config_android_local_HLG = {'platformName': 'Android', 'appium:udid': os.environ['UDID'],\n"
            "    'url': f'http://{os.environ[\"HOST\"]}:4723'}\n"
            "config_ios_local_HLG = dict(platformName='iOS', udid='SIM-1')\n"
            "config_kobiton_android_HLG = {}\nconfig_kobiton_ios_HLG = {}\n",
            encoding="utf-8",
        )
        resultado = servico.inspect(servico.open(str(copia))["id"])
        por_nome = {c["name"]: c for c in resultado["configs"]}
        assert por_nome["config_android_local_HLG"]["values"]["udid"] == "dinâmico"
        assert por_nome["config_android_local_HLG"]["hub"] == "dinâmico"
        assert por_nome["config_ios_local_HLG"]["values"] == {"platformName": "iOS", "udid": "SIM-1"}

    def test_config_que_nao_acho_vira_problema(self, servico, copia):
        main = (copia / "main.py").read_text(encoding="utf-8")
        (copia / "main.py").write_text(main.replace("# init(config_ios_local_HLG)", "# init(config_nao_existe)"),
                                       encoding="utf-8")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        nao_achada = next(c for c in resultado["configs"] if c["name"] == "config_nao_existe")
        assert nao_achada["found"] is False
        assert any("config_nao_existe" in p["message"] for p in resultado["problems"])

    def test_erro_de_sintaxe_vira_problema_e_nao_excecao(self, servico, copia):
        (copia / "main.py").write_text("def main_sem_args(:\n", encoding="utf-8")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["entry"]["found"] is True
        assert resultado["suites"] == []
        assert any("sintaxe" in p["message"].lower() for p in resultado["problems"])

    def test_arquivo_grande_demais_vira_problema(self, servico, copia):
        (copia / "main.py").write_text("x = 1\n" * 200_000, encoding="utf-8")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert any("1 MB" in p["message"] for p in resultado["problems"])


# ------------------------------------------------------------ só leitura


class TestSoLeitura:
    def test_pasta_do_projeto_nao_muda(self, servico):
        antes = _hash_da_pasta(EXEMPLO)
        projeto = servico.open(str(EXEMPLO))
        servico.inspect(projeto["id"])
        servico.analyze(projeto["id"])
        servico.trust(projeto["id"])
        servico.forget(projeto["id"])
        assert _hash_da_pasta(EXEMPLO) == antes

    def test_link_simbolico_nao_e_seguido(self, servico, copia, tmp_path):
        fora = tmp_path / "fora.py"
        fora.write_text("config_android_local_HLG = {'platformName': 'SEGREDO-DE-FORA'}\n")
        (copia / "configs.py").unlink()
        (copia / "configs.py").symlink_to(fora)
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert "SEGREDO-DE-FORA" not in json.dumps(resultado)
        assert any("link simbólico" in p["message"] for p in resultado["problems"])

    def test_arquivos_proibidos_nunca_sao_lidos(self, copia):
        for nome in (".env", ".env.local", "chave.pem", "app.p12", "release.keystore", "local.properties",
                     "google-services.json"):
            with pytest.raises(projects.ProjectFileError):
                projects.read_project_text(copia, nome)
        (copia / ".venv").mkdir()
        (copia / ".venv" / "x.py").write_text("x = 1\n")
        with pytest.raises(projects.ProjectFileError):
            projects.read_project_text(copia, ".venv/x.py")
        with pytest.raises(projects.ProjectFileError):
            projects.read_project_text(copia, "../fora.py")
        with pytest.raises(projects.ProjectFileError):
            projects.read_project_text(copia, "dados.xml")


# ------------------------------------------------- interpretador (B1-4)


def _jdk_table(base, versao, nome, caminho):
    pasta = base / versao / "options"
    pasta.mkdir(parents=True)
    (pasta / "jdk.table.xml").write_text(
        '<application><component name="ProjectJdkTable">'
        f'<jdk version="2"><name value="{nome}" /><type value="Python SDK" /><homePath value="{caminho}" /></jdk>'
        '<jdk version="2"><name value="outro" /><homePath value="/nao/usar" /></jdk>'
        "</component></application>", encoding="utf-8",
    )


def _misc(copia, nome):
    (copia / ".idea" / "misc.xml").write_text(
        f'<project version="4"><component name="ProjectRootManager" version="2" project-jdk-name="{nome}" '
        'project-jdk-type="Python SDK" /></project>', encoding="utf-8",
    )


class TestInterpretadorDoPyCharm:
    def test_nome_do_sdk_no_misc_xml_resolvido_pelo_jdk_table_mais_recente(self, servico, copia, jetbrains):
        shutil.rmtree(copia / ".idea" / "runConfigurations")
        _misc(copia, "Python 3.12 (exemplo)")
        _jdk_table(jetbrains, "PyCharm2025.2", "Python 3.12 (exemplo)", "/velho/bin/python")
        _jdk_table(jetbrains, "PyCharm2026.1", "Python 3.12 (exemplo)", "$USER_HOME$/.virtualenvs/exemplo/bin/python")
        _jdk_table(jetbrains, "PyCharmCE2024.3", "Python 3.12 (exemplo)", "/mais-velho/bin/python")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["interpreter"]["source"] == "pycharm_sdk"
        assert resultado["interpreter"]["path"] == str(pathlib.Path.home() / ".virtualenvs/exemplo/bin/python")

    def test_run_configuration_vale_mais_que_o_misc_xml(self, servico, copia, jetbrains):
        _misc(copia, "Python 3.12 (exemplo)")
        _jdk_table(jetbrains, "PyCharm2026.1", "Python 3.12 (exemplo)", "/outro/bin/python")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["interpreter"]["source"] == "run_configuration"

    def test_sdk_que_nao_esta_no_jdk_table_vira_problema_e_cai_no_venv(self, servico, copia, jetbrains):
        shutil.rmtree(copia / ".idea" / "runConfigurations")
        _misc(copia, "Python sumido")
        _jdk_table(jetbrains, "PyCharm2026.1", "Python 3.12 (exemplo)", "/x/bin/python")
        (copia / ".venv" / "bin").mkdir(parents=True)
        (copia / ".venv" / "pyvenv.cfg").write_text("home = /usr/bin\n")
        (copia / ".venv" / "bin" / "python").write_text("")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["interpreter"]["source"] == "venv"
        assert any("Python sumido" in p["message"] for p in resultado["problems"])

    def test_sdk_name_na_run_configuration(self, servico, copia, jetbrains):
        xml = copia / ".idea" / "runConfigurations" / "main.xml"
        texto = xml.read_text(encoding="utf-8").replace(
            '<option name="SDK_HOME" value="$PROJECT_DIR$/.venv/bin/python" />',
            '<option name="SDK_HOME" value="" /><option name="SDK_NAME" value="Python 3.12 (exemplo)" />')
        xml.write_text(texto, encoding="utf-8")
        _jdk_table(jetbrains, "PyCharm2026.1", "Python 3.12 (exemplo)", "/sdk/bin/python")
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["interpreter"] == {"path": "/sdk/bin/python", "source": "pycharm_sdk", "exists": False,
                                            "candidates": []}

    def test_jdk_table_malicioso_e_ignorado(self, servico, copia, jetbrains):
        shutil.rmtree(copia / ".idea" / "runConfigurations")
        _misc(copia, "x")
        pasta = jetbrains / "PyCharm2026.1" / "options"
        pasta.mkdir(parents=True)
        (pasta / "jdk.table.xml").write_text('<!DOCTYPE a [<!ENTITY e SYSTEM "file:///etc/passwd">]><a>&e;</a>')
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["interpreter"]["path"] is None


    def test_xml_malicioso_do_projeto_nao_derruba_a_analise(self, servico, copia):
        ruim = '<!DOCTYPE a [<!ENTITY e SYSTEM "file:///etc/passwd">]><a>&e;</a>'
        (copia / ".idea" / "misc.xml").write_text(ruim)
        (copia / ".idea" / "runConfigurations" / "main.xml").write_text(ruim)
        resultado = servico.inspect(servico.open(str(copia))["id"])
        assert resultado["run_configuration"] is None
        assert resultado["active_config"] == "config_android_local_HLG"


class TestConfigurar:
    def test_override_do_interpretador_vale_mais_que_a_deteccao_e_null_remove(self, servico):
        projeto = servico.open(str(EXEMPLO))
        resultado = servico.configure(projeto["id"], interpreter=sys.executable)
        assert resultado["interpreter"]["source"] == "manual"
        assert resultado["interpreter"]["path"] == os.path.normpath(sys.executable)
        assert resultado["interpreter"]["exists"] is True
        assert resultado["project"]["interpreter_override"] == os.path.normpath(sys.executable)
        assert servico.open(str(EXEMPLO))["interpreter_override"] == os.path.normpath(sys.executable)
        resultado = servico.configure(projeto["id"], interpreter=None)
        assert resultado["interpreter"]["source"] == "run_configuration"
        assert resultado["project"]["interpreter_override"] is None

    def test_override_da_entrada(self, servico, copia):
        (copia / "rodar.py").write_text("def main_sem_args():\n    pass\n", encoding="utf-8")
        projeto = servico.open(str(copia))
        resultado = servico.configure(projeto["id"], entry="rodar.py")
        assert resultado["entry"]["file"] == "rodar.py"
        assert resultado["project"]["entry_override"] == "rodar.py"
        # Sem mexer no interpretador: ausente fica como estava.
        assert resultado["interpreter"]["source"] == "run_configuration"
        assert servico.configure(projeto["id"], entry=None)["entry"]["file"] == "main.py"

    def test_validacao(self, servico, copia, tmp_path):
        projeto = servico.open(str(copia))
        nao_exec = tmp_path / "python-falso"
        nao_exec.write_text("")
        (copia / "notas.txt").write_text("x")
        fora = tmp_path / "fora.py"
        fora.write_text("x = 1\n")
        (copia / "link.py").symlink_to(fora)
        for kw in ({"interpreter": "python3"}, {"interpreter": str(tmp_path / "nao-existe")},
                   {"interpreter": str(nao_exec)}, {"interpreter": "/usr/bin/../bin/python3"},
                   {"interpreter": 3}, {"entry": "../fora.py"}, {"entry": str(fora)}, {"entry": "notas.txt"},
                   {"entry": "sumiu.py"}, {"entry": "link.py"}, {"entry": ".venv/x.py"}):
            with pytest.raises(InvalidInputError):
                servico.configure(projeto["id"], **kw)
        assert servico.get(projeto["id"])["interpreter_override"] is None
        assert servico.get(projeto["id"])["entry_override"] is None


class TestCandidatos:
    def test_sonda_so_os_que_existem_sem_repetir_e_com_behave(self, tmp_path, monkeypatch):
        monkeypatch.setattr(projects, "_candidate_cache", {"at": 0.0, "items": None})
        link = tmp_path / "python-link"
        link.symlink_to(sys.executable)
        achados = projects.find_candidate_pythons([sys.executable, str(link), str(tmp_path / "nao-existe")])
        assert len(achados) == 1
        assert achados[0]["path"] == sys.executable
        assert achados[0]["version"] == sys.version.split()[0]
        assert "behave" in achados[0]

    def test_cache_curto(self, monkeypatch):
        monkeypatch.setattr(projects, "_candidate_cache", {"at": 0.0, "items": None})
        chamadas = []
        monkeypatch.setattr(projects, "_probe_python", lambda c: chamadas.append(c) or {"path": c})
        projects.find_candidate_pythons([sys.executable])
        projects.find_candidate_pythons([sys.executable])
        assert len(chamadas) == 1

    def test_python_quebrado_fica_de_fora(self, tmp_path, monkeypatch):
        monkeypatch.setattr(projects, "_candidate_cache", {"at": 0.0, "items": None})
        quebrado = tmp_path / "python3"
        quebrado.write_text("#!/bin/sh\nexit 3\n")
        quebrado.chmod(0o755)
        assert projects.find_candidate_pythons([str(quebrado)]) == []
