"""Serviço da aba Relatório com arquivos de verdade: spec, log, exportação.

O foco aqui é a fronteira com o disco: caminho que não existe, arquivo grande
demais, JSON quebrado, pasta de saída que é arquivo. Toda recusa precisa ser
`InvalidInputError` com mensagem que diz o que fazer, nunca erro interno.
"""

from __future__ import annotations

import datetime
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image
from relatorio_dados import AUSENTES, DIVERGENTES, OK, SPEC, TOTAL, gravar

from mobaile.domain.errors import InvalidInputError
from mobaile.security import files as seguranca_arquivos
from mobaile.security import prepare_output_dir, safe_file_stem, unique_path, validate_input_file
from mobaile.services.report import ReportService
from mobaile.services.report.service import BOARD_FILE, HTML_FILE, MARKDOWN_FILE, TSV_FILE

AGORA = datetime.datetime(2026, 10, 8, 21, 30, 5)


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pasta = Path(self.tmp.name).resolve()
        self.spec_path, self.log_path = gravar(self.pasta)
        self.service = ReportService(documents_dir=self.pasta / "Mo baile", now=lambda: AGORA)

    def auditar(self, **kw):
        items, log_path = self.service.read_log(str(self.log_path))
        return self.service.audit(str(self.spec_path), items, source="file", log_path=log_path, **kw)


class TestResumoDaSpec(Base):
    def test_resumo(self):
        resumo = self.service.spec(str(self.spec_path))
        self.assertEqual(resumo["projeto"], "Teste")
        self.assertEqual(resumo["plataforma"], "android")
        self.assertEqual(resumo["cards"], 3)
        self.assertEqual(resumo["variants"], TOTAL)
        self.assertEqual(resumo["sections"], ["Home", "Simulação"])
        self.assertEqual([f["key"] for f in resumo["fluxos"]], ["pessoal", "investimentos"])
        self.assertIsNone(resumo["prints_dir"])
        self.assertFalse(resumo["prints_dir_exists"])

    def test_pasta_de_prints_relativa_e_resolvida_a_partir_da_spec(self):
        (self.pasta / "prints").mkdir()
        spec_path, _ = gravar(self.pasta, spec={**SPEC, "prints_dir": "prints"})
        resumo = self.service.spec(str(spec_path))
        self.assertEqual(resumo["prints_dir"], str((self.pasta / "prints").resolve()))
        self.assertTrue(resumo["prints_dir_exists"])

    def test_til_e_expandido(self):
        with patch.dict("os.environ", {"HOME": str(self.pasta)}):
            resumo = self.service.spec("~/spec.json")
        self.assertEqual(resumo["path"], str(self.spec_path.resolve()))


class TestArquivosRecusados(Base):
    def recusa(self, chamada, trecho):
        with self.assertRaises(InvalidInputError) as ctx:
            chamada()
        self.assertIn(trecho, ctx.exception.message)

    def test_caminho_vazio_nulo_ou_com_byte_nulo(self):
        for ruim in (None, "", "   ", 42, "spec\x00.json"):
            with self.subTest(caminho=ruim), self.assertRaises(InvalidInputError):
                self.service.spec(ruim)

    def test_arquivo_que_nao_existe_ou_e_pasta(self):
        self.recusa(lambda: self.service.spec(str(self.pasta / "nada.json")), "não encontrado")
        pasta_json = self.pasta / "pasta.json"
        pasta_json.mkdir()
        self.recusa(lambda: self.service.spec(str(pasta_json)), "precisa ser um arquivo")

    def test_spec_precisa_ser_json_valido_em_utf8(self):
        quebrada = self.pasta / "quebrada.json"
        quebrada.write_text('{"projeto": "x",\n "cards": [}', encoding="utf-8")
        self.recusa(lambda: self.service.spec(str(quebrada)), "linha 2")
        latin1 = self.pasta / "latin1.json"
        latin1.write_bytes('{"projeto": "Crédito"}'.encode("latin-1"))
        self.recusa(lambda: self.service.spec(str(latin1)), "UTF-8")
        texto = self.pasta / "spec.txt"
        texto.write_text("{}", encoding="utf-8")
        self.recusa(lambda: self.service.spec(str(texto)), ".json")

    def test_log_grande_demais_e_recusado_antes_de_ler(self):
        with patch.object(seguranca_arquivos, "MAX_LOG_BYTES", 10), \
             patch("mobaile.services.report.service.MAX_LOG_BYTES", 10):
            self.recusa(lambda: self.service.read_log(str(self.log_path)), "o limite é")

    def test_extensao_de_log_desconhecida(self):
        planilha = self.pasta / "log.xlsx"
        planilha.write_bytes(b"PK")
        self.recusa(lambda: self.service.read_log(str(planilha)), ".json ou .txt ou .log")

    def test_plataforma_desconhecida(self):
        items, _ = self.service.read_log(str(self.log_path))
        self.recusa(lambda: self.service.audit(str(self.spec_path), items, source="file", platform="web"),
                    "Plataforma inválida")

    def test_exportar_sem_auditoria(self):
        self.recusa(lambda: self.service.export(), "Rode a auditoria primeiro")

    def test_pasta_de_saida_que_e_arquivo(self):
        self.auditar()
        arquivo = self.pasta / "ocupado"
        arquivo.write_text("x", encoding="utf-8")
        self.recusa(lambda: self.service.export(str(arquivo)), "Já existe um arquivo")


class TestAuditoria(Base):
    def test_payload_tem_resumo_e_uma_linha_por_variacao(self):
        relatorio = self.auditar()
        self.assertEqual(relatorio["summary"], {
            "total": TOTAL, "ok": OK, "divergent": DIVERGENTES, "missing": AUSENTES,
            "compliance_rate": round(OK / TOTAL * 100, 1), "extras": 3, "alerts": 1,
        })
        self.assertEqual(relatorio["log_stats"], {"total_lidos": 12, "da_plataforma": 11, "duplicados": 1, "uteis": 10})
        self.assertEqual(relatorio["source"], "file")
        self.assertEqual(relatorio["log_path"], str(self.log_path.resolve()))
        self.assertEqual([r["id"] for r in relatorio["results"]], list(range(TOTAL)))
        self.assertEqual({r["status"] for r in relatorio["results"]}, {"ok", "error", "missing"})
        self.assertEqual(len(relatorio["tsv"].strip().split("\n")), TOTAL + 1)
        self.assertTrue(relatorio["markdown"].startswith("# Auditoria de Tagueamento"))
        json.dumps(relatorio)  # o payload inteiro atravessa o JSON-RPC

    def test_linha_divergente_traz_o_que_corrigir(self):
        relatorio = self.auditar()
        erro = next(r for r in relatorio["results"]
                    if r["status"] == "error" and r["flow"] == "investimentos" and r["variation"] == "click:parcelas")
        self.assertEqual(erro["flow_label"], "CPAGI · credito-investimentos")
        falhas = [c for c in erro["checks"] if not c["ok"]]
        self.assertEqual(falhas, [{"field": "component", "expected": "button", "obtained": "toggle", "ok": False}])
        self.assertEqual(erro["divergences"], "component: obtido toggle, esperado button")
        self.assertTrue(erro["block"].startswith("// CPAGI · interaction_credito_investimentos [ERRO]"))
        self.assertEqual(erro["matched"]["time"], "10:02:00.000")
        self.assertEqual(erro["matched"]["params"]["component"], "toggle")

    def test_valor_que_nao_e_texto_chega_como_json(self):
        relatorio = self.auditar()
        add = next(r for r in relatorio["results"] if r["event"] == "add_to_cart" and r["flow"] == "pessoal")
        self.assertTrue(all(c["obtained"] is None or isinstance(c["obtained"], str) for c in add["checks"]))

    def test_plataforma_da_requisicao_vence_a_da_spec(self):
        relatorio = self.auditar(platform="ios")
        self.assertEqual(relatorio["platform"], "ios")
        self.assertEqual(relatorio["log_stats"]["da_plataforma"], 1)

    def test_print_do_card_so_vai_quando_existe(self):
        (self.pasta / "prints").mkdir()
        Image.new("RGB", (40, 80), "white").save(self.pasta / "prints" / "home.png")
        cards = [dict(SPEC["cards"][0], print="home.png"), dict(SPEC["cards"][1], print="faltando.png")]
        gravar(self.pasta, spec={**SPEC, "prints_dir": "prints", "cards": cards})
        relatorio = self.auditar()
        por_card = {r["card_index"]: r["print_path"] for r in relatorio["results"]}
        self.assertEqual(por_card[0], str((self.pasta / "prints" / "home.png").resolve()))
        self.assertIsNone(por_card[1])


class TestExportacao(Base):
    def test_grava_os_quatro_arquivos_na_pasta_padrao(self):
        self.auditar()
        exportado = self.service.export()
        pasta = Path(exportado["directory"])
        self.assertEqual(pasta, self.pasta / "Mo baile" / "Relatórios" / "teste-android-20261008-213005")
        self.assertEqual([f["name"] for f in exportado["files"]], [BOARD_FILE, HTML_FILE, MARKDOWN_FILE, TSV_FILE])
        for arquivo in exportado["files"]:
            caminho = Path(arquivo["path"])
            self.assertTrue(caminho.is_file(), caminho)
            self.assertEqual(caminho.stat().st_size, arquivo["bytes"])
        board = json.loads((pasta / BOARD_FILE).read_text(encoding="utf-8"))
        self.assertEqual(board["type"], "excalidraw")
        self.assertIn("<!doctype html>", (pasta / HTML_FILE).read_text(encoding="utf-8"))

    def test_pasta_escolhida_e_criada(self):
        self.auditar()
        destino = self.pasta / "saida" / "nova"
        exportado = self.service.export(str(destino))
        self.assertEqual(exportado["directory"], str(destino.resolve()))
        self.assertTrue((destino / TSV_FILE).is_file())

    def test_exporta_o_ultimo_relatorio(self):
        self.auditar()
        self.auditar(platform="ios")
        exportado = self.service.export(str(self.pasta / "ultimo"))
        self.assertIn("(IOS)", Path(exportado["files"][2]["path"]).read_text(encoding="utf-8"))

    def test_progresso_e_cancelamento_entre_arquivos(self):
        self.auditar()
        avisos = []

        class Cancelado(Exception):
            pass

        def cancelar_no_terceiro():
            if len(avisos) == 2:
                raise Cancelado

        with self.assertRaises(Cancelado):
            self.service.export(str(self.pasta / "x"), progress=lambda m, p: avisos.append((m, p)),
                                check_cancelled=cancelar_no_terceiro)
        self.assertEqual([p for _, p in avisos], [0, 25])
        self.assertFalse((self.pasta / "x" / MARKDOWN_FILE).exists())


class TestAuxiliaresDeArquivo(unittest.TestCase):
    def test_nome_de_arquivo_a_partir_de_texto_livre(self):
        self.assertEqual(safe_file_stem("Crédito - CPA & CPAGI"), "credito-cpa-cpagi")
        self.assertEqual(safe_file_stem("../../etc/passwd"), "etc-passwd")
        self.assertEqual(safe_file_stem("💥"), "relatorio")
        self.assertEqual(len(safe_file_stem("a" * 500)), 60)

    def test_caminho_unico_nao_sobrescreve(self):
        with tempfile.TemporaryDirectory() as pasta:
            alvo = Path(pasta) / "spec.json"
            self.assertEqual(unique_path(alvo), alvo)
            alvo.write_text("{}", encoding="utf-8")
            self.assertEqual(unique_path(alvo).name, "spec-2.json")

    def test_tamanho_no_limite_passa_e_um_byte_a_mais_nao(self):
        with tempfile.TemporaryDirectory() as pasta:
            arquivo = Path(pasta) / "log.json"
            arquivo.write_bytes(b"x" * 10)
            self.assertEqual(validate_input_file(str(arquivo), label="log", max_bytes=10), arquivo.resolve())
            with self.assertRaises(InvalidInputError):
                validate_input_file(str(arquivo), label="log", max_bytes=9)

    def test_pasta_de_saida_aceita_path(self):
        with tempfile.TemporaryDirectory() as pasta:
            destino = prepare_output_dir(Path(pasta) / "a" / "b")
            self.assertTrue(destino.is_dir())


if __name__ == "__main__":
    unittest.main()
