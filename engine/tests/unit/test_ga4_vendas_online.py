"""Eventos de vendas on-line do GA4 na escuta e no Relatório (3.27.0).

Referência: developers.google.com/analytics/devguides/collection/ga4/reference/events,
seção "Vendas on-line". Cobre os três defeitos achados na validação de 19/11/2026:

- vírgula dentro do valor cortava o valor sem aviso (``value=30,03`` virava ``30``);
- a escuta ao vivo embaralhava ``items`` (texto ``[Bundle[{…`` e campos do
  último item no nível do evento);
- a auditoria só conferia o primeiro item.
"""

from __future__ import annotations

import unittest

from relatorio_dados import android

from mobaile.adapters.analytics_logcat import FirebaseAnalyticsListener
from mobaile.adapters.firebase_bundle import parse_bundle, split_pairs
from mobaile.domain.report import SpecTemplate, VariantStatus
from mobaile.services.report.audit import check_items, run_audit
from mobaile.services.report.firebase_log import events_from_items
from mobaile.services.report.firebase_log import parse_bundle as parse_bundle_relatorio


def bundle_item(**campos: str) -> str:
    return "Bundle[{" + ", ".join(f"{k}={v}" for k, v in campos.items()) + "}]"


ITEM_1 = bundle_item(item_id="SKU_12345", item_name="Stan and Friends Tee", item_category="Apparel",
                     item_variant="green", price="10.01", quantity="3")
ITEM_2 = bundle_item(item_id="SKU_12346", item_name="Google Grey Women's Tee", price="21.01", quantity="2")
PURCHASE = ("currency(_cu)=USD, value(_v)=72.05, transaction_id=T_12345, coupon=SUMMER_FUN, shipping=3.33, "
            f"tax=1.11, items=[{ITEM_1}, {ITEM_2}]")

# Os 14 eventos da seção, com os parâmetros obrigatórios do documento.
EVENTOS = {
    "add_payment_info": f"currency=USD, value=72.05, payment_type=Credit Card, items=[{ITEM_1}, {ITEM_2}]",
    "add_shipping_info": f"currency=USD, value=72.05, shipping_tier=Ground, items=[{ITEM_1}, {ITEM_2}]",
    "add_to_cart": f"currency=USD, value=30.03, items=[{ITEM_1}]",
    "add_to_wishlist": f"currency=USD, value=30.03, items=[{ITEM_1}]",
    "begin_checkout": f"currency=USD, value=72.05, coupon=SUMMER_FUN, items=[{ITEM_1}, {ITEM_2}]",
    "purchase": PURCHASE,
    "refund": "currency=USD, value=72.05, transaction_id=T_12345",
    "remove_from_cart": f"currency=USD, value=30.03, items=[{ITEM_1}]",
    "select_item": f"item_list_id=related_products, item_list_name=Related products, items=[{ITEM_1}]",
    "select_promotion": "promotion_id=P_12345, promotion_name=Summer Sale, items=["
                        + bundle_item(item_id="SKU_12345", creative_slot="featured_app_1") + "]",
    "view_cart": f"currency=USD, value=72.05, items=[{ITEM_1}, {ITEM_2}]",
    "view_item": f"currency=USD, value=30.03, items=[{ITEM_1}]",
    "view_item_list": f"item_list_id=related_products, items=[{ITEM_1}, {ITEM_2}]",
    "view_promotion": "promotion_name=Summer Sale, items=[" + bundle_item(item_name="Tee") + "]",
}
MOEDA = "re:^[A-Z]{3}$"
VALOR = r"re:^-?\d+(\.\d+)?$"
SOMA = "[soma_itens]"
# Regra do GA4 para cada item: item_id ou item_name (3.28.0).
ITEM = [{"item_id|item_name": "[preenchido]"}]
REGRAS = {
    "add_payment_info": {"currency": MOEDA, "value": SOMA, "items": ITEM},
    "add_shipping_info": {"currency": MOEDA, "value": SOMA, "items": ITEM},
    "add_to_cart": {"currency": MOEDA, "value": SOMA, "items": ITEM},
    "add_to_wishlist": {"currency": MOEDA, "value": SOMA, "items": ITEM},
    "begin_checkout": {"currency": MOEDA, "value": SOMA, "items": ITEM},
    "purchase": {"currency": MOEDA, "value": SOMA, "transaction_id": "[preenchido]", "items": ITEM},
    "refund": {"currency": MOEDA, "value": VALOR, "transaction_id": "[preenchido]"},
    "remove_from_cart": {"currency": MOEDA, "value": SOMA, "items": ITEM},
    "select_item": {"items": ITEM},
    "select_promotion": {"items": ITEM},
    "view_cart": {"currency": MOEDA, "value": SOMA, "items": ITEM},
    "view_item": {"currency": MOEDA, "value": SOMA, "items": ITEM},
    "view_item_list": {"items": ITEM},
    "view_promotion": {"items": ITEM},
}


def auditar(eventos: dict[str, str], regras: dict[str, dict] = REGRAS):
    log = [android(f"10:00:{i:02d}.000", nome, corpo, id_=i) for i, (nome, corpo) in enumerate(eventos.items())]
    events, stats = events_from_items(log, "android")
    spec = {"projeto": "ga4", "cards": [{"evento": nome, "params": p} for nome, p in regras.items() if nome in eventos]}
    return run_audit(SpecTemplate.from_dict(spec), events, "android", stats)


def divergencias(report) -> dict[str, list[str]]:
    return {r.variant.event: [c.field for c in r.checks if not c.ok] for r in report.results}


class TestVirgulaNoValor(unittest.TestCase):
    def test_valor_com_virgula_fica_inteiro(self):
        b = parse_bundle("Bundle[{currency=BRL, value=30,03, flow_name=pedido}]")
        self.assertEqual(b, {"currency": "BRL", "value": "30,03", "flow_name": "pedido"})

    def test_nome_de_item_com_virgula_e_espaco(self):
        b = parse_bundle("Bundle[{items=[Bundle[{item_id=1, item_name=Camiseta, verde, price=10.01}]], value=10}]")
        self.assertEqual(b["items"], [{"item_id": "1", "item_name": "Camiseta, verde", "price": "10.01"}])
        self.assertEqual(b["value"], "10")

    def test_chave_com_nome_curto_do_sdk_abre_par_novo(self):
        self.assertEqual(split_pairs("a=1,5, ga_screen(_sn)=home, b=x"), ["a=1,5", " ga_screen(_sn)=home", " b=x"])

    def test_relatorio_continua_limpando_os_dois_pontos(self):
        self.assertEqual(parse_bundle_relatorio("Bundle[{ga_screen(_sn)=app: home, value=1,5}]"),
                         {"ga_screen": "app:home", "value": "1,5"})

    def test_valor_com_virgula_nao_passa_mais_como_numero_com_ponto(self):
        report = auditar({"add_to_cart": EVENTOS["add_to_cart"].replace("value=30.03", "value=30,03")})
        self.assertEqual(divergencias(report)["add_to_cart"], ["value"])


class TestItemsNaEscutaAoVivo(unittest.TestCase):
    def test_purchase_com_dois_itens_vira_lista(self):
        raw = ("11-19 10:00:01.000  1234  5678 V FA-SVC  : Logging event: origin=app,name=purchase(_pur),"
               f"params=Bundle[{{{PURCHASE}}}]")
        event = FirebaseAnalyticsListener()._parse_line(raw, platform="android")
        self.assertEqual(event.params["currency"], "USD")
        self.assertEqual(event.params["value"], "72.05")
        self.assertEqual(event.params["transaction_id"], "T_12345")
        self.assertEqual([i["item_id"] for i in event.params["items"]], ["SKU_12345", "SKU_12346"])
        self.assertEqual(event.params["items"][0]["item_name"], "Stan and Friends Tee")
        # Nada do item sobe para o evento.
        for campo in ("item_id", "item_name", "price", "quantity", "item_category"):
            self.assertNotIn(campo, event.params)

    def test_aspas_continuam_saindo_dos_valores(self):
        raw = "09-03 14:10:00.100 V/FA: Logging event: screen_view, Bundle[{flow_name=\"pedido\", items=[Bundle[{item_id='1'}]]}]"
        event = FirebaseAnalyticsListener()._parse_line(raw, platform="android")
        self.assertEqual(event.params["flow_name"], "pedido")
        self.assertEqual(event.params["items"], [{"item_id": "1"}])


class TestTodosOsItens(unittest.TestCase):
    def test_um_item_na_spec_vale_para_todos(self):
        checks = check_items([{"item_id": "[preenchido]"}], [{"item_id": "1"}, {"price": "2"}, {"item_id": "3"}])
        self.assertEqual([(c.field, c.ok) for c in checks],
                         [("items[0].item_id", True), ("items[1].item_id", False), ("items[2].item_id", True)])

    def test_item_i_segue_o_item_i_da_spec_e_o_ultimo_vale_para_o_resto(self):
        regras = [{"item_id": "1001"}, {"item_id": "[preenchido]"}]
        checks = check_items(regras, [{"item_id": "1001"}, {"item_id": "2002"}, {"item_id": "3003"}])
        self.assertTrue(all(c.ok for c in checks))
        self.assertEqual([c.field for c in checks], ["items[0].item_id", "items[1].item_id", "items[2].item_id"])

    def test_spec_com_mais_itens_que_o_log_aponta_o_que_falta(self):
        checks = check_items([{"item_id": "1"}, {"item_id": "2"}], [{"item_id": "1"}])
        self.assertEqual([(c.field, c.obtained, c.ok) for c in checks],
                         [("items[0].item_id", "1", True), ("items[1].item_id", None, False)])

    def test_sem_itens_no_log_os_campos_aparecem_sem_valor(self):
        checks = check_items([{"item_id": "[preenchido]", "price": "[numero]"}], None)
        self.assertEqual([(c.field, c.obtained, c.ok) for c in checks],
                         [("items[0].item_id", None, False), ("items[0].price", None, False)])

    def test_segundo_item_sem_id_e_sem_nome_vira_erro_na_auditoria(self):
        anonimo = bundle_item(price="21.01", quantity="2")
        report = auditar({"begin_checkout": f"currency=USD, value=72.05, items=[{ITEM_1}, {anonimo}]"})
        self.assertEqual(report.results[0].status, VariantStatus.ERROR)
        self.assertEqual(divergencias(report)["begin_checkout"], ["items[1].item_id|item_name"])


REGRA_ID_OU_NOME = ({"item_id|item_name": "[preenchido]"},)


class TestItemIdOuItemName(unittest.TestCase):
    def setUp(self):
        self.REGRA = list(REGRA_ID_OU_NOME)

    def test_basta_uma_das_chaves(self):
        checks = check_items(self.REGRA, [{"item_id": "SKU_1"}, {"item_name": "Tee"}, {"item_id": "", "item_name": "Cap"}])
        self.assertEqual([(c.ok, c.obtained) for c in checks],
                         [(True, "item_id=SKU_1"), (True, "item_name=Tee"), (True, "item_name=Cap")])

    def test_sem_nenhuma_das_duas_diverge(self):
        (check,) = check_items(self.REGRA, [{"price": "10.01"}])
        self.assertEqual((check.field, check.obtained, check.ok), ("items[0].item_id|item_name", None, False))

    def test_valor_presente_que_nao_atende_aparece_no_obtido(self):
        (check,) = check_items([{"item_id|item_name": "re:^SKU_\\d+$"}], [{"item_id": "abc"}])
        self.assertEqual((check.obtained, check.ok), ("item_id=abc", False))

    def test_tambem_vale_no_nivel_do_evento(self):
        report = auditar({"purchase": "currency=USD, promotion_id=P_1, transaction_id=T_1"},
                         {"purchase": {"coupon|promotion_id": "[preenchido]"}})
        self.assertEqual(report.results[0].status, VariantStatus.OK)
        self.assertEqual(report.results[0].checks[0].obtained, "promotion_id=P_1")


class TestSomaDosItens(unittest.TestCase):
    def soma(self, corpo: str):
        report = auditar({"view_cart": corpo}, {"view_cart": {"value": "[soma_itens]"}})
        (check,) = report.results[0].checks
        return check

    def test_value_igual_a_soma_de_price_vezes_quantity(self):
        check = self.soma(f"value=72.05, items=[{ITEM_1}, {ITEM_2}]")
        self.assertEqual((check.expected, check.obtained, check.ok), ("soma dos itens: 72.05", "72.05", True))

    def test_value_diferente_da_soma_diverge(self):
        check = self.soma(f"value=999.99, items=[{ITEM_1}, {ITEM_2}]")
        self.assertEqual((check.expected, check.ok), ("soma dos itens: 72.05", False))

    def test_value_com_frete_e_imposto_diverge(self):
        self.assertFalse(self.soma(f"value=76.49, items=[{ITEM_1}, {ITEM_2}]").ok)

    def test_margem_de_um_centavo(self):
        self.assertTrue(self.soma(f"value=72.06, items=[{ITEM_1}, {ITEM_2}]").ok)
        self.assertFalse(self.soma(f"value=72.07, items=[{ITEM_1}, {ITEM_2}]").ok)

    def test_quantity_ausente_vale_um(self):
        item = bundle_item(item_id="A", price="9.90")
        self.assertTrue(self.soma(f"value=19.8, items=[{item}, {item}]").ok)

    def test_item_sem_price_impede_a_soma_e_diz_por_que(self):
        check = self.soma("value=10, items=[" + bundle_item(item_id="A", quantity="1") + "]")
        self.assertEqual((check.expected, check.ok), ("soma dos itens (items[0].price ausente ou não numérico)", False))

    def test_sem_itens_diz_por_que(self):
        check = self.soma("value=10")
        self.assertEqual((check.expected, check.ok), ("soma dos itens (o evento não tem itens)", False))

    def test_value_com_virgula_nao_e_numero(self):
        self.assertFalse(self.soma(f"value=30,03, items=[{ITEM_1}]").ok)

    def test_no_export_do_ga4_sem_itens_fica_nao_exportado(self):
        from mobaile.services.report.audit import check_params

        (check,) = check_params({"value": "[soma_itens]"}, {"value": "72.05"}, frozenset({"value"}))
        self.assertEqual((check.exported, check.ok), (False, True))


class TestOsCatorzeEventos(unittest.TestCase):
    def test_todos_passam_com_os_parametros_do_documento(self):
        report = auditar(EVENTOS)
        self.assertEqual(len(report.results), 14)
        self.assertEqual({r.variant.event: r.status for r in report.results},
                         dict.fromkeys(EVENTOS, VariantStatus.OK))

    def test_erros_do_documento_que_a_spec_pega(self):
        casos = {
            "currency=USD, ": ("", "currency"),
            "currency=USD": ("currency=R$", "currency"),
            "transaction_id=T_12345, ": ("", "transaction_id"),
        }
        for trecho, (troca, campo) in casos.items():
            with self.subTest(trecho=trecho):
                corpo = "currency=USD, value=72.05, transaction_id=T_12345, " + f"items=[{ITEM_1}]"
                report = auditar({"purchase": corpo.replace(trecho, troca, 1)})
                self.assertIn(campo, divergencias(report)["purchase"])


if __name__ == "__main__":
    unittest.main()
