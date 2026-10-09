"""Arquivos e pastas escolhidos pela pessoa (aba Relatório).

Spec, log, pasta de prints e pasta de saída chegam como texto pelo RPC. Antes de
abrir qualquer um, o caminho é normalizado, conferido (existe, é do tipo certo,
cabe no limite) e só então usado. Um log de 2 GB escolhido por engano não pode
derrubar o motor por falta de memória, e um caminho com byte nulo não pode
chegar ao sistema de arquivos.
"""

from __future__ import annotations

import re
import unicodedata
from pathlib import Path

from mobaile.domain.errors import InvalidInputError

MB = 1024 * 1024
MAX_SPEC_BYTES = 5 * MB
MAX_LOG_BYTES = 64 * MB
MAX_PATH_CHARS = 4096
IMAGE_SUFFIXES: tuple[str, ...] = (".png", ".jpg", ".jpeg", ".heic", ".tiff")


def _normalize(raw: object, label: str) -> Path:
    if not isinstance(raw, str) or not raw.strip():
        raise InvalidInputError(f"Informe o caminho de {label}.")
    if "\x00" in raw or len(raw) > MAX_PATH_CHARS:
        raise InvalidInputError(f"Caminho de {label} inválido.")
    return Path(raw.strip()).expanduser().resolve()


def validate_input_file(
    raw: object,
    *,
    label: str,
    max_bytes: int,
    suffixes: tuple[str, ...] = (),
) -> Path:
    """Arquivo que vai ser lido: existe, é arquivo, tem a extensão e o tamanho certos."""
    path = _normalize(raw, label)
    if not path.exists():
        raise InvalidInputError(f"Arquivo de {label} não encontrado: {path}")
    if not path.is_file():
        raise InvalidInputError(f"O caminho de {label} precisa ser um arquivo: {path}")
    if suffixes and path.suffix.lower() not in suffixes:
        raise InvalidInputError(f"O arquivo de {label} precisa ser {' ou '.join(suffixes)}: {path.name}")
    size = path.stat().st_size
    if size > max_bytes:
        raise InvalidInputError(
            f"O arquivo de {label} tem {size / MB:.1f} MB; o limite é {max_bytes // MB} MB."
        )
    return path


def validate_input_dir(raw: object, *, label: str) -> Path:
    """Pasta que vai ser lida."""
    path = _normalize(raw, label)
    if not path.is_dir():
        raise InvalidInputError(f"Pasta de {label} não encontrada: {path}")
    return path


def prepare_output_dir(raw: object, *, label: str = "saída") -> Path:
    """Pasta onde o motor vai gravar. É criada se não existir."""
    path = raw.expanduser().resolve() if isinstance(raw, Path) else _normalize(raw, label)
    if path.exists() and not path.is_dir():
        raise InvalidInputError(f"Já existe um arquivo com o nome da pasta de {label}: {path}")
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise InvalidInputError(f"Não foi possível criar a pasta de {label}: {exc.strerror or exc}") from exc
    return path


def unique_path(path: Path) -> Path:
    """O próprio caminho, ou ``nome-2.ext``, ``nome-3.ext``...: nunca sobrescreve."""
    if not path.exists():
        return path
    for n in range(2, 1000):
        candidate = path.with_name(f"{path.stem}-{n}{path.suffix}")
        if not candidate.exists():
            return candidate
    raise InvalidInputError(f"Há arquivos demais com o nome {path.name} em {path.parent}.")


def safe_file_stem(text: str, fallback: str = "relatorio") -> str:
    """Trecho de nome de arquivo a partir de texto livre (nome do projeto, pasta)."""
    plain = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode("ascii")
    stem = re.sub(r"[^A-Za-z0-9]+", "-", plain).strip("-").lower()[:60]
    return stem or fallback
