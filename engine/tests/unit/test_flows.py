import ast
import os
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from mobaile.services.codegen import CodeGenerator, LocatorStrategy
from mobaile.services.flows import (
    generate_hidden_runner_script,
    verify_preconditions,
)
from mobaile.services.hierarchy import UIElement


class TestFlowRunner(unittest.TestCase):
    def setUp(self):
        self.generator = CodeGenerator(page_objects_key="test_objs")
        self.sample_elem_android = UIElement(
            tag="android.widget.Button",
            class_name="android.widget.Button",
            resource_id="com.example:id/btn_entrar",
            text="Entrar",
            content_desc="Entrar na conta",
            clickable=True,
            bounds=(100, 200, 300, 250),
            area=10000,
            package="com.example.app",
            platform="android",
        )
        self.sample_elem_ios = UIElement(
            tag="XCUIElementTypeButton",
            class_name="XCUIElementTypeButton",
            resource_id="btn_confirmar",
            text="Confirmar",
            content_desc="Confirmar ação",
            clickable=True,
            bounds=(50, 150, 250, 200),
            area=10000,
            package="com.apple.test",
            platform="ios",
        )

    def test_steps_recorded_in_codegen(self):
        self.assertEqual(len(self.generator.get_steps()), 0)

        self.generator.generate_entry(self.sample_elem_android, strategy=LocatorStrategy.POSITION, click_coord=(150, 225))
        self.generator.generate_entry(self.sample_elem_ios, strategy=LocatorStrategy.ID, click_coord=(100, 175))

        steps = self.generator.get_steps()
        self.assertEqual(len(steps), 2)

        # Primeiro passo (Android)
        step1 = steps[0]
        self.assertEqual(step1.step_num, 1)
        self.assertEqual(step1.action_type, "click")
        self.assertEqual(step1.strategy, LocatorStrategy.POSITION)
        self.assertEqual(step1.coords, (150, 225))
        self.assertEqual(step1.platform, "android")

        # Segundo passo (iOS)
        step2 = steps[1]
        self.assertEqual(step2.step_num, 2)
        self.assertEqual(step2.strategy, LocatorStrategy.ID)
        self.assertEqual(step2.platform, "ios")

        # Limpeza
        self.generator.reset()
        self.assertEqual(len(self.generator.get_steps()), 0)

    @patch("subprocess.run")
    def test_verify_preconditions_android_success(self, mock_run):
        mock_res = MagicMock()
        mock_res.returncode = 0
        mock_res.stdout = b"List of devices attached\nemulator-5554\tdevice\n"
        mock_run.return_value = mock_res

        ok, msg = verify_preconditions(platform="android", device_id="emulator-5554", adb_path="adb")
        self.assertTrue(ok)
        self.assertIn("pronto", msg.lower())

    @patch("subprocess.run")
    def test_verify_preconditions_android_offline(self, mock_run):
        mock_res = MagicMock()
        mock_res.returncode = 0
        mock_res.stdout = b"List of devices attached\nemulator-5554\toffline\n"
        mock_run.return_value = mock_res

        ok, msg = verify_preconditions(platform="android", device_id="emulator-5554", adb_path="adb")
        self.assertFalse(ok)
        self.assertIn("offline", msg.lower())

    def test_verify_preconditions_android_no_device(self):
        ok, msg = verify_preconditions(platform="android", device_id=None)
        self.assertFalse(ok)
        self.assertIn("nenhum dispositivo", msg.lower())

    @patch("subprocess.run")
    @patch("requests.get")
    def test_verify_preconditions_ios_success(self, mock_get, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout=b"iPhone 15 (Booted)")
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"sessionId": "test-session-123"}
        mock_get.return_value = mock_resp

        ok, msg = verify_preconditions(platform="ios", device_id="iPhone 15", wda_url="http://localhost:8100")
        self.assertTrue(ok)
        self.assertIn("prontos", msg.lower())

    def test_generate_hidden_runner_script_syntax_validity(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, ".flow_runner.py")
            self.generator.generate_entry(self.sample_elem_android, strategy=LocatorStrategy.POSITION, click_coord=(120, 210))
            steps = self.generator.get_steps()

            script_path = generate_hidden_runner_script(
                steps=steps,
                platform="android",
                device_id="emulator-5554",
                adb_path="adb",
                output_path=out_file,
            )

            self.assertTrue(os.path.isfile(script_path))
            self.assertTrue(os.path.basename(script_path).startswith("."))

            # Valida sintaxe Python com ast.parse
            with open(script_path, encoding="utf-8") as f:
                content = f.read()
            parsed = ast.parse(content)
            self.assertIsNotNone(parsed)

            # Valida se passos e variáveis constam no código gerado
            self.assertIn("emulator-5554", content)
            self.assertIn("android", content)
            self.assertIn("BOTAO_ENTRAR", content)
            self.assertIn("120", content)
            self.assertIn("210", content)


if __name__ == "__main__":
    unittest.main()
