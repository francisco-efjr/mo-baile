import XCTest
@testable import MoBaile

/// Trilha de desempenho (PERF-1 a PERF-5): janela oculta, sinais do Mac,
/// perfil vindo do motor e o freio local da parte visual.
@MainActor
final class PerfTests: XCTestCase {

    private func sessao() throws -> (AppState, FakeEngine, EngineSession) {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        return (estado, motor, EngineSession(state: estado, client: motor))
    }

    // MARK: - PERF-1: janela oculta

    func testJanelaOcultaPausaOEspelhoEVoltarRetoma() async throws {
        let (_, motor, sessao) = try sessao()

        await sessao.setWindowVisible(false, pauseDelayNanoseconds: 0)
        var chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.filter { $0 == "stream.pause" }.count, 1, "\(chamadas)")

        await sessao.setWindowVisible(true)
        chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.last, "stream.resume", "\(chamadas)")
    }

    func testAlternarRapidoNaoPausa() async throws {
        let (_, motor, sessao) = try sessao()

        let oculta = Task { await sessao.setWindowVisible(false, pauseDelayNanoseconds: 2_000_000_000) }
        await Task.yield()
        await sessao.setWindowVisible(true)
        await oculta.value

        let chamadas = await motor.chamadas
        XCTAssertFalse(chamadas.contains("stream.pause"), "voltou antes do prazo: nada a pausar. \(chamadas)")
        XCTAssertFalse(chamadas.contains("stream.resume"), "\(chamadas)")
    }

    func testTelaEstavelComJanelaOcultaReleHierarquiaSoAoVoltar() async throws {
        let (_, motor, sessao) = try sessao()
        await sessao.setWindowVisible(false, pauseDelayNanoseconds: 0)

        await sessao.handle(EngineNotification(method: "stream.settled", payload: Data(#"{"params":{}}"#.utf8)))
        try await Task.sleep(nanoseconds: 300_000_000)
        var chamadas = await motor.chamadas
        XCTAssertFalse(chamadas.contains("hierarchy.dump"), "janela oculta não relê a árvore: \(chamadas)")

        await sessao.setWindowVisible(true)
        try await Task.sleep(nanoseconds: 300_000_000)
        chamadas = await motor.chamadas
        XCTAssertTrue(chamadas.contains("hierarchy.dump"), "ao voltar, relê a árvore que ficou para trás: \(chamadas)")
    }
}
