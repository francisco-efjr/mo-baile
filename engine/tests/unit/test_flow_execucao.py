"""Execucao de fluxo de ponta a ponta no motor, com aparelho falso so na borda.

Servidor JSON-RPC, gravacao (`codegen.record` sobre a arvore lida do `adb`),
processo filho do fluxo e parser de hierarquia sao os reais. Falsos: o binario
`adb` e o WebDriverAgent HTTP (ver `aparelho_falso.py`).
"""

from __future__ import annotations

import io
import json
import logging
import tempfile
import time
import unittest
from pathlib import Path

from aparelho_falso import SERIAL, AdbFalso

from mobaile.rpc.server import EngineServer

SENTINELA = "SENTINELA-7f3a"


class _CapturaDeLog(logging.Handler):
    """Tudo que o motor loga, em qualquer nivel, durante o teste."""

    def __init__(self) -> None:
        super().__init__(level=logging.DEBUG)
        self.linhas: list[str] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.linhas.append(record.getMessage())
        if record.exc_info:
            self.linhas.append(logging.Formatter().formatException(record.exc_info))


class FluxoBase(unittest.TestCase):
    def setUp(self):
        self._pasta = tempfile.TemporaryDirectory()
        self.addCleanup(self._pasta.cleanup)
        self.adb = AdbFalso(Path(self._pasta.name))
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.server.adb.adb_path = str(self.adb.caminho)
        self.addCleanup(self.server.shutdown)

        self.log = _CapturaDeLog()
        raiz = logging.getLogger()
        nivel_anterior = raiz.level
        raiz.addHandler(self.log)
        raiz.setLevel(logging.DEBUG)
        self.addCleanup(raiz.removeHandler, self.log)
        self.addCleanup(raiz.setLevel, nivel_anterior)

    def call(self, method, params=None):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )

    def ok(self, method, params=None):
        resposta = self.call(method, params)
        self.assertNotIn("error", resposta, f"{method} devolveu erro: {resposta.get('error')}")
        return resposta["result"]

    def mensagens(self) -> list[dict]:
        return [json.loads(linha) for linha in self.out.getvalue().splitlines() if linha.strip()]

    def notificacoes(self, metodo: str) -> list[dict]:
        return [m["params"] for m in self.mensagens() if m.get("method") == metodo]

    def esperar_fim(self, prazo: float = 20.0) -> dict:
        limite = time.monotonic() + prazo
        while time.monotonic() < limite:
            fins = self.notificacoes("flow.finished")
            if fins:
                return fins[-1]
            time.sleep(0.02)
        self.fail(f"flow.finished nao chegou. Recebido: {self.out.getvalue()[-2000:]}")

    def gravar_android(self, *toques: tuple[int, int, str]) -> None:
        """Grava passos pelo caminho real: arvore do aparelho e `codegen.record`."""
        self.ok("session.select_device", {"platform": "android", "device_id": SERIAL})
        self.ok("hierarchy.dump", {"force": True})
        for x, y, estrategia in toques:
            self.ok("codegen.record", {"x": x, "y": y, "strategy": estrategia})


class TestPrivacidadeDaEntrada(FluxoBase):
    def test_texto_digitado_chega_ao_aparelho_e_nunca_a_log_nem_notificacao(self):
        # Defeito: o runner imprimia "Preenchendo texto '<valor>'" e a linha
        # virava `flow.log` para a interface (e para quem guardasse o log).
        self.gravar_android((540, 340, "id"), (540, 480, "id"))
        self.assertTrue(self.server.codegen.set_last_input_text(SENTINELA))
        self.adb.teclado(True)

        self.ok("flow.run")
        fim = self.esperar_fim()

        self.assertTrue(fim["success"], fim)
        self.assertIn(f"input text '{SENTINELA}'", self.adb.textos(), "o texto real nao chegou ao aparelho")
        self.assertNotIn(SENTINELA, self.out.getvalue(), "texto digitado vazou para o stdout do motor")
        self.assertFalse([linha for linha in self.log.linhas if SENTINELA in linha],
                         "texto digitado vazou para o log do motor")
        self.assertTrue(self.notificacoes("flow.log"), "a execucao deveria continuar narrando o andamento")

    def test_passo_de_digitacao_sem_texto_falha_sem_inventar_valor(self):
        # Defeito: input sem texto digitava "Texto de Exemplo" no aparelho.
        self.gravar_android((540, 340, "id"))
        self.adb.teclado(True)

        self.ok("flow.run")
        fim = self.esperar_fim()

        self.assertFalse(fim["success"], fim)
        self.assertEqual(self.adb.textos(), [], "nenhum texto pode ser digitado sem valor gravado")
        narrado = " ".join(n["line"] for n in self.notificacoes("flow.log")) + fim["message"]
        self.assertIn("sem texto", narrado.lower())
        self.assertNotIn("Exemplo", self.out.getvalue())


class TestDigitacaoIOS(FluxoBase):
    """F3: no iOS o passo de digitacao digitava nada e era dado como sucesso."""

    def setUp(self):
        super().setUp()
        import os
        from dataclasses import replace
        from unittest.mock import patch

        from aparelho_falso import UDID, WdaFalso, xcrun_falso

        import mobaile.rpc.server as rpc_server
        import mobaile.services.flows as flows_mod

        self.wda = WdaFalso()
        self.addCleanup(self.wda.fechar)
        # A pre-condicao iOS lista os simuladores com `xcrun simctl`.
        pasta = xcrun_falso(Path(self._pasta.name))
        patcher = patch.dict(os.environ, {"PATH": f"{pasta}{os.pathsep}{os.environ.get('PATH', '')}"})
        patcher.start()
        self.addCleanup(patcher.stop)
        for modulo in (rpc_server, flows_mod):
            patcher = patch.object(modulo, "settings", replace(modulo.settings, wda_url=self.wda.url))
            patcher.start()
            self.addCleanup(patcher.stop)
        self.ok("session.select_device", {"platform": "ios", "device_id": UDID})

    def _passo_ios(self, action_type, texto=None):
        from mobaile.domain.models import AutomationStep, LocatorStrategy

        passos = self.server.codegen.steps
        passos.append(AutomationStep(
            step_num=len(passos) + 1, action_type=action_type, var_name="CAMPO_EMAIL",
            element_name="email", class_name="XCUIElementTypeTextField", strategy=LocatorStrategy.ID,
            locator_value='(AppiumBy.ACCESSIBILITY_ID, "email")', coords=(200, 300),
            input_text=texto, package="", platform="ios",
        ))

    def _digitado(self) -> list[str]:
        return ["".join(c.get("value") or []) for c in self.wda.posts("/wda/keys") if isinstance(c, dict)]

    def test_texto_chega_ao_wda_e_nunca_ao_log(self):
        self._passo_ios("input", SENTINELA)
        self.ok("flow.run")
        fim = self.esperar_fim()
        self.assertTrue(fim["success"], fim)
        self.assertEqual(self._digitado(), [SENTINELA])
        self.assertTrue(self.wda.posts("/wda/tap"), "o campo precisa receber o toque antes do texto")
        self.assertNotIn(SENTINELA, self.out.getvalue(), "texto digitado vazou para o stdout do motor")
        self.assertFalse([linha for linha in self.log.linhas if SENTINELA in linha])

    def test_passo_sem_texto_falha_em_vez_de_virar_toque(self):
        self._passo_ios("input")
        self.ok("flow.run")
        fim = self.esperar_fim()
        self.assertFalse(fim["success"], fim)
        self.assertEqual(self._digitado(), [])
        narrado = " ".join(n["line"] for n in self.notificacoes("flow.log")) + fim["message"]
        self.assertIn("sem texto", narrado.lower())

    def test_erro_semantico_do_wda_e_falha_sem_repetir_o_texto(self):
        self.wda.falha_digitacao = "semantica"
        self._passo_ios("input", SENTINELA)
        self.ok("flow.run")
        fim = self.esperar_fim()
        self.assertFalse(fim["success"], fim)
        self.assertNotIn(SENTINELA, self.out.getvalue())

    def test_clique_continua_funcionando(self):
        self._passo_ios("click")
        self.ok("flow.run")
        fim = self.esperar_fim()
        self.assertTrue(fim["success"], fim)
        self.assertEqual(self._digitado(), [])


if __name__ == "__main__":
    unittest.main()
