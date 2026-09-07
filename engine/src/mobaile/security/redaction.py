"""Redação de segredos no tráfego capturado.

O proxy vê o app autenticado do cliente: Bearer tokens, cookies de sessão,
chaves de API, CPF em corpo de requisição. Esse material fica em memória, é
exibido na tela e pode ser exportado. Redigir na entrada é mais barato do que
tentar limpar depois, e evita que um print de tela vire incidente.

Nada aqui é irreversível para quem está depurando: o valor é substituído por
uma marca que preserva o tamanho aproximado, então dá para ver que o header
existia sem expor o segredo. Para depuração pontual, `MOBAILE_REDACT=0`
desliga — decisão consciente do operador, não o padrão.
"""

from __future__ import annotations

import os
import re
from collections.abc import Mapping

_SENSITIVE_HEADERS = frozenset(
    {
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "x-access-token",
        "x-session-token",
        "x-csrf-token",
        "api-key",
        "authentication",
    }
)

# Campos que aparecem em corpo JSON/form de apps financeiros e de onboarding.
_SENSITIVE_BODY_KEYS = (
    "password",
    "senha",
    "token",
    "access_token",
    "refresh_token",
    "id_token",
    "secret",
    "client_secret",
    "authorization",
    "cpf",
    "cnpj",
    "card_number",
    "cardnumber",
    "cvv",
    "pin",
)

_BODY_PATTERN = re.compile(
    r'("(?:' + "|".join(_SENSITIVE_BODY_KEYS) + r')"\s*:\s*)"[^"]*"',
    re.IGNORECASE,
)

_MASK = "«redigido»"


def redaction_enabled() -> bool:
    """Ligado por padrão. `MOBAILE_REDACT=0` desliga explicitamente."""
    return os.getenv("MOBAILE_REDACT", "1").strip().lower() not in ("0", "false", "no")


def redact_headers(headers: Mapping[str, str]) -> dict[str, str]:
    """Devolve uma cópia com os headers sensíveis mascarados."""
    if not redaction_enabled():
        return dict(headers)
    out: dict[str, str] = {}
    for key, value in headers.items():
        if key.lower() in _SENSITIVE_HEADERS:
            out[key] = f"{_MASK} ({len(value)} chars)"
        else:
            out[key] = value
    return out


def redact_body(body: str) -> str:
    """Mascara valores de campos sensíveis em corpo JSON.

    Formato não-JSON passa intacto: mascarar às cegas destruiria a utilidade da
    inspeção, e o ganho seria ilusório.
    """
    if not body or not redaction_enabled():
        return body
    return _BODY_PATTERN.sub(rf'\1"{_MASK}"', body)
