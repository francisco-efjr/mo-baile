"""Escrita segura de artefatos executáveis e pasta dos logs.

O gerador de fluxos produz um script Python e o executa. Escrever esse script
na raiz do projeto com permissão 0755 significa colocar código executável num
caminho previsível, gravável por qualquer processo do usuário, entre a escrita
e a execução. Aqui ele vai para um diretório por sessão, criado com 0700 e
arquivo 0600 — a execução é feita via `sys.executable <script>`, que não exige
bit de execução.

Log de diagnóstico também é dado sensível: leva URL, nome de tela e caminho
do usuário. `logs_dir()` é a pasta única dos logs do motor, só do dono.
"""

from __future__ import annotations

import os
import stat
import sys
import tempfile
from pathlib import Path

_DIR_NAME = "mobaile-runtime"
_LOG_DIR_ENV = "MOBAILE_LOG_DIR"


def secure_runtime_dir() -> Path:
    """Diretório privado da sessão (0700), criado sob demanda."""
    base = Path(tempfile.gettempdir()) / f"{_DIR_NAME}-{os.getuid()}"
    base.mkdir(mode=0o700, exist_ok=True)
    # Se já existia com permissão frouxa, corrige.
    current = stat.S_IMODE(base.stat().st_mode)
    if current != 0o700:
        base.chmod(0o700)
    return base


def logs_dir() -> Path:
    """Pasta dos logs do motor (0700), criada sob demanda.

    `MOBAILE_LOG_DIR` manda quando definida (testes e quem quer o log noutro
    lugar). Sem ela: `~/Library/Logs/Mo baile` no macOS, onde o Console.app
    procura, e `~/.mobaile/logs` fora dele.

    Levanta `OSError` se o caminho for symlink, não for pasta ou for de outro
    usuário: seguir um symlink plantado mandaria o log, e o `chmod`, para o
    destino que outro processo escolheu. Quem chama decide o que fazer sem log.
    """
    override = os.environ.get(_LOG_DIR_ENV)
    if override:
        base = Path(override).expanduser()
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Logs" / "Mo baile"
    else:
        base = Path.home() / ".mobaile" / "logs"
    if not base.is_symlink():
        base.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Conferido pelo descritor, e não pelo caminho: O_NOFOLLOW recusa o
    # symlink (inclusive um trocado depois do mkdir) e O_DIRECTORY recusa
    # arquivo no lugar da pasta; fstat e fchmod agem no que foi aberto.
    fd = os.open(base, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(fd)
        if info.st_uid != os.getuid():
            raise OSError(f"Pasta de logs recusada (de outro usuário): {base}")
        # mkdir não muda pasta que já existia, e o umask pode ter afrouxado a nova.
        if stat.S_IMODE(info.st_mode) != 0o700:
            os.fchmod(fd, 0o700)
    finally:
        os.close(fd)
    return base


def write_executable_script(content: str, filename: str = "flow_runner.py") -> Path:
    """Grava o script com 0600 e devolve o caminho absoluto."""
    target = secure_runtime_dir() / filename
    # O_NOFOLLOW evita seguir um symlink plantado por outro processo.
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
    fd = os.open(target, flags, 0o600)
    # fdopen assume a posse do descritor: o `with` fecha em erro e em sucesso.
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(content)
    target.chmod(0o600)
    return target
