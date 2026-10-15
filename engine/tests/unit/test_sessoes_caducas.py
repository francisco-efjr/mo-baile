"""M6: o id de sessao em cache do WDA/Appium nunca caducava.

Um 404 do WDA e uma resposta HTTP, nao excecao, entao o `session_id` velho
ficava para sempre e todo toque falhava ate reiniciar o motor. No Android, o
"sessao ja estava aberta" respondia True para um id morto.
"""

from __future__ import annotations

import unittest
from unittest.mock import MagicMock, patch

import requests

from mobaile.adapters.appium import AppiumBridge
from mobaile.adapters.ios_wda import IOSBridge

WDA = "http://localhost:8100"


def resposta(status=200, payload=None, texto=""):
    r = MagicMock(spec=requests.Response)
    r.status_code = status
    r.json.return_value = payload if payload is not None else {}
    r.text = texto
    return r


class TestWdaReabreSessaoCaduca(unittest.TestCase):
    def setUp(self):
        self.bridge = IOSBridge(wda_url=WDA)
        self.posts = []

    def _post(self, sessao_valida):
        def post(url, json=None, timeout=None):
            self.posts.append(url)
            if f"/session/{sessao_valida}/" in url:
                return resposta(200)
            if url.endswith("/session"):
                return resposta(200, {"sessionId": sessao_valida})
            return resposta(404, {"value": {"error": "invalid session id"}})

        return post

    def test_tap_reabre_sessao_wda_quando_o_id_caducou(self):
        self.bridge.session_id = "velha"
        with patch("requests.post", side_effect=self._post("nova")), \
             patch("requests.get", return_value=resposta(200, {"sessionId": "nova"})):
            self.assertTrue(self.bridge.tap(10, 20))
        self.assertEqual(self.bridge.session_id, "nova")
        self.assertTrue(any("/session/velha/" in u for u in self.posts), "tentou a sessao velha antes")

    def test_erro_do_servidor_nao_repete_o_toque(self):
        """500 nao e id caduco: repetir poderia tocar duas vezes."""
        self.bridge.session_id = "boa"

        def post(url, json=None, timeout=None):
            self.posts.append(url)
            return resposta(500)

        with patch("requests.post", side_effect=post):
            self.assertFalse(self.bridge.tap(10, 20))
        self.assertEqual(self.bridge.session_id, "boa")
        self.assertFalse(any(u.endswith("/session") for u in self.posts), "nao abre sessao nova")


class TestAppiumLimpaSessaoCaduca(unittest.TestCase):
    def setUp(self):
        self.bridge = AppiumBridge(base_url="http://127.0.0.1:4723")
        self.bridge.session_id = "velha"
        self.bridge.session_platform = "android"
        self.bridge.session_udid = "emulator-5554"

    def test_page_source_com_sessao_invalida_limpa_o_id(self):
        with patch("requests.get", return_value=resposta(404, {"value": {"error": "invalid session id"}})):
            self.assertIsNone(self.bridge.get_page_source())
        self.assertIsNone(self.bridge.session_id)

    def test_depois_de_limpar_a_sessao_e_reaberta_em_vez_de_dita_ja_aberta(self):
        with patch("requests.get", return_value=resposta(404)):
            self.bridge.get_page_source()
        with patch.object(self.bridge, "start_server", return_value=(True, "ok")), \
             patch("requests.post", return_value=resposta(200, {"value": {"sessionId": "nova"}})) as post:
            ok, mensagem = self.bridge.ensure_android_session("emulator-5554")
        self.assertTrue(ok)
        self.assertEqual(self.bridge.session_id, "nova")
        self.assertEqual(post.call_count, 1)
        self.assertNotIn("ja estava aberta", mensagem)

    def test_erro_do_servidor_nao_derruba_a_sessao(self):
        with patch("requests.get", return_value=resposta(500)):
            self.assertIsNone(self.bridge.get_page_source())
        self.assertEqual(self.bridge.session_id, "velha")


if __name__ == "__main__":
    unittest.main()
