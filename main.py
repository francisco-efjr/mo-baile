#!/usr/bin/env python3
"""Atalho para a interface Python.

O ponto de entrada real vive em `apps/tk-legacy/main.py`. Este arquivo existe
porque `python3 main.py` na raiz e o comando que esta na memoria muscular do
time e em atalhos antigos. Ele so redireciona.
"""

import os
import runpy
import sys

_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.argv[0] = os.path.join(_ROOT, "apps", "tk-legacy", "main.py")
runpy.run_path(sys.argv[0], run_name="__main__")
