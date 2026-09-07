"""Localizacao dos arquivos de midia da aplicacao.

Antes cada modulo montava o caminho com `dirname(dirname(__file__))` e uma
lista de tentativas ligeiramente diferente em cada lugar. Isso quebrou assim
que a arvore de pastas mudou, que e exatamente o tipo de acoplamento que um
unico ponto de resolucao evita.

Ordem de busca, da mais especifica para a mais generica:
  1. `MOBAILE_ASSETS_DIR`, para empacotamento e para teste;
  2. `Contents/Resources`, quando roda dentro de um bundle .app;
  3. `assets/` na raiz do repositorio, ao rodar direto do codigo-fonte.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Optional

_MODULE_DIR = Path(__file__).resolve().parent


def repo_root() -> Path:
    """Raiz do repositorio: apps/tk-legacy/mobaile_tk -> tres niveis acima."""
    return _MODULE_DIR.parent.parent.parent


def _candidate_dirs() -> list[Path]:
    dirs: list[Path] = []
    env_dir = os.getenv("MOBAILE_ASSETS_DIR")
    if env_dir:
        dirs.append(Path(env_dir))
    # Dentro de um bundle macOS o executavel fica em Contents/MacOS.
    executable_dir = Path(sys.executable).resolve().parent
    dirs.append(executable_dir.parent / "Resources")
    dirs.append(repo_root() / "assets")
    dirs.append(Path.cwd() / "assets")
    return dirs


def asset_path(filename: str) -> Optional[str]:
    """Caminho absoluto do arquivo, ou `None` quando nao existe em lugar nenhum."""
    for directory in _candidate_dirs():
        candidate = directory / filename
        if candidate.is_file():
            return str(candidate)
    return None


def icon_path() -> Optional[str]:
    return asset_path("icon.png")


def mascot_path() -> Optional[str]:
    return asset_path("mascot.png")


def splash_video_path() -> Optional[str]:
    return asset_path("splash_app.mp4")


def splash_background_path() -> Optional[str]:
    return asset_path("splash_bg.png")
