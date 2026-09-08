"""Contrato JSON-RPC entre o motor e o front SwiftUI.

Este arquivo e a especificacao executavel da fronteira. Se um teste daqui
quebrar, o front quebra junto: e o sinal de que a mudanca precisa de versao
nova do contrato, e nao de um ajuste silencioso.
"""

import io
import json
import unittest
from typing import ClassVar
from unittest.mock import patch

from PIL import Image

from mobaile.rpc import protocol
from mobaile.rpc.server import EngineServer


class ContractBase(unittest.TestCase):
    def setUp(self):
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.addCleanup(self.server.shutdown)

    def call(self, method, params=None, request_id=1):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params or {}})
        )

    def ok(self, method, params=None):
        response = self.call(method, params)
        self.assertNotIn("error", response, f"{method} devolveu erro: {response.get('error')}")
        return response["result"]

    def erro(self, method, params=None):
        response = self.call(method, params)
        self.assertIn("error", response, f"{method} deveria ter falhado")
        return response["error"]

    def notificacoes(self):
        return [json.loads(linha) for linha in self.out.getvalue().splitlines() if linha.strip()]


class TestEnvelope(ContractBase):
    def test_resposta_segue_o_envelope_jsonrpc(self):
        response = self.call("engine.info")
        self.assertEqual(response["jsonrpc"], "2.0")
        self.assertEqual(response["id"], 1)
        self.assertIn("result", response)

    def test_json_invalido_vira_parse_error(self):
        self.assertEqual(self.server.handle_message("{isso nao e json")["error"]["code"], protocol.PARSE_ERROR)

    def test_envelope_errado_e_recusado(self):
        response = self.server.handle_message(json.dumps({"id": 1, "method": "engine.info"}))
        self.assertEqual(response["error"]["code"], protocol.INVALID_REQUEST)

    def test_metodo_desconhecido(self):
        self.assertEqual(self.erro("nao.existe")["code"], protocol.METHOD_NOT_FOUND)

    def test_params_precisa_ser_objeto(self):
        response = self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": "engine.info", "params": [1, 2]})
        )
        self.assertEqual(response["error"]["code"], protocol.INVALID_PARAMS)

    def test_notificacao_nao_gera_resposta(self):
        self.assertIsNone(
            self.server.handle_message(json.dumps({"jsonrpc": "2.0", "method": "engine.info"}))
        )

    def test_erro_de_dominio_carrega_codigo_estavel(self):
        erro = self.erro("hierarchy.dump")
        self.assertEqual(erro["code"], protocol.ENGINE_ERROR)
        self.assertEqual(erro["data"]["code"], "invalid_input")


class TestSuperficie(ContractBase):
    METODOS_ESPERADOS: ClassVar[set[str]] = {
        "engine.info", "engine.shutdown", "session.select_device", "devices.list",
        "devices.watch_start", "devices.watch_stop",
        "diagnostics.check", "simulators.list", "simulators.boot", "simulators.shutdown",
        "emulators.list", "emulators.boot", "wda.start", "wda.status",
        "screen.capture", "screen.size", "hierarchy.dump", "hierarchy.element_at",
        "input.tap", "input.text", "stream.start", "stream.stop", "stream.stats",
        "scrcpy.start", "scrcpy.stop", "scrcpy.status",
        "proxy.start", "proxy.stop", "proxy.events", "proxy.clear",
        "analytics.start", "analytics.stop", "analytics.events", "analytics.clear",
        "codegen.record", "codegen.steps", "codegen.reset",
    }

    def test_superficie_publica_nao_encolhe_sem_aviso(self):
        expostos = set(self.ok("engine.info")["methods"])
        self.assertEqual(self.METODOS_ESPERADOS - expostos, set(), "metodo do contrato desapareceu")

    def test_engine_info_traz_o_diagnostico_da_maquina(self):
        info = self.ok("engine.info")
        for chave in ("version", "platform", "adb_path", "adb_available", "scrcpy_available", "wda_url", "proxy"):
            self.assertIn(chave, info)


class TestSessao(ContractBase):
    def test_seleciona_dispositivo(self):
        resultado = self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        self.assertEqual(resultado, {"platform": "android", "device_id": "emulator-5554"})

    def test_serial_malicioso_e_recusado_na_fronteira(self):
        erro = self.erro("session.select_device", {"platform": "android", "device_id": 'x"; rm -rf /'})
        self.assertEqual(erro["data"]["code"], "invalid_input")

    def test_plataforma_invalida_e_recusada(self):
        self.assertEqual(
            self.erro("session.select_device", {"platform": "symbian"})["data"]["code"], "invalid_input"
        )

    def test_operacao_sem_dispositivo_falha_com_mensagem_util(self):
        erro = self.erro("input.tap", {"x": 10, "y": 10})
        self.assertIn("dispositivo", erro["message"].lower())


class TestValidacaoDeParametros(ContractBase):
    def setUp(self):
        super().setUp()
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})

    def test_coordenada_negativa(self):
        self.assertEqual(self.erro("input.tap", {"x": -1, "y": 10})["data"]["code"], "invalid_input")

    def test_coordenada_ausente(self):
        self.assertEqual(self.erro("input.tap", {})["data"]["code"], "invalid_input")

    def test_texto_invalido_vira_erro_tipado_e_nao_ok_falso(self):
        # Encontrado em QA: o adapter recusava o texto internamente e devolvia
        # False, então a interface recebia {"ok": false} sem motivo nenhum.
        erro = self.erro("input.text", {"text": "linha1\nlinha2"})
        self.assertEqual(erro["data"]["code"], "invalid_input")
        self.assertIn("controle", erro["message"].lower())

    def test_texto_gigante_tambem_e_recusado_na_fronteira(self):
        erro = self.erro("input.text", {"text": "a" * 5000})
        self.assertEqual(erro["data"]["code"], "invalid_input")

    def test_element_at_exige_hierarquia_carregada(self):
        erro = self.erro("hierarchy.element_at", {"x": 5, "y": 5})
        self.assertIn("hierarchy.dump", erro["message"])


class TestFluxoDeInspecao(ContractBase):
    XML = (
        '<hierarchy rotation="0">'
        '<node class="android.widget.Button" text="Continuar" clickable="true"'
        ' bounds="[10,20][110,70]" resource-id="br.app:id/btn_ok" package="br.app"/>'
        "</hierarchy>"
    )

    def setUp(self):
        super().setUp()
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})

    def test_dump_parseia_e_element_at_localiza(self):
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=self.XML):
            dump = self.ok("hierarchy.dump")
        self.assertEqual(dump["count"], 1)
        elemento = dump["elements"][0]
        self.assertEqual(elemento["display_name"], "Continuar")
        self.assertEqual(elemento["chip_type"], "B")

        achado = self.ok("hierarchy.element_at", {"x": 60, "y": 45})["element"]
        self.assertEqual(achado["resource_id"], "br.app:id/btn_ok")

    def test_gravacao_gera_page_object_e_acao(self):
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=self.XML):
            self.ok("hierarchy.dump")
        gravado = self.ok("codegen.record", {"x": 60, "y": 45, "strategy": "id"})
        self.assertIn("BOTAO", gravado["var_name"])
        self.assertIn("AppiumBy", gravado["object_code"])
        self.assertEqual(gravado["step_count"], 1)

        self.assertEqual(len(self.ok("codegen.steps")["steps"]), 1)
        self.ok("codegen.reset")
        self.assertEqual(len(self.ok("codegen.steps")["steps"]), 0)

    def test_clique_fora_de_qualquer_elemento_grava_passo_por_posicao(self):
        """Regressao: clicar em area vazia recusava a gravacao.

        `codegen.record` levantava "Nenhum elemento encontrado nessa
        coordenada" quando o ponto nao caia em no nenhum da arvore. No front
        nativo isso virava clique que nao faz nada: area vazia, canvas de jogo
        e componente desenhado a mao nao aparecem na arvore de acessibilidade,
        e e justamente ai que o passo por coordenada e a unica saida.

        A interface Tk ja sintetizava esse elemento por conta propria, ou seja,
        a regra existia num lugar so e o outro front falhava em silencio.
        """
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=self.XML):
            self.ok("hierarchy.dump")

        # O XML da suite cobre [10,20]-[110,70]; este ponto esta fora dele.
        gravado = self.ok("codegen.record", {"x": 900, "y": 1600, "strategy": "position"})

        self.assertEqual(gravado["step_count"], 1)
        self.assertEqual(gravado["element"]["text"], "pos_900_1600")
        self.assertEqual(gravado["element"]["bounds"], [900, 1600, 900, 1600])
        self.assertTrue(gravado["element"]["clickable"])
        self.assertIn("900", gravado["action_code"] + gravado["object_code"])

    def test_elemento_sintetico_usa_a_classe_da_plataforma_ativa(self):
        """iOS e Android nomeiam o no generico de formas diferentes, e o codigo
        gerado carrega esse nome. Trocar a plataforma tem de trocar a classe."""
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=self.XML):
            self.ok("hierarchy.dump")

        android = self.ok("codegen.record", {"x": 900, "y": 1600})
        self.assertEqual(android["element"]["class_name"], "android.view.View")

        # Trocar de plataforma limpa a hierarquia carregada, entao o dump e
        # refeito pela fonte do iOS antes de gravar de novo.
        self.ok("session.select_device", {"platform": "ios", "device_id": "SIMULADOR"})
        with patch.object(self.server.ios, "get_ui_hierarchy", return_value=self.XML):
            self.ok("hierarchy.dump")
        ios = self.ok("codegen.record", {"x": 900, "y": 1600})
        self.assertEqual(ios["element"]["class_name"], "XCUIElementTypeOther")

    def test_estrategia_invalida_e_recusada(self):
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=self.XML):
            self.ok("hierarchy.dump")
        self.assertEqual(
            self.erro("codegen.record", {"x": 60, "y": 45, "strategy": "adivinhacao"})["data"]["code"],
            "invalid_input",
        )

    def test_captura_devolve_png_em_base64_com_dimensoes(self):
        with patch.object(self.server.adb, "take_screenshot", return_value=Image.new("RGB", (1080, 2400), "black")):
            captura = self.ok("screen.capture", {"max_width": 300})
        self.assertEqual(captura["width"], 300)
        self.assertEqual(captura["source_width"], 1080)
        self.assertTrue(captura["png_base64"].startswith("iVBOR"), "deve ser PNG em base64")


class TestDeteccaoAutomatica(ContractBase):
    def test_vigia_liga_e_desliga(self):
        self.assertTrue(self.ok("devices.watch_start", {"poll_interval": 0.05})["watching"])
        self.assertFalse(self.ok("devices.watch_stop")["watching"])

    def test_desligar_e_idempotente(self):
        self.assertFalse(self.ok("devices.watch_stop")["watching"])
        self.assertFalse(self.ok("devices.watch_stop")["watching"])

    def test_ligar_duas_vezes_substitui_o_vigia_anterior(self):
        self.ok("devices.watch_start", {"poll_interval": 0.05})
        self.assertTrue(self.ok("devices.watch_start", {"poll_interval": 0.05})["watching"])
        self.ok("devices.watch_stop")

    def test_aparelho_detectado_vira_alvo_da_sessao(self):
        import time
        from unittest.mock import patch
        with patch.object(self.server.adb, "list_devices", return_value=[("emulator-5554", "device")]):
            self.ok("devices.watch_start", {"poll_interval": 0.02})
            deadline = time.time() + 2.0
            while self.server.device_id is None and time.time() < deadline:
                time.sleep(0.02)
            self.ok("devices.watch_stop")

        self.assertEqual(self.server.device_id, "emulator-5554")
        avisos = [n for n in self.notificacoes() if n.get("method") == "device.changed"]
        self.assertGreaterEqual(len(avisos), 1)
        self.assertEqual(avisos[0]["params"]["device_id"], "emulator-5554")


class TestAmbienteEInicializacao(ContractBase):
    """O que a tela de estado vazio consome."""

    def test_diagnostico_traz_as_duas_plataformas_com_checagens(self):
        resultado = self.ok("diagnostics.check")
        self.assertEqual(set(resultado), {"ios", "android"})
        for plataforma in ("ios", "android"):
            bloco = resultado[plataforma]
            self.assertIn("title", bloco)
            self.assertIn("ready", bloco)
            self.assertGreater(len(bloco["checks"]), 0)
            for check in bloco["checks"]:
                self.assertEqual(set(check), {"label", "state", "detail", "action"})
                self.assertIn(check["state"], {"ok", "warn", "error", "busy", "off"})

    def test_diagnostico_nao_inventa_dispositivo_conectado(self):
        # O cartao antigo trazia um visto verde fixo em "Dispositivo conectado".
        from unittest.mock import patch
        with patch.object(self.server.adb, "is_available", return_value=True), \
             patch.object(self.server.adb, "list_devices", return_value=[]), \
             patch.object(self.server.adb, "list_avds", return_value=[]):
            android = self.ok("diagnostics.check")["android"]
        estados = {c["label"]: c["state"] for c in android["checks"]}
        self.assertNotEqual(estados.get("Dispositivo autorizado"), "ok")
        self.assertFalse(android["ready"])

    def test_listagem_de_simuladores(self):
        from unittest.mock import patch
        amostra = [{"udid": "A", "name": "iPhone 16", "state": "Shutdown",
                    "runtime": "iOS 18.0", "booted": False}]
        with patch.object(self.server.ios, "list_all_simulators", return_value=amostra):
            resultado = self.ok("simulators.list")
        self.assertEqual(resultado["simulators"][0]["udid"], "A")

    def test_boot_sem_udid_escolhe_o_primeiro(self):
        from unittest.mock import patch
        amostra = [{"udid": "A", "name": "iPhone 16", "state": "Shutdown",
                    "runtime": "iOS 18.0", "booted": False}]
        with patch.object(self.server.ios, "list_all_simulators", return_value=amostra), \
             patch.object(self.server.ios, "boot_simulator", return_value=(True, "Simulador iniciado.")) as boot:
            resultado = self.ok("simulators.boot")
        boot.assert_called_once()
        self.assertEqual(resultado["udid"], "A")
        self.assertTrue(resultado["booted"])

    def test_boot_prefere_simulador_ja_ligado(self):
        from unittest.mock import patch
        amostra = [
            {"udid": "A", "name": "iPhone 16", "state": "Shutdown", "runtime": "iOS 18.0", "booted": False},
            {"udid": "B", "name": "iPhone SE", "state": "Booted", "runtime": "iOS 18.0", "booted": True},
        ]
        with patch.object(self.server.ios, "list_all_simulators", return_value=amostra), \
             patch.object(self.server.ios, "boot_simulator", return_value=(True, "ja estava ligado")):
            self.assertEqual(self.ok("simulators.boot")["udid"], "B")

    def test_boot_sem_simulador_instalado_explica(self):
        from unittest.mock import patch
        with patch.object(self.server.ios, "list_all_simulators", return_value=[]):
            erro = self.erro("simulators.boot")
        self.assertIn("Nenhum simulador", erro["message"])

    def test_status_do_wda_expoe_o_estado_do_appium(self):
        resultado = self.ok("wda.status")
        self.assertEqual(
            set(resultado),
            {"wda_running", "appium_installed", "appium_running", "appium_url", "wda_url"},
        )

    def test_wda_sem_simulador_ligado_explica_a_ordem(self):
        from unittest.mock import patch
        with patch.object(self.server.ios, "list_all_simulators", return_value=[]):
            erro = self.erro("wda.start")
        self.assertIn("simulador", erro["message"].lower())

    def test_wda_start_delega_ao_appium(self):
        from unittest.mock import patch
        ligado = [{"udid": "B", "name": "iPhone 16", "state": "Booted",
                   "runtime": "iOS 18.0", "booted": True}]
        with patch.object(self.server.ios, "list_all_simulators", return_value=ligado), \
             patch.object(self.server.appium, "ensure_wda", return_value=(True, "WebDriverAgent no ar.")) as ensure:
            resultado = self.ok("wda.start")
        ensure.assert_called_once()
        self.assertEqual(ensure.call_args.args[0], "B")
        self.assertTrue(resultado["wda_running"])

    def test_falha_do_appium_chega_como_erro_de_dominio(self):
        from unittest.mock import patch
        ligado = [{"udid": "B", "name": "iPhone 16", "state": "Booted",
                   "runtime": "iOS 18.0", "booted": True}]
        with patch.object(self.server.ios, "list_all_simulators", return_value=ligado), \
             patch.object(self.server.appium, "ensure_wda",
                          return_value=(False, "xcodebuild failed with code 65")):
            erro = self.erro("wda.start")
        self.assertIn("xcodebuild", erro["message"])

    def test_boot_de_emulador_sem_avd_explica(self):
        from unittest.mock import patch
        with patch.object(self.server.adb, "list_avds", return_value=[]):
            self.assertIn("AVD", self.erro("emulators.boot")["message"])


class TestStreamingPorNotificacao(ContractBase):
    def setUp(self):
        super().setUp()
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})

    def test_quadros_chegam_como_notificacao(self):
        import time
        with patch.object(self.server.adb, "take_screenshot", return_value=Image.new("RGB", (400, 800), "black")):
            self.ok("stream.start", {"fps": 30, "max_width": 200})
            time.sleep(0.3)
            estatisticas = self.ok("stream.stats")
            self.ok("stream.stop")

        quadros = [n for n in self.notificacoes() if n.get("method") == "stream.frame"]
        self.assertGreaterEqual(len(quadros), 1)
        self.assertNotIn("id", quadros[0], "notificacao nao carrega id")
        self.assertIn("png_base64", quadros[0]["params"])

        # As metricas viajam com o quadro. Sem isso o front precisava de uma ida
        # e volta de `stream.stats` por quadro, e o laco de notificacoes dele
        # ficava parado esperando a resposta.
        for chave in ("fps", "capture_ms", "skipped"):
            self.assertIn(chave, quadros[0]["params"], f"{chave} deveria vir junto com o quadro")
        self.assertTrue(estatisticas["running"])
        self.assertGreater(estatisticas["frames_captured"], 0)

class TestScrcpy(ContractBase):
    def test_scrcpy_status_responde_com_disponibilidade(self):
        status = self.ok("scrcpy.status")
        self.assertIn("available", status)
        self.assertIn("running", status)

    def test_scrcpy_start_exige_dispositivo(self):
        erro = self.erro("scrcpy.start")
        self.assertEqual(erro["data"]["code"], "invalid_input")

    def test_scrcpy_stop_e_idempotente(self):
        resultado = self.ok("scrcpy.stop")
        self.assertTrue(resultado["stopped"])
        self.assertFalse(resultado["running"])


if __name__ == "__main__":
    unittest.main()
