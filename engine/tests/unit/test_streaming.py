"""Detector de diferenca e laco de streaming.

O ponto central: o quadro so sobe para a apresentacao quando algo mudou. Antes
o callback era chamado a cada ciclo, e uma tela parada custava um redesenho
completo por ciclo, indefinidamente.
"""

import threading
import time
import unittest
from unittest.mock import patch

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

    def test_mudanca_localizada_pequena_e_detectada(self):
        detector = ScreenDiffDetector(diff_threshold=3.5, settle_delay=0.1)
        base = tela("black")
        detector.process_frame(base)
        # Cria uma pequena alteração concentrada (ex: toggle switch acionado)
        com_toggle = tela("black")
        for x in range(30, 60):
            for y in range(30, 60):
                com_toggle.putpixel((x, y), (255, 255, 255))
        mudou, _, _ = detector.process_frame(com_toggle)
        self.assertTrue(mudou, "micro-mudança localizada deve ser detectada")

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
    def test_stop_descarta_captura_que_termina_depois_da_parada(self):
        started, release = threading.Event(), threading.Event()
        frames, settled = [], []

        def capture():
            started.set()
            release.wait(3)
            return tela("black")

        motor = RealTimeStreamEngine(capture, frames.append, lambda: settled.append(True), fps=60)
        motor.start()
        worker = motor._thread
        try:
            self.assertTrue(started.wait(1))
            with patch.object(worker, "join"):
                motor.stop()
            release.set()
            worker.join(1)
            self.assertFalse(worker.is_alive())
            self.assertEqual(frames, [], "nenhum quadro pode sair depois de stop")
            self.assertEqual(settled, [])
        finally:
            motor._stop_event.set()
            release.set()
            worker.join(1)

    def test_start_nao_ressuscita_thread_que_ainda_esta_parando(self):
        started, release = threading.Event(), threading.Event()

        def capture():
            started.set()
            release.wait(3)
            return tela("black")

        motor = RealTimeStreamEngine(capture, lambda _f: None, lambda: None, fps=60)
        motor.start()
        worker = motor._thread
        try:
            self.assertTrue(started.wait(1))
            with patch.object(worker, "join"):
                motor.stop()
            motor.start()
            self.assertIs(motor._thread, worker, "captura anterior ainda viva: nao pode criar outra")
            self.assertTrue(motor._stop_event.is_set())
        finally:
            motor._stop_event.set()
            release.set()
            worker.join(1)
            if motor._thread is not None and motor._thread is not worker:
                motor._thread.join(1)

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

    def test_pausado_nao_captura(self):
        """PERF-1: com a janela oculta o espelho para de capturar, nao so de emitir."""
        capturas = {"n": 0}

        def captura():
            capturas["n"] += 1
            return tela("black")

        motor = RealTimeStreamEngine(captura, lambda _f: None, lambda: None, fps=60)
        motor.start()
        try:
            time.sleep(0.15)
            motor.pause()
            time.sleep(0.05)
            antes = capturas["n"]
            time.sleep(0.4)
            self.assertLessEqual(capturas["n"] - antes, 1, "pausado, o laco nao pode seguir capturando")
            self.assertTrue(motor.paused)
        finally:
            motor.stop()

    def test_retomar_reenvia_o_quadro_mesmo_com_a_tela_igual(self):
        """Ao voltar, a moldura recebe quadro novo na hora, mesmo sem mudanca."""
        quadros = []
        motor = RealTimeStreamEngine(lambda: tela("black"), quadros.append, lambda: None, fps=60)
        motor.start()
        try:
            time.sleep(0.15)
            motor.pause()
            time.sleep(0.05)
            antes = len(quadros)
            inicio = time.monotonic()
            motor.resume()
            while len(quadros) == antes and time.monotonic() - inicio < 1.0:
                time.sleep(0.01)
            self.assertEqual(len(quadros), antes + 1)
            self.assertLess(time.monotonic() - inicio, 0.5, "o quadro de retomada tem de chegar em ate 500 ms")
            self.assertFalse(motor.paused)
        finally:
            motor.stop()


class TestCadenciaAdaptativa(unittest.TestCase):
    """PERF-2: tela parada espaca a captura; toque ou mudanca voltam ao normal."""

    def contador(self, cor="black"):
        estado = {"n": 0, "cor": cor}

        def captura():
            estado["n"] += 1
            return tela(estado["cor"])

        return estado, captura

    def taxa(self, estado, segundos):
        antes = estado["n"]
        time.sleep(segundos)
        return (estado["n"] - antes) / segundos

    def test_tela_parada_baixa_a_cadencia_depois_de_n_quadros_iguais(self):
        estado, captura = self.contador()
        motor = RealTimeStreamEngine(captura, lambda _f: None, lambda: None, fps=50,
                                     idle_fps=4, idle_after=3, idle_grace_s=0)
        motor.start()
        try:
            time.sleep(0.3)
            self.assertTrue(motor.idle)
            self.assertLessEqual(self.taxa(estado, 1.0), 6, "parada, a captura cai para ~4 por segundo")
        finally:
            motor.stop()

    def test_toque_volta_a_cadencia_normal_na_hora(self):
        estado, captura = self.contador()
        motor = RealTimeStreamEngine(captura, lambda _f: None, lambda: None, fps=50,
                                     idle_fps=1, idle_after=3, idle_grace_s=0.3)
        motor.start()
        try:
            time.sleep(0.6)
            self.assertTrue(motor.idle)
            antes = estado["n"]
            motor.wake()
            time.sleep(0.05)
            self.assertGreater(estado["n"], antes, "o toque acorda a captura sem esperar o intervalo ocioso")
            self.assertFalse(motor.idle)
            self.assertGreaterEqual(self.taxa(estado, 0.2), 20, "depois do toque, cadencia normal")
        finally:
            motor.stop()

    def test_quadro_diferente_sai_do_modo_ocioso(self):
        estado, captura = self.contador()
        quadros = []
        motor = RealTimeStreamEngine(captura, quadros.append, lambda: None, fps=50,
                                     idle_fps=2, idle_after=3, idle_grace_s=0)
        motor.start()
        try:
            time.sleep(0.4)
            self.assertTrue(motor.idle)
            estado["cor"] = "white"
            limite = time.monotonic() + 1.5
            while len(quadros) < 2 and time.monotonic() < limite:
                time.sleep(0.01)
            self.assertEqual(len(quadros), 2)
            self.assertFalse(motor.idle, "tela mudou: volta a cadencia normal")
        finally:
            motor.stop()

    def test_sem_idle_fps_a_cadencia_e_a_de_sempre(self):
        estado, captura = self.contador()
        motor = RealTimeStreamEngine(captura, lambda _f: None, lambda: None, fps=50)
        motor.start()
        try:
            time.sleep(0.3)
            self.assertFalse(motor.idle)
            self.assertGreaterEqual(self.taxa(estado, 0.5), 25)
        finally:
            motor.stop()

    def test_captura_mais_lenta_que_o_intervalo_tambem_descansa(self):
        """O laco antigo esperava 10 ms e capturava de novo: thread sempre ocupada."""
        estado = {"n": 0}

        def lenta():
            estado["n"] += 1
            time.sleep(0.08)
            return tela("black")

        motor = RealTimeStreamEngine(lenta, lambda _f: None, lambda: None, fps=60)
        motor.start()
        try:
            time.sleep(0.2)
            self.assertLessEqual(self.taxa(estado, 1.2), 8.5, "80 ms de captura pedem pelo menos 50 ms de descanso")
        finally:
            motor.stop()


if __name__ == "__main__":
    unittest.main()
