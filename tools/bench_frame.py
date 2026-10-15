#!/usr/bin/env python3
"""Mede o custo de codificar um quadro do espelho em PNG e em JPEG.

Imagem sintetica no tamanho de um aparelho (1080x2400): gradiente, blocos de
cor e ruido, para nao favorecer nenhum dos dois formatos. Uso:

    python3 tools/bench_frame.py [--iteracoes 20] [--largura 900]
"""

from __future__ import annotations

import argparse
import io
import random
import time

from PIL import Image, ImageDraw


def imagem_sintetica(largura: int = 1080, altura: int = 2400) -> Image.Image:
    rnd = random.Random(7)
    img = Image.new("RGB", (largura, altura))
    px = img.load()
    for y in range(altura):
        base = int(255 * y / altura)
        for x in range(largura):
            px[x, y] = (base, (x * 255) // largura, 128 + rnd.randint(-12, 12))
    draw = ImageDraw.Draw(img)
    for i in range(40):
        x0, y0 = rnd.randint(0, largura - 200), rnd.randint(0, altura - 120)
        draw.rectangle([x0, y0, x0 + 180, y0 + 90], fill=(rnd.randint(0, 255), rnd.randint(0, 255), rnd.randint(0, 255)))
        draw.text((x0 + 8, y0 + 8), f"Item {i}", fill=(255, 255, 255))
    return img


def medir(img: Image.Image, fmt: str, iteracoes: int, **kw) -> tuple[float, int]:
    tempos, tamanho = [], 0
    for _ in range(iteracoes):
        buf = io.BytesIO()
        t0 = time.perf_counter()
        img.save(buf, format=fmt, **kw)
        tempos.append((time.perf_counter() - t0) * 1000)
        tamanho = buf.tell()
    tempos.sort()
    return tempos[len(tempos) // 2], tamanho


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--iteracoes", type=int, default=20)
    ap.add_argument("--largura", type=int, default=900, help="max_width do espelho")
    args = ap.parse_args()

    original = imagem_sintetica()
    ratio = args.largura / original.width
    img = original.resize((args.largura, int(original.height * ratio)))

    png_ms, png_b = medir(img, "PNG", args.iteracoes, optimize=False, compress_level=1)
    jpg_ms, jpg_b = medir(img, "JPEG", args.iteracoes, quality=80, optimize=False)
    print(f"quadro {img.width}x{img.height}, mediana de {args.iteracoes} iteracoes")
    print(f"{'formato':8} {'ms':>8} {'bytes':>10}")
    print(f"{'PNG c1':8} {png_ms:8.1f} {png_b:10d}")
    print(f"{'JPEG 80':8} {jpg_ms:8.1f} {jpg_b:10d}")
    print(f"JPEG: {100 * (1 - jpg_ms / png_ms):.0f}% menos tempo, {100 * (1 - jpg_b / png_b):.0f}% menos bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
