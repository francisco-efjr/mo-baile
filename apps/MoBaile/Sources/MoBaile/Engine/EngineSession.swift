import AppKit
import Foundation
import Observation

/// Coordenador entre o motor e o estado da interface.
///
/// Este objeto e a peca que faltava na aplicacao: antes existiam servicos
/// escritos em Swift e um `AppState` cheio de campos, mas nada ligava um ao
/// outro. Nenhum servico chegava a ser instanciado, entao a janela mostrava
/// apenas o estado vazio.
///
/// Responsabilidades, e so estas:
/// 1. subir e derrubar o motor;
/// 2. traduzir intencao da interface em chamada do contrato;
/// 3. aplicar notificacao do motor no `AppState`.
///
/// Regra de disciplina: as telas falam com esta classe, nunca com o
/// `EngineClient`. Assim o dia em que o transporte mudar (socket unix para os
/// quadros, por exemplo) nenhuma tela precisa saber.
@MainActor
@Observable
final class EngineSession {
    private(set) var isConnected = false
    private(set) var lastError: String?
    private(set) var engineInfo: EngineDTO.EngineInfo?

    /// Estado real do ambiente, medido pelo motor. Alimenta a tela de estado
    /// vazio, que antes desenhava indicadores escritos no codigo.
    private(set) var diagnostics: EngineDTO.Diagnostics?
    private(set) var simulators: [EngineDTO.Simulator] = []
    private(set) var avds: [String] = []
    private(set) var lastScan: Date?
    private(set) var isBooting = false

    /// Resultado do handshake: versão do motor e tabela de métodos.
    private(set) var hello: EngineDTO.Hello?

    /// Versão do contrato que esta interface fala (ver `docs/PROTOCOLO_RPC.md`).
    nonisolated static let protocolVersion = 2

    /// Como o front se apresenta no `engine.hello`.
    ///
    /// Rodando pelo `swift run` não há Info.plist, e a versão fica `dev`:
    /// inventar um número faria o log do motor afirmar uma versão que não
    /// existe.
    nonisolated static let clientName = "MoBaile/"
        + ((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev")

    /// Quanto esperar entre tentativas de reinício, e quantas aceitar.
    struct RestartPolicy {
        /// Espera antes de cada tentativa. Crescente para não martelar um
        /// ambiente quebrado (adb travado, Python sem dependência) em laço.
        var delays: [Double] = [0.5, 1, 2]
        /// Tentativas aceitas dentro de `window`. Passou disso, a queda é
        /// sistemática e reiniciar de novo só esconderia o problema.
        var maxAttempts = 3
        var window: TimeInterval = 60
    }

    private let state: AppState
    private let makeClient: @MainActor () throws -> any EngineCalling
    private let restartPolicy: RestartPolicy
    private var client: (any EngineCalling)?
    private var notificationTask: Task<Void, Never>?
    private var frameTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private var daemonTask: Task<Void, Never>?
    private var hierarchyRefreshTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var restartAttempts: [Date] = []
    private var watchingDevices = false

    /// Muda sempre que o espelho é limpo. A decodificação do quadro agora
    /// acontece fora do MainActor, e um quadro que termine de decodificar
    /// depois da troca de aparelho não pode repintar a moldura com a tela do
    /// aparelho anterior.
    private var frameGeneration = 0
    /// Só a leitura de hierarquia mais recente pode substituir a árvore.
    /// Duas leituras concorrentes podem terminar fora da ordem em que começaram.
    private var hierarchyRequestGeneration = 0
    private var recordingOperationInProgress = false
    private var recordingStateGeneration = 0

    /// Token de progresso da operação longa em andamento. Progresso com outro
    /// token é de uma chamada que já terminou ou estourou o prazo, e não pode
    /// sobrescrever a mensagem da atual.
    private var activeProgressToken: String?
    private var progressSequence = 0

    convenience init(state: AppState) {
        self.init(state: state) {
            EngineClient(configuration: try EngineLocator.resolve())
        }
    }

    /// `makeClient` fabrica um motor novo a cada conexão e a cada reinício.
    /// Um processo que morreu não é reaproveitado: estado interno pela metade
    /// (buffer, pendências, tabela) é exatamente o que um reinício quer zerar.
    init(
        state: AppState,
        restartPolicy: RestartPolicy = RestartPolicy(),
        makeClient: @escaping @MainActor () throws -> any EngineCalling
    ) {
        self.state = state
        self.restartPolicy = restartPolicy
        self.makeClient = makeClient
    }

    /// Injeta um motor pronto. Só o teste usa: em produção o cliente nasce
    /// dentro de `connect()`, junto com o processo do motor.
    init(state: AppState, client: any EngineCalling) {
        self.state = state
        self.restartPolicy = RestartPolicy()
        self.makeClient = { throw EngineError.notRunning }
        self.client = client
        self.isConnected = true
    }

    // MARK: - Ciclo de vida

    func connect() async {
        guard client == nil else { return }
        restartAttempts.removeAll()
        do {
            let client = try await launch()
            install(client)

            let info: EngineDTO.EngineInfo = try await client.call("engine.info")
            engineInfo = info
            isConnected = true
            lastError = nil
            applyDaemonStatus(from: info)
            state.statusMessage = "Motor \(info.version) conectado"
            await refreshDevices()
            await startWatchingDevices()
            await refreshEnvironment()
            startWatchingDaemons()
        } catch {
            report(error)
        }
    }

    func disconnect() async {
        // Primeiro a supervisão: o encerramento pedido pelo usuário nunca pode
        // ser lido como queda e disparar reinício.
        restartTask?.cancel()
        restartTask = nil
        stopBackgroundWork()
        try? await client?.callIgnoringResult("devices.watch_stop")
        await client?.stop()
        client = nil
        watchingDevices = false
        isConnected = false
        state.streamActive = false
        state.proxyRunning = false
        state.analyticsListenerActive = false
    }

    /// Sobe um motor novo e faz o handshake antes de qualquer outra chamada.
    ///
    /// O cliente só é devolvido depois do `engine.hello`: um motor de outra
    /// versão do protocolo é parado aqui mesmo, sem chegar a receber chamada
    /// que ele entenderia de outro jeito.
    private func launch() async throws -> any EngineCalling {
        let client = try makeClient()
        try await client.start()
        do {
            try await handshake(with: client)
        } catch {
            await client.stop()
            throw error
        }
        return client
    }

    private func handshake(with client: any EngineCalling) async throws {
        let versao = Self.protocolVersion
        let resposta: EngineDTO.Hello
        do {
            resposta = try await client.call("engine.hello", params: [
                "protocol_version": .int(versao),
                "client": .string(Self.clientName),
            ])
        } catch EngineError.engine(let code, let message) where code == "incompatible_protocol" {
            // A mensagem do motor já cita as duas versões; o complemento diz o
            // que fazer.
            throw EngineError.incompatibleProtocol(
                "Motor incompatível com esta versão do Mo baile. \(message) Atualize o app e o motor juntos."
            )
        } catch EngineError.engine(let code, _) where code == "rpc_-32601" {
            // Motor anterior ao handshake não conhece `engine.hello`.
            throw EngineError.incompatibleProtocol(
                "Motor incompatível com esta versão do Mo baile: o app usa o protocolo \(versao) "
                    + "e o motor, o protocolo 1. Atualize o motor."
            )
        }
        guard resposta.protocolVersion == versao else {
            throw EngineError.incompatibleProtocol(
                "Motor incompatível com esta versão do Mo baile: o app usa o protocolo \(versao) "
                    + "e o motor \(resposta.engineVersion), o protocolo \(resposta.protocolVersion). "
                    + "Atualize o app e o motor juntos."
            )
        }
        hello = resposta
        await client.useMethodTable(resposta.methods)
    }

    private func install(_ client: any EngineCalling) {
        self.client = client
        notificationTask = Task { [weak self] in
            for await notification in client.notifications {
                guard !Task.isCancelled else { return }
                await self?.handle(notification)
            }
        }
        // Laço próprio para os quadros: decodificar um quadro não pode atrasar
        // um evento de rede, e um evento lento não pode segurar o espelho.
        frameTask = Task { [weak self] in
            for await frame in client.frames {
                guard !Task.isCancelled else { return }
                await self?.handle(frame)
            }
        }
        terminationTask = Task { [weak self] in
            for await status in client.terminations {
                guard !Task.isCancelled else { return }
                self?.engineTerminated(client, status: status)
            }
        }
    }

    private func stopBackgroundWork() {
        // Chamadas já em andamento podem devolver depois do encerramento.
        frameGeneration += 1
        hierarchyRequestGeneration += 1
        for task in [notificationTask, frameTask, terminationTask, daemonTask, hierarchyRefreshTask] {
            task?.cancel()
        }
        notificationTask = nil
        frameTask = nil
        terminationTask = nil
        daemonTask = nil
        hierarchyRefreshTask = nil
    }

    // MARK: - Supervisao do motor

    /// O que o front sabe no instante da queda e usa para restaurar.
    private struct RestoreSnapshot {
        let device: String?
        let streamWasActive: Bool
        let watchingDevices: Bool
        let proxyWasRunning: Bool
        /// Recursos que caíram junto e ficam desligados, em texto para o usuário.
        let lost: [String]
    }

    /// O motor morreu sem ninguém ter pedido.
    ///
    /// Antes, a queda deixava a janela desconectada até alguém reabrir o app.
    /// Agora a sessão sobe outro motor e devolve o que dá para devolver pelo
    /// estado do front: aparelho, detecção automática e espelho.
    private func engineTerminated(_ dead: any EngineCalling, status: Int32) {
        guard let client, client === dead else { return }

        var lost: [String] = []
        if state.proxyRunning { lost.append("proxy") }
        if state.analyticsListenerActive { lost.append("analytics") }
        if state.passiveListening { lost.append("escuta passiva") }
        if state.screenRecording { lost.append("gravação de tela") }
        let snapshot = RestoreSnapshot(
            device: state.selectedDevice,
            streamWasActive: state.streamActive,
            watchingDevices: watchingDevices,
            proxyWasRunning: state.proxyRunning,
            lost: lost
        )

        stopBackgroundWork()
        self.client = nil
        watchingDevices = false
        isConnected = false

        // Tudo isto vivia dentro do processo que morreu. Deixar ligado na tela
        // seria afirmar um proxy, uma escuta e uma gravação que não existem.
        state.streamActive = false
        state.fps = 0
        state.proxyRunning = false
        state.daemonStatus.proxy = .off
        state.analyticsListenerActive = false
        state.daemonStatus.fa = .off
        state.passiveListening = false
        state.screenRecording = false
        if state.runState == .running { state.runState = .failed }

        restartTask?.cancel()
        restartTask = Task { [weak self] in
            await self?.recover(after: status, restoring: snapshot)
        }
    }

    private func recover(after status: Int32, restoring snapshot: RestoreSnapshot) async {
        var motivo = EngineError.processTerminated(status).localizedDescription
        while !Task.isCancelled {
            // A janela conta tentativas, com ou sem sucesso: um motor que sobe e
            // cai de novo logo depois também esgota o limite, em vez de ficar
            // reiniciando para sempre.
            let agora = Date()
            restartAttempts.removeAll { agora.timeIntervalSince($0) > restartPolicy.window }
            guard restartAttempts.count < restartPolicy.maxAttempts else {
                let mensagem = "O motor caiu e não voltou depois de \(restartPolicy.maxAttempts) tentativas "
                    + "de reinício. \(motivo) Feche e abra o Mo baile para tentar de novo."
                lastError = mensagem
                state.statusMessage = mensagem
                return
            }
            let tentativa = restartAttempts.count
            restartAttempts.append(agora)
            state.statusMessage = "\(motivo) Reiniciando o motor "
                + "(tentativa \(tentativa + 1) de \(restartPolicy.maxAttempts))…"

            let espera = restartPolicy.delays[min(tentativa, restartPolicy.delays.count - 1)]
            try? await Task.sleep(nanoseconds: UInt64(espera * 1_000_000_000))
            guard !Task.isCancelled else { return }

            let novo: any EngineCalling
            do {
                novo = try await launch()
            } catch EngineError.incompatibleProtocol(let mensagem) {
                // Tentar de novo não muda a versão do motor no disco.
                lastError = mensagem
                state.statusMessage = mensagem
                return
            } catch {
                motivo = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                continue
            }
            // `disconnect()` durante a subida: o motor novo não é de ninguém.
            guard !Task.isCancelled else {
                await novo.stop()
                return
            }

            install(novo)
            isConnected = true
            lastError = nil
            await restore(snapshot)
            guard !Task.isCancelled else { return }

            var mensagem = "Motor reiniciado depois de uma queda."
            if !snapshot.lost.isEmpty {
                mensagem += " Desligados na queda, religue se precisar: \(snapshot.lost.joined(separator: ", "))."
            }
            state.statusMessage = mensagem
            return
        }
    }

    /// Devolve o que o front consegue reconstruir sozinho.
    ///
    /// Proxy, analytics e escuta passiva ficam de fora de propósito. O proxy
    /// mexe na rede do aparelho e a escuta grava passos no código: religar sem
    /// o usuário ver seria agir em nome dele, possivelmente num aparelho que
    /// ele já trocou.
    private func restore(_ snapshot: RestoreSnapshot) async {
        guard let client else { return }
        if let device = snapshot.device {
            let sessao = try? await client.call(
                "session.select_device",
                params: ["platform": .string(state.platform.rawValue), "device_id": .string(device)],
                as: EngineDTO.SessionState.self
            )
            state.selectedDevice = sessao?.deviceId
            if sessao?.deviceId != nil {
                // O motor morto pode ter deixado o aparelho Android apontando
                // para um proxy que não existe mais, ou seja, sem rede.
                // `proxy.stop` desfaz essa configuração; não religa nada.
                if snapshot.proxyWasRunning {
                    try? await client.callIgnoringResult("proxy.stop")
                }
                await refreshDeviceSize()
                if snapshot.streamWasActive {
                    await startStream()
                } else {
                    await refreshFrame()
                }
            } else {
                clearFrame()
                state.hierarchyElements = []
                state.selectedElement = nil
            }
        }
        if snapshot.watchingDevices {
            await startWatchingDevices()
        }
        startWatchingDaemons()
    }

    // MARK: - Estado dos servicos do rodape

    /// Mantém WDA, ADB, proxy e analytics do rodapé refletindo a realidade.
    ///
    /// Antes, `applyDaemonStatus` rodava uma única vez, na conexão, e só mexia
    /// em dois dos quatro indicadores. Depois disso o rodapé congelava: subir o
    /// WDA, ligar o proxy ou perder o adb não mudava nada na tela, e o painel
    /// que existe para dizer o que está de pé passava a afirmar o que estava de
    /// pé um minuto atrás.
    private func startWatchingDaemons() {
        daemonTask?.cancel()
        daemonTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDaemonStatus()
                // 5 s equilibra: rápido o bastante para o indicador não mentir,
                // espaçado o bastante para não pesar — `wda.status` faz duas
                // consultas HTTP com timeout próprio.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func refreshDaemonStatus() async {
        guard let client else { return }

        if let info: EngineDTO.EngineInfo = try? await client.call("engine.info") {
            engineInfo = info
            state.daemonStatus.adb = info.adbAvailable ? .ok : .error
            state.daemonStatus.proxy = info.proxy.running ? .ok : .off
            state.proxyRunning = info.proxy.running
            state.scrcpyAvailable = info.scrcpyAvailable
        }

        if let wda: EngineDTO.WDAStatus = try? await client.call("wda.status") {
            state.daemonStatus.wda = wda.wdaRunning ? .ok : (wda.appiumRunning ? .warn : .off)
        }

        await refreshScreenRecordingState()

        state.daemonStatus.fa = state.analyticsListenerActive ? .ok : .off
    }

    // MARK: - Dispositivos

    func refreshDevices() async {
        guard let client else { return }
        do {
            let list: EngineDTO.DeviceList = try await client.call(
                "devices.list", params: ["platform": .string(state.platform.rawValue)]
            )
            state.availableDevices = list.devices.map { (id: $0.id, name: $0.name) }
            state.daemonStatus.adb = state.platform == .android
                ? (list.devices.isEmpty ? .warn : .ok)
                : state.daemonStatus.adb

            // Selecao automatica quando ha exatamente um alvo: o caso comum e
            // um simulador ou um aparelho, e obrigar a escolha nao ajuda.
            if state.selectedDevice == nil, let first = list.devices.first(where: { $0.ready }) {
                await select(deviceID: first.id)
            } else if list.devices.isEmpty {
                state.selectedDevice = nil
            }
        } catch {
            report(error)
        }
    }

    /// Liga a deteccao automatica no motor.
    ///
    /// A partir daqui o aparelho aparece sozinho ao ser plugado: o motor empurra
    /// `device.changed` e a interface reage. Nao ha polling deste lado.
    private func startWatchingDevices() async {
        guard let client else { return }
        if (try? await client.callIgnoringResult("devices.watch_start")) != nil {
            watchingDevices = true
        }
    }

    // MARK: - Ambiente

    /// Relê diagnóstico, simuladores e emuladores.
    func refreshEnvironment() async {
        guard let client else { return }
        diagnostics = try? await client.call("diagnostics.check", as: EngineDTO.Diagnostics.self)
        // Lista de simuladores falha em Mac sem Xcode; o diagnóstico já explica
        // isso, então aqui a falha vira lista vazia e não erro na tela.
        simulators = (try? await client.call("simulators.list", as: EngineDTO.SimulatorList.self))?.simulators ?? []
        avds = (try? await client.call("emulators.list", as: EngineDTO.AvdList.self))?.avds ?? []
        lastScan = Date()
    }

    /// Liga um simulador e traz a janela do Simulator para a frente.
    ///
    /// Sem `udid`, o motor escolhe o primeiro disponível. É o caso de quem só
    /// quer começar a trabalhar e não tem preferência.
    func bootSimulator(udid: String? = nil) async {
        guard let client, !isBooting else { return }
        isBooting = true
        defer { isBooting = false }

        state.statusMessage = "Iniciando simulador…"
        defer { activeProgressToken = nil }
        do {
            var params: [String: JSONValue] = ["progress_token": beginProgress(for: "simulators.boot")]
            if let udid { params["udid"] = .string(udid) }
            let result: EngineDTO.BootResult = try await client.call("simulators.boot", params: params)
            state.statusMessage = result.message
            state.platform = .ios
            // O simulador leva alguns segundos até aparecer no simctl.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refreshEnvironment()
            await refreshDevices()
        } catch {
            report(error)
        }
    }

    /// Abre um token de progresso para a operação longa que vai começar.
    ///
    /// O motor emite `$/progress` com este token enquanto trabalha, e a
    /// mensagem vai para a barra de status, o mesmo lugar onde o texto fixo de
    /// "Iniciando…" já aparecia. Minutos compilando o WDA com uma frase só
    /// pareciam travamento.
    private func beginProgress(for method: String) -> JSONValue {
        progressSequence += 1
        let token = "\(method)-\(progressSequence)"
        activeProgressToken = token
        return .string(token)
    }

    /// Pede ao Appium que suba o WebDriverAgent.
    ///
    /// Na primeira execução o Appium compila o WDA, o que leva minutos. Por
    /// isso a chamada tem timeout generoso na tabela do motor e aqui a
    /// interface mostra o progresso que ele emite em vez de parecer travada.
    func startWDA() async {
        guard let client, !isBooting else { return }
        isBooting = true
        defer { isBooting = false }

        state.statusMessage = "Preparando WebDriverAgent pelo Appium. Na primeira vez isso compila o WDA e demora."
        defer { activeProgressToken = nil }
        do {
            let result: EngineDTO.WDAStartResult = try await client.call(
                "wda.start", params: ["progress_token": beginProgress(for: "wda.start")]
            )
            state.statusMessage = result.message
            state.daemonStatus.wda = .ok
            await refreshEnvironment()
            await refreshHierarchy()
        } catch {
            state.daemonStatus.wda = .error
            report(error)
        }
    }

    func bootEmulator(name: String? = nil) async {
        guard let client, !isBooting else { return }
        isBooting = true
        defer { isBooting = false }

        state.statusMessage = "Iniciando emulador…"
        defer { activeProgressToken = nil }
        do {
            var params: [String: JSONValue] = ["progress_token": beginProgress(for: "emulators.boot")]
            if let name { params["name"] = .string(name) }
            let result: EngineDTO.AvdBootResult = try await client.call("emulators.boot", params: params)
            state.statusMessage = "Emulador \(result.name) iniciando…"
            state.platform = .android
            await refreshEnvironment()
        } catch {
            report(error)
        }
    }

    func select(deviceID: String?) async {
        guard let client else { return }
        do {
            var params: [String: JSONValue] = ["platform": .string(state.platform.rawValue)]
            params["device_id"] = deviceID.map { JSONValue.string($0) } ?? .null
            let session: EngineDTO.SessionState = try await client.call("session.select_device", params: params)
            state.selectedDevice = session.deviceId
            state.hierarchyElements = []
            state.selectedElement = nil
            clearFrame()
            if session.deviceId != nil {
                await activateDevice()
            } else {
                await stopStream()
            }
        } catch {
            report(error)
        }
    }

    /// Tudo que um alvo recém-disponível precisa: medida, primeiro quadro,
    /// árvore e espelho ao vivo.
    ///
    /// Existe como rotina única porque havia dois caminhos até aqui — escolher
    /// no menu e o aparelho aparecer sozinho pelo detector — e só o primeiro
    /// ligava o espelho. Pelo segundo, que é o caminho comum de quem pluga o
    /// aparelho, chegava **um** quadro e a moldura congelava nele: a tela do
    /// app seguia mudando e o espelho continuava mostrando a de minutos atrás,
    /// até alguém clicar em "Atualizar".
    private func activateDevice() async {
        await refreshDeviceSize()
        await refreshFrame()
        await refreshHierarchy()
        await startStream()
    }

    func switchPlatform(to platform: Platform) async {
        state.platform = platform
        state.selectedDevice = nil
        await select(deviceID: nil)
        await refreshDevices()
        await refreshEnvironment()
    }

    /// Le a resolucao real do alvo.
    ///
    /// E o numero que a projecao do espelho usa para converter clique em
    /// coordenada. Errar aqui desloca todo o overlay e faz o toque repassado
    /// cair no lugar errado.
    private func refreshDeviceSize() async {
        guard let client else { return }
        guard let size = try? await client.call("screen.size", as: EngineDTO.ScreenSize.self) else { return }
        state.deviceSize = CGSize(width: size.width, height: size.height)
    }

    // MARK: - Espelho

    func startStream() async {
        guard let client, state.selectedDevice != nil else { return }
        do {
            try await client.callIgnoringResult("stream.start", params: ["fps": .double(6.0), "max_width": .int(900)])
            state.streamActive = true
        } catch {
            report(error)
        }
    }

    func stopStream() async {
        guard let client else { return }
        try? await client.callIgnoringResult("stream.stop")
        state.streamActive = false
        state.fps = 0
    }

    // MARK: - Scrcpy (Espelho Nativo 60 FPS)

    func startScrcpy() async {
        guard let client, state.selectedDevice != nil else { return }
        do {
            let res: EngineDTO.ScrcpyStatus = try await client.call("scrcpy.start", params: [
                "fps": .int(60),
                "max_size": .int(1080),
                "always_on_top": .bool(true),
            ])
            state.scrcpyRunning = res.running
            state.statusMessage = res.running ? "Espelho scrcpy 60 FPS ativo" : "Falha ao iniciar scrcpy"
        } catch {
            report(error)
        }
    }

    func stopScrcpy() async {
        guard let client else { return }
        do {
            let res: EngineDTO.ScrcpyStatus = try await client.call("scrcpy.stop")
            state.scrcpyRunning = res.running
            state.statusMessage = "Espelho scrcpy encerrado"
        } catch {
            report(error)
        }
    }

    func toggleScrcpy() async {
        if state.scrcpyRunning {
            await stopScrcpy()
        } else {
            await startScrcpy()
        }
    }

    func captureNow() async {
        await refreshFrame()
        await refreshHierarchy()
    }

    /// Captura um quadro isolado, sem mexer na hierarquia.
    ///
    /// Existe separado de `captureNow` porque a seleção de dispositivo precisa
    /// de um quadro inicial: antes disso, conectar deixava a hierarquia cheia e
    /// o espelho vazio até alguém ligar o streaming ou clicar em "Forçar
    /// Captura". Quem abre a ferramenta com um aparelho conectado espera ver a
    /// tela, não uma moldura preta.
    func refreshFrame() async {
        guard let client else { return }
        // A geração é lida antes de pedir a captura: a troca de aparelho que
        // acontecer enquanto o motor captura é justamente a que invalida o
        // resultado. Lida depois, ela já seria a nova e deixaria passar a tela
        // do aparelho anterior.
        let geracao = frameGeneration
        do {
            let frame: EngineDTO.Frame = try await client.call("screen.capture", params: ["max_width": .int(900)])
            let image = await Task.detached(priority: .userInitiated) { frame.image }.value
            if let image, mayPublish(frame, generation: geracao) {
                state.currentFrame = image
            }
        } catch {
            report(error)
        }
    }

    private func clearFrame() {
        frameGeneration += 1
        state.currentFrame = nil
    }

    /// Um quadro só vai para a moldura se ainda for do aparelho em uso.
    ///
    /// Sem aparelho selecionado, nenhum quadro vale: é o estado de moldura
    /// vazia. Com aparelho, o `device_id` do quadro tem de bater com ele —
    /// um quadro de A que termina de chegar depois da troca para B pintava a
    /// tela de A sob o nome de B. Motor anterior ao campo não manda
    /// `device_id`, e aí só a geração protege.
    private func mayPublish(_ frame: EngineDTO.Frame, generation: Int) -> Bool {
        guard generation == frameGeneration, let selecionado = state.selectedDevice else { return false }
        return frame.deviceId == nil || frame.deviceId == selecionado
    }

    /// Lê o envelope e decodifica o PNG fora do MainActor.
    ///
    /// O quadro tem centenas de KB de base64. Decodificar o JSON e o PNG na
    /// main thread custava cerca de 7 ms por quadro, tempo em que a janela
    /// não respondia a clique nem desenhava. Só a publicação volta ao MainActor.
    nonisolated private static func decodeFrameNotification(
        _ payload: Data
    ) async -> (frame: EngineDTO.Frame, image: NSImage)? {
        await Task.detached(priority: .userInitiated) {
            guard let frame = try? JSONDecoder().decode(NotificationEnvelope<EngineDTO.Frame>.self, from: payload).params,
                  let image = frame.image else { return nil }
            return (frame, image)
        }.value
    }

    // MARK: - Hierarquia

    func refreshHierarchy() async {
        guard let client else { return }
        hierarchyRequestGeneration += 1
        let requestGeneration = hierarchyRequestGeneration
        let deviceGeneration = frameGeneration
        let deviceID = state.selectedDevice
        let platform = state.platform
        do {
            let dump: EngineDTO.HierarchyDump = try await client.call("hierarchy.dump")
            guard !Task.isCancelled,
                  requestGeneration == hierarchyRequestGeneration,
                  deviceGeneration == frameGeneration,
                  deviceID == state.selectedDevice,
                  platform == state.platform else { return }
            state.hierarchyElements = dump.elements.map { $0.toModel() }
            state.daemonStatus.wda = state.platform == .ios ? .ok : state.daemonStatus.wda
        } catch let error as EngineError {
            guard !Task.isCancelled,
                  requestGeneration == hierarchyRequestGeneration,
                  deviceGeneration == frameGeneration else { return }
            // Hierarquia indisponivel e rotina durante transicao de tela: nao
            // vale interromper o usuario com dialogo.
            if case .engine = error {
                state.statusMessage = error.localizedDescription
            } else {
                report(error)
            }
        } catch {
            report(error)
        }
    }

    /// Atualiza a hierarquia sem bloquear a leitura sequencial de notificações.
    ///
    /// Antes, `stream.settled` chamava `await refreshHierarchy()` dentro do loop
    /// de notificações. Num Android físico com dump lento, isso travava o consumo
    /// de notificações por vários segundos: os quadros do espelho (`stream.frame`)
    /// empilhavam no buffer e a tela congelava até alguém clicar em "Atualizar".
    /// Com a chamada desacoplada e debounced, o espelho flui livre.
    func debouncedRefreshHierarchy(delayNanoseconds: UInt64 = 150_000_000) {
        hierarchyRefreshTask?.cancel()
        hierarchyRefreshTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.refreshHierarchy()
        }
    }

    func selectElement(at point: CGPoint) async {
        guard let client else { return }
        do {
            let lookup: EngineDTO.ElementLookup = try await client.call(
                "hierarchy.element_at",
                params: ["x": .int(Int(point.x)), "y": .int(Int(point.y))]
            )
            state.selectedElement = lookup.element?.toModel()
        } catch {
            report(error)
        }
    }

    // MARK: - Interacao

    func tap(at point: CGPoint) async {
        guard let client else { return }
        do {
            try await client.callIgnoringResult("input.tap", params: ["x": .int(Int(point.x)), "y": .int(Int(point.y))])
        } catch {
            report(error)
            return
        }

        // Com o espelho ao vivo ligado, quem avisa que a tela parou de mudar é
        // o `stream.settled`, e reler aqui seria trabalho repetido.
        //
        // Desligado, ninguém avisa: a moldura e a hierarquia ficavam paradas no
        // estado anterior ao toque. Isso não é só visual — o passo gravado logo
        // depois é resolvido contra a árvore velha, então o toque navega a tela
        // e a gravação aponta para o elemento que não está mais lá.
        guard !state.streamActive else { return }
        try? await Task.sleep(nanoseconds: 600_000_000)
        await refreshFrame()
        await refreshHierarchy()
    }

    /// Grava o passo e toca no aparelho.
    ///
    /// O toque faz parte da gravacao: um fluxo so avanca navegando por ele, e
    /// com os modos separados era preciso alternar entre "Gravar passo" e
    /// "Repassar toque" a cada clique — vinte passos viravam quarenta trocas de
    /// modo. A interface Tk sempre tratou as duas coisas como independentes.
    func record(at point: CGPoint) async {
        guard let client else { return }
        do {
            let strategy = state.locatorStrategy.engineName
            let recorded: EngineDTO.RecordedStep = try await client.call(
                "codegen.record",
                params: ["x": .int(Int(point.x)), "y": .int(Int(point.y)), "strategy": .string(strategy)]
            )
            state.selectedElement = recorded.element.toModel()

            // O motor já devolve a linha do Page Object e o bloco da ação em
            // `codegen.record`, mas ninguém escrevia nos dois editores:
            // `actionsCode` e `locatorsCode` nasciam vazios e só eram limpos.
            // Na prática, gravar um passo não aparecia em lugar nenhum da tela,
            // que é o ciclo inteiro do produto falhando em silêncio.
            //
            // Acrescentar a cada gravação é o que a interface Tk faz, e as duas
            // precisam produzir o mesmo arquivo.
            state.locatorsCode += recorded.objectCode + "\n"
            state.actionsCode += recorded.actionCode + "\n"

            state.statusMessage = "Gravado: \(recorded.varName)"
            await refreshSteps()
        } catch {
            report(error)
            return
        }

        // Grava primeiro, toca depois: a gravacao resolve o elemento contra a
        // arvore da tela atual, e o toque e o que a leva para a proxima.
        await tap(at: point)
    }

    // MARK: - Escuta passiva

    /// Passa a gravar o que a pessoa faz direto no aparelho, sem o espelho.
    ///
    /// No Android o motor lê `/dev/input`; no simulador iOS observa o clique
    /// sobre a janela do Simulator. Em iPhone físico não há como observar
    /// toque, e o motor recusa com explicação.
    func startPassive() async {
        guard let client, !state.passiveListening else { return }
        do {
            let inicio: EngineDTO.PassiveState = try await client.call("passive.start")
            state.passiveListening = true
            state.interactionMode = .record
            state.statusMessage = "Gravando o que você fizer no aparelho (\(inicio.screen[0])×\(inicio.screen[1]))"
        } catch {
            state.passiveListening = false
            report(error)
        }
    }

    func stopPassive() async {
        guard let client else { return }
        defer { state.passiveListening = false }
        try? await client.callIgnoringResult("passive.stop")
        state.statusMessage = "Escuta do aparelho desligada"
    }

    // MARK: - Gravacao de video da tela

    /// Grava video da tela pelo motor: `screenrecord` no Android, `simctl io`
    /// no iOS. Qual das duas ferramentas usar e decisao do motor.
    func startScreenRecording() async {
        guard let client, !state.screenRecording, !recordingOperationInProgress else { return }
        recordingStateGeneration += 1
        recordingOperationInProgress = true
        defer { recordingOperationInProgress = false }
        do {
            let inicio: EngineDTO.RecordingState = try await client.call("recording.start")
            state.screenRecording = inicio.recording
            state.screenRecordingPath = inicio.path
            if let limite = inicio.limitSeconds {
                state.statusMessage = "Gravando a tela (limite de \(limite)s no Android)"
            } else {
                state.statusMessage = "Gravando a tela"
            }
        } catch {
            report(error)
            await refreshScreenRecordingState(afterOperation: true)
        }
    }

    func stopScreenRecording() async {
        guard let client, !recordingOperationInProgress else { return }
        recordingStateGeneration += 1
        recordingOperationInProgress = true
        defer { recordingOperationInProgress = false }
        do {
            let fim: EngineDTO.RecordingResult = try await client.call("recording.stop")
            state.screenRecording = fim.recording
            state.screenRecordingPath = fim.path
            if let caminho = fim.path {
                state.statusMessage = "Video salvo: \(caminho)"
            }
        } catch {
            report(error)
            // Timeout não prova que a operação terminou. Consulte o motor e
            // mantenha o último estado conhecido se ele também não responder.
            await refreshScreenRecordingState(afterOperation: true)
        }
    }

    private func refreshScreenRecordingState(afterOperation: Bool = false) async {
        guard let client, afterOperation || !recordingOperationInProgress else { return }
        let generation = recordingStateGeneration
        guard let recording = try? await client.call("recording.status", as: EngineDTO.RecordingState.self),
              generation == recordingStateGeneration,
              self.client === client else { return }
        state.screenRecording = recording.recording
        if let path = recording.path { state.screenRecordingPath = path }
    }

    func refreshSteps() async {
        guard let client else { return }
        do {
            let list: EngineDTO.StepList = try await client.call("codegen.steps")
            state.steps = list.steps.map { $0.toModel() }
        } catch {
            report(error)
        }
    }

    /// Grava os dois arquivos do Page Object.
    ///
    /// O conteúdo enviado é o dos editores, e não o que o motor tem guardado:
    /// os campos são editáveis, então o que está na tela é o que vale, inclusive
    /// ajuste feito à mão depois de gravar.
    func saveCode() async {
        guard let client else { return }
        do {
            let resultado: EngineDTO.SaveResult = try await client.call(
                "codegen.save",
                params: [
                    "actions_code": .string(state.actionsCode),
                    "locators_code": .string(state.locatorsCode),
                ]
            )
            state.statusMessage = "Salvo em \(resultado.directory)"
        } catch {
            report(error)
        }
    }

    // MARK: - Execucao de fluxo

    /// Roda os passos gravados no aparelho.
    ///
    /// O serviço existia no motor e era testado, mas só a interface Tk o usava:
    /// o front nativo não tinha como rodar automação. O andamento chega por
    /// `flow.log`, linha a linha.
    func runFlow() async {
        guard let client, !state.steps.isEmpty else { return }
        state.runLog.removeAll()
        state.currentRunStep = 0
        state.runState = .running
        do {
            let inicio: EngineDTO.FlowRun = try await client.call("flow.run")
            state.statusMessage = "Executando \(inicio.steps) passo(s)…"
        } catch {
            state.runState = .failed
            report(error)
        }
    }

    func stopFlow() async {
        guard let client, state.runState == .running else { return }
        try? await client.callIgnoringResult("flow.stop")
        state.statusMessage = "Interrupção pedida"
    }

    func clearSteps() async {
        guard let client else { return }
        do {
            try await client.callIgnoringResult("codegen.reset")
            state.clearSteps()
        } catch {
            report(error)
        }
    }

    // MARK: - Rede

    func toggleProxy() async {
        guard let client else { return }
        do {
            if state.proxyRunning {
                let result: EngineDTO.ProxyState = try await client.call("proxy.stop")
                state.proxyRunning = result.running
                state.daemonStatus.proxy = .off
            } else {
                let result: EngineDTO.ProxyState = try await client.call(
                    "proxy.start", params: ["configure_device": .bool(true)]
                )
                state.proxyRunning = result.running
                state.daemonStatus.proxy = result.running ? .ok : .error
                if result.deviceConfigured == false && state.platform == .android {
                    state.statusMessage = "Proxy no ar, mas o aparelho nao aceitou a configuracao automatica."
                }
            }
        } catch {
            report(error)
        }
    }

    /// Tráfego do app em debug no iPhone por cabo, sem proxy: o motor lê o log
    /// `CFNETWORK_DIAGNOSTICS` e entrega cada requisição como `proxy.event`.
    func toggleIOSDebugNet() async {
        guard let client else { return }
        do {
            if state.iosDebugNetActive {
                let result: EngineDTO.NetlogState = try await client.call("netlog.stop")
                state.iosDebugNetActive = result.running
            } else {
                let result: EngineDTO.NetlogState = try await client.call("netlog.start")
                state.iosDebugNetActive = result.running
                if result.running {
                    state.statusMessage = "Lendo o tráfego do iPhone. O app precisa rodar com CFNETWORK_DIAGNOSTICS=3."
                }
            }
        } catch {
            state.iosDebugNetActive = false
            report(error)
        }
    }

    func clearTraffic() async {
        guard let client else { return }
        do {
            try await client.callIgnoringResult("proxy.clear")
            state.clearHTTPTraffic()
        } catch {
            report(error)
        }
    }

    // MARK: - Analytics

    func toggleAnalytics() async {
        guard let client else { return }
        do {
            if state.analyticsListenerActive {
                let result: EngineDTO.AnalyticsState = try await client.call("analytics.stop")
                state.analyticsListenerActive = result.running
                state.daemonStatus.fa = .off
            } else {
                var params: [String: JSONValue] = [:]
                if state.platform == .ios {
                    params["ios_source"] = .string(state.analyticsIOSSource.rpcValue)
                }
                let result: EngineDTO.AnalyticsState = try await client.call("analytics.start", params: params)
                state.analyticsListenerActive = result.running
                state.daemonStatus.fa = result.running ? .ok : .error
            }
        } catch {
            report(error)
        }
    }

    /// Atualiza os iPhones por cabo que podem servir de origem no iOS.
    func refreshAnalyticsIOSDevices() async {
        guard let client else { return }
        do {
            let list: EngineDTO.IOSPhysicalDeviceList = try await client.call("analytics.ios_devices")
            state.analyticsIOSDeviceHint = list.available ? nil : list.hint
            state.analyticsIOSDevices = list.devices.map {
                IOSPhysicalDevice(udid: $0.udid, name: $0.name, iosVersion: $0.iosVersion, problem: $0.problem)
            }
            // O iPhone escolhido foi desconectado: volta ao automatico em vez
            // de deixar a escuta apontando para um aparelho que nao existe.
            if case .device(let udid) = state.analyticsIOSSource,
               !state.analyticsIOSDevices.contains(where: { $0.udid == udid }) {
                state.analyticsIOSSource = .auto
            }
        } catch {
            report(error)
        }
    }

    func clearAnalytics() async {
        guard let client else { return }
        do {
            try await client.callIgnoringResult("analytics.clear")
            state.clearAnalyticsEvents()
        } catch {
            report(error)
        }
    }

    // MARK: - Notificacoes do motor

    private struct NotificationEnvelope<Payload: Decodable>: Decodable {
        let params: Payload
    }

    private func decodeParams<Payload: Decodable>(_ notification: EngineNotification, as type: Payload.Type) -> Payload? {
        try? JSONDecoder().decode(NotificationEnvelope<Payload>.self, from: notification.payload).params
    }

    /// Interno, e não privado, para o teste poder entregar uma notificação
    /// do jeito que o motor entrega.
    func handle(_ notification: EngineNotification) async {
        switch notification.method {
        case "stream.frame":
            let geracao = frameGeneration
            guard let (frame, image) = await Self.decodeFrameNotification(notification.payload),
                  mayPublish(frame, generation: geracao) else { return }
            state.currentFrame = image
            // As métricas chegam dentro do próprio quadro. Antes daqui saía um
            // `stream.stats`, ou seja, uma ida e volta completa por quadro, e o
            // laço de notificações ficava parado esperando a resposta enquanto
            // os quadros seguintes se empilhavam.
            if let fps = frame.fps { state.fps = Int(fps.rounded()) }
            if let captureMs = frame.captureMs { state.latencyMs = Int(captureMs.rounded()) }

        case "device.changed":
            struct Change: Decodable {
                let platform: String
                let deviceId: String?
                enum CodingKeys: String, CodingKey {
                    case platform
                    case deviceId = "device_id"
                }
            }
            guard let change = decodeParams(notification, as: Change.self) else { return }
            if state.selectedDevice != change.deviceId {
                state.hierarchyElements = []
                state.selectedElement = nil
                clearFrame()
            }
            state.selectedDevice = change.deviceId
            if change.deviceId != nil {
                // A ativação vem antes de reler a lista de propósito. O aviso é
                // autoridade sobre a chegada; a lista, não. Um `devices.list`
                // que volte vazio por um instante — o que acontece de verdade
                // com USB instável — zerava o alvo recém-anunciado, e o espelho
                // não chegava a ser ligado.
                await activateDevice()
                state.statusMessage = "Dispositivo conectado"
            } else {
                await stopStream()
                if state.scrcpyRunning {
                    await stopScrcpy()
                }
                state.scrcpyRunning = false
                state.hierarchyElements = []
                state.selectedElement = nil
                clearFrame()
                state.statusMessage = "Dispositivo desconectado"
            }
            await refreshDevices()

        case "passive.step":
            guard let passo = decodeParams(notification, as: EngineDTO.RecordedStep.self) else { return }
            // Mesmo destino do clique no espelho: o passo tem de aparecer no
            // código, que é o ponto inteiro da escuta passiva.
            state.selectedElement = passo.element.toModel()
            state.locatorsCode += passo.objectCode + "\n"
            state.actionsCode += passo.actionCode + "\n"
            state.statusMessage = "Gravado do aparelho: \(passo.varName)"
            await refreshSteps()

        case "passive.skipped":
            struct Pulado: Decodable { let reason: String }
            guard let motivo = decodeParams(notification, as: Pulado.self) else { return }
            state.statusMessage = "Toque não virou passo: \(motivo.reason)"
            if motivo.reason.contains("hierarquia") {
                debouncedRefreshHierarchy(delayNanoseconds: 0)
            }

        case "flow.log":
            struct Linha: Decodable { let line: String }
            guard let payload = decodeParams(notification, as: Linha.self) else { return }
            state.runLog.append(
                LogLine(timestamp: Date(), prefix: "RUN", message: payload.line)
            )
            // O script imprime "PASSO n" ao entrar em cada passo; é o que move o
            // destaque na lista lateral.
            if let numero = Self.numeroDoPasso(em: payload.line) {
                state.currentRunStep = numero
            }

        case "flow.finished":
            struct Fim: Decodable { let success: Bool; let message: String }
            guard let payload = decodeParams(notification, as: Fim.self) else { return }
            state.runState = payload.success ? .passed : .failed
            state.statusMessage = payload.message
            state.runLog.append(
                LogLine(timestamp: Date(), prefix: payload.success ? "PASS" : "FAIL", message: payload.message)
            )

        case "$/progress":
            guard let progresso = decodeParams(notification, as: EngineDTO.Progress.self),
                  let ativo = activeProgressToken, progresso.token == .string(ativo) else { return }
            if let percent = progresso.percent {
                state.statusMessage = "\(progresso.message) (\(Int(percent.rounded()))%)"
            } else {
                state.statusMessage = progresso.message
            }

        case "stream.settled":
            // Tela parou de mudar: relê a hierarquia de forma desacoplada para
            // não travar a recepção contínua dos quadros do espelho.
            debouncedRefreshHierarchy()

        case "proxy.event":
            guard let event = decodeParams(notification, as: EngineDTO.NetworkEventPayload.self) else { return }
            state.httpRequests.append(event.toModel())
            trimTraffic()

        case "analytics.event":
            guard let event = decodeParams(notification, as: EngineDTO.AnalyticsEventPayload.self) else { return }
            state.analyticsEvents.append(event.toModel())

        default:
            break
        }
    }

    /// A lista da interface tem teto proprio: o motor ja limita o historico
    /// dele, mas uma sessao longa ainda acumularia milhares de linhas na tabela.
    private func trimTraffic() {
        let limit = 1000
        if state.httpRequests.count > limit {
            state.httpRequests.removeFirst(state.httpRequests.count - limit)
        }
        if state.analyticsEvents.count > limit {
            state.analyticsEvents.removeFirst(state.analyticsEvents.count - limit)
        }
    }

    // MARK: - Diagnostico

    /// Extrai o número do passo de uma linha de log do executor.
    private static func numeroDoPasso(em linha: String) -> Int? {
        guard let faixa = linha.range(of: #"(?i)passo\s+(\d+)"#, options: .regularExpression) else { return nil }
        return Int(linha[faixa].filter(\.isNumber))
    }

    private func applyDaemonStatus(from info: EngineDTO.EngineInfo) {
        state.daemonStatus.adb = info.adbAvailable ? .ok : .error
        state.daemonStatus.proxy = info.proxy.running ? .ok : .off
        state.scrcpyAvailable = info.scrcpyAvailable
    }

    private func report(_ error: Error) {
        // Cancelamento foi pedido por alguém (prazo, tarefa, encerramento) e
        // não é falha a mostrar.
        if let engineError = error as? EngineError, engineError == .cancelled { return }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        state.statusMessage = message
        if let engineError = error as? EngineError, engineError.isRecoverableBySetup {
            isConnected = false
        }
    }
}
