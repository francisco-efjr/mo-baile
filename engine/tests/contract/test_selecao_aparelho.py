"""M1: escolher o 2o aparelho nao volta para o 1o.

O vigia elegia sempre o primeiro alvo da listagem. Com emulador e aparelho
fisico conectados, `session.select_device` para o segundo era desfeito no poll
seguinte, e o `device.changed` resultante refazia a ativacao no front.
"""

from __future__ import annotations

import io
import json
import unittest
from unittest.mock import MagicMock, patch

from mobaile.rpc.server import EngineServer

A = "emulator-5554"
B = "R58M123ABC"


class TestSelecaoManualDoAparelho(unittest.TestCase):
    def setUp(self):
        self.saida = io.StringIO()
        self.server = EngineServer(out=self.saida)
        self.addCleanup(self.server.shutdown)
        self.server.adb = MagicMock()
        self.server.adb.list_devices.return_value = [(A, "device"), (B, "device")]
        # O laco de fundo disputaria o poll; aqui a varredura e manual.
        patcher = patch("mobaile.services.devices.DeviceWatcher.start")
        patcher.start()
        self.addCleanup(patcher.stop)

    def rpc(self, method, params=None):
        resposta = self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )
        self.assertNotIn("error", resposta, resposta.get("error"))
        return resposta["result"]

    def _notificacoes(self, nome="device.changed"):
        linhas = [json.loads(x) for x in self.saida.getvalue().splitlines() if x.strip()]
        return [n for n in linhas if n.get("method") == nome]

    def test_escolher_o_segundo_alvo_resiste_aos_polls(self):
        self.rpc("session.select_device", {"platform": "android", "device_id": None})
        self.rpc("devices.watch_start", {"poll_interval": 3600})
        watcher = self.server._watcher
        watcher.poll_once()
        self.assertEqual(self.server.device_id, A)
        antes = len(self._notificacoes())

        self.rpc("session.select_device", {"platform": "android", "device_id": B})
        for _ in range(3):
            watcher.poll_once()

        self.assertEqual(self.server.device_id, B)
        self.assertEqual(len(self._notificacoes()), antes, "nenhum device.changed novo")

    def test_watch_start_parte_do_alvo_ja_escolhido(self):
        self.rpc("session.select_device", {"platform": "android", "device_id": B})
        self.rpc("devices.watch_start", {"poll_interval": 3600})
        self.server._watcher.poll_once()
        self.assertEqual(self.server.device_id, B)
        self.assertEqual(self._notificacoes(), [])


if __name__ == "__main__":
    unittest.main()
