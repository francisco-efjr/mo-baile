"""F8: `proxy.diagnose` explica por que o trafego nao aparece, com evidencia."""

from __future__ import annotations

import io
import json
import time
import unittest
from unittest.mock import MagicMock

from mobaile.domain.models import NetworkEvent
from mobaile.rpc.server import EngineServer

SERIAL = "emulator-5554"


def evento(i, *, tunnel=False, error=None, response_bytes=100, age=0.0):
    return NetworkEvent(
        id=i, timestamp=time.time() - age, time_str="", method="CONNECT" if tunnel else "GET",
        url="https://api.exemplo/x", host="api.exemplo", path="/x", status_code=200 if not error else 0,
        status_text="", is_tunnel=tunnel, error=error, response_bytes=response_bytes,
    )


class TestDiagnostico(unittest.TestCase):
    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)
        self.server.proxy = MagicMock()
        self.server.proxy.port = 8082
        self.server.proxy.is_running.return_value = True
        self.server.proxy.events_history = []
        self.server.adb = MagicMock()
        self.server.adb.is_proxy_configured.return_value = True
        self.server.android_netlog = MagicMock()
        self.server.android_netlog.is_running.return_value = False
        self.server.ios_netlog = MagicMock()
        self.server.ios_netlog.is_running.return_value = False
        self._sessao("android", SERIAL)

    def _sessao(self, platform, device_id):
        self.server.handle_message(json.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "session.select_device",
            "params": {"platform": platform, "device_id": device_id},
        }))

    def diag(self):
        resposta = self.server.handle_message(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "proxy.diagnose"}))
        self.assertNotIn("error", resposta, resposta.get("error"))
        return resposta["result"]

    def codigos(self):
        return [c["code"] for c in self.diag()["causes"]]

    def test_proxy_desligado(self):
        self.server.proxy.is_running.return_value = False
        self.assertEqual(self.codigos(), ["proxy_stopped"])

    def test_aparelho_sem_o_proxy_aplicado(self):
        self.server.adb.is_proxy_configured.return_value = False
        resultado = self.diag()
        self.assertIs(resultado["device_configured"], False)
        self.assertIn("proxy_not_on_device", [c["code"] for c in resultado["causes"]])
        self.assertIn("127.0.0.1:8082", resultado["causes"][0]["fix"])

    def test_nada_chega_ao_proxy(self):
        self.assertEqual(self.codigos(), ["no_connections"])

    def test_trafego_recente_nao_acusa_nada(self):
        self.server.proxy.events_history = [evento(1)]
        resultado = self.diag()
        self.assertEqual(resultado["causes"], [])
        self.assertEqual(resultado["requests_total"], 1)
        self.assertLess(resultado["last_event_age_s"], 5)

    def test_tuneis_falhando_sugerem_pinning(self):
        self.server.proxy.events_history = [evento(i, tunnel=True, error="ConnectionResetError", response_bytes=0) for i in range(5)]
        self.assertEqual(self.codigos(), ["tls_pinning_suspected"])

    def test_so_tuneis_sem_conteudo(self):
        self.server.proxy.events_history = [evento(i, tunnel=True) for i in range(4)]
        self.assertEqual(self.codigos(), ["only_tunnels"])

    def test_sessao_ios_com_proxy(self):
        self._sessao("ios", "A1B2C3D4-1111-2222-3333-444455556666")
        resultado = self.diag()
        self.assertIsNone(resultado["device_configured"], "no iOS nao se consulta o adb")
        self.assertIn("ios_no_proxy_support", [c["code"] for c in resultado["causes"]])

    def test_app_em_debug_ligado_sem_eventos(self):
        self.server.proxy.is_running.return_value = False
        self.server.android_netlog.is_running.return_value = True
        self.assertEqual(self.codigos(), ["netlog_running_no_events"])

    def test_causas_tem_titulo_detalhe_e_correcao(self):
        self.server.proxy.is_running.return_value = False
        for causa in self.diag()["causes"]:
            for chave in ("code", "title", "detail", "fix"):
                self.assertTrue(causa.get(chave), chave)


if __name__ == "__main__":
    unittest.main()
