"""Flow no formato do Maestro pelo RPC: gravar, exportar e rodar no aparelho falso.

Servidor, `codegen.record`, parser e runner sao os reais; so o binario `adb` e
falso (ver `aparelho_falso.py`).
"""

from __future__ import annotations

import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from test_flow_execucao import SENTINELA, FluxoBase


class TestFlowMaestroRpc(FluxoBase):
    def exportar(self):
        self.gravar_android((540, 340, "id"), (540, 480, "id"))
        self.assertTrue(self.server.codegen.set_last_input_text(SENTINELA))
        return self.ok("flow.maestro_export", {"name": "Valor"})

    def test_exportar_nao_leva_o_texto_digitado(self):
        exportado = self.exportar()
        self.assertEqual(exportado["steps"], 2)
        self.assertNotIn(SENTINELA, exportado["yaml"])
        self.assertEqual(len(exportado["variables"]), 1)
        self.assertIn(f"${{{exportado['variables'][0]}}}", exportado["yaml"])
        self.assertIn('appId: "br.app"', exportado["yaml"])

    def test_salvar_nunca_sobrescreve_e_fica_em_flows(self):
        self.gravar_android((540, 480, "id"))
        with tempfile.TemporaryDirectory() as casa, patch("pathlib.Path.home", return_value=Path(casa)):
            primeiro = self.ok("flow.maestro_export", {"save": True, "name": "login"})
            segundo = self.ok("flow.maestro_export", {"save": True, "name": "login"})
            pasta = Path(casa) / "Documents" / "Mo baile" / "flows"
            self.assertEqual(Path(primeiro["path"]), pasta / "login.yaml")
            self.assertEqual(Path(segundo["path"]), pasta / "login_2.yaml")
            self.assertEqual(Path(primeiro["path"]).read_text(encoding="utf-8"), primeiro["yaml"])
            # Corrida: outra exportacao criou o nome entre conferir e gravar.
            # Conferir com `exists()` e gravar por cima perderia o primeiro.
            with patch("pathlib.Path.exists", return_value=False):
                terceiro = self.ok("flow.maestro_export", {"save": True, "name": "login"})
            self.assertEqual(Path(terceiro["path"]), pasta / "login_3.yaml")
            self.assertEqual(Path(primeiro["path"]).read_text(encoding="utf-8"), primeiro["yaml"])

    def test_rodar_o_flow_exportado_no_aparelho(self):
        exportado = self.exportar()
        env = {exportado["variables"][0]: SENTINELA}
        self.assertTrue(self.ok("flow.maestro_check", {"yaml": exportado["yaml"], "env": env})["valid"])

        self.adb.limpar_registro()
        iniciado = self.ok("flow.maestro_run", {"yaml": exportado["yaml"], "env": env})
        self.assertTrue(iniciado["running"])
        fim = self.esperar_fim()

        self.assertTrue(fim["success"], fim)
        chamadas = [" ".join(c) for c in self.adb.chamadas()]
        self.assertTrue(any("am force-stop br.app" in c for c in chamadas), "launchApp para o app antes")
        self.assertTrue(any("monkey -p br.app" in c for c in chamadas), "launchApp abre pelo LAUNCHER")
        self.assertIn(f"input text '{SENTINELA}'", self.adb.textos())
        self.assertEqual(self.adb.toques(), [(540, 340), (540, 480)])
        self.assertNotIn(SENTINELA, self.out.getvalue(), "texto digitado vazou para o stdout do motor")
        self.assertFalse([linha for linha in self.log.linhas if SENTINELA in linha])

    def test_elemento_ausente_falha_com_motivo_e_libera_a_trava(self):
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        flow = "- tapOn:\n    text: Inexistente\n    optional: true\n- assertVisible: Continuar\n"
        self.ok("flow.maestro_run", {"yaml": flow})
        fim = self.esperar_fim(prazo=30)
        self.assertTrue(fim["success"], fim)
        self.assertFalse(self.ok("flow.status")["running"])

    def test_flow_invalido_nao_ocupa_o_aparelho(self):
        resposta = self.call("flow.maestro_run", {"yaml": "- runScript: x.js\n"})
        self.assertIn("error", resposta)
        self.assertIn("JavaScript", resposta["error"]["message"])
        self.assertFalse(self.ok("flow.status")["running"])


    def test_flow_step_so_conta_comandos_de_topo(self):
        # onFlowStart, onFlowComplete e os subpassos de retry/runFlow tambem
        # passam por `_passo`; a barra do front conta so os comandos de topo.
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        flow = (
            "appId: br.app\n"
            "onFlowStart:\n  - assertVisible: Continuar\n"
            "onFlowComplete:\n  - assertVisible: Continuar\n"
            "---\n"
            "- assertVisible: Continuar\n"
            "- retry:\n    maxRetries: 1\n    commands:\n"
            "      - assertVisible: Continuar\n      - assertVisible: Continuar\n"
            "- runFlow:\n    commands:\n      - assertVisible: Continuar\n"
        )
        self.ok("flow.maestro_run", {"yaml": flow})
        fim = self.esperar_fim(prazo=30)

        self.assertTrue(fim["success"], fim)
        self.assertIs(fim.get("cancelled"), False, fim)
        self.assertEqual(
            self.notificacoes("flow.step"),
            [{"index": 1, "total": 3}, {"index": 2, "total": 3}, {"index": 3, "total": 3}],
        )

    def test_flow_stop_no_maestro_termina_com_cancelled(self):
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        # O primeiro comando espera um elemento que nunca aparece: o stop chega
        # durante a espera.
        flow = "- tapOn:\n    text: Inexistente\n    optional: true\n- assertVisible: Continuar\n"
        self.ok("flow.maestro_run", {"yaml": flow})
        limite = time.monotonic() + 10
        while not self.notificacoes("flow.step") and time.monotonic() < limite:
            time.sleep(0.02)
        self.assertTrue(self.ok("flow.stop")["stopped"])
        fim = self.esperar_fim(prazo=30)

        self.assertIs(fim.get("cancelled"), True, fim)
        self.assertFalse(fim["success"], fim)
        self.assertEqual([n["index"] for n in self.notificacoes("flow.step")], [1])


if __name__ == "__main__":
    unittest.main()
