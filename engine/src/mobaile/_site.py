"""Bibliotecas instaladas sem os arquivos `.pth`.

O app nativo sobe o motor com `python3 -S`: sem o `site`, o Python não lê os
`.pth` do site-packages. Um `.pth` de instalação editável aponta para a pasta
do projeto, e se ela estiver em `~/Documents` o macOS pede acesso à pasta
Documentos toda vez que o motor sobe, em nome do app (era o `tag_audit` do
bold-kepler). O motor não precisa de nada que venha de `.pth`.

Aqui entram só as pastas de bibliotecas (do sistema e, se permitido, a do
usuário), no fim do caminho, como o `site` faria, mas sem seguir os `.pth`.
"""

from __future__ import annotations

import os
import site
import sys


def add_site_packages() -> list[str]:
    """Põe as pastas site-packages no `sys.path` e devolve as que entraram."""
    folders = list(site.getsitepackages())
    if site.check_enableusersite():
        folders.append(site.getusersitepackages())
    added = []
    for folder in folders:
        if folder not in sys.path and os.path.isdir(folder):
            sys.path.append(folder)
            added.append(folder)
    return added
