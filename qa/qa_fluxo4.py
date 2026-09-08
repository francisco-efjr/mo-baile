import sys

"""FLUXO 4 — HTTPS: tunel CONNECT real, redacao e limites."""
import http.server
import json
import pathlib
import socket
import ssl
import threading
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "engine" / "src"))

from mobaile.adapters.proxy import MAX_BODY_CAPTURE, MobileNetworkProxy

falhas, passes = [], []
def check(nome, cond, detalhe=""):
    (passes if cond else falhas).append(nome)
    print(f"  [{'PASS' if cond else 'FALHA'}] {nome}" + (f"  -> {detalhe}" if detalhe and not cond else ""))

def porta_livre():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0)); return s.getsockname()[1]

# ---------------------------------------------------------------- origem TLS
class AppAmobs(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def _responder(self, corpo, ctype="application/json", status=200):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(corpo)))
        self.send_header("Set-Cookie", "sessao=abc123secreto; Path=/")
        self.end_headers()
        self.wfile.write(corpo)
    def do_GET(self):
        if self.path.startswith("/binario"):
            return self._responder(bytes(range(256)) * 40, "application/octet-stream")
        if self.path.startswith("/grande"):
            return self._responder(b"x" * (MAX_BODY_CAPTURE + 9000), "text/plain")
        self._responder(json.dumps({
            "status": "PRE_APROVADO", "parcelas": 12,
            "token": "eyJhbGciOiJIUzI1NiJ9.credencial.real",
            "cpf": "000.000.000-00",
        }).encode())
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        self.rfile.read(n)
        self._responder(json.dumps({"status": "PRE_APROVADO"}).encode(), status=201)
    def log_message(self, *_a): pass

def _garantir_certificado():
    """Gera o certificado autoassinado da origem HTTPS, se ainda nao existir."""
    import subprocess
    aqui = pathlib.Path(__file__).resolve().parent
    cert, chave = aqui / "cert.pem", aqui / "key.pem"
    if not (cert.exists() and chave.exists()):
        subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-keyout", str(chave),
             "-out", str(cert), "-days", "2", "-nodes", "-subj", "/CN=api.amobs.local"],
            capture_output=True, check=True,
        )
    return str(cert), str(chave)


_cert, _chave = _garantir_certificado()
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(_cert, _chave)
origem_https = http.server.HTTPServer(("127.0.0.1", 0), AppAmobs)
origem_https.socket = ctx.wrap_socket(origem_https.socket, server_side=True)
PORTA_HTTPS = origem_https.server_address[1]
threading.Thread(target=origem_https.serve_forever, daemon=True).start()

origem_http = http.server.HTTPServer(("127.0.0.1", 0), AppAmobs)
PORTA_HTTP = origem_http.server_address[1]
threading.Thread(target=origem_http.serve_forever, daemon=True).start()

print("=" * 78)
print("FLUXO 4 — HTTPS (app amobs)")
print("=" * 78)
print(f"  origem HTTPS em :{PORTA_HTTPS} · origem HTTP em :{PORTA_HTTP}\n")

proxy = MobileNetworkProxy(port=porta_livre())
assert proxy.start()

def ultimo_evento(timeout=5):
    limite = time.time() + timeout
    while time.time() < limite:
        if proxy.events_history:
            return proxy.events_history[-1]
        time.sleep(0.02)
    raise AssertionError("nenhum evento capturado")

try:
    # ============ 4.1 tunel CONNECT com TLS de verdade ======================
    print("  --- 4.1 tunel HTTPS ---")
    cliente_ctx = ssl.create_default_context()
    cliente_ctx.check_hostname = False
    cliente_ctx.verify_mode = ssl.CERT_NONE

    bruto = socket.create_connection(("127.0.0.1", proxy.port), timeout=8)
    bruto.sendall(
        f"CONNECT 127.0.0.1:{PORTA_HTTPS} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{PORTA_HTTPS}\r\n\r\n".encode())
    resposta = bruto.recv(4096)
    check("proxy aceita CONNECT", b"200" in resposta, resposta[:60].decode(errors="replace"))

    tls = cliente_ctx.wrap_socket(bruto, server_hostname="api.amobs.local")
    tls.sendall(
        "GET /v2/credito/simulacao HTTP/1.1\r\nHost: api.amobs.local\r\n"
        "Authorization: Bearer token-de-producao-do-cliente\r\nConnection: close\r\n\r\n".encode())
    corpo = b""
    tls.settimeout(6)
    while True:
        try:
            pedaco = tls.recv(65536)
        except (socket.timeout, ssl.SSLError, OSError):
            break
        if not pedaco: break
        corpo += pedaco
    tls.close()

    check("handshake TLS completa atraves do tunel", b"PRE_APROVADO" in corpo,
          corpo[:80].decode(errors="replace"))

    ev = ultimo_evento()
    check("tunel registrado como evento", ev.method == "CONNECT", ev.method)
    check("evento marcado como tunel", ev.is_tunnel is True)
    check("host e porta de destino registrados",
          ev.host == "127.0.0.1" and ev.path == f":{PORTA_HTTPS}", f"{ev.host}{ev.path}")
    check("bytes do tunel contabilizados", ev.response_bytes > 100, str(ev.response_bytes))
    print(f"       {ev.summary()}  |  {ev.response_body}")

    # LIMITE HONESTO: o tunel nao decifra, entao corpo e headers ficam opacos.
    check("corpo do HTTPS NAO e inspecionavel (limitacao conhecida)",
          "PRE_APROVADO" not in ev.response_body and ev.request_body == "",
          "o proxy estaria decifrando TLS sem CA, o que nao e o caso")
    check("credencial do app nao aparece no evento do tunel",
          "token-de-producao" not in json.dumps(ev.to_dict()))

    # ============ 4.2 HTTP em claro: inspecao e redacao =====================
    print("\n  --- 4.2 HTTP em claro ---")
    def via_proxy(bruto_req, ler=True):
        with socket.create_connection(("127.0.0.1", proxy.port), timeout=8) as s:
            s.sendall(bruto_req)
            if not ler: return b""
            s.settimeout(6); saida = b""
            while True:
                try: p = s.recv(65536)
                except socket.timeout: break
                if not p: break
                saida += p
            return saida

    req = (f"GET http://127.0.0.1:{PORTA_HTTP}/v2/credito/simulacao HTTP/1.1\r\n"
           f"Host: 127.0.0.1:{PORTA_HTTP}\r\n"
           f"Authorization: Bearer token-de-producao-do-cliente\r\n"
           f"Cookie: sessao=abc123secreto\r\n"
           f"User-Agent: amobs/3.2.1 (Android)\r\nConnection: close\r\n\r\n").encode()
    resp = via_proxy(req)
    check("resposta em claro chega ao cliente", b"PRE_APROVADO" in resp)

    ev = ultimo_evento()
    check("requisicao registrada", ev.method == "GET" and ev.status_code == 200, f"{ev.method} {ev.status_code}")
    check("path preservado", "/v2/credito/simulacao" in ev.path, ev.path)
    check("corpo da resposta inspecionavel", "PRE_APROVADO" in ev.response_body)
    check("User-Agent do app preservado", "amobs" in ev.request_headers.get("User-Agent", ""))

    auth = ev.request_headers.get("Authorization", "")
    check("Authorization redigido", "token-de-producao" not in auth and "redigido" in auth, auth)
    cookie = ev.request_headers.get("Cookie", "")
    check("Cookie redigido", "abc123secreto" not in cookie, cookie)
    check("Set-Cookie da resposta redigido",
          "abc123secreto" not in ev.response_headers.get("Set-Cookie", ""),
          ev.response_headers.get("Set-Cookie", ""))
    check("token no corpo da resposta redigido", "credencial.real" not in ev.response_body, ev.response_body[:90])
    check("CPF no corpo redigido", "000.000.000-00" not in ev.response_body, ev.response_body[:90])
    check("campo util preservado", '"parcelas":12' in ev.response_body.replace(" ", ""), ev.response_body[:90])
    print(f"       corpo capturado: {ev.response_body[:100]}")

    corpo_post = '{"valor":1500,"senha":"minhasenha","cpf":"111.222.333-44"}'
    req = (f"POST http://127.0.0.1:{PORTA_HTTP}/v2/credito/simulacao HTTP/1.1\r\n"
           f"Host: 127.0.0.1:{PORTA_HTTP}\r\nContent-Type: application/json\r\n"
           f"Content-Length: {len(corpo_post)}\r\nConnection: close\r\n\r\n{corpo_post}").encode()
    via_proxy(req)
    ev = ultimo_evento()
    check("POST registrado com status 201", ev.status_code == 201, str(ev.status_code))
    check("senha no corpo da requisicao redigida", "minhasenha" not in ev.request_body, ev.request_body)
    check("CPF na requisicao redigido", "111.222.333-44" not in ev.request_body, ev.request_body)
    check("valor de negocio preservado", '"valor":1500' in ev.request_body, ev.request_body)

    # ============ 4.3 limites e robustez ====================================
    print("\n  --- 4.3 limites ---")
    via_proxy((f"GET http://127.0.0.1:{PORTA_HTTP}/grande HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n").encode())
    ev = ultimo_evento()
    check("corpo grande e truncado", ev.body_truncated is True)
    check("truncamento respeita o teto", len(ev.response_body) <= MAX_BODY_CAPTURE + 300, str(len(ev.response_body)))
    check("tamanho real registrado", ev.response_bytes > MAX_BODY_CAPTURE, str(ev.response_bytes))

    via_proxy((f"GET http://127.0.0.1:{PORTA_HTTP}/binario HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n").encode())
    ev = ultimo_evento()
    check("binario nao vira lixo utf-8", "binários não capturados" in ev.response_body, ev.response_body[:60])

    resp = via_proxy(b"GET http://connectivitycheck.gstatic.com/generate_204 HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    check("checagem de conectividade do Android respondida", b"204" in resp, resp[:40].decode(errors="replace"))
    check("204 registrado", ultimo_evento().status_code == 204)

    morta = porta_livre()
    resp = via_proxy(f"GET http://127.0.0.1:{morta}/nada HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".encode())
    check("destino inalcancavel devolve 502", b"502" in resp)
    check("502 nao vaza detalhe interno da rede", b"Connection refused" not in resp and b"127.0.0.1" not in resp,
          resp[:120].decode(errors="replace"))
    check("erro fica registrado para quem depura", ultimo_evento().error is not None)

    resp = via_proxy(f"POST http://127.0.0.1:{PORTA_HTTP}/x HTTP/1.1\r\nHost: x\r\nContent-Length: abc\r\nConnection: close\r\n\r\n".encode())
    check("Content-Length invalido nao derruba o proxy", proxy.is_running() is True)

    check("proxy segue no ar apos toda a bateria", proxy.is_running() is True)
    print(f"\n  total de eventos capturados: {len(proxy.events_history)}")
finally:
    proxy.stop()
    origem_https.shutdown(); origem_http.shutdown()

print(f"\n  RESULTADO: {len(passes)} passaram, {len(falhas)} falharam")
if falhas: print("  FALHAS:", falhas)
sys.exit(1 if falhas else 0)
