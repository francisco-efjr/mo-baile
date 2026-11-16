"""Números que chegam pelo RPC (limites, intervalos, fps, larguras).

O JSON do Python aceita `NaN` e `Infinity`, e um cliente pode mandar texto ou
`true` onde se espera número. Converter com `int()` ou `float()` direto vira
"Erro interno no motor" na melhor hipótese; na pior, passa: `limit` negativo
fatiava o histórico do lado errado, e intervalo negativo virava laço sem pausa.
Aqui o valor é conferido (tipo, finito, faixa) e o erro diz qual parâmetro.
"""

from __future__ import annotations

import math

from mobaile.domain.errors import InvalidInputError


def validate_number(value: object, name: str, *, minimum: float, maximum: float) -> float:
    """Número finito dentro de [minimum, maximum]. `bool` não conta como número."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidInputError(f"{name} precisa ser um número: {value!r}")
    if isinstance(value, float) and not math.isfinite(value):
        raise InvalidInputError(f"{name} precisa ser um número finito: {value!r}")
    if not minimum <= value <= maximum:
        raise InvalidInputError(f"{name} precisa ficar entre {minimum:g} e {maximum:g}: {value!r}")
    return float(value)


def validate_integer(value: object, name: str, *, minimum: int, maximum: int) -> int:
    """Inteiro dentro de [minimum, maximum]. Aceita `3.0`, mas não `3.5`."""
    number = validate_number(value, name, minimum=minimum, maximum=maximum)
    if not number.is_integer():
        raise InvalidInputError(f"{name} precisa ser um número inteiro: {value!r}")
    return int(number)
