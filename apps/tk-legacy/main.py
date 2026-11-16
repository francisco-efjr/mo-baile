#!/usr/bin/env python3
"""Ponto de entrada da UI Tkinter.

Ao rodar direto do codigo-fonte, o motor ainda nao esta instalado no ambiente:
`engine/src` entra no path aqui. Com o pacote instalado (`pip install -e engine`),
essa linha vira inofensiva.
"""

import os
import sys

_APP_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.dirname(os.path.dirname(_APP_DIR))

for path in (_APP_DIR, os.path.join(_REPO_ROOT, "engine", "src")):
    if path not in sys.path:
        sys.path.insert(0, path)

from mobaile_tk.main_window import launch_app  # noqa: E402


def main() -> None:
    launch_app()


if __name__ == "__main__":
    main()
