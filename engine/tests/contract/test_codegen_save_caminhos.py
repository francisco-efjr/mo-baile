"""SEC-5: `codegen.save` so grava dentro da pasta de trabalho do Mo baile."""

from __future__ import annotations

import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from mobaile.rpc.server import EngineServer


class TestCodegenSaveCaminhos(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.home = pathlib.Path(self._tmp.name) / "home"
        self.home.mkdir()
        self.raiz = self.home / "Documents" / "Mo baile"
        env = patch.dict(os.environ, {"HOME": str(self.home)})
        env.start()
        self.addCleanup(env.stop)
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)

    def call(self, **params):
        params.setdefault("actions_code", "class P: pass\n")
        params.setdefault("locators_code", "class L: pass\n")
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": "codegen.save", "params": params})
        )

    def assert_recusado(self, resposta):
        self.assertIn("error", resposta, resposta)
        self.assertEqual(resposta["error"]["data"]["code"], "invalid_input")

    def test_sem_pasta_grava_na_pasta_de_trabalho(self):
        resposta = self.call(key="minha_tela")
        self.assertNotIn("error", resposta, resposta)
        self.assertTrue((self.raiz / "pages" / "minha_tela.py").is_file())
        self.assertTrue((self.raiz / "locators" / "minha_tela.py").is_file())

    def test_subpasta_da_pasta_de_trabalho_e_aceita(self):
        resposta = self.call(key="tela", directory=str(self.raiz / "projeto_x"))
        self.assertNotIn("error", resposta, resposta)
        self.assertTrue((self.raiz / "projeto_x" / "pages" / "tela.py").is_file())

    def test_pasta_fora_da_pasta_de_trabalho_e_recusada(self):
        fora = pathlib.Path(self._tmp.name) / "fora"
        for pasta in (str(fora), "/etc", str(self.raiz / ".." / "fora"), str(self.home)):
            with self.subTest(pasta=pasta):
                self.assert_recusado(self.call(key="tela", directory=pasta))
        self.assertFalse(fora.exists())
        self.assertFalse((self.home / "Documents" / "fora").exists())

    def test_link_simbolico_para_fora_e_recusado(self):
        fora = pathlib.Path(self._tmp.name) / "fora"
        fora.mkdir()
        self.raiz.mkdir(parents=True)
        (self.raiz / "atalho").symlink_to(fora, target_is_directory=True)
        self.assert_recusado(self.call(key="tela", directory=str(self.raiz / "atalho")))
        self.assertEqual(list(fora.iterdir()), [])

    def test_nome_de_arquivo_com_caminho_e_recusado(self):
        for chave in ("..", "../tela", "a/b", "/etc/passwd", "tela.py/..", "a\\b"):
            with self.subTest(chave=chave):
                self.assert_recusado(self.call(key=chave))
        self.assertFalse(self.raiz.exists())


if __name__ == "__main__":
    unittest.main()
