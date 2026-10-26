import XCTest
@testable import MoBaile

/// Listas da interface com teto (MEL-6).
///
/// O corte de `analyticsEvents` só rodava em `proxy.event`: numa sessão só de
/// analytics a tabela crescia sem fim. E o log da execução não tinha teto.
@MainActor
final class ListasComTetoTests: XCTestCase {

    private func notificacao(_ metodo: String, _ params: String) -> EngineNotification {
        EngineNotification(method: metodo, payload: Data(#"{"jsonrpc":"2.0","method":"\#(metodo)","params":\#(params)}"#.utf8))
    }

    private func novaSessao() throws -> (AppState, EngineSession) {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        return (estado, EngineSession(state: estado, client: motor))
    }

    private func eventoDeAnalytics(_ id: Int) -> EngineNotification {
        notificacao("analytics.event", #"""
        {"id":\#(id),"time":"14:32:11.001","timestamp":1757030001.0,"platform":"android","tag":"FA","event_name":"e\#(id)","params":{},"raw_log":"Logging event: e\#(id)"}
        """#)
    }

    func testAnalyticsSemTrafegoDeRedeTambemTemTeto() async throws {
        let (estado, sessao) = try novaSessao()

        for id in 1...1001 {
            await sessao.handle(eventoDeAnalytics(id))
        }

        XCTAssertEqual(estado.analyticsEvents.count, 1000)
        // Sai o mais antigo.
        XCTAssertEqual(estado.analyticsEvents.first?.eventName, "e2")
        XCTAssertEqual(estado.analyticsEvents.last?.eventName, "e1001")
    }

    func testLogDaExecucaoGuardaAsUltimas5000Linhas() async throws {
        let (estado, sessao) = try novaSessao()
        estado.runState = .running

        for numero in 1...5001 {
            await sessao.handle(notificacao("flow.log", #"{"line":"linha \#(numero)"}"#))
        }

        XCTAssertEqual(estado.runLog.count, 5000)
        XCTAssertEqual(estado.runLog.first?.message, "linha 2")
        XCTAssertEqual(estado.runLog.last?.message, "linha 5001")
    }
}
