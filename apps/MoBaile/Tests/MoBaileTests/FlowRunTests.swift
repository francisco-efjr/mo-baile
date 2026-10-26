import XCTest
@testable import MoBaile

/// Andamento e parada da execução de fluxo (MEL-3).
///
/// Antes o destaque só andava quando uma linha de `flow.log` casava
/// `passo N`, o que só acontecia na linha de falha; e parar virava "FAIL",
/// porque `flow.finished` não distinguia parada de falha.
@MainActor
final class FlowRunTests: XCTestCase {

    private func notificacao(_ metodo: String, _ params: String) -> EngineNotification {
        EngineNotification(method: metodo, payload: Data(#"{"jsonrpc":"2.0","method":"\#(metodo)","params":\#(params)}"#.utf8))
    }

    private func novaSessao() throws -> (AppState, EngineSession, FakeEngine) {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        return (estado, EngineSession(state: estado, client: motor), motor)
    }

    // MARK: - flow.step

    func testFlowStepMoveOPassoAtualEGuardaOTotal() async throws {
        let (estado, sessao, _) = try novaSessao()
        estado.runState = .running

        await sessao.handle(notificacao("flow.step", #"{"index":2,"total":3}"#))

        XCTAssertEqual(estado.currentRunStep, 2)
        XCTAssertEqual(estado.runStepTotal, 3)
        XCTAssertEqual(estado.runState, .running)
    }

    /// A regex `passo N` saiu: só `flow.step` move o destaque.
    func testLinhaDeLogQueCitaPassoNaoMoveODestaque() async throws {
        let (estado, sessao, _) = try novaSessao()
        estado.runState = .running

        await sessao.handle(notificacao("flow.log", #"{"line":"[10:00:00] ❌ FALHA no passo 4 (BOTAO). Interrompendo automação."}"#))

        XCTAssertEqual(estado.currentRunStep, 0)
        XCTAssertEqual(estado.runLog.count, 1)
    }

    // MARK: - flow.finished

    func testFimCanceladoVoltaAoOciosoComLinhaStop() async throws {
        let (estado, sessao, _) = try novaSessao()
        estado.runState = .running

        await sessao.handle(notificacao("flow.finished", #"{"success":false,"message":"Automação cancelada.","cancelled":true}"#))

        XCTAssertEqual(estado.runState, .idle)
        XCTAssertEqual(estado.runLog.last?.prefix, "STOP")
        XCTAssertFalse(estado.runLog.contains { $0.prefix == "FAIL" }, "parar virou falha")
    }

    func testFimComFalhaContinuaFalha() async throws {
        let (estado, sessao, _) = try novaSessao()
        estado.runState = .running

        await sessao.handle(notificacao("flow.finished", #"{"success":false,"message":"Automação falhou (código de saída: 1).","cancelled":false}"#))

        XCTAssertEqual(estado.runState, .failed)
        XCTAssertEqual(estado.runLog.last?.prefix, "FAIL")
    }

    /// Motor anterior à 3.12.0, sem `cancelled`: falha continua falha.
    func testFimSemCancelledDeMotorAntigoContinuaFalha() async throws {
        let (estado, sessao, _) = try novaSessao()
        estado.runState = .running

        await sessao.handle(notificacao("flow.finished", #"{"success":false,"message":"falhou"}"#))

        XCTAssertEqual(estado.runState, .failed)
    }

    func testFimComSucessoPassa() async throws {
        let (estado, sessao, _) = try novaSessao()
        estado.runState = .running

        await sessao.handle(notificacao("flow.finished", #"{"success":true,"message":"ok","cancelled":false}"#))

        XCTAssertEqual(estado.runState, .passed)
        XCTAssertEqual(estado.runLog.last?.prefix, "PASS")
    }

    // MARK: - Origem da execução

    func testOrigemDaExecucaoAcompanhaOMetodoEZeraOTotal() async throws {
        let (estado, sessao, _) = try novaSessao()
        estado.steps = [
            AutomationStep(stepNum: 1, actionType: "click", varName: "BOTAO_1", elementName: "Entrar",
                           className: "android.widget.Button", strategy: .id, locatorValue: "x", coords: nil,
                           inputText: nil, package: "", platform: .android, recordedAt: nil)
        ]
        estado.runStepTotal = 9

        await sessao.runMaestroFlow(at: URL(fileURLWithPath: "/tmp/flow.yaml"))
        XCTAssertEqual(estado.runSource, .maestro)
        XCTAssertEqual(estado.runStepTotal, 0)

        estado.runStepTotal = 9
        await sessao.runFlow()
        XCTAssertEqual(estado.runSource, .recordedSteps)
        XCTAssertEqual(estado.runStepTotal, 0)
    }

    // MARK: - Contas do sheet

    func testTotalVemDoFlowStepQuandoChega() {
        let progresso = FlowRunProgress(runState: .running, currentStep: 2, reportedTotal: 5,
                                        source: .recordedSteps, recordedCount: 3)
        XCTAssertEqual(progresso.total, 5)
        XCTAssertEqual(progresso.approved, 1)
        XCTAssertEqual(progresso.currentDisplay, 2)
    }

    func testAntesDoPrimeiroFlowStepOTotalEOsPassosGravados() {
        let progresso = FlowRunProgress(runState: .running, currentStep: 0, reportedTotal: 0,
                                        source: .recordedSteps, recordedCount: 3)
        XCTAssertEqual(progresso.total, 3)
        XCTAssertEqual(progresso.fraction, 0)
    }

    /// No flow do Maestro a lista de passos gravados não tem relação com o
    /// que roda: não ganha destaque, só o `i/total`.
    func testMaestroNaoDestacaPassosGravados() {
        let progresso = FlowRunProgress(runState: .running, currentStep: 2, reportedTotal: 4,
                                        source: .maestro, recordedCount: 3)
        XCTAssertEqual(progresso.total, 4)
        XCTAssertEqual(progresso.currentDisplay, 2)
        for numero in 1...3 {
            XCTAssertEqual(progresso.estado(doPassoGravado: numero), .pendente)
        }
        let concluido = FlowRunProgress(runState: .passed, currentStep: 4, reportedTotal: 4,
                                        source: .maestro, recordedCount: 3)
        XCTAssertEqual(concluido.estado(doPassoGravado: 1), .pendente)
        XCTAssertEqual(concluido.approved, 4)
    }

    func testFlowRunDestacaOPassoAtual() {
        let progresso = FlowRunProgress(runState: .running, currentStep: 2, reportedTotal: 3,
                                        source: .recordedSteps, recordedCount: 3)
        XCTAssertEqual(progresso.estado(doPassoGravado: 1), .ok)
        XCTAssertEqual(progresso.estado(doPassoGravado: 2), .rodando)
        XCTAssertEqual(progresso.estado(doPassoGravado: 3), .pendente)
    }

    /// Parada (D-A): ocioso, sem passo marcado como falho.
    func testParadaNaoMarcaPassoComoFalho() {
        let progresso = FlowRunProgress(runState: .idle, currentStep: 2, reportedTotal: 3,
                                        source: .recordedSteps, recordedCount: 3)
        XCTAssertEqual(progresso.estado(doPassoGravado: 1), .ok)
        XCTAssertEqual(progresso.estado(doPassoGravado: 2), .pendente)
        XCTAssertEqual(progresso.approved, 1)
    }
}
