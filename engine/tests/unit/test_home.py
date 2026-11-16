"""Tela Início: estado, contagem do ambiente, alvos, recentes e novidades.

O oráculo é a especificação (docs/design/home/README.md): primeira vez só
quando nenhuma plataforma serve; pendência diz o que bloqueia; recentes são
locais, até 20, dos últimos 30 dias; novidades vêm da seção da versão.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

from mobaile.services.home import (
    DAILY,
    FIRST_RUN,
    RECENT_MAX,
    RECENT_MAX_AGE_S,
    HomeService,
    RecentStore,
    whats_new,
)


def componente(id_, estado="ok", required=True, install=None, link=None, needed_for="", label=None):
    return {"id": id_, "label": label or id_, "state": estado, "detail": f"detalhe de {id_}",
            "required": required, "install": install, "link": link, "needed_for": needed_for}


def resultado_setup(adb="ok", xcode="ok", appium="ok"):
    return {
        "system": "macos",
        "python": {"version": "3.14.0", "path": "/usr/local/bin/python3"},
        "groups": [
            {"id": "motor", "title": "Motor", "components": [componente("python")]},
            {"id": "android", "title": "Android", "components": [
                componente("adb", adb, install="android", needed_for="tudo no Android",
                           label="Android Platform Tools (adb)"),
                componente("scrcpy", "off", required=False, install="scrcpy"),
            ]},
            {"id": "ios", "title": "iOS", "components": [
                componente("xcode", xcode, link="macappstore://xcode", needed_for="tudo no iOS", label="Xcode"),
                componente("appium", appium, install="appium", needed_for="toque e hierarquia no iOS",
                           label="Appium com o driver XCUITest"),
            ]},
            {"id": "extras", "title": "Extras opcionais", "components": [
                componente("quartz", "off", required=False),
            ]},
        ],
        "features": [],
        "pending": 0,
        "next_step": None,
    }


class SetupFalso:
    system = "macos"

    def __init__(self, resultado):
        self.resultado = resultado

    def run(self, platform_in_use=None):
        return self.resultado


class AdbFalso:
    def __init__(self, devices=(), avds=()):
        self.devices = [SimpleNamespace(id=i, name=n) for i, n in devices]
        self.avds = list(avds)

    def list_devices_typed(self):
        return self.devices

    def list_avds(self):
        return self.avds


class IosFalso:
    def __init__(self, simuladores=()):
        self.simuladores = list(simuladores)

    def list_all_simulators(self):
        return self.simuladores


def simulador(udid, nome, runtime="iOS 18.0", booted=False):
    return {"udid": udid, "name": nome, "state": "Booted" if booted else "Shutdown", "runtime": runtime,
            "booted": booted}


class Base(unittest.TestCase):
    def setUp(self):
        self.pasta = Path(tempfile.mkdtemp())
        self.recentes = RecentStore(self.pasta / "recentes.json", clock=lambda: 1_000_000.0)

    def servico(self, resultado=None, adb=None, ios=None, changelog=None):
        return HomeService(
            setup=lambda: SetupFalso(resultado or resultado_setup()),
            ios=ios or IosFalso(), adb=adb or AdbFalso(), recents=self.recentes,
            changelog=lambda: changelog, version="3.11.0",
        )


class TestEstado(Base):
    def test_sem_plataforma_utilizavel_e_primeira_vez(self):
        resumo = self.servico(resultado_setup(adb="error", xcode="error", appium="error")).summary()
        self.assertEqual(resumo["state"], FIRST_RUN)

    def test_ios_so_com_espelho_ja_e_uso_diario(self):
        resumo = self.servico(resultado_setup(adb="error", appium="error")).summary()
        self.assertEqual(resumo["state"], DAILY)

    def test_plataforma_sugerida_e_a_mais_perto_de_pronta(self):
        resumo = self.servico(resultado_setup(adb="error", xcode="ok", appium="error")).summary()
        sugerida = resumo["suggested_platform"]
        self.assertIn(sugerida, ("android", "ios"))
        cartoes = {p["platform"]: p for p in resumo["platforms"]}
        self.assertEqual(cartoes["ios"]["found"], ["Xcode encontrado"])
        self.assertEqual(cartoes["ios"]["install"], "appium")
        self.assertEqual(cartoes["android"]["install"], "android")
        # Android falta 1 (adb), iOS falta 1 (Appium): empate vai para o Android.
        self.assertEqual(sugerida, "android")


class TestAmbiente(Base):
    def test_conta_so_obrigatorios_das_plataformas_em_uso(self):
        # Android pronto e iOS nunca começado: o iOS não conta.
        ambiente = self.servico(resultado_setup(xcode="error", appium="error")).summary()["environment"]
        self.assertEqual((ambiente["ready"], ambiente["total"]), (2, 2))
        self.assertEqual(ambiente["pending"], [])

    def test_appium_faltando_bloqueia_so_page_objects_no_ios(self):
        ambiente = self.servico(resultado_setup(appium="warn")).summary()["environment"]
        self.assertEqual((ambiente["ready"], ambiente["total"]), (3, 4))
        [pendente] = ambiente["pending"]
        self.assertEqual(pendente["id"], "appium")
        self.assertEqual(pendente["install"], "appium")
        self.assertEqual(pendente["blocks"], [
            {"area": "page_objects", "platform": "ios", "effect": "toque e hierarquia no iOS"},
        ])


class TestAlvos(Base):
    def test_conectado_primeiro_e_capacidades_por_plataforma(self):
        servico = self.servico(
            resultado_setup(appium="error"),
            adb=AdbFalso(devices=[("R58M", "Galaxy S21")], avds=["Pixel_8"]),
            ios=IosFalso([simulador("U1", "iPhone 16 Pro"), simulador("U2", "iPad Air")]),
        )
        alvos = servico.summary(device_id="R58M")["targets"]
        self.assertEqual(alvos[0]["id"], "R58M")
        self.assertTrue(alvos[0]["connected"])
        self.assertEqual(alvos[0]["kind"], "physical")
        iphone = next(a for a in alvos if a["id"] == "U1")
        self.assertEqual(iphone["capabilities"], {"mirror": True, "tap": False, "record": False})
        self.assertEqual(iphone["blocked_by"], ["appium"])
        pixel = next(a for a in alvos if a["id"] == "Pixel_8")
        self.assertEqual((pixel["name"], pixel["kind"], pixel["running"]), ("Pixel 8", "emulator", False))
        self.assertEqual(pixel["capabilities"], {"mirror": True, "tap": True, "record": True})

    def test_com_emulador_ligado_nao_oferece_ligar_avd(self):
        servico = self.servico(adb=AdbFalso(devices=[("emulator-5554", "sdk_gphone64")], avds=["Pixel_8"]))
        ids = [a["id"] for a in servico.summary()["targets"]]
        self.assertIn("emulator-5554", ids)
        self.assertNotIn("Pixel_8", ids)

    def test_iphone_mais_novo_antes_e_sem_repetir_nome(self):
        ios = IosFalso([
            simulador("A", "iPhone 15", "iOS 17.5"), simulador("B", "iPhone 16 Pro", "iOS 18.2"),
            simulador("C", "iPhone 16 Pro", "iOS 17.5"), simulador("D", "iPad Air", "iOS 18.2"),
        ])
        alvos = self.servico(adb=AdbFalso(), ios=ios).summary()["targets"]
        self.assertEqual([a["id"] for a in alvos], ["B", "A", "D"])

    def test_plataforma_sem_ferramenta_nao_lista_alvos(self):
        class Explode:
            def list_all_simulators(self):
                raise AssertionError("não devia listar simuladores sem Xcode")

        resumo = self.servico(resultado_setup(xcode="error"), ios=Explode()).summary()
        self.assertTrue(all(a["platform"] != "ios" for a in resumo["targets"]))


class TestRecentes(Base):
    def test_mais_recente_primeiro_e_mesmo_caminho_sobe(self):
        relogio = iter(range(1, 100))
        store = RecentStore(self.pasta / "r.json", clock=lambda: float(next(relogio)) + 1_000_000)
        store.record("report", "Relatório · A", "1 divergência", "/a.json")
        store.record("page_object", "home.py", "Page Object", "/home.py")
        store.record("report", "Relatório · A", "exportado", "/a.json")
        itens = store.items()
        self.assertEqual([i["path"] for i in itens], ["/a.json", "/home.py"])
        self.assertEqual(itens[0]["subtitle"], "exportado")

    def test_guarda_no_maximo_vinte(self):
        relogio = iter(range(1, 100))
        store = RecentStore(self.pasta / "r.json", clock=lambda: float(next(relogio)) + 1_000_000)
        for n in range(RECENT_MAX + 5):
            store.record("maestro", f"f{n}.yaml", "Flow", f"/f{n}.yaml")
        itens = store.items()
        self.assertEqual(len(itens), RECENT_MAX)
        self.assertEqual(itens[0]["path"], f"/f{RECENT_MAX + 4}.yaml")

    def test_mais_velho_que_trinta_dias_some(self):
        agora = [1_000_000.0]
        store = RecentStore(self.pasta / "r.json", clock=lambda: agora[0])
        store.record("report", "Relatório", "", "/velho.json")
        agora[0] += RECENT_MAX_AGE_S + 1
        self.assertEqual(store.items(), [])

    def test_esquecer_tira_o_item(self):
        self.recentes.record("report", "Relatório", "", "/sumiu.json")
        self.assertTrue(self.recentes.forget("/sumiu.json"))
        self.assertFalse(self.recentes.forget("/sumiu.json"))
        self.assertEqual(self.recentes.items(), [])

    def test_arquivo_estragado_recomeca_vazio(self):
        caminho = self.pasta / "estragado.json"
        caminho.write_text("{não é json", encoding="utf-8")
        store = RecentStore(caminho)
        self.assertEqual(store.items(), [])
        store.record("report", "R", "", "/r.json")
        self.assertEqual(json.loads(caminho.read_text(encoding="utf-8"))["items"][0]["path"], "/r.json")

    def test_tipo_desconhecido_e_recusado(self):
        with self.assertRaises(ValueError):
            self.recentes.record("planilha", "x", "", "/x")

    def test_resumo_nao_confere_se_o_arquivo_existe(self):
        # Conferir o caminho em ~/Documents faria o macOS pedir acesso à pasta.
        self.recentes.record("report", "Relatório", "", "/caminho/que/nao/existe.json")
        self.assertEqual(len(self.servico().summary()["recent"]), 1)


class TestNovidades(Base):
    CHANGELOG = """# Changelog

## [3.11.0] - 2026-10-24

### Adicionado

- **Tela Início nova.** Boas-vindas, aparelho e recentes.
- **Tela Ambiente.** O diagnóstico, à parte.
- Item sem título. Segunda frase que não entra.

### Corrigido

- **Uma correção.** Texto.
- **Outra correção.** Texto.

## [3.10.0] - 2026-10-23

- **Antiga.** Não aparece.
"""

    def test_titulos_da_versao_instalada_ate_quatro(self):
        novidades = whats_new(self.CHANGELOG, "3.11.0")
        self.assertEqual(novidades, {"version": "3.11.0", "items": [
            "Tela Início nova", "Tela Ambiente", "Item sem título", "Uma correção",
        ]})

    def test_versao_sem_secao_nao_mostra_nada(self):
        self.assertIsNone(whats_new(self.CHANGELOG, "9.9.9"))

    def test_resumo_le_o_changelog_ao_lado_do_motor(self):
        caminho = self.pasta / "CHANGELOG.md"
        caminho.write_text(self.CHANGELOG, encoding="utf-8")
        self.assertEqual(self.servico(changelog=caminho).summary()["whats_new"]["version"], "3.11.0")
        self.assertIsNone(self.servico(changelog=None).summary()["whats_new"])


if __name__ == "__main__":
    unittest.main()
