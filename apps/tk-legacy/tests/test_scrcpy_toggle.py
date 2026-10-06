"""Toggle do espelho scrcpy pela janela principal.

Estava na suite do motor, mas so exercita comportamento de janela: o motor
precisa ser testavel sem servidor grafico.
"""

import unittest
from unittest.mock import patch


class TestScrcpyToggleFromUI(unittest.TestCase):
    @patch("mobaile_tk.main_window.messagebox")
    def test_ui_scrcpy_toggle_no_device(self, mock_msgbox):
        import tkinter as tk

        from mobaile_tk.main_window import MobileRecorderApp
        try:
            root = tk.Tk()
        except tk.TclError as exc:
            self.skipTest(f"Sessão gráfica Tkinter indisponível: {exc}")
        self.addCleanup(root.destroy)
        root.withdraw()
        app = MobileRecorderApp(root)
        self.addCleanup(app._stop_passive_listeners)
        self.addCleanup(app.watcher.stop)
        self.addCleanup(app.stream_engine.stop)
        app.active_platform = "android"
        app.selected_device = None
        app._toggle_scrcpy_mirror()
        mock_msgbox.showwarning.assert_called_once()


if __name__ == "__main__":
    unittest.main()
