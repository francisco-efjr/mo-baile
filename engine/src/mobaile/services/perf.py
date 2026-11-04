"""Perfis de desempenho: completo, equilibrado e leve (PERF-3).

Uma politica so, aqui no motor (ADR 0001: a mesma regra em Python e em Swift e
defeito). O front e sensor e atuador: manda os sinais do Mac (`perf.signals`)
e aplica a parte visual do perfil que volta (`perf.profile`). O motor aplica a
parte dele: cadencia e tamanho do espelho, vigia de aparelhos e historicos.

O modo leve reduz apresentacao e cadencia, nunca captura: nenhum evento de rede
ou de analytics deixa de ser notificado por causa do perfil. O que encolhe e
quanto do passado fica na memoria do motor.

`resolve` e pura e testada por tabela (`test_perf_governador.py`). Os valores
de `KNOBS` sao ponto de partida (Suposicao), a calibrar com
`tools/bench_stream.py` num M1 de 8 GB e num Intel.
"""

from __future__ import annotations

import re
import threading
import time
from collections.abc import Callable
from dataclasses import asdict, dataclass, replace
from typing import Any

PERFIS: tuple[str, ...] = ("completo", "equilibrado", "leve")
PREFERENCIAS: tuple[str, ...] = ("auto", *PERFIS)
THERMAL: tuple[str, ...] = ("nominal", "fair", "serious", "critical")
MEMORIA: tuple[str, ...] = ("normal", "warning", "critical")

# Melhorar so depois de tanto tempo com o alvo melhor, um degrau por vez.
MELHORA_S = 60.0
# Ate quanto de memoria fisica o Mac conta como modesto (M1 de 8 GB).
MEMORIA_MODESTA_GB = 8.0

_ARCH = re.compile(r"^[a-z0-9_]{1,16}$")


@dataclass(frozen=True)
class Knobs:
    stream_fps: float
    stream_idle_fps: float
    stream_max_width: int
    stream_quality: int
    # Plano B do iOS (`simctl io screenshot`) em JPEG: decodificar cai de ~16
    # para ~4 ms por quadro (perf-contexto K3). O inspetor continua em PNG.
    stream_capture_jpeg: bool
    poll_interval: float
    proxy_history: int
    analytics_history: int
    glass: bool
    animations: bool

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


KNOBS: dict[str, Knobs] = {
    # A cadencia de hoje: o front pedia 6 fps e 900 px fixos. PNG cru de
    # aparelho moderno passa de 1 MB; o espelho e reduzido antes de virar
    # base64 (o que importa e o layout) e o inspetor usa a captura cheia.
    "completo": Knobs(6.0, 2.0, 900, 80, False, 1.5, 2000, 5000, True, True),
    # 720 px q70: 13,6 ms e 119 KB por quadro (medido, bench_knobs).
    "equilibrado": Knobs(4.0, 1.0, 720, 70, True, 3.0, 1000, 3000, True, True),
    # 600 px q60: 11,8 ms e 79 KB por quadro (medido, bench_knobs).
    "leve": Knobs(2.0, 0.5, 600, 60, True, 5.0, 500, 2000, False, False),
}


@dataclass(frozen=True)
class Sinais:
    """O que o front sabe do Mac. Campo ausente no `perf.signals` fica como estava."""

    thermal: str = "nominal"
    low_power: bool = False
    memory_pressure: str = "normal"
    physical_memory_gb: float | None = None
    arch: str | None = None
    translated: bool = False

    def com(self, valores: dict[str, Any]) -> Sinais:
        """Copia com os campos informados, validados. Invalido: `ValueError`."""
        novos: dict[str, Any] = {}
        for campo, valor in valores.items():
            if campo == "thermal" and valor not in THERMAL:
                raise ValueError(f"thermal invalido: {valor!r}")
            if campo == "memory_pressure" and valor not in MEMORIA:
                raise ValueError(f"memory_pressure invalido: {valor!r}")
            if campo in ("low_power", "translated") and not isinstance(valor, bool):
                raise ValueError(f"{campo} deve ser booleano")
            if campo == "physical_memory_gb" and valor is not None and (
                isinstance(valor, bool) or not isinstance(valor, (int, float)) or not 0 < valor <= 65536
            ):
                raise ValueError("physical_memory_gb fora da faixa")
            if campo == "arch" and valor is not None and not (isinstance(valor, str) and _ARCH.match(valor)):
                raise ValueError("arch invalida")
            if campo in self.__dataclass_fields__:
                novos[campo] = valor
        return replace(self, **novos)

    @property
    def modesto(self) -> bool:
        memoria = self.physical_memory_gb
        return (memoria is not None and memoria <= MEMORIA_MODESTA_GB) or self.arch == "x86_64" or self.translated


@dataclass(frozen=True)
class Estado:
    perfil: str
    motivo: str
    desde: float
    # Desde quando o alvo e melhor que o perfil atual; `None` sem melhora pendente.
    melhora_desde: float | None = None

    def proxima_reavaliacao(self) -> float | None:
        return None if self.melhora_desde is None else self.melhora_desde + MELHORA_S


def _rank(perfil: str) -> int:
    return PERFIS.index(perfil)


def alvo_automatico(sinais: Sinais) -> tuple[str, str]:
    """O perfil que os sinais pedem, com o motivo do mais grave."""
    pedidos = [
        (sinais.thermal == "critical", "leve", "thermal_critical"),
        (sinais.thermal == "serious", "leve", "thermal_serious"),
        (sinais.memory_pressure == "critical", "leve", "memory_critical"),
        (sinais.low_power and sinais.modesto, "leve", "low_power"),
        (sinais.thermal == "fair", "equilibrado", "thermal_fair"),
        (sinais.memory_pressure == "warning", "equilibrado", "memory_warning"),
        (sinais.low_power, "equilibrado", "low_power"),
        (sinais.modesto, "equilibrado", "hardware_modesto"),
    ]
    melhor = ("completo", "sinais_normais")
    for vale, perfil, motivo in pedidos:
        if vale and _rank(perfil) > _rank(melhor[0]):
            melhor = (perfil, motivo)
    return melhor


def resolve(sinais: Sinais, preferencia: str, anterior: Estado | None, agora: float) -> Estado:
    """Perfil efetivo. Pura: mesmo sinal, mesma historia, mesmo resultado."""
    if sinais.thermal == "critical":
        alvo, motivo = "leve", "thermal_critical"
    elif preferencia in PERFIS:
        alvo, motivo = preferencia, "manual"
    else:
        alvo, motivo = alvo_automatico(sinais)

    if anterior is None:
        return Estado(alvo, motivo, agora)
    # Escolha do usuario vale na hora, para melhor ou pior; so a saida do
    # critico respeita a espera, para o Mac esfriar antes de voltar ao manual.
    escolha = motivo == "manual" and anterior.motivo != "thermal_critical"
    if escolha or anterior.motivo == "manual" or _rank(alvo) > _rank(anterior.perfil):
        if alvo == anterior.perfil:
            return Estado(alvo, motivo, anterior.desde)
        return Estado(alvo, motivo, agora)
    if alvo == anterior.perfil:
        return Estado(alvo, motivo, anterior.desde)

    # Alvo melhor que o atual: espera MELHORA_S e sobe um degrau.
    if anterior.melhora_desde is None:
        return replace(anterior, melhora_desde=agora)
    if agora - anterior.melhora_desde < MELHORA_S:
        return anterior
    degrau = PERFIS[_rank(anterior.perfil) - 1]
    if degrau == alvo:
        return Estado(alvo, motivo, agora)
    return Estado(degrau, "recuperando", agora, melhora_desde=agora)


class PerfGovernor:
    """Guarda sinais, preferencia e estado; avisa a cada troca de perfil.

    Thread-safe: `perf.signals` chega pela fila rapida e a reavaliacao da
    histerese por um temporizador.
    """

    def __init__(self, relogio: Callable[[], float] = time.monotonic) -> None:
        self._relogio = relogio
        self._lock = threading.Lock()
        self.sinais = Sinais()
        self.preferencia = "auto"
        self.estado = resolve(self.sinais, self.preferencia, None, relogio())

    def atualizar(self, sinais: dict[str, Any] | None = None, preferencia: str | None = None) -> tuple[Estado, bool]:
        """Aplica sinais e/ou preferencia. Devolve o estado e se o perfil mudou."""
        with self._lock:
            if sinais:
                self.sinais = self.sinais.com(sinais)
            if preferencia is not None:
                if preferencia not in PREFERENCIAS:
                    raise ValueError(f"preferencia invalida: {preferencia!r}")
                self.preferencia = preferencia
            anterior = self.estado
            self.estado = resolve(self.sinais, self.preferencia, anterior, self._relogio())
            return self.estado, self.estado.perfil != anterior.perfil

    def reavaliar(self) -> tuple[Estado, bool]:
        return self.atualizar()

    def agora(self) -> float:
        return self._relogio()

    @property
    def knobs(self) -> Knobs:
        return KNOBS[self.estado.perfil]

    def status(self) -> dict[str, Any]:
        with self._lock:
            estado, sinais, preferencia = self.estado, self.sinais, self.preferencia
        return {
            "profile": estado.perfil,
            "reason": estado.motivo,
            "preference": preferencia,
            "knobs": KNOBS[estado.perfil].to_dict(),
            "signals": asdict(sinais),
            "improving": estado.melhora_desde is not None,
        }
