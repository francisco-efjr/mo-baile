import XCTest
import SwiftUI
@testable import MoBaile

/// As paletas alternativas do Swift têm de ser as do design.
///
/// O teste lê `docs/design/paletas/palettes.css`, gerado pelo próprio design a
/// partir de `paletas-data.js`, e compara cada variável com o token
/// correspondente de `PaletteTheme`, na versão normal e na de alto contraste.
/// Se alguém mudar uma fórmula de um lado só, a diferença aparece aqui.
final class PaletteTests: XCTestCase {

    /// Variável CSS → token do tema.
    private static let mapa: [String: KeyPath<PaletteTheme, Color>] = [
        "--label-primary": \.labelPrimary, "--label-secondary": \.labelSecondary,
        "--label-tertiary": \.labelTertiary, "--label-quaternary": \.labelQuaternary,
        "--separator": \.separator, "--separator-strong": \.separatorStrong,
        "--fill-primary": \.fillPrimary, "--fill-secondary": \.fillSecondary,
        "--fill-tertiary": \.fillTertiary, "--fill-quaternary": \.fillQuaternary,
        "--bg-window": \.bgWindow, "--bg-sidebar-solid": \.bgSidebar, "--bg-content": \.bgContent,
        "--bg-content-alt": \.bgContentAlt, "--bg-group": \.bgGroup, "--bg-control": \.bgControl,
        "--bg-field": \.bgField, "--control-border": \.controlBorder, "--scrim": \.scrim,
        "--accent": \.accent, "--accent-hover": \.accentHover, "--accent-pressed": \.accentPressed,
        "--on-accent": \.onAccent, "--accent-text": \.accentText, "--accent-tint": \.accentTint,
        "--focus-ring": \.focusRing, "--selection": \.selection, "--selection-inactive": \.selectionInactive,
        "--selection-content": \.selectionContent, "--destructive": \.destructive,
        "--destructive-fill": \.destructiveFill, "--success": \.success, "--success-tint": \.successTint,
        "--warning": \.warning, "--warning-tint": \.warningTint, "--danger-tint": \.dangerTint,
        "--info": \.info, "--recording": \.recording, "--cat-1": \.cat1, "--cat-2": \.cat2, "--cat-3": \.cat3,
        "--chip-button": \.chipButton, "--status-2xx": \.status2xx, "--status-3xx": \.status3xx,
        "--status-4xx": \.status4xx, "--http-delete": \.httpDelete,
    ]

    /// No bloco de alto contraste, `--bg-sidebar` é a cor sólida.
    private static let mapaAltoContraste: [String: KeyPath<PaletteTheme, Color>] = {
        var m = mapa
        m["--bg-sidebar"] = \.bgSidebar
        return m
    }()

    private func css() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" && !FileManager.default.fileExists(atPath: url.appendingPathComponent("VERSION").path) {
            url.deleteLastPathComponent()
        }
        return try String(contentsOf: url.appendingPathComponent("docs/design/paletas/palettes.css"), encoding: .utf8)
    }

    /// Variáveis de um bloco `seletor{ ... }`.
    private func bloco(_ seletor: String, em texto: String) throws -> [String: String] {
        let inicio = try XCTUnwrap(texto.range(of: seletor + "{"), "bloco \(seletor) ausente")
        let fim = try XCTUnwrap(texto.range(of: "}", range: inicio.upperBound..<texto.endIndex))
        var vars: [String: String] = [:]
        for linha in texto[inicio.upperBound..<fim.lowerBound].split(separator: "\n") {
            let partes = linha.split(separator: ":", maxSplits: 1)
            guard partes.count == 2 else { continue }
            vars[partes[0].trimmingCharacters(in: .whitespaces)] =
                partes[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        }
        return vars
    }

    private func cor(_ valor: String) throws -> Color {
        if valor.hasPrefix("#") { return Color(hex: valor) }
        let numeros = valor.replacingOccurrences(of: "rgba(", with: "").replacingOccurrences(of: ")", with: "")
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(numeros.count, 4, "cor CSS inesperada: \(valor)")
        return Color(r: numeros[0], g: numeros[1], b: numeros[2], numeros[3])
    }

    func testTokensBatemComPalettesCSS() throws {
        let texto = try css()
        XCTAssertEqual(PaletteSpec.all.count, 9)
        for spec in PaletteSpec.all {
            let normal = PaletteTheme(spec: spec)
            let vars = try bloco("[data-palette=\"\(spec.id)\"]", em: texto)
            for (nome, valor) in vars {
                guard let token = Self.mapa[nome] else { continue }
                XCTAssertEqual(normal[keyPath: token], try cor(valor), "\(spec.id) \(nome) = \(valor)")
            }
            XCTAssertGreaterThanOrEqual(vars.keys.filter { Self.mapa[$0] != nil }.count, 45, "\(spec.id): variáveis faltando")

            let forte = PaletteTheme(spec: spec, highContrast: true)
            let seletorHC = "[data-palette=\"\(spec.id)\"][data-contrast=\"high\"]" + (spec.isDark ? "[data-theme=\"dark\"]" : "")
            let varsHC = try bloco(seletorHC, em: texto)
            XCTAssertEqual(varsHC.count, 10, "\(spec.id): bloco de alto contraste incompleto")
            for (nome, valor) in varsHC {
                let token = try XCTUnwrap(Self.mapaAltoContraste[nome], "\(nome) sem token")
                XCTAssertEqual(forte[keyPath: token], try cor(valor), "\(spec.id) alto contraste \(nome) = \(valor)")
            }
        }
    }

    /// O design afirma que toda paleta passa nas checagens. Se uma cor mudar e
    /// derrubar um contraste, o teste diz qual.
    func testTodasAsPaletasPassamNasChecagens() {
        for spec in PaletteSpec.all + [PaletteSpec.praiaDisplay] {
            XCTAssertEqual(spec.checks.count, 8)
            for check in spec.checks {
                XCTAssertTrue(check.ok, "\(spec.name): \(check.name) \(check.label) abaixo de \(check.minimum)")
            }
        }
    }

    func testContrasteWCAG() {
        XCTAssertEqual(PaletteMath.contrast([0, 0, 0], [255, 255, 255]), 21, accuracy: 0.01)
        XCTAssertEqual(PaletteMath.contrast([255, 255, 255], [255, 255, 255]), 1, accuracy: 0.001)
        XCTAssertEqual(PaletteMath.mix("#8E4A63", "#000000", 0.16), "#773E53")
    }

    func testOQueAPaletaNaoDeclaraVemDaPraia() {
        let escura = PaletteTheme(spec: PaletteSpec.find("dirand")!)
        XCTAssertTrue(escura.isDark)
        XCTAssertEqual(escura.syntaxKeyword, PraiaDarkTheme().syntaxKeyword)
        XCTAssertEqual(escura.bgTerminal, PraiaDarkTheme().bgTerminal)
        let clara = PaletteTheme(spec: PaletteSpec.find("salvia")!)
        XCTAssertEqual(clara.httpGet, PraiaLightTheme().httpGet)
    }

    // MARK: - Escolha da paleta

    @MainActor
    private func gerente() -> (ThemeManager, UserDefaults, String) {
        let suite = "mobaile.testes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (ThemeManager(defaults: defaults), defaults, suite)
    }

    /// A paleta define a aparência: escura deixa o app escuro mesmo com
    /// Aparência em Claro; voltar para a Praia devolve a escolha da Aparência.
    @MainActor
    func testPaletaDefineAAparencia() {
        let (manager, defaults, suite) = gerente()
        defer { defaults.removePersistentDomain(forName: suite) }

        manager.setMode(.light)
        manager.setPalette("wearstler")
        XCTAssertTrue(manager.isDark)
        XCTAssertEqual(manager.preferredColorScheme, .dark)
        XCTAssertEqual(manager.current.accent, Color(hex: "#B4532F"))

        manager.setPalette("mahdavi")
        XCTAssertFalse(manager.isDark)
        XCTAssertEqual(manager.preferredColorScheme, .light)

        manager.setPalette(PaletteSpec.praiaID)
        XCTAssertNil(manager.palette)
        XCTAssertEqual(manager.preferredColorScheme, .light)
        XCTAssertEqual(manager.current.accent, Color(hex: "#C2456E"))
    }

    @MainActor
    func testPaletaSobreviveAReabrirOApp() {
        let (manager, defaults, suite) = gerente()
        defer { defaults.removePersistentDomain(forName: suite) }
        manager.setPalette("garcia")

        let reaberto = ThemeManager(defaults: defaults)
        XCTAssertEqual(reaberto.paletteID, "garcia")
        XCTAssertEqual(reaberto.current.onAccent, Color(hex: "#24170E"))
    }

    @MainActor
    func testPaletaDesconhecidaVoltaParaAPraia() {
        let (manager, defaults, suite) = gerente()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("nao-existe", forKey: ThemeManager.paletteKey)
        XCTAssertEqual(ThemeManager(defaults: defaults).paletteID, PaletteSpec.praiaID)
        manager.setPalette("nao-existe")
        XCTAssertEqual(manager.paletteID, PaletteSpec.praiaID)
    }

    @MainActor
    func testPreviaNaoMexeNosAjustes() {
        let tema = PaletteTheme(spec: PaletteSpec.find("hicks")!)
        let previa = ThemeManager(preview: tema)
        previa.setPalette("salvia")
        previa.setMode(.light)
        XCTAssertEqual(previa.current.id, tema.id)
        XCTAssertEqual(previa.preferredColorScheme, .dark)
    }
}
