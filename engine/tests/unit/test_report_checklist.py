"""Checklist da importação dos prints do Figma: Markdown e HTML no padrão do design system."""

from __future__ import annotations

import datetime
import re
import tempfile
import unittest
from pathlib import Path

from relatorio_ocr import CARD_CHECKOUT, CARD_INTERACTION, CARD_LIST

from mobaile.domain.errors import InvalidInputError
from mobaile.domain.report import SpecTemplate
from mobaile.services.report import ReportService
from mobaile.services.report.card_reader import build_spec, read_card
from mobaile.services.report.checklist import checklist_html, checklist_markdown, parse_checklist
from mobaile.services.report.rules import expand_spec

QUANDO = datetime.datetime(2026, 11, 5, 10, 30)


class TestChecklistMarkdown(unittest.TestCase):
    def setUp(self):
        cards = [read_card(c, f"{i}.png") for i, c in enumerate([CARD_INTERACTION, CARD_CHECKOUT, CARD_LIST])]
        self.spec, self.review = build_spec(cards, "Teste", "android", "/tmp/prints")
        self.md = checklist_markdown(self.spec, self.review, spec_name="teste.json", generated_at=QUANDO)
        self.doc = parse_checklist(self.md)

    def test_um_item_por_validacao_da_auditoria(self):
        disparos = [c for c in self.doc.checks if not c.warn]
        self.assertEqual(len(disparos), len(expand_spec(SpecTemplate.from_dict(self.spec))))

    def test_duvidas_do_ocr_viram_itens_para_revisar(self):
        duvidas = [d for r in self.review for d in r["duvidas"]]
        avisos = [c for c in self.doc.checks if c.warn]
        self.assertEqual(len(avisos), len(duvidas))
        self.assertTrue(all(c.text.startswith("⚠ Revisar OCR:") for c in avisos))

    def test_cabecalho_secoes_e_cards(self):
        self.assertEqual(self.doc.title, "Checklist · Teste")
        self.assertIn(("Plataforma", "ANDROID"), self.doc.meta)
        self.assertIn(("Gerado em", "05/11/2026 10:30"), self.doc.meta)
        self.assertEqual([s.title for s in self.doc.sections], list(dict.fromkeys(c["secao"] for c in self.spec["cards"])))
        card = self.doc.sections[0].cards[0]
        self.assertIn("`0.png`", card.title)
        self.assertIn("fluxo **avulso**", self.md)
        self.assertIn("`items[0].item_id` (só no fluxo avulso): `1001`", self.md)
        self.assertFalse(any(c.done for c in self.doc.checks))

    def test_le_o_que_foi_marcado_e_editado_a_mao(self):
        md = self.md.replace("- [ ]", "- [x]", 2) + "\n## Extra\n\n- [X] item novo\n* [ ] outro\n"
        doc = parse_checklist(md)
        self.assertEqual(sum(c.done for c in doc.checks), 3)
        self.assertEqual(doc.sections[-1].title, "Extra")
        self.assertEqual([c.text for c in doc.sections[-1].checks], ["item novo", "outro"])

    def test_valor_com_crase_usa_crase_dupla(self):
        spec = {"projeto": "x", "cards": [{"secao": "1. a", "evento": "e", "params": {"detail": "a`b"}}]}
        md = checklist_markdown(spec, [{"duvidas": []}], generated_at=QUANDO)
        self.assertIn("`` a`b ``", md)
        self.assertIn('<code class="ck-code">a`b</code>', checklist_html(md, generated_at=QUANDO))


class TestChecklistHtml(unittest.TestCase):
    def setUp(self):
        cards = [read_card(c, f"{i}.png") for i, c in enumerate([CARD_INTERACTION, CARD_CHECKOUT, CARD_LIST])]
        spec, review = build_spec(cards, "Teste <b>", "android", "/tmp/prints")
        self.md = checklist_markdown(spec, review, generated_at=QUANDO).replace("- [ ]", "- [x]", 1)
        self.html = checklist_html(self.md, source_name="teste.checklist.md", generated_at=QUANDO)

    def test_padrao_do_design_system(self):
        self.assertIn("class='mb-root'", self.html)
        self.assertIn("--accent", self.html)  # tokens do design_system.css embutidos
        self.assertIn('class="rp-toolbar"', self.html)
        self.assertIn("mb-check__box", self.html)
        self.assertIn("Gerado pelo <b>Mo baile</b>", self.html)

    def test_estado_e_contagens_do_markdown(self):
        doc = parse_checklist(self.md)
        self.assertEqual(len(re.findall(r'<li class="ck-item[ "]', self.html)), len(doc.checks))
        self.assertEqual(self.html.split('</head>', 1)[1].count('aria-checked="true"'), 1)
        self.assertIn(f"1 de {len(doc.checks)} feitos", self.html)

    def test_texto_de_fora_e_escapado(self):
        corpo = self.html.split("</head>", 1)[1].split('<textarea id="ck-md"', 1)[0]
        self.assertNotIn("<b>\"", corpo)
        self.assertIn("Teste &lt;b&gt;", corpo)
        md = "# T\n\n## S\n\n- [ ] <img src=x onerror=alert(1)>\n"
        self.assertNotIn("<img src=x", checklist_html(md, generated_at=QUANDO))

    def test_arquivo_offline_com_scripts_pelo_hash(self):
        self.assertNotRegex(self.html, r"(src|href)=[\"']https?:")
        csp = re.search(r'Content-Security-Policy" content="([^"]+)"', self.html).group(1)
        self.assertIn("default-src 'none'", csp)
        self.assertEqual(csp.count("'sha256-"), 2)


class TestChecklistPeloServico(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        prints = self.base / "prints"
        prints.mkdir()
        for nome in ("01.png", "02.png", "03.png"):
            (prints / nome).write_bytes(b"x")

        class Ocr:
            def read(self, paths):
                return dict(zip(map(str, paths), [CARD_INTERACTION, CARD_CHECKOUT, CARD_LIST], strict=False))

        self.service = ReportService(ocr=Ocr(), documents_dir=self.base / "Mo baile", now=lambda: QUANDO)
        self.importado = self.service.import_prints(str(prints), projeto="Demanda")

    def test_importar_grava_o_checklist_ao_lado_do_rascunho(self):
        checklist = Path(self.importado["checklist_path"])
        self.assertEqual(checklist, Path(self.importado["spec_path"]).with_suffix(".checklist.md"))
        self.assertTrue(checklist.read_text(encoding="utf-8").startswith("# Checklist · Demanda"))

    def test_exportar_grava_o_html_ao_lado_do_markdown(self):
        checklist = Path(self.importado["checklist_path"])
        checklist.write_text(checklist.read_text(encoding="utf-8").replace("- [ ]", "- [x]", 1), encoding="utf-8")
        resultado = self.service.export_checklist(str(checklist))
        html = Path(resultado["path"])
        self.assertEqual(html.parent.resolve(), checklist.parent.resolve())
        self.assertEqual(html.name, "checklist_demanda_05-11-2026.html")
        self.assertEqual(resultado["done"], 1)
        self.assertGreater(resultado["total"], 7)
        self.assertEqual(resultado["bytes"], html.stat().st_size)

    def test_exportar_em_outra_pasta(self):
        destino = self.base / "saida"
        resultado = self.service.export_checklist(self.importado["checklist_path"], str(destino))
        self.assertEqual(Path(resultado["path"]).parent.resolve(), destino.resolve())

    def test_exportar_pela_spec_usa_o_checklist_da_importacao(self):
        checklist = Path(self.importado["checklist_path"])
        checklist.write_text(checklist.read_text(encoding="utf-8").replace("- [ ]", "- [x]", 1), encoding="utf-8")
        resultado = self.service.export_checklist(spec_path=self.importado["spec_path"])
        self.assertEqual(resultado["done"], 1)

    def test_exportar_pela_spec_sem_checklist_gera_da_spec(self):
        spec = Path(self.importado["spec_path"])
        Path(self.importado["checklist_path"]).unlink()
        resultado = self.service.export_checklist(spec_path=str(spec))
        gerado = spec.with_suffix(".checklist.md").read_text(encoding="utf-8")
        self.assertNotIn("Revisar OCR", gerado)  # sem a importação, não há dúvidas do OCR
        self.assertEqual(resultado["total"], 7)  # um item por disparo, sem log nem auditoria

    def test_so_aceita_markdown(self):
        with self.assertRaises(InvalidInputError):
            self.service.export_checklist(self.importado["spec_path"])
        with self.assertRaises(InvalidInputError):
            self.service.export_checklist(str(self.base / "nao-existe.md"))


if __name__ == "__main__":
    unittest.main()


def test_bug_marker_and_copy_button() -> None:
    from mobaile.services.report.checklist import checklist_html, parse_checklist

    text = "# Checklist · x\n\n## S\n\n### C\n\n- [!] `detail` = `click:a`\n- [x] disparo de `screen_view`\n- [ ] nada\n"
    items = parse_checklist(text).checks
    assert [(i.done, i.bug) for i in items] == [(False, True), (True, False), (False, False)]
    page = checklist_html(text)
    assert 'class="ck-item is-bug"' in page
    assert 'data-copy="click:a"' in page and 'data-copy="screen_view"' in page
    assert 'data-act="save"' in page and 'data-filter="bug"' in page


def test_test_data_form_prefilled_from_markdown() -> None:
    from mobaile.services.report.checklist import TEST_FIELDS, checklist_html

    text = ("# Checklist · x\n\n- Plataforma: IOS\n- Nome: Ana\n- Data início: 09/11/2026\n- Cooperativa: 0101\n\n"
            "## S\n\n### C\n\n- [ ] disparo de `screen_view`\n")
    page = checklist_html(text)
    assert page.count("data-field=") == len(TEST_FIELDS)
    assert 'data-field="nome" data-label="Nome" value="Ana"' in page
    assert 'value="2026-11-09"' in page and 'value="0101"' in page
    assert '<option value="iOS" selected>' in page
