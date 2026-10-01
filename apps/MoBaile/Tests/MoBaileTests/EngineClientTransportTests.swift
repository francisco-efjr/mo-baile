import XCTest
@testable import MoBaile

/// Prazo, cancelamento, contrapressão dos quadros e queda, contra um motor
/// falso de verdade: um processo que fala JSON-RPC pelo mesmo cano.
///
/// O duplo de `EngineCalling` não serve aqui. O que está em teste é o próprio
/// transporte — pendências, temporizador, enquadramento por linha e os dois
/// fluxos de notificação —, e isso só aparece com bytes atravessando um
/// processo. O motor falso é um script Python mínimo, sem dependência do motor
/// real nem de aparelho, então roda em qualquer máquina com `python3`.
final class EngineClientTransportTests: XCTestCase {

    /// Sobe como `python3 -m mobaile.rpc`, exatamente como o motor real: o
    /// cliente não precisa de nenhuma porta de entrada só para teste.
    private static let motorFalso = #"""
    import json, os, signal, sys, threading, time

    trava = threading.Lock()
    pendentes = {}
    teimoso = False
    registro = os.environ.get("MOBAILE_FAKE_LOG")

    def registrar(texto):
        if registro:
            with open(registro, "a") as arquivo:
                arquivo.write(texto + "\n")

    def ao_receber_sigterm(_sinal, _quadro):
        registrar("sigterm")
        os._exit(143)

    signal.signal(signal.SIGTERM, ao_receber_sigterm)

    def enviar(mensagem):
        with trava:
            sys.stdout.write(json.dumps(mensagem) + "\n")
            sys.stdout.flush()

    def responder(pedido, resultado):
        enviar({"jsonrpc": "2.0", "id": pedido, "result": resultado})

    def notificar(metodo, params):
        enviar({"jsonrpc": "2.0", "method": metodo, "params": params})

    while True:
        linha = sys.stdin.readline()
        if not linha:
            break
        mensagem = json.loads(linha)
        metodo = mensagem.get("method")
        pedido = mensagem.get("id")
        params = mensagem.get("params") or {}
        if metodo == "$/cancelRequest":
            alvo = params.get("id")
            notificar("fake.cancel", {"id": alvo, "method": pendentes.get(alvo)})
        elif metodo == "lento":
            pendentes[pedido] = metodo
        elif metodo == "atrasado":
            pendentes[pedido] = metodo
            threading.Timer(params.get("delay", 0.6), responder, (pedido, {"ok": True})).start()
        elif metodo == "cancelado":
            enviar({"jsonrpc": "2.0", "id": pedido, "error": {
                "code": -32800, "message": "Requisicao cancelada.",
                "data": {"code": "request_cancelled", "message": "Requisicao cancelada."}}})
        elif metodo == "rajada":
            for n in range(params["n"]):
                notificar("stream.frame", {"seq": n})
                notificar("evento.teste", {"seq": n})
            responder(pedido, {"ok": True})
        elif metodo == "quadro":
            notificar("stream.frame", {"seq": params["seq"]})
            responder(pedido, {"ok": True})
        elif metodo == "morrer":
            os._exit(3)
        elif metodo == "teimoso":
            teimoso = True
            responder(pedido, {"ok": True})
        elif metodo == "engine.shutdown":
            responder(pedido, {"ok": True})
            if teimoso:
                while True:
                    time.sleep(0.05)
            # Desmonte que leva tempo, como tirar o proxy do Android pelo adb.
            # Um SIGTERM aqui no meio aparece no registro.
            time.sleep(0.3)
            registrar("desmonte-completo")
            break
        else:
            responder(pedido, {"ok": True, "method": metodo})
    """#

    private var raiz: URL!
    private var python: URL!

    override func setUpWithError() throws {
        let candidatos = ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        guard let caminho = candidatos.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("python3 não encontrado para subir o motor falso")
        }
        python = URL(fileURLWithPath: caminho)

        raiz = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobaile-motor-falso-\(UUID().uuidString)")
        let pacote = raiz.appendingPathComponent("mobaile/rpc")
        try FileManager.default.createDirectory(at: pacote, withIntermediateDirectories: true)
        try Data().write(to: raiz.appendingPathComponent("mobaile/__init__.py"))
        try Data().write(to: pacote.appendingPathComponent("__init__.py"))
        try Data(Self.motorFalso.utf8).write(to: pacote.appendingPathComponent("__main__.py"))
    }

    override func tearDownWithError() throws {
        if let raiz { try? FileManager.default.removeItem(at: raiz) }
    }

    private func subirMotorFalso(prazoDeSaida: Double = 3, registro: URL? = nil) async throws -> EngineClient {
        var configuracao = EngineConfiguration(pythonURL: python, sourcePath: raiz.path)
        if let registro {
            configuracao.extraEnvironment["MOBAILE_FAKE_LOG"] = registro.path
        }
        let client = EngineClient(configuration: configuracao, shutdownGrace: prazoDeSaida)
        try await client.start()
        return client
    }

    private struct Ok: Decodable { let ok: Bool }

    /// Resposta que carrega o nome do método: distingue a resposta certa da
    /// sobra de outra chamada, que seria só `{"ok": true}`.
    private struct Eco: Decodable { let ok: Bool; let method: String }

    private func linhasDoRegistro(_ registro: URL) -> [String] {
        ((try? String(contentsOf: registro, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    private struct Seq: Decodable {
        struct Params: Decodable { let seq: Int }
        let params: Params
    }

    private struct AvisoDeCancelamento: Decodable {
        struct Params: Decodable { let id: Int; let method: String? }
        let params: Params
    }

    private func spec(_ segundos: Double) -> EngineDTO.MethodSpec {
        EngineDTO.MethodSpec(lane: "fast", timeoutS: segundos, progress: false)
    }

    /// Coleta as `quantas` primeiras notificações que passam no filtro, com
    /// prazo: transporte quebrado tem de falhar o teste, não travá-lo.
    private func coletar(
        _ fluxo: AsyncStream<EngineNotification>,
        quantas: Int = 1,
        prazo: Double = 5,
        onde filtro: @escaping @Sendable (EngineNotification) -> Bool = { _ in true }
    ) async throws -> [EngineNotification] {
        try await withThrowingTaskGroup(of: [EngineNotification]?.self) { grupo in
            grupo.addTask {
                var coletadas: [EngineNotification] = []
                for await notificacao in fluxo where filtro(notificacao) {
                    coletadas.append(notificacao)
                    if coletadas.count == quantas { break }
                }
                return coletadas
            }
            grupo.addTask {
                try await Task.sleep(nanoseconds: UInt64(prazo * 1_000_000_000))
                return nil
            }
            let primeiro = try await grupo.next()!
            grupo.cancelAll()
            return try XCTUnwrap(primeiro, "prazo de \(prazo)s estourado esperando notificação")
        }
    }

    private func seq(_ notificacao: EngineNotification) throws -> Int {
        try JSONDecoder().decode(Seq.self, from: notificacao.payload).params.seq
    }

    // MARK: - Prazo

    func testPrazoPadraoAntesDoHelloEDaTabelaDepois() async throws {
        let client = EngineClient(configuration: EngineConfiguration(pythonURL: python, sourcePath: raiz.path))
        let antes = await client.timeout(for: "wda.start")
        XCTAssertEqual(antes, 15)
        await client.useMethodTable(["wda.start": spec(600)])
        let depois = await client.timeout(for: "wda.start")
        let ausente = await client.timeout(for: "input.tap")
        XCTAssertEqual(depois, 600)
        XCTAssertEqual(ausente, 15, "método fora da tabela usa o padrão")
    }

    func testPrazoEstouradoMandaCancelRequestEFalhaComTimeout() async throws {
        let client = try await subirMotorFalso()
        defer { Task { await client.stop() } }
        await client.useMethodTable(["lento": spec(0.3)])

        let inicio = Date()
        do {
            _ = try await client.call("lento", as: Ok.self)
            XCTFail("a chamada sem resposta não estourou o prazo")
        } catch let erro as EngineError {
            XCTAssertEqual(erro, .timeout(method: "lento", seconds: 0.3))
            XCTAssertTrue(erro.localizedDescription.contains("lento"), erro.localizedDescription)
        }
        XCTAssertLessThan(Date().timeIntervalSince(inicio), 3, "o prazo da tabela não foi respeitado")

        let aviso = try await coletar(client.notifications) { $0.method == "fake.cancel" }[0]
        let params = try JSONDecoder().decode(AvisoDeCancelamento.self, from: aviso.payload).params
        XCTAssertEqual(params.method, "lento", "o $/cancelRequest não citou o id da chamada que estourou")
    }

    func testRespostaDepoisDoPrazoEDescartadaSemEstrago() async throws {
        let client = try await subirMotorFalso()
        defer { Task { await client.stop() } }
        await client.useMethodTable(["atrasado": spec(0.2)])

        do {
            _ = try await client.call("atrasado", params: ["delay": .double(0.6)], as: Ok.self)
            XCTFail("esperava timeout")
        } catch let erro as EngineError {
            XCTAssertEqual(erro, .timeout(method: "atrasado", seconds: 0.2))
        }

        // A resposta tardia chega neste intervalo e não tem mais dono.
        try await Task.sleep(nanoseconds: 800_000_000)

        // O transporte segue são: a chamada seguinte recebe a resposta dela, e
        // não a sobra da anterior.
        let resposta = try await client.call("eco", as: Eco.self)
        XCTAssertEqual(resposta.method, "eco", "a chamada recebeu a resposta de outra")
        let rodando = await client.isRunning
        XCTAssertTrue(rodando)
    }

    // MARK: - Cancelamento

    func testErroRequestCancelledViraCancelled() async throws {
        let client = try await subirMotorFalso()
        defer { Task { await client.stop() } }

        do {
            _ = try await client.call("cancelado", as: Ok.self)
            XCTFail("esperava cancelamento")
        } catch let erro as EngineError {
            XCTAssertEqual(erro, .cancelled)
        }
    }

    func testCancelarATarefaMandaCancelRequest() async throws {
        let client = try await subirMotorFalso()
        defer { Task { await client.stop() } }
        await client.useMethodTable(["lento": spec(30)])

        let tarefa = Task { try await client.call("lento", as: Ok.self) }
        try await Task.sleep(nanoseconds: 200_000_000)
        tarefa.cancel()

        switch await tarefa.result {
        case .success:
            XCTFail("a chamada cancelada devolveu resultado")
        case .failure(let erro):
            XCTAssertEqual(erro as? EngineError, .cancelled)
        }
        let aviso = try await coletar(client.notifications) { $0.method == "fake.cancel" }[0]
        let params = try JSONDecoder().decode(AvisoDeCancelamento.self, from: aviso.payload).params
        XCTAssertEqual(params.method, "lento")
    }

    // MARK: - Contrapressão

    /// Rajada de 200 quadros com consumidor parado: fica só o mais novo.
    ///
    /// O consumidor aqui é o mais lento possível — não lê nada durante a
    /// rajada. A resposta de `rajada` só chega depois de todas as notificações
    /// (o transporte preserva a ordem), então quando o `call` volta os 200
    /// quadros já passaram pelo cliente. Com o fluxo antigo, ilimitado, os 200
    /// estariam guardados na memória esperando a vez.
    func testRajadaDeQuadrosGuardaSoOMaisNovoEEventosChegamTodosEmOrdem() async throws {
        let client = try await subirMotorFalso()
        defer { Task { await client.stop() } }

        _ = try await client.call("rajada", params: ["n": .int(200)], as: Ok.self)

        let eventos = try await coletar(client.notifications, quantas: 200) { $0.method == "evento.teste" }
        XCTAssertEqual(try eventos.map(seq), Array(0..<200), "evento perdido ou fora de ordem")

        let pendente = try await coletar(client.frames)[0]
        XCTAssertEqual(try seq(pendente), 199, "o quadro guardado não é o mais novo")

        // Se houvesse mais de um guardado, o próximo seria o 198 ou outro
        // velho, e não o quadro emitido agora.
        _ = try await client.call("quadro", params: ["seq": .int(1000)], as: Ok.self)
        let seguinte = try await coletar(client.frames)[0]
        XCTAssertEqual(try seq(seguinte), 1000, "sobrou quadro velho no fluxo")
    }

    // MARK: - Encerramento

    /// `stop()` espera o motor terminar o desmonte em vez de interrompê-lo.
    ///
    /// Regressão: o SIGTERM ia logo depois do `engine.shutdown` e cortava o
    /// desmonte no meio, deixando o proxy do Android apontando para uma porta
    /// morta.
    func testStopNaoMandaSigtermQuandoOMotorSaiNoPrazo() async throws {
        let registro = raiz.appendingPathComponent("registro.txt")
        let client = try await subirMotorFalso(prazoDeSaida: 3, registro: registro)
        _ = try await client.call("eco", as: Eco.self)

        let inicio = Date()
        await client.stop()
        let duracao = Date().timeIntervalSince(inicio)

        let linhas = linhasDoRegistro(registro)
        XCTAssertEqual(linhas, ["desmonte-completo"], "o desmonte foi interrompido: \(linhas)")
        XCTAssertLessThan(duracao, 3, "stop esperou o prazo inteiro por um motor que já tinha saído")
        let rodando = await client.isRunning
        XCTAssertFalse(rodando)
    }

    func testStopMandaSigtermQuandoOMotorNaoSaiNoPrazo() async throws {
        let registro = raiz.appendingPathComponent("registro.txt")
        let client = try await subirMotorFalso(prazoDeSaida: 0.5, registro: registro)
        _ = try await client.call("teimoso", as: Ok.self)

        let inicio = Date()
        await client.stop()
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(inicio), 0.5, "o SIGTERM veio antes do prazo")

        // O sinal é entregue depois que `stop()` volta; o registro aparece logo.
        let limite = Date().addingTimeInterval(3)
        while !linhasDoRegistro(registro).contains("sigterm"), Date() < limite {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(linhasDoRegistro(registro), ["sigterm"], "o motor que não saiu não recebeu SIGTERM")
    }

    // MARK: - Queda

    func testQuedaFalhaPendentesEAvisaTermino() async throws {
        let client = try await subirMotorFalso()
        defer { Task { await client.stop() } }

        do {
            _ = try await client.call("morrer", as: Ok.self)
            XCTFail("a chamada sobreviveu à queda do motor")
        } catch let erro as EngineError {
            XCTAssertEqual(erro, .processTerminated(3))
        }

        let terminos = client.terminations
        let status = try await withThrowingTaskGroup(of: Int32?.self) { grupo in
            grupo.addTask {
                for await status in terminos { return status }
                return nil
            }
            grupo.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let primeiro = try await grupo.next()!
            grupo.cancelAll()
            return primeiro
        }
        XCTAssertEqual(status, 3, "a queda não foi avisada à supervisão")
        let rodando = await client.isRunning
        XCTAssertFalse(rodando)
    }
}
