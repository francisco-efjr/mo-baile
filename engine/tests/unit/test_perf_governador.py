"""PERF-3: politica de perfis de desempenho, testada por tabela.

`resolve` e pura: sinais do Mac, preferencia do usuario, estado anterior e
relogio entram; perfil, motivo e o instante da troca saem. Regras:

- piora na hora com sinal do sistema;
- melhora so depois de 60 s com o alvo melhor, um degrau por vez;
- a escolha manual sempre ganha, exceto com `thermal == critical`.
"""

from __future__ import annotations

import unittest
from typing import ClassVar

from mobaile.services import perf
from mobaile.services.perf import Estado, Sinais, resolve

NORMAL = Sinais()


class TestAlvoAutomatico(unittest.TestCase):
    """Sinal do sistema -> perfil pedido, sem historia."""

    CASOS: ClassVar[list[tuple[Sinais, str, str]]] = [
        (Sinais(), "completo", "sinais_normais"),
        (Sinais(thermal="fair"), "equilibrado", "thermal_fair"),
        (Sinais(thermal="serious"), "leve", "thermal_serious"),
        (Sinais(thermal="critical"), "leve", "thermal_critical"),
        (Sinais(low_power=True), "equilibrado", "low_power"),
        (Sinais(memory_pressure="warning"), "equilibrado", "memory_warning"),
        (Sinais(memory_pressure="critical"), "leve", "memory_critical"),
        (Sinais(physical_memory_gb=8), "equilibrado", "hardware_modesto"),
        (Sinais(physical_memory_gb=16), "completo", "sinais_normais"),
        (Sinais(arch="x86_64"), "equilibrado", "hardware_modesto"),
        (Sinais(translated=True), "equilibrado", "hardware_modesto"),
        # Economia de energia num Mac modesto vai direto ao leve.
        (Sinais(low_power=True, physical_memory_gb=8), "leve", "low_power"),
        # O pior sinal decide; empate fica com o mais grave.
        (Sinais(thermal="fair", memory_pressure="critical"), "leve", "memory_critical"),
        (Sinais(thermal="serious", memory_pressure="critical"), "leve", "thermal_serious"),
    ]

    def test_tabela(self):
        for sinais, perfil, motivo in self.CASOS:
            with self.subTest(sinais=sinais):
                estado = resolve(sinais, "auto", None, 0.0)
                self.assertEqual((estado.perfil, estado.motivo), (perfil, motivo))


class TestHisterese(unittest.TestCase):
    def test_piora_na_hora(self):
        atual = resolve(NORMAL, "auto", None, 0.0)
        quente = resolve(Sinais(thermal="serious"), "auto", atual, 5.0)
        self.assertEqual((quente.perfil, quente.motivo, quente.desde), ("leve", "thermal_serious", 5.0))

    def test_melhora_espera_60_s_e_sobe_um_degrau_por_vez(self):
        tabela = [
            # (instante, sinais, perfil esperado)
            (0.0, Sinais(thermal="serious"), "leve"),
            (10.0, NORMAL, "leve"),          # o alvo melhorou: comeca a contar
            (69.0, NORMAL, "leve"),          # 59 s: ainda nao
            (70.0, NORMAL, "equilibrado"),   # 60 s: um degrau
            (129.0, NORMAL, "equilibrado"),  # o proximo degrau conta de novo
            (130.0, NORMAL, "completo"),
        ]
        estado = None
        for instante, sinais, esperado in tabela:
            estado = resolve(sinais, "auto", estado, instante)
            with self.subTest(instante=instante):
                self.assertEqual(estado.perfil, esperado)
        self.assertEqual(estado.motivo, "sinais_normais")

    def test_degrau_intermediario_diz_que_esta_se_recuperando(self):
        estado = resolve(Sinais(thermal="serious"), "auto", None, 0.0)
        estado = resolve(NORMAL, "auto", estado, 1.0)
        estado = resolve(NORMAL, "auto", estado, 61.0)
        self.assertEqual((estado.perfil, estado.motivo), ("equilibrado", "recuperando"))

    def test_sinal_ruim_no_meio_da_espera_zera_a_contagem(self):
        estado = resolve(Sinais(thermal="serious"), "auto", None, 0.0)
        estado = resolve(NORMAL, "auto", estado, 10.0)
        estado = resolve(Sinais(thermal="serious"), "auto", estado, 40.0)
        self.assertIsNone(estado.melhora_desde)
        estado = resolve(NORMAL, "auto", estado, 45.0)
        estado = resolve(NORMAL, "auto", estado, 80.0)
        self.assertEqual(estado.perfil, "leve", "a espera recomeca depois do sinal ruim")

    def test_mesmo_perfil_com_outro_motivo_mantem_o_inicio(self):
        estado = resolve(Sinais(thermal="serious"), "auto", None, 0.0)
        estado = resolve(Sinais(memory_pressure="critical"), "auto", estado, 30.0)
        self.assertEqual((estado.perfil, estado.motivo, estado.desde), ("leve", "memory_critical", 0.0))

    def test_reavaliar_sem_sinal_novo_tambem_melhora(self):
        estado = resolve(Sinais(thermal="serious"), "auto", None, 0.0)
        estado = resolve(NORMAL, "auto", estado, 1.0)
        self.assertEqual(estado.proxima_reavaliacao(), 61.0)


class TestManual(unittest.TestCase):
    def test_manual_ganha_do_automatico(self):
        for perfil in perf.PERFIS:
            with self.subTest(perfil=perfil):
                estado = resolve(Sinais(thermal="serious"), perfil, None, 0.0)
                self.assertEqual((estado.perfil, estado.motivo), (perfil, "manual"))

    def test_troca_manual_vale_na_hora_mesmo_para_melhor(self):
        estado = resolve(NORMAL, "leve", None, 0.0)
        estado = resolve(NORMAL, "completo", estado, 1.0)
        self.assertEqual((estado.perfil, estado.motivo), ("completo", "manual"))

    def test_critico_vence_o_manual(self):
        estado = resolve(Sinais(thermal="critical"), "completo", None, 0.0)
        self.assertEqual((estado.perfil, estado.motivo), ("leve", "thermal_critical"))

    def test_depois_do_critico_volta_ao_manual_com_histerese(self):
        estado = resolve(Sinais(thermal="critical"), "completo", None, 0.0)
        estado = resolve(NORMAL, "completo", estado, 1.0)
        self.assertEqual(estado.perfil, "leve")
        estado = resolve(NORMAL, "completo", estado, 61.0)
        estado = resolve(NORMAL, "completo", estado, 121.0)
        self.assertEqual((estado.perfil, estado.motivo), ("completo", "manual"))

    def test_voltar_ao_automatico_aplica_o_alvo_na_hora(self):
        estado = resolve(NORMAL, "leve", None, 0.0)
        estado = resolve(NORMAL, "auto", estado, 1.0)
        self.assertEqual((estado.perfil, estado.motivo), ("completo", "sinais_normais"))


class TestSinais(unittest.TestCase):
    def test_atualizacao_parcial_preserva_o_resto(self):
        sinais = Sinais(thermal="fair", physical_memory_gb=8).com({"low_power": True})
        self.assertEqual((sinais.thermal, sinais.low_power, sinais.physical_memory_gb), ("fair", True, 8))

    def test_valor_invalido_e_recusado(self):
        for campo, valor in [("thermal", "morno"), ("memory_pressure", 3), ("low_power", "sim"),
                             ("physical_memory_gb", -1), ("arch", "ppc" * 20)]:
            with self.subTest(campo=campo), self.assertRaises(ValueError):
                Sinais().com({campo: valor})

    def test_knobs_de_cada_perfil(self):
        completo, leve = perf.KNOBS["completo"], perf.KNOBS["leve"]
        # Completo mantem a cadencia de hoje (6 fps, 900 px, q80).
        self.assertEqual((completo.stream_fps, completo.stream_max_width, completo.stream_quality), (6.0, 900, 80))
        self.assertTrue(completo.glass and completo.animations)
        self.assertFalse(leve.glass or leve.animations)
        for nome in ("stream_fps", "stream_idle_fps", "stream_max_width", "stream_quality",
                     "proxy_body_capture_kb"):
            with self.subTest(knob=nome):
                self.assertGreater(getattr(completo, nome), getattr(leve, nome))
        self.assertLess(completo.poll_interval, leve.poll_interval)


class TestEstado(unittest.TestCase):
    def test_estado_e_imutavel(self):
        estado = Estado("completo", "sinais_normais", 0.0)
        with self.assertRaises(AttributeError):
            estado.perfil = "leve"  # type: ignore[misc]


if __name__ == "__main__":
    unittest.main()
