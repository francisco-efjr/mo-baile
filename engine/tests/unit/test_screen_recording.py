"""Gravacao de video da tela.

Inclui a regressao do stdin herdado, que foi encontrada ligando esta feature:
o processo filho herdava o stdin do motor, que e o canal JSON-RPC, e passava a
consumir as linhas do protocolo. A chamada seguinte nunca respondia.
"""

from __future__ import annotations

import pathlib
import re
import signal
import unittest
from unittest.mock import MagicMock, patch

from mobaile.adapters.screen_recorder import ScreenRecorder
from mobaile.domain.errors import EngineError, InvalidInputError
from mobaile.domain.models import Platform


class FakeProcesso:
    def __init__(self, vivo=True):
        self._vivo = vivo
        self.sinais = []
        self.stdout = MagicMock()
        self.stderr = MagicMock()
        self.stderr.read.return_value = b""

    def poll(self):
        return None if self._vivo else 0

    def send_signal(self, sig):
        self.sinais.append(sig)
        self._vivo = False

    def wait(self, timeout=None):
        self._vivo = False
        return 0

    def kill(self):
        self._vivo = False


class TestGravacao(unittest.TestCase):
    def setUp(self):
        self.destino = pathlib.Path(__file__).parent / "_gravacoes_de_teste"
        self.adb = MagicMock()
        self.adb.adb_path = "adb"
        self.adb._run_cmd.return_value = (0, b"", b"")
        self.gravador = ScreenRecorder(self.adb, MagicMock(), output_dir=self.destino)

    def tearDown(self):
        if self.destino.exists():
            for arquivo in self.destino.iterdir():
                arquivo.unlink()
            self.destino.rmdir()

    def _com_processo(self, processo=None):
        return patch("subprocess.Popen", return_value=processo or FakeProcesso())

    def test_android_usa_screenrecord_no_aparelho(self):
        with self._com_processo() as popen, patch("time.sleep"):
            resultado = self.gravador.start(Platform.ANDROID, "ZY22L3CH3X")
        comando = popen.call_args[0][0]
        self.assertIn("screenrecord", comando)
        self.assertIn("-s", comando)
        self.assertIn("ZY22L3CH3X", comando)
        self.assertTrue(resultado["recording"])
        self.assertEqual(resultado["limit_s"], 180)

    def test_ios_usa_simctl_gravando_direto_no_mac(self):
        with self._com_processo() as popen, patch("time.sleep"):
            resultado = self.gravador.start(Platform.IOS, "1A2B3C4D-0000-4000-8000-0000000000AA")
        comando = popen.call_args[0][0]
        self.assertEqual(comando[:4], ["xcrun", "simctl", "io", "1A2B3C4D-0000-4000-8000-0000000000AA"])
        self.assertIn("recordVideo", comando)
        self.assertIsNone(resultado["limit_s"], "so o Android tem limite de tempo")

    def test_uma_gravacao_por_vez(self):
        with self._com_processo(), patch("time.sleep"):
            self.gravador.start(Platform.ANDROID, "ZY22L3CH3X")
            with self.assertRaises(InvalidInputError):
                self.gravador.start(Platform.ANDROID, "ZY22L3CH3X")

    def test_processo_que_morre_na_largada_vira_erro_e_nao_gravacao_falsa(self):
        morto = FakeProcesso(vivo=False)
        morto.stderr.read.return_value = b"screenrecord: permission denied"
        with self._com_processo(morto), patch("time.sleep"), self.assertRaises(EngineError) as ctx:
            self.gravador.start(Platform.ANDROID, "ZY22L3CH3X")
        self.assertIn("permission denied", str(ctx.exception))
        self.assertFalse(self.gravador.is_recording)

    def test_encerramento_e_por_sigint(self):
        """SIGKILL deixaria o MP4 sem indice final e o arquivo nao abriria."""
        processo = FakeProcesso()
        with self._com_processo(processo), patch("time.sleep"):
            self.gravador.start(Platform.ANDROID, "ZY22L3CH3X")
            self.destino.mkdir(parents=True, exist_ok=True)
            (self.destino / "gravado.mp4").write_bytes(b"conteudo")
            self.gravador._atual.local_path = self.destino / "gravado.mp4"
            resultado = self.gravador.stop()
        self.assertEqual(processo.sinais, [signal.SIGINT])
        self.assertEqual(resultado["size_bytes"], 8)
        self.assertFalse(resultado["recording"])

    def test_android_puxa_o_arquivo_e_limpa_o_aparelho(self):
        processo = FakeProcesso()
        with self._com_processo(processo), patch("time.sleep"):
            self.gravador.start(Platform.ANDROID, "ZY22L3CH3X")
            self.destino.mkdir(parents=True, exist_ok=True)
            (self.destino / "gravado.mp4").write_bytes(b"x")
            self.gravador._atual.local_path = self.destino / "gravado.mp4"
            self.gravador.stop()
        acoes = [c.args[0] for c in self.adb._run_cmd.call_args_list]
        self.assertTrue(any("pull" in a for a in acoes), acoes)
        self.assertTrue(any("rm" in a for a in acoes), "o video tem de sair do aparelho")

    def test_arquivo_vazio_vira_erro_explicado(self):
        processo = FakeProcesso()
        with self._com_processo(processo), patch("time.sleep"):
            self.gravador.start(Platform.ANDROID, "ZY22L3CH3X")
            with self.assertRaises(EngineError):
                self.gravador.stop()

    def test_parar_sem_gravar_nao_estoura(self):
        self.assertEqual(self.gravador.stop()["path"], None)

    def test_status_sem_gravacao(self):
        self.assertEqual(
            self.gravador.status(),
            {"recording": False, "path": None, "elapsed_s": 0.0, "platform": None},
        )


class TestStdinDosFilhos(unittest.TestCase):
    """Regressao: filho herdando o stdin do motor rouba o protocolo.

    Descoberto ligando a gravacao de tela: `recording.start` respondia, e
    `recording.status` logo depois nunca respondia. O `adb shell screenrecord`
    tinha herdado o stdin do processo do motor — que e o canal JSON-RPC — e
    consumia as linhas das chamadas seguintes. No app o sintoma e janela
    travada, sem erro nenhum.

    Seis dos sete `Popen` do motor tinham esse defeito. Como o modo de falhar e
    silencioso e dificil de ligar a causa, a regra vira guarda de codigo.
    """

    def test_todo_subprocesso_do_motor_isola_o_stdin(self):
        raiz = pathlib.Path(__file__).resolve().parents[2] / "src" / "mobaile"
        faltando = []
        for arquivo in raiz.rglob("*.py"):
            texto = arquivo.read_text(encoding="utf-8")
            for chamada in re.finditer(r"subprocess\.Popen\((.*?)\)\n", texto, re.DOTALL):
                if "stdin=" not in chamada.group(1):
                    linha = texto[: chamada.start()].count("\n") + 1
                    faltando.append(f"{arquivo.relative_to(raiz)}:{linha}")
        self.assertEqual(
            faltando, [],
            "Popen sem stdin explicito herda o canal JSON-RPC do motor: " + ", ".join(faltando),
        )


class TestCapturaCrua(unittest.TestCase):
    """`screencap` sem `-p` evita a codificacao PNG no aparelho.

    Medido num Motorola g55 fisico: 2,14 s com `-p` contra 1,23 s cru, apesar de
    o cru trafegar 10 MB contra 3 MB. Como o espelho reduz a imagem logo em
    seguida, pagar PNG no aparelho era quase um segundo jogado fora por quadro.
    """

    def ponte(self, retorno):
        from mobaile.adapters.adb import ADBBridge

        p = ADBBridge(adb_path="adb")
        p._run_cmd = lambda *a, **k: retorno
        return p

    @staticmethod
    def quadro(largura, altura, cabecalho):
        corpo = bytes([10, 20, 30, 255]) * (largura * altura)
        return (
            largura.to_bytes(4, "little")
            + altura.to_bytes(4, "little")
            + (1).to_bytes(4, "little")
            + b"\x00" * (cabecalho - 12)
            + corpo
        )

    def test_cabecalho_de_12_bytes(self):
        img = self.ponte((0, self.quadro(4, 3, 12), b""))._screenshot_raw("emulator-5554")
        self.assertEqual(img.size, (4, 3))

    def test_cabecalho_de_16_bytes_do_android_13(self):
        """O campo de espaco de cor entrou no cabecalho no Android 13; aceitar
        os dois tamanhos evita depender da versao do aparelho."""
        img = self.ponte((0, self.quadro(4, 3, 16), b""))._screenshot_raw("emulator-5554")
        self.assertEqual(img.size, (4, 3))

    def test_tamanho_que_nao_fecha_e_recusado(self):
        quebrado = self.quadro(4, 3, 12)[:-9]
        self.assertIsNone(self.ponte((0, quebrado, b""))._screenshot_raw("emulator-5554"))

    def test_dimensao_absurda_e_recusada(self):
        lixo = (99999).to_bytes(4, "little") + (99999).to_bytes(4, "little") + b"\x00" * 16
        self.assertIsNone(self.ponte((0, lixo, b""))._screenshot_raw("emulator-5554"))

    def test_captura_cai_para_png_quando_o_cru_falha(self):
        """Aparelho que nao entrega o formato cru nao pode ficar sem espelho."""
        from mobaile.adapters.adb import ADBBridge

        p = ADBBridge(adb_path="adb")
        p._screenshot_raw = lambda _d: None
        chamou = []
        p._screenshot_png = lambda _d: chamou.append(1) or "imagem"
        self.assertEqual(p.take_screenshot("emulator-5554"), "imagem")
        self.assertEqual(len(chamou), 1)
