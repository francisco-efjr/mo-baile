"""A-6: ligar o modo passivo sem Quartz no iOS nao pode dizer "ativado".

Os metodos sao chamados num stub, sem abrir janela: o que se prova e a
decisao de status e de flag, nao o desenho.
"""

import unittest
from unittest.mock import patch

from mobaile.domain.errors import AdapterError
from mobaile_tk.main_window import MobileRecorderApp


class FlagFalsa:
    def __init__(self, valor):
        self.valor = valor

    def get(self):
        return self.valor

    def set(self, valor):
        self.valor = valor


class Stub:
    _start_passive_listeners = MobileRecorderApp._start_passive_listeners
    _stop_passive_listeners = MobileRecorderApp._stop_passive_listeners
    _on_passive_mode_toggled = MobileRecorderApp._on_passive_mode_toggled

    def __init__(self, plataforma):
        self.passive_mode_var = FlagFalsa(True)
        self.active_platform = plataforma
        self.selected_device = None
        self.android_listener = None
        self.ios_listener = None
        self.status = []

    def _set_status(self, msg):
        self.status.append(msg)

    def _on_passive_tap(self, x, y):
        pass


class TestModoPassivoSemQuartz(unittest.TestCase):
    def test_falha_no_ios_mostra_o_motivo_e_desmarca(self):
        app = Stub("ios")
        with patch("mobaile_tk.main_window.IOSPassiveListener.start", side_effect=AdapterError("sem Quartz")):
            app._on_passive_mode_toggled()
        self.assertFalse(app.passive_mode_var.get())
        self.assertIsNone(app.ios_listener)
        self.assertNotIn("Modo Passivo ativado.", app.status)
        self.assertTrue(any("sem Quartz" in m for m in app.status), app.status)

    def test_sucesso_no_ios_diz_ativado(self):
        app = Stub("ios")
        with patch("mobaile_tk.main_window.IOSPassiveListener.start", return_value=None):
            app._on_passive_mode_toggled()
        self.assertTrue(app.passive_mode_var.get())
        self.assertEqual(app.status[-1], "Modo Passivo ativado.")


if __name__ == "__main__":
    unittest.main()
