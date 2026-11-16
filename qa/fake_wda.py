"""WebDriverAgent falso, suficiente para os caminhos que o app usa."""
import http.server
import json
import threading

from fakebin._qa_common import IOS_XML  # noqa: E402

CHAMADAS = []


class Handler(http.server.BaseHTTPRequestHandler):
    def _json(self, payload, status=200):
        corpo = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(corpo)))
        self.end_headers()
        self.wfile.write(corpo)

    def do_GET(self):
        CHAMADAS.append(("GET", self.path, None))
        if self.path.endswith("/status"):
            self._json({"sessionId": "QA-SESSION", "value": {"state": "success"}})
        elif self.path.endswith("/source"):
            self._json({"value": IOS_XML})
        else:
            self._json({"value": {}})

    def do_POST(self):
        tamanho = int(self.headers.get("Content-Length", 0) or 0)
        corpo = self.rfile.read(tamanho).decode() if tamanho else ""
        CHAMADAS.append(("POST", self.path, corpo))
        if self.path.endswith("/session"):
            self._json({"sessionId": "QA-SESSION", "value": {"sessionId": "QA-SESSION"}})
        else:
            self._json({"value": None})

    def do_DELETE(self):
        CHAMADAS.append(("DELETE", self.path, None))
        self._json({"value": None})

    def log_message(self, *_a):
        pass


def start(port=8100):
    servidor = http.server.HTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=servidor.serve_forever, daemon=True).start()
    return servidor
