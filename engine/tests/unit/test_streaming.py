"""Detector de diferenca e laco de streaming.

O ponto central: o quadro so sobe para a apresentacao quando algo mudou. Antes
o callback era chamado a cada ciclo, e uma tela parada custava um redesenho
completo por ciclo, indefinidamente.
"""

import time
import unittest

from PIL import Image

from mobaile.services.streaming import RealTimeStreamEngine, ScreenDiffDetector


def tela(cor) -> Image.Image:
    return Image.new("RGB", (200, 400), cor)


class TestScreenDiffDetector(unittest.TestCase):
    def test_primeiro_quadro_estabelece_a_linha_de_base(self):
        detector = ScreenDiffDetector(diff_threshold=3.5, settle_delay=0.1)
        mudou, _estabilizou, score = detector.process_frame(tela("black"))
        self.assertFalse(mudou)
        self.assertEqual(score, 0.0)

    def test_quadro_identico_nao_conta_como_mudanca(self):
        detector = ScreenDiffDetector(diff_threshold=3.5, settle_delay=0.1)
        detector.process_frame(tela("black"))
        mudou, _, score = detector.process_frame(tela("black"))
        self.assertFalse(mudou)
        self.assertEqual(score, 0.0)

    def test_mudanca_forte_e_detectada(self):
        detector = ScreenDiffDetector(diff_threshold=3.5, settle_delay=0.1)
        detector.process_frame(tela("black"))
        mudou, _, score = detector.process_frame(tela("white"))
        self.assertTrue(mudou)
        self.assertGreater(score, 3.5)

    def test_estabilizacao_dispara_apos_o_intervalo(self):
        detector = ScreenDiffDetector(diff_threshold=3.5, settle_delay=0.05)
        detector.process_frame(tela("black"))
        detector.process_frame(tela("white"))
        time.sleep(0.08)
        _, estabilizou, _ = detector.process_frame(tela("white"))
        self.assertTrue(estabilizou)

    def test_reset_limpa_a_linha_de_base(self):
        detector = ScreenDiffDetector()
        detector.process_frame(tela("black"))
        detector.reset()
        self.assertIsNone(detector.last_thumb)


class TestRealTimeStreamEngine(unittest.TestCase):
    def test_tela_parada_nao_gera_redesenho_continuo(self):
        quadros = []
        parada = tela("black")
        motor = RealTimeStreamEngine(
            get_frame_fn=lambda: parada,
            on_frame_callback=quadros.append,
            on_screen_settled_callback=lambda: None,
            fps=60,
        )
        motor.start()
        time.sleep(0.5)
        motor.stop()

        self.assertEqual(len(quadros), 1, "so o primeiro quadro deveria subir")
        self.assertGreater(motor.stats.frames_captured, 5, "a captura continua rodando")
        self.assertGreater(motor.stats.frames_skipped, 0)
        self.assertGreater(motor.stats.skip_ratio, 0.5)

    def test_mudanca_de_tela_sobe_o_quadro(self):
        cores = ["black", "white", "red", "blue"]
        estado = {"i": 0}

        def proximo():
            cor = cores[min(estado["i"], len(cores) - 1)]
            estado["i"] += 1
            return tela(cor)

        quadros = []
        motor = RealTimeStreamEngine(
            get_frame_fn=proximo,
            on_frame_callback=quadros.append,
            on_screen_settled_callback=lambda: None,
            fps=60,
        )
        motor.start()
        time.sleep(0.4)
        motor.stop()
        self.assertGreaterEqual(len(quadros), len(cores))

    def test_quadro_com_erro_nao_mata_o_laco(self):
        estado = {"n": 0}

        def instavel():
            estado["n"] += 1
            if estado["n"] < 3:
                raise RuntimeError("dispositivo desconectou")
            return tela("black")

        quadros = []
        motor = RealTimeStreamEngine(
            get_frame_fn=instavel,
            on_frame_callback=quadros.append,
            on_screen_settled_callback=lambda: None,
            fps=60,
        )
        motor.start()
        time.sleep(0.3)
        motor.stop()
        self.assertGreaterEqual(len(quadros), 1, "o laco se recupera depois da falha")

    def test_stop_encerra_rapido_mesmo_pausado(self):
        motor = RealTimeStreamEngine(
            get_frame_fn=lambda: tela("black"),
            on_frame_callback=lambda _f: None,
            on_screen_settled_callback=lambda: None,
            fps=1,
        )
        motor.start()
        motor.pause()
        inicio = time.time()
        motor.stop()
        self.assertLess(time.time() - inicio, 1.5, "stop nao pode esperar o ciclo inteiro")


if __name__ == "__main__":
    unittest.main()
