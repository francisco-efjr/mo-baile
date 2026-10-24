"""Flow no formato do Maestro pelo RPC: gravar, exportar e rodar no aparelho falso.

Servidor, `codegen.record`, parser e runner sao os reais; so o binario `adb` e
falso (ver `aparelho_falso.py`).
"""

from __future__ import annotations

import unittest

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


if __name__ == "__main__":
    unittest.main()
