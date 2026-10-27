"""Log do motor em arquivo (MEL-5).

O motor só escrevia no stderr, e o app aberto pelo Finder perdia tudo: uma
queda deixava apenas "o motor encerrou inesperadamente". Agora o log também
vai para `logs_dir()/engine.log`, só do dono, com rotação e com as URLs
redigidas. Toda escrita aqui cai na pasta de `MOBAILE_LOG_DIR` do teste, nunca
em `~/Library/Logs/Mo baile`.
"""

from __future__ import annotations

import faulthandler
import io
import json
import logging
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from mobaile.rpc import contract, server
from mobaile.rpc.server import EngineServer, configure_logging


class LogBase(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="mobaile-log-motor-")
        self.addCleanup(tmp.cleanup)
        self.pasta = Path(tmp.name) / "logs"
        env = patch.dict(os.environ, {"MOBAILE_LOG_DIR": str(self.pasta)})
        env.start()
        self.addCleanup(env.stop)
        # Garantia contra a rodada em que um teste escreveu no log de verdade:
        # o caminho tem de sair da variável, e ela tem de apontar para o tmp.
        self.assertTrue(os.environ["MOBAILE_LOG_DIR"].startswith(tmp.name))

        raiz = logging.getLogger()
        nivel = raiz.level
        faulthandler_ligado = faulthandler.is_enabled()

        def restaurar():
            server.shutdown_logging()
            raiz.setLevel(nivel)
            # O pytest liga o faulthandler no stderr; o teste o devolve.
            if faulthandler_ligado:
                faulthandler.enable(file=sys.__stderr__)

        self.addCleanup(restaurar)
        self.stderr = io.StringIO()

    def ler_log(self) -> str:
        for handler in logging.getLogger().handlers:
            handler.flush()
        return (self.pasta / "engine.log").read_text(encoding="utf-8")


class TestLogEmArquivo(LogBase):
    def test_arquivo_0600_pasta_0700_e_token_redigido(self):
        caminho = configure_logging(stream=self.stderr)

        self.assertEqual(caminho, str(self.pasta / "engine.log"))
        logging.getLogger("mobaile.teste").info(
            "Baixando https://api.exemplo.com/v1/sessao?token=SEGREDO123&pagina=2"
        )

        texto = self.ler_log()
        self.assertIn("api.exemplo.com/v1/sessao", texto)
        self.assertIn("pagina=2", texto)
        self.assertNotIn("SEGREDO123", texto)
        self.assertNotIn("SEGREDO123", self.stderr.getvalue(), "o stderr passa pelo mesmo filtro")
        self.assertEqual(stat.S_IMODE(os.stat(caminho).st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(os.stat(self.pasta).st_mode), 0o700)

    def test_argumentos_e_excecao_tambem_sao_redigidos(self):
        configure_logging(stream=self.stderr)
        log = logging.getLogger("mobaile.teste")

        log.warning("Falhou em %s", "https://qa:SENHA42@interno.exemplo.com/x")
        try:
            raise RuntimeError("HTTP 500 em https://h.exemplo.com/cb?access_token=TOKEN77")
        except RuntimeError:
            log.exception("Chamada falhou.")

        texto = self.ler_log()
        self.assertIn("interno.exemplo.com/x", texto)
        self.assertNotIn("SENHA42", texto)
        self.assertNotIn("TOKEN77", texto)
        self.assertIn("RuntimeError", texto, "o traceback continua no log")

    def test_argumento_que_nao_casa_com_o_formato_nao_vaza(self):
        configure_logging(stream=self.stderr)
        # Direto nos handlers do motor: o handler de captura do pytest, que
        # vem antes na raiz, levantaria o TypeError por conta própria.
        registro = logging.LogRecord(
            "mobaile.teste", logging.INFO, __file__, 1, "Dois %s %s", ("https://h.exemplo.com/?token=TOK3",), None
        )
        # O `handleError` do logging escreve no sys.stderr do processo.
        with patch("sys.stderr", io.StringIO()) as erro_do_logging:
            for handler in server._log_handlers:
                handler.handle(registro)
        self.assertNotIn("TOK3", self.ler_log())
        self.assertNotIn("TOK3", self.stderr.getvalue())
        self.assertNotIn("TOK3", erro_do_logging.getvalue())
        self.assertIn("h.exemplo.com", self.ler_log())

    def test_redige_mesmo_com_redacao_desligada_para_a_tela(self):
        # MOBAILE_REDACT=0 vale para a tela (D-E); o log é arquivo em disco.
        configure_logging(stream=self.stderr)
        with patch.dict(os.environ, {"MOBAILE_REDACT": "0"}):
            logging.getLogger("mobaile.teste").info("GET https://a.exemplo.com/?api_key=CHAVE9")
        self.assertNotIn("CHAVE9", self.ler_log())

    def test_rotacao_de_1_mb_com_3_copias_e_copia_nova_0600(self):
        caminho = configure_logging(stream=self.stderr)
        # O pytest pendura um FileHandler próprio na raiz; conta só o do motor.
        arquivo = [h for h in logging.getLogger().handlers if getattr(h, "baseFilename", None) == caminho]
        self.assertEqual(len(arquivo), 1)
        handler = arquivo[0]
        self.assertEqual(handler.maxBytes, 1024 * 1024)
        self.assertEqual(handler.backupCount, 3)

        handler.doRollover()
        logging.getLogger("mobaile.teste").info("depois da rotacao")

        self.assertTrue((self.pasta / "engine.log.1").exists())
        self.assertEqual(stat.S_IMODE(os.stat(self.pasta / "engine.log").st_mode), 0o600)
        self.assertIn("depois da rotacao", self.ler_log())

    def test_reconfigurar_nao_duplica_handlers(self):
        configure_logging(stream=self.stderr)
        configure_logging(stream=self.stderr)
        logging.getLogger("mobaile.teste").info("uma vez so")
        self.assertEqual(self.ler_log().count("uma vez so"), 1)

    def test_faulthandler_escreve_num_arquivo_privado_que_fica_aberto(self):
        configure_logging(stream=self.stderr)
        self.assertTrue(faulthandler.is_enabled())
        despejo = self.pasta / "engine-faults.log"
        self.assertEqual(stat.S_IMODE(os.stat(despejo).st_mode), 0o600)
        # O descritor entregue ao faulthandler segue válido depois da subida.
        os.fstat(server._fault_file.fileno())
        self.assertFalse(server._fault_file.closed)

    def test_sem_pasta_de_logs_o_motor_sobe_so_com_stderr(self):
        self.pasta.parent.mkdir(parents=True, exist_ok=True)
        self.pasta.write_text("arquivo no lugar da pasta", encoding="utf-8")

        caminho = configure_logging(stream=self.stderr)

        self.assertIsNone(caminho)
        logging.getLogger("mobaile.teste").info("ainda no stderr")
        self.assertIn("ainda no stderr", self.stderr.getvalue())


class TestCaminhoNoContrato(unittest.TestCase):
    def chamar(self, srv: EngineServer, method: str, params=None):
        resposta = srv.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )
        return resposta["result"]

    def test_hello_e_info_trazem_log_path(self):
        srv = EngineServer(out=io.StringIO(), log_path="/tmp/x/engine.log")
        hello = self.chamar(srv, "engine.hello", {"protocol_version": contract.PROTOCOL_VERSION})
        info = self.chamar(srv, "engine.info")
        self.assertEqual(hello["log_path"], "/tmp/x/engine.log")
        self.assertEqual(info["log_path"], "/tmp/x/engine.log")

    def test_sem_log_em_disco_o_campo_vem_nulo(self):
        srv = EngineServer(out=io.StringIO())
        hello = self.chamar(srv, "engine.hello", {"protocol_version": contract.PROTOCOL_VERSION})
        self.assertIn("log_path", hello)
        self.assertIsNone(hello["log_path"])
        self.assertIsNone(self.chamar(srv, "engine.info")["log_path"])


if __name__ == "__main__":
    unittest.main()
