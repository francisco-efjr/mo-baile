"""Proxy HTTP/HTTPS local para inspeção do tráfego do dispositivo.

O proxy fica no meio da sessão autenticada do app sob teste, então ele é ao
mesmo tempo a peça mais útil e a mais perigosa da ferramenta. As proteções
aqui são deliberadas:

- escuta apenas em 127.0.0.1; o alcance ao aparelho vem do `adb reverse`, e não
  de expor a porta na rede local, o que transformaria a máquina num proxy
  aberto para quem estiver no mesmo Wi-Fi;
- corpo capturado tem teto e o histórico é um buffer circular, porque um
  download grande passando pelo túnel derrubava o processo por consumo de
  memória;
- `Content-Length` vindo do cliente é validado antes de virar tamanho de
  leitura;
- headers e campos sensíveis são redigidos na entrada (ver
  `mobaile.security.redaction`);
- corpo binário não é forçado a UTF-8: vira um resumo, o que evita guardar
  megabytes de lixo ilegível;
- número de conexões simultâneas é limitado, para que um app em retry agressivo
  não esgote as threads do host.
"""

from __future__ import annotations

import datetime
import http.client
import logging
import queue
import select
import socket
import socketserver
import threading
import time
import urllib.parse
from collections import deque
from collections.abc import Callable

from mobaile.config import settings
from mobaile.domain.models import NetworkEvent
from mobaile.security import redact_body, redact_headers

logger = logging.getLogger(__name__)

__all__ = ["MobileNetworkProxy", "NetworkEvent", "ProxyRequestHandler", "network_interceptor"]

# Quanto de corpo guardamos por evento. Acima disso o conteúdo é truncado e o
# evento marcado com body_truncated=True.
MAX_BODY_CAPTURE = 256 * 1024
# Teto de leitura de corpo de requisição, independente do Content-Length anunciado.
MAX_REQUEST_BODY = 16 * 1024 * 1024
# Cabeçalho maior que isso é requisição malformada ou abuso.
MAX_HEADER_BYTES = 64 * 1024
# Eventos mantidos em memória (buffer circular).
MAX_HISTORY = 2000
# Conexões simultâneas atendidas.
MAX_CONCURRENT_CONNECTIONS = 128
# Túnel ocioso por mais que isso é encerrado.
TUNNEL_IDLE_TIMEOUT = 120.0

_TEXTUAL_HINTS = ("json", "text", "xml", "javascript", "html", "urlencoded", "graphql")


def _looks_textual(headers: dict[str, str]) -> bool:
    ctype = ""
    for key, value in headers.items():
        if key.lower() == "content-type":
            ctype = value.lower()
            break
    if not ctype:
        return True  # sem pista, tenta decodificar
    return any(hint in ctype for hint in _TEXTUAL_HINTS)


def _decode_body(raw: bytes, headers: dict[str, str]) -> tuple[str, bool]:
    """Devolve (texto_para_exibicao, foi_truncado)."""
    if not raw:
        return "", False
    truncated = len(raw) > MAX_BODY_CAPTURE
    chunk = raw[:MAX_BODY_CAPTURE]
    if not _looks_textual(headers):
        return f"«{len(raw)} bytes binários não capturados»", truncated
    text = chunk.decode("utf-8", errors="replace")
    if truncated:
        text += f"\n\n«truncado: {len(raw)} bytes no total, {MAX_BODY_CAPTURE} capturados»"
    return text, truncated


class ProxyRequestHandler(socketserver.BaseRequestHandler):
    """Atende uma conexão: requisição HTTP direta ou túnel CONNECT."""

    def handle(self) -> None:
        start_time = time.time()
        client_sock = self.request
        server: MobileNetworkProxy = self.server.interceptor_ref

        if not server.acquire_slot():
            logger.warning("Limite de conexões simultâneas atingido; conexão recusada.")
            self._safe_close(client_sock)
            return

        try:
            client_sock.settimeout(8.0)
            raw_request = self._read_headers(client_sock)
            if not raw_request:
                return

            header_lines = raw_request.decode("utf-8", errors="replace").split("\r\n")
            request_line = header_lines[0].strip() if header_lines else ""
            parts = request_line.split()
            if len(parts) < 2:
                return

            method = parts[0].upper()
            target = parts[1]
            protocol = parts[2] if len(parts) > 2 else "HTTP/1.1"

            headers: dict[str, str] = {}
            for line in header_lines[1:]:
                if ": " in line:
                    key, value = line.split(": ", 1)
                    headers[key.strip()] = value.strip()

            event_id = server.get_next_event_id()
            time_str = datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]

            if method == "CONNECT":
                self._handle_connect(client_sock, target, headers, protocol, event_id, start_time, time_str, server)
            else:
                self._handle_http(
                    client_sock, method, target, headers, protocol, raw_request,
                    event_id, start_time, time_str, server,
                )
        except (OSError, ValueError) as exc:
            logger.debug("Conexão encerrada com erro tratado: %s", exc)
        finally:
            server.release_slot()

    # ------------------------------------------------------------------ util

    @staticmethod
    def _safe_close(sock: socket.socket) -> None:
        try:
            sock.close()
        except OSError:
            pass

    @staticmethod
    def _read_headers(sock: socket.socket) -> bytes:
        """Lê até o fim do cabeçalho, com teto de tamanho."""
        data = bytearray()
        try:
            sock.settimeout(5.0)
        except OSError:
            pass
        while b"\r\n\r\n" not in data:
            if len(data) > MAX_HEADER_BYTES:
                logger.warning("Cabeçalho acima de %d bytes; conexão descartada.", MAX_HEADER_BYTES)
                return b""
            try:
                chunk = sock.recv(4096)
            except (TimeoutError, OSError):
                break
            if not chunk:
                break
            data.extend(chunk)
        return bytes(data)

    @staticmethod
    def _parse_content_length(headers: dict[str, str]) -> int:
        """Content-Length é entrada externa: valor inválido vira 0, valor absurdo é limitado."""
        raw = headers.get("Content-Length") or headers.get("content-length") or "0"
        try:
            length = int(raw)
        except (TypeError, ValueError):
            logger.debug("Content-Length inválido (%r); tratado como 0.", raw)
            return 0
        if length < 0:
            return 0
        if length > MAX_REQUEST_BODY:
            logger.warning("Content-Length %d acima do teto; leitura limitada.", length)
            return MAX_REQUEST_BODY
        return length

    # --------------------------------------------------------------- CONNECT

    def _handle_connect(self, client_sock, target, headers, protocol, event_id, start_time, time_str, server) -> None:
        host, _, port_str = target.partition(":")
        try:
            port = int(port_str) if port_str else 443
        except ValueError:
            port = 443
        if not host or not (1 <= port <= 65535):
            return

        remote_sock: socket.socket | None = None
        status_code, error_msg, bytes_transferred = 200, None, 0

        try:
            remote_sock = socket.create_connection((host, port), timeout=10)
            client_sock.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")

            sockets = [client_sock, remote_sock]
            while True:
                readable, _, exceptional = select.select(sockets, [], sockets, TUNNEL_IDLE_TIMEOUT)
                if exceptional or not readable:
                    break
                for sock in readable:
                    other = remote_sock if sock is client_sock else client_sock
                    data = sock.recv(65536)
                    if not data:
                        return
                    other.sendall(data)
                    bytes_transferred += len(data)
        except OSError as exc:
            error_msg = str(exc)
            status_code = 502
            try:
                client_sock.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            except OSError:
                pass
        finally:
            if remote_sock:
                self._safe_close(remote_sock)
            server.emit_event(
                NetworkEvent(
                    id=event_id,
                    timestamp=start_time,
                    time_str=time_str,
                    method="CONNECT",
                    url=f"https://{target}",
                    host=host,
                    path=f":{port}",
                    status_code=status_code,
                    status_text="Connection Established" if status_code == 200 else "Bad Gateway",
                    request_headers=redact_headers(headers),
                    request_body="",
                    response_headers={},
                    response_body=f"Túnel HTTPS ({bytes_transferred} bytes transferidos)",
                    duration_ms=(time.time() - start_time) * 1000,
                    protocol=protocol,
                    is_tunnel=True,
                    error=error_msg,
                    response_bytes=bytes_transferred,
                )
            )

    # ------------------------------------------------------------------ HTTP

    def _handle_http(self, client_sock, method, target, headers, protocol, raw_request,
                     event_id, start_time, time_str, server) -> None:
        parsed = urllib.parse.urlparse(target)
        host = parsed.hostname or headers.get("Host", "localhost")
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        path = parsed.path or "/"
        if parsed.query:
            path += f"?{parsed.query}"

        # Verificação de conectividade do Android: responder na hora evita que o
        # sistema marque a rede como sem internet e desligue o proxy sozinho.
        if "generate_204" in target or path.endswith("generate_204"):
            try:
                client_sock.sendall(b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            except OSError:
                pass
            server.emit_event(
                NetworkEvent(
                    id=event_id, timestamp=start_time, time_str=time_str, method=method,
                    url=target if target.startswith("http") else f"http://{host}:{port}{path}",
                    host=host, path=path, status_code=204, status_text="No Content (Connectivity Check)",
                    request_headers=redact_headers(headers), response_headers={"Content-Length": "0"},
                    duration_ms=(time.time() - start_time) * 1000, protocol=protocol,
                )
            )
            return

        body_bytes = self._read_request_body(client_sock, headers, raw_request)
        request_body_str, req_truncated = _decode_body(body_bytes, headers)
        request_body_str = redact_body(request_body_str)

        remote_conn = None
        status_code, status_text = 502, "Bad Gateway"
        resp_headers: dict[str, str] = {}
        response_body_str, error_msg = "", None
        resp_truncated = False
        resp_len = 0

        try:
            conn_cls = http.client.HTTPSConnection if parsed.scheme == "https" else http.client.HTTPConnection
            remote_conn = conn_cls(host, port, timeout=15)

            fwd_headers = {
                k: v for k, v in headers.items()
                if k.lower() not in ("proxy-connection", "connection", "keep-alive", "transfer-encoding")
            }
            fwd_headers["Connection"] = "close"

            remote_conn.request(method, path, body=body_bytes or None, headers=fwd_headers)
            resp = remote_conn.getresponse()
            status_code, status_text = resp.status, resp.reason
            resp_headers = dict(resp.getheaders())

            resp_data = resp.read()
            resp_len = len(resp_data)
            response_body_str, resp_truncated = _decode_body(resp_data, resp_headers)
            response_body_str = redact_body(response_body_str)

            client_response = f"HTTP/1.1 {status_code} {status_text}\r\n"
            for key, value in resp.getheaders():
                client_response += f"{key}: {value}\r\n"
            client_response += "\r\n"
            client_sock.sendall(client_response.encode("latin1", errors="replace") + resp_data)

        except (OSError, http.client.HTTPException) as exc:
            error_msg = str(exc)
            status_code, status_text = 502, "Bad Gateway"
            logger.debug("Falha ao encaminhar %s %s: %s", method, target, exc)
            try:
                # Corpo genérico: devolver str(exc) ao cliente vazaria detalhes
                # da rede interna do host para o app sob teste.
                body = b"O proxy nao conseguiu encaminhar a requisicao."
                client_sock.sendall(
                    b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: "
                    + str(len(body)).encode()
                    + b"\r\nConnection: close\r\n\r\n"
                    + body
                )
            except OSError:
                pass
        finally:
            if remote_conn:
                try:
                    remote_conn.close()
                except OSError:
                    pass
            server.emit_event(
                NetworkEvent(
                    id=event_id, timestamp=start_time, time_str=time_str, method=method,
                    url=target if target.startswith("http") else f"http://{host}:{port}{path}",
                    host=host, path=path, status_code=status_code, status_text=status_text,
                    request_headers=redact_headers(headers), request_body=request_body_str,
                    # Encontrado em QA: só a requisição era redigida. O
                    # `Set-Cookie` da resposta carrega o cookie de sessão que o
                    # servidor acabou de emitir, e ele aparecia inteiro na
                    # tabela e na exportação HAR.
                    response_headers=redact_headers(resp_headers),
                    response_body=response_body_str,
                    duration_ms=(time.time() - start_time) * 1000, protocol=protocol,
                    is_tunnel=False, error=error_msg,
                    request_bytes=len(body_bytes), response_bytes=resp_len,
                    body_truncated=req_truncated or resp_truncated,
                )
            )

    def _read_request_body(self, client_sock, headers: dict[str, str], raw_request: bytes) -> bytes:
        content_length = self._parse_content_length(headers)
        header_end = raw_request.find(b"\r\n\r\n")
        if header_end == -1:
            return b""
        body = bytearray(raw_request[header_end + 4:])
        remaining = content_length - len(body)
        while remaining > 0:
            try:
                chunk = client_sock.recv(min(remaining, 65536))
            except (TimeoutError, OSError):
                break
            if not chunk:
                break
            body.extend(chunk)
            remaining -= len(chunk)
        return bytes(body)


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address, RequestHandlerClass, interceptor_ref):
        self.interceptor_ref = interceptor_ref
        super().__init__(server_address, RequestHandlerClass)

    def handle_error(self, request, client_address):
        logger.debug("Erro não tratado ao atender %s", client_address, exc_info=True)


class MobileNetworkProxy:
    """Controla o ciclo de vida do proxy e distribui os eventos capturados.

    Duas formas de consumo, propositais: `event_queue` para quem roda em outra
    thread (a UI faz polling e desenha na sua própria thread) e `add_event_callback`
    para consumo direto. O callback roda na thread da conexão, então quem se
    registra não pode tocar em widget nem bloquear.
    """

    def __init__(self, host: str | None = None, port: int | None = None):
        self.host = host or settings.proxy_host
        self.port = port or settings.proxy_port
        self.event_queue: queue.Queue = queue.Queue(maxsize=MAX_HISTORY * 2)
        self._events: deque[NetworkEvent] = deque(maxlen=MAX_HISTORY)
        self._server: ThreadedTCPServer | None = None
        self._thread: threading.Thread | None = None
        self._is_running = False
        self._event_counter = 0
        self._lock = threading.Lock()
        self._callbacks: list[Callable[[NetworkEvent], None]] = []
        self._slots = threading.Semaphore(MAX_CONCURRENT_CONNECTIONS)

    # ------------------------------------------------------------ concorrência

    def acquire_slot(self) -> bool:
        return self._slots.acquire(blocking=False)

    def release_slot(self) -> None:
        try:
            self._slots.release()
        except ValueError:
            pass

    # ---------------------------------------------------------------- eventos

    @property
    def events_history(self) -> list[NetworkEvent]:
        with self._lock:
            return list(self._events)

    def get_next_event_id(self) -> int:
        with self._lock:
            self._event_counter += 1
            return self._event_counter

    def add_event_callback(self, cb: Callable[[NetworkEvent], None]) -> None:
        self._callbacks.append(cb)

    def emit_event(self, event: NetworkEvent) -> None:
        with self._lock:
            self._events.append(event)  # deque com maxlen descarta o mais antigo
        try:
            self.event_queue.put_nowait(event)
        except queue.Full:
            logger.debug("Fila de eventos cheia; consumidor não está drenando.")
        for cb in self._callbacks:
            try:
                cb(event)
            except Exception:
                logger.exception("Callback de evento falhou.")

    # ------------------------------------------------------------ ciclo de vida

    def start(self) -> bool:
        if self._is_running:
            return True
        if self.host not in ("127.0.0.1", "localhost", "::1"):
            logger.warning(
                "Proxy configurado para escutar em %s. Fora do loopback ele fica "
                "acessível na rede local como proxy aberto.", self.host,
            )
        try:
            self._server = ThreadedTCPServer((self.host, self.port), ProxyRequestHandler, self)
        except OSError as exc:
            logger.error("Não foi possível abrir o proxy em %s:%s -> %s", self.host, self.port, exc)
            self._is_running = False
            return False
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True, name="mobaile-proxy")
        self._thread.start()
        self._is_running = True
        logger.info("Proxy ouvindo em %s:%s", self.host, self.port)
        return True

    def stop(self) -> None:
        if not self._is_running:
            return
        self._is_running = False
        if self._server:
            try:
                self._server.shutdown()
                self._server.server_close()
            except OSError as exc:
                logger.debug("Erro ao encerrar o proxy: %s", exc)
            self._server = None
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        self._thread = None

    def is_running(self) -> bool:
        return self._is_running

    def clear_history(self) -> None:
        with self._lock:
            self._events.clear()
        while True:
            try:
                self.event_queue.get_nowait()
            except queue.Empty:
                break


# Instância compartilhada usada pela UI legada.
network_interceptor = MobileNetworkProxy()
