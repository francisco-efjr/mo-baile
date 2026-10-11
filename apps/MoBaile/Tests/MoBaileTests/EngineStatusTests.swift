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

    private func esperar(_ descricao: String, prazo: Double = 3, _ condicao: () async -> Bool) async throws {
        let limite = Date().addingTimeInterval(prazo)
        while Date() < limite {
            if await condicao() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("prazo estourado esperando: \(descricao)")
    }

    /// Motores fabricados que nem foram parados nem caíram.
    private func vivos(_ fabrica: Fabrica) async -> Int {
        var total = 0
        for motor in fabrica.fabricados {
            let parado = await motor.parado
            let caiu = await motor.caiu
            if !parado && !caiu { total += 1 }
        }
        return total
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

    /// Anota, de outra thread, onde a sonda rodou.
    private final class RegistroDaSonda: @unchecked Sendable {
        private let lock = NSLock()
        private var _naMain: Bool?
        var naMain: Bool? {
            get { lock.lock(); defer { lock.unlock() }; return _naMain }
            set { lock.lock(); _naMain = newValue; lock.unlock() }
        }
    }

    /// R-04: a sonda do Python (até 3 s por candidato) roda fora do MainActor.
    /// Com a sonda presa, este teste, que roda no MainActor, continua andando.
    func testSondaLentaNaoPrendeOMainActor() async throws {
        let liberar = DispatchSemaphore(value: 0)
        let registro = RegistroDaSonda()
        let comecou = expectation(description: "a sonda começou")
        let sessao = EngineSession(state: AppState(), restartPolicy: politicaRapida, resolve: {
            registro.naMain = Thread.isMainThread
            comecou.fulfill()
            // Prazo só para o teste não travar se a sonda vier para o MainActor.
            _ = liberar.wait(timeout: .now() + 5)
            throw EngineError.pythonUnsuitable("Python de teste sem Pillow.")
        })

        let conexao = Task { await sessao.connect() }
        await fulfillment(of: [comecou], timeout: 3)
        // A sonda está presa e o MainActor atende: a sessão responde na hora.
        XCTAssertEqual(sessao.engineStatus, .starting)
        XCTAssertEqual(registro.naMain, false, "a sonda rodou no MainActor")
        liberar.signal()
        await conexao.value

        guard case .stopped(let mensagem) = sessao.engineStatus else {
            return XCTFail("esperava parado, veio \(sessao.engineStatus)")
        }
        XCTAssertTrue(mensagem.contains("sem Pillow"), mensagem)
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

    // MARK: - R-03: reinício idempotente

    /// Duplo clique no botão da faixa, ou faixa e paleta juntas: um motor só.
    func testDoisReiniciosSeguidosDeixamUmMotorVivo() async throws {
        let fabrica = Fabrica()
        fabrica.fila = [try novoMotor(), try novoMotor(), try novoMotor()]
        let sessao = EngineSession(state: AppState(), restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()

        async let primeiro: Void = sessao.restartEngine()
        async let segundo: Void = sessao.restartEngine()
        _ = await (primeiro, segundo)

        XCTAssertEqual(fabrica.fabricados.count, 2, "o segundo reinício subiu outro motor")
        let vivosAgora = await vivos(fabrica)
        XCTAssertEqual(vivosAgora, 1)
        XCTAssertEqual(sessao.engineStatus, .running)
        await sessao.disconnect()
    }

    /// Durante o reinício manual a faixa mostra progresso e a paleta desabilita
    /// Reiniciar Motor, com o motivo.
    func testReinicioManualApareceComoReiniciando() async throws {
        let estado = AppState()
        let fabrica = Fabrica()
        let segundo = try novoMotor()
        fabrica.fila = [try novoMotor(), segundo]
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()

        await segundo.reter("engine.hello")
        let reinicio = Task { await sessao.restartEngine() }
        try await esperar("o reinício chegar ao hello") { await segundo.quantasRetidas("engine.hello") == 1 }

        XCTAssertTrue(sessao.isRestarting)
        let conteudo = try XCTUnwrap(EngineStatusBanner.Conteudo(sessao.engineStatus), "sem faixa no reinício manual")
        XCTAssertEqual(conteudo.tom, .reiniciando, "a faixa não oferece o botão durante o reinício")
        let contexto = CommandContext.current(estado, sessao, nil)
        XCTAssertEqual(CommandRegistry.command(.restartEngine, in: contexto)?.disabledReason, "O motor está reiniciando")

        await segundo.liberar("engine.hello")
        await reinicio.value
        XCTAssertFalse(sessao.isRestarting)
        XCTAssertEqual(sessao.engineStatus, .running)
        await sessao.disconnect()
    }

    /// Reinício pedido enquanto a supervisão sobe outro motor depois de uma
    /// queda: o motor da supervisão é descartado e sobra um só.
    func testReinicioDuranteARecuperacaoDeixaUmMotorVivo() async throws {
        let fabrica = Fabrica()
        let primeiro = try novoMotor()
        let daSupervisao = try novoMotor()
        fabrica.fila = [primeiro, daSupervisao, try novoMotor()]
        let sessao = EngineSession(state: AppState(), restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()

        await daSupervisao.reter("engine.hello")
        await primeiro.cair(status: 9)
        try await esperar("a supervisão chegar ao hello") { await daSupervisao.quantasRetidas("engine.hello") == 1 }
        XCTAssertTrue(sessao.isRecovering)

        let reinicio = Task { await sessao.restartEngine() }
        try await esperar("o reinício começar") { sessao.isRestarting && !sessao.isRecovering }
        await daSupervisao.liberar("engine.hello")
        await reinicio.value

        XCTAssertEqual(fabrica.fabricados.count, 3)
        let vivosAgora = await vivos(fabrica)
        XCTAssertEqual(vivosAgora, 1, "sobrou mais de um motor no ar")
        let supervisaoParada = await daSupervisao.parado
        XCTAssertTrue(supervisaoParada, "o motor da supervisão cancelada ficou órfão")
        XCTAssertEqual(sessao.engineStatus, .running)
        XCTAssertFalse(sessao.isRecovering)
        await sessao.disconnect()
    }

    /// Uma supervisão cancelada que termina depois não apaga a marca da
    /// supervisão nova (contador de geração).
    func testRecuperacaoAntigaNaoApagaAMarcaDaNova() async throws {
        let fabrica = Fabrica()
        let primeiro = try novoMotor()
        let segundo = try novoMotor()
        let terceiro = try novoMotor()
        fabrica.fila = [primeiro, segundo, terceiro]
        let sessao = EngineSession(state: AppState(), restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()

        // A supervisão A sobe o segundo motor e fica presa na restauração.
        await segundo.reter("devices.watch_start")
        await primeiro.cair(status: 9)
        try await esperar("A restaurar") { await segundo.quantasRetidas("devices.watch_start") == 1 }

        // O segundo cai durante a restauração: A é cancelada e B começa, presa no hello.
        await terceiro.reter("engine.hello")
        await segundo.cair(status: 9)
        try await esperar("B chegar ao hello") { await terceiro.quantasRetidas("engine.hello") == 1 }

        // A termina agora, já cancelada.
        await segundo.liberar("devices.watch_start")
        try await esperar("A terminar") { await segundo.quantasRetidas("devices.watch_start") == 0 }
        await Task.yield()
        XCTAssertTrue(sessao.isRecovering, "a supervisão antiga apagou a marca da nova")
        if case .restarting = sessao.engineStatus {} else { XCTFail("faixa deveria seguir reiniciando: \(sessao.engineStatus)") }

        await terceiro.liberar("engine.hello")
        try await esperar("B conectar") { sessao.engineStatus == .running }
        XCTAssertFalse(sessao.isRecovering)
        await sessao.disconnect()
    }
}
