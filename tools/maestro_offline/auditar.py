#!/usr/bin/env python3
"""Prova que o `maestro mcp` rodando pelo lancador offline nao fala com a rede.

Sobe uma armadilha HTTP em 127.0.0.1 para onde o lancador manda as chamadas a
api da mobile.dev, abre o servidor MCP, lista as ferramentas, chama
`list_devices` e `cheat_sheet` (esta tem endereco fixo no codigo e precisa
falhar), e enquanto isso tira fotos do `lsof` do processo. Sai com codigo 1 se
qualquer conexao nao local aparecer.

    python3 tools/maestro_offline/auditar.py            # relatorio em JSON
    python3 tools/maestro_offline/auditar.py --flow f.yaml --device emulator-5554

Nao precisa de aparelho para a parte de rede; com `--flow`, roda o flow pela
ferramenta `run` e inclui o resultado.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import ClassVar

LANCADOR = Path(__file__).with_name("maestro-offline.sh")
LOCAIS = ("127.0.0.1", "[::1]", "localhost", "*")


class _Armadilha(BaseHTTPRequestHandler):
    capturas: ClassVar[list[dict]] = []

    def _registrar(self) -> None:
        tamanho = int(self.headers.get("Content-Length") or 0)
        if tamanho:
            self.rfile.read(tamanho)
        # So metodo, caminho e tamanho: o corpo pode ter stack trace com caminho local.
        self.capturas.append({"metodo": self.command, "caminho": self.path, "bytes": tamanho})
        self.send_response(503)
        self.end_headers()

    do_GET = do_POST = do_PUT = _registrar

    def log_message(self, *_args) -> None:
        pass


def _conexoes(pid: int) -> list[str]:
    """Pontas remotas dos sockets TCP/UDP do processo, como o lsof mostra."""
    saida = subprocess.run(
        ["lsof", "-nP", "-a", "-p", str(pid), "-i"], capture_output=True, text=True, check=False
    ).stdout
    pontas = []
    for linha in saida.splitlines()[1:]:
        nome = linha.split()[8] if len(linha.split()) > 8 else ""
        pontas.append(nome.split("->")[-1])
    return pontas


def _nao_local(ponta: str) -> bool:
    return not ponta.startswith(LOCAIS)


class _ClienteMcp:
    def __init__(self, proc: subprocess.Popen) -> None:
        self.proc = proc
        self.proximo = 0

    def pedir(self, metodo: str, params: dict | None = None, espera: float = 90) -> dict:
        self.proximo += 1
        pedido = {"jsonrpc": "2.0", "id": self.proximo, "method": metodo, "params": params or {}}
        self.proc.stdin.write(json.dumps(pedido) + "\n")
        self.proc.stdin.flush()
        limite = time.monotonic() + espera
        while time.monotonic() < limite:
            linha = self.proc.stdout.readline()
            if not linha:
                raise RuntimeError("o servidor MCP fechou a saida")
            try:
                msg = json.loads(linha)
            except ValueError:
                continue
            if msg.get("id") == self.proximo:
                return msg
        raise TimeoutError(metodo)

    def avisar(self, metodo: str) -> None:
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": metodo}) + "\n")
        self.proc.stdin.flush()


def _texto(resposta: dict) -> str:
    conteudo = (resposta.get("result") or {}).get("content") or []
    return " ".join(c.get("text", "") for c in conteudo if c.get("type") == "text")[:300]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--flow", help="flow YAML para rodar pela ferramenta `run`")
    ap.add_argument("--device", help="device_id para o `run` (de list_devices)")
    args = ap.parse_args()

    servidor = ThreadingHTTPServer(("127.0.0.1", 0), _Armadilha)
    threading.Thread(target=servidor.serve_forever, daemon=True).start()

    estado = tempfile.mkdtemp(prefix="maestro-offline-audit-")
    env = dict(os.environ, MAESTRO_OFFLINE_TRAP=str(servidor.server_port), MAESTRO_OFFLINE_STATE=estado)
    proc = subprocess.Popen(
        [str(LANCADOR), "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, env=env,
    )
    vistas: set[str] = set()
    parar = threading.Event()

    def vigiar() -> None:
        while not parar.is_set() and proc.poll() is None:
            vistas.update(_conexoes(proc.pid))
            parar.wait(0.2)

    threading.Thread(target=vigiar, daemon=True).start()
    relatorio: dict = {"lancador": str(LANCADOR)}
    try:
        cliente = _ClienteMcp(proc)
        info = cliente.pedir("initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "mobaile-auditoria", "version": "1"},
        })
        relatorio["servidor"] = (info.get("result") or {}).get("serverInfo")
        cliente.avisar("notifications/initialized")
        ferramentas = cliente.pedir("tools/list")
        relatorio["ferramentas"] = [t["name"] for t in (ferramentas.get("result") or {}).get("tools", [])]
        relatorio["list_devices"] = _texto(cliente.pedir("tools/call", {"name": "list_devices", "arguments": {}}))
        # As duas ferramentas de documentacao chamam a api da mobile.dev: tem de falhar.
        for nome, argumentos in (("cheat_sheet", {}), ("query_docs", {"question": "tapOn"})):
            if nome not in relatorio["ferramentas"]:
                continue
            resposta = cliente.pedir("tools/call", {"name": nome, "arguments": argumentos}, espera=30)
            relatorio[nome] = {
                "erro": bool((resposta.get("result") or {}).get("isError")) or "error" in resposta,
                "texto": _texto(resposta),
            }
        if args.flow:
            yaml = Path(args.flow).read_text(encoding="utf-8")
            # `run` desde a 2.5.0; antes, `run_flow` com `flow_yaml`.
            if "run" in relatorio["ferramentas"]:
                chamada = {"name": "run", "arguments": {"device_id": args.device, "yaml": yaml}}
            else:
                chamada = {"name": "run_flow", "arguments": {"device_id": args.device, "flow_yaml": yaml}}
            run = cliente.pedir("tools/call", chamada, espera=300)
            relatorio["run"] = {"erro": bool((run.get("result") or {}).get("isError")), "texto": _texto(run)}
    finally:
        proc.stdin.close()
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.terminate()
            proc.wait(timeout=10)
        parar.set()
        # O CLI manda relatorios no encerramento: da tempo de chegarem a armadilha.
        time.sleep(1)
        servidor.shutdown()

    estrangeiras = sorted(p for p in vistas if _nao_local(p))
    relatorio["conexoes_vistas"] = sorted(vistas)
    relatorio["conexoes_nao_locais"] = estrangeiras
    relatorio["armadilha_mobile_dev"] = _Armadilha.capturas
    relatorio["estado"] = estado
    print(json.dumps(relatorio, ensure_ascii=False, indent=2))
    return 1 if estrangeiras else 0


if __name__ == "__main__":
    sys.exit(main())
