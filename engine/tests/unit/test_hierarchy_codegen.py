import unittest

from mobaile.services.codegen import CodeGenerator, LocatorStrategy
from mobaile.services.hierarchy import UIElement


class TestCodeGenerator(unittest.TestCase):
    def setUp(self):
        self.generator = CodeGenerator(page_objects_key="onboarding_credito_objs")
        self.element_ios = UIElement(
            tag="XCUIElementTypeButton",
            class_name="XCUIElementTypeButton",
            resource_id="Li e aceito os Termos e Condições.",
            text="Li e aceito os Termos e Condições.",
            content_desc="Li e aceito os Termos e Condições.",
            clickable=True,
            bounds=(50, 500, 350, 550),
            area=15000,
            package="",
            platform="ios",
        )

    def test_generate_position_strategy(self):
        var_name, obj_line, act_block = self.generator.generate_entry(
            self.element_ios,
            strategy=LocatorStrategy.POSITION,
            click_coord=(390, 594),
        )

        self.assertIn("CHECK_BOX_BOTAO_LI_E_ACEITO_OS", var_name)
        self.assertIn("AppiumBy.XPATH", obj_line)
        self.assertIn("//XCUIElementTypeButton[@name=\"Li e aceito os Termos e Condições.\"]", obj_line)
        self.assertIn("def click_li_e_aceito_os_termos_e(self):", act_block)
        self.assertIn("self.click_at_position(self.locators['onboarding_credito_objs'].CHECK_BOX_BOTAO_", act_block)
        self.assertIn("390, 594)", act_block)

    def test_generate_id_strategy(self):
        _var_name, obj_line, act_block = self.generator.generate_entry(
            self.element_ios,
            strategy=LocatorStrategy.ID,
        )

        self.assertIn("AppiumBy.ACCESSIBILITY_ID", obj_line)
        self.assertIn("self.click(self.locators['onboarding_credito_objs'].CHECK_BOX_BOTAO_", act_block)


if __name__ == "__main__":
    unittest.main()


class TestEscolhaAutomaticaDeLocalizador(unittest.TestCase):
    """Seletor escolhido por robustez e conferido contra a tela inteira.

    Antes, a estrategia era uma so para a sessao inteira e escolhida na mao. O
    efeito e codigo instavel: o mesmo `resource-id` pode aparecer varias vezes
    na tela, e o passo passa a depender de qual delas o Appium ache primeiro.
    Medido num aparelho real, um id da tela inicial casava com 15 elementos.

    A hierarquia inteira ja esta carregada quando se grava, entao da para
    conferir a unicidade em vez de torcer.
    """

    def elemento(self, **campos):
        base = {
            "tag": "android.widget.Button", "class_name": "android.widget.Button",
            "resource_id": "", "text": "", "content_desc": "", "clickable": True,
            "bounds": (0, 0, 10, 10), "area": 100, "package": "br.app", "platform": "android",
        }
        base.update(campos)
        return UIElement(**base)

    def test_id_unico_vence(self):
        gerador = CodeGenerator()
        alvo = self.elemento(resource_id="br.app:id/ok", text="Continuar")
        tela = [alvo, self.elemento(resource_id="br.app:id/outro")]
        self.assertEqual(gerador.choose_locator(alvo, tela)["strategy"], "id")

    def test_id_repetido_perde_para_alternativa_unica(self):
        """O caso que motivou tudo: id que casa com varios elementos gera passo
        que depende da ordem de busca do Appium."""
        gerador = CodeGenerator()
        alvo = self.elemento(resource_id="br.app:id/item", text="Primeiro")
        tela = [alvo] + [self.elemento(resource_id="br.app:id/item") for _ in range(14)]
        escolhido = gerador.choose_locator(alvo, tela)
        self.assertNotEqual(escolhido["strategy"], "id")
        self.assertTrue(escolhido["unique"])

    def test_ambiguo_e_marcado_e_vai_para_o_fim(self):
        gerador = CodeGenerator()
        alvo = self.elemento(resource_id="br.app:id/item")
        tela = [alvo, self.elemento(resource_id="br.app:id/item")]
        ordenados = gerador.rank_locators(alvo, tela)
        porId = next(c for c in ordenados if c["strategy"] == "id")
        self.assertFalse(porId["unique"])
        self.assertEqual(porId["matches"], 2)
        self.assertEqual(ordenados[-1]["strategy"], "id", "ambiguo tem de ir para o fim")

    def test_todo_candidato_explica_o_porque(self):
        """A tela mostra o motivo da escolha; sem isso o usuario nao tem como
        discordar com fundamento."""
        gerador = CodeGenerator()
        alvo = self.elemento(resource_id="br.app:id/ok", content_desc="Confirmar", text="OK")
        for candidato in gerador.rank_locators(alvo, [alvo]):
            self.assertTrue(candidato["why"], f"{candidato['strategy']} sem explicacao")

    def test_elemento_sem_atributo_nenhum_ainda_tem_saida(self):
        """Canvas e componente desenhado a mao nao tem id nem texto; sobra
        caminho na arvore e coordenada."""
        gerador = CodeGenerator()
        alvo = self.elemento()
        estrategias = [c["strategy"] for c in gerador.rank_locators(alvo, [alvo])]
        self.assertIn("xpath", estrategias)
        self.assertIn("position", estrategias)


class TestTextoDigitadoNoPasso(unittest.TestCase):
    """O texto realmente escrito fica no passo, nao no Page Object.

    O metodo gerado continua recebendo `texto` como parametro, porque o Page
    Object precisa servir para qualquer valor. Quem repete a execucao e o passo,
    e e nele que o valor observado tem de ficar.
    """

    def gerador_com_campo(self):
        gerador = CodeGenerator()
        campo = UIElement(
            tag="android.widget.EditText", class_name="android.widget.EditText",
            resource_id="br.app:id/campo_cpf", text="", content_desc="", clickable=True,
            bounds=(0, 0, 100, 40), area=4000, package="br.app", platform="android",
        )
        gerador.generate_entry(campo, strategy=LocatorStrategy.ID)
        return gerador

    def test_guarda_o_texto_no_ultimo_passo_de_entrada(self):
        gerador = self.gerador_com_campo()
        self.assertTrue(gerador.set_last_input_text("12345678900"))
        self.assertEqual(gerador.get_steps()[-1].input_text, "12345678900")

    def test_sem_passo_de_entrada_nao_inventa(self):
        gerador = CodeGenerator()
        botao = UIElement(
            tag="android.widget.Button", class_name="android.widget.Button",
            resource_id="br.app:id/ok", text="Continuar", content_desc="", clickable=True,
            bounds=(0, 0, 100, 40), area=4000, package="br.app", platform="android",
        )
        gerador.generate_entry(botao, strategy=LocatorStrategy.ID)
        self.assertFalse(gerador.set_last_input_text("nao deve entrar"))
