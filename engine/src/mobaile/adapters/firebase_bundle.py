"""Leitura do ``Bundle[{...}]`` que o Firebase Analytics escreve no Logcat.

Um leitor só para a escuta ao vivo (`analytics_logcat`) e para a auditoria do
Relatório (`services/report/firebase_log`). O formato é o ``toString`` do
Bundle do Android: pares ``chave=valor`` separados por ``", "``, com ``items``
como lista de Bundles aninhados:

    Bundle[{currency(_cu)=BRL, value(_v)=30.03, items=[Bundle[{item_id=1, price=10.01}], Bundle[{...}]]}]

O valor não vem entre aspas, então uma vírgula dentro dele (``value=30,03``,
``item_name=Camiseta, verde``) é igual a um separador. Antes, o trecho depois da
vírgula era descartado sem aviso, e ``value=30,03`` virava ``30``. Agora um
trecho só abre um par novo quando começa com uma chave seguida de ``=``. Os
outros trechos continuam o valor anterior. Resta uma ambiguidade sem solução no
formato: um valor com ``", chave="`` dentro.
"""

from __future__ import annotations

import re
from collections.abc import Callable
from typing import Any

_NESTING = re.compile(r"[\[\]{}]")
_SEPARATORS = re.compile(r"[\[\]{},]")
# Começo de um par: chave do SDK, com o nome curto opcional, e "=".
_PAIR_START = re.compile(r"\s*[A-Za-z_][A-Za-z0-9_]*(?:\([^()]*\))?=")
_SDK_SUFFIX = re.compile(r"\(_[a-zA-Z0-9]+\)$")


def split_top_level(text: str) -> list[str]:
    """Divide por vírgulas que não estão dentro de [] ou {}."""
    if _NESTING.search(text) is None:
        parts = text.split(",")
    else:
        # Só os caracteres que importam são visitados, e não o texto inteiro.
        parts: list[str] = []
        depth = start = 0
        for found in _SEPARATORS.finditer(text):
            ch = found.group()
            if ch in "[{":
                depth += 1
            elif ch in "]}":
                depth -= 1
            elif depth == 0:
                parts.append(text[start:found.start()])
                start = found.end()
        parts.append(text[start:])
    if not parts[-1].strip():
        parts.pop()
    return parts


def split_pairs(body: str) -> list[str]:
    """Os pares ``chave=valor`` do corpo, com a vírgula de dentro do valor no lugar."""
    pairs: list[str] = []
    for part in split_top_level(body):
        if pairs and not _PAIR_START.match(part):
            pairs[-1] = f"{pairs[-1]},{part}"
        else:
            pairs.append(part)
    return pairs


def strip_sdk_suffix(key: str) -> str:
    """``ga_screen(_sn)`` vira ``ga_screen``."""
    key = key.strip()
    return _SDK_SUFFIX.sub("", key) if key.endswith(")") else key


def parse_bundle(text: str, clean_value: Callable[[str], Any] | None = None) -> dict[str, Any]:
    """``Bundle[{k=v, items=[Bundle[{...}]]}]`` em dicionário.

    As chaves perdem o sufixo do SDK, e uma lista de Bundles vira lista de
    objetos. `clean_value` trata cada valor de texto, nos itens também. Sem ele,
    o valor fica como veio, só sem os espaços das pontas.
    """
    body = text.strip()
    if body.startswith("Bundle[{") and body.endswith("}]"):
        body = body[8:-2]
    out: dict[str, Any] = {}
    for pair in split_pairs(body):
        if "=" not in pair:
            continue
        key, value = pair.split("=", 1)
        value = value.strip()
        if value.startswith("[Bundle[") and value.endswith("]"):
            out[strip_sdk_suffix(key)] = [parse_bundle(b, clean_value) for b in split_top_level(value[1:-1])]
        else:
            out[strip_sdk_suffix(key)] = clean_value(value) if clean_value else value
    return out
