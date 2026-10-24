"""Flows no formato do Maestro: leitura, selecao de elemento, esperas e exportacao.

Nada aqui toca aparelho nem rede: o `FlowDevice` e um falso que troca de tela
conforme o toque, e o relogio e de mentira, para os prazos de 17 s nao custarem
17 s.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from mobaile.adapters.flow_devices import AndroidFlowDevice, validate_app_id
from mobaile.domain.errors import InvalidInputError
from mobaile.domain.models import AutomationStep, LocatorStrategy
from mobaile.services.hierarchy import UIHierarchyParser
from mobaile.services.maestro_flow import (
    FlowRunner,
    Selector,
    export_steps,
    parse_flow,
    resolve_point,
    select_elements,
    selector_from_step,
)


def no(classe="android.widget.TextView", bounds="[0,0][10,10]", texto="", rid="", desc="",
       clicavel=False, filhos=""):
    return (f'<node class="{classe}" package="br.app" bounds="{bounds}" text="{texto}" '
            f'resource-id="{rid}" content-desc="{desc}" clickable="{str(clicavel).lower()}">{filhos}</node>')


def tela(*nos: str) -> str:
    return ("<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation=\"0\">"
            + no("android.widget.FrameLayout", "[0,0][1080,2400]", filhos="".join(nos)) + "</hierarchy>")


LOGIN = tela(
    no("android.widget.EditText", "[100,300][980,380]", rid="br.app:id/campo_email", clicavel=True),
    no("android.widget.Button", "[100,400][980,560]", rid="br.app:id/btn_entrar", clicavel=True,
       filhos=no(bounds="[400,450][680,510]", texto="Entrar")),
    no(bounds="[100,600][980,640]", texto="Esqueci a senha"),
)
HOME = tela(no(bounds="[100,200][980,260]", texto="Bem-vindo, Ana"))
CARREGANDO = tela(no("android.widget.ProgressBar", "[500,1100][580,1180]"))


class Relogio:
    def __init__(self):
        self.t = 0.0

    def __call__(self) -> float:
        return self.t

    def dormir(self, s: float) -> None:
        self.t += s


class AparelhoFalso:
    """Telas em sequencia. `leituras_ate_mudar` simula uma tela que demora a aparecer."""

    platform = "android"

    def __init__(self, telas: dict[str, str], inicial: str, transicoes: dict | None = None):
        self.telas = telas
        self.atual = inicial
        self.transicoes = transicoes or {}
        self.pendente: tuple[str, int] | None = None
        self.toques: list[tuple[int, int]] = []
        self.digitado: list[str] = []
        self.teclas: list[str] = []
        self.apps: list[tuple[str, str]] = []
        self.deslizes = 0

    def hierarchy(self):
        if self.pendente:
            proxima, faltam = self.pendente
            if faltam <= 0:
                self.atual, self.pendente = proxima, None
            else:
                self.pendente = (proxima, faltam - 1)
        return self.telas[self.atual]

    def screen_size(self):
        return (1080, 2400)

    def tap(self, x, y):
        self.toques.append((x, y))
        for (origem, x1, y1, x2, y2), (destino, atraso) in self.transicoes.items():
            if origem == self.atual and x1 <= x <= x2 and y1 <= y <= y2:
                self.pendente = (destino, atraso)
        return True

    def type_text(self, text):
        self.digitado.append(text)
        return True

    def press_key(self, key):
        self.teclas.append(key)
        return key in ("Back", "Enter", "Backspace", "Escape")

    def swipe(self, *_args):
        self.deslizes += 1
        destino = self.transicoes.get(("swipe", self.atual))
        if destino:
            self.atual = destino
        return True

    def launch_app(self, app_id):
        self.apps.append(("launch", app_id))
        return True

    def stop_app(self, app_id):
        self.apps.append(("stop", app_id))
        return True

    def clear_state(self, app_id):
        self.apps.append(("clear", app_id))
        return True


def runner(aparelho, relogio=None, cancelado=lambda: False):
    relogio = relogio or Relogio()
    linhas: list[str] = []
    r = FlowRunner(aparelho, log=linhas.append, clock=relogio, sleep=relogio.dormir, cancelled=cancelado)
    return r, linhas, relogio


FLOW_LOGIN = """
appId: br.app
name: Login
tags: [smoke]
env:
  EMAIL: ana@exemplo.com
---
- launchApp
- tapOn:
    id: campo_email
- inputText: ${EMAIL}
- tapOn: Entrar
- assertVisible: "Bem-vindo, .*"
"""


class LeituraTest(unittest.TestCase):
    def test_cabecalho_e_comandos(self):
        flow = parse_flow(FLOW_LOGIN)
        self.assertEqual(flow.app_id, "br.app")
        self.assertEqual(flow.tags, ("smoke",))
        self.assertEqual([s.command for s in flow.steps],
                         ["launchApp", "tapOn", "inputText", "tapOn", "assertVisible"])
        self.assertEqual(flow.steps[3].selector, Selector(text="Entrar"))
        self.assertEqual(flow.steps[1].selector, Selector(id="campo_email"))

    def test_env_do_chamador_vence_o_do_cabecalho_e_vira_segredo(self):
        flow = parse_flow(FLOW_LOGIN, env={"EMAIL": "bia@exemplo.com"})
        self.assertEqual(flow.steps[2].text, "bia@exemplo.com")
        self.assertIn("bia@exemplo.com", flow.secrets)
        self.assertNotIn("bia@exemplo.com", flow.steps[2].describe())

    def test_lista_sem_cabecalho_vale(self):
        flow = parse_flow("- tapOn: OK\n- back\n")
        self.assertIsNone(flow.app_id)
        self.assertEqual(flow.steps[1].key, "Back")

    def test_javascript_e_recusado(self):
        with self.assertRaisesRegex(InvalidInputError, "JavaScript"):
            parse_flow("- inputText: ${faker.name()}\n")
        with self.assertRaisesRegex(InvalidInputError, "GraalJS"):
            parse_flow("- runScript: setup.js\n")

    def test_ia_e_nuvem_sao_recusadas_com_motivo(self):
        with self.assertRaisesRegex(InvalidInputError, "nuvem da mobile.dev"):
            parse_flow("- assertWithAI:\n    assertion: tudo certo\n")

    def test_variavel_sem_valor_e_comando_desconhecido(self):
        with self.assertRaisesRegex(InvalidInputError, "sem valor"):
            parse_flow("- inputText: ${SENHA}\n")
        with self.assertRaisesRegex(InvalidInputError, "ainda nao e suportado"):
            parse_flow("- setLocation:\n    latitude: 1\n    longitude: 2\n")

    def test_propriedade_desconhecida_nao_e_ignorada_em_silencio(self):
        with self.assertRaisesRegex(InvalidInputError, "nao suportada: enabled"):
            parse_flow("- tapOn:\n    text: OK\n    enabled: true\n")

    def test_flow_web_recusado(self):
        with self.assertRaisesRegex(InvalidInputError, "web"):
            parse_flow("url: https://exemplo.com\n---\n- tapOn: OK\n")

    def test_env_do_bloco_vale_so_dentro_dele(self):
        flow = parse_flow("- runFlow:\n    env: {X: dentro}\n    commands:\n      - inputText: ${X}\n")
        self.assertEqual(flow.steps[0].steps[0].text, "dentro")
        with self.assertRaisesRegex(InvalidInputError, "sem valor"):
            parse_flow("- runFlow:\n    env: {X: dentro}\n    commands: [inputText: a]\n- inputText: ${X}\n")

    def test_run_flow_de_arquivo_e_ciclo(self):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d)
            (base / "sub.yaml").write_text("appId: br.app\n---\n- tapOn: Entrar\n", encoding="utf-8")
            flow = parse_flow("- runFlow: sub.yaml\n", path=base / "main.yaml")
            self.assertEqual(flow.steps[0].steps[0].selector, Selector(text="Entrar"))
            (base / "ciclo.yaml").write_text("- runFlow: ciclo.yaml\n", encoding="utf-8")
            with self.assertRaisesRegex(InvalidInputError, "aninhado demais"):
                parse_flow("- runFlow: ciclo.yaml\n", path=base / "main.yaml")

    def test_retry_limitado_a_tres(self):
        with self.assertRaisesRegex(InvalidInputError, "maxRetries"):
            parse_flow("- retry:\n    maxRetries: 4\n    commands: [back]\n")

    def test_ponto(self):
        self.assertEqual(resolve_point("50%,25%", 1080, 2400), (540, 600))
        self.assertEqual(resolve_point("10, 20", 1080, 2400), (10, 20))
        with self.assertRaises(InvalidInputError):
            parse_flow("- tapOn:\n    point: 150%,1%\n")


class SelecaoTest(unittest.TestCase):
    def setUp(self):
        self.els = UIHierarchyParser.parse_xml(LOGIN)

    def nomes(self, sel):
        return [self.els[i].text or self.els[i].resource_id for i in select_elements(sel, self.els)]

    def test_texto_e_regex_de_casamento_inteiro_sem_caixa(self):
        self.assertEqual(self.nomes(Selector(text="entrar")), ["Entrar"])
        self.assertEqual(self.nomes(Selector(text="Entr")), [])
        self.assertEqual(self.nomes(Selector(text="Esqueci.*")), ["Esqueci a senha"])

    def test_regex_invalida_vira_literal(self):
        els = UIHierarchyParser.parse_xml(tela(no(bounds="[0,0][90,90]", texto="Total (R$")))
        self.assertEqual(len(select_elements(Selector(text="Total (R$"), els)), 1)

    def test_id_casa_com_e_sem_pacote(self):
        self.assertEqual(self.nomes(Selector(id="btn_entrar")), ["br.app:id/btn_entrar"])
        self.assertEqual(self.nomes(Selector(id="br.app:id/btn_entrar")), ["br.app:id/btn_entrar"])

    def test_relativo_e_indice(self):
        self.assertEqual(self.nomes(Selector(below=Selector(id="btn_entrar"))), ["Esqueci a senha"])
        self.assertEqual(self.nomes(Selector(text="Esqueci a senha", above=Selector(id="campo_email"))), [])
        self.assertEqual(self.nomes(Selector(id=".*", index=0)), ["br.app:id/campo_email"])
        self.assertEqual(self.nomes(Selector(id=".*", index=-1)), ["br.app:id/btn_entrar"])

    def test_filho_e_pai(self):
        self.assertEqual(self.nomes(Selector(text="Entrar", child_of=Selector(id="btn_entrar"))), ["Entrar"])
        self.assertEqual(self.nomes(Selector(contains_child=Selector(text="Entrar"))), ["br.app:id/btn_entrar"])

    def test_mais_fundo_vence_e_clicavel_vem_primeiro(self):
        els = UIHierarchyParser.parse_xml(tela(
            no(bounds="[0,0][500,100]", texto="Pagar"),
            no("android.widget.Button", "[0,200][500,300]", texto="Pagar", clicavel=True),
        ))
        escolhidos = select_elements(Selector(text="Pagar"), els)
        self.assertTrue(els[escolhidos[0]].clickable)


class ExecucaoTest(unittest.TestCase):
    def aparelho_login(self, atraso=0):
        return AparelhoFalso(
            {"login": LOGIN, "home": HOME, "carregando": CARREGANDO}, "login",
            {("login", 100, 400, 980, 560): ("home", atraso)},
        )

    def test_flow_de_login_inteiro(self):
        aparelho = self.aparelho_login()
        r, linhas, _ = runner(aparelho)
        resultado = r.run(parse_flow(FLOW_LOGIN, env={"EMAIL": "segredo@exemplo.com"}))
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.apps, [("stop", "br.app"), ("launch", "br.app")])
        self.assertEqual(aparelho.digitado, ["segredo@exemplo.com"])
        self.assertEqual(aparelho.toques[-1], (540, 480), "centro do rotulo mais fundo, dentro do botao")
        self.assertFalse(any("segredo@exemplo.com" in linha for linha in linhas))

    def test_espera_a_tela_aparecer_sem_sleep_fixo(self):
        # A home leva 12 leituras para aparecer; o assert espera, dentro dos 17 s.
        aparelho = self.aparelho_login(atraso=12)
        r, _, relogio = runner(aparelho)
        resultado = r.run(parse_flow("appId: br.app\n---\n- tapOn: Entrar\n- assertVisible: Bem-vindo.*\n"))
        self.assertTrue(resultado.success, resultado.message)
        self.assertLess(relogio.t, 17)

    def test_elemento_que_nunca_aparece_falha_no_prazo(self):
        r, _, relogio = runner(self.aparelho_login())
        resultado = r.run(parse_flow("- tapOn: Cadastrar\n- back\n"))
        self.assertFalse(resultado.success)
        self.assertIn("nao encontrado em 17 s", resultado.message)
        self.assertEqual(resultado.steps_run, 0)
        self.assertGreaterEqual(relogio.t, 17)

    def test_opcional_segue_com_prazo_menor(self):
        aparelho = self.aparelho_login()
        r, linhas, relogio = runner(aparelho)
        resultado = r.run(parse_flow("- tapOn:\n    text: Pular\n    optional: true\n- back\n"))
        self.assertTrue(resultado.success)
        self.assertLess(relogio.t, 10)
        self.assertEqual(aparelho.teclas, ["Back"])
        self.assertTrue(any("opcional" in linha for linha in linhas))

    def test_assert_not_visible(self):
        aparelho = self.aparelho_login(atraso=2)
        r, _, _ = runner(aparelho)
        ok = r.run(parse_flow("- tapOn: Entrar\n- assertNotVisible: Entrar\n"))
        self.assertTrue(ok.success, ok.message)
        r2, _, _ = runner(self.aparelho_login())
        falha = r2.run(parse_flow("- assertNotVisible: Entrar\n"))
        self.assertIn("continua visivel", falha.message)

    def test_run_flow_condicional_e_retry(self):
        aparelho = self.aparelho_login()
        r, linhas, _ = runner(aparelho)
        flow = parse_flow(
            "- runFlow:\n    when: {platform: iOS}\n    commands: [back]\n"
            "- runFlow:\n    when: {visible: Esqueci.*}\n    commands: [{pressKey: Enter}]\n"
            "- retry:\n    maxRetries: 2\n    commands:\n      - tapOn: {text: Nunca, optional: false}\n"
        )
        r.lookup_timeout_s = 1
        resultado = r.run(flow)
        self.assertEqual(aparelho.teclas, ["Enter"], "o bloco de iOS foi pulado")
        self.assertFalse(resultado.success)
        self.assertEqual(sum("tentativa" in linha for linha in linhas), 2)

    def test_scroll_until_visible(self):
        aparelho = AparelhoFalso({"a": LOGIN, "b": HOME}, "a", {("swipe", "a"): "b"})
        r, _, _ = runner(aparelho)
        resultado = r.run(parse_flow("- scrollUntilVisible:\n    element: Bem-vindo.*\n"))
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.deslizes, 1)

    def test_cancelar_para_antes_do_proximo_passo(self):
        aparelho = self.aparelho_login()
        r, _, _ = runner(aparelho, cancelado=lambda: len(aparelho.teclas) >= 1)
        resultado = r.run(parse_flow("- back\n- back\n- back\n"))
        self.assertFalse(resultado.success)
        self.assertEqual(resultado.message, "Flow cancelado.")
        self.assertEqual(aparelho.teclas, ["Back"])

    def test_on_flow_complete_roda_mesmo_com_falha(self):
        aparelho = self.aparelho_login()
        r, _, _ = runner(aparelho)
        r.lookup_timeout_s = 1
        resultado = r.run(parse_flow("appId: br.app\nonFlowComplete: [stopApp]\n---\n- tapOn: Nada\n"))
        self.assertFalse(resultado.success)
        self.assertEqual(aparelho.apps, [("stop", "br.app")])

    def test_launch_app_sem_app_id_falha_com_motivo(self):
        r, _, _ = runner(self.aparelho_login())
        self.assertIn("appId", r.run(parse_flow("- launchApp\n")).message)


def passo(n, locator, acao="click", coords=(10, 20), plataforma="android", nome="CAMPO_EMAIL"):
    return AutomationStep(step_num=n, action_type=acao, var_name=nome, element_name="email",
                          class_name="android.widget.EditText", strategy=LocatorStrategy.ID,
                          locator_value=locator, coords=coords, input_text="segredo", package="br.app",
                          platform=plataforma)


class ExportacaoTest(unittest.TestCase):
    def test_cada_localizador_vira_seletor(self):
        self.assertEqual(selector_from_step(passo(1, '(AppiumBy.ID, "br.app:id/btn")')), {"id": "br\\.app:id/btn"})
        self.assertEqual(selector_from_step(passo(1, '(AppiumBy.ACCESSIBILITY_ID, "Menu")')), {"text": "Menu"})
        self.assertEqual(selector_from_step(passo(1, '(AppiumBy.ACCESSIBILITY_ID, "menu")', plataforma="ios")),
                         {"id": "menu"})
        xpath = "(AppiumBy.XPATH, '//android.widget.TextView[@text=\"Total (R$)\"]')"
        self.assertEqual(selector_from_step(passo(1, xpath)), {"text": "Total \\(R\\$\\)"})
        self.assertEqual(selector_from_step(passo(1, "(AppiumBy.XPATH, '//*')", coords=(5, 7))), {"point": "5,7"})

    def test_texto_digitado_nao_vai_para_o_arquivo(self):
        yaml, variaveis = export_steps([passo(1, '(AppiumBy.ID, "br.app:id/campo_email")', acao="input")])
        self.assertNotIn("segredo", yaml)
        self.assertEqual(variaveis, ["CAMPO_EMAIL"])
        self.assertIn("- inputText: ${CAMPO_EMAIL}", yaml)

    def test_ida_e_volta_roda_no_runner(self):
        passos = [
            passo(1, '(AppiumBy.ID, "br.app:id/campo_email")', acao="input"),
            passo(2, "(AppiumBy.XPATH, '//android.widget.TextView[@text=\"Entrar\"]')", nome="BOTAO_ENTRAR"),
        ]
        yaml, variaveis = export_steps(passos, name='Login "rapido": v1')
        flow = parse_flow(yaml, env=dict.fromkeys(variaveis, "ana@exemplo.com"))
        self.assertEqual(flow.name, 'Login "rapido": v1')
        aparelho = AparelhoFalso({"login": LOGIN, "home": HOME}, "login",
                                 {("login", 100, 400, 980, 560): ("home", 0)})
        r, _, _ = runner(aparelho)
        resultado = r.run(flow)
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.digitado, ["ana@exemplo.com"])
        self.assertEqual(aparelho.atual, "home")


class AdbFalso:
    def __init__(self):
        self.comandos: list[list[str]] = []

    def _device_args(self, serial, *rest):
        return ["-s", serial, *rest]

    def _run_cmd(self, args, timeout=10):
        self.comandos.append(args)
        return 0, b"", b""


class AdapterAndroidTest(unittest.TestCase):
    def test_launch_stop_clear_e_swipe(self):
        adb = AdbFalso()
        aparelho = AndroidFlowDevice(adb, "emulator-5554", hierarchy=lambda: LOGIN)
        self.assertTrue(aparelho.launch_app("br.app"))
        self.assertTrue(aparelho.stop_app("br.app"))
        self.assertTrue(aparelho.clear_state("br.app"))
        self.assertTrue(aparelho.swipe(540, 1680, 540, 720, 400))
        self.assertEqual([c[3:5] for c in adb.comandos],
                         [["monkey", "-p"], ["am", "force-stop"], ["pm", "clear"], ["input", "swipe"]])

    def test_app_id_com_shell_e_recusado(self):
        for ruim in ("br.app; reboot", "$(id)", "semponto", "a" * 300):
            with self.subTest(ruim=ruim), self.assertRaises(InvalidInputError):
                validate_app_id(ruim)
        self.assertEqual(validate_app_id("com.app.X-beta"), "com.app.X-beta")


if __name__ == "__main__":
    unittest.main()
