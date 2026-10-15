"""F11: quadro do espelho em JPEG, com repasse do MJPEG sem reencodar."""

from __future__ import annotations

import base64
import io
import json
import time
import unittest
from unittest.mock import patch

from PIL import Image

from mobaile.rpc.server import EngineServer


def _jpeg_bytes(size=(60, 120), color="blue") -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color).save(buf, format="JPEG", quality=80)
    return buf.getvalue()


class TestEncodeFrame(unittest.TestCase):
    def test_jpeg_por_padrao_sem_png_base64(self):
        payload = EngineServer._encode_frame(Image.new("RGB", (60, 120), "black"), None, "jpeg", 80)
        self.assertEqual(payload["format"], "jpeg")
        self.assertNotIn("png_base64", payload)
        self.assertTrue(base64.b64decode(payload["image_base64"]).startswith(b"\xff\xd8"))
        self.assertEqual((payload["width"], payload["height"]), (60, 120))

    def test_png_a_pedido_mantem_png_base64_para_front_antigo(self):
        payload = EngineServer._encode_frame(Image.new("RGB", (60, 120), "black"), None, "png", 80)
        self.assertEqual(payload["format"], "png")
        self.assertEqual(payload["png_base64"], payload["image_base64"])
        self.assertTrue(base64.b64decode(payload["png_base64"]).startswith(b"\x89PNG"))

    def test_quadro_que_veio_como_jpeg_e_repassado_sem_reencodar(self):
        data = _jpeg_bytes()
        image = Image.open(io.BytesIO(data))
        image.load()
        image.info["mobaile_jpeg"] = data
        payload = EngineServer._encode_frame(image, 900, "jpeg", 80)
        self.assertEqual(base64.b64decode(payload["image_base64"]), data, "os bytes devem ser os do MJPEG")

    def test_quadro_maior_que_max_width_e_reduzido_mesmo_vindo_do_mjpeg(self):
        data = _jpeg_bytes((600, 1200))
        image = Image.open(io.BytesIO(data))
        image.load()
        image.info["mobaile_jpeg"] = data
        payload = EngineServer._encode_frame(image, 300, "jpeg", 80)
        self.assertEqual(payload["width"], 300)
        self.assertEqual(payload["source_width"], 600)
        self.assertNotEqual(base64.b64decode(payload["image_base64"]), data)

    def test_imagem_rgba_vira_jpeg(self):
        payload = EngineServer._encode_frame(Image.new("RGBA", (10, 10), (1, 2, 3, 255)), None, "jpeg", 80)
        self.assertEqual(payload["format"], "jpeg")


class TestStreamStartFormato(unittest.TestCase):
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

    def test_formato_invalido_e_recusado(self):
        self.call("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        resposta = self.call("stream.start", {"format": "gif"})
        self.assertIn("error", resposta)

    def test_png_a_pedido_no_stream(self):
        self.call("session.select_device", {"platform": "android", "device_id": "emulator-5554"})
        with patch.object(self.server.adb, "take_screenshot", return_value=Image.new("RGB", (40, 80), "black")):
            resultado = self.call("stream.start", {"fps": 30, "max_width": 20, "format": "png"})["result"]
            self.assertEqual(resultado["format"], "png")
            self.assertEqual(resultado["source"], "capture")
            prazo = time.monotonic() + 3
            while not self._quadros() and time.monotonic() < prazo:
                time.sleep(0.02)
            self.call("stream.stop")
        quadro = self._quadros()[0]
        self.assertEqual(quadro["format"], "png")
        self.assertIn("png_base64", quadro)
        self.assertEqual(quadro["width"], 20)


if __name__ == "__main__":
    unittest.main()
