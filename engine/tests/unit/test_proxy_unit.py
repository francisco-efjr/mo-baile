"""Testes unitários das melhorias do proxy e ADBBridge."""

import http.client
import io
import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.proxy import (
    MAX_BODY_CAPTURE,
    MAX_CONCURRENT_CONNECTIONS,
    MobileNetworkProxy,
    ProxyRequestHandler,
)


class TestProxyUnit(unittest.TestCase):
    def forward_response(self, payload, response_headers):
        handler = object.__new__(ProxyRequestHandler)
        client = MagicMock()
        chunks = []
        client.sendall.side_effect = chunks.append
        response = MagicMock(status=200, reason="OK")
        response.getheaders.return_value = response_headers
        response.chunked = any(key.lower() == "transfer-encoding" and value.lower() == "chunked"
                               for key, value in response_headers)
        cursor = 0
        read_sizes = []

        def read(amount=None):
            nonlocal cursor
            read_sizes.append(amount)
            size = len(payload) if amount is None else amount
            chunk = payload[cursor:cursor + size]
            cursor += len(chunk)
            return chunk

        response.read.side_effect = read
        connection = MagicMock()
        connection.getresponse.return_value = response
        proxy = MobileNetworkProxy()
        target = "http://example.test/api?access_token=token-sintetico&item=1"
        with patch("mobaile.adapters.proxy.http.client.HTTPConnection", return_value=connection):
            handler._handle_http(client, "GET", target, {
                "Host": "example.test", "Proxy-Authorization": "Basic proxy-sintetico",
                "Authorization": "Bearer origem-sintetica",
            }, "HTTP/1.1",
                                 b"GET / HTTP/1.1\r\n\r\n", 1, 0, "00:00:00", proxy)
        self.assertNotIn("Proxy-Authorization", connection.request.call_args.kwargs["headers"])
        self.assertEqual(connection.request.call_args.kwargs["headers"]["Authorization"], "Bearer origem-sintetica")
        return b"".join(chunks), proxy.events_history[-1], read_sizes

    def test_resposta_grande_e_encaminhada_em_blocos_com_captura_limitada(self):
        payload = b"x" * (MAX_BODY_CAPTURE * 3)
        forwarded, event, read_sizes = self.forward_response(payload, [("Content-Type", "text/plain")])
        self.assertEqual(forwarded.split(b"\r\n\r\n", 1)[1], payload)
        self.assertTrue(all(size is not None and size <= 65536 for size in read_sizes), read_sizes)
        self.assertEqual(event.response_bytes, len(payload))
        self.assertTrue(event.body_truncated)
        self.assertLessEqual(len(event.response_body), MAX_BODY_CAPTURE + 200)

    def test_resposta_chunked_decodificada_tem_framing_http_valido(self):
        payload = b'{"status":"ok"}'
        forwarded, _, _ = self.forward_response(payload, [("Transfer-Encoding", "chunked")])
        socket = MagicMock()
        socket.makefile.return_value = io.BytesIO(forwarded)
        response = http.client.HTTPResponse(socket)
        self.addCleanup(response.close)
        response.begin()
        self.assertEqual(response.read(), payload)

    def test_url_e_path_capturados_nao_vazam_tokens(self):
        _, event, _ = self.forward_response(b"ok", [])
        for value in (event.url, event.path):
            self.assertNotIn("token-sintetico", value)
            self.assertIn("item=1", value)

    def test_corpo_com_content_encoding_e_encaminhado_sem_captura_binaria(self):
        payload = b"conteudo-comprimido-sintetico"
        forwarded, event, _ = self.forward_response(payload, [
            ("Content-Type", "application/json"), ("Content-Encoding", "gzip"),
        ])
        self.assertTrue(forwarded.endswith(payload))
        self.assertNotIn(payload.decode("ascii"), event.response_body)
        self.assertIn("não capturados", event.response_body)

    def test_leitura_de_cabecalho_recusa_limite_antes_do_delimitador(self):
        sock = MagicMock()
        sock.recv.side_effect = [b"x" * 4096] * 15 + [b"x" * 4093 + b"\r\n\r", b"\n"]
        self.assertEqual(ProxyRequestHandler._read_headers(sock), b"")

    def test_leitura_do_corpo_nao_encaminha_bytes_alem_do_content_length(self):
        handler = object.__new__(ProxyRequestHandler)
        body = handler._read_request_body(MagicMock(), {"Content-Length": "2"}, b"GET / HTTP/1.1\r\n\r\nokexcesso")
        self.assertEqual(body, b"ok")

    def test_framing_invalido_e_corpo_acima_do_teto_nao_chegam_ao_destino(self):
        for headers, expected in (
            ({"Content-Length": "-1"}, b"400"),
            ({"CONTENT-LENGTH": "16777217"}, b"413"),
            ({"Transfer-Encoding": "chunked"}, b"501"),
            ({"Content-Length": "10"}, b"400"),
        ):
            with self.subTest(headers=headers):
                handler = object.__new__(ProxyRequestHandler)
                client = MagicMock()
                client.recv.return_value = b""
                with patch("mobaile.adapters.proxy.http.client.HTTPConnection") as connection:
                    response = connection.return_value.getresponse.return_value
                    response.read.return_value = b""
                    response.getheaders.return_value = []
                    handler._handle_http(client, "POST", "http://example.test/api", headers, "HTTP/1.1",
                                         b"POST / HTTP/1.1\r\n\r\n", 1, 0, "00:00:00", MobileNetworkProxy())
                connection.assert_not_called()
                self.assertIn(expected, client.sendall.call_args.args[0])

    def test_erro_de_encaminhamento_nao_guarda_url_original_com_token(self):
        handler = object.__new__(ProxyRequestHandler)
        proxy = MobileNetworkProxy()
        target = "http://example.test/api?access_token=token-sintetico"
        with patch("mobaile.adapters.proxy.http.client.HTTPConnection") as connection:
            connection.return_value.request.side_effect = http.client.InvalidURL(f"URL inválida: {target}")
            handler._handle_http(MagicMock(), "GET", target, {}, "HTTP/1.1",
                                 b"GET / HTTP/1.1\r\n\r\n", 1, 0, "00:00:00", proxy)
        event = proxy.events_history[-1]
        self.assertEqual(event.status_code, 502)
        self.assertNotIn("token-sintetico", str(event.to_dict()))

    def test_eof_antes_do_content_length_registra_erro_sem_segunda_resposta(self):
        origin_socket = MagicMock()
        origin_socket.makefile.return_value = io.BytesIO(
            b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nok"
        )
        response = http.client.HTTPResponse(origin_socket)
        self.addCleanup(response.close)
        response.begin()
        handler = object.__new__(ProxyRequestHandler)
        client = MagicMock()
        chunks = []
        client.sendall.side_effect = chunks.append
        proxy = MobileNetworkProxy()
        with patch("mobaile.adapters.proxy.http.client.HTTPConnection") as connection:
            connection.return_value.getresponse.return_value = response
            handler._handle_http(client, "GET", "http://example.test/api", {}, "HTTP/1.1",
                                 b"GET / HTTP/1.1\r\n\r\n", 1, 0, "00:00:00", proxy)
        event = proxy.events_history[-1]
        self.assertEqual(event.error, "IncompleteRead")
        self.assertEqual(event.status_code, 200)
        self.assertEqual(event.response_bytes, 2)
        forwarded = b"".join(chunks)
        self.assertEqual(forwarded.count(b"HTTP/1.1 "), 1)
        self.assertTrue(forwarded.endswith(b"ok"))

    def test_head_204_e_304_nao_geram_erro_de_corpo_incompleto(self):
        for method, status in (("HEAD", 200), ("GET", 204), ("GET", 304)):
            with self.subTest(method=method, status=status):
                origin_socket = MagicMock()
                origin_socket.makefile.return_value = io.BytesIO(
                    f"HTTP/1.1 {status} OK\r\nContent-Length: 5\r\n\r\n".encode("ascii")
                )
                response = http.client.HTTPResponse(origin_socket, method=method)
                self.addCleanup(response.close)
                response.begin()
                handler = object.__new__(ProxyRequestHandler)
                proxy = MobileNetworkProxy()
                with patch("mobaile.adapters.proxy.http.client.HTTPConnection") as connection:
                    connection.return_value.getresponse.return_value = response
                    handler._handle_http(MagicMock(), method, "http://example.test/api", {}, "HTTP/1.1",
                                         b"GET / HTTP/1.1\r\n\r\n", 1, 0, "00:00:00", proxy)
                self.assertIsNone(proxy.events_history[-1].error)
                self.assertEqual(proxy.events_history[-1].status_code, status)

    def test_transfer_encoding_nao_decodificado_e_recusado_antes_do_status_200(self):
        origin_socket = MagicMock()
        origin_socket.makefile.return_value = io.BytesIO(
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: gzip, chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"
        )
        response = http.client.HTTPResponse(origin_socket)
        self.addCleanup(response.close)
        response.begin()
        self.assertFalse(response.chunked, "http.client não remove codings compostos")
        handler = object.__new__(ProxyRequestHandler)
        client = MagicMock()
        chunks = []
        client.sendall.side_effect = chunks.append
        proxy = MobileNetworkProxy()
        with patch("mobaile.adapters.proxy.http.client.HTTPConnection") as connection:
            connection.return_value.getresponse.return_value = response
            handler._handle_http(client, "GET", "http://example.test/api", {}, "HTTP/1.1",
                                 b"GET / HTTP/1.1\r\n\r\n", 1, 0, "00:00:00", proxy)
        forwarded = b"".join(chunks)
        self.assertTrue(forwarded.startswith(b"HTTP/1.1 502"))
        self.assertNotIn(b"hello", forwarded)
        self.assertEqual(proxy.events_history[-1].error, "HTTPException")

    def test_max_concurrent_connections_elevado(self):
        self.assertGreaterEqual(MAX_CONCURRENT_CONNECTIONS, 512)

    def test_parse_content_length(self):
        self.assertEqual(ProxyRequestHandler._parse_content_length({"Content-Length": "123"}), 123)
        self.assertEqual(ProxyRequestHandler._parse_content_length({"Content-Length": "-10"}), 0)
        self.assertEqual(ProxyRequestHandler._parse_content_length({"Content-Length": "invalid"}), 0)


class TestADBBridgeProxyControl(unittest.TestCase):
    def setUp(self):
        self.adb = ADBBridge()

    def test_setup_reverse_proxy_sucesso(self):
        self.adb._run_cmd = MagicMock(return_value=(0, b"ok", b""))
        res = self.adb.setup_reverse_proxy("device1", 8082)
        self.assertTrue(res)

        calls = [c[0][0] for c in self.adb._run_cmd.call_args_list]
        # Deve chamar reverse, depois captive_portal_mode 0, depois settings put global http_proxy
        self.assertTrue(any("reverse" in c and "tcp:8082" in c for c in calls))
        self.assertTrue(any("captive_portal_mode" in c and "0" in c for c in calls))
        self.assertTrue(any("http_proxy" in c and "127.0.0.1:8082" in c for c in calls))

    def test_setup_reverse_proxy_falha_reverse_nao_seta_proxy(self):
        self.adb._run_cmd = MagicMock(return_value=(1, b"", b"device offline"))
        res = self.adb.setup_reverse_proxy("device1", 8082)
        self.assertFalse(res)

        calls = [c[0][0] for c in self.adb._run_cmd.call_args_list]
        # Não deve configurar http_proxy se o adb reverse falhou
        self.assertFalse(any("http_proxy" in c for c in calls))

    def test_setup_reverse_proxy_rollback_se_settings_falhar(self):
        # Primeiro comando (reverse) passa, segundo (captive_portal) passa, terceiro (http_proxy) falha
        self.adb._run_cmd = MagicMock(side_effect=[
            (0, b"ok", b""),
            (0, b"ok", b""),
            (1, b"", b"permission denied"),
            (0, b"ok", b""),
            (0, b"ok", b""),
        ])
        res = self.adb.setup_reverse_proxy("device1", 8082)
        self.assertFalse(res)

        calls = [c[0][0] for c in self.adb._run_cmd.call_args_list]
        # Deve ter executado rollback do captive_portal_mode e do reverse
        self.assertTrue(any("captive_portal_mode" in c and "delete" in c for c in calls))
        self.assertTrue(any("--remove" in c for c in calls))

    def test_teardown_reverse_proxy_restaura_tudo(self):
        self.adb._run_cmd = MagicMock(return_value=(0, b"ok", b""))
        res = self.adb.teardown_reverse_proxy("device1", 8082)
        self.assertTrue(res)

        calls = [c[0][0] for c in self.adb._run_cmd.call_args_list]
        self.assertTrue(any("captive_portal_mode" in c and "delete" in c for c in calls))
        self.assertTrue(any("http_proxy" in c and ":0" in c for c in calls))
        self.assertTrue(any("--remove" in c for c in calls))


if __name__ == "__main__":
    unittest.main()
