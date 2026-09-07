#!/usr/bin/env bash
# Lancador do Mo baile para uso no Finder.
#
# Roda a interface Python, que e a que funciona hoje. NAO abre o app instalado
# em /Applications as cegas: se ali estiver a build do front nativo, ela ainda
# nao passou por `swift test` e abre no estado vazio, sem reconhecer aparelho.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${MOBAILE_PYTHON:-python3}"
[ -x "$REPO_ROOT/.venv/bin/python3" ] && PYTHON="$REPO_ROOT/.venv/bin/python3"

if ! "$PYTHON" -c "import tkinter" 2>/dev/null; then
    echo "ERRO: o Python usado ($PYTHON) nao tem tkinter."
    echo "Use um Python do python.org, ou rode: make setup"
    exit 1
fi

exec "$PYTHON" apps/tk-legacy/main.py
