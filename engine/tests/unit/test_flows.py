import ast
import os
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import MagicMock, patch

from mobaile.services.codegen import CodeGenerator, LocatorStrategy
from mobaile.services.flows import (
    FlowExecution,
    generate_hidden_runner_script,
    run_flow_in_background,
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

    def runner_namespace(self, directory, steps=None):
        path = generate_hidden_runner_script(
            steps=steps or [], platform="android", device_id="emulator-5554",
            adb_path="adb", output_path=os.path.join(directory, ".runner.py"),
        )
        namespace = {"__name__": "test_runner", "__file__": path}
        with open(path, encoding="utf-8") as source:
            exec(compile(source.read(), path, "exec"), namespace)
        return namespace

    def test_passo_android_recusa_falha_do_adb(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner_namespace(directory)
            for action in ("click", "input"):
                with self.subTest(action=action), \
                     patch("subprocess.run", return_value=subprocess.CompletedProcess([], 1)) as adb:
                    ok = runner["execute_android_step"](
                        {"coords": [120, 210], "action_type": action, "input_text": "Teste"}
                    )
                    self.assertFalse(ok, "comando ADB recusado nao pode concluir o passo")
                    self.assertEqual(adb.call_count, 1, "tap falhou: nao pode preencher texto")

    def test_preenchimento_android_recusa_falha_do_comando_de_texto(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner_namespace(directory)
            with patch("subprocess.run", side_effect=[
                subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 1),
            ]), patch("time.sleep"):
                self.assertFalse(runner["execute_android_step"](
                    {"coords": [120, 210], "action_type": "input", "input_text": "Teste"}
                ))

    def test_cancelamento_para_antes_do_proximo_passo_em_processo_real(self):
        self.generator.generate_entry(
            self.sample_elem_android, strategy=LocatorStrategy.POSITION, click_coord=(120, 210),
        )
        steps = self.generator.get_steps() * 2
        first_step, finished = threading.Event(), threading.Event()
        logs, results = [], []

        def output(line):
            logs.append(line)
            if line == "STEP":
                first_step.set()

        def done(success, message):
            results.append((success, message))
            finished.set()

        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner_namespace(directory, steps)
            path = runner["__file__"]
            with open(path, encoding="utf-8") as source:
                content = source.read()
            content = content.replace('if __name__ == "__main__":',
                'def verify_preconditions():\n    return True\n\n'
                'def execute_android_step(step):\n    print("STEP", flush=True)\n    return True\n\n'
                'if __name__ == "__main__":')
            with open(path, "w", encoding="utf-8") as source:
                source.write(content)
            execution = run_flow_in_background(path, output, done)
            try:
                self.assertTrue(first_step.wait(3), "primeiro passo nao iniciou")
                execution.cancel()
                self.assertTrue(finished.wait(3), "cancelamento nao encerrou o processo")
            finally:
                execution.join(4)
        self.assertEqual(logs.count("STEP"), 1, "o fluxo executou outro toque apos cancelar")
        self.assertEqual(len(results), 1)
        self.assertFalse(results[0][0])
        self.assertIn("cancelada", results[0][1].lower())

    def test_cancelamento_antes_do_start_notifica_sem_criar_processo(self):
        finished = MagicMock()
        execution = FlowExecution("/tmp/unused-flow.py", MagicMock(), finished)
        execution.cancel()
        with patch("subprocess.Popen") as spawn:
            execution.start()
            execution.join(1)
        spawn.assert_not_called()
        finished.assert_called_once_with(False, "Automação cancelada.")

    def test_cancelamento_tolera_processo_encerrado_entre_poll_e_sinal(self):
        execution = FlowExecution("/tmp/unused-flow.py", MagicMock(), MagicMock())
        execution._process = MagicMock()
        execution._process.poll.return_value = None
        execution._process.terminate.side_effect = ProcessLookupError()
        execution.cancel()
        execution._process.terminate.assert_called_once()

    def test_finalizacao_remove_apenas_script_temporario_gerenciado(self):
        managed = generate_hidden_runner_script(
            steps=[], platform="android", device_id="emulator-5554",
        )
        finished = MagicMock()
        execution = run_flow_in_background(managed, MagicMock(), finished)
        execution.join(3)
        self.assertFalse(execution.is_alive())
        self.assertFalse(os.path.exists(managed))
        finished.assert_called_once()

        with tempfile.TemporaryDirectory() as directory:
            exported = generate_hidden_runner_script(
                steps=[], platform="android", device_id="emulator-5554",
                output_path=os.path.join(directory, "exported.py"),
            )
            execution = run_flow_in_background(exported, MagicMock(), MagicMock())
            execution.join(3)
            self.assertFalse(execution.is_alive())
            self.assertTrue(os.path.exists(exported), "arquivo exportado pertence ao usuario")


if __name__ == "__main__":
    unittest.main()
