import XCTest
@testable import MoBaile

/// F8: a resposta de `proxy.diagnose` decodifica (fixture real) e chega ao estado.
final class TrafficDiagnosisTests: XCTestCase {
    private func fixture(_ nome: String) throws -> Data {
        let url = Bundle.module.url(forResource: "engine_payloads", withExtension: "json")!
        let todas = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: url))
        guard case let .object(resposta)? = todas[nome], let result = resposta["result"] else {
            throw XCTSkip("fixture \(nome) sem result")
        }
        return try JSONEncoder().encode(result)
    }

    func testFixtureDoMotorDecodifica() throws {
        let d = try JSONDecoder().decode(EngineDTO.TrafficDiagnosis.self, from: fixture("proxy.diagnose"))
        XCTAssertFalse(d.proxyRunning)
        XCTAssertEqual(d.causes.first?.code, "proxy_stopped")
        XCTAssertFalse(d.summary.isEmpty)
        XCTAssertEqual(TrafficDiagnosisView.icone("proxy_stopped"), "power")
    }

    func testSemCausasResumoDizQueNadaApontaProblema() throws {
        let json = #"{"proxy_running":true,"device_configured":true,"netlog_running":false,"requests_total":3,"tunnels_total":1,"tunnels_failed":0,"last_event_age_s":2.5,"causes":[]}"#
        let d = try JSONDecoder().decode(EngineDTO.TrafficDiagnosis.self, from: Data(json.utf8))
        XCTAssertTrue(d.causes.isEmpty)
        XCTAssertTrue(d.summary.contains("3 requisições"))
    }

    @MainActor
    func testDiagnosticoChegaAoEstadoEAbreOPopover() async throws {
        let estado = AppState()
        let resposta = Data(#"{"proxy_running":false,"device_configured":null,"netlog_running":false,"requests_total":0,"tunnels_total":0,"tunnels_failed":0,"last_event_age_s":null,"causes":[{"code":"proxy_stopped","title":"O proxy está desligado","detail":"d","fix":"f"}]}"#.utf8)
        let motor = FakeEngine(respostas: ["proxy.diagnose": resposta])
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.diagnoseTraffic()
        XCTAssertEqual(estado.trafficDiagnosis?.causes.map(\.code), ["proxy_stopped"])
        XCTAssertTrue(estado.trafficDiagnosisPresented)
        XCTAssertEqual(estado.statusMessage, "O proxy está desligado")
    }
}
