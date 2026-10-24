"""Regras puras da auditoria: normalização, placeholders e expansão da spec.

Portado do `tag_audit` sem mudar o comportamento (normalizers, spec_template e
o filtro de ruído do log_parser). Nada aqui faz I/O.

Valores aceitos nos parâmetros da spec:

- literal: ``app:pedido:home``;
- alternância, inteira ou em trecho: ``[0|1]``, ``app:pedido:[pessoal|empresa]:home``;
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
from collections.abc import Callable
from functools import lru_cache
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
# Uma regex só para todos os padrões de ruído: um `match` por nome, e não quinze.
_NOISE = re.compile("|".join(f"(?:{pattern})" for pattern in NOISE_EVENT_PATTERNS), re.IGNORECASE)
_COLON_SPACING = re.compile(r"\s*:\s*")
_SDK_SUFFIX = re.compile(r"\(_[a-zA-Z0-9]+\)$")


# --------------------------------------------------------------- normalização


def clean_colon_spacing(value: Any) -> str:
    """``app: pedido: home `` vira ``app:pedido:home``."""
    if not isinstance(value, str):
        return str(value)
    value = value.strip()
    return _COLON_SPACING.sub(":", value) if ":" in value else value


def strip_event_suffixes(event_name: Any) -> str:
    """Tira o sufixo técnico do SDK: ``screen_view(_vs)`` vira ``screen_view``."""
    if not isinstance(event_name, str):
        return str(event_name)
    return _strip_sdk_suffix(event_name.strip())


def strip_param_key_suffixes(key: Any) -> str:
    """``ga_screen(_sn)`` vira ``ga_screen``."""
    if not isinstance(key, str):
        return str(key)
    return _strip_sdk_suffix(key.strip())


def _strip_sdk_suffix(text: str) -> str:
    return _SDK_SUFFIX.sub("", text) if text.endswith(")") else text


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
    return bool(_NOISE.match(event_name) or _NOISE.match(clean_name))


# ---------------------------------------------------------------- placeholders


def value_matches(expected: Any, obtained: Any) -> bool:
    """O valor do log atende o valor da spec (com placeholders)?"""
    if obtained is None:
        return False
    got = str(obtained).strip()
    if not got:
        return False
    return _compiled(str(expected).strip())[1](got)


def literal_value(expected: Any) -> str | None:
    """O texto exato que o valor da spec exige, ou `None` se ele tem placeholder.

    Valor literal casa por igualdade com o valor do log sem espaços nas pontas:
    é o que deixa a auditoria buscar por dicionário em vez de varrer o log.
    """
    return _compiled(str(expected).strip())[0]


@lru_cache(maxsize=8192)
def _compiled(exp: str) -> tuple[str | None, Callable[[str], bool]]:
    """(texto literal ou `None`, função que confere o valor do log), uma vez por valor.

    A auditoria compara o mesmo valor da spec com milhares de eventos; montar e
    procurar a regex a cada comparação era o grosso do custo.
    """
    if exp == FILLED:
        return None, _always
    if exp in (NUMBER, DATE):
        pattern = re.compile(_TOKEN_REGEX[exp])
    elif exp.startswith("re:"):
        pattern = re.compile(exp[3:])
    elif _TOKEN.search(exp):
        pattern = re.compile(_token_pattern(exp))
    else:
        return exp, exp.__eq__
    return None, lambda got: pattern.fullmatch(got) is not None


def _always(_got: str) -> bool:
    return True


def _token_pattern(exp: str) -> str:
    """Regex de um valor com trechos ``[a|b]``, ``[numero]``, ``[data]`` ou ``[preenchido]``."""
    pattern, last = "", 0
    for match in _TOKEN.finditer(exp):
        pattern += re.escape(exp[last:match.start()])
        token = match.group(0)
        if token in _TOKEN_REGEX:
            pattern += _TOKEN_REGEX[token]
        else:
            pattern += "(?:" + "|".join(re.escape(o.strip()) for o in token[1:-1].split("|")) + ")"
        last = match.end()
    return pattern + re.escape(exp[last:])


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
