import XCTest
@testable import MoBaile

/// FLU-3: sem aparelho, um único próximo passo em destaque e textos naturais.
final class NoDeviceTests: XCTestCase {

    private typealias Card = NoDeviceRecommendation.Card

    func testPlataformaEmUsoComAcaoPendenteVence() {
        let ios = Card(pendingAction: "start_wda", enabled: true)
        let android = Card(pendingAction: "boot_avd", enabled: true)
        XCTAssertEqual(NoDeviceRecommendation.pick(activePlatform: .ios, ios: ios, android: android), .ios)
        XCTAssertEqual(NoDeviceRecommendation.pick(activePlatform: .android, ios: ios, android: android), .android)
    }

    func testSemAcaoNaPlataformaEmUsoRecomendaAOutra() {
        let ios = Card(pendingAction: nil, enabled: true)
        let android = Card(pendingAction: "boot_avd", enabled: true)
        XCTAssertEqual(NoDeviceRecommendation.pick(activePlatform: .ios, ios: ios, android: android), .android)
    }

    func testAcaoQueNaoPodeRodarNaoGanhaDestaque() {
        let ios = Card(pendingAction: "boot_simulator", enabled: false)
        let android = Card(pendingAction: nil, enabled: false)
        XCTAssertNil(NoDeviceRecommendation.pick(activePlatform: .ios, ios: ios, android: android),
                     "sem nada executável, nenhum botão fica em destaque")
    }

    func testUltimaVerificacaoEmPortugues() {
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let data = calendario.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 10, minute: 54, second: 55))!
        XCTAssertEqual(NoDeviceCopy.ultimaVerificacao(data, calendar: calendario), "Última verificação às 10:54")
        XCTAssertEqual(NoDeviceCopy.ultimaVerificacao(nil), "Procurando aparelhos…")
    }

    func testDetalheDoMotorSemAbreviacao() {
        XCTAssertEqual(DiagnosticCopy.natural("3 AVD(s) parados."), "3 emuladores Android (AVD) parados.")
        XCTAssertEqual(DiagnosticCopy.natural("1 AVD(s) parados."), "1 emulador Android (AVD) parado.")
        XCTAssertEqual(DiagnosticCopy.natural("2 AVD(s)"), "2 emuladores Android (AVD)")
        XCTAssertEqual(DiagnosticCopy.natural("1 conectado(s)"), "1 conectado")
        XCTAssertEqual(DiagnosticCopy.natural("Nenhum AVD criado. Crie um pelo Android Studio."),
                       "Nenhum emulador Android (AVD) criado. Crie um pelo Android Studio.")
        XCTAssertEqual(DiagnosticCopy.natural("xcrun disponivel"), "xcrun disponivel", "o resto passa intacto")
    }

    /// Nenhum dos textos antigos sobrou no código da tela.
    func testTextosAntigosSairamDaTela() throws {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "MoBaile" || !FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
            url.deleteLastPathComponent()
        }
        let fonte = try String(
            contentsOf: url.appendingPathComponent("Sources/MoBaile/Views/EmptyState/DiagnosticCard.swift"), encoding: .utf8
        )
        XCTAssertFalse(fonte.contains("\"Verificar de Novo\""))
        XCTAssertFalse(fonte.contains("último scan"))
        XCTAssertEqual(fonte.components(separatedBy: ".borderedProminent").count - 1, 1,
                       "um só ponto do código pinta o botão em destaque")
    }
}
