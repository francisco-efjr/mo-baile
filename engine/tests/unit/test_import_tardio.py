"""Subida do motor sem dependencia pesada que ninguem pediu.

Medido antes desta regra: ~220 ms de import, dos quais uns 125 ms eram o
Quartz (pyobjc, trazido pela escuta passiva) e uns 45 ms o `requests` (trazido
pelo Appium e pelo WDA), carregados em toda subida mesmo sem uso. O front
espera o motor a cada abertura do app.

Roda num subprocesso porque `sys.modules` do pytest ja vem sujo dos outros
testes: so um interpretador limpo diz o que a subida carrega de fato.
"""

from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import unittest

FONTE = pathlib.Path(__file__).resolve().parents[2] / "src"

PESADOS = ("Quartz", "AppKit", "objc", "requests", "urllib3", "mobaile.adapters.input_events", "pymobiledevice3")

SONDA = f"""
import json, sys
from mobaile.rpc.server import EngineServer
EngineServer()
print(json.dumps([nome for nome in {PESADOS!r} if nome in sys.modules]))
"""


class TestImportTardio(unittest.TestCase):
    def test_subir_o_motor_nao_carrega_quartz_nem_requests(self):
        env = dict(os.environ, PYTHONPATH=str(FONTE))
        saida = subprocess.run(
            [sys.executable, "-c", SONDA], capture_output=True, text=True, env=env, timeout=30, check=True
        ).stdout
        self.assertEqual(json.loads(saida.strip().splitlines()[-1]), [])


if __name__ == "__main__":
    unittest.main()
