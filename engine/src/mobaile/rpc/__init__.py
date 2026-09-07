"""Fronteira JSON-RPC: a unica porta de entrada do motor para o front."""

from mobaile.rpc.server import EngineServer, serve

__all__ = ["EngineServer", "serve"]
