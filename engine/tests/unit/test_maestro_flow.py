"""Flows no formato do Maestro: leitura, selecao de elemento, esperas e exportacao.

Nada aqui toca aparelho nem rede: o `FlowDevice` e um falso que troca de tela
conforme o toque, e o relogio e de mentira, para os prazos de 17 s nao custarem
17 s.
"""

from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from mobaile.adapters.flow_devices import AndroidFlowDevice, validate_app_id
from mobaile.domain.errors import InvalidInputError
from mobaile.domain.models import AutomationStep, LocatorStrategy
from mobaile.ports import FlowDevice
from mobaile.services.hierarchy import UIHierarchyParser
from mobaile.services.maestro_flow import (
    _ACOES_NO_APARELHO,
    FlowRunner,
    Selector,
    export_steps,
    flow_from_steps,
    parse_flow,
    resolve_point,
    select_elements,
    selector_from_step,
)


def no(classe="android.widget.TextView", bounds="[0,0][10,10]", texto="", rid="", desc="",
       clicavel=False, filhos="", extra=""):
    return (f'<node class="{classe}" package="br.app" bounds="{bounds}" text="{texto}" '
            f'resource-id="{rid}" content-desc="{desc}" clickable="{str(clicavel).lower()}" {extra}>'
            f'{filhos}</node>')


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

    def test_mensagem_de_falha_nao_repete_o_valor_da_variavel(self):
        # MEL-4 (d): `selector.describe()` repete o texto procurado, e a
        # mensagem do resultado vai crua em `flow.finished`.
        r, linhas, _ = runner(self.aparelho_login())
        resultado = r.run(parse_flow("- assertVisible: ${SENHA}\n", env={"SENHA": "SEGREDO"}))
        self.assertFalse(resultado.success)
        self.assertIn("nao ficou visivel", resultado.message)
        self.assertNotIn("SEGREDO", resultado.message)
        self.assertNotIn("SEGREDO", resultado.failed_step or "")
        self.assertFalse(any("SEGREDO" in linha for linha in linhas))

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


class AparelhoQueContaLeituras(AparelhoFalso):
    """Conta as leituras da arvore. Com `espera_ocio`, faz como o `uiautomator dump`."""

    def __init__(self, *args, espera_ocio=False, **kwargs):
        super().__init__(*args, **kwargs)
        self.leituras = 0
        if espera_ocio:
            self.reads_wait_for_idle = True

    def hierarchy(self):
        self.leituras += 1
        return super().hierarchy()


class AparelhoRoteirizado(AparelhoQueContaLeituras):
    """Devolve as telas do roteiro, uma por leitura, e repete a ultima."""

    def __init__(self, roteiro):
        super().__init__({"x": roteiro[0]}, "x", espera_ocio=True)
        self.roteiro = list(roteiro)

    def hierarchy(self):
        self.leituras += 1
        return self.roteiro.pop(0) if len(self.roteiro) > 1 else self.roteiro[0]


class LeituraRapidaTest(unittest.TestCase):
    """AUT-1: menos leituras de ~2 s por comando, sem ler a tela velha."""

    FLOW = "- tapOn: Entrar\n- assertVisible: Bem-vindo.*\n- back\n- assertVisible: Bem-vindo.*\n"

    def aparelho(self, espera_ocio, atraso=0):
        return AparelhoQueContaLeituras(
            {"login": LOGIN, "home": HOME}, "login", {("login", 100, 400, 980, 560): ("home", atraso)},
            espera_ocio=espera_ocio,
        )

    def test_leitor_que_espera_ocio_faz_menos_leituras_e_o_flow_passa(self):
        rapido, comum = self.aparelho(espera_ocio=True), self.aparelho(espera_ocio=False)
        for aparelho in (rapido, comum):
            resultado = runner(aparelho)[0].run(parse_flow(self.FLOW))
            self.assertTrue(resultado.success, resultado.message)
        # tapOn: busca + 1 leitura de espera (pelo dump, a busca ja e tela parada
        # e nao pede leitura de confirmacao); assertVisible: a arvore assentada;
        # back: a tela nao muda (guarda), entao 2 leituras iguais; assertVisible: cache.
        self.assertEqual(rapido.leituras, 4)
        self.assertGreater(comum.leituras, rapido.leituras)

    def test_sem_a_capacidade_continua_exigindo_duas_leituras_iguais(self):
        aparelho = self.aparelho(espera_ocio=False, atraso=1)
        resultado = runner(aparelho)[0].run(parse_flow("- tapOn: Entrar\n"))
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.leituras, 5,
                         "busca, a mesma tela antes do toque, tela antiga, tela nova, tela nova de novo")

    def test_leitura_unica_igual_a_tela_de_antes_nao_conta_como_assentada(self):
        # O toque fora do botao nao muda a tela: pode ser a tela antiga ainda
        # esperando rede, entao a espera volta a pedir duas leituras iguais.
        aparelho = self.aparelho(espera_ocio=True)
        resultado = runner(aparelho)[0].run(parse_flow("- tapOn: Esqueci a senha\n"))
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.leituras, 3)

    def test_acao_sem_espera_descarta_a_arvore_guardada(self):
        # stopApp nao assenta a tela: o assert seguinte nao pode usar a arvore de antes.
        leituras = {}
        for nome, meio in (("sem", ""), ("com", "- stopApp\n")):
            aparelho = self.aparelho(espera_ocio=True)
            flow = parse_flow(f"appId: br.app\n---\n- back\n{meio}- assertVisible: Entrar\n")
            self.assertTrue(runner(aparelho)[0].run(flow).success)
            leituras[nome] = aparelho.leituras
        self.assertEqual(leituras, {"sem": 1, "com": 2}, "o assert depois do stopApp relê a tela")

    def test_assert_not_visible_nunca_usa_a_arvore_guardada(self):
        # A home leva 2 leituras para trocar a tela. A espera do toque so ve o
        # login, e a arvore guardada ainda mostra "Entrar": o assert negativo relê.
        aparelho = self.aparelho(espera_ocio=False, atraso=2)
        r, _, relogio = runner(aparelho)
        resultado = r.run(parse_flow("- tapOn: Entrar\n- assertNotVisible: Entrar\n"))
        self.assertTrue(resultado.success, resultado.message)
        # Usando a arvore guardada, o assert ficaria vendo "Entrar" ate ela vencer (2 s).
        self.assertLess(relogio.t, 1.0, "assertNotVisible esperou o cache vencer: usou a arvore guardada")

    def test_condicao_de_run_flow_nunca_usa_a_arvore_guardada(self):
        # A espera do toque guarda a home; sem nenhuma acao, a tela volta ao login.
        # O `when` decide pela tela de agora: "Bem-vindo" sumiu, o bloco e pulado.
        aparelho = AparelhoRoteirizado([LOGIN, HOME, LOGIN])
        flow = parse_flow("- tapOn: Entrar\n- runFlow:\n    when: {visible: Bem-vindo.*}\n"
                          "    commands: [{pressKey: Enter}]\n")
        resultado = runner(aparelho)[0].run(flow)
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.teclas, [], "o bloco rodou com a arvore guardada, que ja nao valia")

    def test_arvore_guardada_que_nao_casa_e_relida_antes_de_rolar(self):
        # A espera guardou a tela antes de a lista carregar; o item ja esta na
        # tela de agora. Decidir pelo cache faria rolar e tirar o item da tela.
        # A tela vazia faz o papel da lista ainda sem itens (sem indicador, que o
        # SYNC-4 esperaria sumir).
        aparelho = AparelhoRoteirizado([LOGIN, tela(), HOME])
        flow = parse_flow("- tapOn: Entrar\n- scrollUntilVisible:\n    element: Bem-vindo.*\n")
        resultado = runner(aparelho)[0].run(flow)
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.deslizes, 0)

    def test_varios_elementos_casando_viram_aviso_no_log(self):
        repetida = tela(no(bounds="[0,100][500,200]", texto="Item", clicavel=True),
                        no(bounds="[0,300][500,400]", texto="Item", clicavel=True))
        r, linhas, _ = runner(AparelhoFalso({"lista": repetida}, "lista"))
        self.assertTrue(r.run(parse_flow("- tapOn: Item\n")).success)
        self.assertTrue(any("2 elementos casam" in linha for linha in linhas), linhas)

    def test_assert_not_visible_sem_arvore_tenta_ate_o_prazo(self):
        aparelho = AparelhoRoteirizado([None, None, HOME])
        r, _, relogio = runner(aparelho)
        resultado = r.run(parse_flow("- assertNotVisible: Entrar\n"))
        self.assertTrue(resultado.success, resultado.message)
        self.assertGreater(relogio.t, 0, "esperou a arvore voltar em vez de falhar na primeira leitura")

    def test_launch_app_segue_com_duas_leituras_mesmo_com_dump(self):
        aparelho = self.aparelho(espera_ocio=True)
        self.assertTrue(runner(aparelho)[0].run(parse_flow("appId: br.app\n---\n- launchApp\n")).success)
        self.assertGreaterEqual(aparelho.leituras, 2, "partida a frio nao confia numa leitura so")

    def test_toda_acao_do_aparelho_descarta_a_arvore_guardada(self):
        # Um metodo novo de acao no FlowDevice que nao entre nesta lista nao
        # invalidaria o cache: o teste pega o esquecimento.
        acoes = {n for n, v in vars(FlowDevice).items() if callable(v) and not n.startswith("_")}
        self.assertEqual(acoes - {"hierarchy", "screen_size"}, set(_ACOES_NO_APARELHO))
        argumentos = {"tap": (1, 1), "type_text": ("a",), "press_key": ("Back",), "swipe": (1, 1, 2, 2, 100),
                      "launch_app": ("br.app",), "stop_app": ("br.app",), "clear_state": ("br.app",)}
        for nome, args in argumentos.items():
            with self.subTest(acao=nome):
                r = runner(self.aparelho(espera_ocio=True))[0]
                r._assentada = (LOGIN, 0.0)
                getattr(r.device, nome)(*args)
                self.assertIsNone(r._assentada)

    def test_aparelho_sem_arvore_falha_dizendo_isso(self):
        aparelho = self.aparelho(espera_ocio=True)
        aparelho.hierarchy = lambda: None
        r = runner(aparelho)[0]
        r.lookup_timeout_s = 1
        resultado = r.run(parse_flow("- tapOn: Entrar\n"))
        self.assertFalse(resultado.success)
        self.assertIn("nao devolveu a hierarquia", resultado.message)
        nega = runner(aparelho)[0].run(parse_flow("- assertNotVisible: Entrar\n"))
        self.assertFalse(nega.success, "sem arvore nao da para afirmar que algo sumiu")

    def test_adapter_android_diz_quando_a_leitura_esperou_o_ocio(self):
        class Adb:
            pass

        backend = {"valor": "adb"}
        aparelho = AndroidFlowDevice(Adb(), "emulator-5554", hierarchy=lambda: "<hierarchy/>",
                                     backend=lambda: backend["valor"])
        self.assertTrue(aparelho.reads_wait_for_idle)
        backend["valor"] = "appium"
        self.assertFalse(aparelho.reads_wait_for_idle)
        self.assertFalse(AndroidFlowDevice(Adb(), "emulator-5554", hierarchy=lambda: None).reads_wait_for_idle,
                         "leitor injetado sem backend: nao presume nada")
        self.assertTrue(AndroidFlowDevice(Adb(), "emulator-5554").reads_wait_for_idle, "o dump direto espera")


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


class PassosGravadosTest(unittest.TestCase):
    """AUT-2: `flow.run` reproduz os passos gravados pelo localizador."""

    CPF = "123.456.789-00"

    def test_passo_sem_localizador_estavel_toca_o_ponto_gravado_e_diz_isso(self):
        posicao = replace(passo(1, "(AppiumBy.XPATH, '//android.widget.EditText[@resource-id=\"x\"]')",
                                coords=(30, 40)), strategy=LocatorStrategy.POSITION)
        so_classe = passo(2, "(AppiumBy.XPATH, '//android.webkit.WebView')", coords=(50, 60))
        area_vazia = passo(3, "(AppiumBy.XPATH, '//android.view.View[@text=\"pos_900_1600\"]')",
                           coords=(900, 1600))
        for p_, ponto in ((posicao, "30,40"), (so_classe, "50,60"), (area_vazia, "900,1600")):
            with self.subTest(passo=p_.step_num):
                self.assertEqual(selector_from_step(p_), {"point": ponto})
        flow = flow_from_steps([posicao, so_classe, area_vazia])
        self.assertTrue(all("coordenada gravada" in s.describe() for s in flow.steps))
        aparelho = AparelhoFalso({"login": LOGIN}, "login")
        self.assertTrue(runner(aparelho)[0].run(flow).success)
        self.assertEqual(aparelho.toques, [(30, 40), (50, 60), (900, 1600)])

    def test_um_item_de_topo_por_passo_e_o_texto_so_em_memoria(self):
        passos = [
            passo(1, '(AppiumBy.ID, "br.app:id/campo_email")', acao="input"),
            passo(2, "(AppiumBy.XPATH, '//android.widget.TextView[@text=\"Entrar\"]')", nome="BOTAO_ENTRAR"),
        ]
        flow = flow_from_steps(passos)
        self.assertEqual(len(flow.steps), 2)
        self.assertNotIn("segredo", repr(flow), "o texto digitado nao aparece no repr")
        aparelho = AparelhoFalso({"login": LOGIN, "home": HOME}, "login",
                                 {("login", 100, 400, 980, 560): ("home", 0)})
        r, linhas, _ = runner(aparelho)
        resultado = r.run(flow)
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.digitado, ["segredo"])
        self.assertFalse([linha for linha in linhas if "segredo" in linha])

    def test_texto_digitado_escapado_num_seletor_seguinte_tambem_e_mascarado(self):
        # A gravacao le o campo depois da digitacao: o passo seguinte pode ter o
        # valor como localizador de texto, que vira regex escapada no seletor.
        digitar = replace(passo(1, '(AppiumBy.ID, "br.app:id/campo_email")', acao="input"), input_text=self.CPF)
        conferir = passo(2, f"(AppiumBy.XPATH, '//android.widget.TextView[@text=\"{self.CPF}\"]')",
                         nome="CONFIRMACAO")
        flow = flow_from_steps([digitar, conferir])
        r, linhas, _ = runner(self.aparelho_login_com_campo())
        r.lookup_timeout_s = 1
        resultado = r.run(flow)
        self.assertFalse(resultado.success)
        self.assertIn("passo 2", resultado.message, "a falha tem de ser a busca do seletor com o valor")
        self.assertIn("***", resultado.message)
        vazou = [x for x in [*linhas, resultado.message, resultado.failed_step or ""]
                 if "123" in x and "789" in x]
        self.assertEqual(vazou, [])
        yaml, _ = export_steps([digitar, conferir])
        self.assertNotIn("789", yaml, "o YAML exportado tambem nao carrega o valor digitado")

    def test_mascara_do_yaml_nao_mexe_na_coordenada(self):
        digitar = replace(passo(1, '(AppiumBy.ID, "br.app:id/campo")', acao="input"), input_text="100")
        ponto = replace(passo(2, "(AppiumBy.XPATH, '//*')", coords=(540, 1004)), input_text=None)
        yaml, _ = export_steps([digitar, ponto])
        self.assertIn('point: "540,1004"', yaml)

    def aparelho_login_com_campo(self):
        return AparelhoFalso({"login": LOGIN}, "login")

    def test_passo_de_digitacao_sem_texto_falha_no_passo(self):
        sem_texto = replace(passo(1, '(AppiumBy.ID, "br.app:id/campo_email")', acao="input"), input_text=None)
        aparelho = AparelhoFalso({"login": LOGIN}, "login")
        resultado = runner(aparelho)[0].run(flow_from_steps([sem_texto]))
        self.assertFalse(resultado.success)
        self.assertIn("sem texto", resultado.message)
        self.assertEqual(aparelho.digitado, [])


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



# ------------------------------------------------- sincronia com o aparelho
#
# A sequencia que o moto g55 mostrou no appium.log de 28/10/2026: depois do
# toque, a arvore passa por uma transicao (6693 B), fica parada numa tela
# intermediaria (11887 B, tres leituras iguais) e so entao chega a tela real
# (46010 B). As telas abaixo sao sinteticas, com o mesmo formato.

ANTERIOR = tela(
    no(bounds="[0,80][1080,200]", texto="Pedidos"),
    no("android.widget.Button", "[100,800][980,900]", rid="br.app:id/item_pedido", clicavel=True,
       filhos=no(bounds="[140,820][940,880]", texto="Pedido 123")),
)
TRANSICAO = tela()
INTERMEDIARIA = tela(no(bounds="[0,80][1080,200]", texto="Detalhe"))
INTERMEDIARIA_CARREGANDO = tela(no(bounds="[0,80][1080,200]", texto="Detalhe"),
                                no("android.widget.ProgressBar", "[500,1100][580,1180]"))


def detalhe(y=2000, habilitado=True):
    return tela(
        no(bounds="[0,80][1080,200]", texto="Detalhe"),
        no(bounds="[100,400][980,460]", texto="Total R$ 10"),
        no("android.widget.Button", f"[100,{y}][980,{y + 150}]", rid="br.app:id/btn_confirmar",
           clicavel=True, extra=f'enabled="{str(habilitado).lower()}"',
           filhos=no(bounds=f"[400,{y + 40}][680,{y + 110}]", texto="Confirmar")),
    )


REAL = detalhe()
ROTEIRO_G55 = [TRANSICAO, INTERMEDIARIA, INTERMEDIARIA, INTERMEDIARIA, REAL]


class AparelhoComCarregamento(AparelhoQueContaLeituras):
    """Comeca na lista; o toque no pedido serve o roteiro, uma tela por leitura.

    `tocado_em` guarda a tela que estava no aparelho em cada toque: e o que
    diz se a automacao agiu antes da hora.
    """

    def __init__(self, roteiro, espera_ocio=False):
        super().__init__({"anterior": ANTERIOR}, "anterior", espera_ocio=espera_ocio)
        self.roteiro_do_toque = list(roteiro)
        self.fila: list[str] = []
        self.na_tela = ANTERIOR
        self.tocado_em: list[str] = []
        self.digitado_em: list[str] = []

    def hierarchy(self):
        self.leituras += 1
        if self.fila:
            self.na_tela = self.fila.pop(0)
        return self.na_tela

    def tap(self, x, y):
        self.toques.append((x, y))
        self.tocado_em.append(self.na_tela)
        if self.na_tela is ANTERIOR and 100 <= x <= 980 and 800 <= y <= 900:
            self.fila = list(self.roteiro_do_toque)
        return True

    def type_text(self, text):
        self.digitado_em.append(self.na_tela)
        return super().type_text(text)


def gravado(n, estrategia, localizador, coords, classe="android.widget.TextView", nome="Confirmar",
            acao="click"):
    return AutomationStep(step_num=n, action_type=acao, var_name=f"PASSO_{n}", element_name=nome,
                          class_name=classe, strategy=estrategia, locator_value=localizador, coords=coords,
                          input_text="abc" if acao == "input" else None, package="br.app")


PASSOS_G55 = [
    gravado(1, LocatorStrategy.ID, "(AppiumBy.ID, 'br.app:id/item_pedido')", (540, 850), nome="Pedido 123"),
    gravado(2, LocatorStrategy.POSITION, "", (540, 2075)),
]


class SincroniaTest(unittest.TestCase):
    """SYNC-1 a SYNC-6: a automacao nao age antes de a tela do aparelho chegar."""

    def test_replay_do_g55_o_ponto_gravado_espera_a_tela_real(self):
        # SYNC-3: a tela intermediaria passa no "duas leituras iguais", mas sob o
        # ponto gravado nao ha o TextView da gravacao.
        for espera_ocio in (False, True):
            with self.subTest(dump=espera_ocio):
                aparelho = AparelhoComCarregamento(ROTEIRO_G55, espera_ocio=espera_ocio)
                r, _, _ = runner(aparelho)
                resultado = r.run(flow_from_steps(PASSOS_G55))
                self.assertTrue(resultado.success, resultado.message)
                self.assertEqual(aparelho.toques[-1], (540, 2075))
                self.assertIs(aparelho.tocado_em[-1], REAL, "tocou o ponto antes de a tela real chegar")
                self.assertNotIn(TRANSICAO, aparelho.tocado_em)
                self.assertNotIn(INTERMEDIARIA, aparelho.tocado_em)

    def test_ponto_que_nunca_confere_toca_no_prazo_com_aviso(self):
        aparelho = AparelhoComCarregamento([TRANSICAO, INTERMEDIARIA])
        r, linhas, relogio = runner(aparelho)
        resultado = r.run(flow_from_steps(PASSOS_G55))
        self.assertTrue(resultado.success, resultado.message)
        self.assertIs(aparelho.tocado_em[-1], INTERMEDIARIA)
        self.assertGreaterEqual(relogio.t, 16)
        self.assertTrue(any("tocando o ponto mesmo assim" in linha for linha in linhas), linhas)

    def test_toque_em_area_vazia_gravado_nao_confere_classe(self):
        # O elemento sintetico `pos_x_y` nao existe na arvore: nao ha classe a conferir.
        passos = [PASSOS_G55[0], gravado(2, LocatorStrategy.POSITION, "", (540, 2075),
                                         classe="android.view.View", nome="pos_540_2075")]
        flow = flow_from_steps(passos)
        self.assertIsNone(flow.steps[1].steps[0].expect_class)
        self.assertEqual(flow.steps[0].steps[0].expect_class, None, "passo por id nao confere classe")
        self.assertEqual(flow_from_steps(PASSOS_G55).steps[1].steps[0].expect_class, "android.widget.TextView")

    def test_indicador_de_carregamento_impede_o_assentado(self):
        # SYNC-4: a tela com ProgressBar fica parada, mas nao esta pronta. Pelo
        # dump, que espera 1 s de ocio, o quadro de transicao nao aparece; uma
        # leitura avulsa dele, sem indicador, seria aceita (so o SYNC-3 a pega).
        carregando = [INTERMEDIARIA_CARREGANDO] * 3 + [REAL]
        for espera_ocio, roteiro in ((False, [TRANSICAO, *carregando]), (True, carregando)):
            with self.subTest(dump=espera_ocio):
                aparelho = AparelhoComCarregamento(roteiro, espera_ocio=espera_ocio)
                r, linhas, _ = runner(aparelho)
                flow = parse_flow("- tapOn: {id: item_pedido}\n- tapOn: {point: '540,2075'}\n")
                resultado = r.run(flow)
                self.assertTrue(resultado.success, resultado.message)
                self.assertIs(aparelho.tocado_em[-1], REAL)
                self.assertTrue(any("indicador de carregamento" in linha for linha in linhas), linhas)

    def test_indicador_que_nunca_some_segue_no_limite_sem_falhar(self):
        aparelho = AparelhoComCarregamento([INTERMEDIARIA_CARREGANDO])
        r, linhas, relogio = runner(aparelho)
        resultado = r.run(parse_flow("- tapOn: {id: item_pedido}\n"))
        self.assertTrue(resultado.success, resultado.message)
        self.assertGreaterEqual(relogio.t, 5)
        self.assertLess(relogio.t, 8)
        self.assertTrue(any("seguiu sem prontidao" in linha for linha in linhas), linhas)

    def test_barra_de_progresso_horizontal_nao_conta(self):
        # Medido no emulador: a tela de bateria tem `ProgressBar` id `progress`
        # (o nivel da bateria) para sempre, e cada passo esperava 5 s a toa.
        bateria = tela(no(bounds="[0,80][1080,200]", texto="Battery"),
                       no("android.widget.ProgressBar", "[48,520][1032,560]", rid="android:id/progress"))
        aparelho = AparelhoComCarregamento([bateria])
        r, linhas, relogio = runner(aparelho)
        self.assertTrue(r.run(parse_flow("- tapOn: {id: item_pedido}\n")).success)
        self.assertLess(relogio.t, 2)
        self.assertFalse(any("carregamento" in linha for linha in linhas), linhas)

    def test_id_de_carregamento_conta_em_qualquer_formato(self):
        skeleton = tela(no(bounds="[0,300][1080,700]", rid="br.app:id/shimmer_lista"))
        aparelho = AparelhoComCarregamento([skeleton, skeleton, REAL])
        r, _, _ = runner(aparelho)
        self.assertTrue(r.run(parse_flow("- tapOn: {id: item_pedido}\n- tapOn: {point: '540,2075'}\n")).success)
        self.assertIs(aparelho.tocado_em[-1], REAL)

    def test_indicador_fora_da_tela_nao_conta(self):
        escondido = tela(no(bounds="[0,80][1080,200]", texto="Detalhe"),
                         no("android.widget.ProgressBar", "[500,2600][580,2680]"))
        aparelho = AparelhoComCarregamento([escondido])
        r, linhas, relogio = runner(aparelho)
        self.assertTrue(r.run(parse_flow("- tapOn: {id: item_pedido}\n")).success)
        self.assertLess(relogio.t, 2)
        self.assertFalse(any("carregamento" in linha for linha in linhas), linhas)

    def test_alvo_achado_deslizando_e_mirado_de_novo(self):
        # SYNC-2: o botao aparece primeiro mais abaixo e sobe ate o lugar.
        roteiro = [TRANSICAO, INTERMEDIARIA, INTERMEDIARIA, INTERMEDIARIA, detalhe(y=2300), REAL]
        aparelho = AparelhoComCarregamento(roteiro)
        r, linhas, _ = runner(aparelho)
        resultado = r.run(parse_flow("- tapOn: {id: item_pedido}\n- tapOn: Confirmar\n"))
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.toques[-1], (540, 2075), "tocou onde o botao estava, nao onde esta")
        self.assertTrue(any("mirei de novo" in linha for linha in linhas), linhas)

    def test_alvo_desabilitado_espera_habilitar(self):
        class Registra(AparelhoRoteirizado):
            def tap(self, x, y):
                self.leituras_no_toque = self.leituras
                return super().tap(x, y)

        aparelho = Registra([detalhe(habilitado=False), detalhe(habilitado=False),
                             detalhe(habilitado=False), REAL])
        r, linhas, _ = runner(aparelho)
        self.assertTrue(r.run(parse_flow("- tapOn: Confirmar\n")).success)
        self.assertEqual(aparelho.leituras_no_toque, 4, "tocou antes de o botao habilitar")
        self.assertFalse(any("desabilitado" in linha for linha in linhas), linhas)

    def test_alvo_que_nunca_habilita_e_tocado_com_aviso(self):
        aparelho = AparelhoRoteirizado([detalhe(habilitado=False)])
        r, linhas, relogio = runner(aparelho)
        self.assertTrue(r.run(parse_flow("- tapOn: Confirmar\n")).success)
        self.assertEqual(aparelho.toques, [(540, 2075)])
        self.assertGreaterEqual(relogio.t, 2)
        self.assertTrue(any("desabilitado" in linha for linha in linhas), linhas)

    def test_digitacao_espera_o_campo_com_foco(self):
        # SYNC-5.
        sem_foco = tela(no("android.widget.EditText", "[100,300][980,380]", rid="br.app:id/busca"))
        com_foco = tela(no("android.widget.EditText", "[100,300][980,380]", rid="br.app:id/busca",
                           texto="pizza", extra='focused="true"'))

        class Registra(AparelhoRoteirizado):
            def hierarchy(self):
                self.ultima = super().hierarchy()
                return self.ultima

            def type_text(self, text):
                self.digitado_em = self.ultima
                return super().type_text(text)

        aparelho = Registra([sem_foco, sem_foco, com_foco])
        r, linhas, _ = runner(aparelho)
        self.assertTrue(r.run(parse_flow("- inputText: pizza\n")).success)
        self.assertIs(aparelho.digitado_em, com_foco, "digitou antes de o campo ter foco")
        self.assertFalse(any("aviso" in linha for linha in linhas), linhas)

    def test_digitacao_sem_foco_avisa_e_digita(self):
        sem_foco = tela(no("android.widget.EditText", "[100,300][980,380]", rid="br.app:id/busca"))
        aparelho = AparelhoRoteirizado([sem_foco])
        r, linhas, _ = runner(aparelho)
        self.assertTrue(r.run(parse_flow("- inputText: pizza\n")).success)
        self.assertEqual(aparelho.digitado, ["pizza"])
        self.assertTrue(any("nenhum campo com foco" in linha for linha in linhas), linhas)

    def test_campo_que_nao_mostra_o_digitado_vira_aviso_sem_o_valor(self):
        vazio = tela(no("android.widget.EditText", "[100,300][980,380]", rid="br.app:id/busca",
                        extra='focused="true"'))
        senha = tela(no("android.widget.EditText", "[100,300][980,380]", rid="br.app:id/senha",
                        texto="••••••", extra='focused="true" password="true"'))
        for arvore, avisa in ((vazio, True), (senha, False)):
            with self.subTest(avisa=avisa):
                r, linhas, _ = runner(AparelhoRoteirizado([arvore]))
                resultado = r.run(parse_flow("- inputText: ${SENHA}\n", env={"SENHA": "segredo123"}))
                self.assertTrue(resultado.success, resultado.message)
                self.assertEqual(any("nao mostra o texto digitado" in linha for linha in linhas), avisa, linhas)
                self.assertFalse(any("segredo123" in linha for linha in linhas))

    def test_tela_que_nao_para_aparece_no_log(self):
        # SYNC-6: antes, o runner seguia calado depois de 10 tentativas.
        a, b = LOGIN, HOME

        class Piscando(AparelhoFalso):
            def __init__(self):
                super().__init__({"a": a}, "a")
                self.n = 0

            def hierarchy(self):
                self.n += 1
                return a if self.n % 2 else b

        r, linhas, _ = runner(Piscando())
        self.assertTrue(r.run(parse_flow("- back\n")).success)
        self.assertTrue(any("a tela nao parou" in linha for linha in linhas), linhas)

    def test_prazo_da_busca_conta_da_ultima_acao(self):
        # SYNC-6: como no Maestro, os 17 s valem desde o toque, nao depois da espera.
        aparelho = AparelhoComCarregamento([INTERMEDIARIA_CARREGANDO])
        r, _, relogio = runner(aparelho)
        resultado = r.run(parse_flow("- tapOn: {id: item_pedido}\n- tapOn: Nunca\n"))
        self.assertFalse(resultado.success)
        self.assertLess(relogio.t, 18, "somou a espera do indicador aos 17 s")

    def test_indicador_vencido_nao_cobra_a_espera_de_novo(self):
        # R-02: um ProgressBar que nunca some custa os 5 s uma vez, nao em cada passo.
        aparelho = AparelhoRoteirizado([INTERMEDIARIA_CARREGANDO])
        r, linhas, relogio = runner(aparelho)
        self.assertTrue(r.run(parse_flow("- back\n- back\n- back\n")).success)
        self.assertLess(relogio.t, 8)
        self.assertEqual(sum("seguiu sem prontidao" in linha for linha in linhas), 1, linhas)

    def test_prazo_declarado_vale_para_a_espera_inteira(self):
        # R-03: waitForAnimationToEnd de 2 s nao vira 5 s por causa do indicador.
        r, _, relogio = runner(AparelhoRoteirizado([INTERMEDIARIA_CARREGANDO]))
        self.assertTrue(r.run(parse_flow("- waitForAnimationToEnd:\n    timeout: 2000\n")).success)
        self.assertLess(relogio.t, 3)

    def test_retry_e_on_flow_complete_tem_o_prazo_inteiro(self):
        # R-01: o prazo conta da ultima acao, mas cada tentativa recomeca a conta.
        r, _, relogio = runner(AparelhoFalso({"login": LOGIN}, "login"))
        r.lookup_timeout_s = 5
        flow = parse_flow("- back\n- retry:\n    maxRetries: 2\n    commands:\n      - tapOn: Nunca\n")
        self.assertFalse(r.run(flow).success)
        self.assertGreaterEqual(relogio.t, 15, "as tentativas 2 e 3 nao tiveram prazo")
        r2, _, relogio2 = runner(AparelhoFalso({"login": LOGIN}, "login"))
        r2.lookup_timeout_s = 5
        r2.run(parse_flow("onFlowComplete:\n  - tapOn: Nunca\n---\n- back\n- tapOn: Nunca\n"))
        self.assertGreaterEqual(relogio2.t, 10, "a limpeza do onFlowComplete ficou sem prazo")

    def test_scroll_until_visible_tolera_leitura_vazia(self):
        # Medido no emulador: o dump sem ocio devolve nada, e a leitura unica do
        # scrollUntilVisible derrubava o flow ("nao devolveu a hierarquia em 0 s").
        aparelho = AparelhoRoteirizado([None, HOME])
        r, _, _ = runner(aparelho)
        resultado = r.run(parse_flow("- scrollUntilVisible:\n    element: Bem-vindo.*\n"))
        self.assertTrue(resultado.success, resultado.message)
        self.assertEqual(aparelho.deslizes, 0, "rolou sem ter visto a tela")

    def test_launch_app_espera_o_app_em_primeiro_plano(self):
        # SYNC-9: o monkey volta antes de a activity abrir; o launcher ainda na tela
        # passaria nas duas leituras iguais.
        aparelho = AparelhoFalso({"login": LOGIN}, "login")
        focos = iter([None, None, "com.android.launcher", "br.app"])
        aparelho.foreground_app = lambda: next(focos, "br.app")
        r, linhas, relogio = runner(aparelho)
        self.assertTrue(r.run(parse_flow("appId: br.app\n---\n- launchApp\n")).success)
        self.assertGreaterEqual(relogio.t, 0.9)
        self.assertTrue(any("o app abriu" in linha for linha in linhas), linhas)

    def test_launch_app_que_nao_chega_ao_primeiro_plano_segue_com_aviso(self):
        aparelho = AparelhoFalso({"login": LOGIN}, "login")
        aparelho.foreground_app = lambda: "com.outro.app"
        r, linhas, relogio = runner(aparelho)
        self.assertTrue(r.run(parse_flow("appId: br.app\n---\n- launchApp\n")).success)
        self.assertGreaterEqual(relogio.t, 10)
        self.assertTrue(any("nao ficou em primeiro plano" in linha for linha in linhas), linhas)

    def test_flow_gravado_pode_comecar_abrindo_o_app(self):
        flow = flow_from_steps(PASSOS_G55, abrir_app=True)
        self.assertEqual([(s.command, s.app_id) for s in flow.on_start], [("launchApp", "br.app")])
        self.assertEqual(len(flow.steps), len(PASSOS_G55), "abrir o app nao vira passo gravado")
        self.assertEqual(flow_from_steps(PASSOS_G55).on_start, ())
        sem_pacote = [replace(p, package="") for p in PASSOS_G55]
        with self.assertRaisesRegex(InvalidInputError, "pacote"):
            flow_from_steps(sem_pacote, abrir_app=True)

    def test_log_de_sincronia_por_passo_e_rastro_das_telas(self):
        # SYNC-1: cada passo diz quanto esperou; o rastro guarda cada tela diferente.
        aparelho = AparelhoComCarregamento(ROTEIRO_G55)
        r, linhas, _ = runner(aparelho)
        self.assertTrue(r.run(flow_from_steps(PASSOS_G55)).success)
        self.assertEqual(sum(linha.startswith("  sincronia:") for linha in linhas), 2, linhas)
        self.assertEqual([xml for _t, xml in r.rastro], [ANTERIOR, TRANSICAO, INTERMEDIARIA, REAL])

    def test_rastro_gravado_so_local_com_mascara_e_limite(self):
        from mobaile.services.maestro_flow import salvar_rastro

        with tempfile.TemporaryDirectory() as d:
            base = Path(d)
            rastro = [(0.0, ANTERIOR), (0.4, tela(no(texto="ana@exemplo.com")))]
            for _ in range(7):
                pasta = salvar_rastro(rastro, base, lambda t: t.replace("ana@exemplo.com", "***"))
            self.assertEqual(len([p for p in base.iterdir() if p.is_dir()]), 5, "guarda so os 5 ultimos")
            arquivos = sorted(pasta.glob("*.xml"))
            self.assertEqual(len(arquivos), 2)
            self.assertNotIn("ana@exemplo.com", arquivos[1].read_text(encoding="utf-8"))
            self.assertEqual(arquivos[0].stat().st_mode & 0o777, 0o600)
            self.assertIn("B", (pasta / "resumo.txt").read_text(encoding="utf-8"))

    def test_rastro_recusa_pasta_que_e_symlink(self):
        from mobaile.services.maestro_flow import salvar_rastro

        with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as alvo:
            link = Path(d) / "flow-rastro"
            link.symlink_to(alvo)
            with self.assertRaises(OSError):
                salvar_rastro([(0.0, ANTERIOR)], link)
            self.assertEqual(list(Path(alvo).iterdir()), [])

    def test_rastro_guarda_as_ultimas_telas(self):
        from mobaile.services import maestro_flow

        telas = [tela(no(texto=f"tela {n}")) for n in range(maestro_flow.TRACE_MAX_SCREENS + 5)]
        r, _, _ = runner(AparelhoRoteirizado(telas))
        r.lookup_timeout_s = 30
        r.run(parse_flow("- tapOn: Nunca\n"))
        self.assertEqual(len(r.rastro), maestro_flow.TRACE_MAX_SCREENS)
        self.assertEqual(r.rastro[-1][1], telas[-1], "o rastro ficou com as primeiras telas")

    def test_flow_thread_grava_o_rastro_mascarado_conforme_o_modo(self):
        import os
        from dataclasses import replace as substituir
        from unittest import mock

        from mobaile.services import maestro_flow

        segredo = 'a&b"c<d'
        com_segredo = tela(no(texto=segredo.replace("&", "&amp;").replace('"', "&quot;").replace("<", "&lt;")))
        casos = (("falha", "- assertVisible: Nunca\n", True), ("falha", "- back\n", False),
                 ("nunca", "- assertVisible: Nunca\n", False), ("sempre", "- back\n", True))
        for modo, yaml, grava in casos:
            with self.subTest(modo=modo, yaml=yaml), tempfile.TemporaryDirectory() as d, \
                    mock.patch.dict(os.environ, {"MOBAILE_LOG_DIR": d}), \
                    mock.patch.object(maestro_flow, "settings",
                                      substituir(maestro_flow.settings, flow_trace=modo)):
                saidas: list[str] = []
                flow = parse_flow("- inputText: ${X}\n" + yaml, env={"X": segredo})
                execucao = maestro_flow.FlowThread(flow, AparelhoFalso({"t": com_segredo}, "t"),
                                                   saidas.append, lambda *_: None)
                relogio = Relogio()
                execucao.runner._clock, execucao.runner._sleep = relogio, relogio.dormir
                execucao.run()
                pastas = list((Path(d) / "flow-rastro").glob("*/")) if (Path(d) / "flow-rastro").exists() else []
                self.assertEqual(bool(pastas), grava, saidas)
                for arquivo in (pastas[0].glob("*.xml") if pastas else []):
                    conteudo = arquivo.read_text(encoding="utf-8")
                    self.assertNotIn("a&amp;b&quot;c&lt;d", conteudo)
                    self.assertIn("***", conteudo)


if __name__ == "__main__":
    unittest.main()
