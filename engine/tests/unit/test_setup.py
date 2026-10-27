"""Checagem de instalação da tela Início (`setup.check`)."""

from __future__ import annotations

import unittest
from types import SimpleNamespace

from mobaile.services.setup import Probe, SetupService, format_report

PACOTES = {"Pillow": "11.3.0", "requests": "2.32.3"}


def _adb(disponivel=True, emulador=True):
    return SimpleNamespace(
        is_available=lambda: disponivel,
        adb_path="/opt/homebrew/bin/adb" if disponivel else "adb",
        emulator_path="/Users/qa/Library/Android/sdk/emulator/emulator" if emulador else None,
    )


def _appium(caminho="/opt/homebrew/bin/appium"):
    return SimpleNamespace(locate_appium=lambda: caminho)


def _scrcpy(disponivel=False):
    return SimpleNamespace(is_available=lambda: disponivel, scrcpy_path="/opt/homebrew/bin/scrcpy")


def _probe(binarios=("xcrun", "node", "swiftc"), xcode_completo=True, driver=True, modulos=()):
    arquivos = {}
    arquivos["/opt/homebrew/lib/node_modules/appium/package.json"] = '{"version": "2.11.0"}'
    if driver:
        arquivos["/Users/qa/.appium/node_modules/appium-xcuitest-driver/package.json"] = '{"version": "7.24.0"}'
    return Probe(
        which=lambda nome: f"/opt/homebrew/bin/{nome}" if nome in binarios else None,
        is_file=lambda caminho: xcode_completo and caminho.endswith("/usr/bin/simctl"),
        realpath=lambda c: "/opt/homebrew/lib/node_modules/appium/index.js" if c.endswith("/appium") else c,
        find_spec=lambda nome: object() if nome in modulos else None,
        version_of=PACOTES.get,
        read_text=arquivos.get,
        home="/Users/qa",
        environ={},
        python_version="3.12.7",
        python_path="/opt/homebrew/bin/python3",
    )


def _servico(adb=None, appium=None, scrcpy=None, probe=None, system="macos"):
    return SetupService(adb or _adb(), appium or _appium(), scrcpy or _scrcpy(), probe=probe or _probe(),
                        system=system)


def _componentes(resultado):
    return {c["id"]: c for g in resultado["groups"] for c in g["components"]}


def _area(resultado, area, plataforma):
    feature = next(f for f in resultado["features"] if f["id"] == area)
    return next(p for p in feature["platforms"] if p["platform"] == plataforma)


class TestSetupService(unittest.TestCase):
    def test_tudo_instalado_nao_deixa_pendencia(self):
        resultado = _servico().run()
        self.assertEqual(resultado["pending"], 0)
        self.assertIsNone(resultado["next_step"])
        self.assertEqual(_area(resultado, "page_objects", "ios")["state"], "ok")
        self.assertEqual(_area(resultado, "report", "any")["state"], "ok")

    def test_python_mostra_versao_caminho_e_pacotes(self):
        python = _componentes(_servico().run())["python"]
        self.assertEqual(python["label"], "Python 3.12.7")
        self.assertIn("/opt/homebrew/bin/python3", python["detail"])
        self.assertIn("Pillow 11.3.0", python["detail"])

    def test_maquina_zerada_conta_as_duas_plataformas(self):
        resultado = _servico(adb=_adb(disponivel=False, emulador=False), appium=_appium(None),
                             probe=_probe(binarios=())).run()
        componentes = _componentes(resultado)
        self.assertEqual(componentes["adb"]["state"], "error")
        self.assertEqual(componentes["adb"]["install"], "android")
        self.assertEqual(componentes["xcode"]["state"], "error")
        self.assertIsNotNone(componentes["xcode"]["link"], "o Xcode vem da App Store: a linha abre a página")
        # adb, Xcode e Appium: as duas plataformas contam, nenhuma está em uso.
        self.assertEqual(resultado["pending"], 3)
        self.assertEqual(_area(resultado, "page_objects", "android")["state"], "error")

    def test_quem_so_usa_android_nao_ve_o_ios_como_pendencia(self):
        resultado = _servico(appium=_appium(None), probe=_probe(binarios=("node",))).run()
        self.assertEqual(_componentes(resultado)["xcode"]["state"], "error")
        self.assertEqual(resultado["pending"], 0)
        self.assertIsNone(resultado["next_step"])

    def test_ios_em_uso_sem_driver_xcuitest_vira_proximo_passo(self):
        resultado = _servico(probe=_probe(driver=False)).run()
        appium = _componentes(resultado)["appium"]
        self.assertEqual(appium["state"], "error")
        self.assertIn("Appium 2.11.0", appium["detail"])
        self.assertEqual(resultado["pending"], 1)
        self.assertEqual(resultado["next_step"]["component"], "appium")
        self.assertEqual(resultado["next_step"]["install"], "appium")
        # O espelho do simulador funciona sem o Appium: a área fica parcial.
        self.assertEqual(_area(resultado, "page_objects", "ios")["state"], "warn")

    def test_so_command_line_tools_nao_bastam_para_o_simulador(self):
        xcode = _componentes(_servico(probe=_probe(xcode_completo=False)).run())["xcode"]
        self.assertEqual(xcode["state"], "error")
        self.assertIn("Command Line Tools", xcode["detail"])

    def test_appium_sem_node_no_path_avisa_que_nao_sobe(self):
        appium = _componentes(_servico(probe=_probe(binarios=("xcrun", "swiftc"))).run())["appium"]
        self.assertEqual(appium["state"], "warn")
        self.assertIn("Node.js", appium["detail"])

    def test_plataforma_em_uso_vem_primeiro_no_proximo_passo(self):
        servico = _servico(adb=_adb(disponivel=False), probe=_probe(driver=False))
        # Android e iOS em uso? Android não: sem adb nenhum obrigatório dele
        # está ok. Com o iOS em uso, só o Appium conta.
        self.assertEqual(servico.run("android")["next_step"]["component"], "appium")
        servico = _servico(adb=_adb(disponivel=False), appium=_appium(None), probe=_probe(binarios=()))
        self.assertEqual(servico.run("android")["next_step"]["component"], "adb")
        self.assertEqual(servico.run("ios")["next_step"]["component"], "xcode")

    def test_opcionais_nunca_entram_na_contagem(self):
        resultado = _servico(adb=_adb(emulador=False), scrcpy=_scrcpy(False), probe=_probe(modulos=())).run()
        componentes = _componentes(resultado)
        for opcional in ("emulator", "scrcpy", "pymobiledevice3", "quartz", "uiautomator2"):
            self.assertFalse(componentes[opcional]["required"], opcional)
            self.assertEqual(componentes[opcional]["state"], "off", opcional)
        self.assertEqual(resultado["pending"], 0)

    def test_rede_no_ios_depende_do_iphone_fisico(self):
        sem = _servico().run()
        self.assertEqual(_area(sem, "network", "ios")["state"], "warn")
        com = _servico(probe=_probe(modulos=("pymobiledevice3",))).run()
        self.assertEqual(_area(com, "network", "ios")["state"], "ok")

    def test_windows_nao_cobra_o_ios_e_lembra_do_driver_usb(self):
        resultado = _servico(system="windows", probe=_probe(binarios=())).run()
        componentes = _componentes(resultado)
        self.assertEqual(componentes["xcode"]["state"], "off")
        self.assertFalse(componentes["xcode"]["required"])
        self.assertIn("usb_driver", componentes)
        self.assertNotIn("appium", componentes)
        self.assertEqual(_area(resultado, "page_objects", "ios")["detail"], "precisa de um Mac")
        self.assertEqual(resultado["pending"], 0)

    def test_toda_linha_diz_o_que_e(self):
        for resultado in (_servico().run(), _servico(adb=_adb(False), probe=_probe(binarios=())).run()):
            for c in _componentes(resultado).values():
                self.assertTrue(c["detail"], c["id"])
                self.assertIn(c["state"], {"ok", "warn", "error", "off"})
                if c["state"] != "ok" and c["required"]:
                    self.assertTrue(c["install"] or c["link"], f"{c['id']} falta sem dizer como resolver")

    def test_relatorio_de_terminal(self):
        texto = format_report(_servico(probe=_probe(driver=False)).run())
        self.assertIn("[--] Appium com o driver XCUITest", texto)
        self.assertIn("Próximo passo: Appium com o driver XCUITest.", texto)
        self.assertIn("instalar-mac.sh", texto)


if __name__ == "__main__":
    unittest.main()
