"""Leitor do MJPEG que o WebDriverAgent serve da tela do simulador.

O WDA expõe `multipart/x-mixed-replace` na porta 9100: um JPEG por parte, já
codificado pelo próprio simulador. Ler esse fluxo e repassar os bytes evita o
`simctl io screenshot` (centenas de ms por captura) e a reencodificação no
motor. Este módulo só lê; quem decide usar é o servidor, que cai na captura
por `simctl` quando o MJPEG não responde.
"""

from __future__ import annotations

import http.client
import logging
import socket
import threading
from urllib.parse import urlsplit

logger = logging.getLogger(__name__)

_SOI = b"\xff\xd8"
_EOI = b"\xff\xd9"


class MJPEGReader:
    """Mantém sempre o último quadro JPEG do fluxo, em uma thread própria."""

    def __init__(self, url: str, connect_timeout: float = 2.0):
        self.url = url
        self.connect_timeout = connect_timeout
        self._lock = threading.Lock()
        self._latest: bytes | None = None
        self._seq = 0
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._resp = None
        self._conn = None
        self._buf = bytearray()

    # ------------------------------------------------------------ ciclo

    def start(self) -> bool:
        """Conecta dentro do prazo. `False` quando o MJPEG não responde."""
        partes = urlsplit(self.url)
        if partes.scheme != "http" or not partes.hostname:
            logger.info("MJPEG: URL invalida %r", self.url)
            return False
        try:
            # http.client direto, e nao urlopen: a URL e local (host do WDA) e
            # o esquema ja foi conferido acima.
            self._conn = http.client.HTTPConnection(partes.hostname, partes.port or 80, timeout=self.connect_timeout)
            self._conn.request("GET", partes.path or "/")
            self._resp = self._conn.getresponse()
            if self._resp.status != 200:
                raise OSError(f"HTTP {self._resp.status}")
            # O prazo curto vale so para conectar. Na leitura, uma pausa do WDA
            # (um /wda/keys longo, uma transicao) passa de 2 s e derrubaria o
            # fluxo; o `stop()` fecha o socket e destrava a leitura. A resposta
            # e `will_close` (sem Content-Length), entao `conn.sock` ja e None:
            # o socket vivo e o do arquivo da resposta.
            sock = getattr(getattr(self._resp.fp, "raw", None), "_sock", None)
            if sock is not None:
                sock.settimeout(None)
        except (OSError, ValueError, http.client.HTTPException) as exc:
            logger.info("MJPEG indisponivel em %s: %s", self.url, exc)
            self._fechar()
            return False
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True, name="mobaile-mjpeg")
        self._thread.start()
        return True

    def stop(self) -> None:
        self._stop.set()
        self._fechar()
        if self._thread and self._thread is not threading.current_thread():
            self._thread.join(timeout=2.0)
        self._thread = None

    def _fechar(self) -> None:
        # `shutdown` acorda um `read1` bloqueado; so `close` nao garante isso.
        sock = getattr(getattr(getattr(self._resp, "fp", None), "raw", None), "_sock", None)
        if sock is not None:
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        for recurso in (self._resp, self._conn):
            if recurso is not None:
                try:
                    recurso.close()
                except OSError:
                    pass
        self._resp = None
        self._conn = None

    def is_running(self) -> bool:
        return bool(self._thread and self._thread.is_alive())

    def latest(self) -> tuple[bytes, int] | None:
        """O quadro mais novo e o seu número de sequência, ou `None`."""
        with self._lock:
            if self._latest is None:
                return None
            return self._latest, self._seq

    # ------------------------------------------------------------ leitura

    def _loop(self) -> None:
        resp = self._resp
        try:
            while not self._stop.is_set():
                frame = self._read_part(resp)
                if frame is None:
                    break
                with self._lock:
                    self._latest = frame
                    self._seq += 1
        except (OSError, ValueError, http.client.HTTPException, AttributeError) as exc:
            # AttributeError: `stop()` fechou a resposta no meio de um `read1`
            # (o http.client tenta fechar um `fp` que ja e None).
            if not self._stop.is_set():
                logger.info("Fluxo MJPEG terminou: %s", exc)

    def _read_part(self, resp) -> bytes | None:
        """Uma parte do multipart: cabeçalhos, linha em branco e o JPEG.

        Tudo passa por um buffer alimentado com `read1`, que devolve o que já
        chegou em vez de esperar encher: o fluxo nunca termina, e `read(n)`
        travaria. Com `Content-Length` (o que o WDA manda) lê o tamanho exato;
        sem ele, recorta do marcador de início ao de fim do JPEG. O que sobra
        depois do quadro fica no buffer para a parte seguinte.
        """
        buf = self._buf
        while True:
            fim_cabecalho, salto = buf.find(b"\r\n\r\n"), 4
            if fim_cabecalho < 0:
                fim_cabecalho, salto = buf.find(b"\n\n"), 2
            if fim_cabecalho >= 0:
                cabecalho = bytes(buf[:fim_cabecalho])
                inicio = fim_cabecalho + salto
                length = None
                for linha in cabecalho.splitlines():
                    nome, _, valor = linha.partition(b":")
                    if nome.strip().lower() == b"content-length":
                        try:
                            length = int(valor.strip())
                        except ValueError:
                            length = None
                if length is not None and length > 0:
                    if len(buf) >= inicio + length:
                        quadro = bytes(buf[inicio:inicio + length])
                        del buf[:inicio + length]
                        return quadro
                else:
                    soi = buf.find(_SOI, inicio)
                    eoi = buf.find(_EOI, soi + 2) if soi >= 0 else -1
                    if soi >= 0 and eoi > soi:
                        quadro = bytes(buf[soi:eoi + 2])
                        del buf[:eoi + 2]
                        return quadro
            chunk = resp.read1(65536)
            if not chunk:
                return None
            buf += chunk
