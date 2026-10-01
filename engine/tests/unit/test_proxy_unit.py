"""Testes unitários das melhorias do proxy e ADBBridge."""

import unittest
from unittest.mock import MagicMock

from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.proxy import (
    MAX_CONCURRENT_CONNECTIONS,
    ProxyRequestHandler,
)


class TestProxyUnit(unittest.TestCase):
    def test_max_concurrent_connections_elevado(self):
        self.assertGreaterEqual(MAX_CONCURRENT_CONNECTIONS, 512)

    def test_parse_content_length(self):
        self.assertEqual(ProxyRequestHandler._parse_content_length({"Content-Length": "123"}), 123)
        self.assertEqual(ProxyRequestHandler._parse_content_length({"Content-Length": "-10"}), 0)
        self.assertEqual(ProxyRequestHandler._parse_content_length({"Content-Length": "invalid"}), 0)


class TestADBBridgeProxyControl(unittest.TestCase):
    def setUp(self):
        self.adb = ADBBridge()

    def test_setup_reverse_proxy_sucesso(self):
        self.adb._run_cmd = MagicMock(return_value=(0, b"ok", b""))
        res = self.adb.setup_reverse_proxy("device1", 8082)
        self.assertTrue(res)

        calls = [c[0][0] for c in self.adb._run_cmd.call_args_list]
        # Deve chamar reverse, depois captive_portal_mode 0, depois settings put global http_proxy
        self.assertTrue(any("reverse" in c and "tcp:8082" in c for c in calls))
        self.assertTrue(any("captive_portal_mode" in c and "0" in c for c in calls))
        self.assertTrue(any("http_proxy" in c and "127.0.0.1:8082" in c for c in calls))

    def test_setup_reverse_proxy_falha_reverse_nao_seta_proxy(self):
        self.adb._run_cmd = MagicMock(return_value=(1, b"", b"device offline"))
        res = self.adb.setup_reverse_proxy("device1", 8082)
        self.assertFalse(res)

        calls = [c[0][0] for c in self.adb._run_cmd.call_args_list]
        # Não deve configurar http_proxy se o adb reverse falhou
        self.assertFalse(any("http_proxy" in c for c in calls))

    def test_setup_reverse_proxy_rollback_se_settings_falhar(self):
        # Primeiro comando (reverse) passa, segundo (captive_portal) passa, terceiro (http_proxy) falha
        self.adb._run_cmd = MagicMock(side_effect=[
            (0, b"ok", b""),
            (0, b"ok", b""),
            (1, b"", b"permission denied"),
            (0, b"ok", b""),
            (0, b"ok", b""),
        ])
        res = self.adb.setup_reverse_proxy("device1", 8082)
        self.assertFalse(res)

        calls = [c[0][0] for c in self.adb._run_cmd.call_args_list]
        # Deve ter executado rollback do captive_portal_mode e do reverse
        self.assertTrue(any("captive_portal_mode" in c and "delete" in c for c in calls))
        self.assertTrue(any("--remove" in c for c in calls))

    def test_teardown_reverse_proxy_restaura_tudo(self):
        self.adb._run_cmd = MagicMock(return_value=(0, b"ok", b""))
        res = self.adb.teardown_reverse_proxy("device1", 8082)
        self.assertTrue(res)

        calls = [c[0][0] for c in self.adb._run_cmd.call_args_list]
        self.assertTrue(any("captive_portal_mode" in c and "delete" in c for c in calls))
        self.assertTrue(any("http_proxy" in c and ":0" in c for c in calls))
        self.assertTrue(any("--remove" in c for c in calls))


if __name__ == "__main__":
    unittest.main()
