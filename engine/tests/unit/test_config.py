"""Configuracao vinda do ambiente.

Antes, cada campo era `float(os.getenv(...))` avaliado no corpo da dataclass:
um valor invalido no `.env` derrubava o processo no import, e um `STREAM_FPS=0`
virava divisao por zero la adiante, longe da causa.
"""

import dataclasses
import unittest
from unittest.mock import patch

from mobaile.config import Settings


class TestSettings(unittest.TestCase):
    def _com_env(self, **valores) -> Settings:
        with patch.dict("os.environ", valores, clear=False):
            return Settings.from_env()

    def test_padroes(self):
        cfg = self._com_env()
        self.assertEqual(cfg.proxy_host, "127.0.0.1")
        self.assertGreater(cfg.stream_fps, 0)

    def test_valor_nao_numerico_cai_no_padrao_sem_derrubar(self):
        cfg = self._com_env(STREAM_FPS="rapido")
        self.assertEqual(cfg.stream_fps, 3.5)

    def test_zero_e_rejeitado_porque_vira_divisao_por_zero(self):
        self.assertEqual(self._com_env(STREAM_FPS="0").stream_fps, 3.5)

    def test_valor_absurdo_e_limitado(self):
        self.assertEqual(self._com_env(STREAM_FPS="100000").stream_fps, 3.5)
        self.assertEqual(self._com_env(POLL_INTERVAL="-3").poll_interval, 1.5)

    def test_estrategia_invalida_cai_no_padrao(self):
        self.assertEqual(self._com_env(DEFAULT_STRATEGY="telepatia").default_strategy, "position")
        self.assertEqual(self._com_env(DEFAULT_STRATEGY="XPATH").default_strategy, "xpath")

    def test_porta_do_proxy(self):
        self.assertEqual(self._com_env(PROXY_PORT="9090").proxy_port, 9090)
        self.assertEqual(self._com_env(PROXY_PORT="70000").proxy_port, 8082)

    def test_barra_final_da_wda_url_e_normalizada(self):
        self.assertEqual(self._com_env(WDA_URL="http://localhost:8100/").wda_url, "http://localhost:8100")

    def test_settings_e_imutavel(self):
        # Frozen de proposito: configuracao mutavel em tempo de execucao vira
        # bug de estado compartilhado entre threads.
        cfg = self._com_env()
        with self.assertRaises(dataclasses.FrozenInstanceError):
            cfg.stream_fps = 99  # type: ignore[misc]


if __name__ == "__main__":
    unittest.main()
