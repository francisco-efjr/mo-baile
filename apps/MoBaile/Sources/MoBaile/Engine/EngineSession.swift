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

    private let state: AppState
    private var client: (any EngineCalling)?
    private var notificationTask: Task<Void, Never>?
    private var daemonTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
    }

    /// Injeta um motor pronto. Só o teste usa: em produção o cliente nasce
    /// dentro de `connect()`, junto com o processo do motor.
    init(state: AppState, client: any EngineCalling) {
        self.state = state
        self.client = client
        self.isConnected = true
    }

    // MARK: - Ciclo de vida

    func connect() async {
        guard client == nil else { return }
        do {
            let client = EngineClient(configuration: try EngineLocator.resolve())
            try await client.start()
            self.client = client
            observeNotifications(from: client)

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
        notificationTask?.cancel()
        notificationTask = nil
        daemonTask?.cancel()
        daemonTask = nil
        try? await client?.callIgnoringResult("devices.watch_stop")
        await client?.stop()
        client = nil
        isConnected = false
        state.streamActive = false
        state.proxyRunning = false
        state.analyticsListenerActive = false
    }

    private func observeNotifications(from client: EngineClient) {
        notificationTask = Task { [weak self] in
            for await notification in client.notifications {
                guard !Task.isCancelled else { return }
                await self?.handle(notification)
            }
        }
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
        }

        if let wda: EngineDTO.WDAStatus = try? await client.call("wda.status") {
            state.daemonStatus.wda = wda.wdaRunning ? .ok : (wda.appiumRunning ? .warn : .off)
        }

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
        try? await client.callIgnoringResult("devices.watch_start")
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
        do {
            var params: [String: JSONValue] = [:]
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

    /// Pede ao Appium que suba o WebDriverAgent.
    ///
    /// Na primeira execução o Appium compila o WDA, o que leva minutos. Por
    /// isso a chamada tem timeout generoso do lado do motor e aqui a interface
    /// mostra progresso em vez de parecer travada.
    func startWDA() async {
        guard let client, !isBooting else { return }
        isBooting = true
        defer { isBooting = false }

        state.statusMessage = "Preparando WebDriverAgent pelo Appium. Na primeira vez isso compila o WDA e demora."
        do {
            let result: EngineDTO.WDAStartResult = try await client.call("wda.start")
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
        do {
            var params: [String: JSONValue] = [:]
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
            state.currentFrame = nil
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
        do {
            let frame: EngineDTO.Frame = try await client.call("screen.capture", params: ["max_width": .int(900)])
            if let image = frame.image {
                state.currentFrame = image
            }
        } catch {
            report(error)
        }
    }

    // MARK: - Hierarquia

    func refreshHierarchy() async {
        guard let client else { return }
        do {
            let dump: EngineDTO.HierarchyDump = try await client.call("hierarchy.dump")
            state.hierarchyElements = dump.elements.map { $0.toModel() }
            state.daemonStatus.wda = state.platform == .ios ? .ok : state.daemonStatus.wda
        } catch let error as EngineError {
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
        guard let client, !state.screenRecording else { return }
        do {
            let inicio: EngineDTO.RecordingState = try await client.call("recording.start")
            state.screenRecording = true
            state.screenRecordingPath = inicio.path
            if let limite = inicio.limitSeconds {
                state.statusMessage = "Gravando a tela (limite de \(limite)s no Android)"
            } else {
                state.statusMessage = "Gravando a tela"
            }
        } catch {
            state.screenRecording = false
            report(error)
        }
    }

    func stopScreenRecording() async {
        guard let client else { return }
        defer { state.screenRecording = false }
        do {
            let fim: EngineDTO.RecordingResult = try await client.call("recording.stop")
            state.screenRecordingPath = fim.path
            if let caminho = fim.path {
                state.statusMessage = "Video salvo: \(caminho)"
            }
        } catch {
            report(error)
        }
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
        try? await client.callIgnoringResult("codegen.reset")
        state.clearSteps()
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

    func clearTraffic() async {
        guard let client else { return }
        try? await client.callIgnoringResult("proxy.clear")
        state.clearHTTPTraffic()
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
                let result: EngineDTO.AnalyticsState = try await client.call("analytics.start")
                state.analyticsListenerActive = result.running
                state.daemonStatus.fa = result.running ? .ok : .error
            }
        } catch {
            report(error)
        }
    }

    func clearAnalytics() async {
        guard let client else { return }
        try? await client.callIgnoringResult("analytics.clear")
        state.clearAnalyticsEvents()
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
            guard let frame = decodeParams(notification, as: EngineDTO.Frame.self),
                  let image = frame.image else { return }
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
                state.hierarchyElements = []
                state.selectedElement = nil
                state.currentFrame = nil
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
            // Não vira diálogo: durante navegação é rotina o toque cair numa
            // tela cuja árvore ainda não foi lida.
            state.statusMessage = "Toque não virou passo: \(motivo.reason)"

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

        case "stream.settled":
            // Tela parou de mudar: e o instante certo de reler a hierarquia,
            // porque ler durante a animacao devolve arvore inconsistente.
            await refreshHierarchy()

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
    }

    private func report(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        lastError = message
        state.statusMessage = message
        if let engineError = error as? EngineError, engineError.isRecoverableBySetup {
            isConnected = false
        }
    }
}
