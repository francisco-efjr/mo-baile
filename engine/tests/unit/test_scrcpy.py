import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters.scrcpy import ScrcpyManager


class TestScrcpyManager(unittest.TestCase):
    def test_build_command_default(self):
        manager = ScrcpyManager(scrcpy_path="/opt/homebrew/bin/scrcpy")
        cmd = manager.build_command("ZY22L3CH3X")
        self.assertEqual(cmd[0], "/opt/homebrew/bin/scrcpy")
        self.assertIn("-s", cmd)
        self.assertIn("ZY22L3CH3X", cmd)
        self.assertIn("--max-fps=60", cmd)
        self.assertIn("--stay-awake", cmd)
        self.assertIn("--no-audio", cmd)

    # `is_available()` confere se o binario existe no disco. Sem o patch, o
    # teste so passava em maquina com scrcpy instalado naquele caminho exato.
    @patch("os.path.isfile", return_value=True)
    @patch("subprocess.Popen")
    def test_start_and_stop_mirror(self, mock_popen, _mock_isfile):
        mock_process = MagicMock()
        mock_process.poll.return_value = None
        mock_popen.return_value = mock_process

        manager = ScrcpyManager(scrcpy_path="/opt/homebrew/bin/scrcpy")
        success = manager.start_mirror("ZY22L3CH3X")
        self.assertTrue(success)
        self.assertTrue(manager.is_running())

        manager.stop_mirror()
        mock_process.terminate.assert_called_once()
        self.assertFalse(manager.is_running())

    def test_not_available_when_path_none(self):
        manager = ScrcpyManager(scrcpy_path=None)
        manager.scrcpy_path = None
        self.assertFalse(manager.is_available())
        self.assertFalse(manager.start_mirror("ZY22L3CH3X"))

if __name__ == "__main__":
    unittest.main()
