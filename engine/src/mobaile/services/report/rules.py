"""Regras puras da auditoria: normalização, placeholders e expansão da spec.

Portado do `tag_audit` sem mudar o comportamento (normalizers, spec_template e
o filtro de ruído do log_parser). Nada aqui faz I/O.

Valores aceitos nos parâmetros da spec:

- literal: ``app:credito:home``;
- alternância, inteira ou em trecho: ``[0|1]``, ``app:credito:[pessoal|investimentos]:home``;
- ``[numero]``, ``[data]`` (dd/mm/aaaa) e ``[preenchido]`` (qualquer valor não
  vazio), inteiros ou em trecho: ``click:[numero]-parcela-com-seguro``;
- ``re:<regex>``: expressão regular completa;
- ``items``: lista de objetos; cada campo do primeiro item segue as mesmas regras.

``{fluxo}`` é trocado por cada chave de ``fluxos``; ``params_por_fluxo``
sobrescreve valores de um fluxo.
"""

from __future__ import annotations

import json
import re
from typing import Any

from mobaile.domain.report import SpecCard, SpecTemplate, Variant

NUMBER = "[numero]"
DATE = "[data]"
FILLED = "[preenchido]"

_TOKEN_REGEX = {NUMBER: r"-?\d+(?:[.,]\d+)?", DATE: r"\d{2}/\d{2}/\d{4}", FILLED: r".+"}
# Trechos "[a|b]" (alternância) ou "[numero]" / "[data]" / "[preenchido]" dentro de um valor.
_TOKEN = re.compile(r"\[[^\[\]]*\|[^\[\]]*\]|\[numero\]|\[data\]|\[preenchido\]")

# Eventos que são telemetria interna do SDK, e não tagueamento do produto.
NOISE_EVENT_PATTERNS: tuple[str, ...] = (
    r"^session_start.*",
    r"^app_clear_data.*",
    r"^app_exception.*",
    r"^CfgFetch.*",
    r"^fiam_impression.*",
    r"^firebase_in_app_message_impression.*",
    r"^CAROUSEL_.*",
    r"^COOKIES_.*",
    r"^ITEM_.*",
    r"^LS_.*",
    r"^MOBILE_DATA_.*",
    r"^RECOMMENDATION_.*",
    r"^WP_MIX_.*",
    r"^smartstream_.*",
    r"^swipe_.*",
)


# --------------------------------------------------------------- normalização


def clean_colon_spacing(value: Any) -> str:
    """``app: credito: home `` vira ``app:credito:home``."""
    if not isinstance(value, str):
        return str(value)
    return re.sub(r"\s*:\s*", ":", value.strip())


def strip_event_suffixes(event_name: Any) -> str:
    """Tira o sufixo técnico do SDK: ``screen_view(_vs)`` vira ``screen_view``."""
    if not isinstance(event_name, str):
        return str(event_name)
    return re.sub(r"\(_[a-zA-Z0-9]+\)$", "", event_name.strip())


def strip_param_key_suffixes(key: Any) -> str:
    """``ga_screen(_sn)`` vira ``ga_screen``."""
    if not isinstance(key, str):
        return str(key)
    return re.sub(r"\(_[a-zA-Z0-9]+\)$", "", key.strip())


def is_noise_event(event_name: str, params: dict[str, Any]) -> bool:
    """Evento automático do SDK, que não entra em "fora da spec"."""
    if not event_name:
        return True
    origin = params.get("ga_event_origin") or params.get("_o")
    if origin in ("auto", "clx"):
        return True
    clean_name = strip_event_suffixes(event_name)
    if clean_name == "user_engagement" and origin != "app":
        return True
    return any(
        re.match(pattern, event_name, re.IGNORECASE) or re.match(pattern, clean_name, re.IGNORECASE)
        for pattern in NOISE_EVENT_PATTERNS
    )


# ---------------------------------------------------------------- placeholders


def value_matches(expected: Any, obtained: Any) -> bool:
    """O valor do log atende o valor da spec (com placeholders)?"""
    if obtained is None or str(obtained).strip() == "":
        return False
    got = str(obtained).strip()
    exp = str(expected).strip()
    if exp == NUMBER:
        return re.fullmatch(_TOKEN_REGEX[NUMBER], got) is not None
    if exp == DATE:
        return re.fullmatch(_TOKEN_REGEX[DATE], got) is not None
    if exp == FILLED:
        return True
    if exp.startswith("re:"):
        return re.fullmatch(exp[3:], got) is not None
    if _TOKEN.search(exp):
        pattern, last = "", 0
        for match in _TOKEN.finditer(exp):
            pattern += re.escape(exp[last:match.start()])
            token = match.group(0)
            if token in _TOKEN_REGEX:
                pattern += _TOKEN_REGEX[token]
            else:
                pattern += "(?:" + "|".join(re.escape(o.strip()) for o in token[1:-1].split("|")) + ")"
            last = match.end()
        pattern += re.escape(exp[last:])
        return re.fullmatch(pattern, got) is not None
    return got == exp


def display_expected(expected: Any) -> str:
    """Texto curto do valor esperado, para relatório."""
    text = str(expected)
    return text[3:] if text.startswith("re:") else text


# ------------------------------------------------------------------- expansão


def _subst(value: Any, flow: str | None) -> Any:
    if flow is None:
        return value
    if isinstance(value, str):
        return value.replace("{fluxo}", flow)
    if isinstance(value, list):
        return [_subst(v, flow) for v in value]
    if isinstance(value, dict):
        return {k: _subst(v, flow) for k, v in value.items()}
    return value


def _merge(base: dict[str, Any], extra: dict[str, Any]) -> dict[str, Any]:
    out = dict(base)
    for key, value in extra.items():
        if key == "items" and isinstance(value, list) and isinstance(out.get(key), list) and out[key] and value:
            out[key] = [{**out[key][0], **value[0]}]
        else:
            out[key] = value
    return out


def card_is_per_flow(card: SpecCard, spec: SpecTemplate) -> bool:
    if card.por_fluxo is not None:
        return card.por_fluxo and bool(spec.fluxos)
    return bool(spec.fluxos) and "{fluxo}" in json.dumps(card.to_dict(), ensure_ascii=False)


def expand_card(index: int, card: SpecCard, spec: SpecTemplate) -> list[Variant]:
    flows: list[str | None] = list(spec.fluxos) if card_is_per_flow(card, spec) else [None]
    variations = card.variacoes or [{}]
    out: list[Variant] = []
    for flow in flows:
        note = card.obs.get(flow) if isinstance(card.obs, dict) else card.obs
        for variation in variations:
            params = _merge(card.params, variation)
            if flow is not None and flow in card.params_por_fluxo:
                params = _merge(params, card.params_por_fluxo[flow])
            out.append(
                Variant(
                    card_index=index,
                    flow=flow,
                    event=_subst(card.evento, flow),
                    expected=_subst(params, flow),
                    note=note,
                )
            )
    return out


def expand_spec(spec: SpecTemplate) -> list[Variant]:
    out: list[Variant] = []
    for index, card in enumerate(spec.cards):
        out.extend(expand_card(index, card, spec))
    return out
