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
/// - **Toda chamada tem prazo.** O prazo vem da tabela que o motor manda no
///   `engine.hello`; estourado, o cliente avisa o motor com `$/cancelRequest` e
///   falha a chamada. Sem isso, uma resposta que nunca chega vira spinner
///   eterno na interface.
actor EngineClient {
    /// Prazo antes do handshake e para método que a tabela do motor não traz.
    ///
    /// 15 s cobre com folga os métodos das filas rápidas; os longos (`wda.*`,
    /// `simulators.*`) sempre vêm na tabela com prazo próprio.
    static let defaultTimeout: Double = 15

    private struct PendingCall {
        let continuation: CheckedContinuation<Data, Error>
        let timer: Task<Void, Never>
    }

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var pending: [Int: PendingCall] = [:]
    private var nextRequestID = 0
    private var buffer = Data()
    private var methodTable: [String: EngineDTO.MethodSpec] = [:]

    private let notificationContinuation: AsyncStream<EngineNotification>.Continuation
    private let frameContinuation: AsyncStream<EngineNotification>.Continuation
    private let terminationContinuation: AsyncStream<Int32>.Continuation

    /// Entrega ordenada dos pedaços do stdout, e a única tarefa que os consome.
    private var chunkContinuation: AsyncStream<Data>.Continuation?
    private var readerTask: Task<Void, Never>?

    /// Notificacoes do motor, menos os quadros: eventos HTTP, analytics,
    /// progresso, aparelho. Ordenado e sem perda, porque cada uma conta.
    nonisolated let notifications: AsyncStream<EngineNotification>

    /// Só `stream.frame`, guardando apenas o mais novo.
    ///
    /// Os quadros iam no mesmo fluxo ilimitado das outras notificações. Com a
    /// interface ocupada, eles se empilhavam — cada um com centenas de KB de
    /// base64 — e o espelho passava a mostrar a tela de segundos atrás enquanto
    /// a memória crescia. Quadro velho não tem valor quando já existe um mais
    /// novo; evento de rede e de analytics tem. Por isso fluxos separados, com
    /// políticas opostas.
    nonisolated let frames: AsyncStream<EngineNotification>

    /// Código de saída do motor quando ele morre sem que `stop()` tenha sido
    /// chamado. É o sinal que a supervisão da sessão usa para reiniciar.
    nonisolated let terminations: AsyncStream<Int32>

    private let configuration: EngineConfiguration

    /// Quanto `stop()` espera o motor sair sozinho antes de mandar SIGTERM.
    ///
    /// O desmonte do motor inclui tirar o proxy global do Android, e isso é
    /// uma chamada de adb que leva centenas de milissegundos. O SIGTERM
    /// imediato interrompia esse passo no meio e o aparelho ficava apontando
    /// para uma porta morta, sem rede. 3 s cobrem o desmonte com folga sem
    /// segurar o encerramento do app por tempo indeterminado.
    let shutdownGrace: Double

    /// Quem espera a saída de um processo em `stop()`, por identidade.
    private var exitWaiters: [ObjectIdentifier: CheckedContinuation<Bool, Never>] = [:]

    init(configuration: EngineConfiguration, shutdownGrace: Double = 3) {
        self.configuration = configuration
        self.shutdownGrace = shutdownGrace
        (notifications, notificationContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (frames, frameContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (terminations, terminationContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    var isRunning: Bool { process?.isRunning ?? false }

    // MARK: - Ciclo de vida

    func start() throws {
        guard !isRunning else { return }
        // Resto de linha de um processo anterior não pode colar na primeira
        // linha do novo.
        buffer = Data()

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

        // Pedaço vazio é fim de arquivo: o motor fechou o stdout (saiu ou
        // morreu). Sem desligar o tratador aqui, ele continuaria sendo chamado
        // com pedaço vazio em laço, gastando CPU depois de toda queda do motor.
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                entregaPedaco.finish()
                return
            }
            entregaPedaco.yield(chunk)
        }

        // stderr do motor e log, nunca protocolo. Vai para o Console do sistema.
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: chunk, encoding: .utf8) else { return }
            FileHandle.standardError.write(Data("[motor] \(text)".utf8))
        }

        // A identidade do processo acompanha o aviso de término: o aviso chega
        // depois, por outra tarefa, e só vale se ainda for sobre o processo
        // atual. Um `stop()` já esqueceu o processo, então o término que ele
        // provoca não conta como queda.
        let processID = ObjectIdentifier(process)
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { await self?.handleTermination(of: processID, status: status) }
        }

        do {
            try process.run()
        } catch {
            throw EngineError.engineNotFound(error.localizedDescription)
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
    }

    func stop() async {
        guard let process else { return }
        // Pedido educado primeiro: o motor desfaz a configuracao de proxy do
        // aparelho no encerramento. Matar direto deixaria o aparelho sem rede.
        try? send(["jsonrpc": .string("2.0"), "id": .int(nextID()), "method": .string("engine.shutdown")])
        stdinHandle?.closeFile()

        // O cliente esquece o processo já, antes de esperar: a saída que vem a
        // seguir foi pedida e não pode contar como queda, e um `start()`
        // durante a espera sobe outro processo sem herdar nada deste.
        let chunks = chunkContinuation
        let reader = readerTask
        chunkContinuation = nil
        readerTask = nil
        self.process = nil
        self.stdinHandle = nil
        // Encerramento pedido não é falha: quem ainda esperava resposta recebe
        // `cancelled`, que a interface não transforma em mensagem de erro.
        failAllPending(with: .cancelled)

        // SIGTERM só para o motor que não saiu sozinho no prazo. O stdout
        // continua sendo lido durante a espera: um motor que escreve enquanto
        // desmonta travaria no cano cheio e nunca chegaria a sair.
        if await !waitForExit(of: process, timeout: shutdownGrace), process.isRunning {
            process.terminate()
        }
        chunks?.finish()
        reader?.cancel()
    }

    /// Espera o processo sair, com prazo, sem ocupar o ator: a espera é uma
    /// suspensão, e o aviso de término entra normalmente enquanto isso.
    private func waitForExit(of process: Process, timeout: Double) async -> Bool {
        guard process.isRunning else { return true }
        let processID = ObjectIdentifier(process)
        return await withCheckedContinuation { continuation in
            exitWaiters[processID] = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self?.resolveExitWait(processID, exited: false)
            }
        }
    }

    /// Quem chegar primeiro, término ou prazo, responde; o outro não acha
    /// mais ninguém esperando.
    private func resolveExitWait(_ processID: ObjectIdentifier, exited: Bool) {
        exitWaiters.removeValue(forKey: processID)?.resume(returning: exited)
    }

    /// Adota a tabela de métodos que o motor mandou no `engine.hello`.
    func useMethodTable(_ table: [String: EngineDTO.MethodSpec]) {
        methodTable = table
    }

    /// Prazo de uma chamada: o da tabela do motor, ou o padrão.
    func timeout(for method: String) -> Double {
        methodTable[method]?.timeoutS ?? Self.defaultTimeout
    }

    // MARK: - Chamadas

    /// Faz uma chamada e decodifica o `result` no tipo pedido.
    ///
    /// Três saídas além da resposta: o prazo estoura (`timeout`), a tarefa que
    /// espera é cancelada (`cancelled`) ou o motor morre (`processTerminated`).
    /// Nas duas primeiras o motor recebe `$/cancelRequest` para parar o
    /// trabalho que ninguém mais vai ler.
    func call<Response: Decodable>(
        _ method: String,
        params: [String: JSONValue] = [:],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        guard isRunning else { throw EngineError.notRunning }
        guard !Task.isCancelled else { throw EngineError.cancelled }

        let requestID = nextID()
        let seconds = timeout(for: method)
        // O corpo roda neste ator sem ponto de suspensão até registrar a
        // pendência. Um cancelamento que chegue nesse meio entra no ator pela
        // tarefa do `onCancel` e, por isso, só é tratado depois do registro:
        // não há janela em que ele se perca.
        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await self?.abandon(requestID, with: .timeout(method: method, seconds: seconds))
                }
                pending[requestID] = PendingCall(continuation: continuation, timer: timer)
                do {
                    try send([
                        "jsonrpc": .string("2.0"),
                        "id": .int(requestID),
                        "method": .string(method),
                        "params": .object(params),
                    ])
                } catch {
                    timer.cancel()
                    pending.removeValue(forKey: requestID)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.abandon(requestID, with: .cancelled) }
        }
        return try Self.decodeResult(data, as: Response.self)
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

    /// Desiste de uma chamada ainda pendente e avisa o motor.
    ///
    /// Se a resposta já chegou, não há pendência e nada acontece: o prazo e o
    /// cancelamento disputam com a resposta, e quem chega primeiro vence.
    private func abandon(_ requestID: Int, with error: EngineError) {
        guard let call = pending.removeValue(forKey: requestID) else { return }
        call.timer.cancel()
        try? send([
            "jsonrpc": .string("2.0"),
            "method": .string("$/cancelRequest"),
            "params": .object(["id": .int(requestID)]),
        ])
        call.continuation.resume(throwing: error)
    }

    private func failAllPending(with error: EngineError) {
        let waiting = pending
        pending.removeAll()
        for (_, call) in waiting {
            call.timer.cancel()
            call.continuation.resume(throwing: error)
        }
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

        if let id = envelope.id {
            // Sem pendência, é resposta de chamada que já estourou o prazo ou
            // foi cancelada: o chamador já recebeu o erro e seguiu em frente.
            // Descartar é o único destino seguro, porque retomar a mesma
            // continuação duas vezes derruba o app.
            if let call = pending.removeValue(forKey: id) {
                call.timer.cancel()
                call.continuation.resume(returning: line)
            }
            return
        }
        guard let method = envelope.method else { return }
        let notification = EngineNotification(method: method, payload: line)
        if method == "stream.frame" {
            frameContinuation.yield(notification)
        } else {
            notificationContinuation.yield(notification)
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

    /// Código do LSP para requisição cancelada, que o motor adotou.
    static let requestCancelledCode = -32800

    /// Interno, e não privado, para o teste de contrato passar a fixture do
    /// motor pelo mesmo caminho da resposta real.
    static func decodeResult<Response: Decodable>(_ data: Data, as type: Response.Type) throws -> Response {
        let envelope: ResultEnvelope<Response>
        do {
            envelope = try JSONDecoder().decode(ResultEnvelope<Response>.self, from: data)
        } catch {
            throw EngineError.protocolViolation(error.localizedDescription)
        }
        if let failure = envelope.error {
            // O motor só manda este erro quando alguém pediu o cancelamento, e
            // quem pediu já sabe. Virar `.engine` faria a mensagem aparecer na
            // barra de status como se fosse falha.
            if failure.code == requestCancelledCode || failure.data?.code == "request_cancelled" {
                throw EngineError.cancelled
            }
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

    private func handleTermination(of processID: ObjectIdentifier, status: Int32) {
        resolveExitWait(processID, exited: true)
        guard let process, ObjectIdentifier(process) == processID else { return }
        // Deixar chamadas penduradas seria pior que falhar: a interface ficaria
        // com spinner eterno em vez de mostrar que o motor caiu.
        failAllPending(with: .processTerminated(status))
        self.process = nil
        stdinHandle = nil
        terminationContinuation.yield(status)
    }
}

/// Onde encontrar o Python e o codigo do motor.
struct EngineConfiguration: Sendable {
    let pythonURL: URL
    let sourcePath: String
    var extraEnvironment: [String: String] = [:]
}
