"""Hierarquia do Android pelo WebDriver quando o `uiautomator dump` falha.

Motivo de existir: num Motorola com Android 14, `uiautomator dump` e morto com
SIGKILL (exit 137) e volta vazio. Sem hierarquia, `codegen.record` nao tem
elemento para resolver, e a gravacao de passo do Android nao gerava codigo
nenhum — enquanto a do iOS funcionava, porque o iOS ja passava pelo WDA.

A sessao UiAutomator2 do Appium e o equivalente Android do WebDriverAgent.
"""

from __future__ import annotations

import io
import threading
import time
import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters.adb import ADBBridge
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

    def test_backend_appium_e_memorizado_apos_falha_de_uiautomator(self):
        """Após a primeira falha de uiautomator dump, o motor deve memorizar
        que este aparelho precisa de Appium e ir direto a ele nas próximas
        vezes, sem tentar adb.get_ui_hierarchy novamente."""
        def dump_morto(serial):
            self.server.adb.dump_killed[serial] = True
            return None

        with patch.object(self.server.adb, "get_ui_hierarchy", side_effect=dump_morto) as mock_adb, \
             patch.object(self.server.appium, "ensure_android_session", return_value=(True, "ok")), \
             patch.object(self.server.appium, "get_page_source", return_value=XML) as mock_page_source:
            # Primeira chamada: descobre que precisa de Appium
            self.assertEqual(self.server._android_hierarchy("ZY22L3CH3X"), XML)
            self.assertEqual(mock_adb.call_count, 1)

            # Simula sessão ativa
            self.server.appium.session_id = "sessao_123"
            self.server.appium.session_platform = "android"
            self.server.appium.session_udid = "ZY22L3CH3X"

            # Segunda chamada: deve ir direto para get_page_source sem chamar adb.get_ui_hierarchy
            self.assertEqual(self.server._android_hierarchy("ZY22L3CH3X"), XML)
            self.assertEqual(mock_adb.call_count, 1, "adb.get_ui_hierarchy não deveria ter sido chamado de novo")
            self.assertEqual(mock_page_source.call_count, 2)

    def test_dump_vazio_sem_sigkill_nao_troca_o_backend_do_aparelho(self):
        """Tela sem ocio ou corrida com outra leitura tambem devolvem vazio. Isso
        abre o Appium para esta leitura, mas a proxima volta a tentar o dump: so
        o 137 prova que o aparelho nao tem `uiautomator dump`."""
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=None) as mock_adb, \
             patch.object(self.server.appium, "ensure_android_session", return_value=(True, "ok")), \
             patch.object(self.server.appium, "get_page_source", return_value=XML):
            self.assertEqual(self.server._android_hierarchy("ZY22L3CH3X"), XML)
            self.assertNotEqual(self.server._android_backend.get("ZY22L3CH3X"), "appium")
            self.server._android_hierarchy("ZY22L3CH3X")
        self.assertEqual(mock_adb.call_count, 2)

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


class TestLeitorDoFlow(unittest.TestCase):
    """AUT-1: a thread do flow le a arvore sem abrir sessao nem trocar o backend."""

    SERIAL = "emulator-5554"

    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.server.platform = Platform.ANDROID
        self.server.device_id = self.SERIAL

    def tearDown(self):
        self.server.shutdown()

    def abrir_sessao(self):
        self.server.appium.session_id = "s1"
        self.server.appium.session_platform = "android"
        self.server.appium.session_udid = self.SERIAL

    def test_sessao_ja_aberta_le_pelo_appium_sem_dump(self):
        self.abrir_sessao()
        ler, backend = self.server._leitor_do_flow(self.SERIAL)
        with patch.object(self.server.appium, "get_page_source", return_value=XML), \
             patch.object(self.server.adb, "get_ui_hierarchy") as dump:
            self.assertEqual(ler(), XML)
        dump.assert_not_called()
        self.assertEqual(backend(), "appium")

    def test_sem_sessao_le_pelo_dump_e_a_arvore_vira_a_atual(self):
        ler, backend = self.server._leitor_do_flow(self.SERIAL)
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=XML):
            self.assertEqual(ler(), XML)
        self.assertEqual(backend(), "adb")
        self.assertEqual(self.server.current_xml, XML, "o inspetor do espelho acha a leitura pronta")

    def test_nunca_abre_sessao_nem_troca_o_backend_dentro_do_flow(self):
        ler, backend = self.server._leitor_do_flow(self.SERIAL)
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=None), \
             patch.object(self.server.appium, "ensure_android_session") as sessao:
            self.assertIsNone(ler())
        sessao.assert_not_called()
        self.assertIsNone(backend())
        self.assertNotIn(self.SERIAL, self.server._android_backend)

    def test_arvore_lida_depois_de_trocar_o_alvo_nao_vira_a_atual(self):
        ler, _ = self.server._leitor_do_flow(self.SERIAL)
        with self.server._state_lock:
            self.server._session_epoch += 1
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=XML):
            self.assertEqual(ler(), XML, "a leitura segue valendo para o flow")
        self.assertIsNone(self.server.current_xml, "mas nao vira a arvore do alvo novo")

    def test_inspetor_aproveita_a_leitura_do_flow_em_vez_de_disputar_o_dump(self):
        ler, _ = self.server._leitor_do_flow(self.SERIAL)
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=XML) as dump:
            ler()
            self.server.hierarchy_dump({})
        self.assertEqual(dump.call_count, 1)

    def test_backend_appium_sem_sessao_nao_le_nem_abre_nada(self):
        # A sessao caiu no meio do flow: o leitor devolve nada e o runner diz
        # que o aparelho nao devolveu a arvore, sem abrir sessao sem progresso.
        self.server._android_backend[self.SERIAL] = "appium"
        ler, backend = self.server._leitor_do_flow(self.SERIAL)
        with patch.object(self.server.adb, "get_ui_hierarchy") as dump, \
             patch.object(self.server.appium, "ensure_android_session") as sessao:
            self.assertIsNone(ler())
        dump.assert_not_called()
        sessao.assert_not_called()
        self.assertIsNone(backend())

    def test_aparelho_que_depende_do_appium_sem_sessao_e_recusado_sem_abrir_nada(self):
        # Abrir a sessao aqui levaria ate minutos dentro de um pedido de 30 s.
        self.server._android_backend[self.SERIAL] = "appium"
        with patch.object(self.server.appium, "ensure_android_session") as sessao, \
             self.assertRaisesRegex(Exception, "Atualize a hierarquia no inspetor"):
            self.server._conferir_leitura_do_flow(self.SERIAL)
        sessao.assert_not_called()
        self.abrir_sessao()
        self.server._conferir_leitura_do_flow(self.SERIAL)

    def test_aparelho_com_dump_nao_precisa_de_sessao(self):
        with patch.object(self.server.appium, "ensure_android_session") as sessao:
            self.server._conferir_leitura_do_flow(self.SERIAL)
        sessao.assert_not_called()

    def test_dump_morto_num_aparelho_novo_diz_o_que_fazer(self):
        def dump_morto(serial):
            self.server.adb.dump_killed[serial] = True
            return None

        ler, _ = self.server._leitor_do_flow(self.SERIAL)
        with patch.object(self.server.adb, "get_ui_hierarchy", side_effect=dump_morto), \
             self.assertRaisesRegex(Exception, "so devolve a tela pelo Appium"):
            ler()


class TestUiAutomationOcupado(unittest.TestCase):
    """O driver do Maestro esquecido no aparelho segura o UiAutomation: o dump
    morre com 137 e o Appium esbarraria no mesmo lugar depois de dezenas de
    segundos. Visto num moto g55 com Android 14."""

    SERIAL = "ZY22L3CH3X"

    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.server.platform = Platform.ANDROID
        self.server.device_id = self.SERIAL

    def tearDown(self):
        self.server.shutdown()

    def dump_bloqueado(self, serial):
        self.server.adb.dump_blocked_by[serial] = "dev.mobile.maestro.test"
        return None

    def test_inspetor_diz_quem_ocupa_e_nao_abre_o_appium(self):
        with patch.object(self.server.adb, "get_ui_hierarchy", side_effect=self.dump_bloqueado), \
             patch.object(self.server.appium, "ensure_android_session") as sessao:
            self.assertIsNone(self.server._android_hierarchy(self.SERIAL))
        sessao.assert_not_called()
        self.assertNotIn(self.SERIAL, self.server._android_backend)
        motivo = self.server._motivo_de_hierarquia_indisponivel()
        self.assertIn("driver do Maestro", motivo)
        self.assertIn(f"adb -s {self.SERIAL} shell am force-stop dev.mobile.maestro", motivo)

    def test_flow_recusa_com_o_comando_que_libera(self):
        ler, _ = self.server._leitor_do_flow(self.SERIAL)
        with patch.object(self.server.adb, "get_ui_hierarchy", side_effect=self.dump_bloqueado), \
             self.assertRaisesRegex(Exception, "am force-stop dev.mobile.maestro"):
            ler()


class TestDumpDoAdb(unittest.TestCase):
    INSTRUMENTACAO = (
        b"    mInstr=ActiveInstrumentation{8de623b {dev.mobile.maestro.test/"
        b"androidx.test.runner.AndroidJUnitRunner} 1 procs}\n"
    )

    def test_sigkill_com_maestro_no_aparelho_e_bloqueio(self):
        ponte = ADBBridge(adb_path="adb")

        def run_cmd(args, **_k):
            if "dumpsys activity processes" in " ".join(args):
                return 0, self.INSTRUMENTACAO, b""
            return 137, b"", b""

        ponte._run_cmd = run_cmd
        self.assertIsNone(ponte.get_ui_hierarchy("ZY22L3CH3X"))
        self.assertEqual(ponte.dump_blocked_by["ZY22L3CH3X"], "dev.mobile.maestro.test")
        self.assertFalse(ponte.dump_killed["ZY22L3CH3X"])

    def test_instrumentacao_do_appium_nao_e_bloqueio(self):
        """Pela sessao UiAutomator2 o motor le a tela: segue como dump morto."""
        ponte = ADBBridge(adb_path="adb")
        appium = self.INSTRUMENTACAO.replace(b"dev.mobile.maestro.test", b"io.appium.uiautomator2.server.test")

        def run_cmd(args, **_k):
            if "dumpsys activity processes" in " ".join(args):
                return 0, appium, b""
            return 137, b"", b""

        ponte._run_cmd = run_cmd
        self.assertIsNone(ponte.get_ui_hierarchy("ZY22L3CH3X"))
        self.assertNotIn("ZY22L3CH3X", ponte.dump_blocked_by)
        self.assertTrue(ponte.dump_killed["ZY22L3CH3X"])


    def test_sigkill_e_registrado_e_outra_falha_nao(self):
        ponte = ADBBridge(adb_path="adb")
        ponte._run_cmd = lambda *a, **k: (137, b"", b"")
        self.assertIsNone(ponte.get_ui_hierarchy("ZY22L3CH3X"))
        self.assertTrue(ponte.dump_killed["ZY22L3CH3X"])
        ponte._run_cmd = lambda *a, **k: (1, b"", b"")
        self.assertIsNone(ponte.get_ui_hierarchy("ZY22L3CH3X"))
        self.assertFalse(ponte.dump_killed["ZY22L3CH3X"])

    def test_dois_dumps_do_mesmo_aparelho_nao_se_cruzam(self):
        """O arquivo remoto e um so por processo: o `rm -f` de um dump apagava o
        do outro. Com a trava, o segundo so comeca depois do primeiro."""
        ponte = ADBBridge(adb_path="adb")
        dentro, maximo = [0], [0]
        trava = threading.Lock()

        def run_cmd(args, **_k):
            if "uiautomator" in " ".join(args):
                with trava:
                    dentro[0] += 1
                    maximo[0] = max(maximo[0], dentro[0])
                time.sleep(0.05)
                with trava:
                    dentro[0] -= 1
                return 0, XML.encode(), b""
            return 0, b"", b""

        ponte._run_cmd = run_cmd
        threads = [threading.Thread(target=ponte.get_ui_hierarchy, args=("emulator-5554",)) for _ in range(3)]
        for th in threads:
            th.start()
        for th in threads:
            th.join()
        self.assertEqual(maximo[0], 1)


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
