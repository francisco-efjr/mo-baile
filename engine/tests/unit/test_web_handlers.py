"""Front web local (LIB-5): handlers, confinamento e decodificação, sem rede.

A página nunca manda caminho do disco para o motor: envia o arquivo, recebe um
nome gerado dentro da pasta da sessão e devolve esse nome. Aqui se prova que
nada fora da sessão é lido nem gravado, que os prints de uma spec de terceiros
não entram no HTML e que só os métodos da allowlist chegam ao serviço.
Dados sintéticos de `relatorio_dados`.
"""

from __future__ import annotations

import base64
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from PIL import Image
from relatorio_dados import LOG, SPEC, TOTAL, gravar

from mobaile.rpc import protocol
from mobaile.services.report import ReportService
from mobaile.web.handlers import ALLOWED_METHODS, WebHandlers
from mobaile.web.sandbox import Session, decode_text

LOGCAT = "\n".join([
    "11-16 10:00:00.000 V/FA-SVC  (1): Logging event: origin=app,name=screen_view(_vs),"
    "params=Bundle[{ga_event_origin(_o)=app, ga_screen(_sn)=app:home, flow_name=pedido}]",
    "11-16 10:00:01.000 I/ActivityManager(1): linha que não é evento",
    "11-16 10:00:02.500 V/FA-SVC  (1): Logging event: origin=app,name=add_to_cart,"
    "params=Bundle[{value=10, items=[Bundle[{item_id=1, item_name=pedido}]]}]",
])


def png_bytes() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (8, 8), (12, 34, 56)).save(buffer, format="PNG")
    return buffer.getvalue()


class Base(unittest.TestCase):
    def setUp(self):
        self.session = Session()
        self.addCleanup(self.session.cleanup)
        self.handlers = WebHandlers(self.session)
        self.fora = tempfile.TemporaryDirectory()
        self.addCleanup(self.fora.cleanup)
        self.pasta_fora = Path(self.fora.name).resolve()

    def rpc(self, method, params=None, id_=1):
        body = json.dumps({"jsonrpc": "2.0", "id": id_, "method": method, "params": params or {}}).encode()
        return self.handlers.handle_rpc(body)

    def enviar(self, spec=None, log=None):
        spec_nome = self.session.save_upload("spec", json.dumps(spec or SPEC, ensure_ascii=False).encode())
        log_nome = self.session.save_upload("log", json.dumps(log or LOG, ensure_ascii=False).encode())
        return spec_nome, log_nome

    def auditar(self, **extra):
        spec_nome, log_nome = self.enviar()
        return self.rpc("report.audit", {"spec_path": spec_nome, "log_path": log_nome, "source": "file", **extra})

    def assertRecusa(self, resposta, trecho=None):
        self.assertIn("error", resposta, resposta)
        self.assertEqual(resposta["error"]["code"], protocol.ENGINE_ERROR)
        self.assertEqual(resposta["error"]["data"]["code"], "invalid_input")
        if trecho:
            self.assertIn(trecho, resposta["error"]["message"])


class TestDecodificacao(unittest.TestCase):
    def test_utf16_com_bom_do_powershell(self):
        texto = "Logging event: ação"
        self.assertEqual(decode_text(b"\xff\xfe" + texto.encode("utf-16-le"), label="log", strict=True), texto)
        self.assertEqual(decode_text(b"\xfe\xff" + texto.encode("utf-16-be"), label="log", strict=True), texto)

    def test_bom_utf8_sai_do_texto(self):
        self.assertEqual(decode_text(b"\xef\xbb\xbf{}", label="spec", strict=True), "{}")

    def test_spec_fora_de_utf8_e_recusada_e_log_e_tolerado(self):
        from mobaile.domain.errors import InvalidInputError

        with self.assertRaises(InvalidInputError):
            decode_text(b"\xe7\xe3o", label="spec", strict=True)
        self.assertIn("�", decode_text(b"\xe7\xe3o", label="log", strict=False))


class TestSessao(Base):
    def test_upload_tem_nome_gerado_dentro_da_sessao(self):
        nome = self.session.save_upload("spec", b"{}")
        self.assertRegex(nome, r"^spec-[0-9a-f]{16}\.json$")
        self.assertTrue((self.session.root / nome).is_file())
        self.assertNotEqual(nome, self.session.save_upload("spec", b"{}"))

    def test_upload_utf16_vira_utf8_no_disco(self):
        nome = self.session.save_upload("log", b"\xff\xfe" + LOGCAT.encode("utf-16-le"))
        self.assertEqual((self.session.root / nome).read_text(encoding="utf-8"), LOGCAT)

    def test_tipo_de_upload_desconhecido(self):
        from mobaile.domain.errors import InvalidInputError

        with self.assertRaises(InvalidInputError):
            self.session.save_upload("../x", b"{}")

    def test_caminho_fora_da_sessao_e_recusado(self):
        from mobaile.domain.errors import InvalidInputError

        spec_fora, _ = gravar(self.pasta_fora)
        for caminho in (str(spec_fora), "/etc/hosts", "../../etc/hosts", "", None, 3, "a\x00b", "x" * 5000):
            with self.subTest(caminho=caminho), self.assertRaises(InvalidInputError):
                self.session.confine(caminho, "spec")
        # No Windows a contrabarra sobe de pasta; no POSIX é parte do nome. Nos dois, fica na sessão ou é recusado.
        try:
            dentro = Path(self.session.confine("..\\..\\x", "spec"))
        except InvalidInputError:
            pass
        else:
            self.assertTrue(dentro.is_relative_to(self.session.root))
        self.assertRecusa(self.rpc("report.spec", {"path": "..\\..\\x"}))

    @unittest.skipIf(os.name == "nt", "link simbólico exige privilégio no Windows")
    def test_link_simbolico_para_fora_e_recusado(self):
        from mobaile.domain.errors import InvalidInputError

        spec_fora, _ = gravar(self.pasta_fora)
        (self.session.root / "atalho.json").symlink_to(spec_fora)
        with self.assertRaises(InvalidInputError):
            self.session.confine("atalho.json", "spec")

    def test_bilhete_de_visualizacao_e_de_uso_unico_e_so_html(self):
        pasta = self.session.new_export_dir()
        html, md = pasta / "r.html", pasta / "r.md"
        html.write_text("<p>oi</p>", encoding="utf-8")
        md.write_text("# oi", encoding="utf-8")
        bilhete = self.session.ticket(self.session.register(html))
        self.assertEqual(self.session.redeem(bilhete), html)
        self.assertIsNone(self.session.redeem(bilhete))
        from mobaile.domain.errors import InvalidInputError

        with self.assertRaises(InvalidInputError):
            self.session.ticket(self.session.register(md))
        with self.assertRaises(InvalidInputError):
            self.session.ticket("id-que-nao-existe")

    def test_registro_recusa_arquivo_fora_da_sessao(self):
        from mobaile.domain.errors import InvalidInputError

        spec_fora, _ = gravar(self.pasta_fora)
        with self.assertRaises(InvalidInputError):
            self.session.register(spec_fora)

    def test_limpeza_apaga_a_pasta(self):
        self.session.save_upload("spec", b"{}")
        self.session.cleanup()
        self.assertFalse(self.session.root.exists())


class TestAllowlist(Base):
    def test_allowlist_e_fechada(self):
        self.assertEqual(ALLOWED_METHODS, frozenset({"report.spec", "report.audit", "report.export"}))

    def test_metodo_fora_da_allowlist_da_32601(self):
        for metodo in ("report.import", "report.checklist_export", "report.cards_update", "report.card_update",
                       "workspace.open", "run.start", "engine.hello", "analytics.start", "proxy.start"):
            with self.subTest(metodo=metodo):
                resposta = self.rpc(metodo, {"path": "/etc/hosts"})
                self.assertEqual(resposta["error"]["code"], protocol.METHOD_NOT_FOUND)

    def test_method_que_nao_e_texto(self):
        resposta = self.handlers.handle_rpc(json.dumps({"jsonrpc": "2.0", "id": 1, "method": ["x"]}).encode())
        self.assertEqual(resposta["error"]["code"], protocol.METHOD_NOT_FOUND)

    def test_envelope_invalido(self):
        self.assertEqual(self.handlers.handle_rpc(b"{nao json")["error"]["code"], protocol.PARSE_ERROR)
        self.assertEqual(self.handlers.handle_rpc(b"\xff\xfe")["error"]["code"], protocol.PARSE_ERROR)
        self.assertEqual(self.handlers.handle_rpc(b"[]")["error"]["code"], protocol.INVALID_REQUEST)
        corpo = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "report.spec", "params": []}).encode()
        self.assertEqual(self.handlers.handle_rpc(corpo)["error"]["code"], protocol.INVALID_PARAMS)


class TestRelatorio(Base):
    def test_spec_enviada(self):
        spec_nome, _ = self.enviar()
        resposta = self.rpc("report.spec", {"path": spec_nome})
        self.assertEqual(resposta["result"]["variants"], TOTAL)
        self.assertEqual(resposta["result"]["path"], spec_nome)

    def test_spec_fora_da_sessao_e_recusada(self):
        spec_fora, log_fora = gravar(self.pasta_fora)
        self.assertRecusa(self.rpc("report.spec", {"path": str(spec_fora)}))
        _, log_nome = self.enviar()
        self.assertRecusa(self.rpc("report.audit", {"spec_path": str(spec_fora), "log_path": log_nome}))
        spec_nome, _ = self.enviar()
        self.assertRecusa(self.rpc("report.audit", {"spec_path": spec_nome, "log_path": str(log_fora)}))

    def test_auditoria_igual_ao_servico_direto(self):
        resposta = self.auditar()["result"]
        spec_fora, log_fora = gravar(self.pasta_fora)
        direto = ReportService(documents_dir=self.pasta_fora)
        items, log_path = direto.read_log(str(log_fora))
        esperado = direto.audit(str(spec_fora), items, source="file", log_path=log_path)
        for chave in ("summary", "results", "log_stats", "extras", "alerts", "platform", "source"):
            self.assertEqual(resposta[chave], esperado[chave], chave)
        self.assertNotIn(str(self.session.root), json.dumps(resposta["spec"]))
        self.assertFalse(Path(resposta["log_path"]).is_absolute())

    def test_source_e_forcado_para_arquivo(self):
        self.assertRecusa(self.auditar(source="session"), "source")

    def test_plataforma_so_android_ou_ios(self):
        self.assertRecusa(self.auditar(platform="windows"), "android ou ios")
        self.assertRecusa(self.auditar(platform=["android"]), "android ou ios")
        self.assertEqual(self.auditar(platform="ios")["result"]["platform"], "ios")

    def test_log_sem_eventos(self):
        spec_nome = self.session.save_upload("spec", json.dumps(SPEC).encode())
        log_nome = self.session.save_upload("log", b"nada aqui")
        self.assertRecusa(self.rpc("report.audit", {"spec_path": spec_nome, "log_path": log_nome}), "não tem eventos")

    def test_export_ignora_o_directory_do_cliente(self):
        self.auditar()
        resposta = self.rpc("report.export", {"directory": str(self.pasta_fora / "saida")})["result"]
        self.assertFalse((self.pasta_fora / "saida").exists())
        self.assertEqual(sorted(f["kind"] for f in resposta["files"]), ["board", "html", "markdown", "tsv"])
        for arquivo in resposta["files"]:
            self.assertNotIn("path", arquivo)
            caminho = self.session.lookup(arquivo["id"])
            self.assertTrue(caminho.is_relative_to(self.session.root))
            self.assertEqual(caminho.stat().st_size, arquivo["bytes"])

    def test_export_sem_auditoria(self):
        self.assertRecusa(self.rpc("report.export"), "Rode a auditoria")


class TestPrintsNeutralizados(Base):
    """Spec de terceiros não pode embutir imagem do disco de quem roda o servidor."""

    def setUp(self):
        super().setUp()
        self.png = png_bytes()
        (self.pasta_fora / "segredo.png").write_bytes(self.png)
        self.spec = json.loads(json.dumps(SPEC))
        self.spec["prints_dir"] = str(self.pasta_fora)
        self.spec["cards"][0]["print"] = "segredo.png"
        self.spec["cards"][1]["print"] = str(self.pasta_fora / "segredo.png")
        self.marca = base64.b64encode(self.png).decode()

    def test_servico_direto_embutiria_o_print(self):
        # Controle: sem a neutralização, a mesma spec leva a imagem para o HTML.
        spec_path, log_path = gravar(self.pasta_fora, spec=self.spec)
        direto = ReportService(documents_dir=self.pasta_fora)
        items, _ = direto.read_log(str(log_path))
        direto.audit(str(spec_path), items, source="file")
        arquivos = direto.export(self.pasta_fora / "saida")["files"]
        html = next(Path(f["path"]) for f in arquivos if f["kind"] == "html").read_text(encoding="utf-8")
        self.assertIn(self.marca, html)

    def test_web_nao_embute_nem_aponta_o_print(self):
        spec_nome, log_nome = self.enviar(spec=self.spec)
        resumo = self.rpc("report.spec", {"path": spec_nome})["result"]
        self.assertIsNone(resumo["prints_dir"])
        auditoria = self.rpc("report.audit", {"spec_path": spec_nome, "log_path": log_nome})["result"]
        self.assertIsNone(auditoria["spec"]["prints_dir"])
        self.assertTrue(all(r["print_path"] is None for r in auditoria["results"]))
        for arquivo in self.rpc("report.export")["result"]["files"]:
            conteudo = self.session.lookup(arquivo["id"]).read_text(encoding="utf-8")
            self.assertNotIn(self.marca, conteudo, arquivo["kind"])
            self.assertNotIn("segredo.png", conteudo, arquivo["kind"])


class TestAnalytics(Base):
    def test_eventos_do_logcat(self):
        resposta = self.handlers.analytics(LOGCAT.encode())
        self.assertEqual(resposta["platform"], "android")
        self.assertEqual([e["event_name"] for e in resposta["events"]], ["screen_view", "add_to_cart"])
        self.assertEqual(resposta["events"][0]["time_str"], "10:00:00.000")
        self.assertEqual(resposta["events"][1]["params"]["items"], [{"item_id": "1", "item_name": "pedido"}])
        self.assertEqual(resposta["stats"]["uteis"], 2)
        linhas = resposta["tsv"].splitlines()
        self.assertEqual(linhas[0].split("\t")[3], "Nome do Evento")
        self.assertEqual(len(linhas), 3)
        self.assertTrue(all(len(linha.split("\t")) == 6 for linha in linhas))

    def test_logcat_utf16_do_powershell(self):
        resposta = self.handlers.analytics(b"\xff\xfe" + LOGCAT.encode("utf-16-le"))
        self.assertEqual(len(resposta["events"]), 2)

    def test_crlf_do_windows(self):
        resposta = self.handlers.analytics(LOGCAT.replace("\n", "\r\n").encode())
        self.assertEqual(len(resposta["events"]), 2)

    def test_tsv_sem_tab_nem_quebra_dentro_da_celula(self):
        log = [{"event_name": "x\ty", "platform": "android", "params": {"a": "1\n2"}, "time_str": "10:00:00.000"}]
        linhas = self.handlers.analytics(json.dumps(log).encode())["tsv"].splitlines()
        self.assertEqual(len(linhas), 2)
        self.assertEqual(len(linhas[1].split("\t")), 6)

    def test_ios_fica_de_fora_no_mvp(self):
        resposta = self.handlers.analytics(json.dumps(LOG).encode())
        self.assertTrue(all(e["platform"] == "android" for e in resposta["events"]))
