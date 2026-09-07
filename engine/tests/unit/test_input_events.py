import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.input_events import AndroidPassiveListener, get_video_viewport


class TestPassiveListener(unittest.TestCase):
    def test_get_video_viewport_letterbox(self):
        # Janela mais estreita que o aspecto do dispositivo (1080x2400 -> ratio 0.45)
        # Janela: 327 x 762 (ratio 0.429) -> Letterbox (barras pretas no topo e embaixo)
        vp_x, vp_y, vp_w, vp_h = get_video_viewport(327, 762, 1080, 2400)
        self.assertEqual(vp_x, 0)
        self.assertEqual(vp_w, 327)
        self.assertGreater(vp_h, 700)
        self.assertLessEqual(vp_h, 762)
        self.assertGreaterEqual(vp_y, 0)

    def test_get_video_viewport_pillarbox(self):
        # Janela mais larga que o dispositivo (ex: tablet ou janela expandida)
        # Janela: 600 x 600 (ratio 1.0) vs ratio 0.45 -> Pillarbox (barras pretas laterais)
        vp_x, vp_y, vp_w, vp_h = get_video_viewport(600, 600, 1080, 2400)
        self.assertEqual(vp_y, 0)
        self.assertEqual(vp_h, 600)
        self.assertEqual(vp_w, int(600 * (1080 / 2400)))
        self.assertEqual(vp_x, (600 - vp_w) // 2)

    def test_get_video_viewport_exact(self):
        # Proporções idênticas
        vp_x, vp_y, vp_w, vp_h = get_video_viewport(540, 1200, 1080, 2400)
        self.assertEqual((vp_x, vp_y, vp_w, vp_h), (0, 0, 540, 1200))

    def test_get_video_viewport_invalid(self):
        vp = get_video_viewport(0, 0, 1080, 2400)
        self.assertEqual(vp, (0, 0, 1, 1))

    @patch("subprocess.Popen")
    def test_android_passive_listener_adb_packet_parsing(self, mock_popen):
        # Simula fluxo getevent com tela 1080x2400 e digitador 4320x9600
        mock_proc = MagicMock()
        # Mock lines: touch down no centro (raw X: 0x870 = 2160, raw Y: 0x12c0 = 4800)
        mock_proc.stdout = [
            "/dev/input/event8: EV_ABS       ABS_MT_TRACKING_ID   00000001\n",
            "/dev/input/event8: EV_KEY       BTN_TOUCH            DOWN\n",
            "/dev/input/event8: EV_ABS       ABS_MT_POSITION_X    00000870\n",
            "/dev/input/event8: EV_ABS       ABS_MT_POSITION_Y    000012c0\n",
            "/dev/input/event8: EV_SYN       SYN_REPORT           00000000\n",
            # Movimento no mesmo toque (não deve disparar outro callback)
            "/dev/input/event8: EV_ABS       ABS_MT_POSITION_X    00000880\n",
            "/dev/input/event8: EV_SYN       SYN_REPORT           00000000\n",
            # Dedo levantado
            "/dev/input/event8: EV_ABS       ABS_MT_TRACKING_ID   ffffffff\n",
            "/dev/input/event8: EV_KEY       BTN_TOUCH            UP\n",
            "/dev/input/event8: EV_SYN       SYN_REPORT           00000000\n",
        ]
        mock_popen.return_value = mock_proc

        taps = []
        def tap_cb(x, y):
            taps.append((x, y))

        listener = AndroidPassiveListener(
            adb_path="adb",
            device_id="DEV123",
            on_tap_callback=tap_cb,
            screen_size=(1080, 2400),
            digitizer_bounds=("/dev/input/event8", 4320, 9600),
        )

        listener._listen_adb_loop()

        # Deve ter registrado exatamente 1 toque
        self.assertEqual(len(taps), 1)
        target_x, target_y = taps[0]
        # (2160 / 4320) * 1080 = 540
        self.assertEqual(target_x, 540)
        # (4800 / 9600) * 2400 = 1200
        self.assertEqual(target_y, 1200)

    def test_adb_bridge_get_screen_size_parsing(self):
        bridge = ADBBridge()
        with patch.object(bridge, "_run_cmd") as mock_run:
            mock_run.return_value = (0, b"Physical size: 1080x2400\n", b"")
            size = bridge.get_screen_size("DEV123")
            self.assertEqual(size, (1080, 2400))

    def test_adb_bridge_get_digitizer_bounds_parsing(self):
        bridge = ADBBridge()
        with patch.object(bridge, "_run_cmd") as mock_run:
            sample_output = (
                b"add device 4: /dev/input/event8\n"
                b"  name:     \"fts_ts\"\n"
                b"  events:\n"
                b"    ABS (0003): 0035  : value 0, min 0, max 4320, fuzz 0\n"
                b"                0036  : value 0, min 0, max 9600, fuzz 0\n"
            )
            mock_run.return_value = (0, sample_output, b"")
            dev, max_x, max_y = bridge.get_digitizer_bounds("DEV123")
            self.assertEqual(dev, "/dev/input/event8")
            self.assertEqual(max_x, 4320)
            self.assertEqual(max_y, 9600)


if __name__ == "__main__":
    unittest.main()
