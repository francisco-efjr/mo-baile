import XCTest
import SwiftUI
import AppKit
@testable import MoBaile

/// Liquid Glass (ADR 0006): o papel de cada vidro, o recuo no macOS 14 e 15,
/// Reduzir transparência e as regras de onde o vidro pode entrar.
///
/// O desenho do vidro só aparece na captura do servidor de janelas
/// (`WindowSnapshotTests`, com MOBAILE_SNAPSHOT_DIR); aqui fica o que dá para
/// provar sem tela.
final class GlassTests: XCTestCase {

    // MARK: - Papel → superfície

    func testMacOS26DesenhaVidroDoSistema() {
        XCTAssertEqual(GlassSurface.resolve(.flutuante, glassAvailable: true, reduceTransparency: false),
                       .glass(clear: false, interactive: false))
        XCTAssertEqual(GlassSurface.resolve(.capsula, glassAvailable: true, reduceTransparency: false, interactive: true),
                       .glass(clear: false, interactive: true))
    }

    func testVidroTransparenteSoSobreMidia() {
        for papel in GlassRole.allCases {
            let superficie = GlassSurface.resolve(papel, glassAvailable: true, reduceTransparency: false)
            XCTAssertEqual(superficie == .glass(clear: true, interactive: false), papel == .midia, "\(papel)")
        }
    }

    func testAntesDoMacOS26VoltaAoQueOAppJaDesenhava() {
        XCTAssertEqual(GlassSurface.resolve(.flutuante, glassAvailable: false, reduceTransparency: false), .material)
        XCTAssertEqual(GlassSurface.resolve(.capsula, glassAvailable: false, reduceTransparency: false), .fill)
        XCTAssertEqual(GlassSurface.resolve(.midia, glassAvailable: false, reduceTransparency: false), .fill)
    }

    func testReduzirTransparenciaViraSuperficieOpacaEmQualquerSistema() {
        for papel in GlassRole.allCases {
            for disponivel in [true, false] {
                XCTAssertEqual(GlassSurface.resolve(papel, glassAvailable: disponivel, reduceTransparency: true,
                                                    interactive: true), .solid, "\(papel), vidro: \(disponivel)")
            }
        }
    }

    func testBordaPropriaSoOndeOVidroDoSistemaNaoDesenha() {
        XCTAssertFalse(GlassSurface.glass(clear: false, interactive: false).drawsOwnEdge)
        XCTAssertFalse(GlassSurface.fill.drawsOwnEdge)
        XCTAssertTrue(GlassSurface.material.drawsOwnEdge)
        XCTAssertTrue(GlassSurface.solid.drawsOwnEdge)
    }

    func testSemVidroForcaOCaminhoAntigo() throws {
        // A suíte não define a variável; com ela, `available` é falso.
        guard ProcessInfo.processInfo.environment["MOBAILE_SEM_VIDRO"] == nil else {
            XCTAssertFalse(GlassSupport.available)
            return
        }
        if #available(macOS 26.0, *) {
            XCTAssertTrue(GlassSupport.available)
        } else {
            XCTAssertFalse(GlassSupport.available)
        }
    }

    // MARK: - Rótulo do Rodar

    /// O Rodar é vidro tingido com o destaque e rótulo `onAccent`. Na Costes o
    /// destaque é dourado: rótulo branco dava 2,1:1.
    func testRotuloDoRodarLegivelSobreODestaqueDeTodaPaleta() throws {
        var temas: [(String, any ThemeTokens)] = []
        for alto in [false, true] {
            temas.append(("Praia clara", PraiaLightTheme(highContrast: alto)))
            temas.append(("Praia escura", PraiaDarkTheme(highContrast: alto)))
            for spec in PaletteSpec.all { temas.append((spec.name, PaletteTheme(spec: spec, highContrast: alto))) }
        }
        for (nome, tema) in temas {
            let rotulo = try XCTUnwrap(NSColor(tema.onAccent).usingColorSpace(.sRGB))
            let fundo = try XCTUnwrap(NSColor(tema.accent).usingColorSpace(.sRGB))
            let rgb = { (c: NSColor) -> [Double] in [Double(c.redComponent) * 255, Double(c.greenComponent) * 255, Double(c.blueComponent) * 255] }
            let valor = PaletteMath.contrast(rgb(rotulo), rgb(fundo))
            XCTAssertGreaterThanOrEqual(valor, 4.5, "\(nome): onAccent sobre accent dá \(valor)")
        }
    }

    // MARK: - Onde o vidro entra (lê as fontes)

    private func fontes() throws -> [(nome: String, texto: String)] {
        var raiz = URL(fileURLWithPath: #filePath)
        while raiz.lastPathComponent != "MoBaile"
            || !FileManager.default.fileExists(atPath: raiz.appendingPathComponent("Package.swift").path) {
            guard raiz.path != "/" else { throw XCTSkip("Package.swift do app não encontrado") }
            raiz.deleteLastPathComponent()
        }
        let pasta = raiz.appendingPathComponent("Sources/MoBaile")
        let itens = try XCTUnwrap(FileManager.default.enumerator(at: pasta, includingPropertiesForKeys: nil))
        return try itens.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map {
            ($0.path.replacingOccurrences(of: pasta.path + "/", with: ""), try String(contentsOf: $0, encoding: .utf8))
        }
    }

    /// Código sem comentários, para a guarda não disparar em texto explicativo.
    private func semComentarios(_ texto: String) -> String {
        texto.split(separator: "\n", omittingEmptySubsequences: false)
            .map { linha in linha.range(of: "//").map { String(linha[..<$0.lowerBound]) } ?? String(linha) }
            .joined(separator: "\n")
    }

    /// As telas pedem um papel; quem fala com a API do macOS 26 é o design
    /// system e a toolbar (`ToolbarContent` não aceita modificador de View).
    func testSoODesignSystemEAToolbarFalamComOMacOS26() throws {
        let permitidos: Set = ["Views/DesignSystem/Glass.swift", "Views/MainWindow/UnifiedToolbar.swift"]
        let padroes = [
            #"#?(un)?available\([^)]*macOS 26"#, #"\.glass(Effect\w*|Prominent)?\b"#, #"\bGlass(EffectContainer)?\b"#,
            #"\b\w*Material\b"#, #"\.safeAreaBar\("#, #"sharedBackgroundVisibility"#, #"ToolbarSpacer"#,
            #"scrollEdgeEffect\w*"#, #"backgroundExtensionEffect"#,
        ]
        let regex = try padroes.map { try NSRegularExpression(pattern: $0) }
        for (nome, texto) in try fontes() where !permitidos.contains(nome) {
            let codigo = semComentarios(texto)
            for (padrao, re) in zip(padroes, regex) {
                let achou = re.firstMatch(in: codigo, range: NSRange(codigo.startIndex..., in: codigo)) != nil
                XCTAssertFalse(achou, "\(nome) casa \(padrao): peça um papel em Glass.swift")
            }
        }
    }

    /// Barra lateral, popovers e sheets já são vidro do sistema: vidro dentro
    /// deles seria vidro sobre vidro.
    func testNadaDeVidroDentroDoVidroDoSistema() throws {
        let fontes = Dictionary(uniqueKeysWithValues: try fontes().map { ($0.nome, $0.texto) })
        let dentroDoVidro = [
            "Views/MainWindow/AppSidebar.swift",            // barra lateral
            "Views/Mirror/MirrorRefreshButton.swift",       // popover da Correlação
            "Views/Network/TrafficDiagnosisView.swift",     // popover do diagnóstico
            "Views/Automation/StructureSheet.swift",        // sheets
            "Views/Automation/FlowRunnerSheet.swift",
            "Views/Report/ReportImportSheet.swift",
        ]
        for nome in dentroDoVidro {
            guard let texto = fontes[nome] else {
                XCTFail("\(nome) não existe: atualize a lista")
                continue
            }
            for termo in [".mbGlass(", ".mbProminentGlassButton("] {
                XCTAssertFalse(semComentarios(texto).contains(termo), "\(nome) já está dentro do vidro do sistema")
            }
        }
    }

    /// O splash abre num `NSHostingView` sem `ThemeManager` no ambiente: o vidro
    /// não pode exigir o tema, senão o app cai na abertura.
    @MainActor
    func testSplashSemTemaNoAmbienteNaoCai() {
        let splash = NSHostingView(rootView: SplashView(progress: SplashProgress(message: "Abrindo…", fraction: 0.4)))
        splash.frame = NSRect(x: 0, y: 0, width: 640, height: 380)
        splash.layoutSubtreeIfNeeded()
        let capsula = NSHostingView(rootView: Text("x").padding(4).mbGlass(.capsula, in: Capsule(), highlighted: true))
        capsula.frame = NSRect(x: 0, y: 0, width: 80, height: 30)
        capsula.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(splash.fittingSize.width, 0)
        XCTAssertGreaterThan(capsula.fittingSize.width, 0)
    }

    func testSuperficiesDoRedesenhoUsamOVidro() throws {
        let fontes = Dictionary(uniqueKeysWithValues: try fontes().map { ($0.nome, $0.texto) })
        let esperado: [(String, String)] = [
            ("Views/CommandPalette/CommandPaletteView.swift", ".mbGlass(.flutuante"),
            ("Views/CommandPalette/CommandPaletteView.swift", ".mbGlassTransition()"),
            ("Views/Home/HomeDaily.swift", ".mbGlass(.capsula"),
            ("Views/Splash/SplashWindow.swift", ".mbGlass(.midia"),
            ("Views/MainWindow/UnifiedToolbar.swift", ".mbProminentGlassButton("),
            ("Views/MainWindow/UnifiedToolbar.swift", ".sharedBackgroundVisibility(.hidden)"),
            ("Views/MainWindow/AppSidebar.swift", ".mbBottomBar {"),
            ("Views/DesignSystem/Glass.swift", ".foregroundStyle(tingido ? theme.onAccent"),
        ]
        for (nome, termo) in esperado {
            XCTAssertTrue(fontes[nome]?.contains(termo) == true, "\(nome) deveria usar \(termo)")
        }
    }
}
