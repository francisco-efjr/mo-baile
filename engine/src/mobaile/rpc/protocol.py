"""Enquadramento e vocabulario da fronteira JSON-RPC.

Escolhas e porques:

- **JSON-RPC 2.0 sobre stdio, uma mensagem por linha.** O front sobe o motor
  como processo filho. Sem porta TCP nao ha superficie de rede, nao ha
  autenticacao para inventar e o ciclo de vida do motor morre junto com o app,
  o que resolve de graca o problema de processo orfao segurando o adb.
- **Notificacao para o que e continuo.** Quadro de tela, evento HTTP e evento
  de analytics chegam sem `id`: sao empurrados pelo motor, e o front nao fica
  fazendo polling.
- **Erro tipado.** Cada `EngineError` vira um codigo estavel no campo `data`,
  para o front decidir entre "mostrar dialogo" e "so registrar".
"""

from __future__ import annotations

import json
from typing import Any

JSONRPC_VERSION = "2.0"

# Codigos padrao do JSON-RPC 2.0.
PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603
# Faixa reservada a implementacao: erros do dominio do motor.
ENGINE_ERROR = -32000


def encode(message: dict[str, Any]) -> str:
    """Serializa em uma unica linha. `ensure_ascii=False` mantem acento legivel."""
    return json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n"


def result(request_id: Any, payload: Any) -> dict[str, Any]:
    return {"jsonrpc": JSONRPC_VERSION, "id": request_id, "result": payload}


def error(request_id: Any, code: int, message: str, data: Any | None = None) -> dict[str, Any]:
    body: dict[str, Any] = {"code": code, "message": message}
    if data is not None:
        body["data"] = data
    return {"jsonrpc": JSONRPC_VERSION, "id": request_id, "error": body}


def notification(method: str, params: Any) -> dict[str, Any]:
    return {"jsonrpc": JSONRPC_VERSION, "method": method, "params": params}
