"""M7 / A1: o seletor escolhido como "unico" tem de ser unico de verdade.

O ranking contava `matches` pelo texto, mas o xpath emitido priorizava o
`resource-id`: com tres botoes de mesmo id e textos diferentes, o passo gravado
casava com os tres. E o teste que cobria isso so olhava `unique`, nunca o valor.
"""

from __future__ import annotations

import io
import unittest

from mobaile.domain.models import Platform
from mobaile.rpc.server import EngineServer
from mobaile.services.codegen import CodeGenerator
from mobaile.services.hierarchy import UIElement


def botao(texto, rid="br.app:id/item", classe="android.widget.Button", x0=0):
    return UIElement(
        tag=classe, class_name=classe, resource_id=rid, text=texto, content_desc="",
        clickable=True, bounds=(x0, 0, x0 + 100, 100), area=10000, package="br.app", platform="android",
    )


XML_TRES_BOTOES = """<hierarchy rotation="0">
<node index="0" text="Primeiro" resource-id="br.app:id/item" class="android.widget.Button" package="br.app" content-desc="" clickable="true" bounds="[0,0][100,100]" />
<node index="1" text="Segundo" resource-id="br.app:id/item" class="android.widget.Button" package="br.app" content-desc="" clickable="true" bounds="[100,0][200,100]" />
<node index="2" text="Terceiro" resource-id="br.app:id/item" class="android.widget.Button" package="br.app" content-desc="" clickable="true" bounds="[200,0][300,100]" />
</hierarchy>"""

XML_BOTAO_CAMPO = """<hierarchy rotation="0">
<node index="0" text="Preencher campo" resource-id="" class="android.widget.Button" package="br.app" content-desc="" clickable="true" bounds="[0,0][100,100]" />
</hierarchy>"""


class TestRankingHonesto(unittest.TestCase):
    def test_candidato_por_texto_emite_xpath_de_texto(self):
        alvo = botao("Primeiro")
        tela = [alvo, botao("Segundo", x0=100), botao("Terceiro", x0=200)]
        candidatos = {c["strategy"]: c for c in CodeGenerator().rank_locators(alvo, tela)}
        self.assertIn("@text=", candidatos["text"]["value"])
        self.assertNotIn("resource-id", candidatos["text"]["value"])
        self.assertEqual(candidatos["text"]["matches"], 1)

    def test_xpath_por_id_repetido_nao_se_diz_unico(self):
        alvo = botao("Primeiro")
        tela = [alvo, botao("Segundo", x0=100), botao("Terceiro", x0=200)]
        candidatos = {c["strategy"]: c for c in CodeGenerator().rank_locators(alvo, tela)}
        self.assertEqual(candidatos["xpath"]["matches"], 3)
        self.assertFalse(candidatos["xpath"]["unique"])

    def test_dois_elementos_sem_atributo_nenhum_nao_sao_unicos_por_xpath(self):
        sem = lambda x0: UIElement(  # noqa: E731
            tag="android.view.View", class_name="android.view.View", resource_id="", text="", content_desc="",
            clickable=True, bounds=(x0, 0, x0 + 50, 50), area=2500, package="br.app", platform="android",
        )
        alvo = sem(0)
        candidatos = {c["strategy"]: c for c in CodeGenerator().rank_locators(alvo, [alvo, sem(60)])}
        self.assertEqual(candidatos["xpath"]["matches"], 2)

    def test_xpath_de_texto_no_ios_aceita_label_alem_de_value(self):
        """O `text` do elemento iOS pode vir do label; `@value` sozinho nao achava."""
        alvo = UIElement(
            tag="XCUIElementTypeButton", class_name="XCUIElementTypeButton", resource_id="Entrar",
            text="Entrar", content_desc="Entrar", clickable=True, bounds=(0, 0, 100, 50),
            area=5000, package="", platform="ios",
        )
        filho = UIElement(
            tag="XCUIElementTypeStaticText", class_name="XCUIElementTypeStaticText", resource_id="Entrar",
            text="Entrar", content_desc="Entrar", clickable=False, bounds=(0, 0, 80, 20),
            area=1600, package="", platform="ios",
        )
        candidatos = {c["strategy"]: c for c in CodeGenerator().rank_locators(alvo, [alvo, filho])}
        valor = candidatos["text"]["value"]
        self.assertIn("@label=", valor)
        self.assertIn("@value=", valor)

    def test_no_ios_a_contagem_segue_o_mesmo_criterio_do_xpath(self):
        """A-2: botao com label "Adicionar" e value "1" tem `text` "1", mas o
        xpath `@value or @label` o casa. A contagem precisa casar tambem."""
        def botao_ios(value, label):
            return UIElement(
                tag="XCUIElementTypeButton", class_name="XCUIElementTypeButton", resource_id=label,
                text=value or label, content_desc=label, clickable=True, bounds=(0, 0, 100, 50),
                area=5000, package="", platform="ios",
            )
        alvo, outro = botao_ios("", "Adicionar"), botao_ios("1", "Adicionar")
        candidatos = {c["strategy"]: c for c in CodeGenerator().rank_locators(alvo, [alvo, outro])}
        self.assertEqual(candidatos["text"]["matches"], 2)
        self.assertFalse(candidatos["text"]["unique"])


class TestPassoGravadoUsaOLocalizadorEscolhido(unittest.TestCase):
    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)
        self.server.platform = Platform.ANDROID

    def _grava(self, xml, x, y):
        with self.server._state_lock:
            self.server.current_xml = xml
        return self.server.codegen_record({"x": x, "y": y, "strategy": "auto"})

    def test_objeto_gerado_e_o_candidato_unico_e_nao_o_id_repetido(self):
        resultado = self._grava(XML_TRES_BOTOES, 50, 50)
        self.assertIn("@text=", resultado["object_code"])
        self.assertNotIn("resource-id", resultado["object_code"])
        passo = self.server.codegen.get_steps()[-1]
        self.assertIn("@text=", passo.locator_value)

    def test_botao_com_campo_no_rotulo_continua_sendo_clique(self):
        self._grava(XML_BOTAO_CAMPO, 50, 50)
        self.assertEqual(self.server.codegen.get_steps()[-1].action_type, "click")


class TestCamposQueNaoSaoEditText(unittest.TestCase):
    """A-1: a classificacao por prefixo deixou de fora campos cujo nome de
    classe nao diz "EditText" nem "input"."""

    def _passo(self, classe, rid):
        gerador = CodeGenerator()
        gerador.generate_entry(botao("", rid=rid, classe=classe))
        return gerador.get_steps()[-1]

    def test_autocomplete_text_view_e_campo(self):
        passo = self._passo("android.widget.AutoCompleteTextView", "br.app:id/campo_nome")
        self.assertEqual(passo.action_type, "input")
        self.assertTrue(passo.var_name.startswith("CAMPO_"), passo.var_name)

    def test_multi_autocomplete_text_view_e_campo(self):
        self.assertEqual(self._passo("android.widget.MultiAutoCompleteTextView", "br.app:id/tags").action_type, "input")

    def test_componente_custom_com_campo_no_id_e_campo(self):
        self.assertEqual(self._passo("android.view.View", "br.app:id/campo_data").action_type, "input")

    def test_texto_com_campo_no_rotulo_continua_clique(self):
        gerador = CodeGenerator()
        gerador.generate_entry(botao("Campo obrigatório", rid="", classe="android.widget.TextView"))
        self.assertEqual(gerador.get_steps()[-1].action_type, "click")


if __name__ == "__main__":
    unittest.main()
