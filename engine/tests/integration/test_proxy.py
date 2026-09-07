"""Proxy de interceptacao: comportamento de ponta a ponta e limites de seguranca.

Nota sobre a versao anterior deste arquivo: ele usava `urllib` com ProxyHandler
para atravessar o proxy. Funciona na maquina do dev, mas `urllib` consulta
`no_proxy` e ignora o proxy para 127.0.0.1 em qualquer ambiente que tenha essa
variavel (CI e containers costumam ter). O teste passava por acaso: a
requisicao ia direto ao destino e nada era interceptado.

Aqui a requisicao e montada no socket, exatamente como um aparelho faz:
linha de requisicao com URI absoluta. Ficou deterministico e ainda exercita o
parser real do proxy.
"""

import http.server
import socket
import socketserver
import threading
import time
import unittest

from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.proxy import (
    MAX_BODY_CAPTURE,
    MAX_HISTORY,
    MobileNetworkProxy,
    NetworkEvent,
    ProxyRequestHandler,
)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class DummyHTTPHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/grande"):
            payload = b"x" * (MAX_BODY_CAPTURE + 5000)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        if self.path.startswith("/binario"):
            payload = bytes(range(256)) * 8
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        body = b'{"status": "ok", "message": "hello mobile", "token": "abc123"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-Custom-Header", "TestValue")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


class ProxyTestBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        socketserver.TCPServer.allow_reuse_address = True
        cls.origin = socketserver.TCPServer(("127.0.0.1", 0), DummyHTTPHandler)
        cls.origin_port = cls.origin.server_address[1]
        cls.origin_thread = threading.Thread(target=cls.origin.serve_forever, daemon=True)
        cls.origin_thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.origin.shutdown()
        cls.origin.server_close()

    def setUp(self):
        self.proxy = MobileNetworkProxy(port=free_port())
        self.assertTrue(self.proxy.start(), "proxy deveria subir em porta livre")
        self.addCleanup(self.proxy.stop)

    def send_through_proxy(self, raw_request: bytes, read_response: bool = True) -> bytes:
        with socket.create_connection(("127.0.0.1", self.proxy.port), timeout=5) as sock:
            sock.sendall(raw_request)
            if not read_response:
                return b""
            sock.settimeout(5)
            chunks = []
            while True:
                try:
                    chunk = sock.recv(65536)
                except TimeoutError:
                    break
                if not chunk:
                    break
                chunks.append(chunk)
            return b"".join(chunks)

    def get(self, path: str = "/api/v1/test", extra_headers: str = "") -> bytes:
        request = (
            f"GET http://127.0.0.1:{self.origin_port}{path} HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{self.origin_port}\r\n"
            "User-Agent: MobileTestAgent/1.0\r\n"
            f"{extra_headers}"
            "Connection: close\r\n\r\n"
        )
        return self.send_through_proxy(request.encode())

    def last_event(self, timeout: float = 3.0) -> NetworkEvent:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.proxy.events_history:
                return self.proxy.events_history[-1]
            time.sleep(0.02)
        self.fail("nenhum evento capturado dentro do tempo esperado")


class TestProxyLifecycle(unittest.TestCase):
    def test_lifecycle(self):
        proxy = MobileNetworkProxy(port=free_port())
        self.assertFalse(proxy.is_running())
        self.assertTrue(proxy.start())
        self.assertTrue(proxy.is_running())
        self.assertTrue(proxy.start(), "start repetido deve ser idempotente")
        proxy.stop()
        self.assertFalse(proxy.is_running())
        proxy.stop()  # stop repetido nao pode levantar

    def test_porta_ocupada_nao_derruba(self):
        port = free_port()
        blocker = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        blocker.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        blocker.bind(("127.0.0.1", port))
        blocker.listen(1)
        try:
            proxy = MobileNetworkProxy(port=port)
            self.assertFalse(proxy.start(), "porta ocupada deve devolver False, nao excecao")
            self.assertFalse(proxy.is_running())
        finally:
            blocker.close()

    def test_escuta_somente_no_loopback_por_padrao(self):
        proxy = MobileNetworkProxy()
        self.assertEqual(proxy.host, "127.0.0.1")


class TestProxyInterception(ProxyTestBase):
    def test_requisicao_http_e_interceptada(self):
        response = self.get()
        self.assertIn(b"hello mobile", response)

        event = self.last_event()
        self.assertEqual(event.method, "GET")
        self.assertEqual(event.status_code, 200)
        self.assertIn("/api/v1/test", event.path)
        self.assertIn("hello mobile", event.response_body)
        self.assertIn("MobileTestAgent", event.request_headers.get("User-Agent", ""))
        self.assertEqual(event.response_headers.get("X-Custom-Header"), "TestValue")

    def test_generate_204_responde_sem_ir_a_rede(self):
        request = (
            "GET http://connectivitycheck.gstatic.com/generate_204 HTTP/1.1\r\n"
            "Host: connectivitycheck.gstatic.com\r\nConnection: close\r\n\r\n"
        )
        response = self.send_through_proxy(request.encode())
        self.assertIn(b"204", response)
        self.assertEqual(self.last_event().status_code, 204)

    def test_header_sensivel_e_redigido(self):
        self.get(extra_headers="Authorization: Bearer super-secreto-do-cliente\r\n")
        event = self.last_event()
        auth = event.request_headers.get("Authorization", "")
        self.assertNotIn("super-secreto-do-cliente", auth)
        self.assertIn("redigido", auth)

    def test_campo_sensivel_no_corpo_e_redigido(self):
        event_body = '{"user":"bella","password":"1234"}'
        request = (
            f"POST http://127.0.0.1:{self.origin_port}/api/login HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{self.origin_port}\r\n"
            "Content-Type: application/json\r\n"
            f"Content-Length: {len(event_body)}\r\n"
            "Connection: close\r\n\r\n"
            f"{event_body}"
        )
        self.send_through_proxy(request.encode())
        event = self.last_event()
        self.assertNotIn("1234", event.request_body)
        self.assertIn("redigido", event.request_body)

    def test_corpo_grande_e_truncado(self):
        self.get("/grande")
        event = self.last_event()
        self.assertTrue(event.body_truncated)
        self.assertLessEqual(len(event.response_body), MAX_BODY_CAPTURE + 200)
        self.assertGreater(event.response_bytes, MAX_BODY_CAPTURE)

    def test_corpo_binario_nao_vira_lixo_utf8(self):
        self.get("/binario")
        event = self.last_event()
        self.assertIn("binários não capturados", event.response_body)

    def test_destino_inalcancavel_devolve_502_sem_vazar_detalhe(self):
        request = (
            f"GET http://127.0.0.1:{free_port()}/nada HTTP/1.1\r\n"
            "Host: 127.0.0.1\r\nConnection: close\r\n\r\n"
        )
        response = self.send_through_proxy(request.encode())
        self.assertIn(b"502", response)
        # A mensagem de excecao (que carrega endereco/porta internos) fica no
        # evento para quem depura, mas nao volta para o app sob teste.
        self.assertNotIn(b"Connection refused", response)
        self.assertIsNotNone(self.last_event().error)


class TestProxyLimits(unittest.TestCase):
    def test_content_length_invalido_nao_derruba(self):
        for raw in ("abc", "-5", "999999999999999999999", ""):
            with self.subTest(content_length=raw):
                value = ProxyRequestHandler._parse_content_length({"Content-Length": raw})
                self.assertIsInstance(value, int)
                self.assertGreaterEqual(value, 0)
                self.assertLessEqual(value, 16 * 1024 * 1024)

    def test_historico_e_circular(self):
        proxy = MobileNetworkProxy(port=free_port())
        for index in range(MAX_HISTORY + 50):
            proxy.emit_event(
                NetworkEvent(
                    id=index, timestamp=0.0, time_str="00:00:00", method="GET",
                    url="http://x/", host="x", path="/", status_code=200, status_text="OK",
                )
            )
        self.assertEqual(len(proxy.events_history), MAX_HISTORY)
        self.assertEqual(proxy.events_history[-1].id, MAX_HISTORY + 49)

    def test_callback_que_explode_nao_derruba_o_proxy(self):
        proxy = MobileNetworkProxy(port=free_port())
        recebidos = []
        proxy.add_event_callback(lambda _e: (_ for _ in ()).throw(RuntimeError("boom")))
        proxy.add_event_callback(recebidos.append)
        proxy.emit_event(
            NetworkEvent(id=1, timestamp=0.0, time_str="00:00:00", method="GET", url="http://x/",
                         host="x", path="/", status_code=200, status_text="OK")
        )
        self.assertEqual(len(recebidos), 1, "callback seguinte deve continuar recebendo")


class TestADBProxyIntegration(unittest.TestCase):
    def test_metodos_de_proxy_existem_no_adb(self):
        adb = ADBBridge()
        for name in ("setup_reverse_proxy", "teardown_reverse_proxy", "is_proxy_configured"):
            self.assertTrue(callable(getattr(adb, name, None)), f"ADBBridge.{name} ausente")


if __name__ == "__main__":
    unittest.main()
