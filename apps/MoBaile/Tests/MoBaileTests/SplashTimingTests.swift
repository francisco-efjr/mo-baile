import XCTest
@testable import MoBaile

/// Splash de abertura: fica até o app estar pronto, com mínimo e teto.
///
/// Defeito que cobre: o splash saía em 1,5 s fixos, antes de o motor terminar
/// de subir, e a janela aparecia ainda "Procurando…".
@MainActor
final class SplashTimingTests: XCTestCase {

    func testNaoSaiAntesDoMinimoMesmoPronto() {
        XCTAssertFalse(SplashTiming.shouldClose(elapsed: 1.0, phase: .ready, fraction: 1))
        XCTAssertTrue(SplashTiming.shouldClose(elapsed: SplashTiming.minimum, phase: .ready, fraction: 1))
    }

    func testEsperaOMotorEAVarreduraTerminarem() {
        XCTAssertFalse(SplashTiming.shouldClose(elapsed: 5, phase: .startingEngine, fraction: 0.45))
        XCTAssertFalse(SplashTiming.shouldClose(elapsed: 5, phase: .scanning, fraction: 0.88))
    }

    func testSoSaiComABarraCheia() {
        XCTAssertFalse(SplashTiming.shouldClose(elapsed: 5, phase: .ready, fraction: 0.6))
    }

    func testFalhaDoMotorLiberaAJanelaParaMostrarOErro() {
        XCTAssertTrue(SplashTiming.shouldClose(elapsed: SplashTiming.minimum, phase: .failed, fraction: 0.2))
    }

    func testTetoNuncaPrende() {
        XCTAssertTrue(SplashTiming.shouldClose(elapsed: SplashTiming.maximum, phase: .scanning, fraction: 0.5))
    }

    func testBarraAndaAteOTetoDaFaseESoCompletaQuandoPronto() {
        var fracao = 0.0
        for _ in 0..<200 { fracao = SplashTiming.nextFraction(current: fracao, phase: .startingEngine) }
        XCTAssertEqual(fracao, SplashTiming.target(.startingEngine), accuracy: 0.0001)
        for _ in 0..<200 { fracao = SplashTiming.nextFraction(current: fracao, phase: .scanning) }
        XCTAssertLessThan(fracao, 1, "barra cheia antes de pronto mentiria")
        var passos = 0
        while fracao < 1 { fracao = SplashTiming.nextFraction(current: fracao, phase: .ready); passos += 1 }
        XCTAssertLessThanOrEqual(passos, 2, "pronto completa rápido")
    }

    func testFrasePorFase() {
        XCTAssertEqual(SplashTiming.message(.startingEngine), "Iniciando o motor…")
        XCTAssertEqual(SplashTiming.message(.scanning), "Procurando aparelhos e simuladores…")
    }

    // MARK: - Fase vinda da sessão

    func testFaseDaSessaoAcompanhaASubida() async throws {
        let estado = AppState()
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: try resultadosDasFixtures()))
        XCTAssertEqual(sessao.launchPhase, .scanning, "conectado, ainda sem varredura")
        await sessao.refreshEnvironment()
        XCTAssertEqual(sessao.launchPhase, .ready)
    }

    func testMotorQueNaoSobeViraFalha() async {
        let sessao = EngineSession(state: AppState()) { throw EngineError.engineNotFound("python3 não encontrado") }
        XCTAssertEqual(sessao.launchPhase, .startingEngine)
        await sessao.connect()
        XCTAssertEqual(sessao.launchPhase, .failed)
    }
}
