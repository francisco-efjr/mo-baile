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
    ITEMS_SUM,
    ITEMS_SUM_TOLERANCE,
    decimal_or_none,
    display_expected,
    expand_spec,
    format_decimal,
    is_noise_event,
    items_sum,
    key_alternatives,
    literal_value,
    value_matches,
)

ALERT_EVENTS = ("app_exception", "error_view")
IGNORED_EXTRA_EVENTS = ("user_engagement", "session_start", "app_clear_data")


def screen_of(params: dict[str, Any]) -> Any:
    return params.get("screen_name") or params.get("ga_screen")


def is_exported(key: str, exported: frozenset[str] | None) -> bool:
    """O log traz este parâmetro? Num logcat (`exported` None), sempre."""
    if exported is None:
        return True
    if "|" in key:
        return any(is_exported(alt, exported) for alt in key_alternatives(key))
    if key == "screen_name":
        return "screen_name" in exported or "ga_screen" in exported
    return key in exported


def check_params(
    expected: dict[str, Any], params: dict[str, Any], exported: frozenset[str] | None = None,
) -> list[ParamCheck]:
    """Confere cada parâmetro da spec. O que o export não traz vira "não exportado"."""
    checks: list[ParamCheck] = []
    for key, exp in expected.items():
        # A soma depende dos itens, que o export do GA4 nunca traz.
        sum_without_items = _is_items_sum(exp) and not is_exported("items", exported)
        if sum_without_items or not is_exported(key, exported):
            if key == "items" and isinstance(exp, list):
                checks.extend(
                    ParamCheck(field=f"items[{i}].{k}", expected=display_expected(v), obtained=None, ok=True, exported=False)
                    for i, rule in enumerate(_item_rules(exp))
                    for k, v in rule.items()
                )
            else:
                checks.append(ParamCheck(field=key, expected=display_expected(exp), obtained=None, ok=True, exported=False))
            continue
        if key == "items" and isinstance(exp, list):
            checks.extend(check_items(exp, params.get("items")))
            continue
        checks.append(check_value(key, key, exp, params, items=params.get("items"), event_level=True))
    return checks


def _is_items_sum(expected: Any) -> bool:
    return isinstance(expected, str) and expected.strip() == ITEMS_SUM


def check_value(
    field: str, key: str, expected: Any, source: dict[str, Any], *, items: Any = None, event_level: bool = False,
) -> ParamCheck:
    """Um parâmetro da spec contra o evento ou o item do log.

    - Chave com ``|`` (``item_id|item_name``) passa se uma das alternativas
      atende. O obtido mostra qual delas veio (``item_name=Tee``).
    - ``[soma_itens]`` compara o número com a soma de ``price * quantity`` dos
      itens do evento, com margem de um centavo.
    """
    if _is_items_sum(expected):
        if not event_level:
            return ParamCheck(field=field, expected="soma dos itens (só vale no evento)",
                              obtained=source.get(key), ok=False)
        return _check_items_sum(field, source.get(key), items)
    alternatives = key_alternatives(key)
    if len(alternatives) == 1:
        got = screen_of(source) if event_level and key == "screen_name" else source.get(key)
        return ParamCheck(field=field, expected=display_expected(expected), obtained=got,
                          ok=value_matches(expected, got))
    present: str | None = None
    for alt in alternatives:
        got = source.get(alt)
        if value_matches(expected, got):
            return ParamCheck(field=field, expected=display_expected(expected), obtained=f"{alt}={got}", ok=True)
        if present is None and got not in (None, ""):
            present = f"{alt}={got}"
    return ParamCheck(field=field, expected=display_expected(expected), obtained=present, ok=False)


def _check_items_sum(field: str, got: Any, items: Any) -> ParamCheck:
    total, reason = items_sum(items)
    if total is None:
        return ParamCheck(field=field, expected=f"soma dos itens ({reason})", obtained=got, ok=False)
    value = decimal_or_none(got)
    ok = value is not None and abs(value - total) <= ITEMS_SUM_TOLERANCE
    return ParamCheck(field=field, expected=f"soma dos itens: {format_decimal(total)}", obtained=got, ok=ok)


def _item_rules(expected_items: list[Any]) -> list[dict[str, Any]]:
    return [rule for rule in expected_items if isinstance(rule, dict)] or [{}]


def check_items(expected_items: list[Any], got_items: Any) -> list[ParamCheck]:
    """Confere todos os itens do evento, e não só o primeiro.

    O item ``i`` do log segue o item ``i`` da spec. Os itens além dos que a spec
    lista seguem o último item dela. Assim, uma spec com um item só vale para
    todos os itens do evento. Uma spec com mais itens do que o log aponta os que
    faltam. Sem itens no log, cada campo da spec aparece sem valor.
    """
    rules = _item_rules(expected_items)
    got = [item for item in got_items if isinstance(item, dict)] if isinstance(got_items, list) else []
    checks: list[ParamCheck] = []
    for i in range(max(len(rules), len(got))):
        rule = rules[min(i, len(rules) - 1)]
        item = got[i] if i < len(got) else {}
        checks.extend(
            check_value(f"items[{i}].{item_key}", item_key, item_exp, item) for item_key, item_exp in rule.items()
        )
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


def _candidates(variant: Variant, events: EventIndex, exported: frozenset[str] | None = None) -> Sequence[TagEvent]:
    exp = variant.expected
    # Campo que o export não traz não recorta: ele não está em nenhum evento.
    base = [(key, exp[key]) for key in ("flow_name", "detail") if key in exp and is_exported(key, exported)]
    if "screen_name" not in exp or not is_exported("screen_name", exported):
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


def _judge(variant: Variant, pool: Sequence[TagEvent], exported: frozenset[str] | None = None) -> VariantResult:
    """Resultado da variação a partir dos disparos dela, em ordem de horário."""
    if not pool:
        return VariantResult(variant=variant, status=VariantStatus.MISSING)
    latest = pool[-1]
    others: Sequence[TagEvent] = pool[:-1]
    if exported is not None:
        # Export do GA4: as linhas são combinações, sem "mais recente". Vale a
        # última que atende tudo, se houver; as outras viram aviso.
        matching = [e for e in pool if not _failures(check_params(variant.expected, e.params, exported))]
        if matching:
            latest = matching[-1]
            others = [e for e in pool if e is not latest]
    checks = check_params(variant.expected, latest.params, exported)
    current = _failures(checks)
    # Cada disparo anterior é conferido uma vez só.
    older_bad = [
        diff for diff in (_failures(check_params(variant.expected, e.params, exported)) - current for e in others)
        if diff
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
    log_stats: dict[str, Any] | None = None,
) -> AuditReport:
    variants = expand_spec(spec)
    index = EventIndex(events)
    # Export do GA4: só os parâmetros que vieram no arquivo são conferidos.
    listed = (log_stats or {}).get("exportados")
    exported = frozenset(listed) if listed is not None else None
    pools = [_candidates(v, index, exported) for v in variants]
    results = [_judge(v, pool, exported) for v, pool in zip(variants, pools, strict=True)]
    extras, alerts = find_extras(variants, events, pools)
    return AuditReport(
        spec=spec, platform=platform, results=results, log_stats=dict(log_stats or {}), extras=extras, alerts=alerts,
        first_event=events[0] if events else None, last_event=events[-1] if events else None,
    )
