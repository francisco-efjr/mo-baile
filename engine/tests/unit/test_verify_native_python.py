"""PY-1: tools/verify_native_app.sh escolhe o Python com a regra do app.

A regra: o primeiro candidato (MOBAILE_PYTHON, depois os caminhos fixos do
EngineLocator) com Python >= 3.10 e as dependencias do motor importaveis.
`/usr/bin/python3` do macOS e 3.9 sem Pillow: antes ele era aceito so por
existir, e o handshake falhava sem dizer o porque.

Os candidatos falsos sao scripts que respondem a sonda com o codigo de saida
dela: 3 para versao antiga, 4 para dependencia faltando.
"""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[3] / "tools" / "verify_native_app.sh"


@unittest.skipUnless(shutil.which("bash"), "precisa de bash")
class TestEscolhaDoPython(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.pasta = pathlib.Path(self._tmp.name)

    def falso(self, nome: str, codigo: int) -> str:
        caminho = self.pasta / nome
        caminho.write_text(f"#!/bin/sh\necho 'Python 3.9.6'\nexit {codigo}\n", encoding="utf-8")
        caminho.chmod(0o755)
        return str(caminho)

    def bom(self) -> str:
        """Um Python de verdade com as dependencias: o que roda esta suite."""
        caminho = self.pasta / "python_bom"
        caminho.symlink_to(sys.executable)
        return str(caminho)

    def escolher(self, candidatos: list[str], override: str = "") -> subprocess.CompletedProcess:
        env = dict(os.environ, VERIFY_PYTHON_CANDIDATES=" ".join(candidatos), MOBAILE_PYTHON=override)
        return subprocess.run(
            ["bash", str(SCRIPT), "--so-python"], capture_output=True, text=True, env=env, timeout=60
        )

    def test_pula_versao_antiga_e_sem_dependencia(self):
        velho = self.falso("python_velho", 3)
        sem_deps = self.falso("python_sem_deps", 4)
        bom = self.bom()
        r = self.escolher([str(self.pasta / "nao_existe"), velho, sem_deps, bom])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), bom)

    def test_override_valido_vence(self):
        bom = self.bom()
        r = self.escolher([self.falso("outro", 0)], override=bom)
        self.assertEqual(r.stdout.strip(), bom, r.stderr)

    def test_override_que_nao_serve_cai_para_a_lista(self):
        bom = self.bom()
        r = self.escolher([bom], override=self.falso("override_velho", 3))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), bom)

    def test_nenhum_serve_explica_o_motivo_e_o_que_instalar(self):
        velho = self.falso("python_velho", 3)
        sem_deps = self.falso("python_sem_deps", 4)
        r = self.escolher([velho, sem_deps])
        self.assertNotEqual(r.returncode, 0)
        saida = r.stdout + r.stderr
        self.assertIn(velho, saida)
        self.assertIn("3.10", saida)
        self.assertIn(sem_deps, saida)
        self.assertIn("pip install", saida)
        self.assertIn("Pillow", saida)


if __name__ == "__main__":
    unittest.main()
