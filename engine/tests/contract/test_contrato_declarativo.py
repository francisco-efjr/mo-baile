"""Tabela declarativa do contrato, aperto de mao e progresso.

`mobaile/rpc/contract.py` e a fonte de verdade que o front recebe em
`engine.hello`. Estes testes impedem que ela envelheca separada do que o motor
realmente expoe, do que ele realmente emite e do que a documentacao promete:
tabela que mente e pior que tabela nenhuma, porque o front confia nela.
"""

from __future__ import annotations

import io
import json
import pathlib
import re
import unittest
from unittest.mock import patch

from mobaile import __version__
from mobaile.rpc import contract, protocol
from mobaile.rpc.server import EngineServer

REPO = pathlib.Path(__file__).resolve().parents[3]
FONTE = REPO / "engine" / "src" / "mobaile"
DOC = REPO / "docs" / "PROTOCOLO_RPC.md"

XML = (
    '<hierarchy rotation="0">'
    '<node class="android.widget.Button" text="Continuar" clickable="true"'
    ' bounds="[10,20][110,70]" resource-id="br.app:id/btn_ok" package="br.app"/>'
    "</hierarchy>"
)
LIGADO = [{"udid": "B", "name": "iPhone 16", "state": "Booted", "runtime": "iOS 18.0", "booted": True}]


class Base(unittest.TestCase):
    def setUp(self):
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.addCleanup(self.server.shutdown)

    def call(self, method, params=None):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )

    def ok(self, method, params=None):
        response = self.call(method, params)
        self.assertNotIn("error", response, f"{method} devolveu erro: {response.get('error')}")
        return response["result"]

    def progresso(self):
        linhas = [json.loads(linha) for linha in self.out.getvalue().splitlines() if linha.strip()]
        return [n["params"] for n in linhas if n.get("method") == contract.PROGRESS]


class TestTabelaDeMetodos(Base):
    def test_tabela_cobre_exatamente_os_metodos_do_servidor(self):
        self.assertEqual(set(contract.METHODS), set(self.server.methods))

    def test_toda_entrada_tem_fila_prazo_e_progresso_validos(self):
        for nome, spec in contract.METHODS.items():
            with self.subTest(metodo=nome):
                self.assertEqual(set(spec), {"lane", "timeout_s", "progress"})
                self.assertIn(spec["lane"], contract.LANES)
                self.assertIsInstance(spec["timeout_s"], (int, float))
                self.assertGreater(spec["timeout_s"], 0)
                self.assertIsInstance(spec["progress"], bool)

    def test_fila_inline_so_tem_o_que_responde_em_milissegundos(self):
        inline = {nome for nome, spec in contract.METHODS.items() if spec["lane"] == contract.LANE_INLINE}
        self.assertEqual(inline, {"engine.hello", "engine.shutdown"})

    def test_cada_metodo_esta_na_fila_do_seu_pior_caso(self):
        """Consulta curta atras de preparo longo estoura prazo a toa, e metodo
        lento na fila rapida travaria toque e espelho de novo."""
        filas = {
            contract.LANE_ENVIRONMENT: {"wda.start", "simulators.boot", "simulators.shutdown", "emulators.boot"},
            contract.LANE_QUERY: {"devices.list", "wda.status", "simulators.list", "emulators.list",
                                  "diagnostics.check", "analytics.ios_devices"},
            contract.LANE_SERVICES: {"proxy.start", "proxy.stop", "proxy.events", "proxy.clear",
                                     "netlog.start", "netlog.stop",
                                     "analytics.start", "analytics.stop", "analytics.events", "analytics.clear",
                                     "flow.run", "flow.stop", "flow.status", "recording.start", "recording.stop"},
            contract.LANE_CAPTURE: {"hierarchy.dump", "screen.capture", "screen.size", "passive.start",
                                    "passive.stop"},
            contract.LANE_INLINE: {"engine.hello", "engine.shutdown"},
            # Relatorio nao toca aparelho: nem espera o espelho nem o segura.
            contract.LANE_REPORT: {"report.spec", "report.audit", "report.export", "report.import"},
        }
        for fila, metodos in filas.items():
            for nome in metodos:
                self.assertEqual(contract.lane_of(nome), fila, nome)
        rapidos = set(contract.METHODS) - set().union(*filas.values())
        self.assertEqual({contract.lane_of(nome) for nome in rapidos}, {contract.LANE_FAST})
        self.assertIn("input.tap", rapidos)
        self.assertIn("passive.status", rapidos)

    def test_stop_espera_quem_pode_estar_na_frente_na_fila(self):
        """O prazo conta a fila. Um `stop` que estoura ainda na fila sai dela sem
        efeito e deixa o recurso ligado, entao o prazo dele cobre o pior caso de
        quem pode estar na frente."""
        for nome, spec in contract.METHODS.items():
            if not nome.endswith(".stop") or spec["lane"] in (contract.LANE_FAST, contract.LANE_INLINE):
                continue
            vizinhos = [
                outro["timeout_s"] for outro_nome, outro in contract.METHODS.items()
                if outro["lane"] == spec["lane"] and not outro_nome.endswith(".stop")
            ]
            with self.subTest(metodo=nome):
                self.assertGreater(spec["timeout_s"], max(vizinhos))

    def test_quem_emite_progresso(self):
        com_progresso = {nome for nome, spec in contract.METHODS.items() if spec["progress"]}
        self.assertEqual(
            com_progresso,
            {"wda.start", "simulators.boot", "emulators.boot", "hierarchy.dump", "diagnostics.check",
             "report.audit", "report.export", "report.import"},
        )

    def test_engine_info_lista_os_mesmos_metodos(self):
        self.assertEqual(self.ok("engine.info")["methods"], sorted(contract.METHODS))


class TestDeriva(unittest.TestCase):
    """O contrato declarado contra o codigo e contra a documentacao."""

    @staticmethod
    def _emitidas_no_codigo() -> set[str]:
        emitidas = set()
        for arquivo in FONTE.rglob("*.py"):
            emitidas |= set(re.findall(r"\bnotify\(\s*\"([^\"]+)\"", arquivo.read_text(encoding="utf-8")))
        return emitidas

    def test_toda_notificacao_emitida_esta_declarada(self):
        emitidas = self._emitidas_no_codigo()
        self.assertGreater(len(emitidas), 5, "a busca por notify(...) parou de achar as notificacoes")
        self.assertEqual(emitidas - set(contract.NOTIFICATIONS), set())

    def test_toda_notificacao_declarada_e_emitida(self):
        # `$/progress` sai por `contract.PROGRESS`, nao por literal.
        declaradas = set(contract.NOTIFICATIONS) - {contract.PROGRESS}
        self.assertEqual(declaradas - self._emitidas_no_codigo(), set())

    def test_todo_metodo_e_notificacao_estao_na_documentacao(self):
        doc = DOC.read_text(encoding="utf-8")
        nomes = [*contract.METHODS, *contract.NOTIFICATIONS, *contract.CLIENT_NOTIFICATIONS]
        ausentes = [nome for nome in nomes if f"`{nome}`" not in doc]
        self.assertEqual(ausentes, [], "acrescente estes nomes as tabelas de docs/PROTOCOLO_RPC.md")

    def test_codigos_de_erro_novos_estao_na_documentacao(self):
        doc = DOC.read_text(encoding="utf-8")
        for codigo in ("incompatible_protocol", "request_cancelled"):
            self.assertIn(f"`{codigo}`", doc)


class TestHello(Base):
    def test_versao_igual_devolve_a_tabela(self):
        hello = self.ok("engine.hello", {"protocol_version": contract.PROTOCOL_VERSION, "client": "teste"})
        self.assertEqual(hello["protocol_version"], 2)
        self.assertEqual(hello["engine_version"], __version__)
        self.assertEqual(set(hello["capabilities"]), {"cancel", "progress", "lanes"})
        self.assertEqual(hello["methods"], contract.METHODS)
        self.assertEqual(hello["methods"]["hierarchy.dump"], {"lane": "capture", "timeout_s": 60, "progress": True})
        self.assertIn("$/progress", hello["notifications"])
        self.assertIn("stream.frame", hello["notifications"])

    def test_resultado_e_copia_e_nao_a_tabela_viva(self):
        hello = self.ok("engine.hello", {"protocol_version": contract.PROTOCOL_VERSION})
        hello["methods"]["wda.start"]["timeout_s"] = 1
        self.assertEqual(contract.METHODS["wda.start"]["timeout_s"], 600)

    def test_versao_diferente_e_recusada_citando_as_duas(self):
        erro = self.call("engine.hello", {"protocol_version": 1})["error"]
        self.assertEqual(erro["code"], protocol.ENGINE_ERROR)
        self.assertEqual(erro["data"]["code"], "incompatible_protocol")
        self.assertIn("1", erro["message"])
        self.assertIn("2", erro["message"])

    def test_sem_versao_tambem_e_incompativel(self):
        self.assertEqual(self.call("engine.hello")["error"]["data"]["code"], "incompatible_protocol")

    def test_hello_nao_e_obrigatorio(self):
        """Harness de QA e clientes antigos seguem funcionando sem ele."""
        self.assertIn("version", self.ok("engine.info"))


class TestProgresso(Base):
    def test_wda_start_com_token_emite_as_fases(self):
        with patch.object(self.server.ios, "list_all_simulators", return_value=LIGADO), \
             patch.object(self.server.appium, "ensure_wda", return_value=(True, "no ar")):
            self.ok("wda.start", {"progress_token": "wda-1"})
        fases = self.progresso()
        self.assertGreaterEqual(len(fases), 2)
        for fase in fases:
            self.assertEqual(set(fase), {"token", "message", "percent"})
            self.assertEqual(fase["token"], "wda-1")
            self.assertTrue(fase["message"])
        self.assertEqual(fases[-1]["percent"], 100)
        self.assertIsNone(fases[0]["percent"])

    def test_sem_token_nada_e_emitido(self):
        with patch.object(self.server.ios, "list_all_simulators", return_value=LIGADO), \
             patch.object(self.server.appium, "ensure_wda", return_value=(True, "no ar")):
            self.ok("wda.start")
        self.assertEqual(self.progresso(), [])

    def test_token_numerico_e_aceito(self):
        with patch.object(self.server.adb, "list_avds", return_value=["Pixel_9"]), \
             patch.object(self.server.adb, "start_avd", return_value=True):
            self.ok("emulators.boot", {"progress_token": 7})
        self.assertTrue(self.progresso())
        self.assertTrue(all(fase["token"] == 7 for fase in self.progresso()))

    def test_token_de_tipo_invalido_e_recusado(self):
        erro = self.call("wda.status", {"progress_token": {"x": 1}})["error"]
        self.assertEqual(erro["code"], protocol.INVALID_PARAMS)

    def test_boot_de_simulador_e_diagnostico_emitem(self):
        with patch.object(self.server.ios, "list_all_simulators", return_value=LIGADO), \
             patch.object(self.server.ios, "boot_simulator", return_value=(True, "ok")):
            self.ok("simulators.boot", {"progress_token": "sim"})
        self.ok("diagnostics.check", {"progress_token": "diag"})
        tokens = [fase["token"] for fase in self.progresso()]
        self.assertIn("sim", tokens)
        self.assertEqual(tokens.count("diag"), 2)

    def test_dump_so_emite_quando_cai_no_appium(self):
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=XML):
            self.ok("hierarchy.dump", {"force": True, "progress_token": "rapido"})
        self.assertEqual(self.progresso(), [], "o uiautomator responde em segundos: nao ha o que anunciar")

        with patch.object(self.server.adb, "get_ui_hierarchy", return_value=None), \
             patch.object(self.server.appium, "ensure_android_session", return_value=(True, "ok")), \
             patch.object(self.server.appium, "get_page_source", return_value=XML):
            self.ok("hierarchy.dump", {"force": True, "progress_token": "appium"})
        self.assertTrue(self.progresso())
        self.assertTrue(all(fase["token"] == "appium" for fase in self.progresso()))


if __name__ == "__main__":
    unittest.main()
