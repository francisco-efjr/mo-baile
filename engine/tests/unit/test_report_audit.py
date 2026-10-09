"""Auditoria de tagueamento: regras, leitura do log, casamento e relatórios.

Portado dos testes do `tag_audit`. O oráculo são as regras do card do Figma
escritas à mão no cenário (`relatorio_dados.py`), não a saída do próprio
motor: cada número esperado aqui foi contado no log sintético.
"""

from __future__ import annotations

import json
import unittest

from relatorio_dados import AUSENTES, DIVERGENTES, LOG, OK, SPEC, TOTAL, android

from mobaile.domain.errors import InvalidInputError
from mobaile.domain.report import SpecTemplate, VariantStatus
from mobaile.services.report.audit import run_audit
from mobaile.services.report.board import build_board, variant_block_text
from mobaile.services.report.documents import generate_html, generate_markdown, generate_tsv
from mobaile.services.report.firebase_log import (
    events_from_items,
    items_from_json,
    items_from_text,
    parse_bundle,
    parse_ios_items,
)
from mobaile.services.report.rules import (
    clean_colon_spacing,
    expand_spec,
    is_noise_event,
    strip_event_suffixes,
    strip_param_key_suffixes,
    value_matches,
)


def relatorio(log=None, platform="android"):
    events, stats = events_from_items(LOG if log is None else log, platform)
    return run_audit(SpecTemplate.from_dict(SPEC), events, platform, stats)


class TestNormalizacao(unittest.TestCase):
    def test_espacos_em_volta_dos_dois_pontos_somem(self):
        self.assertEqual(clean_colon_spacing(" app: credito :home "), "app:credito:home")

    def test_sufixo_do_sdk_sai_do_evento_e_da_chave(self):
        self.assertEqual(strip_event_suffixes("screen_view(_vs)"), "screen_view")
        self.assertEqual(strip_param_key_suffixes("ga_screen(_sn)"), "ga_screen")

    def test_evento_automatico_do_sdk_e_ruido(self):
        self.assertTrue(is_noise_event("screen_view", {"ga_event_origin": "auto"}))
        self.assertTrue(is_noise_event("session_start(_s)", {}))
        self.assertTrue(is_noise_event("user_engagement", {}))
        self.assertFalse(is_noise_event("user_engagement", {"ga_event_origin": "app"}))
        self.assertFalse(is_noise_event("interaction", {"ga_event_origin": "app"}))


class TestPlaceholders(unittest.TestCase):
    def test_alternancia_inteira_e_em_trecho(self):
        self.assertTrue(value_matches("[0|1]", "0"))
        self.assertFalse(value_matches("[0|1]", "2"))
        self.assertTrue(value_matches("app:credito:[pessoal|investimentos]:sucesso", "app:credito:pessoal:sucesso"))
        self.assertFalse(value_matches("app:credito:[pessoal|investimentos]:sucesso", "app:credito:outro:sucesso"))

    def test_numero_data_e_preenchido(self):
        self.assertTrue(value_matches("click:[numero]-parcela-sem-seguro", "click:10-parcela-sem-seguro"))
        self.assertTrue(value_matches("[numero]", "200,50"))
        self.assertFalse(value_matches("[numero]", "abc"))
        self.assertTrue(value_matches("[data]", "01/12/2026"))
        self.assertFalse(value_matches("[data]", "2026-12-01"))
        self.assertTrue(value_matches("[preenchido]", "x"))

    def test_valor_ausente_ou_vazio_nunca_atende(self):
        for vazio in (None, "", "   "):
            with self.subTest(valor=vazio):
                self.assertFalse(value_matches("[preenchido]", vazio))

    def test_regex_explicita(self):
        self.assertTrue(value_matches("re:card-[0-9a-f]{4}", "card-1a2b"))
        self.assertFalse(value_matches("re:card-[0-9a-f]{4}", "card-xyz"))

    def test_metacaractere_no_literal_nao_vira_regex(self):
        """Ponto e parênteses de um literal são texto: `a.b` não casa com `axb`."""
        self.assertFalse(value_matches("click:[a|b].fim", "click:axfim"))
        self.assertTrue(value_matches("click:[a|b].fim", "click:a.fim"))


class TestExpansao(unittest.TestCase):
    def test_um_card_vira_uma_variacao_por_fluxo_e_detail(self):
        variants = expand_spec(SpecTemplate.from_dict(SPEC))
        # home (1) + 2 fluxos x 2 details + 2 fluxos x 1
        self.assertEqual(len(variants), 1 + 4 + 2)

    def test_params_por_fluxo_sobrescreve_so_o_fluxo_dele(self):
        variants = expand_spec(SpecTemplate.from_dict(SPEC))
        pessoal = next(v for v in variants if v.event == "add_to_cart" and v.flow == "pessoal")
        investimentos = next(v for v in variants if v.event == "add_to_cart" and v.flow == "investimentos")
        self.assertEqual(pessoal.expected["items"][0], {"item_id": "14063", "item_name": "credito-pessoal"})
        self.assertEqual(investimentos.expected["items"][0]["item_id"], "[preenchido]")


class TestLeituraDoLog(unittest.TestCase):
    def test_bundle_aninhado_vira_lista_de_objetos(self):
        bundle = parse_bundle("Bundle[{a=1, items=[Bundle[{item_name=x, item_id=2}]], ga_screen(_sn)=app: b}]")
        self.assertEqual(bundle["items"], [{"item_name": "x", "item_id": "2"}])
        self.assertEqual(bundle["ga_screen"], "app:b")

    def test_items_do_ios_em_texto(self):
        self.assertEqual(parse_ios_items("[ { item_id = card-1; price = 1.5; }, { item_id = card-2; } ]"),
                         [{"item_id": "card-1", "price": "1.5"}, {"item_id": "card-2"}])

    def test_filtra_plataforma_e_deduplica(self):
        events, stats = events_from_items(LOG, "android")
        self.assertEqual(stats, {"total_lidos": 12, "da_plataforma": 11, "duplicados": 1, "uteis": 10})
        self.assertTrue(all(e.platform == "android" for e in events))
        self.assertEqual(len(events_from_items(LOG, "ios")[0]), 1)

    def test_no_android_os_parametros_vem_do_raw_log(self):
        events, _ = events_from_items(LOG, "android")
        home = next(e for e in events if e.event_name == "screen_view")
        self.assertNotIn("quebrado", home.params)
        self.assertEqual(home.params["ga_screen"], "app:credito:home")

    def test_formatos_de_arquivo_aceitos(self):
        self.assertEqual(len(items_from_json({"eventos": LOG})), len(LOG))
        self.assertEqual(len(items_from_json({"jornadas": {"a": {"eventos": LOG[:2]}, "b": LOG[2:4]}})), 4)
        logcat = "\n".join(e["raw_log"] for e in LOG[:3]) + "\nlinha sem evento\n"
        self.assertEqual(len(items_from_text(logcat)), 2)  # o terceiro é iOS, sem "Logging event:"

    def test_eventos_da_escuta_do_mo_baile_sao_lidos(self):
        """`AnalyticsEvent.to_dict` (o que a escuta guarda) usa `time`, não `time_str`."""
        item = dict(android("11:00:00.000", "screen_view(_vs)", "flow_name=credito, ga_screen(_sn)=app:credito:home"))
        item["time"] = item.pop("time_str")
        events, _ = events_from_items([item], "android")
        self.assertEqual(events[0].time_str, "11:00:00.000")

    def test_ordem_e_a_do_horario(self):
        fora_de_ordem = [LOG[3], LOG[0]]
        events, _ = events_from_items(fora_de_ordem, "android")
        self.assertEqual([e.time_str for e in events], ["10:00:00.000", "10:01:00.000"])


class TestAuditoria(unittest.TestCase):
    def setUp(self):
        self.report = relatorio()

    def resultado(self, card, flow=None, detail=None):
        for r in self.report.results:
            if r.variant.card_index == card and r.variant.flow == flow and (
                detail is None or r.variant.expected.get("detail") == detail
            ):
                return r
        raise AssertionError("variação não encontrada")

    def test_totais(self):
        self.assertEqual(self.report.total, TOTAL)
        self.assertEqual(self.report.total_ok, OK)
        self.assertEqual(self.report.total_divergent, DIVERGENTES)
        self.assertEqual(self.report.total_missing, AUSENTES)
        self.assertEqual(self.report.compliance_rate, round(OK / TOTAL * 100, 1))

    def test_ok_nao_disparado_e_divergente(self):
        self.assertIs(self.resultado(0).status, VariantStatus.OK)
        self.assertIs(self.resultado(1, "pessoal", "click:parcelas").status, VariantStatus.OK)
        self.assertIs(self.resultado(1, "pessoal", "click:[numero]-parcela-sem-seguro").status, VariantStatus.MISSING)
        erro = self.resultado(1, "investimentos", "click:parcelas")
        self.assertIs(erro.status, VariantStatus.ERROR)
        self.assertEqual([c.field for c in erro.checks if not c.ok], ["component"])

    def test_vale_o_disparo_mais_recente_e_os_antigos_viram_aviso(self):
        r = self.resultado(2, "pessoal")
        self.assertIs(r.status, VariantStatus.OK)
        self.assertEqual(r.matched.time_str, "10:04:00.000")
        self.assertEqual(r.older_divergent, 1)
        self.assertIn("items[0].item_name=credito-errado", r.older_divergences)

    def test_mesma_acao_em_outra_tela_nao_rouba_o_casamento(self):
        self.assertEqual(self.resultado(1, "pessoal", "click:parcelas").matched.time_str, "10:01:00.000")
        self.assertEqual(self.resultado(0).matched.time_str, "10:00:00.000")

    def test_tela_certa_com_screen_name_errado_e_erro_de_screen_name(self):
        r = self.resultado(2, "investimentos")
        self.assertIs(r.status, VariantStatus.ERROR)
        self.assertEqual([c.field for c in r.checks if not c.ok], ["screen_name"])

    def test_fora_da_spec_e_alertas(self):
        self.assertEqual(
            [(e.event, e.screen, e.detail) for e in self.report.extras],
            [("interaction_credito_pessoal", "app:credito:pessoal:detalhes-da-proposta", "click:parcelas"),
             ("screen_view", "app:credito:outra-tela", None),
             ("modal_view", "app:credito:pessoal:simulacao", "calendario")],
        )
        self.assertEqual([a.event for a in self.report.alerts], ["app_exception"])

    def test_log_vazio_deixa_tudo_nao_disparado(self):
        vazio = relatorio(log=[])
        self.assertEqual(vazio.total_missing, TOTAL)
        self.assertEqual(vazio.compliance_rate, 0.0)


class TestRelatorios(unittest.TestCase):
    def setUp(self):
        self.report = relatorio()

    def test_board_tem_um_bloco_por_variacao(self):
        doc = build_board(self.report, prints_dir="/caminho/que/nao/existe")
        self.assertEqual(doc["type"], "excalidraw")
        textos = [e["text"] for e in doc["elements"] if e["type"] == "text"]
        blocos = [t for t in textos if t.startswith("// ")]
        self.assertEqual(len(blocos), self.report.total)
        self.assertTrue(any("↳ esperado: button" in t for t in blocos))
        self.assertTrue(any("Fora da spec" in t for t in textos))
        self.assertTrue(any("(print indisponível)" in t for t in textos))
        json.dumps(doc)  # o board inteiro precisa ser JSON
        ids = [e["id"] for e in doc["elements"]]
        self.assertEqual(len(ids), len(set(ids)), "id repetido some com elemento no Excalidraw")

    def test_mesmo_relatorio_gera_o_mesmo_board(self):
        self.assertEqual(json.dumps(build_board(self.report)), json.dumps(build_board(relatorio())))

    def test_markdown_tsv_e_html(self):
        md = generate_markdown(self.report)
        self.assertIn("NÃO DISPARADO", md)
        tsv = generate_tsv(self.report).strip().split("\n")
        self.assertEqual(len(tsv), 1 + self.report.total)
        self.assertTrue(all(len(linha.split("\t")) == 9 for linha in tsv))
        html = generate_html(self.report, prints_dir="/caminho/que/nao/existe")
        self.assertEqual(html.count('class="v '), self.report.total)
        self.assertIn(f"Divergentes ({DIVERGENTES})", html)

    def test_bloco_de_variacao_nao_disparada_mostra_o_esperado(self):
        ausente = next(r for r in self.report.results if r.status is VariantStatus.MISSING)
        bloco = variant_block_text(ausente, "CPA")
        self.assertTrue(bloco.startswith("// CPA · "))
        self.assertIn("NÃO DISPARADO", bloco)
        self.assertIn("esperado (spec)", bloco)

    def test_texto_hostil_da_spec_e_do_log_nao_vira_marcacao(self):
        spec = dict(SPEC, projeto='<script>alert("x")</script>')
        log = [android("10:00:00.000", "screen_view(_vs)",
                       "flow_name=credito, ga_screen(_sn)=<img src=x onerror=alert(1)>")]
        events, stats = events_from_items(log, "android")
        report = run_audit(SpecTemplate.from_dict(spec), events, "android", stats)
        html = generate_html(report)
        self.assertNotIn("<script>alert", html)
        self.assertNotIn("<img src=x", html)
        self.assertIn("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;", html)

    def test_tabulacao_e_quebra_no_valor_nao_quebram_a_planilha(self):
        log = [android("10:00:00.000", "interaction_credito_pessoal",
                       "screen_name=app:credito:pessoal:simulacao, flow_name=credito-pessoal, "
                       "component=bot\tao, detail=click:parcelas")]
        events, stats = events_from_items(log, "android")
        report = run_audit(SpecTemplate.from_dict(SPEC), events, "android", stats)
        linhas = generate_tsv(report).strip().split("\n")
        self.assertTrue(all(len(linha.split("\t")) == 9 for linha in linhas))


class TestValidacaoDaSpec(unittest.TestCase):
    """Spec malformada vira `invalid_input` com o lugar do problema, nunca erro interno."""

    def recusa(self, spec, trecho):
        with self.assertRaises(InvalidInputError) as ctx:
            SpecTemplate.from_dict(spec)
        self.assertIn(trecho, ctx.exception.message)

    def test_estrutura(self):
        self.recusa([], "objeto JSON")
        self.recusa({"cards": [{"evento": "x"}]}, "'projeto'")
        self.recusa({"projeto": "p"}, "não tem cards")
        self.recusa({"projeto": "p", "cards": []}, "não tem cards")
        self.recusa({"projeto": "p", "cards": ["x"]}, "card 1")
        self.recusa({"projeto": "p", "cards": [{"params": {}}]}, "card 1.evento")

    def test_tipos_dos_campos(self):
        base = {"projeto": "p", "cards": [{"evento": "e"}]}
        self.recusa({**base, "plataforma": "windows"}, "Plataforma inválida")
        self.recusa({**base, "fluxos": ["a"]}, "'fluxos'")
        self.recusa({**base, "projeto": 7}, "'projeto' precisa ser texto")
        self.recusa({"projeto": "p", "cards": [{"evento": "e", "variacoes": {"detail": "x"}}]}, "'variacoes'")
        self.recusa({"projeto": "p", "cards": [{"evento": "e", "por_fluxo": "sim"}]}, "'por_fluxo'")

    def test_regex_invalida_e_apontada_no_card(self):
        self.recusa({"projeto": "p", "cards": [{"evento": "e"}, {"evento": "f", "params": {"detail": "re:(abc"}}]},
                    "card 2: expressão regular inválida")

    def test_campos_desconhecidos_sao_ignorados(self):
        spec = SpecTemplate.from_dict({**SPEC, "extra": 1, "cards": [{**SPEC["cards"][0], "x": 2}]})
        self.assertEqual(spec.cards[0].evento, "screen_view")

    def test_plataforma_e_normalizada(self):
        self.assertEqual(SpecTemplate.from_dict({**SPEC, "plataforma": "iOS"}).plataforma, "ios")


if __name__ == "__main__":
    unittest.main()
