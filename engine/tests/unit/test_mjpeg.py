"""F11: leitor do MJPEG do WebDriverAgent, com um servidor multipart falso."""

from __future__ import annotations

import http.server
import io
import json
import threading
import time
import unittest
from dataclasses import replace
from unittest.mock import patch

from PIL import Image

from mobaile.adapters.mjpeg import MJPEGReader
from mobaile.rpc.server import EngineServer


def _jpeg(color) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (40, 80), color).save(buf, format="JPEG", quality=80)
    return buf.getvalue()


class ServidorMJPEG:
    """Serve `quadros` como o WDA: multipart/x-mixed-replace com Content-Length."""

    def __init__(self, quadros: list[bytes], com_content_length: bool = True, pausa_entre_quadros: float = 0.03):
        servidor = self
        self.pausa = pausa_entre_quadros

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=--BoundaryString")
                self.end_headers()
                for quadro in servidor.quadros:
                    self.wfile.write(b"--BoundaryString\r\nContent-type: image/jpg\r\n")
                    if servidor.com_content_length:
                        self.wfile.write(b"Content-Length: %d\r\n" % len(quadro))
                    self.wfile.write(b"\r\n" + quadro + b"\r\n")
                    self.wfile.flush()
                    time.sleep(servidor.pausa)
                servidor.terminou.set()
                # Segura a conexao aberta ate o cliente fechar, como o WDA.
                servidor.solta.wait(5)

            def log_message(self, *_args):
                pass

        self.quadros = quadros
        self.com_content_length = com_content_length
        self.terminou = threading.Event()
        self.solta = threading.Event()
        self._http = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self._http.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self._http.server_address[1]}/"

    def fechar(self):
        self.solta.set()
        self._http.shutdown()
        self._http.server_close()


class TestMJPEGReader(unittest.TestCase):
    def _le_tudo(self, servidor, esperado):
        reader = MJPEGReader(servidor.url, connect_timeout=2)
        self.assertTrue(reader.start())
        self.addCleanup(reader.stop)
        self.assertTrue(servidor.terminou.wait(3))
        prazo = time.monotonic() + 2
        while time.monotonic() < prazo:
            quadro = reader.latest()
            if quadro and quadro[1] == len(esperado):
                break
            time.sleep(0.01)
        quadro = reader.latest()
        self.assertIsNotNone(quadro)
        data, seq = quadro
        self.assertEqual(seq, len(esperado))
        self.assertEqual(data, esperado[-1], "o ultimo quadro e o que fica")

    def test_le_quadros_com_content_length(self):
        quadros = [_jpeg("red"), _jpeg("green"), _jpeg("blue")]
        servidor = ServidorMJPEG(quadros)
        self.addCleanup(servidor.fechar)
        self._le_tudo(servidor, quadros)

    def test_le_quadros_sem_content_length(self):
        quadros = [_jpeg("red"), _jpeg("blue")]
        servidor = ServidorMJPEG(quadros, com_content_length=False)
        self.addCleanup(servidor.fechar)
        self._le_tudo(servidor, quadros)

    def test_pausa_maior_que_o_prazo_de_conexao_nao_derruba_a_leitura(self):
        quadros = [_jpeg("red"), _jpeg("blue")]
        servidor = ServidorMJPEG(quadros, pausa_entre_quadros=1.2)
        self.addCleanup(servidor.fechar)
        reader = MJPEGReader(servidor.url, connect_timeout=0.5)
        self.assertTrue(reader.start())
        self.addCleanup(reader.stop)
        self.assertTrue(servidor.terminou.wait(5))
        prazo = time.monotonic() + 2
        while time.monotonic() < prazo and (reader.latest() or (None, 0))[1] < 2:
            time.sleep(0.02)
        self.assertEqual(reader.latest()[1], 2, "o segundo quadro chegou apos a pausa")
        self.assertTrue(reader.is_running())

    def test_sem_servidor_start_devolve_false_rapido(self):
        reader = MJPEGReader("http://127.0.0.1:1/", connect_timeout=0.5)
        inicio = time.monotonic()
        self.assertFalse(reader.start())
        self.assertLess(time.monotonic() - inicio, 3)
        self.assertIsNone(reader.latest())

    def test_stop_encerra_a_thread(self):
        servidor = ServidorMJPEG([_jpeg("red")])
        self.addCleanup(servidor.fechar)
        reader = MJPEGReader(servidor.url, connect_timeout=2)
        self.assertTrue(reader.start())
        reader.stop()
        self.assertFalse(reader.is_running())


class TestEspelhoIOSPeloMJPEG(unittest.TestCase):
    """Com o MJPEG no ar, o espelho iOS repassa o JPEG do WDA e nao chama o simctl."""

    def setUp(self):
        self.out = io.StringIO()
        self.server = EngineServer(out=self.out)
        self.addCleanup(self.server.shutdown)

    def call(self, method, params=None):
        return self.server.handle_message(
            json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}})
        )

    def _quadros(self):
        return [json.loads(linha)["params"] for linha in self.out.getvalue().splitlines() if '"stream.frame"' in linha]

    def test_quadro_do_wda_sai_sem_reencodar_e_sem_simctl(self):
        import mobaile.rpc.server as rpc_server

        quadros = [_jpeg("red"), _jpeg("green")]
        servidor = ServidorMJPEG(quadros)
        self.addCleanup(servidor.fechar)
        porta = int(servidor.url.rsplit(":", 1)[1].strip("/"))
        with patch.object(rpc_server, "settings", replace(rpc_server.settings, wda_url="http://127.0.0.1:8100",
                                                           wda_mjpeg_port=porta)), \
             patch.object(self.server.ios, "take_screenshot", return_value=Image.new("RGB", (40, 80), "black")) as shot, \
             patch.object(self.server.ios, "set_mjpeg_scaling", return_value=True) as escala:
            self.call("session.select_device", {"platform": "ios", "device_id": "A1B2C3D4-1111-2222-3333-444455556666"})
            resultado = self.call("stream.start", {"fps": 30, "max_width": 900})["result"]
            self.assertEqual(resultado["source"], "wda_mjpeg")
            # Uma captura so, para medir a largura; os quadros vem do MJPEG.
            escala.assert_not_called()  # 40 px cabe em 900: nao precisa reduzir
            prazo = time.monotonic() + 3
            while len(self._quadros()) < 1 and time.monotonic() < prazo:
                time.sleep(0.02)
            self.call("stream.stop")
        emitidos = self._quadros()
        self.assertTrue(emitidos, "nenhum quadro saiu do MJPEG")
        self.assertEqual(shot.call_count, 1, "o simctl so mede a largura; os quadros vem do MJPEG")
        import base64

        bytes_emitidos = {base64.b64decode(q["image_base64"]) for q in emitidos}
        self.assertTrue(bytes_emitidos & set(quadros), "o JPEG emitido deve ser o mesmo que o WDA mandou")

    def test_quadro_nativo_maior_que_max_width_pede_reducao_ao_wda(self):
        import mobaile.rpc.server as rpc_server

        servidor = ServidorMJPEG([_jpeg("red")])
        self.addCleanup(servidor.fechar)
        porta = int(servidor.url.rsplit(":", 1)[1].strip("/"))
        with patch.object(rpc_server, "settings", replace(rpc_server.settings, wda_url="http://127.0.0.1:8100",
                                                           wda_mjpeg_port=porta)), \
             patch.object(self.server.ios, "take_screenshot", return_value=Image.new("RGB", (1170, 2532), "black")), \
             patch.object(self.server.ios, "set_mjpeg_scaling", return_value=True) as escala:
            self.call("session.select_device", {"platform": "ios", "device_id": "A1B2C3D4-1111-2222-3333-444455556666"})
            self.call("stream.start", {"fps": 30, "max_width": 900, "quality": 70})
            self.call("stream.stop")
        escala.assert_called_once_with(76, 70)

    def test_sem_mjpeg_cai_no_simctl(self):
        import mobaile.rpc.server as rpc_server

        with patch.object(rpc_server, "settings", replace(rpc_server.settings, wda_url="http://127.0.0.1:8100",
                                                           wda_mjpeg_port=1)), \
             patch.object(self.server.ios, "take_screenshot", return_value=Image.new("RGB", (40, 80), "black")):
            self.call("session.select_device", {"platform": "ios", "device_id": "A1B2C3D4-1111-2222-3333-444455556666"})
            resultado = self.call("stream.start", {"fps": 30, "max_width": 900})["result"]
            self.assertEqual(resultado["source"], "capture")
            prazo = time.monotonic() + 3
            while not self._quadros() and time.monotonic() < prazo:
                time.sleep(0.02)
            self.call("stream.stop")
        self.assertTrue(self._quadros())


if __name__ == "__main__":
    unittest.main()
