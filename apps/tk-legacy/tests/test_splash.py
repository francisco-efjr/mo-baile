import unittest
from unittest.mock import MagicMock

from mobaile_tk.splash import calculate_apple_geometry, get_splash_video_path


class TestSplashAndGeometry(unittest.TestCase):
    def test_calculate_apple_geometry_standard(self):
        mock_root = MagicMock()
        mock_root.winfo_screenwidth.return_value = 1920
        mock_root.winfo_screenheight.return_value = 1080

        w, h, x, y = calculate_apple_geometry(mock_root)
        self.assertEqual(w, 1440)
        self.assertEqual(h, 900)
        self.assertEqual(x, (1920 - 1440) // 2)
        self.assertEqual(y, max(25, (1080 - 900) // 2 - 25))

    def test_calculate_apple_geometry_small_screen(self):
        mock_root = MagicMock()
        mock_root.winfo_screenwidth.return_value = 1280
        mock_root.winfo_screenheight.return_value = 800

        w, h, x, y = calculate_apple_geometry(mock_root)
        self.assertGreaterEqual(w, 1080)
        self.assertGreaterEqual(h, 720)
        self.assertLessEqual(w, 1280)
        self.assertLessEqual(h, 800)

    def test_get_splash_video_path(self):
        path = get_splash_video_path()
        self.assertIsNotNone(path)
        self.assertTrue(path.endswith("splash_app.mp4"))

    def test_get_splash_mascot_and_bg_paths(self):
        from mobaile_tk.splash import get_splash_bg_path, get_splash_mascot_path
        mascot = get_splash_mascot_path()
        self.assertIsNotNone(mascot)
        self.assertTrue(mascot.endswith("mascot.png"))

        bg = get_splash_bg_path()
        self.assertIsNotNone(bg)
        self.assertTrue(bg.endswith("splash_bg.png"))

    def test_splash_screen_lifecycle(self):
        import tkinter as tk

        from mobaile_tk.splash import SplashScreen
        try:
            root = tk.Tk()
            root.withdraw()
            completed = []
            splash = SplashScreen(
                on_complete=lambda: completed.append(True),
                root=root,
            )
            self.assertEqual(splash.width, 1280)
            self.assertEqual(splash.height, 720)
            self.assertFalse(splash.is_closed)
            splash._close()
            self.assertTrue(splash.is_closed)
            self.assertEqual(len(completed), 1)
            root.destroy()
        except tk.TclError:
            pass


if __name__ == "__main__":
    unittest.main()
