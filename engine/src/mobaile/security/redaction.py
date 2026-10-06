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

import json
import os
import re
import urllib.parse
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
    "api_key",
    "apikey",
    "x-amz-signature",
    "x-amz-credential",
    "x-amz-security-token",
)

# Reconhece a chave como string JSON completa, inclusive escapes. O decoder
# encontra o fim do valor (string, número, objeto ou lista) sem cortar em uma
# aspa escapada; a captura pode ser apenas um prefixo de JSON grande.
_JSON_KEY_PATTERN = re.compile(r'("(?:\\.|[^"\\])*")\s*:\s*')
_JSON_DECODER = json.JSONDecoder()
_SENSITIVE_KEYS = frozenset(key.replace("_", "").replace("-", "") for key in _SENSITIVE_BODY_KEYS)

_MASK = "«redigido»"


def _is_sensitive_key(key: str) -> bool:
    return key.lower().replace("_", "").replace("-", "") in _SENSITIVE_KEYS


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
        elif key.lower() in ("location", "content-location", "referer"):
            out[key] = redact_url(value)
        else:
            out[key] = value
    return out


def redact_body(body: str) -> str:
    """Mascara valores JSON e form sem modificar campos inocentes.

    Em JSON truncado, um valor sensível incompleto é ocultado até o fim da
    captura: guardar o prefixo de uma senha ainda exporia a credencial.
    """
    if not body or not redaction_enabled():
        return body
    if not body.lstrip().startswith(("{", "[")) and "=" in body:
        body = _redact_form(body)
    chunks = []
    cursor = 0
    for match in _JSON_KEY_PATTERN.finditer(body):
        if match.start() < cursor:
            continue
        try:
            key = json.loads(match.group(1)).lower()
        except (ValueError, TypeError):
            continue
        if not _is_sensitive_key(key):
            continue
        value_start = match.end()
        try:
            _, value_end = _JSON_DECODER.raw_decode(body, value_start)
        except (ValueError, RecursionError):
            value_end = len(body)
        chunks.append(body[cursor:value_start])
        chunks.append(json.dumps(_MASK, ensure_ascii=False))
        cursor = value_end
    chunks.append(body[cursor:])
    return "".join(chunks)


def _redact_form(value: str) -> str:
    fields = []
    for field in value.split("&"):
        key, separator, raw_value = field.partition("=")
        if separator and _is_sensitive_key(urllib.parse.unquote_plus(key)):
            raw_value = urllib.parse.quote_plus(_MASK)
        fields.append(key + separator + raw_value)
    return "&".join(fields)


def redact_url(url: str) -> str:
    """Oculta userinfo e credenciais de query/fragment antes de guardar URLs."""
    if not url or not redaction_enabled():
        return url
    try:
        parsed = urllib.parse.urlsplit(url)
    except ValueError:
        return f"{_MASK} (URL inválida)"
    netloc = parsed.netloc
    if "@" in netloc:
        netloc = urllib.parse.quote(_MASK) + "@" + netloc.rsplit("@", 1)[1]
    return urllib.parse.urlunsplit((
        parsed.scheme, netloc, parsed.path,
        _redact_form(parsed.query), _redact_form(parsed.fragment),
    ))
