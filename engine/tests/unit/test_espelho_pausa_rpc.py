"""PERF-1: `stream.pause` e `stream.resume` pelo RPC.

O front pede a pausa quando a janela fica oculta, coberta ou minimizada, e a
retomada quando ela volta. A regra de quando a pausa vale mora no motor:
durante `flow.run`, `flow.maestro_run` ou a escuta passiva o espelho continua,
e a pausa pedida passa a valer quando eles terminam.
"""

from __future__ import annotations

import time
from unittest.mock import MagicMock

from PIL import Image
from test_flow_execucao import FluxoBase


class TestPausaDoEspelho(FluxoBase):
    def setUp(self):
        super().setUp()
        self.server.adb.take_screenshot = lambda *_a, **_k: Image.new("RGB", (60, 120), "black")
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})

    def test_pausa_e_retoma_o_espelho_ligado(self):
        self.ok("stream.start", {"fps": 30, "max_width": 30})
        self.assertEqual(self.ok("stream.pause"), {"running": True, "paused": True, "kept_for": None})
        self.assertTrue(self.server._stream.paused)
        self.assertEqual(self.ok("stream.resume"), {"running": True, "paused": False, "kept_for": None})
        self.assertFalse(self.server._stream.paused)

    def test_sem_espelho_a_pausa_e_inofensiva_e_vale_no_proximo_start(self):
        self.assertEqual(self.ok("stream.pause"), {"running": False, "paused": False, "kept_for": None})
        # A janela continua oculta quando o espelho liga (aparelho plugado com
        # a janela coberta): ele ja nasce pausado.
        self.ok("stream.start", {"fps": 30, "max_width": 30})
        self.assertTrue(self.server._stream.paused)
        self.ok("stream.resume")
        self.assertFalse(self.server._stream.paused)

    def test_durante_flow_o_espelho_nao_pausa(self):
        self.ok("stream.start", {"fps": 30, "max_width": 30})
        self.server._flow_running = True
        self.assertEqual(self.ok("stream.pause"), {"running": True, "paused": False, "kept_for": "flow"})
        self.assertFalse(self.server._stream.paused)
        # Acabou o flow: a pausa pedida passa a valer.
        self.server._release_flow()
        self.assertTrue(self.server._stream.paused)

    def test_durante_escuta_passiva_o_espelho_nao_pausa(self):
        self.ok("stream.start", {"fps": 30, "max_width": 30})
        self.server._passive = MagicMock()
        self.assertEqual(self.ok("stream.pause")["kept_for"], "passive")
        self.assertFalse(self.server._stream.paused)
        self.ok("passive.stop")
        self.assertTrue(self.server._stream.paused)

    def test_flow_que_comeca_com_a_janela_oculta_retoma_o_espelho(self):
        espelho = MagicMock()
        self.server._stream = espelho
        self.ok("stream.pause")
        espelho.pause.assert_called()
        espelho.reset_mock()

        flow = "- assertVisible: Continuar\n"
        self.ok("flow.maestro_run", {"yaml": flow})
        espelho.resume.assert_called()
        self.esperar_fim(prazo=30)
        limite = time.monotonic() + 2
        while not espelho.pause.called and time.monotonic() < limite:
            time.sleep(0.02)
        espelho.pause.assert_called()
        self.server._stream = None

    def test_stream_stop_esquece_a_pausa_so_se_o_front_retomar(self):
        self.ok("stream.start", {"fps": 30, "max_width": 30})
        self.ok("stream.pause")
        self.ok("stream.stop")
        self.ok("stream.resume")
        self.ok("stream.start", {"fps": 30, "max_width": 30})
        self.assertFalse(self.server._stream.paused)


class TestEspelhoAcordaNoToque(FluxoBase):
    """PERF-2: toque repassado tira o espelho da cadencia de tela parada."""

    def setUp(self):
        super().setUp()
        self.server.adb.take_screenshot = lambda *_a, **_k: Image.new("RGB", (60, 120), "black")
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})

    def test_input_tap_acorda_o_espelho(self):
        self.server.adb.tap = MagicMock(return_value=True)
        espelho = MagicMock()
        self.server._stream = espelho
        try:
            self.ok("input.tap", {"x": 10, "y": 20})
        finally:
            self.server._stream = None
        espelho.wake.assert_called_once()

    def test_stream_start_liga_a_cadencia_ociosa_e_idle_fps_zero_desliga(self):
        self.ok("stream.start", {"fps": 30, "max_width": 30})
        self.assertIsNotNone(self.server._stream.idle_interval)
        self.ok("stream.start", {"fps": 30, "max_width": 30, "idle_fps": 0})
        self.assertIsNone(self.server._stream.idle_interval)
        self.ok("stream.stop")
