"""REV-3: o proxy conta os tuneis abertos, que ainda nao estao no historico."""

import unittest

from mobaile.adapters.proxy import MobileNetworkProxy


class TestTuneisAtivos(unittest.TestCase):
    def test_contador_sobe_e_desce_e_nunca_fica_negativo(self):
        proxy = MobileNetworkProxy(host="127.0.0.1", port=0)
        self.assertEqual(proxy.active_tunnels, 0)
        proxy.tunnel_opened()
        proxy.tunnel_opened()
        self.assertEqual(proxy.active_tunnels, 2)
        proxy.tunnel_closed()
        proxy.tunnel_closed()
        proxy.tunnel_closed()
        self.assertEqual(proxy.active_tunnels, 0)


if __name__ == "__main__":
    unittest.main()
