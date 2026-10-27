"""HTML interativo do Relatório: identidade do app, arquivo único e seguro.

O cenário é o mesmo de `test_report_audit` (7 validações: 3 OK, 2 divergentes,
2 não disparadas). Aqui o que se confere é o arquivo: tudo embutido, nada de
rede, os scripts autorizados pelo hash, texto de fora sempre escapado e o
design system em dia com `docs/design/design-system`.
"""

from __future__ import annotations

import base64
import hashlib
import re
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from PIL import Image
from relatorio_dados import AUSENTES, DIVERGENTES, LOG, OK, SPEC, TOTAL, android, ios

from mobaile import __version__
from mobaile.domain.report import SpecTemplate
from mobaile.services.report.audit import run_audit
from mobaile.services.report.board import log_period
from mobaile.services.report.documents import generate_html, generate_markdown
from mobaile.services.report.firebase_log import events_from_items
from mobaile.services.report.html_report import MOTION_VERSION, generate_interactive_html

ROOT = Path(__file__).resolve().parents[3]
QUANDO = datetime(2026, 10, 23, 14, 30)


def relatorio(spec=None, log=None, platform="android"):
    events, stats = events_from_items(LOG if log is None else log, platform)
    return run_audit(SpecTemplate.from_dict(SPEC if spec is None else spec), events, platform, stats)


class TestRelatorioInterativo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = relatorio()
        cls.html = generate_interactive_html(cls.report, prints_dir="/caminho/que/nao/existe", generated_at=QUANDO)

    def test_uma_validacao_por_resultado_com_o_status_certo(self):
        self.assertEqual(self.html.count('class="v '), TOTAL)
        self.assertEqual(self.html.count('data-s="ok" id="v-'), OK)
        self.assertEqual(self.html.count('data-s="err" id="v-'), DIVERGENTES)
        self.assertEqual(self.html.count('data-s="miss" id="v-'), AUSENTES)
        # A tabela tem uma linha por validação, que leva ao card.
        self.assertEqual(self.html.count('data-target="card-'), TOTAL)

    def test_filtros_com_as_contagens_do_app(self):
        for rotulo in (f"Todas ({TOTAL})", f"Pedem Ação ({DIVERGENTES + AUSENTES})", f"Divergentes ({DIVERGENTES})",
                       f"Não Disparadas ({AUSENTES})", f"OK ({OK})"):
            self.assertIn(f'aria-label="{rotulo}"', self.html)
        self.assertIn("42,9%", self.html)

    def test_nao_disparada_mostra_o_que_a_spec_espera(self):
        ausente = re.search(r'<article class="v err" data-s="miss".*?</article>', self.html, re.S).group(0)
        self.assertIn("Não disparado", ausente)
        self.assertIn("click:[numero]-parcela-sem-seguro", ausente)

    def test_divergencia_destaca_obtido_e_esperado(self):
        self.assertRegex(self.html, r'class="is-bad".*?v__field">component<.*?v__got">toggle<.*?v__exp">button<')

    def test_identidade_e_letras_miudas_do_mo_baile(self):
        self.assertIn('<footer class="rp-footer">', self.html)
        self.assertIn(f"Gerado pelo <b>Mo baile</b> {__version__}", self.html)
        self.assertIn("23/10/2026 14:30", self.html)
        self.assertIn(f"Motion {MOTION_VERSION} (MIT)", self.html)
        self.assertIn('rel="icon" href="data:image/png;base64,', self.html)
        # Design system inteiro: marca, aparências, vidro e molas.
        for token in ("--brand-flamingo: #F389A9", '[data-theme="dark"]', '[data-contrast="high"]',
                      "--glass-filter", "--spring-snappy-ease", ".mb-seg__thumb", ".mb-status--error"):
            self.assertIn(token, self.html)

    def test_arquivo_unico_sem_rede(self):
        self.assertNotRegex(self.html, r"""(?:src|href)\s*=\s*["']?(?:https?:)?//""")
        self.assertNotIn("@import", self.html)
        self.assertIn("default-src 'none'", self.html)

    def test_so_rodam_os_scripts_embutidos(self):
        csp = re.search(r'http-equiv="Content-Security-Policy" content="([^"]+)"', self.html).group(1)
        permitidos = set(re.findall(r"'sha256-([^']+)'", csp))
        scripts = re.findall(r"<script>(.*?)</script>", self.html, re.S)
        self.assertEqual(len(scripts), 3)
        for script in scripts:
            digest = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
            self.assertIn(digest, permitidos)
        self.assertNotIn("unsafe-inline' 'self", csp)
        self.assertNotRegex(csp, r"script-src[^;]*unsafe-inline")

    def test_mesmo_relatorio_na_mesma_hora_gera_o_mesmo_arquivo(self):
        outro = generate_interactive_html(relatorio(), prints_dir="/caminho/que/nao/existe", generated_at=QUANDO)
        self.assertEqual(outro, self.html)

    def test_documents_usa_o_html_interativo(self):
        self.assertIn('class="rp-toolbar"', generate_html(self.report))


class TestPeriodoDoLog(unittest.TestCase):
    """Data e hora do primeiro ao último evento, no cabeçalho do HTML e no Markdown."""

    def test_logcat_traz_dia_e_mes_e_a_duracao(self):
        periodo = log_period(relatorio())
        self.assertEqual((periodo.start, periodo.end, periodo.duration), ("08/10 10:00:00", "10:06:00", "6 min"))
        self.assertEqual(periodo.text(), "08/10 10:00:00 até 10:06:00 (6 min)")

    def test_destaque_ao_lado_da_plataforma(self):
        html = generate_interactive_html(relatorio(), generated_at=QUANDO)
        meta = re.search(r'<div class="rp-hero__meta">(.*?)</div>', html, re.S).group(1)
        self.assertRegex(meta, r'rp-chip--android.*?</span><span class="rp-period"')
        self.assertIn("<time>08/10 10:00:00</time><span class=\"rp-period__to\">até</span><time>10:06:00</time>", meta)
        self.assertIn('<span class="rp-period__dur">6 min</span>', meta)

    def test_markdown_tambem_traz_o_periodo(self):
        self.assertIn("- Período do log: 08/10 10:00:00 até 10:06:00 (6 min)", generate_markdown(relatorio()))

    def test_ios_com_ano_e_virada_de_dia(self):
        log = [ios("2026-10-08 23:58:10.000", "screen_view", {"ga_screen": "app:pedido:home"}),
               ios("2026-10-09 00:03:40.500", "screen_view", {"ga_screen": "app:pedido:home"})]
        periodo = log_period(relatorio(log=log, platform="ios"))
        self.assertEqual((periodo.start, periodo.end, periodo.duration),
                         ("08/10/2026 23:58:10", "09/10/2026 00:03:40", "5 min"))

    def test_sem_data_mostra_so_a_hora(self):
        log = [ios("09:15:00.000", "screen_view", {"ga_screen": "a"}), ios("11:20:30.000", "screen_view", {"ga_screen": "b"})]
        periodo = log_period(relatorio(log=log, platform="ios"))
        self.assertEqual((periodo.start, periodo.end, periodo.duration), ("09:15:00", "11:20:30", "2 h 05 min"))

    def test_sem_eventos_ou_sem_horario_nao_inventa_periodo(self):
        self.assertIsNone(log_period(relatorio(log=[], platform="ios")))
        sem_hora = [ios("", "screen_view", {"ga_screen": "a"})]
        self.assertIsNone(log_period(relatorio(log=sem_hora, platform="ios")))
        self.assertNotIn('class="rp-period"', generate_interactive_html(relatorio(log=[], platform="ios")))


class TestTextoDeFora(unittest.TestCase):
    def test_spec_e_log_hostis_nao_viram_marcacao(self):
        hostil = '<img src=x onerror=alert(1)>'
        spec = dict(SPEC, projeto='</script><script>alert("x")</script>', versao_especificacao=hostil)
        spec["cards"] = [dict(SPEC["cards"][0], secao=hostil, titulo='"><svg onload=alert(2)>')]
        log = [android("10:00:00.000", "screen_view(_vs)",
                       f"flow_name=pedido, ga_event_origin(_o)=app, ga_screen(_sn)={hostil}")]
        html = generate_interactive_html(relatorio(spec, log), generated_at=QUANDO)
        self.assertEqual(html.count("<script>"), 3)
        self.assertNotIn("<img src=x", html)
        self.assertNotIn("<svg onload", html)
        self.assertIn("&lt;/script&gt;&lt;script&gt;alert(&quot;x&quot;)", html)


class TestPrintDaSpec(unittest.TestCase):
    def test_print_embutido_e_ampliavel_ou_aviso_quando_falta(self):
        with tempfile.TemporaryDirectory() as pasta:
            Image.new("RGB", (40, 30), "#F389A9").save(Path(pasta) / "home.png")
            spec = dict(SPEC)
            spec["cards"] = [dict(SPEC["cards"][0], print="home.png"), dict(SPEC["cards"][1], print="falta.png"),
                             SPEC["cards"][2]]
            html = generate_interactive_html(relatorio(spec), prints_dir=pasta, generated_at=QUANDO)
        self.assertEqual(html.count('class="rp-print"'), 1)
        self.assertIn('src="data:image/png;base64,', html)
        self.assertIn("falta.png", html)
        self.assertIn("Sem print", html)


@unittest.skipUnless((ROOT / "docs" / "design" / "design-system").is_dir(), "fora do repositório")
class TestDesignSystemEmDia(unittest.TestCase):
    def test_copia_embutida_bate_com_o_design_system(self):
        result = subprocess.run([sys.executable, str(ROOT / "tools" / "sync_report_assets.py"), "--check"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
