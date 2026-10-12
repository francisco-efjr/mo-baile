"""`report.*` pela fronteira JSON-RPC, com o servidor de verdade.

Os testes de unidade provam as regras; aqui o que se prova é o acordo com o
front: nome dos métodos, forma dos parâmetros, progresso com token, e que toda
recusa chega como `invalid_input` (o front mostra a mensagem) e não como erro
interno (o front mostraria "Erro interno no motor").
"""

from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "unit"))

from relatorio_dados import LOG, TOTAL, gravar
from relatorio_ocr import CARD_CHECKOUT, CARD_INTERACTION

from mobaile.domain.models import AnalyticsEvent
from mobaile.rpc import contract, protocol
from mobaile.rpc.server import EngineServer
from mobaile.services.report import ReportService


class OcrFalso:
    def read(self, paths):
        cards = [CARD_INTERACTION, CARD_CHECKOUT]
        return {str(p): cards[i % 2] for i, p in enumerate(paths)}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pasta = Path(self.tmp.name).resolve()
        self.spec_path, self.log_path = gravar(self.pasta)
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.addCleanup(self.server.shutdown)
        self.server.report = ReportService(ocr=OcrFalso(), documents_dir=self.pasta / "Mo baile")

    def call(self, method, params=None):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )

    def ok(self, method, params=None):
        resposta = self.call(method, params)
        self.assertNotIn("error", resposta, f"{method} devolveu erro: {resposta.get('error')}")
        return resposta["result"]

    def invalido(self, method, params=None):
        resposta = self.call(method, params)
        self.assertIn("error", resposta, f"{method} deveria recusar {params}")
        self.assertEqual(resposta["error"]["code"], protocol.ENGINE_ERROR)
        self.assertEqual(resposta["error"]["data"]["code"], "invalid_input")
        return resposta["error"]["message"]

    def progresso(self):
        linhas = [json.loads(linha) for linha in self.out.getvalue().splitlines() if linha.strip()]
        return [n["params"] for n in linhas if n.get("method") == contract.PROGRESS]


class TestRelatorioPeloContrato(Base):
    def test_metodos_estao_na_fila_de_relatorio(self):
        for nome in ("report.spec", "report.audit", "report.export", "report.import"):
            self.assertEqual(contract.lane_of(nome), contract.LANE_REPORT)

    def test_spec(self):
        resumo = self.ok("report.spec", {"path": str(self.spec_path)})
        self.assertEqual(resumo["variants"], TOTAL)

    def test_auditoria_de_arquivo_com_progresso(self):
        relatorio = self.ok("report.audit", {
            "spec_path": str(self.spec_path), "source": "file", "log_path": str(self.log_path),
            "progress_token": "rel-1",
        })
        self.assertEqual(relatorio["summary"]["total"], TOTAL)
        fases = self.progresso()
        self.assertGreaterEqual(len(fases), 2)
        self.assertTrue(all(f["token"] == "rel-1" for f in fases))
        self.assertEqual(fases[-1]["percent"], 100)

    def test_auditoria_dos_eventos_da_sessao(self):
        """O que a escuta capturou é auditado sem passar por arquivo exportado."""
        for i, item in enumerate(LOG):
            self.server.analytics.events_history.append(AnalyticsEvent(
                id=i, timestamp=0.0, time_str=item["time_str"], tag=item["tag"], event_name=item["event_name"],
                params=item["params"], raw_log=item["raw_log"], platform=item["platform"],
            ))
        relatorio = self.ok("report.audit", {"spec_path": str(self.spec_path), "source": "session"})
        self.assertEqual(relatorio["source"], "session")
        self.assertIsNone(relatorio["log_path"])
        self.assertEqual(relatorio["log_stats"]["uteis"], 10)

    def test_sessao_sem_eventos_e_recusada(self):
        mensagem = self.invalido("report.audit", {"spec_path": str(self.spec_path), "source": "session"})
        self.assertIn("Nenhum evento capturado", mensagem)

    def test_parametros_invalidos_viram_invalid_input(self):
        casos = [
            ("report.spec", {}),
            ("report.spec", {"path": 123}),
            ("report.audit", {"spec_path": str(self.spec_path), "source": "ftp"}),
            ("report.audit", {"spec_path": str(self.spec_path), "source": "file"}),
            ("report.audit", {"spec_path": str(self.spec_path), "source": "file", "log_path": str(self.log_path),
                              "platform": 7}),
            ("report.export", {}),
            ("report.import", {"prints_dir": str(self.pasta / "nao-existe")}),
            ("report.import", {"prints_dir": str(self.pasta), "projeto": ["x"]}),
        ]
        for metodo, params in casos:
            with self.subTest(metodo=metodo, params=params):
                self.invalido(metodo, params)

    def test_log_sem_eventos_e_recusado(self):
        vazio = self.pasta / "vazio.json"
        vazio.write_text("[]", encoding="utf-8")
        mensagem = self.invalido("report.audit", {
            "spec_path": str(self.spec_path), "source": "file", "log_path": str(vazio),
        })
        self.assertIn("não tem eventos", mensagem)

    def test_exportacao_depois_da_auditoria(self):
        self.ok("report.audit", {"spec_path": str(self.spec_path), "source": "file", "log_path": str(self.log_path)})
        exportado = self.ok("report.export", {"directory": str(self.pasta / "saida"), "progress_token": 9})
        self.assertEqual(len(exportado["files"]), 4)
        self.assertTrue(all(Path(f["path"]).is_file() for f in exportado["files"]))
        self.assertTrue(all(f["token"] == 9 for f in self.progresso()))

    def test_importacao_de_prints(self):
        prints = self.pasta / "prints"
        prints.mkdir()
        for nome in ("a.png", "b.png"):
            (prints / nome).write_bytes(b"x")
        resultado = self.ok("report.import", {"prints_dir": str(prints), "projeto": "Demanda", "platform": "ios",
                                              "progress_token": "imp"})
        self.assertTrue(resultado["spec_path"].endswith("demanda.json"))
        self.assertEqual(resultado["spec"]["plataforma"], "ios")
        self.assertEqual(len(resultado["review"]), 2)
        self.assertTrue(self.progresso())


if __name__ == "__main__":
    unittest.main()
