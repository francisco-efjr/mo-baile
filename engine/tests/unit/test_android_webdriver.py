"""Hierarquia do Android pelo WebDriver quando o `uiautomator dump` falha.

Motivo de existir: num Motorola com Android 14, `uiautomator dump` e morto com
SIGKILL (exit 137) e volta vazio. Sem hierarquia, `codegen.record` nao tem
elemento para resolver, e a gravacao de passo do Android nao gerava codigo
nenhum — enquanto a do iOS funcionava, porque o iOS ja passava pelo WDA.

A sessao UiAutomator2 do Appium e o equivalente Android do WebDriverAgent.
"""

from __future__ import annotations

import io
import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters.appium import AppiumBridge
from mobaile.domain.models import Platform
from mobaile.rpc.server import EngineServer

XML = (
    '<hierarchy rotation="0">'
    '<node class="android.widget.Button" text="Continuar" clickable="true"'
    ' bounds="[10,20][110,70]" resource-id="br.app:id/btn_ok"'
    ' content-desc="Botao continuar" package="br.app"/>'
    "</hierarchy>"
)


class TestReservaPeloWebDriver(unittest.TestCase):
    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.server.platform = Platform.ANDROID
        self.server.device_id = "ZY22L3CH3X"

    def tearDown(self):
        self.server.shutdown()

    def test_caminho_rapido_e_o_uiautomator(self):
        """Quando o dump funciona, nao se abre sessao do Appium a toa: ela custa
        dezenas de segundos na primeira vez."""
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=XML), \
             patch.object(self.server.appium, "ensure_android_session") as sessao:
            self.assertEqual(self.server._android_hierarchy("ZY22L3CH3X"), XML)
        sessao.assert_not_called()

    def test_dump_vazio_cai_para_o_appium(self):
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=None), \
             patch.object(self.server.appium, "ensure_android_session", return_value=(True, "ok")), \
             patch.object(self.server.appium, "get_page_source", return_value=XML):
            self.assertEqual(self.server._android_hierarchy("ZY22L3CH3X"), XML)

    def test_as_duas_falhando_devolvem_none(self):
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=None), \
             patch.object(self.server.appium, "ensure_android_session", return_value=(False, "sem sessao")):
            self.assertIsNone(self.server._android_hierarchy("ZY22L3CH3X"))

    def test_uiautomation_travado_vira_erro_com_o_que_fazer(self):
        """Mensagem generica deixava o usuario sem hierarquia, sem codigo e sem
        pista. O sintoma tem conserto conhecido, e ele entra no texto."""
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=None), \
             patch.object(
                 self.server.appium, "ensure_android_session",
                 return_value=(False, "java.lang.IllegalStateException: UiAutomation not connected"),
             ):
            self.server._android_hierarchy("ZY22L3CH3X")
        motivo = self.server._motivo_de_hierarquia_indisponivel()
        self.assertIn("UiAutomation", motivo)
        self.assertIn("reiniciando o aparelho", motivo)

    def test_erro_do_ios_aponta_para_o_wda(self):
        self.server.platform = Platform.IOS
        self.assertIn("WebDriverAgent", self.server._motivo_de_hierarquia_indisponivel())


class TestSessaoAndroidDoAppium(unittest.TestCase):
    def setUp(self):
        self.ponte = AppiumBridge(base_url="http://127.0.0.1:4723")

    def test_capabilities_pedem_uiautomator2(self):
        caps = self.ponte._android_capabilities("ZY22L3CH3X")
        self.assertEqual(caps["platformName"], "Android")
        self.assertEqual(caps["appium:automationName"], "UiAutomator2")
        self.assertEqual(caps["appium:udid"], "ZY22L3CH3X")
        # Mesmo motivo do iOS: com o padrao de 60 s o Appium encerraria a sessao
        # por inatividade e derrubaria o servidor de UI junto.
        self.assertEqual(caps["appium:newCommandTimeout"], 0)

    def test_sessao_ja_aberta_para_o_mesmo_alvo_e_reaproveitada(self):
        self.ponte.session_id = "abc"
        self.ponte.session_platform = "android"
        self.ponte.session_udid = "ZY22L3CH3X"
        with patch.object(self.ponte, "start_server") as subir:
            ok, _ = self.ponte.ensure_android_session("ZY22L3CH3X")
        self.assertTrue(ok)
        subir.assert_not_called()

    def test_sessao_de_ios_nao_e_reaproveitada_para_android(self):
        """Sem isto, pedir hierarquia de Android devolveria a arvore do
        simulador iOS que estivesse aberto."""
        self.ponte.session_id = "abc"
        self.ponte.session_platform = "ios"
        self.ponte.session_udid = "SIMULADOR"
        with patch.object(self.ponte, "start_server", return_value=(False, "parado")):
            ok, _ = self.ponte.ensure_android_session("ZY22L3CH3X")
        self.assertFalse(ok)

    def test_page_source_sem_sessao_e_none(self):
        self.assertIsNone(self.ponte.get_page_source())

    def test_page_source_devolve_o_xml(self):
        resposta = MagicMock(status_code=200)
        resposta.json.return_value = {"value": XML}
        self.ponte.session_id = "abc"
        with patch("requests.get", return_value=resposta):
            self.assertEqual(self.ponte.get_page_source(), XML)

    def test_page_source_vazio_conta_como_ausente(self):
        resposta = MagicMock(status_code=200)
        resposta.json.return_value = {"value": "   "}
        self.ponte.session_id = "abc"
        with patch("requests.get", return_value=resposta):
            self.assertIsNone(self.ponte.get_page_source())
