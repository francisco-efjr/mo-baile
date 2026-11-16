"""`project.*` pela fronteira: formato que o front decodifica e erros.

O conteúdo da análise é coberto em `tests/unit/test_projects.py`; aqui fica o
que o front enxerga: as chaves de cada resposta, a fila e que nenhum segredo
do projeto de exemplo atravessa o RPC.
"""

from __future__ import annotations

import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from mobaile.rpc import contract
from mobaile.rpc.server import EngineServer

EXEMPLO = pathlib.Path(__file__).resolve().parents[1] / "fixtures" / "projeto_exemplo_behave"


class TestProjectRpc(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        env = patch.dict(os.environ, {"MOBAILE_DATA_DIR": self._tmp.name})
        env.start()
        self.addCleanup(env.stop)
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.addCleanup(self.server.shutdown)

    def call(self, method, **params):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
        )

    def ok(self, method, **params):
        resposta = self.call(method, **params)
        self.assertNotIn("error", resposta, resposta)
        return resposta["result"]

    def test_abrir_listar_inspecionar_e_esquecer(self):
        projeto = self.ok("project.open", path=str(EXEMPLO))["project"]
        self.assertEqual(set(projeto), {"id", "root", "name", "entry", "trusted", "opened_at",
                                        "interpreter_override", "entry_override"})
        self.assertEqual(self.ok("project.list")["projects"][0]["id"], projeto["id"])

        analise = self.ok("project.inspect", project_id=projeto["id"])
        self.assertEqual(set(analise), {
            "project", "entry", "interpreter", "working_dir", "run_configuration", "active_config", "hub_state",
            "hub_reason", "configs", "suites", "unused_suites", "problems",
        })
        self.assertEqual(set(analise["configs"][0]), {
            "name", "active", "found", "file", "line", "platform", "values", "hub", "cloud", "hub_state", "keys",
        })
        self.assertEqual(set(analise["suites"][0]), {"name", "defined", "line", "runs"})
        self.assertEqual(set(analise["suites"][0]["runs"][0]), {
            "squad", "feature", "line", "found", "path", "title", "scenarios",
        })

        self.assertEqual(self.ok("project.forget", project_id=projeto["id"]), {"removed": True})
        self.assertEqual(self.ok("project.list")["projects"], [])

    def test_nenhum_segredo_atravessa_o_rpc(self):
        projeto = self.ok("project.open", path=str(EXEMPLO))["project"]
        self.ok("project.inspect", project_id=projeto["id"])
        self.ok("project.list")
        for segredo in ("FAKE-KEY-0000", "FAKE-SENHA-1234", "FAKE-TOKEN-9999", "usuario-falso"):
            self.assertNotIn(segredo, self.out.getvalue())

    def test_erros_de_entrada(self):
        for metodo, params in (("project.open", {}), ("project.open", {"path": "/nao/existe/mesmo"}),
                               ("project.inspect", {"project_id": "desconhecido"}),
                               ("project.forget", {})):
            with self.subTest(metodo=metodo, params=params):
                erro = self.call(metodo, **params)["error"]
                self.assertEqual(erro["data"]["code"], "invalid_input")

    def test_fila_propria(self):
        for nome in ("project.open", "project.list", "project.forget", "project.inspect", "project.doctor"):
            self.assertEqual(contract.lane_of(nome), contract.LANE_PROJECT)

    def test_doctor_emite_progresso_e_devolve_uma_linha_por_checagem(self):
        from mobaile.services.project_doctor import CHECK_IDS, ProjectDoctor

        class Adb:
            def list_devices(self):
                return [("emulator-5554", "device")]

            def get_prop(self, serial, nome):
                return "14"

            def package_installed(self, serial, pacote):
                return True

            def uiautomation_holder(self, serial):
                return None

        class Appium:
            def locate_appium(self):
                return None

            def owns_server_on(self, porta):
                return False

        self.server.project_doctor = ProjectDoctor(
            adb=Adb(), appium=Appium(), run=lambda args, timeout, env=None: (0, "3.14.0\n", ""),
            port_open=lambda host, porta: False,
        )
        projeto = self.ok("project.open", path=str(EXEMPLO))["project"]
        resultado = self.ok("project.doctor", project_id=projeto["id"], device_id="emulator-5554",
                            progress_token="doc-1")
        self.assertEqual(set(resultado), {"project_id", "checks", "summary", "ready", "trusted"})
        self.assertEqual([c["id"] for c in resultado["checks"]], list(CHECK_IDS))
        self.assertEqual(set(resultado["summary"]), {"ok", "warn", "fail", "skip"})
        progresso = [json.loads(linha)["params"] for linha in self.out.getvalue().splitlines()
                     if '"$/progress"' in linha]
        self.assertEqual(len(progresso), len(CHECK_IDS))
        self.assertTrue(all(p["token"] == "doc-1" for p in progresso))
        self.assertNotIn("FAKE-TOKEN-9999", self.out.getvalue())

    def test_doctor_recusa_device_id_invalido(self):
        projeto = self.ok("project.open", path=str(EXEMPLO))["project"]
        erro = self.call("project.doctor", project_id=projeto["id"], device_id="x; rm -rf /")["error"]
        self.assertEqual(erro["data"]["code"], "invalid_input")

    def test_configurar_devolve_o_inspect_com_override_e_null_remove(self):
        import sys

        projeto = self.ok("project.open", path=str(EXEMPLO))["project"]
        analise = self.ok("project.configure", project_id=projeto["id"], interpreter=sys.executable)
        self.assertEqual(set(analise), set(self.ok("project.inspect", project_id=projeto["id"])))
        self.assertEqual(analise["interpreter"]["source"], "manual")
        self.assertEqual(set(analise["interpreter"]), {"path", "source", "exists", "candidates"})
        analise = self.ok("project.configure", project_id=projeto["id"], interpreter=None)
        self.assertEqual(analise["interpreter"]["source"], "run_configuration")
        erro = self.call("project.configure", project_id=projeto["id"], entry="../fora.py")["error"]
        self.assertEqual(erro["data"]["code"], "invalid_input")
