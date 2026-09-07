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
    private var client: EngineClient?
    private var notificationTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
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
        } catch {
            report(error)
        }
    }

    func disconnect() async {
        notificationTask?.cancel()
        notificationTask = nil
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
            if session.deviceId != nil {
                await refreshDeviceSize()
                await refreshHierarchy()
            }
        } catch {
            report(error)
        }
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
        guard let client else { return }
        do {
            let frame: EngineDTO.Frame = try await client.call("screen.capture", params: ["max_width": .int(900)])
            if let image = frame.image {
                state.currentFrame = image
            }
            await refreshHierarchy()
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
        }
    }

    func record(at point: CGPoint) async {
        guard let client else { return }
        do {
            let strategy = state.locatorStrategy == .coords ? "position" : state.locatorStrategy.rawValue
            let recorded: EngineDTO.RecordedStep = try await client.call(
                "codegen.record",
                params: ["x": .int(Int(point.x)), "y": .int(Int(point.y)), "strategy": .string(strategy)]
            )
            state.selectedElement = recorded.element.toModel()
            await refreshSteps()
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

    private func handle(_ notification: EngineNotification) async {
        switch notification.method {
        case "stream.frame":
            guard let frame = decodeParams(notification, as: EngineDTO.Frame.self),
                  let image = frame.image else { return }
            state.currentFrame = image
            await refreshStreamStats()

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
            await refreshDevices()
            if change.deviceId != nil {
                await refreshDeviceSize()
                await refreshHierarchy()
                state.statusMessage = "Dispositivo conectado"
            } else {
                state.hierarchyElements = []
                state.selectedElement = nil
                state.currentFrame = nil
                state.statusMessage = "Dispositivo desconectado"
            }

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

    private func refreshStreamStats() async {
        guard let client else { return }
        guard let stats = try? await client.call("stream.stats", as: EngineDTO.StreamStats.self) else { return }
        state.fps = Int((stats.effectiveFps ?? 0).rounded())
        state.latencyMs = Int((stats.lastCaptureMs ?? 0).rounded())
    }

    // MARK: - Diagnostico

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
