"""Geração de Page Objects e ações Appium a partir dos elementos inspecionados.

`LocatorStrategy` e `AutomationStep` vivem no domínio — este módulo só sabe
transformá-los em código. Ficam reexportados para compatibilidade dos imports
existentes.
"""

from __future__ import annotations

import re
import unicodedata

from mobaile.config import settings
from mobaile.domain.models import AutomationStep, LocatorStrategy, UIElement

__all__ = ["AutomationStep", "CodeGenerator", "LocatorStrategy", "UIElement"]


class CodeGenerator:
    def __init__(
        self,
        page_objects_key: str | None = None,
        strategy: LocatorStrategy = LocatorStrategy.POSITION,
    ):
        self.page_objects_key = page_objects_key or settings.page_objects_key
        self.strategy = strategy
        self.declared_objects: dict[str, str] = {}
        self.declared_actions: dict[str, str] = {}
        self.steps: list[AutomationStep] = []

    def reset(self):
        self.declared_objects.clear()
        self.declared_actions.clear()
        self.steps.clear()

    def set_last_input_text(self, texto: str) -> bool:
        """Guarda no ultimo passo de digitacao o texto que foi realmente escrito.

        O metodo gerado continua recebendo `texto` como parametro, porque o Page
        Object precisa ser reutilizavel. O valor observado fica no passo, que e
        o que a execucao repete.
        """
        for passo in reversed(self.steps):
            if passo.action_type == "input":
                passo.input_text = texto
                return True
        return False

    def get_steps(self) -> list[AutomationStep]:
        return list(self.steps)

    def clear_steps(self):
        self.steps.clear()

    @staticmethod
    def _sanitize_string(text: str) -> str:
        nfkd = unicodedata.normalize("NFKD", text)
        clean = "".join([c for c in nfkd if not unicodedata.combining(c)])
        stripped = re.sub(r"[^\w\s]", " ", clean)
        words = stripped.strip().split()[:7]
        return "_".join(words).upper()

    @staticmethod
    def _sanitize_slug(text: str) -> str:
        nfkd = unicodedata.normalize("NFKD", text)
        clean = "".join([c for c in nfkd if not unicodedata.combining(c)])
        stripped = re.sub(r"[^\w\s]", " ", clean)
        words = stripped.strip().split()[:6]
        return "_".join(words).lower()

    @staticmethod
    def _get_prefix(class_name: str, text: str) -> str:
        combined = f"{class_name} {text}".lower()

        if any(w in combined for w in ("checkbox", "check", "termos")):
            if any(w in combined for w in ("button", "botao", "termos")):
                return "CHECK_BOX_BOTAO"
            return "CHECK_BOX"
        if any(w in combined for w in ("button", "btn")):
            return "BOTAO"
        if any(w in combined for w in ("search", "edittext", "input", "textfield")):
            return "CAMPO"
        if any(w in combined for w in ("switch", "toggle")):
            return "SWITCH"
        if any(w in combined for w in ("image", "icon")):
            return "IMAGEM"
        if any(w in combined for w in ("textview", "statictext", "label")):
            return "TEXTO"
        if "cell" in combined:
            return "CELULA"
        if "radio" in combined:
            return "RADIO"
        return "ELEMENTO"

    def generate_variable_name(self, element: UIElement) -> tuple[str, str]:
        raw_text = ""
        base_name = ""

        if element.text and element.text.strip():
            raw_text = element.text.strip()
            base_name = self._sanitize_string(raw_text)
        elif element.content_desc and element.content_desc.strip():
            raw_text = element.content_desc.strip()
            base_name = self._sanitize_string(raw_text)
        elif element.resource_id:
            raw_id = element.resource_id.split("/")[-1]
            raw_text = raw_id
            base_name = self._sanitize_string(raw_id)

        if not base_name:
            simple_class = element.class_name.replace("XCUIElementType", "").split(".")[-1]
            raw_text = simple_class
            base_name = self._sanitize_string(simple_class)

        prefix = self._get_prefix(element.class_name, raw_text)
        slug = self._sanitize_slug(raw_text) or "elemento"
        var_name = f"{prefix}_{base_name}" if base_name else f"{prefix}_DESCONHECIDO"

        final_name = var_name
        final_slug = slug
        counter = 1
        while final_name in self.declared_objects:
            final_name = f"{var_name}_{counter}"
            final_slug = f"{slug}_{counter}"
            counter += 1

        return final_name, final_slug

    def rank_locators(self, element: UIElement, screen: list[UIElement]) -> list[dict]:
        """Ordena os localizadores possiveis do mais robusto ao menos, dizendo
        quais sao unicos na tela atual.

        Escolher o seletor na mao, uma estrategia so para a sessao inteira,
        produz codigo instavel: o mesmo `resource-id` pode aparecer cinco vezes
        na tela, e o passo gerado passa a depender de qual delas o Appium achar
        primeiro. Como a hierarquia inteira ja esta carregada, da para conferir.

        A ordem segue robustez: identificador estavel primeiro, texto depois
        (muda com idioma e conteudo), e coordenada por ultimo, que quebra em
        qualquer mudanca de layout.
        """
        candidatos: list[dict] = []

        def quantos_com(campo: str, valor: str) -> int:
            return sum(1 for e in screen if getattr(e, campo, None) == valor)

        if element.resource_id:
            campo = "resource_id"
            candidatos.append({
                "strategy": "id",
                "value": self.generate_locator_value(element, LocatorStrategy.ID),
                "matches": quantos_com(campo, element.resource_id),
                "why": "identificador do elemento, o que menos muda entre versoes",
            })
        if element.content_desc:
            candidatos.append({
                "strategy": "accessibility_id",
                "value": f'(AppiumBy.ACCESSIBILITY_ID, "{element.content_desc}")',
                "matches": quantos_com("content_desc", element.content_desc),
                "why": "rotulo de acessibilidade, estavel e legivel",
            })
        if element.text:
            candidatos.append({
                "strategy": "text",
                "value": f'(AppiumBy.XPATH, \'{self._generate_xpath(element)}\')',
                "matches": quantos_com("text", element.text),
                "why": "texto visivel; muda com idioma e com conteudo dinamico",
            })
        candidatos.append({
            "strategy": "xpath",
            "value": f'(AppiumBy.XPATH, \'{self._generate_xpath(element)}\')',
            "matches": 1,
            "why": "caminho na arvore; quebra se o layout mudar",
        })
        candidatos.append({
            "strategy": "position",
            "value": self.generate_locator_value(element, LocatorStrategy.POSITION),
            "matches": 1,
            "why": "coordenada absoluta; ultimo recurso, quebra com qualquer mudanca de tela",
        })

        for c in candidatos:
            c["unique"] = c["matches"] == 1
        # Unico vence ambiguo; entre iguais, mantem a ordem de robustez acima.
        return sorted(candidatos, key=lambda c: not c["unique"])

    def choose_locator(self, element: UIElement, screen: list[UIElement]) -> dict:
        """O melhor localizador para este elemento nesta tela."""
        return self.rank_locators(element, screen)[0]

    def generate_locator_value(self, element: UIElement, strategy: LocatorStrategy) -> str:
        if strategy == LocatorStrategy.ID:
            if element.platform == "ios":
                id_val = element.resource_id or element.content_desc or element.text
                if id_val:
                    return f'(AppiumBy.ACCESSIBILITY_ID, "{id_val}")'
            else:
                if element.resource_id:
                    return f'(AppiumBy.ID, "{element.resource_id}")'
                elif element.content_desc:
                    return f'(AppiumBy.ACCESSIBILITY_ID, "{element.content_desc}")'

        xpath = self._generate_xpath(element)
        return f"(AppiumBy.XPATH, '{xpath}')"

    @staticmethod
    def _generate_xpath(element: UIElement) -> str:
        tag = element.class_name
        if element.platform == "ios":
            if element.resource_id:
                return f'//{tag}[@name="{element.resource_id}"]'
            elif element.content_desc:
                return f'//{tag}[@label="{element.content_desc}"]'
            elif element.text:
                return f'//{tag}[@value="{element.text}"]'
            return f"//{tag}"
        else:
            if element.resource_id:
                return f'//{tag}[@resource-id="{element.resource_id}"]'
            elif element.text:
                return f'//{tag}[@text="{element.text}"]'
            elif element.content_desc:
                return f'//{tag}[@content-desc="{element.content_desc}"]'
            return f"//{tag}"

    def generate_entry(
        self,
        element: UIElement,
        strategy: LocatorStrategy | None = None,
        click_coord: tuple[int, int] | None = None,
    ) -> tuple[str, str, str]:
        active_strat = strategy or self.strategy
        var_name, slug = self.generate_variable_name(element)
        locator_val = self.generate_locator_value(element, active_strat)

        object_line = f"    {var_name} = {locator_val}"
        self.declared_objects[var_name] = object_line

        is_input = "CAMPO" in var_name or "SEARCH" in element.class_name.upper()

        if active_strat == LocatorStrategy.POSITION:
            pos_x, pos_y = click_coord if click_coord else element.center
            if is_input:
                action_block = (
                    f"    def preencher_{slug}(self, texto):\n"
                    f"        self.click_at_position(self.locators['{self.page_objects_key}'].{var_name}, {pos_x}, {pos_y})\n"
                    f"        self.send_keys(self.locators['{self.page_objects_key}'].{var_name}, texto)\n"
                )
            else:
                action_block = (
                    f"    def click_{slug}(self):\n"
                    f"        self.click_at_position(self.locators['{self.page_objects_key}'].{var_name}, {pos_x}, {pos_y})\n"
                )
        else:
            if is_input:
                action_block = (
                    f"    def preencher_{slug}(self, texto):\n"
                    f"        self.send_keys(self.locators['{self.page_objects_key}'].{var_name}, texto)\n"
                )
            else:
                action_block = (
                    f"    def click_{slug}(self):\n"
                    f"        self.click(self.locators['{self.page_objects_key}'].{var_name})\n"
                )

        self.declared_actions[var_name] = action_block

        pos_coord = click_coord if click_coord else element.center
        step = AutomationStep(
            step_num=len(self.steps) + 1,
            action_type="input" if is_input else "click",
            var_name=var_name,
            element_name=element.display_name or slug,
            class_name=element.class_name,
            strategy=active_strat,
            locator_value=locator_val,
            coords=pos_coord,
            input_text=None,
            package=element.package,
            platform=element.platform,
        )
        self.steps.append(step)

        return var_name, object_line, action_block
