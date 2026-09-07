"""Deteccao automatica de alvos conectados.

O servico existia no projeto e nao era usado por ninguem: nenhuma chamada, zero
cobertura. Como "descoberta automatica de dispositivos" e feature anunciada do
produto, o caminho certo era liga-lo ao contrato, e nao remove-lo.
"""

import threading
import time
import unittest
from unittest.mock import MagicMock

from mobaile.services.devices import DeviceWatcher


class FakeADB:
    def __init__(self, devices=None):
        self.devices = devices or []

    def list_devices(self):
        return list(self.devices)


class FakeIOS:
    def __init__(self, sims=None):
        self.sims = sims or []

    def list_booted_simulators(self):
        return list(self.sims)


def watcher(adb=None, ios=None, platform="android", handler=None):
    return DeviceWatcher(
        adb_bridge=adb or FakeADB(),
        ios_bridge=ios or FakeIOS(),
        on_device_changed=handler or MagicMock(),
        target_platform=platform,
        poll_interval=0.02,
    )


class TestDeteccao(unittest.TestCase):
    def test_avisa_quando_o_aparelho_aparece(self):
        eventos = []
        adb = FakeADB()
        w = watcher(adb=adb, handler=lambda p, d: eventos.append((p, d)))

        self.assertIsNone(w.poll_once())
        adb.devices = [("emulator-5554", "device")]
        self.assertEqual(w.poll_once(), "emulator-5554")
        self.assertEqual(eventos, [("android", "emulator-5554")])

    def test_nao_repete_aviso_para_o_mesmo_aparelho(self):
        eventos = []
        adb = FakeADB([("emulator-5554", "device")])
        w = watcher(adb=adb, handler=lambda p, d: eventos.append((p, d)))
        for _ in range(5):
            w.poll_once()
        self.assertEqual(len(eventos), 1, "so a transicao gera evento")

    def test_avisa_quando_o_aparelho_some(self):
        eventos = []
        adb = FakeADB([("emulator-5554", "device")])
        w = watcher(adb=adb, handler=lambda p, d: eventos.append((p, d)))
        w.poll_once()
        adb.devices = []
        self.assertIsNone(w.poll_once())
        self.assertEqual(eventos[-1], ("none", ""))

    def test_aparelho_nao_autorizado_e_ignorado(self):
        # Selecionar um alvo em `unauthorized` faria toda operacao seguinte
        # falhar sem explicacao util para quem esta usando.
        adb = FakeADB([("R58N12ABCDE", "unauthorized"), ("emulator-5554", "offline")])
        self.assertIsNone(watcher(adb=adb).poll_once())

    def test_troca_de_plataforma_forca_nova_deteccao(self):
        eventos = []
        adb = FakeADB([("emulator-5554", "device")])
        ios = FakeIOS([("UDID-1", "iPhone 15")])
        w = watcher(adb=adb, ios=ios, platform="android", handler=lambda p, d: eventos.append((p, d)))
        w.poll_once()
        w.set_platform("ios")
        w.poll_once()
        self.assertEqual(eventos, [("android", "emulator-5554"), ("ios", "UDID-1")])

    def test_falha_do_adb_nao_derruba_a_varredura(self):
        class ADBQuebrado:
            def list_devices(self):
                raise OSError("adb morreu")

        w = watcher(adb=ADBQuebrado())
        self.assertIsNone(w.poll_once(), "falha vira log, nao excecao")

    def test_plataforma_desconhecida_nao_encontra_nada(self):
        self.assertIsNone(watcher(platform="symbian").poll_once())


class TestCicloDeVida(unittest.TestCase):
    def test_start_e_stop(self):
        w = watcher()
        self.assertFalse(w.is_running())
        w.start()
        self.assertTrue(w.is_running())
        w.stop()
        self.assertFalse(w.is_running())

    def test_start_repetido_nao_cria_segunda_thread(self):
        antes = threading.active_count()
        w = watcher()
        w.start()
        w.start()
        self.assertEqual(threading.active_count(), antes + 1)
        w.stop()

    def test_stop_e_notado_imediatamente(self):
        # Com `time.sleep(poll_interval)` o encerramento esperava o ciclo
        # inteiro; com intervalo grande, a aplicacao parecia travar ao fechar.
        w = DeviceWatcher(
            adb_bridge=FakeADB(), ios_bridge=FakeIOS(),
            on_device_changed=MagicMock(), target_platform="android",
            poll_interval=30.0,
        )
        w.start()
        time.sleep(0.05)
        inicio = time.time()
        w.stop()
        self.assertLess(time.time() - inicio, 1.0, "stop nao pode esperar o intervalo de varredura")

    def test_laco_detecta_de_verdade_em_execucao(self):
        eventos = []
        adb = FakeADB()
        w = watcher(adb=adb, handler=lambda p, d: eventos.append((p, d)))
        w.start()
        try:
            time.sleep(0.05)
            adb.devices = [("emulator-5554", "device")]
            deadline = time.time() + 2.0
            while not eventos and time.time() < deadline:
                time.sleep(0.02)
        finally:
            w.stop()
        self.assertEqual(eventos, [("android", "emulator-5554")])


if __name__ == "__main__":
    unittest.main()
