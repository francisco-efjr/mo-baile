"""
Trafego HTTP(S) de um app Android em debug, sem proxy: o log do OkHttp.
------------------------------------------------------------------------
O par do "iPhone em Debug" (`ios_cfnetwork`). Quando o build de debug do app
usa o `HttpLoggingInterceptor` do OkHttp (o Retrofit usa OkHttp por baixo),
cada requisicao e resposta ja sai no logcat, fora do TLS. Lendo o logcat pelo
`adb`, o Mo baile mostra URL, metodo, status, headers, corpo e tempo sem proxy,
sem certificado e sem mexer no Wi-Fi do aparelho. Funciona com o debugger do
Android Studio conectado: o logcat e compartilhado, ao contrario do JDWP.

Limites, de proposito escritos aqui:

- so apps com o interceptor ligado. No nivel BASIC sai so a linha de cada
  requisicao; HEADERS traz os headers; BODY traz tambem os corpos;
- so trafego do OkHttp. `HttpURLConnection`, Volley, Ktor (formato proprio) e
  Flutter nao aparecem;
- o App Inspection do Android Studio (Network Inspector) ve tudo do app
  debuggable porque injeta um agente JVMTI; isso nao e reproduzido aqui.

Formato (OkHttp 3 e 4), linha a linha no logcat:

    --> POST https://api.exemplo.com/v1/simulacao
    Content-Type: application/json
    (linha vazia)
    {"valor": 5000}
    --> END POST (15-byte body)
    <-- 201 https://api.exemplo.com/v1/simulacao (182ms)
    content-type: application/json
    (linha vazia)
    {"parcelas": 12}
    <-- END HTTP (16-byte body)

As linhas de uma chamada saem na mesma thread, entao o parser separa por
processo e thread (`logcat -v threadtime`) e ignora o resto do log.
"""

from __future__ import annotations

import logging
import re
import subprocess
import threading
import time
import urllib.parse
from collections.abc import Callable
from dataclasses import dataclass, field

from mobaile.domain.errors import AdapterError, InvalidInputError
from mobaile.domain.models import NetworkEvent
from mobaile.security import redact_body, redact_headers, redact_url, validate_device_id

logger = logging.getLogger(__name__)

# Mesmo teto do proxy: o corpo inteiro de um download nao cabe na interface.
MAX_BODY_CHARS = 256 * 1024
# Requisicao sem resposta no log por mais que isso vira evento com erro.
PENDING_TIMEOUT_S = 60.0
_MAX_THREADS = 500
_START_CHECK_S = 0.4

_METHODS = "GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT"
_LOGCAT = re.compile(
    r"^(?P<date>\d\d-\d\d)\s+(?P<time>\d\d:\d\d:\d\d\.\d{3})\s+(?P<pid>\d+)\s+(?P<tid>\d+)\s+"
    r"[VDIWEFA]\s+(?P<tag>.*?)\s*:\s?(?P<msg>.*)$"
)
_REQ_START = re.compile(
    rf"^--> (?P<method>{_METHODS}) (?P<url>https?://\S+)"
    r"(?: (?P<proto>(?:http|HTTP)/[\d.]+|h2|h2_prior_knowledge|quic))?"
    r"(?: \((?P<basic>[^)]*body[^)]*)\))?\s*$"
)
_REQ_END = re.compile(r"^--> END (?P<method>\S+)(?: \((?P<info>.*)\))?\s*$")
_RESP_START = re.compile(
    r"^<-- (?P<status>\d{3})(?: (?P<message>[^(]*?))? (?P<url>https?://\S+) "
    r"\((?P<ms>\d+)ms(?:, (?P<basic>[^)]*))?\)\s*$"
)
_RESP_END = re.compile(r"^<-- END HTTP(?: \((?P<info>.*)\))?\s*$")
_FAILED = re.compile(r"^<-- HTTP FAILED: (?P<error>.*)$")
_HEADER = re.compile(r"^(?P<name>[A-Za-z0-9][A-Za-z0-9\-_.]*):\s?(?P<value>.*)$")


@dataclass
class _Call:
    """Uma chamada em andamento numa thread do app."""

    tag: str
    method: str
    url: str
    protocol: str
    started: float
    time_str: str
    phase: str = "req_headers"
    request_headers: dict[str, str] = field(default_factory=dict)
    request_body: list[str] = field(default_factory=list)
    status: int = 0
    status_text: str = ""
    duration_ms: float = 0.0
    response_headers: dict[str, str] = field(default_factory=dict)
    response_body: list[str] = field(default_factory=list)


def _status_text(code: int) -> str:
    try:
        from http import HTTPStatus

        return HTTPStatus(code).phrase
    except ValueError:
        return ""


# O `android.util.Log` corta mensagem acima disto em varias linhas. Uma linha
# de corpo exatamente desse tamanho continua na proxima, sem quebra de linha.
LOGCAT_CHUNK = 4000


def _append_body(lines: list[str], msg: str) -> None:
    if lines and len(lines[-1]) >= LOGCAT_CHUNK and len(lines[-1]) % LOGCAT_CHUNK == 0:
        lines[-1] += msg
    else:
        lines.append(msg)


def _body(lines: list[str]) -> str:
    text = "\n".join(lines).strip("\n")
    if len(text) > MAX_BODY_CHARS:
        text = text[:MAX_BODY_CHARS] + f"\n\n«truncado: {len(text)} caracteres no total»"
    return redact_body(text)


class OkHttpLogParser:
    """Transforma linhas do `logcat -v threadtime` em `NetworkEvent`.

    Puro: nao abre processo nem le relogio sozinho (o `now` vem de fora), para
    o teste alimentar linhas e conferir os eventos.

    `_active` guarda a chamada aberta de cada thread (processo, thread). Uma
    requisicao que nao fechou antes da proxima na mesma thread (nivel BASIC, sem
    END) vai para `_parked` e ainda casa com a resposta pela URL.
    """

    def __init__(self, next_id: Callable[[], int]) -> None:
        self._next_id = next_id
        self._active: dict[tuple[str, str], _Call] = {}
        self._parked: list[tuple[str, _Call]] = []

    def has_open_calls(self) -> bool:
        return bool(self._active)

    def feed(self, line: str, now: float | None = None) -> list[NetworkEvent]:
        now = time.time() if now is None else now
        match = _LOGCAT.match(line.rstrip("\n"))
        if not match:
            return []
        key = (match["pid"], match["tid"])
        tag, msg = match["tag"], match["msg"]
        events: list[NetworkEvent] = []

        start = _REQ_START.match(msg)
        if start:
            self._park(key)
            call = _Call(
                tag=tag, method=start["method"], url=start["url"], protocol=start["proto"] or "",
                started=now, time_str=match["time"],
            )
            # No nivel BASIC a linha ja traz o tamanho do corpo e nao ha END.
            call.phase = "await_response" if start["basic"] else "req_headers"
            self._active[key] = call
            return self._expire(now, events)

        response = _RESP_START.match(msg)
        if response:
            call = self._call_for_response(key, response["url"]) or _Call(
                tag=tag, method="?", url=response["url"], protocol="", started=now, time_str=match["time"],
            )
            call.tag = tag
            call.status = int(response["status"])
            call.status_text = (response["message"] or "").strip() or _status_text(call.status)
            call.duration_ms = float(response["ms"])
            if response["basic"]:
                events.append(self._finish(call))
            else:
                self._park(key)
                call.phase = "resp_headers"
                self._active[key] = call
            return self._expire(now, events)

        call = self._active.get(key)
        failed = _FAILED.match(msg)
        if failed and call is not None:
            del self._active[key]
            events.append(self._finish(call, error=failed["error"].strip()))
            return self._expire(now, events)

        # Daqui para baixo so continua uma chamada aberta nesta thread, com a
        # mesma tag: outro log do app na mesma thread nao vira header nem corpo.
        if call is None or tag != call.tag:
            return self._expire(now, events)
        if _REQ_END.match(msg):
            call.phase = "await_response"
        elif _RESP_END.match(msg):
            del self._active[key]
            events.append(self._finish(call))
        elif call.phase in ("req_headers", "resp_headers"):
            header = _HEADER.match(msg)
            if header:
                alvo = call.request_headers if call.phase == "req_headers" else call.response_headers
                alvo[header["name"]] = header["value"]
            else:
                call.phase = "req_body" if call.phase == "req_headers" else "resp_body"
                if msg.strip():
                    _append_body(call.request_body if call.phase == "req_body" else call.response_body, msg)
        elif call.phase == "req_body":
            _append_body(call.request_body, msg)
        elif call.phase == "resp_body":
            _append_body(call.response_body, msg)
        return self._expire(now, events)

    def flush(self) -> list[NetworkEvent]:
        """Fecha o que ainda estava aberto (fim da leitura)."""
        abertas = list(self._active.values()) + [call for _, call in self._parked]
        self._active.clear()
        self._parked.clear()
        return [
            self._finish(call, error=None if call.status else "Leitura do log encerrada antes da resposta.")
            for call in abertas
        ]

    def _park(self, key: tuple[str, str]) -> None:
        anterior = self._active.pop(key, None)
        if anterior is not None and anterior.status == 0:
            anterior.phase = "await_response"
            self._parked.append((key[0], anterior))

    def _call_for_response(self, key: tuple[str, str], url: str) -> _Call | None:
        call = self._active.get(key)
        if call is not None and call.url == url and call.status == 0:
            del self._active[key]
            return call
        # Requisicao estacionada, ou resposta numa outra thread do mesmo
        # processo: casa pela URL, a mais antiga primeiro.
        for indice, (pid, candidata) in enumerate(self._parked):
            if pid == key[0] and candidata.url == url:
                del self._parked[indice]
                return candidata
        for chave, candidata in list(self._active.items()):
            if chave[0] == key[0] and candidata.url == url and candidata.status == 0:
                del self._active[chave]
                return candidata
        return None

    def _expire(self, now: float, events: list[NetworkEvent]) -> list[NetworkEvent]:
        for chave, call in list(self._active.items()):
            if call.status == 0 and now - call.started > PENDING_TIMEOUT_S:
                del self._active[chave]
                events.append(self._finish(call, error="Sem resposta no log em 60 s."))
        vencidas = [item for item in self._parked if now - item[1].started > PENDING_TIMEOUT_S]
        for item in vencidas:
            self._parked.remove(item)
            events.append(self._finish(item[1], error="Sem resposta no log em 60 s."))
        # Log que nunca fecha nada nao pode crescer sem limite.
        if len(self._active) > _MAX_THREADS:
            for chave in list(self._active)[: len(self._active) - _MAX_THREADS]:
                del self._active[chave]
        del self._parked[:-_MAX_THREADS]
        return events

    def _finish(self, call: _Call, error: str | None = None) -> NetworkEvent:
        url = redact_url(call.url)
        parsed = urllib.parse.urlparse(url)
        path = parsed.path or "/"
        if parsed.query:
            path += f"?{parsed.query}"
        request_body = _body(call.request_body)
        response_body = _body(call.response_body)
        protocolo = call.protocol.upper() if call.protocol.lower().startswith("http") else call.protocol
        return NetworkEvent(
            id=self._next_id(),
            timestamp=call.started,
            time_str=call.time_str,
            method=call.method,
            url=url,
            host=parsed.hostname or "",
            path=path,
            status_code=call.status,
            status_text=call.status_text,
            request_headers=redact_headers(call.request_headers),
            request_body=request_body,
            response_headers=redact_headers(call.response_headers),
            response_body=response_body,
            duration_ms=call.duration_ms,
            protocol=protocolo or "HTTP/1.1",
            error=error,
            request_bytes=len(request_body.encode("utf-8")),
            response_bytes=len(response_body.encode("utf-8")),
        )


class AndroidDebugNetworkCapture:
    """Le o logcat do aparelho e entrega `NetworkEvent` para quem registrar."""

    def __init__(self, adb_path: Callable[[], str], emit: Callable[[NetworkEvent], None],
                 next_id: Callable[[], int]) -> None:
        self._adb_path = adb_path
        self._emit = emit
        self._next_id = next_id
        self._proc: subprocess.Popen | None = None
        self._thread: threading.Thread | None = None
        self._running = False
        self.device_id: str | None = None

    def is_running(self) -> bool:
        return self._running

    def start(self, serial: str) -> bool:
        if self._running:
            return True
        if not serial:
            raise InvalidInputError("Nenhum aparelho Android selecionado.")
        self.device_id = validate_device_id(serial)
        # `-T 1`: so o que chegar daqui em diante (o buffer antigo inteiro
        # viraria uma rajada de requisicoes velhas na tabela).
        cmd = [self._adb_path(), "-s", self.device_id, "logcat", "-v", "threadtime", "-T", "1"]
        try:
            self._proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,  # o stdin do motor e o canal JSON-RPC
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
            )
        except OSError as exc:
            raise AdapterError(f"Nao foi possivel ler o logcat: {exc}") from exc
        time.sleep(_START_CHECK_S)
        if self._proc.poll() is not None:
            self._proc = None
            raise AdapterError("O logcat do aparelho encerrou ao iniciar. Confira se ele continua conectado.")
        self._running = True
        self._thread = threading.Thread(target=self._reader, daemon=True, name="mobaile-android-netlog")
        self._thread.start()
        return True

    def stop(self) -> None:
        self._running = False
        proc, self._proc = self._proc, None
        if proc:
            try:
                proc.terminate()
                proc.wait(timeout=1.0)
            except (OSError, subprocess.TimeoutExpired):
                try:
                    proc.kill()
                    proc.wait(timeout=1.0)
                except (OSError, subprocess.TimeoutExpired) as exc:
                    logger.warning("Leitura do logcat nao encerrou: %s", exc)
            finally:
                if proc.stdout:
                    try:
                        proc.stdout.close()
                    except OSError:
                        pass
        if self._thread and self._thread.is_alive() and self._thread is not threading.current_thread():
            self._thread.join(timeout=1.0)
        self._thread = None

    def _reader(self) -> None:
        proc = self._proc
        if not proc or not proc.stdout:
            return
        parser = OkHttpLogParser(self._next_id)
        for line in iter(proc.stdout.readline, ""):
            if not self._running:
                break
            # Barato: a maioria das linhas do logcat nao e do OkHttp.
            if "-->" not in line and "<--" not in line and not parser.has_open_calls():
                continue
            try:
                events = parser.feed(line)
            except (ValueError, KeyError) as exc:
                logger.debug("Linha do OkHttp ignorada: %s", exc)
                continue
            for event in events:
                self._emit(event)
        for event in parser.flush():
            self._emit(event)
        self._running = False
