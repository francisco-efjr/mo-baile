"""Importação dos prints do Figma: OCR para o rascunho da spec-modelo.

As linhas de OCR são sintéticas (`relatorio_ocr.py`), com os ruídos vistos nos
prints reais. O OCR de verdade só roda no macOS com Swift e fica no fim.
"""

from __future__ import annotations

import json
import platform
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from relatorio_ocr import CARD_CHECKOUT, CARD_INTERACTION, CARD_LIST

from mobaile.adapters.vision_ocr import VisionOCR
from mobaile.domain.errors import InvalidInputError, ToolNotFoundError
from mobaile.domain.report import SpecTemplate
from mobaile.services.report import ReportService
from mobaile.services.report.card_reader import build_spec, clean_value, fix_click, match_vocab, read_card
from mobaile.services.report.rules import expand_spec


class TestNormalizacaoDoOcr(unittest.TestCase):
    def test_vocabulario(self):
        self.assertEqual(match_vocab("screenname", ["screen_name"]), ("screen_name", True))
        self.assertEqual(match_vocab("tlow_name", ["flow_name"]), ("flow_name", True))
        self.assertEqual(match_vocab("detail", ["detail"]), ("detail", False))
        self.assertEqual(match_vocab("xpto", ["detail"]), (None, False))

    def test_valores(self):
        self.assertEqual(clean_value("[0/1]"), "[0|1]")
        self.assertEqual(clean_value("[011]"), "[0|1]")
        self.assertEqual(clean_value("app:credito:[pessoal)investimentos]:sucesso"),
                         "app:credito:[pessoal|investimentos]:sucesso")
        self.assertEqual(clean_value("[seguro credito]"), "[seguro|credito]")
        self.assertEqual(clean_value("[label do botao]"), "[label do botao]")  # descritivo, não alternância
        self.assertEqual(clean_value("[valor bruto]"), "[valor bruto]")

    def test_click(self):
        self.assertEqual(fix_click("clickifechar"), ("click:fechar", True))
        self.assertEqual(fix_click("clickiir para tela inicial"), ("click:ir-para-tela-inicial", True))
        self.assertEqual(fix_click("click:voltar"), ("click:voltar", False))


class TestLeituraDeCard(unittest.TestCase):
    def test_card_com_observacao(self):
        card = read_card(CARD_INTERACTION, "a.png")
        self.assertEqual(card.event, "interaction_credito_[pessoal|investimentos]")
        self.assertEqual(card.params["screen_name"], "app:credito:[pessoal|investimentos]:simulacao")
        self.assertEqual(card.params["flow_name"], "credito-[pessoal|investimentos]")
        self.assertEqual(card.bullets["component"], ["modal"])
        self.assertEqual(card.bullets["detail"], ["click:10-parcela-com-seguro", "click:fechar"])
        self.assertTrue(any("screen name" in d for d in card.doubts))
        self.assertNotIn("interactio", str(card.params))

    def test_card_de_ecommerce(self):
        card = read_card(CARD_CHECKOUT, "b.png")
        self.assertEqual(card.event, "add_to_cart")
        self.assertIn("loan_insurance_value", card.params)
        self.assertNotIn("lue", card.params)
        self.assertEqual(card.params["insurance"], "[0|1]")
        self.assertEqual(card.params["operation_type"], "[pessoal|investimentos]-pre-aprovado")
        self.assertEqual(card.params["items"],
                         [{"item_id": "14063", "item_name": "credito-pessoal", "item_category": "simulacao"}])

    def test_print_sem_texto_vira_duvida_e_nao_erro(self):
        card = read_card([], "vazio.png")
        self.assertEqual(card.event, "")
        self.assertIn("nenhum texto lido", card.doubts)


class TestSpecGerada(unittest.TestCase):
    def setUp(self):
        cards = [read_card(c, f"{i}.png") for i, c in enumerate([CARD_INTERACTION, CARD_CHECKOUT, CARD_LIST])]
        self.spec, self.review = build_spec(cards, "Teste", "android", "/tmp/prints")

    def test_fluxos_e_variacoes(self):
        self.assertEqual(list(self.spec["fluxos"]), ["pessoal", "investimentos"])
        card = self.spec["cards"][0]
        self.assertEqual(card["evento"], "interaction_credito_{fluxo}")
        self.assertEqual(card["params"]["component"], "modal")
        self.assertEqual([v["detail"] for v in card["variacoes"]],
                         ["click:[numero]-parcela-com-seguro", "click:fechar"])  # generalizado pela tabela

    def test_placeholders_e_items_por_fluxo(self):
        params = self.spec["cards"][1]["params"]
        self.assertEqual(params["installments"], "[numero]")
        self.assertEqual(params["due_date"], "[data]")
        self.assertEqual(params["loan_insurance_value"], "[numero]")
        self.assertEqual(params["operation_type"], "{fluxo}-pre-aprovado")
        self.assertEqual(params["items"][0]["item_name"], "credito-{fluxo}")
        self.assertEqual(params["items"][0]["item_id"], "[preenchido]")
        self.assertEqual(self.spec["cards"][1]["params_por_fluxo"], {"pessoal": {"items": [{"item_id": "14063"}]}})

    def test_card_sem_fluxo_e_itens_de_exemplo(self):
        lista = self.spec["cards"][2]
        self.assertEqual(lista["evento"], "view_item_list")
        self.assertNotIn("{fluxo}", str(lista))
        self.assertEqual(lista["params"]["items"][0]["item_name"], "recebivel-[numero]")
        self.assertEqual(lista["params"]["items"][0]["item_id"], "card-[preenchido]")
        self.assertEqual(lista["params"]["items"][0]["price"], "[numero]")

    def test_rascunho_valida_e_expande(self):
        variants = expand_spec(SpecTemplate.from_dict(self.spec))
        # interaction: 2 fluxos x 2 details; checkout: 2 fluxos; lista: 1
        self.assertEqual(len(variants), 4 + 2 + 1)

    def test_revisao_lista_as_duvidas(self):
        duvidas = [d for r in self.review for d in r["duvidas"]]
        self.assertTrue(any("click:fechar" in d for d in duvidas))
        self.assertTrue(any("generalizado" in d for d in duvidas))
        self.assertTrue(any("item_id" in d for d in duvidas))


class OcrFalso:
    """Devolve as linhas sintéticas na ordem dos prints, como o Vision faria."""

    def __init__(self, cards):
        self.cards = cards
        self.lidos: list[str] = []

    def read(self, paths):
        self.lidos = [str(p) for p in paths]
        return {str(p): card for p, card in zip(paths, self.cards, strict=False)}


class TestImportacaoPeloServico(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.prints = self.base / "tag_antecipacao"
        self.prints.mkdir()
        for nome in ("01.png", "02.png", "03.jpg", ".oculto.png", "notas.txt"):
            (self.prints / nome).write_bytes(b"x")
        self.ocr = OcrFalso([CARD_INTERACTION, CARD_CHECKOUT, CARD_LIST])
        self.service = ReportService(ocr=self.ocr, documents_dir=self.base / "Mo baile")

    def test_grava_rascunho_e_revisao_na_pasta_padrao(self):
        resultado = self.service.import_prints(str(self.prints), projeto="Antecipação de Produção")
        self.assertEqual([Path(p).name for p in self.ocr.lidos], ["01.png", "02.png", "03.jpg"])
        spec_path = Path(resultado["spec_path"])
        self.assertEqual(spec_path, self.base / "Mo baile" / "Specs" / "antecipacao-de-producao.json")
        self.assertEqual(json.loads(spec_path.read_text(encoding="utf-8"))["projeto"], "Antecipação de Produção")
        self.assertTrue(Path(resultado["review_path"]).read_text(encoding="utf-8").startswith("# Revisão"))
        self.assertEqual(resultado["spec"]["variants"], 7)
        self.assertIsNone(resultado["spec_error"])
        self.assertEqual(len(resultado["review"]), 3)
        self.assertEqual(resultado["doubts_total"], sum(len(r["doubts"]) for r in resultado["review"]))

    def test_nunca_sobrescreve_um_rascunho_ja_revisado(self):
        primeiro = Path(self.service.import_prints(str(self.prints))["spec_path"])
        primeiro.write_text('{"revisado": true}', encoding="utf-8")
        segundo = Path(self.service.import_prints(str(self.prints))["spec_path"])
        self.assertNotEqual(primeiro, segundo)
        self.assertEqual(segundo.name, "tag-antecipacao-2.json")
        self.assertEqual(primeiro.read_text(encoding="utf-8"), '{"revisado": true}')

    def test_card_sem_evento_vai_para_revisao_sem_resumo(self):
        self.ocr.cards = [[], CARD_CHECKOUT, CARD_LIST]
        resultado = self.service.import_prints(str(self.prints))
        self.assertIsNone(resultado["spec"])
        self.assertIn("card 1.evento", resultado["spec_error"])
        self.assertTrue(Path(resultado["spec_path"]).exists())

    def test_destino_escolhido_precisa_ser_json(self):
        with self.assertRaises(InvalidInputError):
            self.service.import_prints(str(self.prints), spec_path=str(self.base / "spec.txt"))
        destino = self.service.import_prints(str(self.prints), spec_path=str(self.base / "minha.json"))
        self.assertEqual(Path(destino["spec_path"]).name, "minha.json")

    def test_pasta_sem_imagem_ou_inexistente_e_recusada(self):
        vazia = self.base / "vazia"
        vazia.mkdir()
        with self.assertRaises(InvalidInputError) as ctx:
            self.service.import_prints(str(vazia))
        self.assertIn("Nenhuma imagem", ctx.exception.message)
        with self.assertRaises(InvalidInputError):
            self.service.import_prints(str(self.base / "nao-existe"))

    def test_plataforma_invalida_e_recusada_antes_do_ocr(self):
        with self.assertRaises(InvalidInputError):
            self.service.import_prints(str(self.prints), platform="windows")
        self.assertEqual(self.ocr.lidos, [])


class TestAdapterDeOcr(unittest.TestCase):
    def test_fora_do_macos_diz_que_nao_ha_ocr(self):
        with patch("mobaile.adapters.vision_ocr.platform.system", return_value="Linux"), \
             self.assertRaises(ToolNotFoundError):
            VisionOCR(cache=Path(tempfile.gettempdir())).read(["x.png"])


@unittest.skipUnless(platform.system() == "Darwin" and shutil.which("swiftc"), "OCR real requer macOS com swiftc")
class TestOcrReal(unittest.TestCase):
    """Compila o leitor na primeira vez (de 20 a 60 s); depois usa o cache."""

    def test_le_texto_de_uma_imagem(self):
        from PIL import Image, ImageDraw, ImageFont

        with tempfile.TemporaryDirectory() as pasta:
            imagem = Image.new("RGB", (600, 120), "white")
            try:
                fonte = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 32)
            except OSError:
                fonte = ImageFont.load_default()
            ImageDraw.Draw(imagem).text((20, 40), "screen_name app:credito:home", fill="black", font=fonte)
            caminho = Path(pasta) / "card.png"
            imagem.save(caminho)
            linhas = VisionOCR().read([caminho])[str(caminho)]
            self.assertIn("app:credito:home", " ".join(ln.t for ln in linhas))


if __name__ == "__main__":
    unittest.main()
