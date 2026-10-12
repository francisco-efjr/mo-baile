"""QA-1: `tools/generate_fixtures.py --check` barra fixture desatualizada no portao local."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

TOOL = pathlib.Path(__file__).resolve().parents[3] / "tools" / "generate_fixtures.py"
spec = importlib.util.spec_from_file_location("generate_fixtures_tool", TOOL)
gerador = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gerador)

ATUAL = {"engine_hello": {"protocol": 3}, "proxy_status": {"running": False}}


class TestModoCheck(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.arquivo = pathlib.Path(self._tmp.name) / "engine_payloads.json"
        for alvo, valor in (("build", lambda: json.loads(json.dumps(ATUAL))), ("FIXTURE_PATH", self.arquivo)):
            p = patch.object(gerador, alvo, valor)
            p.start()
            self.addCleanup(p.stop)

    def rodar(self, *args: str) -> tuple[int, str]:
        saida = io.StringIO()
        with contextlib.redirect_stdout(saida), contextlib.redirect_stderr(saida):
            codigo = gerador.main(list(args))
        return codigo, saida.getvalue()

    def test_gerar_e_depois_conferir_passa(self):
        self.assertEqual(self.rodar()[0], 0)
        codigo, _ = self.rodar("--check")
        self.assertEqual(codigo, 0)

    def test_check_nao_escreve_no_arquivo(self):
        self.rodar()
        antes = self.arquivo.read_bytes()
        with patch.object(gerador, "build", lambda: {"outra": 1}):
            self.rodar("--check")
        self.assertEqual(self.arquivo.read_bytes(), antes)

    def test_fixture_desatualizada_falha_e_diz_o_que_rodar(self):
        self.rodar()
        with patch.object(gerador, "build", lambda: {**ATUAL, "proxy_status": {"running": True}}):
            codigo, saida = self.rodar("--check")
        self.assertNotEqual(codigo, 0)
        self.assertIn("make fixtures", saida)
        self.assertIn("proxy_status", saida)

    def _png(self, cor, nivel):
        import base64

        from PIL import Image

        buf = io.BytesIO()
        Image.new("RGB", (30, 60), cor).save(buf, format="PNG", compress_level=nivel)
        return base64.b64encode(buf.getvalue()).decode()

    def test_png_igual_com_outra_compressao_passa(self):
        # Pillow/zlib de outra maquina comprime diferente; a imagem e a mesma.
        a, b = self._png((10, 20, 30), 1), self._png((10, 20, 30), 9)
        self.assertNotEqual(a, b)
        with patch.object(gerador, "build", lambda: {"shot": {"png_base64": a}}):
            self.rodar()
        with patch.object(gerador, "build", lambda: {"shot": {"png_base64": b}}):
            codigo, saida = self.rodar("--check")
        self.assertEqual(codigo, 0, saida)

    def test_png_com_pixel_diferente_falha(self):
        with patch.object(gerador, "build", lambda: {"shot": {"png_base64": self._png((10, 20, 30), 6)}}):
            self.rodar()
        with patch.object(gerador, "build", lambda: {"shot": {"png_base64": self._png((10, 20, 31), 6)}}):
            codigo, saida = self.rodar("--check")
        self.assertNotEqual(codigo, 0)
        self.assertIn("shot", saida)

    def test_fixture_ausente_falha(self):
        codigo, saida = self.rodar("--check")
        self.assertNotEqual(codigo, 0)
        self.assertIn("make fixtures", saida)


if __name__ == "__main__":
    unittest.main()
