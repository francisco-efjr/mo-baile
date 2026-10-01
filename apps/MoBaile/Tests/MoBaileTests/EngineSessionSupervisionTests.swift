import XCTest
@testable import MoBaile

/// Fabrica um motor falso por conexão, como o `EngineLocator` faz com o
/// processo de verdade: o reinício só é observável se cada subida entregar um
/// motor novo.
@MainActor
final class FabricaDeMotores {
    private var fila: [FakeEngine]
    private(set) var fabricados: [FakeEngine] = []
    private(set) var tentativas = 0

    init(_ motores: [FakeEngine]) {
        self.fila = motores
    }

    func fazer() throws -> any EngineCalling {
        tentativas += 1
        guard !fila.isEmpty else {
            throw EngineError.engineNotFound("o teste não preparou outro motor")
        }
        let motor = fila.removeFirst()
        fabricados.append(motor)
        return motor
    }
}

/// Handshake, progresso e supervisão da sessão, sem Python.
///
/// Cobre as garantias da Etapa 1 do lado da sessão: o `engine.hello` vem antes
/// de tudo, motor de outra versão não é usado, progresso chega à barra de
/// status e uma queda do motor é reparada sem o usuário reabrir o app.
@MainActor
final class EngineSessionSupervisionTests: XCTestCase {

    /// Esperas curtas: o teste mede o comportamento, não o relógio.
    private let politicaRapida = EngineSession.RestartPolicy(delays: [0.01, 0.01, 0.01])

    private func helloJSON(versao: Int = 2) -> Data {
        Data("""
        {"protocol_version":\(versao),"engine_version":"0.1.0",
         "capabilities":["cancel","progress","lanes"],
         "methods":{
           "engine.hello":{"lane":"inline","timeout_s":5,"progress":false},
           "hierarchy.dump":{"lane":"capture","timeout_s":60,"progress":true},
           "wda.start":{"lane":"environment","timeout_s":600,"progress":true}},
         "notifications":["stream.frame","$/progress"]}
        """.utf8)
    }

    private func novoMotor(helloVersao: Int = 2, erros: [String: EngineError] = [:]) throws -> FakeEngine {
        var respostas = try resultadosDasFixtures()
        respostas["engine.hello"] = helloJSON(versao: helloVersao)
        return FakeEngine(respostas: respostas, erros: erros)
    }

    private func notificacao(_ metodo: String, _ params: String) -> EngineNotification {
        EngineNotification(method: metodo, payload: Data(#"{"jsonrpc":"2.0","method":"\#(metodo)","params":\#(params)}"#.utf8))
    }

    /// Espera uma condição que depende de tarefas em segundo plano da sessão.
    private func esperar(
        _ descricao: String,
        prazo: Double = 3,
        _ condicao: () async -> Bool
    ) async throws {
        let limite = Date().addingTimeInterval(prazo)
        while Date() < limite {
            if await condicao() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("prazo estourado esperando: \(descricao)")
    }

    // MARK: - Handshake

    func testHelloEAPrimeiraChamadaEATabelaChegaAoCliente() async throws {
        let estado = AppState()
        let motor = try novoMotor()
        let fabrica = FabricaDeMotores([motor])
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }

        await sessao.connect()
        defer { Task { await sessao.disconnect() } }

        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.first, "engine.hello", "chamadas: \(chamadas)")
        let paramsHello = await motor.parametros(de: "engine.hello")
        let params = try XCTUnwrap(paramsHello)
        XCTAssertEqual(params["protocol_version"], .int(2))
        guard case .string(let cliente)? = params["client"] else {
            return XCTFail("client ausente no hello: \(params)")
        }
        XCTAssertTrue(cliente.hasPrefix("MoBaile/"), cliente)

        // O prazo de cada chamada vem da tabela do motor, e não de uma tabela
        // própria do front.
        let tabelaRecebida = await motor.tabela
        let tabela = try XCTUnwrap(tabelaRecebida, "a tabela do hello não chegou ao cliente")
        XCTAssertEqual(tabela["wda.start"]?.timeoutS, 600)
        XCTAssertEqual(tabela["hierarchy.dump"]?.lane, "capture")
        XCTAssertEqual(sessao.hello?.engineVersion, "0.1.0")
        XCTAssertTrue(sessao.isConnected)
    }

    func testErroDeProtocoloIncompativelImpedeOResto() async throws {
        let estado = AppState()
        let motor = try novoMotor(erros: [
            "engine.hello": .engine(
                code: "incompatible_protocol",
                message: "O cliente fala o protocolo 2 e o motor, o protocolo 3."
            ),
        ])
        let fabrica = FabricaDeMotores([motor])
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }

        await sessao.connect()

        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas, ["engine.hello"], "nada pode ser chamado depois do hello recusado")
        let parado = await motor.parado
        XCTAssertTrue(parado, "o motor incompatível continuou no ar")
        XCTAssertFalse(sessao.isConnected)
        let mensagem = try XCTUnwrap(sessao.lastError)
        XCTAssertTrue(mensagem.contains("2") && mensagem.contains("3"), mensagem)
        XCTAssertEqual(estado.statusMessage, mensagem)
    }

    func testVersaoDiferenteNoResultadoTambemImpede() async throws {
        let estado = AppState()
        let motor = try novoMotor(helloVersao: 3)
        let fabrica = FabricaDeMotores([motor])
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }

        await sessao.connect()

        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas, ["engine.hello"])
        let parado = await motor.parado
        XCTAssertTrue(parado)
        let mensagem = try XCTUnwrap(sessao.lastError)
        XCTAssertTrue(mensagem.contains("protocolo 2"), mensagem)
        XCTAssertTrue(mensagem.contains("protocolo 3"), mensagem)
    }

    // MARK: - Progresso

    func testProgressoDoWDAApareceNaBarraDeStatus() async throws {
        let estado = AppState()
        let motor = try novoMotor()
        let fabrica = FabricaDeMotores([motor])
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()
        defer { Task { await sessao.disconnect() } }

        await motor.reter("wda.start")
        let subida = Task { await sessao.startWDA() }

        try await esperar("wda.start chegar ao motor") { await motor.parametros(de: "wda.start") != nil }
        let paramsWDA = await motor.parametros(de: "wda.start")
        let params = try XCTUnwrap(paramsWDA)
        guard case .string(let token)? = params["progress_token"] else {
            return XCTFail("wda.start sem progress_token: \(params)")
        }

        await motor.emitir(notificacao("$/progress", #"{"token":"\#(token)","message":"Compilando o WebDriverAgent","percent":null}"#))
        try await esperar("mensagem de progresso") { estado.statusMessage == "Compilando o WebDriverAgent" }

        await motor.emitir(notificacao("$/progress", #"{"token":"\#(token)","message":"Assinando","percent":40}"#))
        try await esperar("progresso com percentual") { estado.statusMessage == "Assinando (40%)" }

        await motor.liberar("wda.start")
        await subida.value
        let final = estado.statusMessage

        // Progresso atrasado da chamada que já terminou não sobrescreve nada.
        // O `flow.log` depois serve de marca: o fluxo é ordenado, então quando
        // ele aparece o progresso velho já foi tratado.
        await motor.emitir(notificacao("$/progress", #"{"token":"\#(token)","message":"velho","percent":null}"#))
        await motor.emitir(notificacao("flow.log", #"{"line":"marca"}"#))
        try await esperar("marca do fluxo ordenado") { !estado.runLog.isEmpty }
        XCTAssertEqual(estado.statusMessage, final)
    }

    func testBootsMandamProgressToken() async throws {
        let estado = AppState()
        let motor = try novoMotor()
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.bootEmulator()
        let params = await motor.parametros(de: "emulators.boot")
        guard case .string(let token)? = params?["progress_token"] else {
            return XCTFail("emulators.boot sem progress_token")
        }
        XCTAssertTrue(token.hasPrefix("emulators.boot"), token)
    }

    // MARK: - Cancelamento

    /// Cancelamento foi pedido por alguém; não pode virar mensagem de erro.
    func testCancelamentoNaoViraErroNaTela() async throws {
        let estado = AppState()
        estado.statusMessage = "antes"
        let motor = try novoMotor(erros: ["codegen.steps": .cancelled])
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.refreshSteps()

        XCTAssertNil(sessao.lastError)
        XCTAssertEqual(estado.statusMessage, "antes")
    }

    // MARK: - Quadros

    /// O quadro chega pelo fluxo próprio e as métricas continuam atualizando.
    func testQuadroPeloFluxoProprioAtualizaEspelhoEMetricas() async throws {
        let estado = AppState()
        let motor = try novoMotor()
        let fabrica = FabricaDeMotores([motor])
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()
        defer { Task { await sessao.disconnect() } }
        estado.selectedDevice = "emulator-5554"

        let png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        await motor.emitir(notificacao("stream.frame", """
        {"png_base64":"\(png1x1)","width":1,"height":1,"source_width":1,"source_height":1,"fps":12.4,"capture_ms":38.6,"skipped":3}
        """))

        try await esperar("quadro no espelho") { estado.currentFrame != nil }
        XCTAssertEqual(estado.fps, 12)
        XCTAssertEqual(estado.latencyMs, 39)
        XCTAssertEqual(estado.currentFrame?.size, NSSize(width: 1, height: 1))
    }

    // MARK: - Quadro de outro aparelho

    private static let png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    private static let png2x2 = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP4z8AARAwQCgAf7gP9i18U1AAAAABJRU5ErkJggg=="

    /// Quadro com o tamanho no próprio PNG: é o tamanho que diz, depois, qual
    /// deles foi parar na moldura.
    private func quadro(_ png: String, lado: Int, aparelho: String?) -> String {
        var campos = #""png_base64":"\#(png)","width":\#(lado),"height":\#(lado),"#
            + #""source_width":\#(lado),"source_height":\#(lado)"#
        if let aparelho { campos += #","device_id":"\#(aparelho)""# }
        return "{\(campos)}"
    }

    private func sessaoSelecionada(_ aparelho: String?) -> Data {
        Data(#"{"platform":"android","device_id":\#(aparelho.map { "\"\($0)\"" } ?? "null")}"#.utf8)
    }

    /// Motor sem `screen.capture`: a captura inicial do `select` falha e a
    /// moldura só recebe o que o teste entregar.
    private func motorSemCaptura() throws -> FakeEngine {
        var respostas = try resultadosDasFixtures()
        respostas.removeValue(forKey: "screen.capture")
        return FakeEngine(respostas: respostas)
    }

    func testQuadroDoAparelhoAnteriorNaoEPintadoDepoisDaTroca() async throws {
        let estado = AppState()
        let motor = try motorSemCaptura()
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.select(deviceID: "emulator-5554")
        await motor.responder("session.select_device", com: sessaoSelecionada("aparelho-b"))
        await sessao.select(deviceID: "aparelho-b")
        XCTAssertEqual(estado.selectedDevice, "aparelho-b")

        await sessao.handle(notificacao("stream.frame", quadro(Self.png1x1, lado: 1, aparelho: "emulator-5554")))
        XCTAssertNil(estado.currentFrame, "a tela do aparelho anterior foi pintada sob o novo")

        await sessao.handle(notificacao("stream.frame", quadro(Self.png2x2, lado: 2, aparelho: "aparelho-b")))
        XCTAssertEqual(estado.currentFrame?.size, NSSize(width: 2, height: 2))
    }

    func testSemAparelhoSelecionadoNenhumQuadroEPintado() async throws {
        let estado = AppState()
        let motor = try motorSemCaptura()
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.select(deviceID: "emulator-5554")
        await motor.responder("session.select_device", com: sessaoSelecionada(nil))
        await sessao.select(deviceID: nil)
        XCTAssertNil(estado.selectedDevice)

        await sessao.handle(notificacao("stream.frame", quadro(Self.png1x1, lado: 1, aparelho: "emulator-5554")))
        XCTAssertNil(estado.currentFrame)
        // Nem o quadro de motor antigo, sem `device_id`.
        await sessao.handle(notificacao("stream.frame", quadro(Self.png1x1, lado: 1, aparelho: nil)))
        XCTAssertNil(estado.currentFrame)
    }

    /// Captura pedida no aparelho A que volta depois da troca para B.
    ///
    /// As duas capturas vêm sem `device_id`, como de um motor anterior ao
    /// campo: quem protege aqui é só a geração, e ela tem de ter sido lida
    /// antes de pedir a captura.
    func testCapturaQueVoltaDepoisDaTrocaEDescartada() async throws {
        let estado = AppState()
        estado.selectedDevice = "emulator-5554"
        let motor = try novoMotor()
        let sessao = EngineSession(state: estado, client: motor)
        let captura = { (png: String, lado: Int) in Data(self.quadro(png, lado: lado, aparelho: nil).utf8) }
        await motor.enfileirar("screen.capture", [captura(Self.png1x1, 1), captura(Self.png2x2, 2)])
        await motor.responder("session.select_device", com: sessaoSelecionada("aparelho-b"))
        await motor.reter("screen.capture")

        let antiga = Task { await sessao.refreshFrame() }
        try await esperar("captura antiga no motor") { await motor.quantasRetidas("screen.capture") == 1 }
        let troca = Task { await sessao.select(deviceID: "aparelho-b") }
        try await esperar("captura nova no motor") { await motor.quantasRetidas("screen.capture") == 2 }

        // A nova volta primeiro e pinta; a antiga chega por último, que é o
        // caso em que ela sobrescreveria a moldura.
        await motor.liberarUltima("screen.capture")
        await troca.value
        XCTAssertEqual(estado.currentFrame?.size, NSSize(width: 2, height: 2))
        await motor.liberar("screen.capture")
        await antiga.value

        XCTAssertEqual(estado.currentFrame?.size, NSSize(width: 2, height: 2),
                       "a captura do aparelho anterior repintou a moldura")
    }

    // MARK: - Supervisão

    func testQuedaReiniciaERestauraAparelhoDeteccaoEEspelho() async throws {
        let estado = AppState()
        let primeiro = try novoMotor()
        let segundo = try novoMotor()
        let fabrica = FabricaDeMotores([primeiro, segundo])
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()
        defer { Task { await sessao.disconnect() } }

        await sessao.select(deviceID: "emulator-5554")
        XCTAssertTrue(estado.streamActive)
        // A primeira leitura do rodapé roda em segundo plano e escreve o estado
        // do proxy; ligar os recursos antes dela seria desfeito por ela.
        try await esperar("primeira leitura do rodapé") { await primeiro.chamadas.contains("wda.status") }
        estado.proxyRunning = true
        estado.analyticsListenerActive = true
        estado.passiveListening = true

        await primeiro.cair(status: 9)

        try await esperar("reinício completo") {
            estado.statusMessage.contains("reiniciado") && sessao.isConnected
        }

        let chamadas = await segundo.chamadas
        XCTAssertEqual(chamadas.first, "engine.hello", "o motor novo não começou pelo hello: \(chamadas)")
        let selecao = await segundo.parametros(de: "session.select_device")
        XCTAssertEqual(selecao?["device_id"], .string("emulator-5554"))
        XCTAssertTrue(chamadas.contains("devices.watch_start"), "\(chamadas)")
        XCTAssertTrue(chamadas.contains("stream.start"), "\(chamadas)")
        let tabela = await segundo.tabela
        XCTAssertNotNil(tabela, "o motor novo ficou sem a tabela de prazos")

        // Proxy, analytics e escuta não voltam sozinhos.
        for metodo in ["proxy.start", "analytics.start", "passive.start"] {
            XCTAssertFalse(chamadas.contains(metodo), "\(metodo) foi religado sem o usuário pedir")
        }
        // Mas a configuração de proxy que o motor morto deixou no aparelho é
        // desfeita, ou o aparelho ficaria sem rede.
        XCTAssertTrue(chamadas.contains("proxy.stop"), "\(chamadas)")
        XCTAssertFalse(estado.proxyRunning)
        XCTAssertFalse(estado.analyticsListenerActive)
        XCTAssertFalse(estado.passiveListening)
        XCTAssertTrue(estado.statusMessage.contains("proxy"), estado.statusMessage)
        XCTAssertTrue(estado.statusMessage.contains("analytics"), estado.statusMessage)
        XCTAssertTrue(estado.statusMessage.contains("escuta passiva"), estado.statusMessage)

        XCTAssertEqual(estado.selectedDevice, "emulator-5554")
        XCTAssertTrue(estado.streamActive)
        XCTAssertEqual(fabrica.tentativas, 2)
    }

    /// Espelho desligado na queda continua desligado depois do reinício.
    func testReinicioNaoLigaEspelhoQueEstavaDesligado() async throws {
        let estado = AppState()
        let primeiro = try novoMotor()
        let segundo = try novoMotor()
        let fabrica = FabricaDeMotores([primeiro, segundo])
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()
        defer { Task { await sessao.disconnect() } }

        await sessao.select(deviceID: "emulator-5554")
        await sessao.stopStream()

        await primeiro.cair(status: 9)
        try await esperar("reinício completo") { estado.statusMessage.contains("reiniciado") }

        let chamadas = await segundo.chamadas
        XCTAssertTrue(chamadas.contains("session.select_device"), "\(chamadas)")
        XCTAssertFalse(chamadas.contains("stream.start"), "\(chamadas)")
        XCTAssertFalse(chamadas.contains("proxy.stop"), "proxy estava desligado: \(chamadas)")
    }

    func testDisconnectDoUsuarioNaoReinicia() async throws {
        let estado = AppState()
        let primeiro = try novoMotor()
        let fabrica = FabricaDeMotores([primeiro, try novoMotor()])
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()

        await sessao.disconnect()
        // O processo encerrado pelo próprio disconnect avisa o término depois.
        await primeiro.cair(status: 0)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(fabrica.tentativas, 1, "o encerramento pedido virou reinício")
        let parado = await primeiro.parado
        XCTAssertTrue(parado)
        XCTAssertFalse(sessao.isConnected)
        XCTAssertFalse(estado.statusMessage.contains("Reiniciando"), estado.statusMessage)
    }

    func testTentativasEsgotadasMostramErroEParam() async throws {
        let estado = AppState()
        let fabrica = FabricaDeMotores([try novoMotor()])   // só o primeiro sobe
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()
        let primeiro = fabrica.fabricados[0]

        await primeiro.cair(status: 9)
        try await esperar("desistência") { sessao.lastError?.contains("não voltou") == true }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(fabrica.tentativas, 1 + 3, "eram três tentativas de reinício, nem mais nem menos")
        XCTAssertFalse(sessao.isConnected)
        XCTAssertEqual(estado.statusMessage, sessao.lastError)
    }

    /// O limite vale também para um motor que sobe e cai de novo: senão uma
    /// queda sistemática viraria reinício eterno.
    func testMotorQueCaiLogoDepoisDeSubirTambemEsgotaOLimite() async throws {
        let estado = AppState()
        let motores = try (0..<5).map { _ in try novoMotor() }
        let fabrica = FabricaDeMotores(motores)
        let sessao = EngineSession(state: estado, restartPolicy: politicaRapida) { try fabrica.fazer() }
        await sessao.connect()

        for indice in 0..<3 {
            await fabrica.fabricados[indice].cair(status: 9)
            try await esperar("reinício \(indice + 1)") { fabrica.fabricados.count == indice + 2 && sessao.isConnected }
        }
        await fabrica.fabricados[3].cair(status: 9)
        try await esperar("desistência") { sessao.lastError?.contains("não voltou") == true }

        XCTAssertEqual(fabrica.tentativas, 4)
        XCTAssertFalse(sessao.isConnected)
    }
}
