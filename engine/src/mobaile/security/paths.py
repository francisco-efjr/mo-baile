"""Escrita segura de artefatos executáveis.

O gerador de fluxos produz um script Python e o executa. Escrever esse script
na raiz do projeto com permissão 0755 significa colocar código executável num
caminho previsível, gravável por qualquer processo do usuário, entre a escrita
e a execução. Aqui ele vai para um diretório por sessão, criado com 0700 e
arquivo 0600 — a execução é feita via `sys.executable <script>`, que não exige
bit de execução.
"""

from __future__ import annotations

import os
import stat
import tempfile
from pathlib import Path

_DIR_NAME = "mobaile-runtime"


def secure_runtime_dir() -> Path:
    """Diretório privado da sessão (0700), criado sob demanda."""
    base = Path(tempfile.gettempdir()) / f"{_DIR_NAME}-{os.getuid()}"
    base.mkdir(mode=0o700, exist_ok=True)
    # Se já existia com permissão frouxa, corrige.
    current = stat.S_IMODE(base.stat().st_mode)
    if current != 0o700:
        base.chmod(0o700)
    return base


def write_executable_script(content: str, filename: str = "flow_runner.py") -> Path:
    """Grava o script com 0600 e devolve o caminho absoluto."""
    target = secure_runtime_dir() / filename
    # O_EXCL evita seguir um symlink plantado por outro processo.
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
    fd = os.open(target, flags, 0o600)
    # fdopen assume a posse do descritor: o `with` fecha em erro e em sucesso.
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(content)
    target.chmod(0o600)
    return target
