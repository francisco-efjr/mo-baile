"""Front web local (LIB-5) com o servidor de verdade em 127.0.0.1, porta livre.

`http.client` deixa forjar `Host` e `Origin`, que é o que um ataque de DNS
rebinding ou uma página de outra origem fariam. O fluxo completo (enviar spec e
log, auditar, exportar, baixar, ver o HTML) é conferido contra o
`ReportService` chamado direto, com os mesmos dados sintéticos.

O teste de portabilidade sobe `python -m mobaile.web` num processo à parte sem
`os.getuid`, `O_NOFOLLOW`, `fchmod` e com `AppKit`/`fcntl`/`pwd` bloqueados. É
simulação: não substitui rodar num Windows de verdade, o que não foi feito.
"""

from __future__ import annotations

import http.client
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "unit"))

from relatorio_dados import LOG, SPEC, gravar

from mobaile.services.report import ReportService
from mobaile.web.__main__ import main
from mobaile.web.server import TOKEN_HEADER, WebServer

pytestmark = pytest.mark.integration

SRC = Path(__file__).resolve().parents[2] / "src"
# Logcat sintético: dois eventos do Firebase e uma linha que não é evento.
LOGCAT = "\n".join([
    "11-16 10:00:00.000 V/FA-SVC  (1): Logging event: origin=app,name=screen_view(_vs),"
    "params=Bundle[{ga_event_origin(_o)=app, ga_screen(_sn)=app:home, flow_name=pedido}]",
    "11-16 10:00:01.000 I/ActivityManager(1): linha que não é evento",
    "11-16 10:00:02.500 V/FA-SVC  (1): Logging event: origin=app,name=add_to_cart,"
    "params=Bundle[{value=10, items=[Bundle[{item_id=1, item_name=pedido}]]}]",
])


class Servidor(unittest.TestCase):
    def setUp(self):
        self.srv = WebServer("127.0.0.1", 0)
        self.thread = threading.Thread(target=self.srv.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self._parar)
        self.host = f"127.0.0.1:{self.srv.port}"

    def _parar(self):
        self.srv.shutdown()
        self.thread.join(5)
        self.srv.close()

    def pedir(self, metodo, caminho, corpo=None, *, token=True, host=None, origin=None, tipo=None, extra=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.srv.port, timeout=10)
        cabecalhos = {"Host": host or self.host}
        if token:
            cabecalhos[TOKEN_HEADER] = self.srv.token if token is True else token
        if origin:
            cabecalhos["Origin"] = origin
        if tipo:
            cabecalhos["Content-Type"] = tipo
        cabecalhos.update(extra or {})
        try:
            conn.request(metodo, caminho, body=corpo, headers=cabecalhos)
            resposta = conn.getresponse()
            return resposta.status, dict(resposta.getheaders()), resposta.read()
        finally:
            conn.close()

    def rpc(self, method, params=None, **kw):
        corpo = json.dumps({"jsonrpc": "2.0", "id": 7, "method": method, "params": params or {}})
        status, _, dados = self.pedir("POST", "/rpc", corpo, tipo="application/json", **kw)
        self.assertEqual(status, 200, dados)
        return json.loads(dados)

    def enviar(self, tipo, conteudo: bytes):
        status, _, dados = self.pedir("POST", f"/upload?kind={tipo}", conteudo, tipo="application/octet-stream")
        self.assertEqual(status, 200, dados)
        return json.loads(dados)["path"]


class TestFronteira(Servidor):
    def test_url_tem_token_no_fragmento_e_porta_aleatoria(self):
        self.assertNotEqual(self.srv.port, 0)
        self.assertTrue(self.srv.url.startswith(f"http://127.0.0.1:{self.srv.port}/#t="))
        self.assertTrue(self.srv.url.endswith(self.srv.token))
        self.assertGreaterEqual(len(self.srv.token), 40)

    def test_pagina_com_csp_e_sem_cors(self):
        status, cab, corpo = self.pedir("GET", "/", token=False)
        self.assertEqual(status, 200)
        self.assertIn("default-src 'none'", cab["Content-Security-Policy"])
        self.assertIn("frame-ancestors 'none'", cab["Content-Security-Policy"])
        self.assertEqual(cab["X-Content-Type-Options"], "nosniff")
        self.assertNotIn("Access-Control-Allow-Origin", cab)
        self.assertIn(b"Produto em desenvolvimento: pode conter bugs", corpo)
        self.assertIn(b"issues/new?template=bug.yml", corpo)
        for estatico in ("/static/app.js", "/static/app.css", "/static/design_system.css"):
            self.assertEqual(self.pedir("GET", estatico, token=False)[0], 200, estatico)
        self.assertEqual(self.pedir("GET", "/static/../server.py", token=False)[0], 401)
        self.assertEqual(self.pedir("GET", "/static/../server.py")[0], 404)

    def test_sem_token_ou_token_errado_da_401(self):
        corpo = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "report.spec", "params": {}})
        for token in (False, "errado", self.srv.token + "x", "ção"):
            with self.subTest(token=token):
                status, cab, _ = self.pedir("POST", "/rpc", corpo, token=token, tipo="application/json")
                self.assertEqual(status, 401)
                self.assertNotIn("Access-Control-Allow-Origin", cab)
        self.assertEqual(self.pedir("GET", "/download/qualquer", token=False)[0], 401)
        self.assertEqual(self.pedir("POST", "/analytics", b"x", token=False, tipo="application/octet-stream")[0], 401)

    def test_host_forjado_da_421_antes_de_qualquer_rota(self):
        for caminho, metodo in (("/", "GET"), ("/static/app.js", "GET"), ("/rpc", "POST"), ("/view/x", "GET")):
            with self.subTest(caminho=caminho):
                status, _, _ = self.pedir(metodo, caminho, b"{}", host="evil.example", tipo="application/json")
                self.assertEqual(status, 421)
        self.assertEqual(self.pedir("GET", "/", token=False, host=f"127.0.0.1:{self.srv.port + 1}")[0], 421)
        self.assertEqual(self.pedir("GET", "/", token=False, host=f"localhost:{self.srv.port}")[0], 200)

    def test_origin_forjado_da_403(self):
        status, cab, _ = self.pedir("POST", "/rpc", b"{}", origin="http://evil.example", tipo="application/json")
        self.assertEqual(status, 403)
        self.assertNotIn("Access-Control-Allow-Origin", cab)
        self.assertEqual(self.pedir("GET", "/", token=False, origin="null")[0], 403)
        self.assertEqual(self.rpc("report.export", origin=f"http://{self.host}")["error"]["data"]["code"], "invalid_input")

    def test_preflight_nao_libera_outra_origem(self):
        status, cab, _ = self.pedir("OPTIONS", "/rpc", token=False, origin="http://evil.example",
                                    extra={"Access-Control-Request-Method": "POST"})
        self.assertGreaterEqual(status, 400)
        self.assertNotIn("Access-Control-Allow-Origin", cab)

    def test_metodo_fora_da_allowlist(self):
        self.assertEqual(self.rpc("workspace.open", {"path": "/"})["error"]["code"], -32601)

    def test_tipo_de_conteudo_e_tamanho(self):
        self.assertEqual(self.pedir("POST", "/rpc", b"{}", tipo="text/plain")[0], 415)
        self.assertEqual(self.pedir("POST", "/upload?kind=spec", b"{}", tipo="application/json")[0], 415)
        self.assertEqual(self.pedir("POST", "/upload?kind=nada", b"{}", tipo="application/octet-stream")[0], 400)
        # Content-Length acima do teto: recusado sem ler o corpo (que nem foi enviado).
        status, _, _ = self.pedir("POST", "/upload?kind=spec", None, tipo="application/octet-stream",
                                  extra={"Content-Length": str(6 * 1024 * 1024)})
        self.assertEqual(status, 413)
        status, _, _ = self.pedir("POST", "/rpc", None, tipo="application/json",
                                  extra={"Content-Length": "abc"})
        self.assertEqual(status, 411)
        status, _, _ = self.pedir("POST", "/rpc", None, tipo="application/json",
                                  extra={"Transfer-Encoding": "chunked"})
        self.assertEqual(status, 411)

    def test_rota_desconhecida(self):
        self.assertEqual(self.pedir("GET", "/etc/passwd")[0], 404)
        self.assertEqual(self.pedir("POST", "/rpc/../x", b"{}", tipo="application/json")[0], 404)


class TestFluxoCompleto(Servidor):
    def test_relatorio_igual_ao_servico_direto(self):
        spec = self.enviar("spec", json.dumps(SPEC, ensure_ascii=False).encode())
        log = self.enviar("log", json.dumps(LOG, ensure_ascii=False).encode())
        resposta = self.rpc("report.audit", {"spec_path": spec, "log_path": log, "source": "file"})["result"]

        with tempfile.TemporaryDirectory() as pasta:
            spec_path, log_path = gravar(Path(pasta))
            direto = ReportService(documents_dir=Path(pasta))
            items, caminho = direto.read_log(str(log_path))
            esperado = direto.audit(str(spec_path), items, source="file", log_path=caminho)
        self.assertEqual(resposta["summary"], esperado["summary"])
        self.assertEqual(resposta["results"], esperado["results"])

        arquivos = self.rpc("report.export", {"directory": "/tmp"})["result"]["files"]
        html = next(f for f in arquivos if f["kind"] == "html")
        status, cab, corpo = self.pedir("GET", f"/download/{html['id']}")
        self.assertEqual(status, 200)
        self.assertIn("attachment", cab["Content-Disposition"])
        self.assertEqual(len(corpo), html["bytes"])
        self.assertEqual(self.pedir("GET", f"/download/{html['id']}", token=False)[0], 401)
        self.assertEqual(self.pedir("GET", "/download/nao-existe")[0], 404)

        status, _, dados = self.pedir("POST", "/ticket", json.dumps({"id": html["id"]}), tipo="application/json")
        self.assertEqual(status, 200)
        bilhete = json.loads(dados)["view"]
        status, cab, corpo = self.pedir("GET", f"/view/{bilhete}", token=False)
        self.assertEqual(status, 200)
        self.assertTrue(cab["Content-Security-Policy"].startswith("sandbox allow-scripts"))
        self.assertTrue(cab["Content-Type"].startswith("text/html"))
        self.assertIn(b"<!doctype html>", corpo[:40].lower())
        # Uso único: o endereço do iframe não vira chave permanente.
        self.assertEqual(self.pedir("GET", f"/view/{bilhete}", token=False)[0], 404)

    def test_caminho_fora_da_sessao_pela_rede(self):
        with tempfile.TemporaryDirectory() as pasta:
            spec_path, _ = gravar(Path(pasta))
            resposta = self.rpc("report.spec", {"path": str(spec_path)})
        self.assertEqual(resposta["error"]["data"]["code"], "invalid_input")

    def test_analytics_do_logcat(self):
        status, _, dados = self.pedir("POST", "/analytics", LOGCAT.encode("utf-8"), tipo="application/octet-stream")
        self.assertEqual(status, 200)
        resposta = json.loads(dados)
        self.assertEqual([e["event_name"] for e in resposta["events"]], ["screen_view", "add_to_cart"])
        status, _, dados = self.pedir("POST", "/analytics", b"\xff\xfe" + LOGCAT.encode("utf-16-le"),
                                      tipo="application/octet-stream")
        self.assertEqual(len(json.loads(dados)["events"]), 2)


class TestHost(unittest.TestCase):
    def test_host_fora_do_loopback_e_recusado(self):
        for host in ("0.0.0.0", "::", "192.168.0.10", "exemplo.com", ""):
            with self.subTest(host=host), self.assertRaises(SystemExit) as saida:
                main(["--host", host, "--no-browser"])
            self.assertEqual(saida.exception.code, 2)
            with self.assertRaises(ValueError):
                WebServer(host, 0)


BOOT = r"""
import os, runpy, sys
sys.path.insert(0, {src!r})
# Simula o que o Windows não tem. Não é um Windows: é o que dá para pegar daqui.
for nome in ("getuid", "geteuid", "getgid", "fchmod", "O_NOFOLLOW", "O_DIRECTORY", "killpg", "setsid"):
    if hasattr(os, nome):
        delattr(os, nome)
for modulo in ("AppKit", "Quartz", "objc", "Foundation", "fcntl", "termios", "pwd", "grp", "resource"):
    sys.modules[modulo] = None
sys.argv = ["mobaile-web", "--no-browser"]
runpy.run_module("mobaile.web", run_name="__main__", alter_sys=True)
"""


class TestPortabilidadeSimulada(unittest.TestCase):
    def test_sobe_sem_apis_posix_nem_macos(self):
        proc = subprocess.Popen(
            [sys.executable, "-I", "-c", BOOT.format(src=str(SRC))],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        try:
            url = ""
            for _ in range(10):
                linha = proc.stdout.readline()
                if not linha or "http://" in linha:
                    url = linha.strip().split()[-1] if linha else ""
                    break
            self.assertTrue(url.startswith("http://127.0.0.1:"), proc.stderr.read() if proc.poll() is not None else url)
            endereco, token = url[len("http://"):].split("/#t=")
            porta = int(endereco.rsplit(":", 1)[1])
            conn = http.client.HTTPConnection("127.0.0.1", porta, timeout=10)
            conn.request("POST", "/analytics", body=LOGCAT.encode(),
                         headers={"Host": endereco, TOKEN_HEADER: token, "Content-Type": "application/octet-stream"})
            resposta = conn.getresponse()
            self.assertEqual(resposta.status, 200)
            self.assertEqual(len(json.loads(resposta.read())["events"]), 2)
            conn.close()
        finally:
            proc.terminate()
            try:
                proc.wait(10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(5)
            proc.stdout.close()
            proc.stderr.close()
        if os.name != "nt":  # no Windows, terminate() não passa pelo SIGTERM
            self.assertEqual(proc.returncode, 0)
