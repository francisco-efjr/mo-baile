#!/usr/bin/env python3
"""Monta o PDF do catálogo de telas a partir das capturas do app nativo.

As capturas e o `catalogo.json` saem de `WindowSnapshotTests.testCatalogoDeTelas`
(ver `docs/design/telas/CHECKLIST.md`). Este script só diagrama: uma página por
tela, com o título, o que conferir e as versões clara e escura lado a lado.

    python3 tools/catalogo_telas.py docs/design/telas

Gera `catalogo-telas.pdf` e `folha-de-contato.png` (todas as telas claras numa
imagem só, para revisão rápida).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PAGINA = (2200, 1400)
MARGEM = 60
FUNDO = (246, 246, 248)
TINTA = (20, 21, 67)
SECUNDARIO = (90, 92, 120)


def _fonte(tamanho: int, negrito: bool = False) -> ImageFont.ImageFont:
    candidatas = (
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if negrito else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    )
    for caminho in candidatas:
        try:
            return ImageFont.truetype(caminho, tamanho)
        except OSError:
            continue
    return ImageFont.load_default()


def _encaixar(imagem: Image.Image, largura: int, altura: int) -> Image.Image:
    escala = min(largura / imagem.width, altura / imagem.height, 1.0)
    return imagem.resize((max(1, int(imagem.width * escala)), max(1, int(imagem.height * escala))), Image.LANCZOS)


def pagina(pasta: Path, tela: dict, numero: int, total: int) -> Image.Image:
    folha = Image.new("RGB", PAGINA, FUNDO)
    desenho = ImageDraw.Draw(folha)
    desenho.text((MARGEM, MARGEM - 10), f"{tela['id']} · {tela['titulo']}", fill=TINTA, font=_fonte(44, True))
    desenho.text((MARGEM, MARGEM + 50), f"Conferir: {tela['conferir']}", fill=SECUNDARIO, font=_fonte(26))
    desenho.text((PAGINA[0] - MARGEM - 160, PAGINA[1] - MARGEM), f"{numero} / {total}", fill=SECUNDARIO, font=_fonte(22))

    arquivos = [(rotulo, tela[chave]) for chave, rotulo in (("claro", "Claro"), ("escuro", "Escuro"), ("unica", "Paleta"))
                if chave in tela]
    topo = MARGEM + 120
    area_altura = PAGINA[1] - topo - MARGEM - 40
    coluna = (PAGINA[0] - 2 * MARGEM - (len(arquivos) - 1) * 40) // len(arquivos)
    x = MARGEM
    for rotulo, arquivo in arquivos:
        with Image.open(pasta / arquivo) as original:
            imagem = _encaixar(original.convert("RGB"), coluna, area_altura - 40)
        desenho.text((x, topo), rotulo, fill=SECUNDARIO, font=_fonte(24, True))
        folha.paste(imagem, (x, topo + 40))
        desenho.rectangle((x - 1, topo + 39, x + imagem.width, topo + 40 + imagem.height), outline=(210, 210, 220))
        x += coluna + 40
    return folha


def folha_de_contato(pasta: Path, telas: list[dict], destino: Path) -> None:
    celula, colunas, legenda = (560, 360), 5, 34
    linhas = (len(telas) + colunas - 1) // colunas
    folha = Image.new("RGB", (colunas * celula[0], linhas * (celula[1] + legenda)), FUNDO)
    desenho = ImageDraw.Draw(folha)
    for i, tela in enumerate(telas):
        arquivo = tela.get("claro") or tela.get("unica")
        x, y = (i % colunas) * celula[0], (i // colunas) * (celula[1] + legenda)
        with Image.open(pasta / arquivo) as original:
            miniatura = _encaixar(original.convert("RGB"), celula[0] - 16, celula[1] - 8)
        folha.paste(miniatura, (x + 8, y + legenda))
        desenho.text((x + 8, y + 6), tela["id"], fill=TINTA, font=_fonte(20, True))
    folha.save(destino)


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    pasta = Path(argv[1])
    telas = json.loads((pasta / "catalogo.json").read_text(encoding="utf-8"))["telas"]
    paginas = [pagina(pasta, tela, i + 1, len(telas)) for i, tela in enumerate(telas)]
    destino = pasta / "catalogo-telas.pdf"
    paginas[0].save(destino, save_all=True, append_images=paginas[1:], resolution=150)
    folha_de_contato(pasta, telas, pasta / "folha-de-contato.png")
    print(f"{len(paginas)} páginas em {destino}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
