"""Cliente JSON-RPC de teste: sobe o motor de verdade como subprocesso.

E o mesmo transporte que o front SwiftUI usa, entao o que passa aqui e o que a
interface vai ver.
"""
import json
import os
import pathlib
import queue
import subprocess
import sys
import threading
import time


class Motor:
    def __init__(self, *, android=False, ios=False, ios_booted=False, extra_env=None):
        env = dict(os.environ)
        env["PATH"] = str(pathlib.Path(__file__).resolve().parent / "fakebin") + ":" + env["PATH"]
        env["PYTHONPATH"] = str(pathlib.Path(__file__).resolve().parent.parent / "engine" / "src")
        env["PYTHONUNBUFFERED"] = "1"
        env["QA_ANDROID"] = "1" if android else "0"
        env["QA_IOS"] = "1" if ios else "0"
        env["QA_IOS_BOOTED"] = "1" if ios_booted else "0"
        env["QA_LOG"] = str(pathlib.Path(__file__).resolve().parent / "calls.log")
        env.setdefault("WDA_URL", "http://127.0.0.1:8100")
        env.update(extra_env or {})

        self.proc = subprocess.Popen(
            [sys.executable, "-m", "mobaile.rpc"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1, env=env,
        )
        self._id = 0
        self.respostas = {}
        self.notificacoes = queue.Queue()
        self.stderr = []
        threading.Thread(target=self._ler_stdout, daemon=True).start()
        threading.Thread(target=self._ler_stderr, daemon=True).start()

    def _ler_stdout(self):
        for linha in self.proc.stdout:
            linha = linha.strip()
            if not linha:
                continue
            try:
                msg = json.loads(linha)
            except json.JSONDecodeError:
                self.stderr.append(f"LINHA FORA DO PROTOCOLO: {linha[:120]}")
                continue
            if "id" in msg:
                self.respostas[msg["id"]] = msg
            else:
                self.notificacoes.put(msg)

    def _ler_stderr(self):
        for linha in self.proc.stderr:
            self.stderr.append(linha.rstrip())

    def chamar(self, metodo, params=None, timeout=30):
        self._id += 1
        rid = self._id
        self.proc.stdin.write(json.dumps(
            {"jsonrpc": "2.0", "id": rid, "method": metodo, "params": params or {}}) + "\n")
        self.proc.stdin.flush()
        limite = time.time() + timeout
        while time.time() < limite:
            if rid in self.respostas:
                return self.respostas.pop(rid)
            time.sleep(0.01)
        raise TimeoutError(f"{metodo} nao respondeu em {timeout}s")

    def ok(self, metodo, params=None, timeout=30):
        r = self.chamar(metodo, params, timeout)
        if "error" in r:
            raise AssertionError(f"{metodo} falhou: {r['error']}")
        return r["result"]

    def erro(self, metodo, params=None):
        r = self.chamar(metodo, params)
        assert "error" in r, f"{metodo} deveria ter falhado, devolveu {r.get('result')}"
        return r["error"]

    def esperar_notificacao(self, metodo, timeout=15):
        limite = time.time() + timeout
        vistas = []
        while time.time() < limite:
            try:
                msg = self.notificacoes.get(timeout=0.2)
            except queue.Empty:
                continue
            if msg.get("method") == metodo:
                return msg
            vistas.append(msg.get("method"))
        raise TimeoutError(f"notificacao '{metodo}' nao chegou. Vistas: {set(vistas)}")

    def encerrar(self):
        try:
            self.chamar("engine.shutdown", timeout=5)
        except Exception:
            pass
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
