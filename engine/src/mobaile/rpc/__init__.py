"""Fronteira JSON-RPC: a unica porta de entrada do motor para o front.

`EngineServer` e `serve` sao carregados so quando pedidos: quem precisa apenas
do envelope (`mobaile.rpc.protocol`), como o front web, nao arrasta junto o
servidor inteiro e todos os adapters.
"""

from typing import Any

__all__ = ["EngineServer", "serve"]


def __getattr__(name: str) -> Any:
    if name in __all__:
        from mobaile.rpc import server

        return getattr(server, name)
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
