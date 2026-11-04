"""PERF-3: `perf.signals`, `perf.set_preference`, `perf.status` e `perf.profile`.

O perfil escolhido pelo governador chega ao que esta ligado no motor: cadencia
e tamanho do espelho, intervalo do vigia de aparelhos e teto dos historicos. E
o modo leve nunca perde captura: todo evento continua notificado.
"""

from __future__ import annotations

import time
from unittest.mock import MagicMock

from PIL import Image
from test_flow_execucao import FluxoBase

from mobaile.domain.models import AnalyticsEvent, NetworkEvent
from mobaile.services import perf


class PerfBase(FluxoBase):
    def setUp(self):
        super().setUp()
        self.server.adb.take_screenshot = lambda *_a, **_k: Image.new("RGB", (60, 120), "black")
        self.ok("session.select_device", {"platform": "android", "device_id": "emulator-5554"})


class TestContratoPerf(PerfBase):
    def test_status_inicial_e_completo_automatico(self):
        status = self.ok("perf.status")
        self.assertEqual((status["profile"], status["reason"], status["preference"]),
                         ("completo", "sinais_normais", "auto"))
        self.assertEqual(status["knobs"], perf.KNOBS["completo"].to_dict())
        self.assertEqual(status["signals"]["thermal"], "nominal")
        self.assertFalse(status["improving"])

    def test_sinal_quente_vai_ao_leve_e_notifica(self):
        status = self.ok("perf.signals", {"thermal": "serious", "low_power": False})
        self.assertEqual((status["profile"], status["reason"]), ("leve", "thermal_serious"))
        avisos = self.notificacoes("perf.profile")
        self.assertEqual(len(avisos), 1)
        self.assertEqual(avisos[0]["profile"], "leve")
        self.assertFalse(avisos[0]["knobs"]["glass"])

    def test_sinal_igual_nao_notifica_de_novo(self):
        self.ok("perf.signals", {"thermal": "serious"})
        self.ok("perf.signals", {"thermal": "serious"})
        self.assertEqual(len(self.notificacoes("perf.profile")), 1)

    def test_preferencia_manual_ganha_e_volta_ao_automatico(self):
        self.ok("perf.signals", {"thermal": "fair"})
        status = self.ok("perf.set_preference", {"preference": "completo"})
        self.assertEqual((status["profile"], status["reason"]), ("completo", "manual"))
        status = self.ok("perf.set_preference", {"preference": "auto"})
        self.assertEqual((status["profile"], status["reason"]), ("equilibrado", "thermal_fair"))

    def test_entrada_invalida_e_invalid_input(self):
        for metodo, params in [("perf.signals", {"thermal": "morno"}),
                               ("perf.signals", {"physical_memory_gb": "8"}),
                               ("perf.set_preference", {"preference": "turbo"}),
                               ("perf.set_preference", {})]:
            with self.subTest(metodo=metodo, params=params):
                resposta = self.call(metodo, params)
                self.assertEqual(resposta["error"]["data"]["code"], "invalid_input", resposta)

    def test_melhora_agenda_reavaliacao_e_cancela_no_encerramento(self):
        self.ok("perf.signals", {"thermal": "serious"})
        self.ok("perf.signals", {"thermal": "nominal"})
        self.assertTrue(self.ok("perf.status")["improving"])
        self.assertIsNotNone(self.server._perf_timer)
        self.server.shutdown()
        self.assertIsNone(self.server._perf_timer)


class TestKnobsAplicados(PerfBase):
    def test_espelho_sem_parametros_segue_o_perfil(self):
        self.ok("perf.set_preference", {"preference": "leve"})
        inicio = self.ok("stream.start")
        leve = perf.KNOBS["leve"]
        self.assertEqual((inicio["fps"], inicio["max_width"], inicio["quality"], inicio["idle_fps"], inicio["profile"]),
                         (leve.stream_fps, leve.stream_max_width, leve.stream_quality, leve.stream_idle_fps, "leve"))
        self.ok("stream.stop")

    def test_troca_de_perfil_com_o_espelho_ligado(self):
        self.ok("stream.start")
        self.ok("perf.set_preference", {"preference": "leve"})
        leve = perf.KNOBS["leve"]
        self.assertAlmostEqual(self.server._stream.frame_interval, 1 / leve.stream_fps)
        self.assertAlmostEqual(self.server._stream.idle_interval, 1 / leve.stream_idle_fps)
        self.assertEqual(self.server._stream_cfg["max_width"], leve.stream_max_width)
        self.assertEqual(self.server._stream_cfg["quality"], leve.stream_quality)
        self.ok("stream.stop")

    def test_o_que_o_chamador_fixou_o_perfil_nao_mexe(self):
        self.ok("stream.start", {"fps": 30, "max_width": 30})
        self.ok("perf.set_preference", {"preference": "leve"})
        self.assertAlmostEqual(self.server._stream.frame_interval, 1 / 30)
        self.assertEqual(self.server._stream_cfg["max_width"], 30)
        self.ok("stream.stop")

    def test_vigia_de_aparelhos_segue_o_perfil(self):
        self.server.adb.list_devices_typed = MagicMock(return_value=[])
        self.ok("devices.watch_start")
        self.assertEqual(self.server._watcher.poll_interval, perf.KNOBS["completo"].poll_interval)
        self.ok("perf.set_preference", {"preference": "leve"})
        self.assertEqual(self.server._watcher.poll_interval, perf.KNOBS["leve"].poll_interval)
        self.ok("devices.watch_stop")

    def test_perfil_nunca_mexe_no_teto_do_historico(self):
        """D-6 (R1): o historico ja capturado e o registro da auditoria."""
        tetos = (self.server.proxy._events.maxlen, self.server.analytics.events_history.maxlen)
        for perfil in ("leve", "equilibrado", "completo"):
            with self.subTest(perfil=perfil):
                self.ok("perf.set_preference", {"preference": perfil})
                self.assertEqual(
                    (self.server.proxy._events.maxlen, self.server.analytics.events_history.maxlen), tetos,
                )

    def test_leve_so_encolhe_o_corpo_das_capturas_novas(self):
        self.ok("perf.set_preference", {"preference": "leve"})
        self.assertEqual(self.server.proxy.body_capture_limit, perf.KNOBS["leve"].proxy_body_capture_kb * 1024)
        self.ok("perf.set_preference", {"preference": "completo"})
        self.assertEqual(self.server.proxy.body_capture_limit, 256 * 1024)


class TestLeveNaoPerdeCaptura(PerfBase):
    """F5: N eventos entram, N notificacoes saem, em qualquer perfil."""

    def evento_rede(self, ident: int) -> NetworkEvent:
        return NetworkEvent(
            id=ident, timestamp=time.time(), time_str="00:00:00.000", method="GET",
            url=f"https://exemplo.com/{ident}", host="exemplo.com", path=f"/{ident}", status_code=200,
            status_text="OK", request_headers={}, request_body="", response_headers={}, response_body="",
            duration_ms=1.0, protocol="HTTP/1.1", is_tunnel=False, error=None, request_bytes=0,
            response_bytes=0, body_truncated=False,
        )

    def evento_analytics(self, ident: int) -> AnalyticsEvent:
        return AnalyticsEvent(
            id=ident, timestamp=time.time(), time_str="00:00:00.000", tag="FA", event_name="tela",
            params={}, raw_log="", platform="android",
        )

    def test_todo_evento_e_notificado_e_guardado_no_leve(self):
        self.server._ensure_proxy_notify()
        for ident in range(600):
            self.server.proxy.emit_event(self.evento_rede(ident))
        for ident in range(2500):
            self.server.analytics._emit(self.evento_analytics(ident))
        # O Mac esquenta no meio da sessao: nada do que ja foi capturado sai.
        self.ok("perf.signals", {"thermal": "serious"})
        self.assertEqual(self.ok("perf.status")["profile"], "leve")
        self.assertEqual(len(self.notificacoes("proxy.event")), 600)
        self.assertEqual(len(self.notificacoes("analytics.event")), 2500)
        self.assertEqual(len(self.server.proxy.events_history), 600)
        self.assertEqual(len(self.server.analytics.events_history), 2500)

    def test_teto_estourado_aparece_no_status(self):
        from mobaile.adapters import analytics_logcat

        self.assertEqual(self.ok("perf.status")["history_full"], {"proxy": False, "analytics": False})
        for ident in range(analytics_logcat.MAX_HISTORY + 1):
            self.server.analytics._emit(self.evento_analytics(ident))
        self.assertEqual(self.ok("perf.status")["history_full"], {"proxy": False, "analytics": True})
        self.ok("analytics.clear")
        self.assertFalse(self.ok("perf.status")["history_full"]["analytics"])

    def test_fila_sem_leitor_nao_enche_no_motor_do_app(self):
        self.server._ensure_proxy_notify()
        self.server.proxy.emit_event(self.evento_rede(1))
        self.assertTrue(self.server.proxy.event_queue.empty())
        self.assertTrue(self.server.analytics.event_queue.empty())


class TestCorpoCapturado(PerfBase):
    def test_corpo_truncado_respeita_o_limite_do_perfil(self):
        from mobaile.adapters.proxy import _decode_body

        texto, cortado = _decode_body(b"a" * 100, {"Content-Type": "text/plain"}, limite=10)
        self.assertTrue(cortado)
        self.assertIn("100 bytes no total, 10 capturados", texto)


class TestPerfilDuranteOStart(PerfBase):
    def test_perfil_trocado_no_meio_do_stream_start_vale_para_o_espelho_novo(self):
        """R5: a histerese dispara entre ler os knobs e publicar o espelho."""
        original = self.server._start_mjpeg_if_available

        def troca_no_meio(*args, **kwargs):
            # Como o temporizador faria: governador muda e aplica, sem espelho.
            estado, mudou = self.server.perf.atualizar(preferencia="leve")
            self.server._perf_aplicar(estado, mudou)
            return original(*args, **kwargs)

        self.server._start_mjpeg_if_available = troca_no_meio
        self.ok("stream.start")
        leve = perf.KNOBS["leve"]
        self.assertAlmostEqual(self.server._stream.frame_interval, 1 / leve.stream_fps)
        self.assertEqual(self.server._stream_cfg["max_width"], leve.stream_max_width)
        self.ok("stream.stop")
