"""Motor subido com `python3 -S`: bibliotecas sem seguir `.pth`.

Um `.pth` de instalação editável apontava para uma pasta em `~/Documents`, e o
macOS pedia acesso à pasta Documentos toda vez que o app subia o motor.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from mobaile import _site

SRC = Path(__file__).resolve().parents[2] / "src"


class TestSiteSemPth(unittest.TestCase):
    def test_entra_a_pasta_de_bibliotecas_e_nao_o_destino_do_pth(self):
        with tempfile.TemporaryDirectory() as raiz:
            libs, protegida = Path(raiz, "site-packages"), Path(raiz, "Documents", "projeto")
            libs.mkdir()
            protegida.mkdir(parents=True)
            (libs / "__editable__.projeto.pth").write_text(f"{protegida}\n", encoding="utf-8")
            with mock.patch.object(_site.site, "getsitepackages", return_value=[str(libs)]), \
                    mock.patch.object(_site.site, "check_enableusersite", return_value=False), \
                    mock.patch.object(sys, "path", list(sys.path)):
                self.assertEqual(_site.add_site_packages(), [str(libs)])
                self.assertIn(str(libs), sys.path)
                self.assertNotIn(str(protegida), sys.path)
                self.assertEqual(_site.add_site_packages(), [], "a mesma pasta não entra duas vezes")

    def test_motor_sobe_com_menos_s_e_responde(self):
        hello = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "engine.hello", "params": {"protocol_version": 2}})
        env = dict(os.environ, PYTHONPATH=str(SRC))
        result = subprocess.run([sys.executable, "-S", "-m", "mobaile.rpc"], input=hello + "\n",
                                capture_output=True, text=True, env=env, timeout=30, check=False)
        resposta = json.loads(result.stdout.splitlines()[0])
        self.assertEqual(resposta["result"]["protocol_version"], 2, result.stderr)


if __name__ == "__main__":
    unittest.main()
