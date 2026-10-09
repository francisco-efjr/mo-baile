"""Modelos da auditoria de tagueamento (aba Relatório).

O núcleo veio do `tag_audit` (projeto bold-kepler): uma spec-modelo com os
cards do Figma é expandida em variações (card x fluxo x variação), e cada
variação é procurada no log de eventos do Firebase Analytics. Aqui ficam só os
tipos e a validação da spec, sem I/O; as regras de casamento moram em
`services/report`.

O `tag_audit` usava Pydantic. O motor não tem essa dependência e o app nativo
roda no Python do sistema, então os modelos viraram dataclasses com validação
explícita: spec malformada vira `InvalidInputError` com a posição do problema,
e não um erro interno.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

from mobaile.domain.errors import InvalidInputError

PLATFORMS: tuple[str, ...] = ("android", "ios")


class VariantStatus(str, Enum):
    """Resultado de uma variação. Os valores são os do contrato RPC."""

    OK = "ok"
    ERROR = "error"
    MISSING = "missing"


@dataclass(frozen=True)
class OcrLine:
    """Uma linha de texto lida de um print.

    Caixa normalizada de 0 a 1, com `y` contado a partir do topo, e a confiança
    do reconhecimento. É o formato que o leitor de cards espera de qualquer
    OCR, não só do Vision.
    """

    t: str
    x: float
    y: float
    w: float
    h: float
    c: float = 1.0


@dataclass
class SpecCard:
    """Um card do Figma: evento, parâmetros esperados e variações."""

    evento: str
    secao: str = "Geral"
    titulo: str | None = None
    print_name: str | None = None
    params: dict[str, Any] = field(default_factory=dict)
    variacoes: list[dict[str, Any]] = field(default_factory=list)
    por_fluxo: bool | None = None
    params_por_fluxo: dict[str, dict[str, Any]] = field(default_factory=dict)
    obs: str | dict[str, str] | None = None

    def to_dict(self) -> dict[str, Any]:
        """Mesmo formato do JSON da spec (a chave do print é `print`)."""
        return {
            "secao": self.secao,
            "titulo": self.titulo,
            "print": self.print_name,
            "evento": self.evento,
            "params": self.params,
            "variacoes": self.variacoes,
            "por_fluxo": self.por_fluxo,
            "params_por_fluxo": self.params_por_fluxo,
            "obs": self.obs,
        }


@dataclass
class SpecTemplate:
    """A spec-modelo inteira, já validada."""

    projeto: str
    cards: list[SpecCard]
    versao_especificacao: str | None = None
    plataforma: str = "android"
    prints_dir: str | None = None
    fluxos: dict[str, str] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: Any) -> SpecTemplate:
        """Valida o JSON da spec. Erro aponta o card e o campo, em português."""
        if not isinstance(data, dict):
            raise InvalidInputError("A spec precisa ser um objeto JSON com 'projeto' e 'cards'.")
        projeto = _text(data.get("projeto"), "projeto", required=True)
        plataforma = (_text(data.get("plataforma"), "plataforma") or "android").lower()
        if plataforma not in PLATFORMS:
            raise InvalidInputError(f"Plataforma inválida na spec: {plataforma!r}. Use android ou ios.")
        fluxos = data.get("fluxos") or {}
        if not isinstance(fluxos, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in fluxos.items()
        ):
            raise InvalidInputError("'fluxos' precisa mapear a chave do fluxo para o rótulo, os dois em texto.")
        cards_raw = data.get("cards")
        if not isinstance(cards_raw, list) or not cards_raw:
            raise InvalidInputError("A spec não tem cards. Liste ao menos um em 'cards'.")
        cards = [_card(i, raw) for i, raw in enumerate(cards_raw, 1)]
        return cls(
            projeto=projeto,
            cards=cards,
            versao_especificacao=_text(data.get("versao_especificacao"), "versao_especificacao"),
            plataforma=plataforma,
            prints_dir=_text(data.get("prints_dir"), "prints_dir"),
            fluxos=dict(fluxos),
        )


def _text(value: Any, name: str, *, required: bool = False) -> str | None:
    if value is None or value == "":
        if required:
            raise InvalidInputError(f"Campo obrigatório ausente na spec: '{name}'.")
        return None
    if not isinstance(value, str):
        raise InvalidInputError(f"'{name}' precisa ser texto, veio {type(value).__name__}.")
    return value


def _card(index: int, raw: Any) -> SpecCard:
    where = f"card {index}"
    if not isinstance(raw, dict):
        raise InvalidInputError(f"{where}: cada card precisa ser um objeto JSON.")
    evento = _text(raw.get("evento"), f"{where}.evento", required=True)
    params = raw.get("params") or {}
    if not isinstance(params, dict):
        raise InvalidInputError(f"{where}: 'params' precisa ser um objeto.")
    variacoes = raw.get("variacoes") or []
    if not isinstance(variacoes, list) or not all(isinstance(v, dict) for v in variacoes):
        raise InvalidInputError(f"{where}: 'variacoes' precisa ser uma lista de objetos.")
    por_fluxo = raw.get("por_fluxo")
    if por_fluxo is not None and not isinstance(por_fluxo, bool):
        raise InvalidInputError(f"{where}: 'por_fluxo' precisa ser true ou false.")
    por_fluxo_params = raw.get("params_por_fluxo") or {}
    if not isinstance(por_fluxo_params, dict) or not all(isinstance(v, dict) for v in por_fluxo_params.values()):
        raise InvalidInputError(f"{where}: 'params_por_fluxo' precisa mapear o fluxo para um objeto.")
    obs = raw.get("obs")
    if obs is not None and not isinstance(obs, str) and not (
        isinstance(obs, dict) and all(isinstance(v, str) for v in obs.values())
    ):
        raise InvalidInputError(f"{where}: 'obs' precisa ser texto ou um objeto por fluxo.")
    for origem in (params, *variacoes, *por_fluxo_params.values()):
        _check_regexes(origem, where)
    return SpecCard(
        evento=evento or "",
        secao=_text(raw.get("secao"), f"{where}.secao") or "Geral",
        titulo=_text(raw.get("titulo"), f"{where}.titulo"),
        print_name=_text(raw.get("print"), f"{where}.print"),
        params=dict(params),
        variacoes=[dict(v) for v in variacoes],
        por_fluxo=por_fluxo,
        params_por_fluxo={k: dict(v) for k, v in por_fluxo_params.items()},
        obs=obs,
    )


def _check_regexes(value: Any, where: str) -> None:
    """`re:<regex>` inválida quebraria a auditoria no meio; aqui vira erro de spec."""
    if isinstance(value, dict):
        for item in value.values():
            _check_regexes(item, where)
    elif isinstance(value, list):
        for item in value:
            _check_regexes(item, where)
    elif isinstance(value, str) and value.strip().startswith("re:"):
        try:
            re.compile(value.strip()[3:])
        except re.error as exc:
            raise InvalidInputError(f"{where}: expressão regular inválida {value!r} ({exc}).") from exc


@dataclass
class Variant:
    """Uma combinação concreta (card x fluxo x variação) a procurar no log."""

    card_index: int
    flow: str | None
    event: str
    expected: dict[str, Any]
    note: str | None = None


@dataclass
class TagEvent:
    """Evento de tagueamento já normalizado para a auditoria.

    Diferente de `AnalyticsEvent`, que é o que a escuta captura: aqui o nome
    perdeu o sufixo do SDK (`screen_view(_vs)`), os parâmetros do Android foram
    relidos do `raw_log` e o `items` virou lista de objetos.
    """

    id: Any
    event_name: str
    params: dict[str, Any] = field(default_factory=dict)
    platform: str = "android"
    raw_log: str | None = None
    time_str: str | None = None
    origin: str | None = None


@dataclass
class ParamCheck:
    field: str
    expected: str
    obtained: Any
    ok: bool


@dataclass
class VariantResult:
    variant: Variant
    status: VariantStatus
    matched: TagEvent | None = None
    checks: list[ParamCheck] = field(default_factory=list)
    occurrences: int = 0
    older_divergent: int = 0
    older_divergences: list[str] = field(default_factory=list)
    ga_screen: str | None = None


@dataclass
class ExtraEvent:
    """Evento fora da spec, ou alerta, agrupado por tela e parâmetros."""

    event: str
    screen: str | None = None
    flow_name: str | None = None
    component: str | None = None
    detail: str | None = None
    count: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "event": self.event,
            "screen": self.screen,
            "flow_name": self.flow_name,
            "component": self.component,
            "detail": self.detail,
            "count": self.count,
        }


@dataclass
class AuditReport:
    spec: SpecTemplate
    platform: str
    results: list[VariantResult]
    log_stats: dict[str, int] = field(default_factory=dict)
    extras: list[ExtraEvent] = field(default_factory=list)
    alerts: list[ExtraEvent] = field(default_factory=list)

    @property
    def total(self) -> int:
        return len(self.results)

    @property
    def total_ok(self) -> int:
        return sum(1 for r in self.results if r.status is VariantStatus.OK)

    @property
    def total_missing(self) -> int:
        return sum(1 for r in self.results if r.status is VariantStatus.MISSING)

    @property
    def total_error(self) -> int:
        """Tudo que não está OK, inclusive o que não disparou."""
        return self.total - self.total_ok

    @property
    def total_divergent(self) -> int:
        """Disparou, mas com algum parâmetro errado."""
        return self.total_error - self.total_missing

    @property
    def compliance_rate(self) -> float:
        return round(self.total_ok / self.total * 100.0, 1) if self.total else 0.0

    def results_by_card(self, card_index: int) -> list[VariantResult]:
        return [r for r in self.results if r.variant.card_index == card_index]
