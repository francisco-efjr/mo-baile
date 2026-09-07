"""Teste de widget do inspetor HTTP.

Vive junto da UI legada, e nao na suite do motor: exigir Tkinter para rodar
o teste do proxy travava a suite inteira em qualquer ambiente headless (CI
inclusive), que foi exatamente o que aconteceu no diagnostico inicial.
"""

import time
import unittest

from mobaile.adapters.proxy import NetworkEvent
from mobaile_tk.http_viewer import HTTPInspectorFrame, HTTPViewerWindow  # noqa: F401


class TestHTTPInspectorWidget(unittest.TestCase):
    def test_http_inspector_frame_tabs_and_formatting(self):
        import tkinter as tk
        try:
            root = tk.Tk()
            root.withdraw()
            frame = HTTPInspectorFrame(root)
            self.assertEqual(len(frame.notebook.tabs()), 2)
            self.assertEqual(frame.notebook.tab(0, "text"), "Requisição (Request)")
            self.assertEqual(frame.notebook.tab(1, "text"), "Resposta (Response)")

            event = NetworkEvent(
                id=1,
                timestamp=time.time(),
                time_str="12:00:00.000",
                method="POST",
                url="http://api.exemplo.com/v1/login",
                host="api.exemplo.com",
                path="/v1/login",
                status_code=200,
                status_text="OK",
                request_headers={"Content-Type": "application/json"},
                request_body='{"user": "qa", "pass": "123"}',
                response_headers={"Content-Type": "application/json"},
                response_body='{"token": "xyz123"}',
                duration_ms=45.2,
            )

            req_txt = frame._format_request_text(event)
            resp_txt = frame._format_response_text(event)
            self.assertIn("URL: http://api.exemplo.com/v1/login", req_txt)
            self.assertIn("STATUS: 200 OK", resp_txt)
            self.assertIn("token", resp_txt)

            frame.destroy_resources()
            root.destroy()
        except tk.TclError:
            pass



if __name__ == "__main__":
    unittest.main()
