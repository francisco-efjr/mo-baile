"""Subida do WebDriverAgent via Appium.

O time usa Appium para gerenciar o WDA, então o botão "Iniciar WDA" pede ao
Appium em vez de compilar o WDA por conta própria.
"""

import subprocess
import unittest
from unittest.mock import MagicMock, patch

import requests

from mobaile.adapters.appium import AppiumBridge
from mobaile.domain.errors import InvalidInputError, ToolNotFoundError


def resposta(status=200, payload=None, texto=""):
    r = MagicMock(spec=requests.Response)
    r.status_code = status
    r.json.return_value = payload if payload is not None else {}
    r.text = texto
    return r


class TestDescoberta(unittest.TestCase):
    def test_encontra_appium_no_path(self):
        with patch("shutil.which", return_value="/opt/homebrew/bin/appium"), \
             patch("pathlib.Path.is_file", return_value=True), \
             patch("os.access", return_value=True):
            self.assertEqual(AppiumBridge.locate_appium(), "/opt/homebrew/bin/appium")

    def test_sem_appium_devolve_none(self):
        with patch("shutil.which", return_value=None), patch("pathlib.Path.is_file", return_value=False):
            self.assertIsNone(AppiumBridge.locate_appium())

    def test_servidor_no_ar(self):
        with patch("requests.get", return_value=resposta(200)):
            self.assertTrue(AppiumBridge().is_running())

    def test_servidor_fora_do_ar_nao_levanta(self):
        with patch("requests.get", side_effect=requests.ConnectionError()):
            self.assertFalse(AppiumBridge().is_running())


class TestCapabilities(unittest.TestCase):
    def setUp(self):
        self.bridge = AppiumBridge(wda_url="http://localhost:8100")

    def test_sessao_nao_pede_app_nem_bundle(self):
        # Sem app/bundleId o XCUITest sobe o WDA e deixa o simulador na tela
        # inicial, que é o que queremos: não estamos testando um app.
        caps = self.bridge._capabilities("AAAA-1111", None)
        self.assertNotIn("appium:app", caps)
        self.assertNotIn("appium:bundleId", caps)

    def test_timeout_de_comando_desligado(self):
        # Com o padrão de 60 s, o Appium encerraria a sessão por inatividade e
        # derrubaria o WDA junto: o indicador ficaria verde e voltaria a vermelho.
        self.assertEqual(self.bridge._capabilities("A", None)["appium:newCommandTimeout"], 0)

    def test_porta_do_wda_vem_da_configuracao(self):
        bridge = AppiumBridge(wda_url="http://localhost:9100")
        self.assertEqual(bridge._capabilities("A", None)["appium:wdaLocalPort"], 9100)

    def test_versao_da_plataforma_e_opcional(self):
        self.assertNotIn("appium:platformVersion", self.bridge._capabilities("A", None))
        self.assertEqual(self.bridge._capabilities("A", "18.0")["appium:platformVersion"], "18.0")


class TestSubidaDoServidor(unittest.TestCase):
    def test_servidor_ja_no_ar_nao_inicia_outro(self):
        bridge = AppiumBridge()
        with patch.object(bridge, "is_running", return_value=True), \
             patch("subprocess.Popen") as popen:
            ok, msg = bridge.start_server()
        self.assertTrue(ok)
        popen.assert_not_called()
        self.assertIn("ja estava", msg)

    def test_sem_appium_instalado_levanta_erro_tipado(self):
        bridge = AppiumBridge()
        with patch.object(bridge, "is_running", return_value=False), \
             patch.object(AppiumBridge, "locate_appium", return_value=None), \
             self.assertRaises(ToolNotFoundError) as ctx:
            bridge.start_server()
        self.assertIn("npm i -g appium", str(ctx.exception))

    def test_processo_que_morre_na_largada_e_reportado(self):
        bridge = AppiumBridge()
        processo = MagicMock()
        processo.poll.return_value = 1  # encerrou
        with patch.object(bridge, "is_running", return_value=False), \
             patch.object(AppiumBridge, "locate_appium", return_value="/bin/appium"), \
             patch("subprocess.Popen", return_value=processo), \
             patch("pathlib.Path.open", side_effect=OSError):
            ok, msg = bridge.start_server()
        self.assertFalse(ok)
        self.assertIn("encerrou", msg)


class TestGarantirWDA(unittest.TestCase):
    def test_wda_ja_no_ar_nao_abre_sessao(self):
        bridge = AppiumBridge()
        with patch.object(bridge, "is_wda_running", return_value=True), \
             patch("requests.post") as post:
            ok, msg = bridge.ensure_wda("AAAA-1111")
        self.assertTrue(ok)
        post.assert_not_called()
        self.assertIn("ja estava", msg)

    def test_fluxo_completo_abre_sessao_e_espera_a_porta(self):
        bridge = AppiumBridge()
        # WDA fora do ar na primeira checagem, no ar depois da sessão.
        with patch.object(bridge, "is_wda_running", side_effect=[False, True]), \
             patch.object(bridge, "start_server", return_value=(True, "ok")), \
             patch("requests.post", return_value=resposta(200, {"sessionId": "S1"})) as post:
            ok, _msg = bridge.ensure_wda("AAAA-1111", "18.0")
        self.assertTrue(ok)
        self.assertEqual(bridge.session_id, "S1")
        caps = post.call_args.kwargs["json"]["capabilities"]["alwaysMatch"]
        self.assertEqual(caps["appium:udid"], "AAAA-1111")
        self.assertEqual(caps["appium:platformVersion"], "18.0")

    def test_recusa_do_appium_vira_mensagem_util(self):
        bridge = AppiumBridge()
        erro = resposta(500, {"value": {"message": "xcodebuild failed with code 65"}})
        with patch.object(bridge, "is_wda_running", return_value=False), \
             patch.object(bridge, "start_server", return_value=(True, "ok")), \
             patch("requests.post", return_value=erro):
            ok, msg = bridge.ensure_wda("AAAA-1111")
        self.assertFalse(ok)
        self.assertIn("xcodebuild failed", msg)

    def test_primeira_compilacao_demorada_explica_o_motivo(self):
        bridge = AppiumBridge()
        with patch.object(bridge, "is_wda_running", return_value=False), \
             patch.object(bridge, "start_server", return_value=(True, "ok")), \
             patch("requests.post", side_effect=requests.Timeout()):
            ok, msg = bridge.ensure_wda("AAAA-1111")
        self.assertFalse(ok)
        self.assertIn("compila o WDA", msg)

    def test_servidor_que_nao_sobe_interrompe_cedo(self):
        bridge = AppiumBridge()
        with patch.object(bridge, "is_wda_running", return_value=False), \
             patch.object(bridge, "start_server", return_value=(False, "porta ocupada")), \
             patch("requests.post") as post:
            ok, msg = bridge.ensure_wda("AAAA-1111")
        self.assertFalse(ok)
        self.assertEqual(msg, "porta ocupada")
        post.assert_not_called()

    def test_udid_malicioso_e_recusado(self):
        with self.assertRaises(InvalidInputError):
            AppiumBridge().ensure_wda("A; rm -rf /")


class TestEncerramento(unittest.TestCase):
    def test_so_derruba_o_servidor_que_nos_subimos(self):
        bridge = AppiumBridge()
        bridge._process = None
        with patch("subprocess.Popen") as popen:
            bridge.stop_server()
        popen.assert_not_called()

    def test_encerra_o_processo_proprio(self):
        bridge = AppiumBridge()
        processo = MagicMock()
        bridge._process = processo
        bridge.stop_server()
        processo.terminate.assert_called_once()
        self.assertIsNone(bridge._process)

    def test_processo_teimoso_leva_kill(self):
        bridge = AppiumBridge()
        processo = MagicMock()
        processo.wait.side_effect = subprocess.TimeoutExpired("appium", 5)
        bridge._process = processo
        bridge.stop_server()
        processo.kill.assert_called_once()


if __name__ == "__main__":
    unittest.main()
