"""Literais do codigo gerado (SEC-2).

Texto, resource-id e content-desc vem da tela do app testado, que nao e
confiavel. Eles precisam entrar no Page Object so como string: nunca como
codigo. A primeira classe trava a saida de hoje para os casos comuns
(caracterizacao, expectativas fixadas da execucao original), para a correcao
nao mudar nada do que ja funciona.
"""

from __future__ import annotations

import ast
import unittest

from mobaile.domain.models import UIElement
from mobaile.services.codegen import CodeGenerator, LocatorStrategy

PAYLOAD = "x'), __import__('os').system('echo PWN'), ('"


def elemento(**campos) -> UIElement:
    base = {
        "tag": "android.widget.Button", "class_name": "android.widget.Button",
        "resource_id": "", "text": "", "content_desc": "", "clickable": True,
        "bounds": (0, 0, 10, 10), "area": 100, "package": "br.app", "platform": "android",
    }
    base.update(campos)
    return UIElement(**base)


def ios(**campos) -> UIElement:
    campos.setdefault("tag", "XCUIElementTypeButton")
    campos.setdefault("class_name", campos["tag"])
    return elemento(platform="ios", **campos)


class TestCaracterizacaoSaidaComum(unittest.TestCase):
    """Comportamento atual, fixado antes da correcao."""

    def setUp(self):
        self.gerador = CodeGenerator(page_objects_key="onboarding_objs")

    def test_android_id(self):
        e = elemento(resource_id="br.app:id/btn_ok", text="Continuar", content_desc="Botao continuar")
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.ID),
                         '(AppiumBy.ID, "br.app:id/btn_ok")')
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.POSITION),
                         "(AppiumBy.XPATH, '//android.widget.Button[@resource-id=\"br.app:id/btn_ok\"]')")
        valores = [c["value"] for c in self.gerador.rank_locators(e, [e])]
        self.assertEqual(valores[1], '(AppiumBy.ACCESSIBILITY_ID, "Botao continuar")')

    def test_android_texto_e_rotulo(self):
        e = elemento(text="Entrar agora")
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.ID),
                         "(AppiumBy.XPATH, '//android.widget.Button[@text=\"Entrar agora\"]')")
        e = elemento(content_desc="Fechar")
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.ID),
                         '(AppiumBy.ACCESSIBILITY_ID, "Fechar")')
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.POSITION),
                         "(AppiumBy.XPATH, '//android.widget.Button[@content-desc=\"Fechar\"]')")

    def test_android_sem_atributo(self):
        self.assertEqual(self.gerador.generate_locator_value(elemento(), LocatorStrategy.ID),
                         "(AppiumBy.XPATH, '//android.widget.Button')")

    def test_ios(self):
        e = ios(resource_id="Aceito os Termos e Condições.", text="Aceito", content_desc="Aceito rot")
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.ID),
                         '(AppiumBy.ACCESSIBILITY_ID, "Aceito os Termos e Condições.")')
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.POSITION),
                         "(AppiumBy.XPATH, '//XCUIElementTypeButton[@name=\"Aceito os Termos e Condições.\"]')")
        e = ios(tag="XCUIElementTypeStaticText", content_desc="Saldo")
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.POSITION),
                         "(AppiumBy.XPATH, '//XCUIElementTypeStaticText[@label=\"Saldo\"]')")
        e = ios(tag="XCUIElementTypeTextField", text="CPF")
        self.assertEqual(self.gerador.generate_locator_value(e, LocatorStrategy.POSITION),
                         "(AppiumBy.XPATH, '//XCUIElementTypeTextField[@value=\"CPF\"]')")

    def test_entrada_completa(self):
        e = elemento(resource_id="br.app:id/btn_ok", text="Continuar")
        nome, linha, bloco = self.gerador.generate_entry(e, LocatorStrategy.ID)
        self.assertEqual(nome, "BOTAO_CONTINUAR")
        self.assertEqual(linha, '    BOTAO_CONTINUAR = (AppiumBy.ID, "br.app:id/btn_ok")')
        self.assertEqual(
            bloco,
            "    def click_continuar(self):\n"
            "        self.wait_to_be_visible(self.locators['onboarding_objs'].BOTAO_CONTINUAR, 15)\n"
            "        self.click(self.locators['onboarding_objs'].BOTAO_CONTINUAR, 2)\n",
        )


VALORES_HOSTIS = [
    PAYLOAD,
    'aspas "duplas"',
    "aspas 'simples'",
    "as duas ' e \"",
    "barra \\ invertida",
    "barra no fim \\",
    "cerquilha # resto",
    "quebra\nde linha",
    "retorno\rcarro",
    '") ; import os #',
]


class TestValorDaTelaSoComoString(unittest.TestCase):
    """O valor da tela vira um unico literal, e nada mais."""

    def _assert_so_string(self, codigo: str, valor: str) -> None:
        arvore = ast.parse(codigo)
        chamadas = [n for n in ast.walk(arvore) if isinstance(n, ast.Call)]
        self.assertEqual(chamadas, [], f"codigo gerado tem chamada: {codigo!r}")
        nomes = {n.id for n in ast.walk(arvore) if isinstance(n, ast.Name)}
        self.assertLessEqual(nomes, {"AppiumBy"}, codigo)
        literais = [n.value for n in ast.walk(arvore) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
        self.assertTrue(any(valor in s for s in literais), f"{valor!r} nao esta num literal de {codigo!r}")

    def _todos_os_localizadores(self, e: UIElement) -> list[str]:
        gerador = CodeGenerator(page_objects_key="objs")
        valores = [gerador.generate_locator_value(e, s) for s in LocatorStrategy]
        valores += [c["value"] for c in gerador.rank_locators(e, [e])]
        return valores

    def test_android_cada_campo(self):
        for valor in VALORES_HOSTIS:
            for campo in ("text", "resource_id", "content_desc"):
                with self.subTest(campo=campo, valor=valor):
                    for codigo in self._todos_os_localizadores(elemento(**{campo: valor})):
                        self._assert_so_string(codigo, valor)

    def test_ios_cada_campo(self):
        for valor in VALORES_HOSTIS:
            for campo in ("text", "resource_id", "content_desc"):
                with self.subTest(campo=campo, valor=valor):
                    for codigo in self._todos_os_localizadores(ios(**{campo: valor})):
                        self._assert_so_string(codigo, valor)

    def test_classe_hostil_nao_vaza_para_o_codigo(self):
        e = elemento(class_name=PAYLOAD, tag=PAYLOAD, text="ok")
        for codigo in self._todos_os_localizadores(e):
            arvore = ast.parse(codigo)
            self.assertEqual([n for n in ast.walk(arvore) if isinstance(n, ast.Call)], [], codigo)

    def test_xpath_com_as_duas_aspas_continua_xpath_valido(self):
        e = elemento(text="as duas ' e \"")
        codigo = CodeGenerator().generate_locator_value(e, LocatorStrategy.POSITION)
        xpath = ast.parse(codigo).body[0].value.elts[1].value
        self.assertEqual(xpath, "//android.widget.Button[@text=concat(\"as duas ' e \", '\"')]")

    def test_entrada_inteira_compila_e_nao_chama_nada_da_tela(self):
        for valor in VALORES_HOSTIS:
            for campo in ("text", "resource_id", "content_desc"):
                with self.subTest(campo=campo, valor=valor):
                    gerador = CodeGenerator(page_objects_key="objs")
                    nome, linha, bloco = gerador.generate_entry(elemento(**{campo: valor}), LocatorStrategy.ID)
                    self.assertTrue(nome.isidentifier(), nome)
                    fonte = f"class Locators:\n{linha}\n\nclass Pagina:\n{bloco}"
                    arvore = ast.parse(fonte)
                    chamadas = {ast.unparse(n.func) for n in ast.walk(arvore) if isinstance(n, ast.Call)}
                    self.assertLessEqual(chamadas, {"self.wait_to_be_visible", "self.click", "self.send_keys"})

    def test_nome_de_metodo_e_variavel_sao_identificadores(self):
        for texto in ("², ³ e ½", "١٢٣ árabe", "日本語 ボタン", "emoji 😀 fim", "-- ** --"):
            with self.subTest(texto=texto):
                nome, _linha, bloco = CodeGenerator().generate_entry(elemento(text=texto), LocatorStrategy.ID)
                self.assertTrue(nome.isidentifier(), nome)
                metodo = bloco.split("def ", 1)[1].split("(", 1)[0]
                self.assertTrue(metodo.isidentifier(), metodo)

    def test_chave_do_page_object_entra_como_string(self):
        gerador = CodeGenerator(page_objects_key=PAYLOAD)
        _nome, _linha, bloco = gerador.generate_entry(elemento(text="ok"), LocatorStrategy.ID)
        arvore = ast.parse(f"class P:\n{bloco}")
        chamadas = {ast.unparse(n.func) for n in ast.walk(arvore) if isinstance(n, ast.Call)}
        self.assertLessEqual(chamadas, {"self.wait_to_be_visible", "self.click", "self.send_keys"})


if __name__ == "__main__":
    unittest.main()
