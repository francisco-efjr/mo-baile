"""Arvore Projeto da aba Page Objects (PO-5): listar, ler e gravar arquivos.

So a pasta de trabalho do Mo baile (`~/Documents/Mo baile`), e so as pastas
onde o motor ja grava: `pages` e `locators` (`codegen.save`) e `flows`
(`flow.maestro_export`). Specs e Relatorios ficam fora nesta rodada (D-4).

Travas (SEC-5, as mesmas do `codegen.save`): caminho relativo sem `..`,
nenhum link simbolico em nenhum nivel, extensao de texto conhecida, arquivo
de ate 1 MB.

Texto como o PyCharm: o documento chega ao front com LF; o separador do
arquivo (LF, CRLF ou CR) e o BOM vao a parte e voltam na gravacao. Arquivo
que nao e UTF-8 abre como somente leitura e nao e regravado.
"""

from __future__ import annotations

import codecs
import pathlib
from typing import Any

from mobaile.domain.errors import InvalidInputError

PASTAS = ("pages", "locators", "flows")
EXTENSOES = frozenset({".py", ".yaml", ".yml", ".json", ".txt", ".md"})
LIMITE_BYTES = 1_000_000
LIMITE_NOS = 2_000
PROFUNDIDADE = 8
SEPARADORES = {"LF": "\n", "CRLF": "\r\n", "CR": "\r"}


def raiz_padrao() -> pathlib.Path:
    return pathlib.Path.home() / "Documents" / "Mo baile"


def arvore(raiz: pathlib.Path) -> dict[str, Any]:
    """Pastas e arquivos, pastas primeiro, em ordem alfabetica sem caixa."""
    restantes = [LIMITE_NOS]
    nos = [
        _no(raiz / nome, raiz, restantes, 0)
        for nome in sorted(PASTAS)
        if (raiz / nome).is_dir() and not (raiz / nome).is_symlink()
    ]
    return {
        "root": str(raiz), "name": raiz.name, "exists": raiz.is_dir(),
        "nodes": nos, "truncated": restantes[0] < 0,
    }


def _no(caminho: pathlib.Path, raiz: pathlib.Path, restantes: list[int], nivel: int) -> dict[str, Any]:
    restantes[0] -= 1
    no: dict[str, Any] = {"name": caminho.name, "path": caminho.relative_to(raiz).as_posix()}
    if not caminho.is_dir():
        return {**no, "kind": "file"}
    filhos = []
    if nivel < PROFUNDIDADE:
        entradas = [
            e for e in caminho.iterdir()
            if not e.name.startswith(".") and not e.is_symlink() and (e.is_dir() or e.is_file())
        ]
        for entrada in sorted(entradas, key=lambda e: (not e.is_dir(), e.name.casefold())):
            if restantes[0] <= 0:
                restantes[0] = -1
                break
            filhos.append(_no(entrada, raiz, restantes, nivel + 1))
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


def ler(raiz: pathlib.Path, relativo: Any) -> dict[str, Any]:
    alvo = _caminho(raiz, relativo)
    if not alvo.is_file():
        raise InvalidInputError(f"Arquivo nao encontrado: {relativo}")
    tamanho = alvo.stat().st_size
    if tamanho > LIMITE_BYTES:
        raise InvalidInputError(f"Arquivo grande demais para o editor ({tamanho} bytes).")
    texto, bom, utf8 = _decodificar(alvo.read_bytes())
    return {
        "path": relativo, "text": texto.replace("\r\n", "\n").replace("\r", "\n"),
        "encoding": "UTF-8" if utf8 else "desconhecida", "line_separator": _separador(texto),
        "bom": bom, "read_only": not utf8, "size": tamanho,
    }


def gravar(raiz: pathlib.Path, relativo: Any, texto: Any, separador: Any = "LF", bom: Any = False) -> dict[str, Any]:
    alvo = _caminho(raiz, relativo)
    if separador not in SEPARADORES:
        raise InvalidInputError(f"Separador de linha invalido: {separador!r}")
    if not isinstance(texto, str) or len(texto) > LIMITE_BYTES:
        raise InvalidInputError("Texto ausente ou grande demais para gravar.")
    if alvo.exists():
        if not alvo.is_file():
            raise InvalidInputError(f"Nao e um arquivo: {relativo}")
        if not _decodificar(alvo.read_bytes())[2]:
            raise InvalidInputError("Arquivo somente leitura: nao e UTF-8.")
    corpo = texto.replace("\r\n", "\n").replace("\r", "\n").replace("\n", SEPARADORES[separador])
    dados = (codecs.BOM_UTF8 if bom is True else b"") + corpo.encode("utf-8")
    alvo.parent.mkdir(parents=True, exist_ok=True)
    alvo.write_bytes(dados)
    return {"path": relativo, "saved": True, "bytes": len(dados)}
