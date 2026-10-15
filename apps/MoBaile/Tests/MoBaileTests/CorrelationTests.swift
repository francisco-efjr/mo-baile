import XCTest
@testable import MoBaile

/// F5: selecionar um passo pede `session.correlate` e filtra Rede e Analytics pela janela.
@MainActor
final class CorrelationTests: XCTestCase {
    private func passo(_ n: Int, hora: Date? = Date()) -> AutomationStep {
        AutomationStep(stepNum: n, actionType: "click", varName: "BOTAO_\(n)", elementName: "Entrar",
                       className: "android.widget.Button", strategy: .id, locatorValue: "x", coords: nil,
                       inputText: nil, package: "", platform: .android, recordedAt: hora)
    }

    private func requisicao(_ id: Int) -> NetworkEvent {
        NetworkEvent(id: id, timestamp: Date(), timeStr: "", method: "POST", url: "https://api/auth", host: "api",
                     path: "/auth", statusText: "", requestHeaders: [:], requestBody: "", responseHeaders: [:],
                     responseBody: "", protocol: "HTTP/1.1", isTunnel: false)
    }

    private func evento(_ id: Int) -> AnalyticsEvent {
        AnalyticsEvent(id: id, timestamp: Date(), timeStr: "", tag: "FA", eventName: "login", params: [:], rawLog: "",
                       platform: .android)
    }

    private let resposta = Data(#"{"step_num":2,"recorded_at":1757030000.0,"window":[1757029999.0,1757030004.0],"requests":[2,3],"events":[11],"probable":true}"#.utf8)

    func testCorrelacaoFiltraRedeEAnalyticsEMostrarTudoDesfaz() async {
        let estado = AppState()
        estado.steps = [passo(1), passo(2)]
        estado.httpRequests = [1, 2, 3, 4].map(requisicao)
        estado.analyticsEvents = [10, 11, 12].map(evento)
        let motor = FakeEngine(respostas: ["session.correlate": resposta])
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.correlate(step: estado.steps[1])

        XCTAssertEqual(estado.correlation?.stepNum, 2)
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [3, 2])
        XCTAssertEqual(estado.filteredAnalyticsEvents.map(\.id), [11])
        XCTAssertEqual(estado.correlatedStep?.stepNum, 2)
        XCTAssertEqual(CorrelationChip.texto(estado.correlation!, passo: estado.correlatedStep),
                       "Passo 2 · Entrar · 2 requisições · 1 evento")
        let params = await motor.chamadasComParametros.first { $0.0 == "session.correlate" }?.1
        XCTAssertEqual(params?["step_num"], .int(2))

        estado.clearCorrelation()
        XCTAssertEqual(estado.filteredHTTPRequests.count, 4)
        XCTAssertEqual(estado.filteredAnalyticsEvents.count, 3)
    }

    func testCorrelacaoSeCombinaComEscopoEBusca() async {
        let estado = AppState()
        estado.steps = [passo(1), passo(2)]
        estado.httpRequests = [1, 2, 3].map(requisicao)
        let motor = FakeEngine(respostas: ["session.correlate": resposta])
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.correlate(step: estado.steps[1])
        estado.httpFilterText = "metodo:GET"
        XCTAssertTrue(estado.filteredHTTPRequests.isEmpty, "a busca continua valendo dentro da janela")
        estado.httpFilterText = "metodo:POST"
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [3, 2])
    }

    func testErroDoMotorLimpaACorrelacao() async {
        let estado = AppState()
        estado.steps = [passo(1)]
        let motor = FakeEngine(respostas: [:], erros: ["session.correlate": .notRunning])
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.correlate(step: estado.steps[0])
        XCTAssertNil(estado.correlation)
    }

    func testLimparPassosLimpaACorrelacao() async {
        let estado = AppState()
        estado.steps = [passo(1), passo(2)]
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: ["session.correlate": resposta]))
        await sessao.correlate(step: estado.steps[1])
        estado.clearSteps()
        XCTAssertNil(estado.correlation)
    }

    func testPassoDaFixtureTrazRecordedAt() throws {
        let url = Bundle.module.url(forResource: "engine_payloads", withExtension: "json")!
        let todas = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: url))
        guard case let .object(resposta)? = todas["codegen.steps"], let result = resposta["result"] else {
            return XCTFail("fixture codegen.steps ausente")
        }
        let lista = try JSONDecoder().decode(EngineDTO.StepList.self, from: JSONEncoder().encode(result))
        XCTAssertNotNil(lista.steps.first?.toModel().recordedAt)
    }
}
