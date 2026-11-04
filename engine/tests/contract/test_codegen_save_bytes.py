"""PO-1 (P0-3): `codegen.save` grava os bytes que o PyCharm gravaria.

O PyCharm guarda toda quebra de linha como `\\n` no documento e grava com o
separador do arquivo (LF no macOS), em UTF-8 sem BOM. Ao salvar, nao remove
espaco no fim da linha nem forca quebra de linha final (D-3). Nada de
normalizacao Unicode: o `e` com acento em NFC e em NFD sai como entrou.

Os bytes esperados sao os da secao 5.3 de `docs/research/pycharm-page-objects.md`.
Eles sao previsao a partir de fatos verificados do PyCharm; o oraculo real (colar
T1 no PyCharm e rodar `xxd`) ainda precisa confirmar (risco R6 da pesquisa).
"""

from __future__ import annotations

import io
import json
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

from mobaile.rpc.server import EngineServer

# Texto de prova T1, linha a linha (secao 5.2).
T1_LINHAS = [
    "s = \"reta\" + 'simples'",
    "# -- ... --- fim",
    "a\tb",
    "x\u00a0y",
    "z\u200bw",
    "\U0001F600 \U0001F469\u200d\U0001F4BB",
    "c\u00e9 ce\u0301",
    "def f():",
    "    return 1",
]

# Bytes da secao 5.3: oito 0A, nenhum 0D, sem BOM e sem 0A no fim.
T1_BYTES = bytes.fromhex(
    "73 20 3D 20 22 72 65 74 61 22 20 2B 20 27 73 69 6D 70 6C 65 73 27 0A"
    "23 20 2D 2D 20 2E 2E 2E 20 2D 2D 2D 20 66 69 6D 0A"
    "61 09 62 0A"
    "78 C2 A0 79 0A"
    "7A E2 80 8B 77 0A"
    "F0 9F 98 80 20 F0 9F 91 A9 E2 80 8D F0 9F 92 BB 0A"
    "63 C3 A9 20 63 65 CC 81 0A"
    "64 65 66 20 66 28 29 3A 0A"
    "20 20 20 20 72 65 74 75 72 6E 20 31"
)


class TestCodegenSaveBytes(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        home = pathlib.Path(self._tmp.name)
        self.raiz = home / "Documents" / "Mo baile"
        env = patch.dict(os.environ, {"HOME": str(home)})
        env.start()
        self.addCleanup(env.stop)
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)

    def salvar(self, acoes: str, locators: str = "X = 1") -> tuple[bytes, bytes]:
        resposta = self.server.handle_message(json.dumps({
            "jsonrpc": "2.0", "id": 1, "method": "codegen.save",
            "params": {"key": "prova", "actions_code": acoes, "locators_code": locators},
        }))
        self.assertNotIn("error", resposta, resposta)
        return (
            (self.raiz / "pages" / "prova.py").read_bytes(),
            (self.raiz / "locators" / "prova.py").read_bytes(),
        )

    def test_t1_ja_normalizado_grava_os_bytes_do_pycharm(self):
        pages, _ = self.salvar("\n".join(T1_LINHAS))
        self.assertEqual(pages, T1_BYTES)

    def test_t1_com_crlf_grava_so_lf(self):
        """Cliente antigo ou harness que mande CRLF: o disco recebe LF, como o
        documento do PyCharm, que normaliza toda quebra de linha."""
        pages, locators = self.salvar("\r\n".join(T1_LINHAS), "A = 1\rB = 2\r\n")
        self.assertEqual(pages, T1_BYTES)
        self.assertEqual(locators, b"A = 1\nB = 2\n")

    def test_sem_bom_e_sem_quebra_final_forcada(self):
        pages, locators = self.salvar("x = 1", "Y = 2  ")
        self.assertFalse(pages.startswith(b"\xef\xbb\xbf"))
        self.assertEqual(pages, b"x = 1")
        # Espaco no fim da linha fica (D-3).
        self.assertEqual(locators, b"Y = 2  ")

    def test_nfd_e_nfc_ficam_como_vieram(self):
        pages, _ = self.salvar("c\u00e9 ce\u0301")
        self.assertEqual(pages, "c\u00e9 ce\u0301".encode())

    def test_u2028_nao_vira_quebra_de_linha(self):
        """LSEP e PSEP nao sao separador de linha no PyCharm: ficam no texto."""
        pages, _ = self.salvar("a\u2028b\u2029c")
        self.assertEqual(pages, "a\u2028b\u2029c".encode())


if __name__ == "__main__":
    unittest.main()
