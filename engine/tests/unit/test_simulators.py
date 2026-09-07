"""Ciclo de vida do simulador iOS e diagnostico de ambiente.

Antes desta adicao o projeto nao tinha nenhum codigo capaz de ligar um
simulador: so sabia listar os que ja estavam de pe. Clicar em "abrir simulador"
na interface nao tinha para onde ir.
"""

import json
import subprocess
import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters.ios_wda import IOSBridge
from mobaile.domain.errors import InvalidInputError, ToolNotFoundError
from mobaile.domain.models import DaemonState
from mobaile.services.diagnostics import DiagnosticsService

SIMCTL_JSON = json.dumps({
    "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
            {"udid": "AAAA-1111", "name": "iPhone 16", "state": "Shutdown", "isAvailable": True},
            {"udid": "BBBB-2222", "name": "iPhone 16 Pro", "state": "Booted", "isAvailable": True},
            {"udid": "CCCC-3333", "name": "iPad Air", "state": "Shutdown", "isAvailable": False},
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-5": [
            {"udid": "DDDD-4444", "name": "iPhone SE", "state": "Shutdown", "isAvailable": True},
        ],
    }
})


def resultado(returncode=0, stdout=b"", stderr=b""):
    return subprocess.CompletedProcess(args=[], returncode=returncode, stdout=stdout, stderr=stderr)


class TestListagemDeSimuladores(unittest.TestCase):
    def test_lista_todos_e_nao_so_os_ligados(self):
        with patch("subprocess.run", return_value=resultado(stdout=SIMCTL_JSON.encode())):
            simuladores = IOSBridge(wda_url="http://x").list_all_simulators()

        # 4 declarados, 1 indisponivel (runtime nao baixado) fica de fora.
        self.assertEqual(len(simuladores), 3)
        self.assertEqual({s["name"] for s in simuladores},
                         {"iPhone 16", "iPhone 16 Pro", "iPhone SE"})

    def test_ligados_vem_primeiro(self):
        with patch("subprocess.run", return_value=resultado(stdout=SIMCTL_JSON.encode())):
            simuladores = IOSBridge(wda_url="http://x").list_all_simulators()
        self.assertTrue(simuladores[0]["booted"])
        self.assertEqual(simuladores[0]["name"], "iPhone 16 Pro")

    def test_runtime_vira_rotulo_legivel(self):
        with patch("subprocess.run", return_value=resultado(stdout=SIMCTL_JSON.encode())):
            simuladores = IOSBridge(wda_url="http://x").list_all_simulators()
        self.assertIn("iOS 18.0", {s["runtime"] for s in simuladores})

    def test_sem_xcrun_levanta_erro_tipado(self):
        with patch("subprocess.run", side_effect=FileNotFoundError()), \
             self.assertRaises(ToolNotFoundError):
            IOSBridge(wda_url="http://x").list_all_simulators()

    def test_json_corrompido_nao_derruba(self):
        with patch("subprocess.run", return_value=resultado(stdout=b"nao e json")):
            self.assertEqual(IOSBridge(wda_url="http://x").list_all_simulators(), [])


class TestBootDeSimulador(unittest.TestCase):
    def test_liga_e_abre_a_janela_do_simulator(self):
        with patch("subprocess.run", return_value=resultado()) as run:
            ok, _msg = IOSBridge(wda_url="http://x").boot_simulator("AAAA-1111")
        self.assertTrue(ok)
        comandos = [c.args[0] for c in run.call_args_list]
        self.assertIn(["xcrun", "simctl", "boot", "AAAA-1111"], comandos)
        # `simctl boot` sobe o runtime mas nao mostra janela nenhuma.
        self.assertIn(["open", "-a", "Simulator"], comandos)

    def test_simulador_ja_ligado_conta_como_sucesso(self):
        erro = b"Unable to boot device in current state: Booted"
        with patch("subprocess.run", return_value=resultado(returncode=149, stderr=erro)):
            ok, msg = IOSBridge(wda_url="http://x").boot_simulator("BBBB-2222")
        self.assertTrue(ok, "quem pediu 'abre' e ja esta aberto foi atendido")
        self.assertIn("ja estava ligado", msg)

    def test_falha_real_devolve_a_mensagem_do_simctl(self):
        with patch("subprocess.run", return_value=resultado(returncode=1, stderr=b"Invalid device")):
            ok, msg = IOSBridge(wda_url="http://x").boot_simulator("AAAA-1111")
        self.assertFalse(ok)
        self.assertIn("Invalid device", msg)

    def test_udid_malicioso_e_recusado(self):
        with self.assertRaises(InvalidInputError):
            IOSBridge(wda_url="http://x").boot_simulator("AAAA; rm -rf /")

    def test_open_app_pode_ser_desligado(self):
        with patch("subprocess.run", return_value=resultado()) as run:
            IOSBridge(wda_url="http://x").boot_simulator("AAAA-1111", open_app=False)
        comandos = [c.args[0] for c in run.call_args_list]
        self.assertNotIn(["open", "-a", "Simulator"], comandos)

    def test_timeout_nao_vira_excecao(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("simctl", 90)):
            ok, msg = IOSBridge(wda_url="http://x").boot_simulator("AAAA-1111")
        self.assertFalse(ok)
        self.assertIn("demorou", msg)


class TestConstrutorSemIO(unittest.TestCase):
    def test_construtor_nao_faz_requisicao(self):
        # A versao anterior abria sessao WDA aqui, travando ate 6 s quando o
        # host engolia pacotes.
        with patch("requests.get") as get, patch("requests.post") as post:
            IOSBridge(wda_url="http://127.0.0.1:8100")
        get.assert_not_called()
        post.assert_not_called()


class TestDiagnostico(unittest.TestCase):
    def _servico(self, *, xcrun=True, simuladores=None, wda=False,
                 adb=True, devices=None, avds=None):
        ios = MagicMock()
        ios.is_xcrun_available.return_value = xcrun
        ios.list_all_simulators.return_value = simuladores or []
        ios.is_wda_running.return_value = wda
        adb_mock = MagicMock()
        adb_mock.is_available.return_value = adb
        adb_mock.adb_path = "/usr/local/bin/adb"
        adb_mock.list_devices.return_value = devices or []
        adb_mock.list_avds.return_value = avds or []
        return DiagnosticsService(adb=adb_mock, ios=ios)

    def _estado(self, diag, rotulo):
        return next(c.state for c in diag.checks if c.label == rotulo)

    def test_sem_xcrun_tudo_desce_em_cascata(self):
        diag = self._servico(xcrun=False).ios_diagnostics()
        self.assertEqual(self._estado(diag, "Ferramentas do Xcode"), DaemonState.ERROR)
        self.assertFalse(diag.ready)

    def test_simulador_parado_sugere_acao_de_ligar(self):
        diag = self._servico(
            simuladores=[{"name": "iPhone 16", "booted": False, "udid": "A"}]
        ).ios_diagnostics()
        check = next(c for c in diag.checks if c.label == "Simulador ligado")
        self.assertEqual(check.state, DaemonState.WARN)
        self.assertEqual(check.action, "boot_simulator")

    def test_ambiente_ios_completo_fica_pronto(self):
        diag = self._servico(
            simuladores=[{"name": "iPhone 16", "booted": True, "udid": "A"}], wda=True
        ).ios_diagnostics()
        self.assertTrue(diag.ready)

    def test_nao_mente_dizendo_que_ha_dispositivo(self):
        # O cartao antigo trazia "Dispositivo conectado" com visto verde fixo.
        diag = self._servico(adb=True, devices=[]).android_diagnostics()
        self.assertNotEqual(self._estado(diag, "Dispositivo autorizado"), DaemonState.OK)

    def test_aparelho_nao_autorizado_explica_o_que_fazer(self):
        diag = self._servico(devices=[("R58N", "unauthorized")]).android_diagnostics()
        check = next(c for c in diag.checks if c.label == "Dispositivo autorizado")
        self.assertEqual(check.state, DaemonState.WARN)
        self.assertIn("depuracao USB", check.detail)

    def test_avd_parado_sugere_acao(self):
        diag = self._servico(devices=[], avds=["Pixel_7"]).android_diagnostics()
        check = next(c for c in diag.checks if c.label == "Emulador disponivel")
        self.assertEqual(check.action, "boot_avd")

    def test_run_devolve_as_duas_plataformas(self):
        resultado = self._servico().run()
        self.assertEqual(set(resultado), {"ios", "android"})
        self.assertIn("checks", resultado["ios"])


if __name__ == "__main__":
    unittest.main()
