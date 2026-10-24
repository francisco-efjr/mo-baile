"""Parâmetros numéricos do RPC: valor estranho vira `invalid_input`, não erro interno.

Antes, `limit: -5` devolvia o histórico fatiado do lado errado, `"abc"` virava
"Erro interno no motor" e `NaN` (JSON válido para o Python) passava adiante.
"""

from __future__ import annotations

import io
import unittest
from unittest.mock import MagicMock

from mobaile.rpc import protocol
from mobaile.rpc.server import EngineServer


class TestParametrosNumericos(unittest.TestCase):
    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)
        self.server.proxy = MagicMock()
        self.server.proxy.events_history = []
        self.server.analytics = MagicMock()
        self.server.analytics.events_history = []

    def call(self, method, raw_params):
        # Texto cru: `NaN` e `Infinity` só chegam assim, nunca por `json.dumps` estrito.
        return self.server.handle_message(
            f'{{"jsonrpc": "2.0", "id": 1, "method": "{method}", "params": {raw_params}}}'
        )

    def recusa(self, method, raw_params, trecho):
        resposta = self.call(method, raw_params)
        self.assertIn("error", resposta, resposta)
        self.assertEqual(resposta["error"]["code"], protocol.ENGINE_ERROR)
        self.assertEqual(resposta["error"]["data"]["code"], "invalid_input")
        self.assertIn(trecho, resposta["error"]["message"])

    def test_limite_dos_historicos(self):
        for metodo in ("proxy.events", "analytics.events"):
            for params in ('{"limit": -5}', '{"limit": "abc"}', '{"limit": NaN}', '{"limit": 2.5}'):
                with self.subTest(metodo=metodo, params=params):
                    self.recusa(metodo, params, "limit")
            with self.subTest(metodo=metodo, params="padrão"):
                self.assertIn("result", self.call(metodo, "{}"))

    def test_intervalo_da_deteccao(self):
        for params in ('{"poll_interval": -1}', '{"poll_interval": Infinity}', '{"poll_interval": "1"}'):
            with self.subTest(params=params):
                self.recusa("devices.watch_start", params, "poll_interval")

    def test_correlacao(self):
        self.recusa("session.correlate", '{"step_num": "x"}', "step_num")
        self.recusa("session.correlate", '{"step_num": 1, "after_s": 999}', "after_s")
        self.recusa("session.correlate", '{"step_num": 1, "before_s": NaN}', "before_s")


if __name__ == "__main__":
    unittest.main()
