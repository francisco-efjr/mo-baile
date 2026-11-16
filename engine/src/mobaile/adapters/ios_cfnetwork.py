"""
Trafego HTTP(S) de um app em debug no iPhone fisico, sem proxy.
---------------------------------------------------------------
Quando o app roda com a variavel de ambiente `CFNETWORK_DIAGNOSTICS=3` (scheme
do Xcode, em Run > Arguments > Environment Variables), o proprio CFNetwork
escreve no log do sistema cada requisicao e resposta do `URLSession`, ja fora
do TLS. Esse log chega pelo cabo pelo mesmo canal do tagueamento
(`ios_device_log`, servico `os_trace_relay`), entao nao precisa de proxy, de
certificado nem de configurar o Wi-Fi do aparelho.

Limites, de proposito escritos aqui:

- so apps com essa variavel ligada (na pratica, build de debug do seu app);
- so o que passa pelo `URLSession`/CFNetwork. Flutter (dart:io) e sockets
  proprios nao aparecem;
- o formato do texto nao e documentado pela Apple e muda entre versoes do iOS.
  O parser e tolerante e, para diagnostico, os blocos brutos (com headers
  sensiveis mascarados) ficam em `raw_log_path()`, na pasta dos logs do motor;
- corpo de requisicao e resposta normalmente nao vem no log.

Cada bloco do log tem a forma:

    CFNetwork Diagnostics [3:45] 10:20:30.123 {
      Protocol Enqueue: request GET https://api.exemplo.com/v1 HTTP/1.1
        Request:  <CFURLRequest 0x...> {url = https://api.exemplo.com/v1, cs = 0x0}
        Message: GET https://api.exemplo.com/v1 HTTP/1.1
        Accept: */*
    } [3:45]

e a resposta traz `Status Code: 200, Headers {` seguido de pares
`"Nome" = ( "valor" );`. Requisicao e resposta sao casadas pela URL, na ordem.
"""

from __future__ import annotations

import datetime
import json
import logging
import os
import re
import subprocess
import threading
import time
import urllib.parse
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from mobaile.adapters import ios_device_log
from mobaile.domain.errors import AdapterError, InvalidInputError
from mobaile.domain.models import NetworkEvent
from mobaile.security import is_sensitive_header, logs_dir, redact_headers, redact_url, validate_device_id

logger = logging.getLogger(__name__)

# Ate a 3.11 o arquivo ficava em `~/Library/Logs/MoBaile/`; agora fica com os
# outros logs do motor (`logs_dir()`). O arquivo antigo nao e apagado.
RAW_LOG_NAME = "cfnetwork-diagnostics.log"
RAW_LOG_MAX_BYTES = 5 * 1024 * 1024
# Requisicao sem resposta no log por mais que isso vira evento com erro.
PENDING_TIMEOUT_S = 60.0
_READY_TIMEOUT_S = 20.0
_MAX_PENDING = 500

BODY_UNAVAILABLE = "«corpo não disponível no diagnóstico do CFNetwork»"

_BLOCK_OPEN = re.compile(r"CFNetwork Diagnostics \[(\d+:\d+)\][^{]*\{")
_BLOCK_CLOSE = re.compile(r"^\s*\}\s*\[(\d+:\d+)\]\s*$")
_METHODS = "GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT"
_REQUEST_LINE = re.compile(rf"\b({_METHODS})\s+(https?://\S+)(?:\s+(HTTP/[\d.]+))?")
_URL_FIELD = re.compile(r"\b(?:url|URL)\s*[=:]\s*(https?://[^,}\s]+)")
_STATUS = re.compile(r"Status Code:\s*(\d{3})")
_HEADER_LINE = re.compile(r"^\s*([A-Za-z0-9][A-Za-z0-9\-]*):\s?(.*)$")
_DICT_PAIR = re.compile(r'^\s*"?([^"=]+?)"?\s*=\s*\(?\s*"?(.*?)"?\s*\)?\s*;?\s*$')
# Chave da forma de dicionario no bloco bruto: `"Set-Cookie" = (` ou `Cookie = "x";`.
_DICT_KEY = re.compile(r'^\s*"?([A-Za-z0-9][A-Za-z0-9\-]*)"?\s*=\s*(.*)$')
# Qualquer URL dentro de uma linha do bloco bruto, para passar por `redact_url`.
_ANY_URL = re.compile(r"https?://[^\s,}>\"]+")
_ERROR = re.compile(r"Error Domain=(\S+)\s+Code=(-?\d+)(?:.*?\"(.*?)\")?")
# Rotulos do proprio diagnostico que parecem header mas nao sao.
_NOT_HEADERS = {
    "message",
    "request",
    "response",
    "protocol enqueue",
    "response received",
    "did receive response",
    "did finish",
    "did fail",
    "error",
    "loader",
    "task",
    "connection",
    "protocol",
    "data",
    "url",
    "timing",
    "cs",
}


@dataclass
class _Pending:
    method: str
    url: str
    protocol: str
    headers: dict[str, str]
    started: float
    time_str: str


@dataclass
class _Response:
    url: str | None
    status: int
    headers: dict[str, str] = field(default_factory=dict)
    error: str | None = None


def _status_text(code: int) -> str:
    try:
        from http import HTTPStatus

        return HTTPStatus(code).phrase
    except ValueError:
        return ""


class CFNetworkDiagParser:
    """Monta blocos do log e devolve `NetworkEvent` quando a resposta chega.

    Puro (sem processo nem relogio proprio) para ser testado com texto fixo.
    `feed` recebe uma mensagem de log, que pode conter o bloco inteiro ou um
    pedaco dele; o estado e mantido por pid.
    """

    def __init__(self, next_id: Callable[[], int], on_raw_block: Callable[[str], None] | None = None) -> None:
        self._next_id = next_id
        self._on_raw_block = on_raw_block
        self._buffers: dict[int, list[str]] = {}
        self._pending: list[_Pending] = []

    # ------------------------------------------------------------ entrada

    def feed(self, pid: int, message: str, now: float | None = None) -> list[NetworkEvent]:
        now = time.time() if now is None else now
        events: list[NetworkEvent] = []
        for line in message.splitlines() or [message]:
            if _BLOCK_OPEN.search(line):
                # Bloco anterior sem fechamento: processa o que tinha.
                if pid in self._buffers:
                    events += self._finish(self._buffers.pop(pid), now)
                self._buffers[pid] = [line]
                continue
            buf = self._buffers.get(pid)
            if buf is None:
                continue
            buf.append(line)
            if _BLOCK_CLOSE.match(line):
                events += self._finish(self._buffers.pop(pid), now)
        events += self.expire(now)
        return events

    def expire(self, now: float) -> list[NetworkEvent]:
        """Requisicoes que esperaram demais viram evento com erro."""
        expired = [p for p in self._pending if now - p.started > PENDING_TIMEOUT_S]
        if not expired:
            return []
        self._pending = [p for p in self._pending if p not in expired]
        return [self._event(p, None, now, error="Sem resposta no log do CFNetwork.") for p in expired]

    # ------------------------------------------------------------ blocos

    def _finish(self, lines: list[str], now: float) -> list[NetworkEvent]:
        if self._on_raw_block:
            try:
                self._on_raw_block(_mask_block(lines))
            except Exception:
                logger.debug("Falha ao guardar bloco bruto do CFNetwork.", exc_info=True)
        response = self._parse_response(lines)
        if response is not None:
            return self._match(response, now)
        request = self._parse_request(lines, now)
        if request is not None:
            self._pending.append(request)
            if len(self._pending) > _MAX_PENDING:
                self._pending.pop(0)
        return []

    def _parse_request(self, lines: list[str], now: float) -> _Pending | None:
        for idx, line in enumerate(lines):
            m = _REQUEST_LINE.search(line)
            if not m:
                continue
            method, url, protocol = m.group(1), m.group(2).rstrip(","), m.group(3) or "HTTP/1.1"
            # Headers: linhas `Nome: valor` depois da linha `Message:`.
            start = next((i for i, item in enumerate(lines) if "Message:" in item), idx)
            headers = _headers_from_lines(lines[start + 1 :])
            stamp = datetime.datetime.fromtimestamp(now).strftime("%H:%M:%S.%f")[:-3]
            return _Pending(method, url, protocol, headers, now, stamp)
        return None

    def _parse_response(self, lines: list[str]) -> _Response | None:
        text = "\n".join(lines)
        status = _STATUS.search(text)
        error = _ERROR.search(text)
        if not status and not error:
            return None
        url = None
        for line in lines:
            if "Response" in line or "Did Fail" in line or "Error" in line:
                m = _URL_FIELD.search(line) or _REQUEST_LINE.search(line)
                if m:
                    url = m.group(1) if m.re is _URL_FIELD else m.group(2)
                    break
        if url is None:
            m = _URL_FIELD.search(text)
            url = m.group(1) if m else None
        if status:
            headers = _headers_from_dict(lines[_index_of(lines, "Status Code") + 1 :])
            return _Response(url=url, status=int(status.group(1)), headers=headers)
        assert error is not None
        desc = error.group(3) or ""
        return _Response(url=url, status=0, error=f"{error.group(1)} {error.group(2)} {desc}".strip())

    def _match(self, response: _Response, now: float) -> list[NetworkEvent]:
        pending = None
        if response.url:
            key = response.url.rstrip("/")
            pending = next((p for p in self._pending if p.url.rstrip("/") == key), None)
        if pending is None and response.url is None and self._pending:
            pending = self._pending[0]
        if pending is not None:
            self._pending.remove(pending)
            return [self._event(pending, response, now)]
        if not response.url:
            return []
        # Resposta sem requisicao vista (comecou antes da escuta, por exemplo).
        stamp = datetime.datetime.fromtimestamp(now).strftime("%H:%M:%S.%f")[:-3]
        orphan = _Pending("?", response.url, "HTTP/1.1", {}, now, stamp)
        return [self._event(orphan, response, now)]

    def _event(
        self, req: _Pending, resp: _Response | None, now: float, error: str | None = None
    ) -> NetworkEvent:
        url = redact_url(req.url)
        parsed = urllib.parse.urlparse(url)
        path = parsed.path or "/"
        if parsed.query:
            path += f"?{parsed.query}"
        status = resp.status if resp else 0
        return NetworkEvent(
            id=self._next_id(),
            timestamp=req.started,
            time_str=req.time_str,
            method=req.method,
            url=url,
            host=parsed.hostname or "",
            path=path,
            status_code=status,
            status_text=_status_text(status) if status else "",
            request_headers=redact_headers(req.headers),
            request_body=BODY_UNAVAILABLE if req.method not in ("GET", "HEAD", "?") else "",
            response_headers=redact_headers(resp.headers) if resp else {},
            response_body=BODY_UNAVAILABLE if status else "",
            duration_ms=max(0.0, (now - req.started) * 1000.0),
            protocol=req.protocol,
            error=error or (resp.error if resp else None),
        )


def _index_of(lines: list[str], needle: str) -> int:
    return next((i for i, line in enumerate(lines) if needle in line), len(lines))


def _headers_from_lines(lines: list[str]) -> dict[str, str]:
    headers: dict[str, str] = {}
    for line in lines:
        if _BLOCK_CLOSE.match(line):
            break
        m = _HEADER_LINE.match(line)
        if not m or m.group(1).lower() in _NOT_HEADERS:
            continue
        headers[m.group(1)] = m.group(2).strip()
    return headers


def _headers_from_dict(lines: list[str]) -> dict[str, str]:
    """`"Content-Type" = ( "application/json" );` e variantes, ate fechar o `}`."""
    headers: dict[str, str] = {}
    pending_key: str | None = None
    for raw in lines:
        line = raw.strip()
        if not line or _BLOCK_CLOSE.match(raw) or line.startswith("}"):
            if line.startswith("}"):
                break
            continue
        if pending_key is not None:
            # Valor de lista em linha propria: `"application/json"` ou `);`.
            if line.startswith(")"):
                pending_key = None
                continue
            headers[pending_key] = line.strip('",; ')
            pending_key = None
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip().strip('"')
        value = value.strip()
        if not key or " " in key:
            continue
        if value in ("(", "(\n"):
            pending_key = key
            continue
        m = _DICT_PAIR.match(line)
        headers[key] = (m.group(2) if m else value).strip('",; ()')
    return headers


def raw_log_path() -> Path:
    """Arquivo do log bruto. Levanta `OSError` se a pasta dos logs for recusada."""
    return logs_dir() / RAW_LOG_NAME


def _mask_value(name: str, value: str) -> str:
    # `force`: o arquivo em disco ignora `MOBAILE_REDACT=0` (D-E); o opt-out
    # vale para a tela.
    return redact_headers({name: value.strip('"(); ,')}, force=True)[name]


def _mask_list_start(name: str, resto: str) -> tuple[str, bool]:
    """Inicio `( ...` de uma lista sensivel: texto mascarado e se ela continua.

    A lista so fecha na mesma linha se ela termina em `)` (ou `);`): um `)`
    no meio e do valor (`( "a=(1)",`) e nao fecha nada.
    """
    if not resto.rstrip(" ;").endswith(")"):
        primeiro = resto[1:].strip()
        return "(" + (" " + _mask_value(name, primeiro) if primeiro else ""), True
    return _mask_value(name, resto) + (";" if resto.endswith(";") else ""), False


def _mask_block(lines: list[str]) -> str:
    """Bloco bruto com headers sensiveis e credenciais de URL mascarados.

    O bloco vai para um arquivo em disco: token na query string ou usuario e
    senha na URL nao podem ir junto (SEC-3). Os headers da resposta vem na
    forma de dicionario, `"Set-Cookie" = (` com o valor nas linhas seguintes
    ate `);`, entao a chave sensivel fica pendente ate a lista fechar, como em
    `_headers_from_dict`. Com `"Set-Cookie" =` sozinho na linha, o `(` vem na
    seguinte: a chave fica pendente ate ele.
    """
    out = []
    pendente: str | None = None
    abrindo = False  # chave sensivel vista, `(` ainda por vir
    for line in lines:
        corpo = line.strip()
        margem = line[: len(line) - len(line.lstrip())]
        if pendente is not None and corpo.startswith((")", "}")):
            pendente, abrindo = None, False
        elif abrindo and not corpo:
            out.append(line)
            continue
        elif abrindo:
            if corpo.startswith("("):
                texto, continua = _mask_list_start(pendente, corpo)
            else:
                # Valor solto, sem lista: mascara e encerra.
                texto, continua = _mask_value(pendente, corpo) + (";" if corpo.endswith(";") else ""), False
            out.append(margem + texto)
            abrindo = False
            if not continua:
                pendente = None
            continue
        elif pendente is not None:
            # Valor de lista em linha propria: `"sid=..."`, `"a=1",` ou `"b=2");`.
            fecha = corpo.endswith((")", ");"))
            out.append(margem + _mask_value(pendente, corpo) + (");" if fecha else ""))
            if fecha:
                pendente = None
            continue
        m = _HEADER_LINE.match(line)
        d = _DICT_KEY.match(line)
        if m and m.group(1).lower() not in _NOT_HEADERS:
            masked = redact_headers({m.group(1): m.group(2)}, force=True)[m.group(1)]
            line = line[: m.start(2)] + masked
        elif d and is_sensitive_header(d.group(1)):
            resto = d.group(2).strip()
            if not resto:
                # `"Set-Cookie" =` sozinho: o `(` vem na linha seguinte.
                pendente, abrindo = d.group(1), True
            elif resto.startswith("("):
                texto, continua = _mask_list_start(d.group(1), resto)
                line = line[: d.start(2)] + texto
                if continua:
                    pendente = d.group(1)
            else:
                line = line[: d.start(2)] + _mask_value(d.group(1), resto) + (";" if resto.endswith(";") else "")
        line = _ANY_URL.sub(lambda u: redact_url(u.group(0), force=True), line)
        out.append(line)
    return "\n".join(out)


class IOSDebugNetworkCapture:
    """Escuta o log do iPhone e entrega `NetworkEvent` para quem registrar."""

    def __init__(self, emit: Callable[[NetworkEvent], None], next_id: Callable[[], int]) -> None:
        self._emit = emit
        self._next_id = next_id
        self._proc: subprocess.Popen | None = None
        self._thread: threading.Thread | None = None
        self._running = False
        self._ready = threading.Event()
        self._error: str | None = None
        self._raw_lock = threading.Lock()
        self.device_id: str | None = None

    def is_running(self) -> bool:
        return self._running

    def start(self, udid: str) -> bool:
        if self._running:
            return True
        if not udid:
            raise InvalidInputError("UDID do iPhone nao informado.")
        if not ios_device_log.is_available():
            raise AdapterError("pymobiledevice3 nao esta instalado.", detail=ios_device_log.INSTALL_HINT)
        self.device_id = validate_device_id(udid)
        self._ready.clear()
        self._error = None
        self._proc = subprocess.Popen(
            ios_device_log.cfnetwork_command(self.device_id),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,  # o stdin do motor e o canal JSON-RPC
            text=True,
            bufsize=1,
            **ios_device_log.popen_kwargs(),
        )
        self._running = True
        self._thread = threading.Thread(target=self._reader, daemon=True, name="mobaile-ios-netlog")
        self._thread.start()
        if not self._ready.wait(_READY_TIMEOUT_S) or self._error:
            error = self._error or "O iPhone nao comecou a mandar o log a tempo."
            self.stop()
            raise AdapterError(error)
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
                    logger.warning("Leitura do log do iPhone nao encerrou: %s", exc)
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
        parser = CFNetworkDiagParser(self._next_id, on_raw_block=self._save_raw)
        for line in iter(proc.stdout.readline, ""):
            if not self._running:
                break
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if "status" in payload:
                self._ready.set()
                continue
            if "error" in payload:
                self._error = payload["error"]
                self._ready.set()
                continue
            try:
                events = parser.feed(int(payload.get("pid") or 0), str(payload.get("message", "")))
            except Exception as exc:
                # So o tipo: a mensagem e o traceback podem citar trecho do
                # bloco (cabecalhos), e este log vai para o engine.log.
                logger.error("Falha ao interpretar bloco do CFNetwork (%s).", type(exc).__name__)
                continue
            for event in events:
                self._emit(event)
        if not self._ready.is_set():
            self._error = self._error or "A leitura do log do iPhone encerrou inesperadamente."
            self._ready.set()
        self._running = False

    def _save_raw(self, block: str) -> None:
        """Acrescenta o bloco ao log bruto, legivel so pelo dono (0600)."""
        with self._raw_lock:
            # `logs_dir()` cria a pasta 0700, corrige a que ja existia e recusa
            # symlink no lugar dela.
            caminho = raw_log_path()
            rotacionado = caminho.with_suffix(".log.1")
            if caminho.is_file() and not caminho.is_symlink() and caminho.stat().st_size > RAW_LOG_MAX_BYTES:
                caminho.replace(rotacionado)
            # O .log.1 copiado a mao ou de versao anterior pode ter nascido 0644.
            if rotacionado.is_file() and not rotacionado.is_symlink():
                os.chmod(rotacionado, 0o600)
            # O_NOFOLLOW: nao escreve num symlink plantado no lugar do arquivo.
            fd = os.open(caminho, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
            # Arquivo de versao anterior pode ter nascido 0644.
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "a", encoding="utf-8") as fh:
                fh.write(block + "\n\n")
