"""Trafego HTTPS de app Android em debug, lido do log do OkHttp no logcat.

As linhas seguem o formato real do `HttpLoggingInterceptor` (OkHttp 3 e 4) no
`logcat -v threadtime`. O que se prova: requisicao e resposta viram um
`NetworkEvent` so, threads intercaladas nao se misturam, outro log da mesma
thread nao vira header, e credencial sai redigida.
"""

from __future__ import annotations

import io
import itertools
import json
import unittest
from unittest.mock import patch

from mobaile.adapters.android_okhttp_log import LOGCAT_CHUNK, PENDING_TIMEOUT_S, OkHttpLogParser
from mobaile.domain.errors import DeviceNotFoundError
from mobaile.domain.models import Platform
from mobaile.rpc.server import EngineServer

TAG = "okhttp.OkHttpClient"


def linha(msg: str, tid: int = 5678, tag: str = TAG, pid: int = 1234, hora: str = "10:20:30.123") -> str:
    return f"10-09 {hora}  {pid}  {tid} I {tag}: {msg}\n"


def alimentar(parser: OkHttpLogParser, linhas: list[str], agora: float = 1000.0) -> list:
    eventos = []
    for texto in linhas:
        eventos += parser.feed(texto, now=agora)
    return eventos


def novo_parser() -> OkHttpLogParser:
    contador = itertools.count(1)
    return OkHttpLogParser(lambda: next(contador))


NIVEL_BODY = [
    linha("--> POST https://api.exemplo.com.br/v2/credito/simulacao?canal=app"),
    linha("Content-Type: application/json; charset=UTF-8"),
    linha("Content-Length: 15"),
    linha("Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.segredo"),
    linha(""),
    linha('{"valor": 5000}'),
    linha("--> END POST (15-byte body)"),
    linha("<-- 201 https://api.exemplo.com.br/v2/credito/simulacao?canal=app (182ms)"),
    linha("content-type: application/json"),
    linha(""),
    linha('{"parcelas": 12, "token": "abc123"}'),
    linha("<-- END HTTP (35-byte body)"),
]


class TestNiveisDoInterceptor(unittest.TestCase):
    def test_nivel_body_vira_um_evento_completo(self):
        (evento,) = alimentar(novo_parser(), NIVEL_BODY)
        self.assertEqual((evento.method, evento.status_code, evento.status_text), ("POST", 201, "Created"))
        self.assertEqual(evento.host, "api.exemplo.com.br")
        self.assertEqual(evento.path, "/v2/credito/simulacao?canal=app")
        self.assertEqual(evento.duration_ms, 182.0)
        self.assertEqual(evento.time_str, "10:20:30.123")
        self.assertEqual(evento.request_body, '{"valor": 5000}')
        self.assertIn('"parcelas": 12', evento.response_body)
        self.assertEqual(evento.response_headers["content-type"], "application/json")
        self.assertIsNone(evento.error)

    def test_credencial_sai_redigida(self):
        (evento,) = alimentar(novo_parser(), NIVEL_BODY)
        self.assertNotIn("segredo", evento.request_headers["Authorization"])
        self.assertNotIn("abc123", evento.response_body)

    def test_nivel_headers_sem_corpo(self):
        eventos = alimentar(novo_parser(), [
            linha("--> GET https://cdn.exemplo.com.br/img/a.png http/1.1"),
            linha("Accept: image/png"),
            linha("--> END GET"),
            linha("<-- 304 Not Modified https://cdn.exemplo.com.br/img/a.png (41ms)"),
            linha("etag: W/\"1\""),
            linha("<-- END HTTP"),
        ])
        (evento,) = eventos
        self.assertEqual((evento.method, evento.status_code, evento.status_text), ("GET", 304, "Not Modified"))
        self.assertEqual(evento.protocol, "HTTP/1.1")
        self.assertEqual(evento.request_headers, {"Accept": "image/png"})
        self.assertEqual(evento.response_body, "")

    def test_nivel_basic_so_com_as_linhas(self):
        eventos = alimentar(novo_parser(), [
            linha("--> POST https://api.exemplo.com.br/v1/login (39-byte body)"),
            linha("<-- 200 OK https://api.exemplo.com.br/v1/login (95ms, 120-byte body)"),
        ])
        (evento,) = eventos
        self.assertEqual((evento.method, evento.status_code, evento.path), ("POST", 200, "/v1/login"))
        self.assertEqual(evento.duration_ms, 95.0)

    def test_falha_de_rede_vira_evento_com_erro(self):
        (evento,) = alimentar(novo_parser(), [
            linha("--> GET https://api.fora.com.br/v1/status"),
            linha("--> END GET"),
            linha("<-- HTTP FAILED: java.net.UnknownHostException: Unable to resolve host \"api.fora.com.br\""),
        ])
        self.assertEqual(evento.status_code, 0)
        self.assertIn("UnknownHostException", evento.error)


class TestLogDeVerdade(unittest.TestCase):
    def test_threads_intercaladas_nao_se_misturam(self):
        eventos = alimentar(novo_parser(), [
            linha("--> GET https://api.exemplo.com.br/a", tid=1),
            linha("--> GET https://api.exemplo.com.br/b", tid=2),
            linha("X-Thread: um", tid=1),
            linha("X-Thread: dois", tid=2),
            linha("--> END GET", tid=2),
            linha("--> END GET", tid=1),
            linha("<-- 200 https://api.exemplo.com.br/b (10ms)", tid=2),
            linha("<-- END HTTP", tid=2),
            linha("<-- 500 https://api.exemplo.com.br/a (20ms)", tid=1),
            linha("<-- END HTTP", tid=1),
        ])
        por_path = {e.path: e for e in eventos}
        self.assertEqual(set(por_path), {"/a", "/b"})
        self.assertEqual(por_path["/a"].request_headers, {"X-Thread": "um"})
        self.assertEqual(por_path["/a"].status_code, 500)
        self.assertEqual(por_path["/b"].request_headers, {"X-Thread": "dois"})

    def test_outro_log_na_mesma_thread_nao_vira_header(self):
        (evento,) = alimentar(novo_parser(), [
            linha("--> GET https://api.exemplo.com.br/a"),
            linha("Accept: */*"),
            linha("Usuario: 123 clicou", tag="MainActivity"),
            linha("--> END GET"),
            linha("<-- 200 https://api.exemplo.com.br/a (5ms)"),
            linha("<-- END HTTP"),
        ])
        self.assertEqual(evento.request_headers, {"Accept": "*/*"})

    def test_linhas_que_nao_sao_do_logcat_sao_ignoradas(self):
        parser = novo_parser()
        self.assertEqual(parser.feed("--------- beginning of main\n"), [])
        self.assertEqual(parser.feed("lixo sem formato\n"), [])

    def test_corpo_grande_picado_pelo_logcat_volta_inteiro(self):
        corpo = json.dumps({"dados": "x" * (LOGCAT_CHUNK * 2)})
        pedacos = [corpo[i:i + LOGCAT_CHUNK] for i in range(0, len(corpo), LOGCAT_CHUNK)]
        (evento,) = alimentar(novo_parser(), [
            linha("--> GET https://api.exemplo.com.br/grande"),
            linha("--> END GET"),
            linha("<-- 200 https://api.exemplo.com.br/grande (7ms)"),
            linha(""),
            *[linha(p) for p in pedacos],
            linha("<-- END HTTP"),
        ])
        self.assertEqual(json.loads(evento.response_body)["dados"], "x" * (LOGCAT_CHUNK * 2))

    def test_requisicao_sem_resposta_expira(self):
        parser = novo_parser()
        self.assertEqual(alimentar(parser, [linha("--> GET https://api.exemplo.com.br/lenta"), linha("--> END GET")]), [])
        eventos = parser.feed(linha("qualquer coisa", tag="Outro"), now=1000.0 + PENDING_TIMEOUT_S + 1)
        (evento,) = eventos
        self.assertIn("Sem resposta", evento.error)

    def test_fim_da_leitura_fecha_o_que_estava_aberto(self):
        parser = novo_parser()
        alimentar(parser, [linha("--> GET https://api.exemplo.com.br/aberta")])
        (evento,) = parser.flush()
        self.assertIn("encerrada antes da resposta", evento.error)
        self.assertFalse(parser.has_open_calls())


class TestContratoDoNetlog(unittest.TestCase):
    """`netlog.start` escolhe a fonte pela plataforma da sessao."""

    def setUp(self):
        self.server = EngineServer(out=io.StringIO())
        self.addCleanup(self.server.shutdown)

    def test_android_sem_aparelho_e_recusado(self):
        self.server.platform = Platform.ANDROID
        self.server.device_id = None
        with self.assertRaises(DeviceNotFoundError):
            self.server.netlog_start({})

    def test_android_le_o_logcat_do_aparelho_da_sessao(self):
        self.server.platform = Platform.ANDROID
        self.server.device_id = "emulator-5554"
        with patch.object(self.server.android_netlog, "start", return_value=True) as start, \
             patch.object(self.server.android_netlog, "is_running", return_value=True):
            self.server.android_netlog.device_id = "emulator-5554"
            resposta = self.server.netlog_start({})
        start.assert_called_once_with("emulator-5554")
        self.assertEqual(resposta["source"], "okhttp_logcat")
        self.assertEqual(resposta["device_id"], "emulator-5554")
        self.assertTrue(resposta["running"])

    def test_stop_para_as_duas_fontes(self):
        with patch.object(self.server.android_netlog, "stop") as android, \
             patch.object(self.server.ios_netlog, "stop") as ios:
            self.assertEqual(self.server.netlog_stop({}), {"running": False})
        android.assert_called_once()
        ios.assert_called_once()


if __name__ == "__main__":
    unittest.main()
