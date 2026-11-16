"""Servidor HTTP do front web local: só loopback, token por sessão, sem CORS.

Ordem de cada requisição, sem exceção de rota:

1. `Host` precisa ser `127.0.0.1:PORTA`, `localhost:PORTA` ou `[::1]:PORTA`,
   senão 421 (fecha o DNS rebinding);
2. `Origin`, quando vem, precisa ser a do próprio servidor, senão 403;
3. a página e os estáticos saem sem token (são públicos e não têm dado);
   `/view/<bilhete>` usa bilhete de uso único, porque o iframe não manda
   cabeçalho; o resto exige `X-Mobaile-Token`, comparado em tempo constante.

O token vai no fragmento da URL (`#t=`), que o navegador não envia ao servidor.
Nenhuma linha de acesso é registrada: a URL e o token não vão para log.
"""

from __future__ import annotations

import hmac
import json
import logging
import secrets
import socket
import socketserver
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlsplit

from mobaile.domain.errors import InvalidInputError
from mobaile.security import MAX_LOG_BYTES
from mobaile.web.handlers import WebHandlers
from mobaile.web.sandbox import UPLOAD_LIMITS, Session

logger = logging.getLogger(__name__)

# Nome aceito em --host -> endereço do bind. Qualquer outro é recusado.
LOOPBACK = {"127.0.0.1": "127.0.0.1", "localhost": "127.0.0.1", "::1": "::1"}
TOKEN_HEADER = "X-Mobaile-Token"
MAX_RPC_BYTES = 1024 * 1024
_STATIC = Path(__file__).resolve().parent / "static"
_REPORT_HTML = Path(__file__).resolve().parents[1] / "services" / "report" / "html"
# Lista fechada: o servidor não serve pasta, só estes arquivos.
STATIC_FILES = {
    "/": (_STATIC / "index.html", "text/html; charset=utf-8"),
    "/static/app.js": (_STATIC / "app.js", "text/javascript; charset=utf-8"),
    "/static/app.css": (_STATIC / "app.css", "text/css; charset=utf-8"),
    "/static/design_system.css": (_REPORT_HTML / "design_system.css", "text/css; charset=utf-8"),
}
PAGE_CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; "
            "frame-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
API_CSP = "default-src 'none'; frame-ancestors 'none'; sandbox"
# O HTML do relatório traz a própria CSP com hash dos scripts; aqui ele ganha
# origem opaca, sem acesso à página que guarda o token.
VIEW_CSP = "sandbox allow-scripts; frame-ancestors 'self'"


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    # No Windows, SO_REUSEADDR deixa outro processo ocupar a mesma porta.
    allow_reuse_address = False
    app: WebServer

    def server_bind(self) -> None:
        # Sem o `getfqdn` do HTTPServer, que pode esperar DNS para 127.0.0.1.
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = "localhost", self.server_address[1]


class _Server6(_Server):
    address_family = socket.AF_INET6


class _Handler(BaseHTTPRequestHandler):
    server: _Server
    server_version = "Mobaile"
    sys_version = ""
    timeout = 30

    def log_message(self, format: str, *args: Any) -> None:
        """Sem linha de acesso: ela levaria a URL, e a do iframe tem o bilhete."""

    def do_GET(self) -> None:
        self._guarded("GET")

    def do_POST(self) -> None:
        self._guarded("POST")

    def _guarded(self, verb: str) -> None:
        try:
            self._route(verb)
        except Exception:
            logger.exception("Falha no front web (%s)", verb)
            self._json(500, {"error": "Erro interno."})

    def _route(self, verb: str) -> None:
        app = self.server.app
        if not app.host_ok(self.headers.get("Host")):
            return self._json(421, {"error": "Endereço não aceito."})
        origin = self.headers.get("Origin")
        if origin is not None and not app.origin_ok(origin):
            return self._json(403, {"error": "Origem não aceita."})
        url = urlsplit(self.path)
        if verb == "GET" and url.path in STATIC_FILES:
            path, content_type = STATIC_FILES[url.path]
            return self._send(200, path.read_bytes(), content_type, PAGE_CSP if url.path == "/" else API_CSP)
        if verb == "GET" and url.path.startswith("/view/"):
            target = app.session.redeem(url.path[len("/view/"):])
            if target is None:
                return self._json(404, {"error": "Bilhete vencido. Abra o relatório de novo."})
            return self._send(200, target.read_bytes(), "text/html; charset=utf-8", VIEW_CSP)
        if not app.token_ok(self.headers.get(TOKEN_HEADER)):
            return self._json(401, {"error": "Não autorizado."})
        if verb == "GET" and url.path.startswith("/download/"):
            target = app.session.lookup(url.path[len("/download/"):])
            if target is None:
                return self._json(404, {"error": "Arquivo não encontrado nesta sessão."})
            return self._send(200, target.read_bytes(), "application/octet-stream", API_CSP,
                              {"Content-Disposition": f'attachment; filename="{target.name}"'})
        if verb == "POST":
            return self._post(url.path, parse_qs(url.query).get("kind", [""])[0])
        return self._json(404, {"error": "Rota desconhecida."})

    def _post(self, path: str, kind: str) -> None:
        app = self.server.app
        routes = {"/rpc": "application/json", "/ticket": "application/json",
                  "/upload": "application/octet-stream", "/analytics": "application/octet-stream"}
        if path not in routes:
            return self._json(404, {"error": "Rota desconhecida."})
        if self.headers.get_content_type() != routes[path]:
            return self._json(415, {"error": f"Envie {routes[path]}."})
        limit = {"/upload": UPLOAD_LIMITS.get(kind), "/analytics": MAX_LOG_BYTES}.get(path, MAX_RPC_BYTES)
        if limit is None:
            return self._json(400, {"error": "Tipo de envio desconhecido: use spec ou log."})
        body = self._body(limit)
        if body is None:
            return None
        try:
            if path == "/rpc":
                return self._json(200, app.handlers.handle_rpc(body))
            if path == "/analytics":
                return self._json(200, app.handlers.analytics(body))
            if path == "/upload":
                return self._json(200, {"path": app.session.save_upload(kind, body), "bytes": len(body)})
            return self._json(200, {"view": app.session.ticket(_json_field(body, "id"))})
        except InvalidInputError as exc:
            return self._json(400, {"error": exc.message})

    def _body(self, limit: int) -> bytes | None:
        """Corpo com `Content-Length` conferido antes de ler; sem chunked."""
        raw = self.headers.get("Content-Length", "")
        if self.headers.get("Transfer-Encoding") or not (raw.isascii() and raw.isdigit()):
            self._json(411, {"error": "Envie o corpo com Content-Length."})
            return None
        if int(raw) > limit:
            self._json(413, {"error": f"Arquivo grande demais: o limite é {limit // (1024 * 1024) or 1} MB."})
            return None
        body = self.rfile.read(int(raw))
        if len(body) != int(raw):
            self._json(400, {"error": "Corpo incompleto."})
            return None
        return body

    def _json(self, status: int, payload: Any) -> None:
        body = json.dumps(payload, ensure_ascii=False, default=str).encode("utf-8")
        self._send(status, body, "application/json; charset=utf-8", API_CSP)

    def _send(self, status: int, body: bytes, content_type: str, csp: str, extra: dict[str, str] | None = None) -> None:
        self.send_response(status)
        headers = {
            "Content-Type": content_type, "Content-Length": str(len(body)), "Content-Security-Policy": csp,
            "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Cache-Control": "no-store",
            "Cross-Origin-Resource-Policy": "same-origin", **(extra or {}),
        }
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)


def _json_field(body: bytes, name: str) -> object:
    try:
        data = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InvalidInputError("JSON inválido.") from exc
    return data.get(name) if isinstance(data, dict) else None


class WebServer:
    """O servidor, a pasta da sessão e o token, criados juntos e fechados juntos."""

    def __init__(self, host: str = "127.0.0.1", port: int = 0) -> None:
        if host not in LOOPBACK:
            raise ValueError(f"Host recusado: {host!r}. Use 127.0.0.1, ::1 ou localhost.")
        bind = LOOPBACK[host]
        self.token = secrets.token_urlsafe(32)
        self.httpd = (_Server6 if ":" in bind else _Server)((bind, port), _Handler)
        self.httpd.app = self
        self.port: int = self.httpd.server_address[1]
        self.session = Session()
        self.handlers = WebHandlers(self.session)
        hosts = (f"127.0.0.1:{self.port}", f"localhost:{self.port}", f"[::1]:{self.port}")
        self._hosts = frozenset(hosts)
        self._origins = frozenset(f"http://{h}" for h in hosts)
        self.url = f"http://{'[::1]' if ':' in bind else '127.0.0.1'}:{self.port}/#t={self.token}"

    def host_ok(self, host: str | None) -> bool:
        return (host or "").lower() in self._hosts

    def origin_ok(self, origin: str) -> bool:
        return origin.lower() in self._origins

    def token_ok(self, value: str | None) -> bool:
        return value is not None and hmac.compare_digest(value.encode("utf-8"), self.token.encode("utf-8"))

    def serve_forever(self) -> None:
        self.httpd.serve_forever(poll_interval=0.5)

    def shutdown(self) -> None:
        """Para o laço; chamado de outra thread."""
        self.httpd.shutdown()

    def close(self) -> None:
        self.httpd.server_close()
        self.session.cleanup()
