"""ARQ-1: o proxy global do Android e desfeito no aparelho em que foi ligado.

Antes o desmonte usava o aparelho *atual* da sessao. Com o proxy ligado no
aparelho A, trocar para B e parar (ou fechar o app) deixava A com
`http_proxy` apontando para uma porta morta, sem rede.
"""

from __future__ import annotations

import io
import json
import unittest
from unittest.mock import MagicMock

from mobaile.rpc.server import EngineServer

A = "emulator-5554"
B = "R58M123ABC"


class TestProxyDesfeitoNoAparelhoCerto(unittest.TestCase):
    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)
        self.server.adb = MagicMock()
        self.server.adb.setup_reverse_proxy.return_value = True
        self.server.proxy = MagicMock()
        self.server.proxy.port = 8082
        self.server.proxy.start.return_value = True
        self.server.proxy.is_running.return_value = True

    def ok(self, method, params=None):
        resposta = self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )
        self.assertNotIn("error", resposta, resposta.get("error"))
        return resposta["result"]

    def _seleciona(self, serial):
        self.ok("session.select_device", {"platform": "android", "device_id": serial})

    def _desfeitos(self) -> list[str]:
        return [c.args[0] for c in self.server.adb.teardown_reverse_proxy.call_args_list]

    def test_stop_depois_de_trocar_de_aparelho_desfaz_no_anterior(self):
        self._seleciona(A)
        self.assertTrue(self.ok("proxy.start", {"configure_device": True})["device_configured"])
        self.server.adb.setup_reverse_proxy.assert_called_once_with(A, 8082)
        self._seleciona(B)
        self.ok("proxy.stop")
        self.assertIn(A, self._desfeitos())
        self.assertNotIn(B, self._desfeitos())

    def test_trocar_de_aparelho_com_proxy_ligado_desfaz_no_anterior_na_hora(self):
        self._seleciona(A)
        self.ok("proxy.start", {"configure_device": True})
        self._seleciona(B)
        self.assertEqual(self._desfeitos(), [A])
        # Ja desfeito: o stop seguinte nao repete nem mexe em B.
        self.ok("proxy.stop")
        self.assertEqual(self._desfeitos(), [A])

    def test_selecionar_o_mesmo_aparelho_nao_desfaz(self):
        self._seleciona(A)
        self.ok("proxy.start", {"configure_device": True})
        self._seleciona(A)
        self.assertEqual(self._desfeitos(), [])

    def test_shutdown_desfaz_no_aparelho_configurado(self):
        self._seleciona(A)
        self.ok("proxy.start", {"configure_device": True})
        with self.server._state_lock:
            # Troca por fora do RPC (sem passar por session.select_device).
            self.server.device_id = B
        self.server.shutdown()
        self.assertEqual(self._desfeitos(), [A])

    def test_stop_sem_registro_mantem_a_limpeza_no_aparelho_da_sessao(self):
        """Recuperacao do front apos o motor cair: o motor novo nao configurou
        nada, mas o `proxy.stop` ainda limpa o aparelho da sessao."""
        self._seleciona(A)
        self.ok("proxy.stop")
        self.assertEqual(self._desfeitos(), [A])


if __name__ == "__main__":
    unittest.main()
