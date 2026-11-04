"""PO-5: `workspace.tree`, `workspace.read` e `workspace.write`.

A arvore Projeto da aba Page Objects le e grava so dentro da pasta de trabalho
(`~/Documents/Mo baile`), nas pastas que o motor ja usa (`pages`, `locators`,
`flows`), sem seguir link simbolico (SEC-5). O texto chega ao front com LF; o
separador e o BOM do arquivo vao a parte e voltam na gravacao, como o PyCharm
faz (teste T4 da pesquisa).
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


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.home = pathlib.Path(self._tmp.name)
        self.raiz = self.home / "Documents" / "Mo baile"
        env = patch.dict(os.environ, {"HOME": str(self.home)})
        env.start()
        self.addCleanup(env.stop)
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)

    def call(self, method, **params):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
        )

    def ok(self, method, **params):
        resposta = self.call(method, **params)
        self.assertNotIn("error", resposta, resposta)
        return resposta["result"]

    def recusado(self, method, **params):
        resposta = self.call(method, **params)
        self.assertIn("error", resposta, resposta)
        self.assertEqual(resposta["error"]["data"]["code"], "invalid_input")

    def arquivo(self, relativo: str, dados: bytes) -> pathlib.Path:
        alvo = self.raiz / relativo
        alvo.parent.mkdir(parents=True, exist_ok=True)
        alvo.write_bytes(dados)
        return alvo


class TestArvore(Base):
    def test_pasta_inexistente_devolve_arvore_vazia(self):
        arvore = self.ok("workspace.tree")
        self.assertEqual(arvore["name"], "Mo baile")
        self.assertEqual(arvore["root"], str(self.raiz))
        self.assertFalse(arvore["exists"])
        self.assertEqual(arvore["nodes"], [])

    def test_lista_pages_locators_flows_com_pastas_primeiro(self):
        self.arquivo("pages/tela.py", b"x")
        self.arquivo("pages/sub/b.py", b"x")
        self.arquivo("pages/a.py", b"x")
        self.arquivo("locators/tela.py", b"x")
        self.arquivo("flows/login.yaml", b"x")
        self.arquivo("Specs/spec.json", b"{}")  # fora nesta rodada (D-4)
        self.arquivo("pages/.oculto.py", b"x")
        arvore = self.ok("workspace.tree")
        self.assertTrue(arvore["exists"])
        self.assertEqual([n["name"] for n in arvore["nodes"]], ["flows", "locators", "pages"])
        pages = arvore["nodes"][2]
        self.assertEqual(pages["kind"], "dir")
        self.assertEqual([(n["name"], n["kind"]) for n in pages["children"]],
                         [("sub", "dir"), ("a.py", "file"), ("tela.py", "file")])
        self.assertEqual(pages["children"][0]["children"][0]["path"], "pages/sub/b.py")
        self.assertFalse(arvore["truncated"])

    def test_link_simbolico_nao_aparece(self):
        fora = self.home / "fora"
        fora.mkdir()
        (fora / "segredo.py").write_text("x")
        (self.raiz / "pages").mkdir(parents=True)
        (self.raiz / "pages" / "atalho").symlink_to(fora, target_is_directory=True)
        (self.raiz / "pages" / "link.py").symlink_to(fora / "segredo.py")
        arvore = self.ok("workspace.tree")
        self.assertEqual(arvore["nodes"][0]["children"], [])


class TestLerEGravar(Base):
    def test_le_utf8_com_lf(self):
        self.arquivo("pages/tela.py", "def a():\n    return 'é'\n".encode())
        lido = self.ok("workspace.read", path="pages/tela.py")
        self.assertEqual(lido["text"], "def a():\n    return 'é'\n")
        self.assertEqual(lido["line_separator"], "LF")
        self.assertEqual(lido["encoding"], "UTF-8")
        self.assertFalse(lido["bom"])
        self.assertFalse(lido["read_only"])

    def test_t4_crlf_e_preservado_ao_editar_e_salvar(self):
        alvo = self.arquivo("pages/win.py", b"a = 1\r\nb = 2\r\n")
        lido = self.ok("workspace.read", path="pages/win.py")
        self.assertEqual(lido["text"], "a = 1\nb = 2\n")
        self.assertEqual(lido["line_separator"], "CRLF")
        self.ok("workspace.write", path="pages/win.py", text=lido["text"] + "c = 3",
                line_separator=lido["line_separator"], bom=lido["bom"])
        self.assertEqual(alvo.read_bytes(), b"a = 1\r\nb = 2\r\nc = 3")

    def test_trocar_para_lf_converte_o_arquivo_inteiro(self):
        alvo = self.arquivo("pages/win.py", b"a\r\nb\r\n")
        self.ok("workspace.write", path="pages/win.py", text="a\nb\n", line_separator="LF")
        self.assertEqual(alvo.read_bytes(), b"a\nb\n")

    def test_bom_e_mantido(self):
        alvo = self.arquivo("pages/bom.py", b"\xef\xbb\xbfx = 1\n")
        lido = self.ok("workspace.read", path="pages/bom.py")
        self.assertTrue(lido["bom"])
        self.assertEqual(lido["text"], "x = 1\n")
        self.ok("workspace.write", path="pages/bom.py", text="x = 2\n", line_separator="LF", bom=True)
        self.assertEqual(alvo.read_bytes(), b"\xef\xbb\xbfx = 2\n")

    def test_arquivo_que_nao_e_utf8_abre_so_leitura_e_nao_e_regravado(self):
        alvo = self.arquivo("pages/latin.py", "x = 'ação'\n".encode("latin-1"))
        lido = self.ok("workspace.read", path="pages/latin.py")
        self.assertTrue(lido["read_only"])
        self.recusado("workspace.write", path="pages/latin.py", text="y = 1\n")
        self.assertEqual(alvo.read_bytes(), "x = 'ação'\n".encode("latin-1"))

    def test_gravar_cria_arquivo_novo_dentro_das_pastas(self):
        self.ok("workspace.write", path="flows/novo.yaml", text="appId: x\n")
        self.assertEqual((self.raiz / "flows" / "novo.yaml").read_bytes(), b"appId: x\n")


class TestTravasDeCaminho(Base):
    def test_caminhos_fora_da_pasta_sao_recusados(self):
        self.arquivo("pages/ok.py", b"x")
        for caminho in ("", "/etc/passwd", "../fora.py", "pages/../../fora.py", "pages/./ok.py",
                        "Specs/x.json", "pages\\ok.py", "~/x.py", "pages/ok.exe", "pages"):
            with self.subTest(caminho=caminho):
                self.recusado("workspace.read", path=caminho)
                self.recusado("workspace.write", path=caminho, text="x")
        self.assertFalse((self.home / "fora.py").exists())

    def test_link_simbolico_e_recusado_para_ler_e_gravar(self):
        fora = self.home / "fora"
        fora.mkdir()
        (fora / "alvo.py").write_text("segredo")
        (self.raiz / "pages").mkdir(parents=True)
        (self.raiz / "pages" / "link.py").symlink_to(fora / "alvo.py")
        (self.raiz / "pages" / "pasta").symlink_to(fora, target_is_directory=True)
        for caminho in ("pages/link.py", "pages/pasta/alvo.py"):
            with self.subTest(caminho=caminho):
                self.recusado("workspace.read", path=caminho)
                self.recusado("workspace.write", path=caminho, text="x")
        self.assertEqual((fora / "alvo.py").read_text(), "segredo")

    def test_arquivo_grande_demais_e_recusado(self):
        self.arquivo("pages/grande.py", b"x" * 1_000_001)
        self.recusado("workspace.read", path="pages/grande.py")

    def test_separador_invalido_e_recusado(self):
        self.recusado("workspace.write", path="pages/a.py", text="x", line_separator="NEL")



class TestRevisao(Base):
    """Achados da revisao independente (R-04, R-09, R-10, R-11, R-14)."""

    def test_r09_limite_conta_bytes_codificados(self):
        # 400 mil caracteres de 3 bytes: menos de 1 milhao de caracteres, mais de 1 MB.
        self.recusado("workspace.write", path="pages/a.py", text="\u20ac" * 400_000)
        self.assertFalse((self.raiz / "pages" / "a.py").exists())

    def test_r09_arquivo_existente_grande_nao_e_lido_para_gravar(self):
        alvo = self.arquivo("pages/grande.py", b"x" * 1_000_001)
        self.recusado("workspace.write", path="pages/grande.py", text="y")
        self.assertEqual(alvo.stat().st_size, 1_000_001)

    def test_r10_sem_permissao_vira_erro_de_entrada_e_nao_erro_interno(self):
        alvo = self.arquivo("pages/travado.py", b"x = 1\n")
        alvo.chmod(0o444)
        self.addCleanup(alvo.chmod, 0o644)
        self.recusado("workspace.write", path="pages/travado.py", text="x = 2\n")
        self.assertEqual(alvo.read_bytes(), b"x = 1\n")
        # Componente do caminho que e arquivo, e nao pasta.
        self.arquivo("flows/arquivo.yaml", b"a: 1")
        self.recusado("workspace.write", path="flows/arquivo.yaml/dentro.yaml", text="x")

    def test_r10_pasta_sem_leitura_nao_derruba_a_arvore(self):
        self.arquivo("pages/fechada/a.py", b"x")
        fechada = self.raiz / "pages" / "fechada"
        fechada.chmod(0o000)
        self.addCleanup(fechada.chmod, 0o755)
        arvore = self.ok("workspace.tree")
        no = arvore["nodes"][0]["children"][0]
        self.assertEqual(no["name"], "fechada")
        self.assertEqual(no["children"], [])
        self.assertIn("error", no)

    def test_r11_gravacao_atomica_sem_sobra_de_temporario(self):
        alvo = self.arquivo("pages/a.py", b"velho")
        self.ok("workspace.write", path="pages/a.py", text="novo")
        self.assertEqual(alvo.read_bytes(), b"novo")
        self.assertEqual(sorted(p.name for p in alvo.parent.iterdir()), ["a.py"])

    def test_r11_symlink_plantado_no_lugar_do_arquivo_nao_e_seguido(self):
        from mobaile.security.paths import write_file_atomic

        fora = self.home / "fora.py"
        fora.write_text("segredo")
        (self.raiz / "pages").mkdir(parents=True)
        link = self.raiz / "pages" / "a.py"
        link.symlink_to(fora)
        with self.assertRaises(OSError):
            write_file_atomic(link, b"invadido")
        self.assertEqual(fora.read_text(), "segredo")

    def test_r14_corte_por_profundidade_marca_truncated(self):
        fundo = self.raiz / "pages"
        for nivel in range(10):
            fundo = fundo / f"n{nivel}"
        fundo.mkdir(parents=True)
        (fundo / "a.py").write_text("x")
        self.assertTrue(self.ok("workspace.tree")["truncated"])

    def test_r04_read_devolve_mtime_e_write_recusa_se_mudou(self):
        alvo = self.arquivo("pages/a.py", b"x = 1\n")
        lido = self.ok("workspace.read", path="pages/a.py")
        self.assertEqual(lido["mtime_ns"], alvo.stat().st_mtime_ns)
        # Outro editor (o PyCharm) grava no meio.
        alvo.write_bytes(b"x = 99\n")
        os.utime(alvo, ns=(lido["mtime_ns"] + 5_000_000, lido["mtime_ns"] + 5_000_000))
        resposta = self.call("workspace.write", path="pages/a.py", text="x = 2\n", expected_mtime_ns=lido["mtime_ns"])
        self.assertEqual(resposta["error"]["data"]["code"], "file_changed", resposta)
        self.assertEqual(alvo.read_bytes(), b"x = 99\n")
        # Sobrescrever: sem `expected_mtime_ns`, grava e devolve o mtime novo.
        gravado = self.ok("workspace.write", path="pages/a.py", text="x = 2\n")
        self.assertEqual(gravado["mtime_ns"], alvo.stat().st_mtime_ns)
        self.ok("workspace.write", path="pages/a.py", text="x = 3\n", expected_mtime_ns=gravado["mtime_ns"])

    def test_r04_arquivo_apagado_depois_de_lido_tambem_e_conflito(self):
        alvo = self.arquivo("pages/a.py", b"x")
        lido = self.ok("workspace.read", path="pages/a.py")
        alvo.unlink()
        resposta = self.call("workspace.write", path="pages/a.py", text="y", expected_mtime_ns=lido["mtime_ns"])
        self.assertEqual(resposta["error"]["data"]["code"], "file_changed")


if __name__ == "__main__":
    unittest.main()
