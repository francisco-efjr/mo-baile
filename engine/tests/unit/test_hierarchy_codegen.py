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
