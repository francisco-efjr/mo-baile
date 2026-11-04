"""Arvore Projeto da aba Page Objects (PO-5): listar, ler e gravar arquivos.

So a pasta de trabalho do Mo baile (`~/Documents/Mo baile`), e so as pastas
onde o motor ja grava: `pages` e `locators` (`codegen.save`) e `flows`
(`flow.maestro_export`). Specs e Relatorios ficam fora nesta rodada (D-4).

Travas (SEC-5, as mesmas do `codegen.save`): caminho relativo sem `..`,
nenhum link simbolico em nenhum nivel, extensao de texto conhecida, arquivo
de ate 1 MB em bytes. Leitura com `O_NOFOLLOW` e gravacao atomica
(`security.paths.write_file_atomic`).

Texto como o PyCharm: o documento chega ao front com LF; o separador do
arquivo (LF, CRLF ou CR) e o BOM vao a parte e voltam na gravacao. Arquivo
que nao e UTF-8 abre como somente leitura e nao e regravado.
"""

from __future__ import annotations

import codecs
import os
import pathlib
from typing import Any

from mobaile.domain.errors import FileChangedError, InvalidInputError
from mobaile.security.paths import write_file_atomic

PASTAS = ("pages", "locators", "flows")
EXTENSOES = frozenset({".py", ".yaml", ".yml", ".json", ".txt", ".md"})
LIMITE_BYTES = 1_000_000
LIMITE_NOS = 2_000
PROFUNDIDADE = 8
SEPARADORES = {"LF": "\n", "CRLF": "\r\n", "CR": "\r"}


def raiz_padrao() -> pathlib.Path:
    return pathlib.Path.home() / "Documents" / "Mo baile"


def arvore(raiz: pathlib.Path) -> dict[str, Any]:
    """Pastas e arquivos, pastas primeiro, em ordem alfabetica sem caixa.

    `truncated` diz que algo ficou de fora: limite de nos ou de profundidade.
    Pasta que nao da para ler vem vazia, com `error` (R-10).
    """
    estado = {"restantes": LIMITE_NOS, "cortado": False}
    nos = [
        _no(raiz / nome, raiz, estado, 0)
        for nome in sorted(PASTAS)
        if (raiz / nome).is_dir() and not (raiz / nome).is_symlink()
    ]
    return {
        "root": str(raiz), "name": raiz.name, "exists": raiz.is_dir(),
        "nodes": nos, "truncated": estado["cortado"],
    }


def _no(caminho: pathlib.Path, raiz: pathlib.Path, estado: dict[str, Any], nivel: int) -> dict[str, Any]:
    estado["restantes"] -= 1
    no: dict[str, Any] = {"name": caminho.name, "path": caminho.relative_to(raiz).as_posix()}
    if not caminho.is_dir():
        return {**no, "kind": "file"}
    filhos: list[dict[str, Any]] = []
    try:
        entradas = [
            e for e in caminho.iterdir()
            if not e.name.startswith(".") and not e.is_symlink() and (e.is_dir() or e.is_file())
        ]
    except OSError as exc:
        return {**no, "kind": "dir", "children": filhos, "error": exc.strerror or str(exc)}
    if entradas and nivel >= PROFUNDIDADE:
        estado["cortado"] = True
        return {**no, "kind": "dir", "children": filhos}
    for entrada in sorted(entradas, key=lambda e: (not e.is_dir(), e.name.casefold())):
        if estado["restantes"] <= 0:
            estado["cortado"] = True
            break
        filhos.append(_no(entrada, raiz, estado, nivel + 1))
    return {**no, "kind": "dir", "children": filhos}


def _caminho(raiz: pathlib.Path, relativo: Any) -> pathlib.Path:
    """Resolve `relativo` dentro da raiz, ou recusa."""
    texto = relativo if isinstance(relativo, str) else ""
    partes = texto.split("/")
    if (
        not texto or "\\" in texto or "\x00" in texto or texto.startswith(("/", "~"))
        or any(parte in ("", ".", "..") for parte in partes) or partes[0] not in PASTAS or len(partes) < 2
    ):
        raise InvalidInputError(f"Caminho fora das pastas do projeto: {texto!r}")
    alvo = raiz.joinpath(*partes)
    atual = raiz
    for parte in partes:
        atual = atual / parte
        if atual.is_symlink():
            raise InvalidInputError(f"Link simbolico nao e aberto: {texto!r}")
    if not alvo.resolve().is_relative_to(raiz.resolve()):
        raise InvalidInputError(f"O arquivo precisa ficar dentro de {raiz}.")
    if alvo.suffix.lower() not in EXTENSOES:
        raise InvalidInputError(f"Tipo de arquivo nao suportado: {alvo.suffix or 'sem extensao'}")
    return alvo


def _decodificar(dados: bytes) -> tuple[str, bool, bool]:
    """(texto, bom, utf8)."""
    bom = dados.startswith(codecs.BOM_UTF8)
    corpo = dados[len(codecs.BOM_UTF8):] if bom else dados
    try:
        return corpo.decode("utf-8"), bom, True
    except UnicodeDecodeError:
        return corpo.decode("latin-1"), bom, False


def _separador(texto: str) -> str:
    """O primeiro separador do arquivo, como o PyCharm detecta. Sem nenhum, LF."""
    for indice, caractere in enumerate(texto):
        if caractere == "\r":
            return "CRLF" if texto[indice + 1:indice + 2] == "\n" else "CR"
        if caractere == "\n":
            return "LF"
    return "LF"


def _erro_de_disco(exc: OSError, relativo: Any) -> InvalidInputError:
    """Sem permissao, componente que e arquivo, disco cheio: erro de entrada
    com o motivo do sistema, e nao "Erro interno no motor" (R-10)."""
    return InvalidInputError(f"Nao deu para usar {relativo}: {exc.strerror or exc}")


def _ler_limitado(alvo: pathlib.Path) -> tuple[bytes, os.stat_result]:
    """Le sem seguir link e sem passar do limite, mesmo se o arquivo crescer."""
    fd = os.open(alvo, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as entrada:
        info = os.fstat(entrada.fileno())
        if info.st_size > LIMITE_BYTES:
            raise InvalidInputError(f"Arquivo grande demais para o editor ({info.st_size} bytes).")
        dados = entrada.read(LIMITE_BYTES + 1)
    if len(dados) > LIMITE_BYTES:
        raise InvalidInputError("Arquivo grande demais para o editor.")
    return dados, info


def ler(raiz: pathlib.Path, relativo: Any) -> dict[str, Any]:
    alvo = _caminho(raiz, relativo)
    try:
        if not alvo.is_file():
            raise InvalidInputError(f"Arquivo nao encontrado: {relativo}")
        dados, info = _ler_limitado(alvo)
    except OSError as exc:
        raise _erro_de_disco(exc, relativo) from exc
    texto, bom, utf8 = _decodificar(dados)
    return {
        "path": relativo, "text": texto.replace("\r\n", "\n").replace("\r", "\n"),
        "encoding": "UTF-8" if utf8 else "desconhecida", "line_separator": _separador(texto),
        "bom": bom, "read_only": not utf8, "size": len(dados), "mtime_ns": info.st_mtime_ns,
    }


def gravar(
    raiz: pathlib.Path, relativo: Any, texto: Any, separador: Any = "LF", bom: Any = False,
    mtime_esperado: Any = None,
) -> dict[str, Any]:
    """Grava atomicamente (R-11). Com `mtime_esperado` (o `mtime_ns` do
    `read`), recusa com `file_changed` se o arquivo mudou ou sumiu (R-04)."""
    alvo = _caminho(raiz, relativo)
    if separador not in SEPARADORES:
        raise InvalidInputError(f"Separador de linha invalido: {separador!r}")
    if not isinstance(texto, str):
        raise InvalidInputError("Texto ausente.")
    corpo = texto.replace("\r\n", "\n").replace("\r", "\n").replace("\n", SEPARADORES[separador])
    dados = (codecs.BOM_UTF8 if bom is True else b"") + corpo.encode("utf-8")
    if len(dados) > LIMITE_BYTES:
        raise InvalidInputError(f"Texto grande demais para gravar ({len(dados)} bytes).")
    try:
        existe = alvo.exists()
        if mtime_esperado is not None:
            atual = alvo.stat().st_mtime_ns if existe else None
            if atual != mtime_esperado:
                raise FileChangedError(f"O arquivo {relativo} mudou no disco depois de aberto.")
        if existe:
            if not alvo.is_file():
                raise InvalidInputError(f"Nao e um arquivo: {relativo}")
            if not _decodificar(_ler_limitado(alvo)[0])[2]:
                raise InvalidInputError("Arquivo somente leitura: nao e UTF-8.")
        alvo.parent.mkdir(parents=True, exist_ok=True)
        write_file_atomic(alvo, dados)
        mtime = alvo.stat().st_mtime_ns
    except OSError as exc:
        raise _erro_de_disco(exc, relativo) from exc
    return {"path": relativo, "saved": True, "bytes": len(dados), "mtime_ns": mtime}
