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
"""

from __future__ import annotations

from collections import OrderedDict
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
from mobaile.services.report.rules import display_expected, expand_spec, is_noise_event, value_matches

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


def _candidates(variant: Variant, events: list[TagEvent]) -> list[TagEvent]:
    exp = variant.expected
    candidates = [e for e in events if e.event_name == variant.event]
    if "flow_name" in exp:
        candidates = [e for e in candidates if value_matches(exp["flow_name"], e.params.get("flow_name"))]
    if "detail" in exp:
        candidates = [e for e in candidates if value_matches(exp["detail"], e.params.get("detail"))]
    if "screen_name" in exp:
        same_screen = [e for e in candidates if value_matches(exp["screen_name"], screen_of(e.params))]
        if same_screen:
            return same_screen
        # Disparou na tela certa (ga_screen) com screen_name divergente: vira erro
        # de screen_name. Em outra tela qualquer não é esta variação: fica como
        # não disparado e o evento vai para "fora da spec".
        return [e for e in candidates if value_matches(exp["screen_name"], e.params.get("ga_screen"))]
    return candidates


def audit_variant(variant: Variant, events: list[TagEvent]) -> VariantResult:
    pool = _candidates(variant, events)
    if not pool:
        return VariantResult(variant=variant, status=VariantStatus.MISSING)
    latest = pool[-1]
    checks = check_params(variant.expected, latest.params)
    current = _failures(checks)
    older_bad = [e for e in pool[:-1] if _failures(check_params(variant.expected, e.params)) - current]
    diffs = sorted({d for e in older_bad for d in _failures(check_params(variant.expected, e.params)) - current})
    ga_screen = latest.params.get("ga_screen")
    explicit = latest.params.get("screen_name")
    return VariantResult(
        variant=variant,
        status=VariantStatus.OK if all(c.ok for c in checks) else VariantStatus.ERROR,
        matched=latest,
        checks=checks,
        occurrences=len(pool),
        older_divergent=len(older_bad),
        older_divergences=diffs,
        ga_screen=ga_screen if explicit and ga_screen and ga_screen != explicit else None,
    )


def _covered(event: TagEvent, variants: list[Variant]) -> bool:
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


def find_extras(variants: list[Variant], events: list[TagEvent]) -> tuple[list[ExtraEvent], list[ExtraEvent]]:
    spec_flows = [v.expected["flow_name"] for v in variants if "flow_name" in v.expected]
    spec_screens = [v.expected["screen_name"] for v in variants if "screen_name" in v.expected]

    def in_flows(event: TagEvent) -> bool:
        return any(value_matches(flow, event.params.get("flow_name")) for flow in spec_flows)

    def in_screens(event: TagEvent) -> bool:
        screen = event.params.get("ga_screen") or screen_of(event.params)
        return any(value_matches(spec_screen, screen) for spec_screen in spec_screens)

    alerts = [e for e in events if e.event_name in ALERT_EVENTS and (in_flows(e) or in_screens(e))]
    # Evento já atribuído a uma variação, inclusive como erro, não é "fora da spec".
    assigned = {id(e) for v in variants for e in _candidates(v, events)}
    extras = [
        e for e in events
        if id(e) not in assigned
        and e.event_name not in ALERT_EVENTS
        and e.event_name not in IGNORED_EXTRA_EVENTS
        and not is_noise_event(e.event_name, e.params)
        and in_flows(e)
        and not _covered(e, variants)
    ]
    return _group(extras), _group(alerts)


def run_audit(
    spec: SpecTemplate,
    events: list[TagEvent],
    platform: str,
    log_stats: dict[str, int] | None = None,
) -> AuditReport:
    variants = expand_spec(spec)
    results = [audit_variant(v, events) for v in variants]
    extras, alerts = find_extras(variants, events)
    return AuditReport(
        spec=spec, platform=platform, results=results, log_stats=dict(log_stats or {}), extras=extras, alerts=alerts,
    )
