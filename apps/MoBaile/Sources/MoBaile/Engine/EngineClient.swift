import Foundation

/// Notificacao empurrada pelo motor (mensagem JSON-RPC sem `id`).
struct EngineNotification: Sendable {
    let method: String
    let payload: Data
}

/// Transporte JSON-RPC 2.0 com o motor Python.
///
/// Decisoes de projeto:
///
/// - **Processo filho, nao servico de rede.** O motor sobe como subprocesso e
///   conversa por stdin/stdout. Sem porta aberta nao ha superficie de rede nem
///   autenticacao para inventar, e o motor morre junto com o app, o que elimina
///   a categoria de bug em que um processo orfao continua segurando o adb.
/// - **Ator.** Todo o estado mutavel (processo, pendencias, contador de id)
///   fica isolado; a leitura do stdout acontece numa fila propria e entra no
///   ator por `await`.
/// - **Uma linha por mensagem.** Enquadramento por `\n`, que casa com o lado
///   Python e dispensa cabecalho de tamanho.
actor EngineClient {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var nextRequestID = 0
    private var buffer = Data()

    private var notificationContinuation: AsyncStream<EngineNotification>.Continuation?

    /// Entrega ordenada dos pedaços do stdout, e a única tarefa que os consome.
    private var chunkContinuation: AsyncStream<Data>.Continuation?
    private var readerTask: Task<Void, Never>?
    /// Fluxo de notificacoes do motor: quadros do espelho, eventos HTTP, analytics.
    nonisolated let notifications: AsyncStream<EngineNotification>

    private let configuration: EngineConfiguration

    init(configuration: EngineConfiguration) {
        self.configuration = configuration
        var continuation: AsyncStream<EngineNotification>.Continuation!
        self.notifications = AsyncStream { continuation = $0 }
        self.notificationContinuation = continuation
    }

    var isRunning: Bool { process?.isRunning ?? false }

    // MARK: - Ciclo de vida

    func start() throws {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = configuration.pythonURL
        process.arguments = ["-m", "mobaile.rpc"]

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONPATH"] = configuration.sourcePath
        // Sem buffer no lado Python: com buffer, a resposta so chegaria quando o
        // bloco enchesse, e cada chamada pareceria travada.
        environment["PYTHONUNBUFFERED"] = "1"
        for (key, value) in configuration.extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Os pedaços do stdout precisam ser consumidos NA ORDEM em que saíram
        // do cano.
        //
        // Antes, cada pedaço virava uma `Task` própria — e `Task` não garante
        // ordem. Resposta curta cabe num pedaço só e nunca deu problema, mas um
        // quadro do espelho passa de 400 KB em base64 e chega em vários pedaços,
        // que eram remontados embaralhados. O JSON ainda decodificava, porque a
        // troca caía dentro da string base64, e o resultado era um PNG parcial:
        // certo no topo, uma faixa de lixo e o resto preto.
        //
        // O `AsyncStream` preserva a ordem do `yield`, e um único consumidor
        // aplica os pedaços em sequência.
        let (pedacos, entregaPedaco) = AsyncStream<Data>.makeStream(bufferingPolicy: .unbounded)
        self.chunkContinuation = entregaPedaco
        self.readerTask = Task { [weak self] in
            for await chunk in pedacos {
                guard !Task.isCancelled else { return }
                await self?.ingest(chunk)
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            entregaPedaco.yield(chunk)
        }

        // stderr do motor e log, nunca protocolo. Vai para o Console do sistema.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
            FileHandle.standardError.write(Data("[motor] \(text)".utf8))
        }

        process.terminationHandler = { [weak self] finished in
            Task { await self?.handleTermination(status: finished.terminationStatus) }
        }

        do {
            try process.run()
        } catch {
            throw EngineError.engineNotFound(error.localizedDescription)
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
    }

    func stop() {
        guard let process else { return }
        // Pedido educado primeiro: o motor desfaz a configuracao de proxy do
        // aparelho no encerramento. Matar direto deixaria o aparelho sem rede.
        try? send(["jsonrpc": .string("2.0"), "id": .int(nextID()), "method": .string("engine.shutdown")])
        stdinHandle?.closeFile()
        process.terminate()
        chunkContinuation?.finish()
        chunkContinuation = nil
        readerTask?.cancel()
        readerTask = nil
        self.process = nil
        self.stdinHandle = nil
    }

    // MARK: - Chamadas

    /// Faz uma chamada e decodifica o `result` no tipo pedido.
    func call<Response: Decodable>(
        _ method: String,
        params: [String: JSONValue] = [:],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        guard isRunning else { throw EngineError.notRunning }

        let requestID = nextID()
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation
            do {
                try send([
                    "jsonrpc": .string("2.0"),
                    "id": .int(requestID),
                    "method": .string(method),
                    "params": .object(params),
                ])
            } catch {
                pending.removeValue(forKey: requestID)
                continuation.resume(throwing: error)
            }
        }
        return try decodeResult(data, as: Response.self)
    }

    /// Chamada cujo resultado nao interessa.
    ///
    /// Nome diferente de propósito: uma sobrecarga de `call` sem tipo de
    /// retorno inferível deixaria a resolução ambígua em toda chamada
    /// descartada.
    func callIgnoringResult(_ method: String, params: [String: JSONValue] = [:]) async throws {
        _ = try await call(method, params: params, as: EmptyResult.self)
    }

    private struct EmptyResult: Decodable {}

    // MARK: - Interno

    private func nextID() -> Int {
        nextRequestID += 1
        return nextRequestID
    }

    private func send(_ message: [String: JSONValue]) throws {
        guard let stdinHandle else { throw EngineError.notRunning }
        var payload = try JSONEncoder().encode(message)
        payload.append(0x0A)  // \n: o enquadramento e por linha
        try stdinHandle.write(contentsOf: payload)
    }

    private func ingest(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            if !line.isEmpty {
                route(Data(line))
            }
        }
    }

    private struct Envelope: Decodable {
        let id: Int?
        let method: String?
    }

    private func route(_ line: Data) {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else {
            FileHandle.standardError.write(Data("[motor] linha fora do protocolo ignorada\n".utf8))
            return
        }

        if let id = envelope.id, let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: line)
            return
        }
        if let method = envelope.method {
            notificationContinuation?.yield(EngineNotification(method: method, payload: line))
        }
    }

    private struct ResultEnvelope<Response: Decodable>: Decodable {
        let result: Response?
        let error: RPCErrorBody?
    }

    private struct RPCErrorBody: Decodable {
        struct Detail: Decodable {
            let code: String
            let message: String
        }
        let code: Int
        let message: String
        let data: Detail?
    }

    private func decodeResult<Response: Decodable>(_ data: Data, as type: Response.Type) throws -> Response {
        let envelope: ResultEnvelope<Response>
        do {
            envelope = try JSONDecoder().decode(ResultEnvelope<Response>.self, from: data)
        } catch {
            throw EngineError.protocolViolation(error.localizedDescription)
        }
        if let failure = envelope.error {
            throw EngineError.engine(
                code: failure.data?.code ?? "rpc_\(failure.code)",
                message: failure.data?.message ?? failure.message
            )
        }
        guard let result = envelope.result else {
            throw EngineError.protocolViolation("resposta sem 'result' nem 'error'")
        }
        return result
    }

    private func handleTermination(status: Int32) {
        // Deixar chamadas penduradas seria pior que falhar: a interface ficaria
        // com spinner eterno em vez de mostrar que o motor caiu.
        let waiting = pending
        pending.removeAll()
        for (_, continuation) in waiting {
            continuation.resume(throwing: EngineError.processTerminated(status))
        }
        process = nil
        stdinHandle = nil
    }
}

/// Onde encontrar o Python e o codigo do motor.
struct EngineConfiguration: Sendable {
    let pythonURL: URL
    let sourcePath: String
    var extraEnvironment: [String: String] = [:]
}
