import XCTest
import SwiftUI
@testable import MoBaile

final class ThemeTests: XCTestCase {

    func testTemaEscuroSegueODesignSystem() {
        let theme = PraiaDarkTheme()
        XCTAssertEqual(theme.name, "dark")
        XCTAssertEqual(theme.id, "praia_dark")
        XCTAssertTrue(theme.isDark)
        // tokens/colors.css, [data-theme="dark"]
        XCTAssertEqual(theme.bgWindow, Color(hex: "#24242C"))
        XCTAssertEqual(theme.bgContent, Color(hex: "#18181E"))
        XCTAssertEqual(theme.accentText, Color(hex: "#F389A9"))
    }

    func testTemaClaroSegueODesignSystem() {
        let light = PraiaLightTheme()
        XCTAssertEqual(light.id, "praia_light")
        XCTAssertFalse(light.isDark)
        XCTAssertEqual(light.bgWindow, Color(hex: "#ECECF1"))
        XCTAssertNotEqual(PraiaDarkTheme().bgWindow, light.bgWindow)
    }

    /// O destaque é o flamingo escurecido: o #F389A9 do ícone tem só 2,2:1
    /// com branco e não serve para fundo de botão nem para texto.
    func testDestaqueEOFlamingoEscurecido() {
        XCTAssertEqual(PraiaLightTheme().accent, Color(hex: "#C2456E"))
        XCTAssertEqual(PraiaDarkTheme().accent, Color(hex: "#C2456E"))
        XCTAssertNotEqual(PraiaLightTheme().accent, Color(hex: "#F389A9"))
    }

    /// Aumentar contraste troca rótulos, separadores e destaque.
    func testAumentarContrasteReforcaRotulosEDestaque() {
        let normal = PraiaLightTheme()
        let forte = PraiaLightTheme(highContrast: true)
        XCTAssertTrue(forte.highContrast)
        XCTAssertNotEqual(normal.labelSecondary, forte.labelSecondary)
        XCTAssertNotEqual(normal.separator, forte.separator)
        XCTAssertEqual(forte.accent, Color(hex: "#A8365C"))
        XCTAssertEqual(PraiaDarkTheme(highContrast: true).accent, Color(hex: "#D9567F"))
        XCTAssertEqual(PraiaDarkTheme(highContrast: true).labelPrimary, Color.white)
    }

    func testPlatformIdentity() {
        // iOS #0A84FF
        XCTAssertEqual(PlatformIdentity.ios, Color(hex: "#0A84FF"))
        XCTAssertEqual(PlatformIdentity.android, Color(hex: "#34C759"))
    }

    func testCoresDeMetodoEStatusHTTP() {
        let theme = PraiaLightTheme()
        XCTAssertEqual(theme.methodColor("get"), theme.httpGet)
        XCTAssertEqual(theme.methodColor("PATCH"), theme.httpPost)
        XCTAssertEqual(theme.methodColor("CONNECT"), theme.httpConnect)
        XCTAssertEqual(theme.statusColor(nil), theme.labelTertiary)
        XCTAssertEqual(theme.statusColor(201), theme.status2xx)
        XCTAssertEqual(theme.statusColor(304), theme.status3xx)
        XCTAssertEqual(theme.statusColor(422), theme.status4xx)
    }

    @MainActor
    func testThemeManagerDefaults() {
        let defaults = UserDefaults(suiteName: "mobaile.testes.\(UUID().uuidString)")!
        let manager = ThemeManager(defaults: defaults)
        XCTAssertEqual(manager.mode, .system)
        XCTAssertNil(manager.preferredColorScheme)
    }

    /// A aparência escolhida em Ajustes sobrevive a fechar e abrir o app.
    @MainActor
    func testThemeManagerGuardaAAparencia() {
        let suite = "mobaile.testes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = ThemeManager(defaults: defaults)
        manager.setMode(.dark)
        XCTAssertTrue(manager.isDark)
        XCTAssertEqual(manager.preferredColorScheme, .dark)

        let reaberto = ThemeManager(defaults: defaults)
        XCTAssertEqual(reaberto.mode, .dark)
        XCTAssertTrue(reaberto.isDark)
    }
}
