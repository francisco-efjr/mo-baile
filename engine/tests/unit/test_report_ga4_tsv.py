"""Log em TSV exportado de uma exploração do Google Analytics 4.

Dados fictícios (app DemoApp). O export traz só as dimensões escolhidas: o que
a spec pede e o arquivo não traz vira "não exportado", sem contar como
divergência.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from mobaile.domain.report import SpecTemplate, VariantStatus
from mobaile.services.report.audit import check_params, run_audit
from mobaile.services.report.board import variant_block_text
from mobaile.services.report.firebase_log import events_from_items, items_from_text
from mobaile.services.report.ga4_tsv import items_from_ga4_tsv, looks_like_ga4_tsv
from mobaile.services.report.html_report import generate_interactive_html
from mobaile.services.report.service import ReportService

# Pivô por sistema operacional, como o GA4 exporta: comentários, linha do pivô,
# cabeçalho, linha de totais e os dados.
TSV_PIVO = (
    "# ----------------------------------------\n"
    "# DemoApp\n"
    "# Exploração de teste\n"
    "# 20261111-20261111\n"
    "# ----------------------------------------\n"
    "\n"
    "\t\t\tSistema operacional\tiOS\tAndroid\tTotais\n"
    "Nome do evento\tfirebase_screen\tflow_name\tflow_step\tTotal de usuários\tTotal de usuários\tTotal de usuários\n"
    "\t\t\t\t5\t4\t9\tTotal geral\n"
    "screen_view\tdemoapp:loja:inicio\tloja\tprimeiro-acesso\t3\t2\t5\n"
    "add_to_cart\tdemoapp:loja:sacola\tloja\t(not set)\t2\t0\t2\n"
    "purchase\tdemoapp:loja:sucesso\tcompra\tretomada\t0\t2\t2\n"
    "\n"
)

TSV_SIMPLES = (
    "# DemoApp\n"
    "Nome do evento\tfirebase_screen\tflow_name\tContagem de eventos\n"
    "\t\t\t12\n"
    "screen_view\tdemoapp:loja:inicio\tloja\t10\n"
    "add_to_cart\tdemoapp:loja:sacola\tloja\t2\n"
)

TSV_PLATAFORMA_NA_LINHA = (
    "Nome do evento\tPlataforma\tflow_name\tTotal de usuários\n"
    "screen_view\tAndroid\tloja\t4\n"
    "screen_view\tiOS\tloja\t1\n"
)

SPEC = {
    "projeto": "DemoApp",
    "plataforma": "ios",
    "fluxos": {},
    "cards": [
        {"secao": "Loja", "titulo": "Início", "evento": "screen_view",
         "params": {"screen_name": "demoapp:loja:inicio", "flow_name": "loja", "flow_step": "primeiro-acesso"}},
        {"secao": "Loja", "titulo": "Sacola", "evento": "add_to_cart",
         "params": {"screen_name": "demoapp:loja:sacola", "flow_name": "loja", "flow_step": "[preenchido]",
                    "component": "button", "detail": "click:adicionar",
                    "items": [{"item_id": "[preenchido]", "price": "[numero]"}]}},
        {"secao": "Loja", "titulo": "Compra", "evento": "purchase",
         "params": {"screen_name": "demoapp:loja:sucesso", "flow_name": "compra"}},
    ],
}


class LeituraDoTsvTest(unittest.TestCase):
    def test_reconhece_o_export_e_nao_confunde_com_logcat_ou_json(self):
        self.assertTrue(looks_like_ga4_tsv(TSV_PIVO))
        self.assertTrue(looks_like_ga4_tsv(TSV_SIMPLES))
        logcat = "11-16 10:00:00.000  4321  4400 V FA-SVC : Logging event: origin=app,name=screen_view,params=Bundle[{}]"
        self.assertFalse(looks_like_ga4_tsv(logcat))
        self.assertFalse(looks_like_ga4_tsv("a\tb\nc\td\n"))
        self.assertEqual(items_from_text("[]"), [])

    def test_pivo_por_sistema_operacional_vira_um_evento_por_plataforma(self):
        items = items_from_ga4_tsv(TSV_PIVO)
        resumo = [(i["event_name"], i["platform"]) for i in items]
        # Linha de totais fica de fora; contagem zero não vira evento.
        self.assertEqual(resumo, [
            ("screen_view", "ios"), ("screen_view", "android"), ("add_to_cart", "ios"), ("purchase", "android"),
        ])
        self.assertEqual(items[0]["params"], {"ga_screen": "demoapp:loja:inicio", "flow_name": "loja", "flow_step": "primeiro-acesso"})
        self.assertIsNone(items[2]["params"]["flow_step"])  # (not set): exportado e vazio
        self.assertEqual(items[0]["exportados"], ["ga_screen", "flow_name", "flow_step"])

    def test_sem_pivo_a_metrica_e_a_coluna_numerica_da_direita(self):
        items = items_from_ga4_tsv(TSV_SIMPLES)
        self.assertEqual([i["event_name"] for i in items], ["screen_view", "add_to_cart"])
        self.assertEqual(items[0]["exportados"], ["ga_screen", "flow_name"])
        self.assertEqual({i["platform"] for i in items}, {"qualquer"})
        # Sem plataforma no export, vale para a plataforma auditada.
        eventos, stats = events_from_items(items_from_text(TSV_SIMPLES), "android")
        self.assertEqual(len(eventos), 2)
        self.assertEqual(eventos[0].platform, "android")
        self.assertEqual(stats["exportados"], ["ga_screen", "flow_name"])

    def test_plataforma_como_dimensao_de_linha(self):
        items = items_from_ga4_tsv(TSV_PLATAFORMA_NA_LINHA)
        self.assertEqual([i["platform"] for i in items], ["android", "ios"])
        self.assertEqual(items[0]["exportados"], ["flow_name"])
        self.assertNotIn("Plataforma", items[0]["params"])

    def test_estatisticas_da_leitura(self):
        eventos, stats = events_from_items(items_from_text(TSV_PIVO), "ios")
        self.assertEqual([e.event_name for e in eventos], ["screen_view", "add_to_cart"])
        self.assertEqual(stats, {"total_lidos": 4, "da_plataforma": 2, "duplicados": 0, "uteis": 2,
                                 "exportados": ["ga_screen", "flow_name", "flow_step"]})


class AuditoriaComTsvTest(unittest.TestCase):
    def relatorio(self, tsv=TSV_PIVO, plataforma="ios"):
        eventos, stats = events_from_items(items_from_text(tsv), plataforma)
        return run_audit(SpecTemplate.from_dict(SPEC), eventos, plataforma, stats)

    def test_o_que_nao_veio_no_export_nao_diverge(self):
        r = self.relatorio()
        inicio, sacola, compra = r.results
        self.assertEqual(inicio.status, VariantStatus.OK)
        # A sacola veio com flow_step (not set): exportado e vazio diverge.
        self.assertEqual(sacola.status, VariantStatus.ERROR)
        por_campo = {c.field: c for c in sacola.checks}
        self.assertFalse(por_campo["flow_step"].ok)
        self.assertTrue(por_campo["flow_step"].exported)
        for campo in ("component", "detail", "items[0].item_id", "items[0].price"):
            self.assertFalse(por_campo[campo].exported, campo)
            self.assertTrue(por_campo[campo].ok, campo)
            self.assertIsNone(por_campo[campo].obtained)
        self.assertTrue(por_campo["screen_name"].exported)
        self.assertEqual(por_campo["screen_name"].obtained, "demoapp:loja:sacola")
        # A compra só existe no Android.
        self.assertEqual(compra.status, VariantStatus.MISSING)

    def test_detail_nao_exportado_nao_recorta_os_candidatos(self):
        r = self.relatorio()
        self.assertEqual(r.results[1].occurrences, 1)

    def test_logcat_continua_conferindo_tudo(self):
        checks = check_params({"component": "button"}, {})
        self.assertEqual([(c.ok, c.exported) for c in checks], [(False, True)])

    def test_html_e_bloco_mostram_nao_exportado(self):
        r = self.relatorio()
        bloco = variant_block_text(r.results[1], None)
        self.assertIn('"component": —,  // não exportado', bloco)
        html = generate_interactive_html(r, None)
        self.assertIn("export do GA4 · confere ga_screen, flow_name, flow_step", html)
        self.assertIn('<td class="v__none">não exportado</td>', html)


class ServicoComTsvTest(unittest.TestCase):
    def test_payload_marca_so_o_nao_exportado_e_aceita_tsv(self):
        with tempfile.TemporaryDirectory() as tmp:
            pasta = Path(tmp)
            spec = pasta / "spec.json"
            spec.write_text(json.dumps(SPEC), encoding="utf-8")
            log = pasta / "export.tsv"
            log.write_text(TSV_PIVO, encoding="utf-8")
            servico = ReportService(ocr=None, documents_dir=pasta)
            itens, caminho = servico.read_log(str(log))
            p = servico.audit(str(spec), itens, source="file", log_path=caminho, platform="ios")
            self.assertEqual(p["exported_fields"], ["ga_screen", "flow_name", "flow_step"])
            checks = {c["field"]: c for c in p["results"][1]["checks"]}
            self.assertEqual(checks["component"], {"field": "component", "expected": "button", "obtained": None,
                                                   "ok": True, "exported": False})
            self.assertNotIn("exported", checks["screen_name"])
            self.assertEqual(p["summary"]["divergent"], 1)
            # Logcat: o payload não ganha campo novo.
            logcat = pasta / "log.txt"
            logcat.write_text("", encoding="utf-8")
            p2 = servico.audit(str(spec), [], source="file", log_path=logcat, platform="ios")
            self.assertNotIn("exported_fields", p2)


if __name__ == "__main__":
    unittest.main()
