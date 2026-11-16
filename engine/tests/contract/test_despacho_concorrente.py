"""Despacho concorrente, cancelamento e encerramento.

Antes, `serve_forever` executava cada metodo na thread que le o stdin: um
`wda.start` de minutos congelava toque, parada de espelho e ate o
`engine.shutdown`. Estes testes sobem o laco de verdade (`serve_forever`) com
stdin e stdout em memoria e trocam o metodo lento por um falso que so dorme,
sem gancho de teste no codigo de producao.

Os criterios vem do estudo de arquitetura (licao 1): p95 abaixo de 50 ms na
fila rapida com a de ambiente ocupada, cancelamento que interrompe
`hierarchy.dump`, e `engine.shutdown` respondendo em menos de 2 s.
"""

from __future__ import annotations

import io
import json
import os
import pathlib
import queue
import signal
import subprocess
import sys
import threading
import time
import unittest
from collections import Counter
from unittest.mock import MagicMock, patch

from PIL import Image

from mobaile.rpc import protocol
from mobaile.rpc.server import LANE_DRAIN_TIMEOUT_S, EngineServer

FONTE = pathlib.Path(__file__).resolve().parents[2] / "src"

XML = (
    '<hierarchy rotation="0">'
    '<node class="android.widget.Button" text="Continuar" clickable="true"'
    ' bounds="[10,20][110,70]" resource-id="br.app:id/btn_ok" package="br.app"/>'
    "</hierarchy>"
)


class _Entrada:
    """stdin em memoria: cada `enviar` vira uma linha; `fechar` e o EOF."""

    def __init__(self) -> None:
        self._linhas: queue.Queue[str | None] = queue.Queue()

    def __iter__(self):
        while True:
            linha = self._linhas.get()
            if linha is None:
                return
            yield linha

    def enviar(self, mensagem: dict) -> None:
        self._linhas.put(json.dumps(mensagem) + "\n")

    def fechar(self) -> None:
        self._linhas.put(None)


class _Saida:
    """stdout em memoria que anota o instante de chegada de cada linha."""

    def __init__(self) -> None:
        self._cond = threading.Condition()
        self.mensagens: list[tuple[float, dict]] = []

    def write(self, texto: str) -> None:
        with self._cond:
            for linha in texto.splitlines():
                if linha.strip():
                    self.mensagens.append((time.monotonic(), json.loads(linha)))
            self._cond.notify_all()

    def flush(self) -> None:
        pass

    def esperar(self, predicado, timeout: float):
        with self._cond:
            limite = time.monotonic() + timeout
            while True:
                for instante, mensagem in self.mensagens:
                    if predicado(mensagem):
                        return instante, mensagem
                restante = limite - time.monotonic()
                if restante <= 0:
                    return None
                self._cond.wait(restante)


class MotorEmMemoria:
    def __init__(self) -> None:
        self.entrada = _Entrada()
        self.saida = _Saida()
        self.server = EngineServer(out=self.saida)
        self.thread = threading.Thread(target=self.server.serve_forever, args=(self.entrada,), daemon=True)
        self.thread.start()
        self._id = 0

    def enviar(self, metodo: str, params: dict | None = None) -> int:
        self._id += 1
        self.entrada.enviar({"jsonrpc": "2.0", "id": self._id, "method": metodo, "params": params or {}})
        return self._id

    def cancelar(self, request_id: int) -> None:
        self.entrada.enviar({"jsonrpc": "2.0", "method": "$/cancelRequest", "params": {"id": request_id}})

    def resposta(self, request_id: int, timeout: float = 5.0) -> tuple[float, dict]:
        achada = self.saida.esperar(lambda m: m.get("id") == request_id, timeout)
        if achada is None:
            raise AssertionError(f"pedido {request_id} nao respondeu em {timeout}s")
        return achada

    def chamar(self, metodo: str, params: dict | None = None, timeout: float = 5.0) -> tuple[float, dict]:
        """Envia e espera. Devolve a latencia em segundos e a resposta."""
        inicio = time.monotonic()
        instante, resposta = self.resposta(self.enviar(metodo, params), timeout)
        return instante - inicio, resposta

    def respondidos(self) -> Counter:
        return Counter(m["id"] for _, m in self.saida.mensagens if "id" in m)

    def encerrar(self) -> None:
        self.entrada.fechar()
        self.thread.join(LANE_DRAIN_TIMEOUT_S + 5)


def p95(amostras: list[float]) -> float:
    ordenadas = sorted(amostras)
    return ordenadas[max(0, round(0.95 * len(ordenadas)) - 1)]


class DespachoBase(unittest.TestCase):
    def setUp(self):
        self.motor = MotorEmMemoria()
        self.server = self.motor.server
        # Solto no fim de todo teste, para nenhuma fila ficar presa entre eles.
        self.liberar = threading.Event()
        self.addCleanup(self.server.shutdown)
        self.addCleanup(self.motor.encerrar)
        self.addCleanup(self.liberar.set)

    def tearDown(self):
        repetidos = {rid: n for rid, n in self.motor.respondidos().items() if n > 1}
        self.assertEqual(repetidos, {}, "id com mais de uma resposta")

    def metodo_lento(self, nome: str, segundos: float = 3.0, resultado=None) -> threading.Event:
        """Troca `nome` por um metodo que segura a fila ate `liberar` ou `segundos`."""
        comecou = threading.Event()

        def lento(_params):
            comecou.set()
            self.liberar.wait(segundos)
            return resultado if resultado is not None else {"lento": True}

        self.server.methods[nome] = lento
        return comecou

    def selecionar_android(self):
        _, resposta = self.motor.chamar(
            "session.select_device", {"platform": "android", "device_id": "emulator-5554"}
        )
        self.assertIn("result", resposta)


class TestFilasIndependentes(DespachoBase):
    def test_fila_rapida_responde_com_wda_start_em_andamento(self):
        self.selecionar_android()
        comecou = self.metodo_lento("wda.start", 3.0)
        wda = self.motor.enviar("wda.start")
        self.assertTrue(comecou.wait(1), "wda.start falso nao comecou")

        latencias = []
        with patch.object(self.server.adb, "tap", return_value=True):
            for _ in range(20):
                latencia, resposta = self.motor.chamar("codegen.steps")
                self.assertIn("result", resposta)
                latencias.append(latencia)
                latencia, resposta = self.motor.chamar("input.tap", {"x": 10, "y": 20})
                self.assertEqual(resposta["result"], {"ok": True})
                latencias.append(latencia)

        self.assertIsNone(self.motor.saida.esperar(lambda m: m.get("id") == wda, 0),
                          "wda.start deveria continuar em andamento")
        self.assertLess(p95(latencias), 0.050, f"p95 de {p95(latencias) * 1000:.1f} ms")
        self.liberar.set()
        self.assertIn("result", self.motor.resposta(wda)[1])

    def test_ordem_de_chegada_e_ordem_de_execucao_dentro_da_fila(self):
        executados = []

        def registra(params):
            # Duracoes diferentes: se houvesse paralelismo dentro da fila, a
            # ordem de termino embaralharia.
            time.sleep(0.004 * (params["n"] % 3))
            executados.append(params["n"])
            return {"n": params["n"]}

        self.server.methods["screen.size"] = registra
        ids = [self.motor.enviar("screen.size", {"n": n}) for n in range(12)]
        chegadas = [self.motor.resposta(rid)[0] for rid in ids]

        self.assertEqual(executados, list(range(12)))
        self.assertEqual(chegadas, sorted(chegadas), "respostas da mesma fila chegaram fora de ordem")

    def test_notificacao_do_metodo_chega_antes_da_resposta(self):
        ligado = [{"udid": "B", "name": "iPhone 16", "state": "Booted", "runtime": "iOS 18.0", "booted": True}]
        with patch.object(self.server.ios, "list_all_simulators", return_value=ligado), \
             patch.object(self.server.appium, "ensure_wda", return_value=(True, "no ar")):
            rid = self.motor.enviar("wda.start", {"progress_token": "wda-1"})
            self.motor.resposta(rid)

        ordem = [m.get("method") or m.get("id") for _, m in self.motor.saida.mensagens]
        self.assertIn("$/progress", ordem)
        self.assertLess(max(i for i, x in enumerate(ordem) if x == "$/progress"), ordem.index(rid))


class TestEncerramento(DespachoBase):
    def test_shutdown_responde_rapido_com_a_fila_de_ambiente_ocupada(self):
        comecou = self.metodo_lento("wda.start", 30.0)
        self.motor.enviar("wda.start")
        self.assertTrue(comecou.wait(1))

        with patch.object(self.server.proxy, "stop", wraps=self.server.proxy.stop) as parar_proxy:
            latencia, resposta = self.motor.chamar("engine.shutdown")
            self.assertEqual(resposta["result"], {"stopped": True})
            self.assertLess(latencia, 2.0)

            # O laco termina sozinho, sem esperar o wda.start preso, e o
            # desmonte roda uma vez so mesmo chamado de novo.
            self.motor.thread.join(LANE_DRAIN_TIMEOUT_S + 3)
            self.assertFalse(self.motor.thread.is_alive(), "serve_forever nao terminou")
            self.server.shutdown()
            self.assertEqual(parar_proxy.call_count, 1)

    def test_fim_do_stdin_encerra_sem_pendurar_na_fila_presa(self):
        comecou = self.metodo_lento("wda.start", 30.0)
        self.motor.enviar("wda.start")
        self.assertTrue(comecou.wait(1))

        inicio = time.monotonic()
        self.motor.entrada.fechar()
        self.motor.thread.join(LANE_DRAIN_TIMEOUT_S + 3)
        self.assertFalse(self.motor.thread.is_alive())
        self.assertLess(time.monotonic() - inicio, LANE_DRAIN_TIMEOUT_S + 2)

    def test_fim_do_stdin_ainda_responde_o_que_estava_na_fila(self):
        rid = self.motor.enviar("codegen.steps")
        self.motor.entrada.fechar()
        self.motor.thread.join(LANE_DRAIN_TIMEOUT_S + 3)
        self.assertIn("result", self.motor.resposta(rid, timeout=0)[1])


class TestCancelamento(DespachoBase):
    def assertCancelado(self, resposta):
        self.assertEqual(resposta["error"]["code"], protocol.REQUEST_CANCELLED)
        self.assertEqual(resposta["error"]["data"]["code"], "request_cancelled")

    def test_pedido_na_fila_sai_dela_e_nunca_roda(self):
        comecou = self.metodo_lento("wda.start", 5.0)
        boot = MagicMock(return_value={"booted": True})
        self.server.methods["simulators.boot"] = boot
        wda = self.motor.enviar("wda.start")
        self.assertTrue(comecou.wait(1))
        na_fila = self.motor.enviar("simulators.boot")

        inicio = time.monotonic()
        self.motor.cancelar(na_fila)
        instante, resposta = self.motor.resposta(na_fila, timeout=1)
        self.assertCancelado(resposta)
        self.assertLess(instante - inicio, 0.5)

        self.liberar.set()
        self.assertIn("result", self.motor.resposta(wda)[1])
        # Um pedido depois do cancelado prova que a fila passou por ele.
        self.server.methods["simulators.list"] = MagicMock(return_value={"simulators": []})
        self.assertIn("result", self.motor.chamar("simulators.list")[1])
        boot.assert_not_called()

    def test_pedido_em_execucao_recebe_erro_na_hora_e_o_resultado_e_descartado(self):
        comecou = self.metodo_lento("wda.start", 5.0, resultado={"tarde": True})
        wda = self.motor.enviar("wda.start")
        self.assertTrue(comecou.wait(1))

        self.motor.cancelar(wda)
        self.assertCancelado(self.motor.resposta(wda, timeout=1)[1])

        self.liberar.set()
        self.server.methods["wda.status"] = MagicMock(return_value={"wda_running": False})
        self.assertIn("result", self.motor.chamar("wda.status")[1])
        self.assertEqual(self.motor.respondidos()[wda], 1, "o resultado tardio saiu como segunda resposta")

    def test_id_desconhecido_ou_ja_respondido_e_ignorado(self):
        _, resposta = self.motor.chamar("codegen.steps")
        self.motor.cancelar(resposta["id"])
        self.motor.cancelar(999)
        self.assertIn("result", self.motor.chamar("codegen.steps")[1])
        self.assertFalse([m for _, m in self.motor.saida.mensagens if "error" in m])

    def test_wda_start_desiste_antes_de_chamar_o_appium(self):
        listando = threading.Event()

        def lista_devagar():
            listando.set()
            self.liberar.wait(5)
            return [{"udid": "B", "name": "iPhone", "state": "Booted", "runtime": "iOS", "booted": True}]

        with patch.object(self.server.ios, "list_all_simulators", side_effect=lista_devagar), \
             patch.object(self.server.appium, "ensure_wda", return_value=(True, "ok")) as ensure:
            wda = self.motor.enviar("wda.start")
            self.assertTrue(listando.wait(1))
            self.motor.cancelar(wda)
            self.assertCancelado(self.motor.resposta(wda, timeout=1)[1])
            self.liberar.set()
            self.server.methods["wda.status"] = MagicMock(return_value={})
            self.motor.chamar("wda.status")
        ensure.assert_not_called()

    def test_cancelamento_interrompe_hierarchy_dump_antes_do_appium(self):
        self.selecionar_android()
        dumpando = threading.Event()

        def dump_vazio(_device):
            dumpando.set()
            self.liberar.wait(5)
            return None

        with patch.object(self.server.adb, "get_ui_hierarchy", side_effect=dump_vazio), \
             patch.object(self.server.appium, "ensure_android_session", return_value=(True, "ok")) as sessao:
            dump = self.motor.enviar("hierarchy.dump", {"force": True})
            self.assertTrue(dumpando.wait(1))
            self.motor.cancelar(dump)
            self.assertCancelado(self.motor.resposta(dump, timeout=1)[1])
            self.liberar.set()
            self.server.methods["screen.size"] = MagicMock(return_value={})
            self.motor.chamar("screen.size")
        sessao.assert_not_called()

    def test_simulators_boot_automatico_desiste_antes_de_ligar(self):
        listando = threading.Event()

        def lista_devagar():
            listando.set()
            self.liberar.wait(5)
            return [{"udid": "A", "name": "iPhone", "state": "Shutdown", "runtime": "iOS", "booted": False}]

        with patch.object(self.server.ios, "list_all_simulators", side_effect=lista_devagar), \
             patch.object(self.server.ios, "boot_simulator", return_value=(True, "ok")) as boot:
            rid = self.motor.enviar("simulators.boot")
            self.assertTrue(listando.wait(1))
            self.motor.cancelar(rid)
            self.assertCancelado(self.motor.resposta(rid, timeout=1)[1])
            self.liberar.set()
            self.server.methods["simulators.list"] = MagicMock(return_value={})
            self.motor.chamar("simulators.list")
        boot.assert_not_called()


class TestEpocaDaSessao(DespachoBase):
    def test_dump_que_termina_depois_da_troca_nao_sobrescreve_a_arvore(self):
        self.selecionar_android()
        dumpando = threading.Event()

        def dump_lento(_device):
            dumpando.set()
            self.liberar.wait(5)
            return XML

        with patch.object(self.server.adb, "get_ui_hierarchy", side_effect=dump_lento):
            dump = self.motor.enviar("hierarchy.dump", {"force": True})
            self.assertTrue(dumpando.wait(1))

            # A troca roda na fila rapida enquanto o dump segura a de captura.
            _, troca = self.motor.chamar(
                "session.select_device", {"platform": "android", "device_id": "emulator-5556"}
            )
            self.assertIn("result", troca)
            self.liberar.set()
            self.assertEqual(self.motor.resposta(dump)[1]["result"]["count"], 1)
            self.assertIsNone(self.server.current_xml, "arvore do aparelho anterior virou estado do novo")

            # Controle: sem troca no meio, a mesma leitura vira estado.
            _, outro = self.motor.chamar("hierarchy.dump", {"force": True})
            self.assertIn("result", outro)
        self.assertEqual(self.server.current_xml, XML)

    def test_troca_de_aparelho_pelo_vigia_tambem_avanca_a_epoca(self):
        self.selecionar_android()
        epoca = self.server._session_epoch
        with patch.object(self.server.adb, "list_devices", return_value=[("emulator-5556", "device")]):
            self.motor.chamar("devices.watch_start", {"poll_interval": 0.02})
            limite = time.monotonic() + 2
            while self.server.device_id != "emulator-5556" and time.monotonic() < limite:
                time.sleep(0.02)
            self.motor.chamar("devices.watch_stop")
        self.assertEqual(self.server.device_id, "emulator-5556")
        self.assertGreater(self.server._session_epoch, epoca)


class TestOrigemDoQuadro(DespachoBase):
    def test_captura_diz_de_qual_aparelho_veio(self):
        self.selecionar_android()
        with patch.object(self.server.adb, "take_screenshot", return_value=Image.new("RGB", (40, 80))):
            _, resposta = self.motor.chamar("screen.capture")
        self.assertEqual(resposta["result"]["device_id"], "emulator-5554")

    def test_quadro_capturado_antes_da_troca_nao_e_emitido(self):
        self.selecionar_android()
        capturando = threading.Event()
        cores = iter(["red", "green", "blue", "white", "black"] * 50)

        def captura(device):
            if device == "emulator-5554":
                capturando.set()
                self.liberar.wait(5)
            return Image.new("RGB", (40, 80), next(cores))

        with patch.object(self.server.adb, "take_screenshot", side_effect=captura):
            self.motor.chamar("stream.start", {"fps": 30})
            self.assertTrue(capturando.wait(1))
            # O espelho esta no meio de uma captura do aparelho antigo.
            self.motor.chamar("session.select_device", {"platform": "android", "device_id": "emulator-5556"})
            self.liberar.set()
            chegou = self.motor.saida.esperar(lambda m: m.get("method") == "stream.frame", 2)
            self.motor.chamar("stream.stop")

        self.assertIsNotNone(chegou, "o espelho parou de emitir depois da troca")
        quadros = [m["params"] for _, m in self.motor.saida.mensagens if m.get("method") == "stream.frame"]
        self.assertEqual({q["device_id"] for q in quadros}, {"emulator-5556"})


class TestVigiaEPlataforma(unittest.TestCase):
    def test_serial_android_nao_entra_em_sessao_ios(self):
        """Repro do revisor: `adb devices` em voo quando a sessao vira iOS."""
        server = EngineServer(out=io.StringIO())
        self.addCleanup(server.shutdown)
        listando, soltar = threading.Event(), threading.Event()
        simulador = "11111111-2222-3333-4444-555555555555"

        def lista_android():
            listando.set()
            soltar.wait(5)
            return [("R58M123ABC", "device")]

        def chamar(metodo, params):
            return server.handle_message(json.dumps({"jsonrpc": "2.0", "id": 1, "method": metodo, "params": params}))

        with patch.object(server.adb, "list_devices", side_effect=lista_android), \
             patch.object(server.ios, "list_booted_simulators", return_value=[(simulador, "iPhone")]):
            chamar("session.select_device", {"platform": "android"})
            chamar("devices.watch_start", {"poll_interval": 30})
            self.assertTrue(listando.wait(2))
            chamar("session.select_device", {"platform": "ios", "device_id": simulador})
            soltar.set()
            time.sleep(0.2)
            chamar("devices.watch_stop", {})

        self.assertEqual((server.platform.value, server.device_id), ("ios", simulador))


class TestDesmonteContraOrfaos(DespachoBase):
    def test_passive_start_que_termina_depois_do_desmonte_desliga_o_ouvinte(self):
        self.selecionar_android()
        ouvinte = MagicMock()
        with patch("mobaile.adapters.input_events.AndroidPassiveListener", return_value=ouvinte), \
             patch.object(self.server.adb, "get_screen_size", return_value=(1080, 2400)), \
             patch.object(self.server.adb, "get_ui_hierarchy", return_value=XML):
            # O desmonte roda enquanto o `start` ainda nao gravou o ouvinte.
            ouvinte.start.side_effect = self.server.shutdown
            erro = self.server.handle_message(json.dumps(
                {"jsonrpc": "2.0", "id": 99, "method": "passive.start", "params": {}}))
        self.assertIn("encerrando", erro["error"]["message"])
        ouvinte.stop.assert_called_once()
        self.assertIsNone(self.server._passive)

    def test_pedido_que_sai_da_fila_depois_do_desmonte_nao_roda(self):
        comecou = self.metodo_lento("screen.size", 30.0)
        tardio = MagicMock(return_value={})
        self.server.methods["hierarchy.dump"] = tardio
        self.motor.enviar("screen.size")
        self.assertTrue(comecou.wait(1))
        self.motor.enviar("hierarchy.dump")
        self.motor.entrada.fechar()
        self.motor.thread.join(LANE_DRAIN_TIMEOUT_S + 3)
        # O dreno desistiu da fila presa e o desmonte ja rodou; soltar agora
        # deixa a fila andar, e o pedido seguinte nao pode comecar.
        self.liberar.set()
        time.sleep(0.1)
        tardio.assert_not_called()


# Motor de verdade com as bordas do desmonte trocadas por versoes que so
# registram no stderr. O `adb reverse` falso e lento como o real (um `adb shell
# settings` leva dezenas de milissegundos), para o sinal ter onde cair no meio.
DESMONTE_OBSERVAVEL = """
import sys, time
from mobaile.adapters.adb import ADBBridge
from mobaile.adapters.analytics_logcat import FirebaseAnalyticsListener
from mobaile.adapters.appium import AppiumBridge
from mobaile.adapters.proxy import MobileNetworkProxy
from mobaile.adapters.scrcpy import ScrcpyManager

def registra(etapa):
    sys.stderr.write("DESMONTE " + etapa + "\\n")
    sys.stderr.flush()

def reverse_lento(self, device_id, port=8082):
    for passo in range(6):
        registra(f"reverse {passo}")
        time.sleep(0.08)
    return True

ADBBridge.teardown_reverse_proxy = reverse_lento
MobileNetworkProxy.is_running = lambda self: True
MobileNetworkProxy.stop = lambda self: registra("proxy")
FirebaseAnalyticsListener.stop = lambda self: registra("analytics")
ScrcpyManager.stop_mirror = lambda self: registra("scrcpy")
AppiumBridge.stop_server = lambda self: registra("appium")

from mobaile.rpc.server import serve
serve()
"""
ETAPAS_DO_DESMONTE = [*(f"reverse {passo}" for passo in range(6)), "proxy", "analytics", "scrcpy", "appium"]


class TestProcessoDeVerdade(unittest.TestCase):
    """O mesmo transporte do front: `python -m mobaile.rpc` com stdio de verdade."""

    def _subir(self, stderr=subprocess.DEVNULL) -> subprocess.Popen:
        env = dict(os.environ, PYTHONPATH=str(FONTE), PYTHONUNBUFFERED="1")
        proc = subprocess.Popen(
            [sys.executable, "-m", "mobaile.rpc"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
            text=True, bufsize=1, env=env,
        )
        self.addCleanup(lambda: proc.poll() is None and proc.kill())
        return proc

    @staticmethod
    def _pedir(proc, request_id, metodo, params=None) -> dict:
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": request_id, "method": metodo,
                                     "params": params or {}}) + "\n")
        proc.stdin.flush()
        while True:
            mensagem = json.loads(proc.stdout.readline())
            if mensagem.get("id") == request_id:
                return mensagem

    def test_hello_e_shutdown_encerram_o_processo(self):
        proc = self._subir()
        hello = self._pedir(proc, 1, "engine.hello", {"protocol_version": 2, "client": "teste"})
        self.assertEqual(hello["result"]["protocol_version"], 2)

        inicio = time.monotonic()
        self.assertEqual(self._pedir(proc, 2, "engine.shutdown")["result"], {"stopped": True})
        self.assertLess(time.monotonic() - inicio, 2.0)
        self.assertEqual(proc.wait(timeout=LANE_DRAIN_TIMEOUT_S + 5), 0)
        proc.stdin.close()
        proc.stdout.close()

    def test_sigterm_logo_apos_o_shutdown_nao_interrompe_o_desmonte(self):
        """A sequencia exata do `EngineClient.stop()` do front.

        `engine.shutdown`, stdin fechado e SIGTERM sem esperar resposta, com
        o sinal chegando junto (0 ms) ou ja no meio do desmonte (50 ms). O
        desmonte e lento e observavel de proposito: o `adb reverse` falso leva
        meio segundo em seis etapas. Um segundo SIGTERM no meio dele tambem nao
        pode interromper nada.
        """
        for atraso in (0.0, 0.05):
            with self.subTest(atraso_ms=atraso * 1000):
                proc = subprocess.Popen(
                    [sys.executable, "-c", DESMONTE_OBSERVAVEL],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, bufsize=1, env=dict(os.environ, PYTHONPATH=str(FONTE), PYTHONUNBUFFERED="1"),
                )
                self.addCleanup(lambda proc=proc: proc.poll() is None and proc.kill())
                selecao = self._pedir(proc, 1, "session.select_device",
                                      {"platform": "android", "device_id": "emulator-5554"})
                self.assertIn("result", selecao)

                proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 2, "method": "engine.shutdown"}) + "\n")
                proc.stdin.flush()
                proc.stdin.close()
                if atraso:
                    time.sleep(atraso)
                proc.send_signal(signal.SIGTERM)
                time.sleep(0.2)
                if proc.poll() is None:
                    proc.send_signal(signal.SIGTERM)

                # stdin ja foi fechado, entao `communicate` nao serve aqui.
                codigo = proc.wait(timeout=LANE_DRAIN_TIMEOUT_S + 5)
                log = proc.stderr.read()
                proc.stdout.close()
                proc.stderr.close()
                self.assertEqual(codigo, 0, log)
                self.assertIn("Motor encerrado.", log)
                # So o que vem antes do fim do `shutdown()`: o `atexit` do
                # scrcpy chama `stop_mirror` de novo na saida do interpretador.
                ate_o_fim = log.split("Motor encerrado.", 1)[0]
                etapas = [linha.split("DESMONTE ", 1)[1] for linha in ate_o_fim.splitlines() if "DESMONTE " in linha]
                self.assertEqual(etapas, ETAPAS_DO_DESMONTE, log)

    def test_fim_do_stdin_encerra_o_processo(self):
        proc = self._subir()
        self.assertIn("result", self._pedir(proc, 1, "engine.info"))
        proc.stdin.close()
        self.assertEqual(proc.wait(timeout=LANE_DRAIN_TIMEOUT_S + 5), 0)
        proc.stdout.close()


if __name__ == "__main__":
    unittest.main()
