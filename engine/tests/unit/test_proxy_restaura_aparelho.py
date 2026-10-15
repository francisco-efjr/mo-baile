"""M2: desligar o proxy devolve o aparelho ao que ele era, e a falha nao some.

Antes, `teardown_reverse_proxy` apagava `http_proxy` e `captive_portal_mode`
mesmo quando o aparelho tinha valores proprios (um proxy corporativo, por
exemplo), devolvia True sempre, e o servidor esquecia o registro antes de saber
se o desmonte tinha funcionado. Cabo solto: o aparelho ficava com o proxy
apontando para uma porta morta, sem rede e sem nova tentativa.
"""

from __future__ import annotations

import io
import json
import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters.adb import ADBBridge
from mobaile.rpc.server import EngineServer

SERIAL = "emulator-5554"


class AparelhoFalso:
    """`settings` de um aparelho, atras de um `_run_cmd` falso."""

    def __init__(self, **settings):
        self.settings = dict(settings)
        self.conectado = True
        self.reversas = set()

    def run(self, args, timeout=15):
        if not self.conectado:
            return 1, b"", b"error: device not found"
        rest = [a for a in args if a not in ("-s", SERIAL)]
        if rest[:2] == ["shell", "settings"]:
            verbo, chave = rest[2], rest[4]
            if verbo == "get":
                return 0, (self.settings.get(chave) or "null").encode() + b"\n", b""
            if verbo == "put":
                self.settings[chave] = rest[5]
                return 0, b"", b""
            if verbo == "delete":
                self.settings.pop(chave, None)
                return 0, b"", b""
        if rest[:1] == ["reverse"]:
            if rest[1] == "--remove":
                self.reversas.discard(rest[2])
            else:
                self.reversas.add(rest[1])
            return 0, b"", b""
        return 0, b"", b""


def adb_com(aparelho):
    bridge = ADBBridge(adb_path="/falso/adb")
    bridge._run_cmd = aparelho.run
    return bridge


class TestAdbRestauraOValorAnterior(unittest.TestCase):
    def test_restaura_proxy_e_captive_portal_que_o_aparelho_tinha(self):
        aparelho = AparelhoFalso(http_proxy="corp.exemplo:3128", captive_portal_mode="1")
        adb = adb_com(aparelho)
        self.assertTrue(adb.setup_reverse_proxy(SERIAL, 8082))
        self.assertEqual(aparelho.settings["http_proxy"], "127.0.0.1:8082")
        self.assertEqual(aparelho.settings["captive_portal_mode"], "0")

        self.assertTrue(adb.teardown_reverse_proxy(SERIAL, 8082))
        self.assertEqual(aparelho.settings.get("http_proxy"), "corp.exemplo:3128")
        self.assertEqual(aparelho.settings.get("captive_portal_mode"), "1")

    def test_sem_valor_anterior_apaga_como_antes(self):
        aparelho = AparelhoFalso()
        adb = adb_com(aparelho)
        adb.setup_reverse_proxy(SERIAL, 8082)
        self.assertTrue(adb.teardown_reverse_proxy(SERIAL, 8082))
        self.assertNotIn("http_proxy", aparelho.settings)
        self.assertNotIn("captive_portal_mode", aparelho.settings)

    def test_religar_nao_sobrescreve_o_valor_original_guardado(self):
        aparelho = AparelhoFalso(http_proxy="corp.exemplo:3128")
        adb = adb_com(aparelho)
        adb.setup_reverse_proxy(SERIAL, 8082)
        adb.setup_reverse_proxy(SERIAL, 8082)  # o "anterior" agora e o nosso
        adb.teardown_reverse_proxy(SERIAL, 8082)
        self.assertEqual(aparelho.settings.get("http_proxy"), "corp.exemplo:3128")

    def test_desmonte_com_cabo_solto_devolve_false_e_guarda_o_original(self):
        aparelho = AparelhoFalso(http_proxy="corp.exemplo:3128")
        adb = adb_com(aparelho)
        adb.setup_reverse_proxy(SERIAL, 8082)
        aparelho.conectado = False
        self.assertFalse(adb.teardown_reverse_proxy(SERIAL, 8082))
        aparelho.conectado = True
        self.assertTrue(adb.teardown_reverse_proxy(SERIAL, 8082))
        self.assertEqual(aparelho.settings.get("http_proxy"), "corp.exemplo:3128")

    def test_falha_ao_ligar_devolve_o_captive_portal_que_existia(self):
        aparelho = AparelhoFalso(captive_portal_mode="1")
        original = aparelho.run

        def run(args, timeout=15):
            if "put" in args and "http_proxy" in args:
                return 1, b"", b"permission denied"
            return original(args, timeout)

        adb = ADBBridge(adb_path="/falso/adb")
        adb._run_cmd = run
        self.assertFalse(adb.setup_reverse_proxy(SERIAL, 8082))
        self.assertEqual(aparelho.settings.get("captive_portal_mode"), "1")


class TestServidorRetentaODesmonte(unittest.TestCase):
    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)
        self.server.adb = MagicMock()
        self.server.adb.setup_reverse_proxy.return_value = True
        self.server.proxy = MagicMock()
        self.server.proxy.port = 8082
        self.server.proxy.start.return_value = True
        self.server.proxy.is_running.return_value = True
        patcher = patch("mobaile.services.devices.DeviceWatcher.start")
        patcher.start()
        self.addCleanup(patcher.stop)

    def rpc(self, method, params=None):
        resposta = self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )
        self.assertNotIn("error", resposta, resposta.get("error"))
        return resposta["result"]

    def _liga_proxy(self):
        self.rpc("session.select_device", {"platform": "android", "device_id": SERIAL})
        self.rpc("proxy.start", {"configure_device": True})

    def test_desmonte_que_falhou_e_retentado_quando_o_serial_volta(self):
        self._liga_proxy()
        self.server.adb.teardown_reverse_proxy.return_value = False
        self.rpc("proxy.stop")
        self.assertEqual(self.server.adb.teardown_reverse_proxy.call_count, 1)

        self.server.adb.teardown_reverse_proxy.return_value = True
        self.rpc("devices.watch_start", {"poll_interval": 3600})
        self.server._watcher.on_device_changed("android", SERIAL)
        # A nova tentativa roda numa thread curta; espera ela terminar.
        for _ in range(100):
            if self.server.adb.teardown_reverse_proxy.call_count >= 2:
                break
            import time
            time.sleep(0.02)
        self.assertEqual(self.server.adb.teardown_reverse_proxy.call_count, 2)
        self.assertEqual(self.server._proxy_pending, {})

    def test_desmonte_bem_sucedido_nao_deixa_pendencia(self):
        self._liga_proxy()
        self.server.adb.teardown_reverse_proxy.return_value = True
        self.rpc("proxy.stop")
        self.assertEqual(self.server._proxy_pending, {})


if __name__ == "__main__":
    unittest.main()
