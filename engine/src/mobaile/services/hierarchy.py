"""Parsing da árvore de acessibilidade (Android uiautomator + iOS WDA).

O `UIElement` mora em `mobaile.domain.models`: é vocabulário compartilhado com
o front, não detalhe deste parser. Fica reexportado aqui para não quebrar quem
já importava daqui.
"""

from __future__ import annotations

import logging
import re
import xml.etree.ElementTree as ET

from mobaile.domain.models import UIElement
from mobaile.security import parse_untrusted_xml

logger = logging.getLogger(__name__)

__all__ = ["UIElement", "UIHierarchyParser"]


class UIHierarchyParser:
    BOUNDS_REGEX = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")

    @classmethod
    def parse_android_bounds(cls, bounds_str: str) -> tuple[int, int, int, int] | None:
        match = cls.BOUNDS_REGEX.match(bounds_str)
        if match:
            x1, y1, x2, y2 = map(int, match.groups())
            return (x1, y1, x2, y2)
        return None

    @classmethod
    def parse_xml(cls, xml_content: str) -> list[UIElement]:
        if not xml_content:
            return []

        # Parser endurecido: recusa DOCTYPE/entidades vindas do app sob teste.
        root = parse_untrusted_xml(xml_content)
        if root is None:
            return []

        is_ios = "XCUIElementType" in xml_content or root.tag.startswith("XCUIElementType")
        return cls._parse_ios(root) if is_ios else cls._parse_android(root)

    @classmethod
    def _parse_android(cls, root: ET.Element) -> list[UIElement]:
        elements: list[UIElement] = []

        def walk(node: ET.Element, depth: int, parent_idx: int | None):
            attribs = node.attrib
            bounds = cls.parse_android_bounds(attribs.get("bounds", ""))
            current_idx = None
            if bounds:
                x1, y1, x2, y2 = bounds
                area = (x2 - x1) * (y2 - y1)
                if area > 0:
                    current_idx = len(elements)
                    elements.append(
                        UIElement(
                            tag=node.tag,
                            class_name=attribs.get("class", node.tag),
                            resource_id=attribs.get("resource-id", ""),
                            text=attribs.get("text", ""),
                            content_desc=attribs.get("content-desc", ""),
                            clickable=attribs.get("clickable", "false").lower() == "true",
                            bounds=bounds,
                            area=area,
                            package=attribs.get("package", ""),
                            platform="android",
                            depth=depth,
                            parent_idx=parent_idx,
                        )
                    )
            next_parent = current_idx if current_idx is not None else parent_idx
            for child in node:
                walk(child, depth + (1 if current_idx is not None else 0), next_parent)

        walk(root, 0, None)
        return elements

    @classmethod
    def _parse_ios(cls, root: ET.Element) -> list[UIElement]:
        elements: list[UIElement] = []

        def walk(node: ET.Element, depth: int, parent_idx: int | None):
            attribs = node.attrib
            tag = node.tag
            bounds = None
            try:
                x = int(float(attribs.get("x", 0)))
                y = int(float(attribs.get("y", 0)))
                w = int(float(attribs.get("width", 0)))
                h = int(float(attribs.get("height", 0)))
                area = w * h
                if area > 0:
                    bounds = (x, y, x + w, y + h)
            except (ValueError, TypeError):
                area = 0

            current_idx = None
            if bounds:
                name = attribs.get("name") or ""
                label = attribs.get("label") or ""
                value = attribs.get("value") or ""

                is_clickable = (
                    "Button" in tag
                    or "TextField" in tag
                    or "Cell" in tag
                    or "Switch" in tag
                    or attribs.get("accessible", "false").lower() == "true"
                )

                current_idx = len(elements)
                elements.append(
                    UIElement(
                        tag=tag,
                        class_name=tag,
                        resource_id=name,
                        text=value if value else label,
                        content_desc=label if label else name,
                        clickable=is_clickable,
                        bounds=bounds,
                        area=area,
                        package="",
                        platform="ios",
                        depth=depth,
                        parent_idx=parent_idx,
                    )
                )

            next_parent = current_idx if current_idx is not None else parent_idx
            for child in node:
                walk(child, depth + (1 if current_idx is not None else 0), next_parent)

        walk(root, 0, None)
        return elements

    @classmethod
    def find_element_at(cls, xml_content: str, x: int, y: int) -> UIElement | None:
        elements = cls.parse_xml(xml_content)
        candidates = [
            elem for elem in elements
            if elem.bounds[0] <= x <= elem.bounds[2] and elem.bounds[1] <= y <= elem.bounds[3]
        ]

        if not candidates:
            return None

        meaningful = [
            e for e in candidates
            if (e.text or e.resource_id or e.content_desc or e.clickable)
            and e.class_name not in ("XCUIElementTypeApplication", "XCUIElementTypeWindow")
        ]

        pool = meaningful or candidates
        pool.sort(key=lambda e: e.area)
        return pool[0]
