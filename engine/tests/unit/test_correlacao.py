"""F5: cada passo gravado ganha hora, e `session.correlate` liga passo, rede e analytics."""

from __future__ import annotations

import io
import json
import unittest
from unittest.mock import MagicMock, patch

from mobaile.domain.models import AnalyticsEvent, AutomationStep, LocatorStrategy, NetworkEvent
from mobaile.rpc.server import EngineServer

T0 = 1_757_030_000.0


def requisicao(i, t):
    return NetworkEvent(id=i, timestamp=t, time_str="", method="POST", url="https://api/x", host="api", path="/x",
                        status_code=200, status_text="OK")


def evento(i, t):
    return AnalyticsEvent(id=i, timestamp=t, time_str="", tag="FA", event_name="login")


class TestCorrelacao(unittest.TestCase):
    def setUp(self):
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.addCleanup(self.server.shutdown)
        self.server.proxy = MagicMock()
        self.server.proxy.events_history = []
        self.server.analytics = MagicMock()
        self.server.analytics.history_events.return_value = []

    def call(self, method, params=None):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )

    def _passo(self, num, t):
        self.server.codegen.steps.append(AutomationStep(
            step_num=num, action_type="click", var_name=f"BOTAO_{num}", element_name=f"botao {num}",
            class_name="android.widget.Button", strategy=LocatorStrategy.ID, locator_value="(AppiumBy.ID, 'x')",
            coords=(1, 1), platform="android", recorded_at=t,
        ))

    def test_passo_gravado_ganha_hora_do_mac(self):
        self.call("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        with self.server._state_lock:
            self.server.current_xml = (
                '<hierarchy><node index="0" text="Entrar" resource-id="br.app:id/ok" class="android.widget.Button" '
                'package="br.app" content-desc="" clickable="true" bounds="[0,0][100,100]" /></hierarchy>'
            )
        from types import SimpleNamespace

        from mobaile.services import codegen as codegen_mod

        with patch.object(codegen_mod, "time", SimpleNamespace(time=lambda: T0)):
            gravado = self.call("codegen.record", {"x": 50, "y": 50, "strategy": "id"})["result"]
        self.assertEqual(gravado["recorded_at"], T0)
        self.assertEqual(gravado["step_num"], 1)
        passos = self.call("codegen.steps")["result"]["steps"]
        self.assertEqual(passos[0]["recorded_at"], T0)

    def test_janela_pega_so_o_que_esta_em_volta_do_toque(self):
        self._passo(1, T0)
        self.server.proxy.events_history = [requisicao(1, T0 - 5), requisicao(2, T0 + 0.8), requisicao(3, T0 + 3.9),
                                            requisicao(4, T0 + 4.5)]
        self.server.analytics.history_events.return_value = [evento(10, T0 - 0.5), evento(11, T0 + 2), evento(12, T0 + 9)]
        r = self.call("session.correlate", {"step_num": 1})["result"]
        self.assertEqual(r["requests"], [2, 3])
        self.assertEqual(r["events"], [10, 11])
        self.assertEqual(r["window"], [T0 - 1.0, T0 + 4.0])
        self.assertTrue(r["probable"])

    def test_janela_termina_no_passo_seguinte(self):
        self._passo(1, T0)
        self._passo(2, T0 + 1.5)
        self.server.proxy.events_history = [requisicao(1, T0 + 1), requisicao(2, T0 + 2)]
        r = self.call("session.correlate", {"step_num": 1})["result"]
        self.assertEqual(r["requests"], [1], "a requisicao depois do passo 2 e dele")
        self.assertEqual(r["window"][1], T0 + 1.5)
        r2 = self.call("session.correlate", {"step_num": 2})["result"]
        self.assertEqual(r2["requests"], [1, 2])

    def test_janela_configuravel(self):
        self._passo(1, T0)
        self.server.proxy.events_history = [requisicao(1, T0 + 8)]
        self.assertEqual(self.call("session.correlate", {"step_num": 1, "after_s": 10})["result"]["requests"], [1])
        self.assertIn("error", self.call("session.correlate", {"step_num": 1, "after_s": 999}))

    def test_passo_inexistente_e_erro_de_entrada(self):
        resposta = self.call("session.correlate", {"step_num": 7})
        self.assertEqual(resposta["error"]["data"]["code"], "invalid_input")

    def test_passo_sem_hora_e_erro_claro(self):
        self._passo(1, 0.0)
        resposta = self.call("session.correlate", {"step_num": 1})
        self.assertIn("hora", resposta["error"]["message"])


if __name__ == "__main__":
    unittest.main()
