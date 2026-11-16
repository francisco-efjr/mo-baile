"""`home.summary`, `home.forget_recent` e a notificação `home.changed`.

O que se confere pela fronteira: o formato que o front decodifica, que salvar
um Page Object vira recente e avisa a interface sem polling, e que tirar um
recente exige o caminho.
"""

from __future__ import annotations

import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from mobaile.rpc.server import EngineServer
from mobaile.services.home import RecentStore


class TestHomeRpc(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.home = pathlib.Path(self._tmp.name) / "home"
        self.home.mkdir()
        env = patch.dict(os.environ, {"HOME": str(self.home)})
        env.start()
        self.addCleanup(env.stop)
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.addCleanup(self.server.shutdown)
        self.server.home.recents = RecentStore(pathlib.Path(self._tmp.name) / "recentes.json")

    def call(self, method, **params):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
        )

    def notificacoes(self):
        return [json.loads(linha) for linha in self.out.getvalue().splitlines() if '"id"' not in linha]

    def test_resumo_tem_o_formato_do_contrato(self):
        resumo = self.call("home.summary")["result"]
        self.assertEqual(set(resumo), {
            "state", "python", "environment", "platforms", "suggested_platform", "targets", "recent", "whats_new",
        })
        self.assertIn(resumo["state"], ("first_run", "daily"))
        self.assertEqual(set(resumo["environment"]), {"ready", "total", "pending"})
        for alvo in resumo["targets"]:
            self.assertEqual(set(alvo), {
                "id", "name", "platform", "kind", "running", "connected", "capabilities", "blocked_by",
            })

    def test_salvar_page_object_vira_recente_e_avisa_a_interface(self):
        resposta = self.call("codegen.save", key="checkout", actions_code="class P: pass\n",
                             locators_code="class L: pass\n")
        self.assertNotIn("error", resposta, resposta)
        [recente] = self.call("home.summary")["result"]["recent"]
        self.assertEqual((recente["kind"], recente["title"]), ("page_object", "checkout.py"))
        self.assertTrue(recente["path"].endswith("pages/checkout.py"))
        self.assertIn({"jsonrpc": "2.0", "method": "home.changed", "params": {"reason": "recent"}},
                      self.notificacoes())

    def test_esquecer_recente(self):
        self.server.home.recents.record("report", "Relatório · X", "", "/sumiu.json")
        self.assertEqual(self.call("home.forget_recent", path="/sumiu.json")["result"], {"removed": True})
        self.assertEqual(self.call("home.summary")["result"]["recent"], [])
        erro = self.call("home.forget_recent")["error"]
        self.assertEqual(erro["data"]["code"], "invalid_input")


if __name__ == "__main__":
    unittest.main()
