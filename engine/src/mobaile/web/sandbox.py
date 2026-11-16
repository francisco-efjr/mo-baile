"""Pasta da sessão do front web: uploads, confinamento de caminhos e downloads.

A página nunca manda caminho do disco para o motor. Ela envia o arquivo, recebe
um nome gerado dentro da pasta da sessão e devolve esse nome nas chamadas. Todo
caminho que chega é resolvido (links simbólicos e `..` incluídos) e precisa
cair dentro da pasta; o resto é recusado antes de qualquer leitura. Download e
visualização usam id opaco, nunca caminho.
"""

from __future__ import annotations

import codecs
import secrets
import shutil
import tempfile
import threading
import time
from pathlib import Path

from mobaile.domain.errors import InvalidInputError
from mobaile.security import MAX_LOG_BYTES, MAX_SPEC_BYTES
from mobaile.security.files import MAX_PATH_CHARS

UPLOAD_LIMITS = {"spec": MAX_SPEC_BYTES, "log": MAX_LOG_BYTES}
_SUFFIXES = {"spec": ".json", "log": ".log"}
# O bilhete do iframe vale uma vez e por pouco tempo: o endereço não vira chave.
TICKET_TTL_S = 60.0
# UTF-32 antes de UTF-16: o BOM do UTF-32 LE começa com o do UTF-16 LE.
_BOMS = (
    (codecs.BOM_UTF32_LE, "utf-32-le"), (codecs.BOM_UTF32_BE, "utf-32-be"),
    (codecs.BOM_UTF8, "utf-8"), (codecs.BOM_UTF16_LE, "utf-16-le"), (codecs.BOM_UTF16_BE, "utf-16-be"),
)


def decode_text(data: bytes, *, label: str, strict: bool) -> str:
    """Texto do arquivo enviado. O BOM manda: o `>` do PowerShell 5 grava UTF-16.

    Sem isso o log em UTF-16 viraria texto com byte nulo entre as letras, e a
    auditoria diria "o log não tem eventos" em vez de ler o arquivo.
    """
    encoding = "utf-8"
    for bom, name in _BOMS:
        if data.startswith(bom):
            data, encoding = data[len(bom):], name
            break
    try:
        return data.decode(encoding, errors="strict" if strict else "replace")
    except UnicodeDecodeError as exc:
        raise InvalidInputError(f"O arquivo de {label} não está em UTF-8 nem em UTF-16.") from exc


class Session:
    """Uma pasta temporária por execução do servidor, apagada ao sair."""

    def __init__(self) -> None:
        # `mkdtemp` cria a pasta só para o dono (0700) onde há permissão POSIX.
        self.root = Path(tempfile.mkdtemp(prefix="mobaile-web-")).resolve()
        self._lock = threading.Lock()
        self._files: dict[str, Path] = {}
        self._tickets: dict[str, tuple[str, float]] = {}

    def save_upload(self, kind: str, data: bytes) -> str:
        """Grava o envio em UTF-8 com nome gerado e devolve esse nome (relativo à sessão)."""
        limit = UPLOAD_LIMITS.get(kind)
        if limit is None:
            raise InvalidInputError("Tipo de envio desconhecido: use spec ou log.")
        if len(data) > limit:
            raise InvalidInputError(f"O arquivo de {kind} passa do limite de {limit // (1024 * 1024)} MB.")
        text = decode_text(data, label=kind, strict=kind == "spec")
        name = f"{kind}-{secrets.token_hex(8)}{_SUFFIXES[kind]}"
        (self.root / name).write_bytes(text.encode("utf-8"))
        return name

    def confine(self, raw: object, label: str) -> str:
        """Caminho de `label` dentro da sessão, ou recusa. Nunca devolve caminho de fora."""
        if not isinstance(raw, str) or not raw.strip() or "\x00" in raw or len(raw) > MAX_PATH_CHARS:
            raise InvalidInputError(f"Envie o arquivo de {label} por esta página antes.")
        path = (self.root / raw.strip()).resolve()
        if not path.is_relative_to(self.root):
            raise InvalidInputError(f"O arquivo de {label} precisa ter sido enviado por esta página.")
        return str(path)

    def new_export_dir(self) -> Path:
        path = self.root / f"export-{secrets.token_hex(8)}"
        path.mkdir()
        return path

    def register(self, path: Path) -> str:
        """Id opaco para baixar um arquivo gerado na sessão."""
        if not path.resolve().is_relative_to(self.root):
            raise InvalidInputError("Só arquivos desta sessão podem ser baixados.")
        file_id = secrets.token_urlsafe(16)
        with self._lock:
            self._files[file_id] = path
        return file_id

    def lookup(self, file_id: str) -> Path | None:
        with self._lock:
            return self._files.get(file_id)

    def ticket(self, file_id: object) -> str:
        """Bilhete de uso único para o iframe, que não manda cabeçalho de token."""
        path = self.lookup(file_id) if isinstance(file_id, str) else None
        if path is None or path.suffix != ".html":
            raise InvalidInputError("Esse relatório não existe nesta sessão.")
        ticket = secrets.token_urlsafe(16)
        with self._lock:
            self._tickets[ticket] = (file_id, time.monotonic() + TICKET_TTL_S)
        return ticket

    def redeem(self, ticket: str) -> Path | None:
        with self._lock:
            file_id, expires = self._tickets.pop(ticket, ("", 0.0))
        return self.lookup(file_id) if time.monotonic() < expires else None

    def cleanup(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)
