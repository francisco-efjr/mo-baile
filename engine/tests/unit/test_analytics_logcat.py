import unittest

from mobaile.adapters.analytics_logcat import AnalyticsEvent, FirebaseAnalyticsListener


class TestAnalyticsListener(unittest.TestCase):
    def setUp(self):
        self.listener = FirebaseAnalyticsListener()

    def test_parse_logcat_line_case_a(self):
        raw = "09-03 22:06:24.732 V/FA-SVC  (11637): Logging event: origin=app,name=Consent_Device,params=Bundle[{opened_from_app_list=1, ga_event_origin(_o)=app, ga_screen_class(_sc)=MainActivity, ga_screen_id(_si)=-1985242701408864993, ga_screen(_sn)=consent_device}]"
        event = self.listener._parse_line(raw, platform="android")
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "Consent_Device")
        self.assertEqual(event.tag, "FA-SVC")
        self.assertEqual(event.time_str, "22:06:24.732")
        self.assertEqual(event.params.get("ga_screen"), "consent_device")
        self.assertEqual(event.params.get("opened_from_app_list"), "1")

    def test_parse_logcat_line_case_b(self):
        raw = "09-03 14:10:00.100 V/FA: Logging event: screen_view, Bundle[{ga_screen_name=app:home, flow_name=credito}]"
        event = self.listener._parse_line(raw, platform="android")
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "screen_view")
        self.assertEqual(event.tag, "FA")
        self.assertEqual(event.params.get("flow_name"), "credito")
        self.assertEqual(event.params.get("ga_screen_name"), "app:home")

    def test_parse_ios_log_line(self):
        raw = "2026-09-04 09:30:15.123456-0300 Default [FirebaseAnalytics] Logging event: origin=app, name=screen_view, params={ ga_screen = \"app:home\"; ga_screen_class = \"HomeController\"; flow_name = \"credito\"; }"
        event = self.listener._parse_line(raw, platform="ios")
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "screen_view")
        self.assertEqual(event.tag, "iOS (Firebase)")
        self.assertEqual(event.platform, "ios")
        self.assertEqual(event.params.get("ga_screen"), "app:home")
        self.assertEqual(event.params.get("ga_screen_class"), "HomeController")
        self.assertEqual(event.params.get("flow_name"), "credito")

    # Saida real de `log stream --style compact` para o log do Xcode com -FIRDebugEnabled.
    IOS_DEBUG_RECORD = (
        "2026-09-30 10:22:01.482 Df MeuApp[4321:1a2b3c] [com.google.utilities.logger:FirebaseAnalytics] "
        "10.22.1 - [FirebaseAnalytics][I-ACS023073] Debug mode is enabled. Marking event as debug and real-time. "
        "Event name, parameters: interaction_credito_pessoal, {\n"
        "    component = button;\n"
        "    detail = \"click:ir-para-o-saldo-da-conta\";\n"
        "    flow_name = credito-pessoal;\n"
        "    ga_debug (_dbg) = 1;\n"
        "    ga_event_origin (_o) = app;\n"
        "    ga_realtime (_r) = 1;\n"
        "    ga_screen (_sn) = app:creditos:pessoal:sucesso;\n"
        "    ga_screen_class (_sc) = LoginNavigationController;\n"
        "    ga_screen_id (_si) = -3365154693535786272;\n"
        "    insurance = 1;\n"
        "    screen_name = app:credito:pessoal:sucesso;\n"
        "}"
    )

    def test_parse_ios_registro_debug_mode(self):
        event = self.listener._parse_ios_record(self.IOS_DEBUG_RECORD)
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "interaction_credito_pessoal")
        self.assertEqual(event.platform, "ios")
        self.assertEqual(event.tag, "iOS (Firebase)")
        self.assertEqual(event.time_str, "10:22:01.482")
        self.assertEqual(event.params["component"], "button")
        self.assertEqual(event.params["detail"], "click:ir-para-o-saldo-da-conta")
        self.assertEqual(event.params["ga_debug"], "1")
        self.assertEqual(event.params["ga_screen_id"], "-3365154693535786272")
        self.assertEqual(event.params["screen_name"], "app:credito:pessoal:sucesso")
        self.assertEqual(len(event.params), 11)

    def test_parse_ios_nome_curto_e_parametro_aninhado(self):
        record = (
            "2026-09-30 10:22:02.000 Df MeuApp[1:2] 10.22.1 - [FirebaseAnalytics][I-ACS023072] "
            "Event logged. Event name, event params: purchase (_p), {\n"
            "    items = (\n"
            "        {\n"
            "            \"item_id\" = sku1;\n"
            "        }\n"
            "    );\n"
            "    value = 10;\n"
            "}"
        )
        event = self.listener._parse_ios_record(record)
        self.assertEqual(event.event_name, "purchase")
        self.assertEqual(event.params["value"], "10")
        self.assertIn("sku1", event.params["items"])

    def test_parse_ios_ignora_logs_que_nao_sao_evento(self):
        ignorados = [
            "2026-09-30 10:22:00.000 Df MeuApp[1:2] 10.22.1 - [FirebaseAnalytics][I-ACS023007] Analytics v.10.22.1 started",
            "2026-09-30 10:22:00.000 Df MeuApp[1:2] 10.22.1 - [FirebaseAnalytics][I-ACS023051] "
            "Logging event: origin, name, params: app, screen_view (_vs), {\n    ga_screen (_sn) = home;\n}",
        ]
        for record in ignorados:
            self.assertIsNone(self.listener._parse_ios_record(record))

    def test_ios_estagios_do_mesmo_evento_viram_um_so(self):
        logged = self.IOS_DEBUG_RECORD.replace(
            "[I-ACS023073] Debug mode is enabled. Marking event as debug and real-time. Event name, parameters:",
            "[I-ACS023072] Event logged. Event name, event params:",
        )
        self.assertIsNotNone(self.listener._parse_ios_record(self.IOS_DEBUG_RECORD))
        self.assertIsNone(self.listener._parse_ios_record(logged))
        # Segundo toque no mesmo botao: evento novo, tambem com dois estagios.
        self.assertIsNotNone(self.listener._parse_ios_record(self.IOS_DEBUG_RECORD))
        self.assertIsNone(self.listener._parse_ios_record(logged))

    def test_assembler_fecha_registro_sem_esperar_o_proximo(self):
        from mobaile.adapters.analytics_logcat import IOSLogRecordAssembler

        assembler = IOSLogRecordAssembler()
        linhas = [
            'Filtering the log data using "composedMessage CONTAINS \\"I-ACS\\""\n',
            "Timestamp               Ty Process[PID:TID]\n",
            *[linha + "\n" for linha in self.IOS_DEBUG_RECORD.split("\n")],
        ]
        saidas = [assembler.feed(linha) for linha in linhas]
        # So a ultima linha ("}") completa o registro.
        self.assertEqual([len(s) for s in saidas[:-1]], [0] * (len(linhas) - 1))
        self.assertEqual(saidas[-1], [self.IOS_DEBUG_RECORD])

        # Registro de uma linha so fecha na hora.
        simples = "2026-09-30 10:22:00.000 Df MeuApp[1:2] [I-ACS023007] Analytics started\n"
        self.assertEqual(assembler.feed(simples), [simples.rstrip("\n")])

    def test_stream_ios_de_ponta_a_ponta(self):
        import io
        from unittest.mock import MagicMock

        recebidos = []
        self.listener.add_event_callback(recebidos.append)
        self.listener.active_platform = "ios"
        self.listener.active_source = "ios_simulator"
        self.listener._is_running = True
        self.listener._proc = MagicMock()
        self.listener._proc.stdout = io.StringIO("Timestamp  Ty Process\n" + self.IOS_DEBUG_RECORD + "\n")

        self.listener._stream_reader()

        self.assertEqual(len(recebidos), 1)
        self.assertEqual(recebidos[0].event_name, "interaction_credito_pessoal")
        self.assertEqual(len(self.listener.events_history), 1)

    def test_start_ios_usa_log_stream_do_simulador(self):
        from unittest.mock import patch

        with patch("subprocess.Popen") as popen, patch("threading.Thread"):
            self.assertTrue(self.listener.start(platform="ios", device_id="ABCD-1234"))
        cmd = popen.call_args[0][0]
        self.assertEqual(cmd[:4], ["xcrun", "simctl", "spawn", "ABCD-1234"])
        self.assertIn("--level", cmd)
        self.assertEqual(cmd[cmd.index("--level") + 1], "debug")
        self.assertIn('eventMessage CONTAINS "I-ACS"', cmd)

    # ------------------------------------------------ iPhone fisico (por cabo)

    def _linha_do_filho(self, message: str) -> str:
        import json

        return json.dumps({"time": "2026-10-01 10:22:01.482", "process": "MeuApp", "pid": 321, "message": message})

    def test_iphone_fisico_linha_json_vira_evento(self):
        message = self.IOS_DEBUG_RECORD.split(" ", 5)[5]  # so a mensagem, sem cabecalho do log stream
        recebidos = []
        self.listener.add_event_callback(recebidos.append)
        self.listener._handle_device_line('{"status": "ready"}\n')
        self.listener._handle_device_line(self._linha_do_filho(message) + "\n")

        self.assertTrue(self.listener._device_ready.is_set())
        self.assertEqual(len(recebidos), 1)
        evento = recebidos[0]
        self.assertEqual(evento.event_name, "interaction_credito_pessoal")
        self.assertEqual(evento.time_str, "10:22:01.482")
        self.assertEqual(evento.params["flow_name"], "credito-pessoal")
        self.assertIn("MeuApp[321]", evento.raw_log)

    def _start_fisico_com_saida(self, saida: str):
        import io
        from unittest.mock import MagicMock, patch

        proc = MagicMock()
        proc.stdout = io.StringIO(saida)
        with patch("subprocess.Popen", return_value=proc) as popen, \
             patch("mobaile.adapters.ios_device_log.is_available", return_value=True):
            resultado = self.listener.start(platform="ios", device_id="00008020-001549180128402E", ios_physical=True)
        return resultado, popen

    def test_start_iphone_fisico_roda_o_filho_e_espera_ficar_pronto(self):
        resultado, popen = self._start_fisico_com_saida('{"status": "ready"}\n')
        self.assertTrue(resultado)
        cmd = popen.call_args[0][0]
        self.assertEqual(cmd[1:5], ["-m", "mobaile.adapters.ios_device_log", "stream", "00008020-001549180128402E"])
        self.assertIn("PYTHONPATH", popen.call_args[1]["env"])
        self.assertEqual(self.listener.active_source, "ios_device")
        self.listener.stop()

    def test_start_iphone_fisico_bloqueado_vira_erro_com_a_mensagem(self):
        from mobaile.domain.errors import AdapterError

        with self.assertRaises(AdapterError) as ctx:
            self._start_fisico_com_saida('{"error": "Desbloqueie o iPhone e tente de novo."}\n')
        self.assertIn("Desbloqueie", ctx.exception.message)
        self.assertFalse(self.listener.is_running())

    def test_start_iphone_fisico_filho_morre_sem_aviso_nao_espera_o_prazo(self):
        import time as _time

        from mobaile.domain.errors import AdapterError

        inicio = _time.monotonic()
        with self.assertRaises(AdapterError):
            self._start_fisico_com_saida("")
        self.assertLess(_time.monotonic() - inicio, 5)

    def test_start_iphone_fisico_sem_pymobiledevice3(self):
        from unittest.mock import patch

        from mobaile.domain.errors import AdapterError

        with patch("mobaile.adapters.ios_device_log.is_available", return_value=False), \
             self.assertRaises(AdapterError) as ctx:
            self.listener.start(platform="ios", device_id="00008020-001549180128402E", ios_physical=True)
        self.assertIn("pip install pymobiledevice3", ctx.exception.detail)

    def test_export_tsv_and_json(self):
        ev = AnalyticsEvent(
            id=1,
            timestamp=1788487587.0,
            time_str="22:06:24.732",
            tag="FA-SVC",
            event_name="Consent_Device",
            params={"ga_screen": "consent_device", "flow": "onboarding"},
            raw_log="sample log line",
        )
        self.listener.events_history.append(ev)

        tsv = self.listener.export_as_tsv()
        self.assertIn("Consent_Device", tsv)
        self.assertIn("consent_device", tsv)
        self.assertIn("\t", tsv)

        json_out = self.listener.export_as_json()
        self.assertIn('"event_name": "Consent_Device"', json_out)
        self.assertIn('"ga_screen": "consent_device"', json_out)


    def test_parse_logcat_firebase_analytics_tag(self):
        raw = "09-03 15:20:10.500 V/FirebaseAnalytics: Logging event: button_clicked, Bundle[{id=btn_submit}]"
        event = self.listener._parse_line(raw, platform="android")
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "button_clicked")
        self.assertEqual(event.tag, "FirebaseAnalytics")
        self.assertEqual(event.params.get("id"), "btn_submit")

    def test_parse_logcat_event_recorded(self):
        raw = "09-03 15:20:11.200 V/FA-SVC: Event recorded: Event{appId='com.test', name='purchase_complete', params=Bundle[{value=100}]}"
        event = self.listener._parse_line(raw, platform="android")
        self.assertIsNotNone(event)
        self.assertEqual(event.event_name, "purchase_complete")
        self.assertEqual(event.params.get("value"), "100")

    def test_setup_props_configura_debug_mode_e_buffer(self):
        from unittest.mock import patch
        with patch("subprocess.run") as mock_run:
            self.listener.adb.get_current_package = lambda _dev: "com.exemplo.app"
            res = self.listener.setup_props("dev123")
            self.assertTrue(res)

            executed_cmds = [" ".join(c[0][0]) for c in mock_run.call_args_list]
            self.assertTrue(any("debug.firebase.analytics.app com.exemplo.app" in cmd for cmd in executed_cmds))
            self.assertTrue(any("logcat -G 8M" in cmd for cmd in executed_cmds))
            self.assertTrue(any("log.tag.FirebaseAnalytics VERBOSE" in cmd for cmd in executed_cmds))


if __name__ == "__main__":
    unittest.main()
