"""Auditoria em log grande: mesmo resultado da varredura simples, em tempo de app.

O índice de eventos (`EventIndex`) e os candidatos calculados uma vez trocaram a
varredura do log inteiro por variação. O oráculo aqui é a versão anterior,
escrita do jeito direto (uma passada pelo log por variação), comparada com a
atual em cenários sintéticos com milhares de eventos. O cenário vem de
`tools/bench_report.py`, o mesmo das medições em docs/DESEMPENHO_RELATORIO.md.
"""

from __future__ import annotations

import importlib.util
import time
import unittest
from pathlib import Path
from typing import Any

from mobaile.domain.report import SpecTemplate, TagEvent, Variant
from mobaile.services.report.audit import (
    ALERT_EVENTS,
    IGNORED_EXTRA_EVENTS,
    EventIndex,
    _candidates,
    _group,
    audit_variant,
    find_extras,
    run_audit,
    screen_of,
)
from mobaile.services.report.firebase_log import _split_top_level, events_from_items
from mobaile.services.report.rules import expand_spec, is_noise_event, literal_value, value_matches

_BENCH = Path(__file__).resolve().parents[3] / "tools" / "bench_report.py"


def _bench():
    spec = importlib.util.spec_from_file_location("bench_report", _BENCH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bench = _bench()


# ------------------------------------------------- oráculo: a versão anterior


def candidatos_simples(variant: Variant, events: list[TagEvent]) -> list[TagEvent]:
    exp = variant.expected
    found = [e for e in events if e.event_name == variant.event]
    if "flow_name" in exp:
        found = [e for e in found if value_matches(exp["flow_name"], e.params.get("flow_name"))]
    if "detail" in exp:
        found = [e for e in found if value_matches(exp["detail"], e.params.get("detail"))]
    if "screen_name" in exp:
        same = [e for e in found if value_matches(exp["screen_name"], screen_of(e.params))]
        return same or [e for e in found if value_matches(exp["screen_name"], e.params.get("ga_screen"))]
    return found


def coberto_simples(event: TagEvent, variants: list[Variant]) -> bool:
    for variant in variants:
        exp = variant.expected
        if event.event_name != variant.event:
            continue
        if "flow_name" in exp and not value_matches(exp["flow_name"], event.params.get("flow_name")):
            continue
        if "screen_name" in exp and not value_matches(exp["screen_name"], screen_of(event.params)):
            continue
        if "detail" in exp and not value_matches(exp["detail"], event.params.get("detail")):
            continue
        return True
    return False


def fora_da_spec_simples(variants: list[Variant], events: list[TagEvent]) -> tuple[list[Any], list[Any]]:
    flows = [v.expected["flow_name"] for v in variants if "flow_name" in v.expected]
    screens = [v.expected["screen_name"] for v in variants if "screen_name" in v.expected]

    def in_flows(e):
        return any(value_matches(f, e.params.get("flow_name")) for f in flows)

    def in_screens(e):
        screen = e.params.get("ga_screen") or screen_of(e.params)
        return any(value_matches(s, screen) for s in screens)

    alerts = [e for e in events if e.event_name in ALERT_EVENTS and (in_flows(e) or in_screens(e))]
    assigned = {id(e) for v in variants for e in candidatos_simples(v, events)}
    extras = [
        e for e in events
        if id(e) not in assigned and e.event_name not in ALERT_EVENTS and e.event_name not in IGNORED_EXTRA_EVENTS
        and not is_noise_event(e.event_name, e.params) and in_flows(e) and not coberto_simples(e, variants)
    ]
    return _group(extras), _group(alerts)


def cenario(eventos: int, cards: int, fluxos: int, seed: int) -> tuple[SpecTemplate, list[TagEvent]]:
    spec = bench.build_spec(cards, fluxos, None)
    events, _ = events_from_items(bench.build_log(spec, eventos, seed=seed), "android")
    return SpecTemplate.from_dict(spec), events


class TestParidadeComAVarreduraSimples(unittest.TestCase):
    def test_candidatos_iguais_em_cenarios_sorteados(self):
        for seed in (1, 2, 3):
            spec, events = cenario(3000, 40, 3, seed)
            index = EventIndex(events)
            for variant in expand_spec(spec):
                with self.subTest(seed=seed, evento=variant.event, fluxo=variant.flow):
                    self.assertEqual(
                        [id(e) for e in _candidates(variant, index)],
                        [id(e) for e in candidatos_simples(variant, events)],
                    )

    def test_fora_da_spec_e_alertas_iguais(self):
        for seed in (4, 5):
            spec, events = cenario(3000, 40, 3, seed)
            variants = expand_spec(spec)
            esperado = fora_da_spec_simples(variants, events)
            for obtido in (find_extras(variants, events), run_audit(spec, events, "android")):
                if not isinstance(obtido, tuple):
                    obtido = (obtido.extras, obtido.alerts)
                with self.subTest(seed=seed):
                    self.assertEqual([e.to_dict() for e in obtido[0]], [e.to_dict() for e in esperado[0]])
                    self.assertEqual([e.to_dict() for e in obtido[1]], [e.to_dict() for e in esperado[1]])

    def test_audit_variant_aceita_lista_ou_indice(self):
        spec, events = cenario(1000, 12, 2, 6)
        index = EventIndex(events)
        for variant in expand_spec(spec):
            self.assertEqual(audit_variant(variant, events), audit_variant(variant, index))


class TestPecasNovas(unittest.TestCase):
    def test_valor_literal_e_so_o_sem_placeholder(self):
        self.assertEqual(literal_value(" app:pedido:home "), "app:pedido:home")
        self.assertEqual(literal_value(1), "1")
        for coringa in ("[numero]", "[data]", "[preenchido]", "re:a.*", "[0|1]", "click:[numero]-x"):
            with self.subTest(valor=coringa):
                self.assertIsNone(literal_value(coringa))

    def test_divisao_do_bundle_respeita_colchetes_e_chaves(self):
        self.assertEqual(_split_top_level("a=1, b=2"), ["a=1", " b=2"])
        self.assertEqual(_split_top_level("a=1, items=[Bundle[{x=1, y=2}]], b=3"),
                         ["a=1", " items=[Bundle[{x=1, y=2}]]", " b=3"])
        self.assertEqual(_split_top_level("a=1,,b=2, "), ["a=1", "", "b=2"])
        self.assertEqual(_split_top_level(""), [])

    def test_indice_ignora_valor_vazio_como_value_matches(self):
        vazio = TagEvent(id=1, event_name="e", params={"flow_name": "  "})
        cheio = TagEvent(id=2, event_name="e", params={"flow_name": " f "})
        self.assertEqual(list(EventIndex([vazio, cheio]).select("e", [("flow_name", "f")])), [cheio])
        self.assertEqual(list(EventIndex([vazio, cheio]).select("e", [("flow_name", "")])), [])


class TestTempoDeAuditoria(unittest.TestCase):
    """Guarda contra a volta da varredura O(eventos x variações).

    20 mil eventos e 1.800 variações levavam 2,5 s antes do índice e levam
    0,07 s depois (Apple M4 Pro). No runner do CI, com cobertura, os mesmos
    0,07 s viram mais de 1 s, então o limite não é em segundos: é medido em
    passadas simples pelo log, cronometradas na mesma máquina. A auditoria
    custa umas 60 passadas e a regressão custaria uma por variação (1.800).
    O teto de 400 deixa folga de 6x para oscilação e pega a regressão com 4x.
    """

    PASSADAS_MAXIMAS = 400

    def test_log_grande_audita_rapido(self):
        spec, events = cenario(20000, 200, 6, 7)
        amostra = expand_spec(spec)[::60]
        start = time.perf_counter()
        for variant in amostra:
            candidatos_simples(variant, events)
        passada = (time.perf_counter() - start) / len(amostra)

        start = time.perf_counter()
        report = run_audit(spec, events, "android")
        elapsed = time.perf_counter() - start
        self.assertEqual(report.total, 1800)
        self.assertLess(
            elapsed / passada, self.PASSADAS_MAXIMAS,
            f"auditoria levou {elapsed:.2f} s, {elapsed / passada:.0f} passadas de {passada * 1000:.1f} ms",
        )


if __name__ == "__main__":
    unittest.main()
