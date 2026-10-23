#!/usr/bin/env python3
"""Copia o design system e o ícone para o HTML do Relatório.

O relatório exportado é um arquivo único, aberto fora do app e muitas vezes
sem internet. Por isso tudo o que ele usa vai embutido, e o motor não pode ler
`docs/` nem `assets/`: o app empacota só `engine/src`. Este script gera as
cópias que ficam em `engine/src/mobaile/services/report/html/`:

    design_system.css   tokens + componentes de docs/design/design-system,
                        na ordem do styles.css (claro, escuro, alto contraste,
                        Reduzir transparência e Reduzir movimento)
    icons.json          glifos Lucide do design system que o relatório usa
    icon.png            ícone do app em 128 px

    python3 tools/sync_report_assets.py          # regenera
    python3 tools/sync_report_assets.py --check  # falha se estiver desatualizado

O teste `test_report_html.py` roda o --check: mudar o design system sem rodar
este script quebra a suíte.
"""

from __future__ import annotations

import io
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DS = ROOT / "docs" / "design" / "design-system"
OUT = ROOT / "engine" / "src" / "mobaile" / "services" / "report" / "html"
ICON_SOURCE = ROOT / "assets" / "icon.png"
ICON_SIZE = 128
GLYPHS = (
    "braces", "check", "chevron-down", "circle-alert", "circle-check", "circle-x", "contrast", "copy",
    "info", "layers", "list-filter", "minus", "moon", "scan-search", "search", "smartphone", "sun",
    "triangle-alert", "x",
)

HEADER = (
    "/* Mo baile — design system (macOS 27 · Liquid Glass) para o HTML do Relatório.\n"
    "   GERADO por tools/sync_report_assets.py a partir de docs/design/design-system.\n"
    "   Não edite aqui: mude o design system e rode o script de novo. */\n"
)


def design_system_css() -> str:
    """Concatena os @import do styles.css do design system, na mesma ordem."""
    styles = (DS / "styles.css").read_text(encoding="utf-8")
    parts = [HEADER]
    for name in re.findall(r'@import url\("([^"]+)"\);', styles):
        css = (DS / name).read_text(encoding="utf-8").strip()
        parts.append(f"\n/* ── {name} ── */\n{css}\n")
    return "".join(parts)


def icons_json() -> str:
    """Os glifos do `Icon.jsx` (Lucide, ISC) que o HTML desenha."""
    source = (DS / "components" / "indicators" / "Icon.jsx").read_text(encoding="utf-8")
    paths = json.loads(re.search(r"const PATHS = (\{.*?\});", source, re.S).group(1))
    return json.dumps({name: paths[name] for name in GLYPHS}, ensure_ascii=False, indent=1, sort_keys=True) + "\n"


def icon_png() -> bytes:
    from PIL import Image

    with Image.open(ICON_SOURCE) as image:
        small = image.convert("RGBA").resize((ICON_SIZE, ICON_SIZE), Image.Resampling.LANCZOS)
        out = io.BytesIO()
        small.save(out, format="PNG", optimize=True)
        return out.getvalue()


def main(argv: list[str]) -> int:
    css_path, icons_path, icon_path = OUT / "design_system.css", OUT / "icons.json", OUT / "icon.png"
    css, icons = design_system_css(), icons_json()
    if "--check" in argv:
        def current(path: Path) -> str:
            return path.read_text(encoding="utf-8") if path.exists() else ""

        if current(css_path) != css or current(icons_path) != icons or not icon_path.exists():
            print("HTML do Relatório desatualizado: rode python3 tools/sync_report_assets.py", file=sys.stderr)
            return 1
        print("HTML do Relatório em dia com o design system.")
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    css_path.write_text(css, encoding="utf-8")
    icons_path.write_text(icons, encoding="utf-8")
    icon_path.write_bytes(icon_png())
    print(f"{css_path.relative_to(ROOT)} ({len(css)} bytes)")
    print(f"{icons_path.relative_to(ROOT)} ({len(icons)} bytes)")
    print(f"{icon_path.relative_to(ROOT)} ({icon_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
