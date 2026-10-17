"""M5: leitores de fundo que morriam em silencio e deixavam a tela dizendo "ligado".

Cada caso aqui era um jeito de a escuta (passiva ou de analytics) parar sem que
a pessoa soubesse: um `dumpsys` lento, um callback que levanta, o Python do app
sem Quartz, o `logcat` que morre com o cabo.
"""

from __future__ import annotations

import io
import itertools
import subprocess
import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters import input_events
from mobaile.adapters.analytics_logcat import FirebaseAnalyticsListener
from mobaile.adapters.input_events import AndroidPassiveListener, IOSPassiveListener
from mobaile.domain.errors import AdapterError
from mobaile.rpc.server import EngineServer


class TestToquePassivoNoServidor(unittest.TestCase):
    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)
        self.server.adb = MagicMock()
        self.server.device_id = "emulator-5554"
        self.avisos = []
        self.server.notify = lambda method, params=None: self.avisos.append((method, params))

    def test_dumpsys_lento_nao_derruba_a_checagem_do_teclado(self):
        self.server.adb._device_args.return_value = ["-s", "emulator-5554"]
        self.server.adb._run_cmd.side_effect = subprocess.TimeoutExpired("adb", 4)
        self.assertFalse(self.server._teclado_aberto())

    def test_erro_inesperado_no_passo_vira_aviso_e_nao_mata_a_escuta(self):
        self.server._teclado_aberto = lambda: False
        with self.server._state_lock:
            self.server.current_xml = "<hierarchy/>"
        self.server.codegen_record = MagicMock(side_effect=RuntimeError("boom"))
        self.server._on_passive_tap(10, 20)  # nao levanta
        self.assertEqual([m for m, _ in self.avisos], ["passive.skipped"])
        self.assertIn("boom", self.avisos[0][1]["reason"])


class TestEscutaPassivaAndroid(unittest.TestCase):
    @patch("subprocess.Popen")
    def test_callback_que_levanta_nao_derruba_a_thread_do_getevent(self, popen):
        toque = [
            "/dev/input/event8: EV_ABS       ABS_MT_TRACKING_ID   00000001\n",
            "/dev/input/event8: EV_KEY       BTN_TOUCH            DOWN\n",
            "/dev/input/event8: EV_ABS       ABS_MT_POSITION_X    00000870\n",
            "/dev/input/event8: EV_ABS       ABS_MT_POSITION_Y    000012c0\n",
            "/dev/input/event8: EV_SYN       SYN_REPORT           00000000\n",
            "/dev/input/event8: EV_ABS       ABS_MT_TRACKING_ID   ffffffff\n",
            "/dev/input/event8: EV_KEY       BTN_TOUCH            UP\n",
            "/dev/input/event8: EV_SYN       SYN_REPORT           00000000\n",
        ]
        proc = MagicMock()
        proc.stdout = toque + toque
        popen.return_value = proc

        recebidos = []

        def callback(x, y):
            recebidos.append((x, y))
            if len(recebidos) == 1:
                raise RuntimeError("falha no primeiro toque")

        listener = AndroidPassiveListener(
            adb_path="adb",
            device_id="DEV123",
            on_tap_callback=callback,
            screen_size=(1080, 2400),
            digitizer_bounds=("/dev/input/event8", 4320, 9600),
        )
        relogio = itertools.count(1000.0, 1.0)  # os dois toques ficam > 0,15 s afastados
        with patch.object(input_events.time, "time", side_effect=lambda: next(relogio)):
            listener._listen_adb_loop()
        self.assertEqual(len(recebidos), 2, "o segundo toque tem que chegar ao callback")


class TestEscutaPassivaIOS(unittest.TestCase):
    def test_sem_quartz_o_start_diz_o_que_falta(self):
        listener = IOSPassiveListener(on_tap_callback=lambda x, y: None)
        with patch.object(input_events, "QUARTZ_AVAILABLE", False), self.assertRaises(AdapterError) as ctx:
            listener.start()
        self.assertIn("Quartz", str(ctx.exception))


class TestAnalyticsMorreSemAvisar(unittest.TestCase):
    def setUp(self):
        self.listener = FirebaseAnalyticsListener()
        self.listener.adb.adb_path = "/falso/adb"

    def test_fim_da_leitura_marca_como_parado(self):
        proc = MagicMock()
        proc.stdout.readline.return_value = ""  # EOF: o logcat morreu
        self.listener._proc = proc
        self.listener._is_running = True
        self.listener.active_source = "android"
        self.listener._stream_reader()
        self.assertFalse(self.listener.is_running())

    def test_start_com_processo_morto_reinicia_em_vez_de_dizer_que_ja_ligou(self):
        proc_vivo, proc_morto = MagicMock(), MagicMock()
        proc_vivo.poll.return_value = None
        proc_morto.poll.return_value = 1
        with patch("subprocess.Popen", side_effect=[proc_vivo, proc_vivo]) as popen, \
             patch("threading.Thread"), patch("subprocess.run"):
            self.assertTrue(self.listener.start(platform="ios", device_id="ABCD-1234"))
            self.listener._proc = proc_morto  # o processo morreu, a flag nao
            self.assertTrue(self.listener.start(platform="ios", device_id="ABCD-1234"))
        self.assertEqual(popen.call_count, 2, "o start deve religar a coleta")


if __name__ == "__main__":
    unittest.main()
