"""Auditoria por variação (card x fluxo x variação), parâmetro a parâmetro.

Portado do `tag_audit` (core/variant_audit) sem mudar as regras:

- Candidatos: mesmo evento, ``flow_name`` e ``detail`` compatíveis, na tela da
  spec (``screen_name`` explícito ou, na falta, ``ga_screen``). Se só houver
  disparos com ``ga_screen`` na tela certa e ``screen_name`` diferente, eles
  viram ERRO de ``screen_name``.
- O disparo mais recente é o avaliado (estado atual do app). Disparos
  anteriores com divergência diferente aparecem como aviso.
- Sem candidato: não disparado. Com candidato e algum parâmetro divergente: erro.
- Eventos dos fluxos da spec que nenhuma variação cobre vão para "fora da
  spec"; ``app_exception`` e ``error_view`` nas telas da spec viram alertas.

Desempenho: os eventos são indexados por nome e, sob demanda, pelo valor exato
de ``flow_name``, ``detail`` e da tela. Cada variação começa pelo recorte mais
estreito do índice e só confere placeholders nele, em vez de varrer o log
inteiro; os candidatos de cada variação são calculados uma vez e servem tanto
para o resultado quanto para "fora da spec" (ver docs/DESEMPENHO_RELATORIO.md).
"""

from __future__ import annotations

from collections import OrderedDict
from collections.abc import Callable, Sequence
from typing import Any

from mobaile.domain.report import (
    AuditReport,
    ExtraEvent,
    ParamCheck,
    SpecTemplate,
    TagEvent,
    Variant,
    VariantResult,
    VariantStatus,
)
from mobaile.services.report.rules import (
    display_expected,
    expand_spec,
    is_noise_event,
    literal_value,
    value_matches,
)

ALERT_EVENTS = ("app_exception", "error_view")
IGNORED_EXTRA_EVENTS = ("user_engagement", "session_start", "app_clear_data")


def screen_of(params: dict[str, Any]) -> Any:
    return params.get("screen_name") or params.get("ga_screen")


def check_params(expected: dict[str, Any], params: dict[str, Any]) -> list[ParamCheck]:
    checks: list[ParamCheck] = []
    for key, exp in expected.items():
        if key == "items" and isinstance(exp, list):
            got_items = params.get("items")
            first = (
                got_items[0]
                if isinstance(got_items, list) and got_items and isinstance(got_items[0], dict)
                else {}
            )
            exp_first = exp[0] if exp and isinstance(exp[0], dict) else {}
            for item_key, item_exp in exp_first.items():
                got = first.get(item_key)
                checks.append(ParamCheck(
                    field=f"items[0].{item_key}", expected=display_expected(item_exp),
                    obtained=got, ok=value_matches(item_exp, got),
                ))
            continue
        got = screen_of(params) if key == "screen_name" else params.get(key)
        checks.append(ParamCheck(field=key, expected=display_expected(exp), obtained=got, ok=value_matches(exp, got)))
    return checks


def _failures(checks: list[ParamCheck]) -> set[str]:
    return {f"{c.field}={c.obtained}" for c in checks if not c.ok}


# Campos pelos quais uma variação recorta os eventos.
_FIELDS: dict[str, Callable[[dict[str, Any]], Any]] = {
    "flow_name": lambda p: p.get("flow_name"),
    "detail": lambda p: p.get("detail"),
    "screen": screen_of,
    "ga_screen": lambda p: p.get("ga_screen"),
}


class EventIndex:
    """Eventos do log por nome e, sob demanda, por valor exato de um campo.

    As listas devolvidas são do índice e seguem a ordem do log: quem recebe só lê.
    """

    def __init__(self, events: Sequence[TagEvent]) -> None:
        by_name: dict[str, list[TagEvent]] = {}
        for event in events:
            by_name.setdefault(event.event_name, []).append(event)
        self._by_name = {name: tuple(found) for name, found in by_name.items()}
        self._by_value: dict[tuple[str, str], dict[str, tuple[TagEvent, ...]]] = {}

    def named(self, name: str) -> Sequence[TagEvent]:
        return self._by_name.get(name, ())

    def _values(self, name: str, field: str) -> dict[str, tuple[TagEvent, ...]]:
        index = self._by_value.get((name, field))
        if index is None:
            getter = _FIELDS[field]
            grouped: dict[str, list[TagEvent]] = {}
            for event in self.named(name):
                got = getter(event.params)
                # Mesma normalização de `value_matches`: valor vazio nunca atende.
                key = None if got is None else str(got).strip()
                if key:
                    grouped.setdefault(key, []).append(event)
            index = self._by_value[(name, field)] = {key: tuple(found) for key, found in grouped.items()}
        return index

    def select(self, name: str, filters: list[tuple[str, Any]]) -> Sequence[TagEvent]:
        """Eventos ``name`` que atendem todos os filtros (campo, valor da spec), na ordem do log.

        Começa pelo valor literal mais seletivo, buscado no índice, e confere os
        demais filtros só nesse recorte.
        """
        pool: Sequence[TagEvent] = self.named(name)
        start = None
        for position, (field, expected) in enumerate(filters):
            literal = literal_value(expected)
            if literal is not None:
                found = self._values(name, field).get(literal, ())
                if start is None or len(found) < len(pool):
                    pool, start = found, position
        for position, (field, expected) in enumerate(filters):
            if position != start and pool:
                getter = _FIELDS[field]
                pool = [e for e in pool if value_matches(expected, getter(e.params))]
        return pool


def _candidates(variant: Variant, events: EventIndex) -> Sequence[TagEvent]:
    exp = variant.expected
    base = [(key, exp[key]) for key in ("flow_name", "detail") if key in exp]
    if "screen_name" not in exp:
        return events.select(variant.event, base)
    same_screen = events.select(variant.event, [*base, ("screen", exp["screen_name"])])
    if same_screen:
        return same_screen
    # Disparou na tela certa (ga_screen) com screen_name divergente: vira erro
    # de screen_name. Em outra tela qualquer não é esta variação: fica como
    # não disparado e o evento vai para "fora da spec".
    return events.select(variant.event, [*base, ("ga_screen", exp["screen_name"])])


def audit_variant(variant: Variant, events: Sequence[TagEvent] | EventIndex) -> VariantResult:
    index = events if isinstance(events, EventIndex) else EventIndex(events)
    return _judge(variant, _candidates(variant, index))


def _judge(variant: Variant, pool: Sequence[TagEvent]) -> VariantResult:
    """Resultado da variação a partir dos disparos dela, em ordem de horário."""
    if not pool:
        return VariantResult(variant=variant, status=VariantStatus.MISSING)
    latest = pool[-1]
    checks = check_params(variant.expected, latest.params)
    current = _failures(checks)
    # Cada disparo anterior é conferido uma vez só.
    older_bad = [
        diff for diff in (_failures(check_params(variant.expected, e.params)) - current for e in pool[:-1]) if diff
    ]
    ga_screen = latest.params.get("ga_screen")
    explicit = latest.params.get("screen_name")
    return VariantResult(
        variant=variant,
        status=VariantStatus.OK if all(c.ok for c in checks) else VariantStatus.ERROR,
        matched=latest,
        checks=checks,
        occurrences=len(pool),
        older_divergent=len(older_bad),
        older_divergences=sorted(set().union(*older_bad)),
        ga_screen=ga_screen if explicit and ga_screen and ga_screen != explicit else None,
    )


def _any_matcher(expected: list[Any]) -> Callable[[Any], bool]:
    """Confere um valor do log contra uma lista de valores da spec, lembrando a resposta.

    O log repete poucos valores de fluxo e de tela em milhares de eventos;
    `value_matches` só depende do texto sem espaços nas pontas, que vira a chave.
    """
    patterns = list(dict.fromkeys(str(value).strip() for value in expected))
    memo: dict[str | None, bool] = {}

    def check(obtained: Any) -> bool:
        key = None if obtained is None else str(obtained).strip()
        hit = memo.get(key)
        if hit is None:
            hit = memo[key] = any(value_matches(pattern, key) for pattern in patterns)
        return hit

    return check


def _group(events: list[TagEvent]) -> list[ExtraEvent]:
    groups: OrderedDict[tuple[Any, ...], ExtraEvent] = OrderedDict()
    for event in events:
        p = event.params
        key = (event.event_name, screen_of(p), p.get("flow_name"), p.get("component"), p.get("detail"))
        if key not in groups:
            groups[key] = ExtraEvent(
                event=event.event_name,
                screen=_text_or_none(key[1]),
                flow_name=_text_or_none(key[2]),
                component=_text_or_none(key[3]),
                detail=_text_or_none(key[4]),
            )
        groups[key].count += 1
    return list(groups.values())


def _text_or_none(value: Any) -> str | None:
    return None if value is None else str(value)


def find_extras(
    variants: list[Variant],
    events: Sequence[TagEvent],
    pools: Sequence[Sequence[TagEvent]] | None = None,
) -> tuple[list[ExtraEvent], list[ExtraEvent]]:
    """Eventos "fora da spec" e alertas. ``pools`` são os candidatos de cada variação, se já calculados."""
    in_flows = _any_matcher([v.expected["flow_name"] for v in variants if "flow_name" in v.expected])
    in_screens = _any_matcher([v.expected["screen_name"] for v in variants if "screen_name" in v.expected])

    def related(event: TagEvent) -> bool:
        return in_flows(event.params.get("flow_name")) or in_screens(
            event.params.get("ga_screen") or screen_of(event.params)
        )

    alerts = [e for e in events if e.event_name in ALERT_EVENTS and related(e)]
    if pools is None:
        index = EventIndex(events)
        pools = [_candidates(v, index) for v in variants]
    # Evento já atribuído a uma variação, inclusive como erro, não é "fora da spec".
    # Isso também cobre o evento que casa com evento, fluxo, tela e detail de
    # alguma variação: ele está entre os candidatos dela.
    assigned = {id(e) for pool in pools for e in pool}
    extras = [
        e for e in events
        if id(e) not in assigned
        and e.event_name not in ALERT_EVENTS
        and e.event_name not in IGNORED_EXTRA_EVENTS
        and in_flows(e.params.get("flow_name"))
        and not is_noise_event(e.event_name, e.params)
    ]
    return _group(extras), _group(alerts)


def run_audit(
    spec: SpecTemplate,
    events: list[TagEvent],
    platform: str,
    log_stats: dict[str, int] | None = None,
) -> AuditReport:
    variants = expand_spec(spec)
    index = EventIndex(events)
    pools = [_candidates(v, index) for v in variants]
    results = [_judge(v, pool) for v, pool in zip(variants, pools, strict=True)]
    extras, alerts = find_extras(variants, events, pools)
    return AuditReport(
        spec=spec, platform=platform, results=results, log_stats=dict(log_stats or {}), extras=extras, alerts=alerts,
        first_event=events[0] if events else None, last_event=events[-1] if events else None,
    )
