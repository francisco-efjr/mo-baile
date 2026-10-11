import XCTest
@testable import MoBaile

/// FLU-2: a faixa "Motor parado" segue o `engineStatus` da sessão, e o botão
/// Reiniciar Motor usa o ciclo de vida que já existe.
@MainActor
final class EngineStatusTests: XCTestCase {

    private let politicaRapida = EngineSession.RestartPolicy(delays: [0.01, 0.01, 0.01])

    /// Fábrica que aceita motores novos depois de criada: o teste precisa de
    /// um motor bom depois que a supervisão desiste.
    private final class Fabrica {
        var fila: [FakeEngine] = []
        var fabricados: [FakeEngine] = []
        var tentativas = 0

        func fazer() throws -> any EngineCalling {
            tentativas += 1
            guard !fila.isEmpty else { throw EngineError.engineNotFound("sem motor no teste") }
            let motor = fila.removeFirst()
            fabricados.append(motor)
            return motor
        }
    }

    private func novoMotor() throws -> FakeEngine {
        var respostas = try resultadosDasFixtures()
        respostas["engine.hello"] = Data("""
        {"protocol_version":2,"engine_version":"0.1.0","capabilities":[],"methods":{},"notifications":[]}
        """.utf8)
        return FakeEngine(respostas: respostas)
    }

    private func esperar(_ descricao: String, prazo: Double = 3, _ condicao: () -> Bool) async throws {
        let limite = Date().addingTimeInterval(prazo)
        while Date() < limite {
            if condicao() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("prazo estourado esperando: \(descricao)")
    }

    func testConteudoDaFaixaPorEstado() {
        XCTAssertNil(EngineStatusBanner.Conteudo(.running), "motor no ar: sem faixa")
        XCTAssertNil(EngineStatusBanner.Conteudo(.starting), "primeira subida: o splash cobre")
        let reiniciando = try? XCTUnwrap(EngineStatusBanner.Conteudo(.restarting("tentativa 1 de 3")))
        XCTAssertEqual(reiniciando?.reiniciando, true)
        let parado = EngineStatusBanner.Conteudo(.stopped("Python sem Pillow."))
        XCTAssertEqual(parado?.reiniciando, false)
        XCTAssertEqual(parado?.titulo, "O motor está parado")
        XCTAssertTrue(parado?.anuncio.contains("Python sem Pillow.") == true, "o VoiceOver ouve o motivo")
    }

    func testMotorQueNaoSobeFicaParadoComOMotivo() async {
        let sessao = EngineSession(state: AppState()) {
            throw EngineError.engineNotFound("Nenhum Python 3.10 com Pillow.")
        }
        XCTAssertEqual(sessao.engineStatus, .starting)
        await sessao.connect()
        guard case .stopped(let mensagem) = sessao.engineStatus else {
            return XCTFail("esperava parado, veio \(sessao.engineStatus)")
        }
        XCTAssertTrue(mensagem.contains("Python 3.10"), mensagem)
    }

    func testErroDeChamadaComMotorNoArNaoViraFaixa() async throws {
        let estado = AppState()
        let motor = FakeEngine(
            respostas: try resultadosDasFixtures(),
            erros: ["codegen.save": .engine(code: "io_error", message: "Disco cheio")]
        )
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.saveCode()
        XCTAssertEqual(sessao.lastError, "Disco cheio")
        XCTAssertEqual(sessao.engineStatus, .running, "erro de uma chamada não é motor parado")
    }

    /// A queda passa por "reiniciando"; esgotadas as tentativas, a faixa fica
    /// parada; o botão Reiniciar Motor sobe um motor novo e a faixa some.
    func testQuedaReinicioDesistenciaEReinicioManual() async throws {
        let estado = AppState()
        let fabrica = Fabrica()
        fabrica.fila = [try novoMotor()]
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()
        XCTAssertEqual(sessao.engineStatus, .running)

        await fabrica.fabricados[0].cair(status: 9)
        try await esperar("desistência") {
            if case .stopped = sessao.engineStatus { return true }
            return false
        }
        guard case .stopped(let mensagem) = sessao.engineStatus else { return XCTFail() }
        XCTAssertTrue(mensagem.contains("Reiniciar Motor"), "a mensagem aponta o botão: \(mensagem)")
        XCTAssertFalse(mensagem.contains("Feche e abra"), mensagem)
        XCTAssertFalse(sessao.isRecovering)

        fabrica.fila = [try novoMotor()]
        await sessao.restartEngine()
        XCTAssertEqual(sessao.engineStatus, .running)
        XCTAssertNil(sessao.lastError)
        await sessao.disconnect()
    }

    /// R-02: o Reiniciar Motor faz a sonda do Python rodar de novo.
    func testReinicioManualLimpaOCacheDaSonda() async {
        let caminho = "/teste/reinicio-\(UUID().uuidString)/python3"
        var rodadas = 0
        let sonda: (String) -> PythonProbe.Result = { _ in rodadas += 1; return .init(kind: .usable, version: "3.12.1") }
        _ = PythonProbe.cached(caminho, runner: sonda)
        let sessao = EngineSession(state: AppState()) { throw EngineError.engineNotFound("sem motor no teste") }
        await sessao.restartEngine()
        _ = PythonProbe.cached(caminho, runner: sonda)
        XCTAssertEqual(rodadas, 2, "o reinício manual não limpou o cache da sonda")
    }

    func testReinicioPedidoComMotorNoArTrocaOMotor() async throws {
        let fabrica = Fabrica()
        fabrica.fila = [try novoMotor(), try novoMotor()]
        let sessao = EngineSession(state: AppState(), restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()
        await sessao.restartEngine()
        XCTAssertEqual(fabrica.fabricados.count, 2)
        let primeiroParado = await fabrica.fabricados[0].parado
        XCTAssertTrue(primeiroParado, "o motor antigo foi parado, não abandonado")
        XCTAssertEqual(sessao.engineStatus, .running)
        await sessao.disconnect()
    }
}
