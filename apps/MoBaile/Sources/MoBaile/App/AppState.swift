import SwiftUI
import Observation

@Observable
class AppState {
    // --- Platform & Device ---
    var platform: Platform = .ios
    var selectedDevice: String? = nil
    var availableDevices: [(id: String, name: String)] = []
    var isDeviceConnected: Bool { selectedDevice != nil }
    
    // --- UI Visibility ---
    var mirrorVisible: Bool = true
    var hierarchyVisible: Bool = false
    var workspaceVisible: Bool = true
    var zenMode: Bool = false
    
    // --- Streaming & Interaction ---
    var streamActive: Bool = false
    var tapForward: Bool = false
    var passiveMode: Bool = false
    
    // --- Locator & Code ---
    /// Começa no "Seletor padrão" de Ajustes › Geral.
    var locatorStrategy: LocatorStrategy = LocatorStrategy.storedDefault
    var locatorKey: String = "onboarding_credito"
    var workspaceTab: WorkspaceTab = .pageObjects

    /// Mostra os dois editores lado a lado, ou só o de ações.
    var splitEditors: Bool = false
    /// Modal com a tabela ordenada dos passos gravados.
    var showingStructure: Bool = false
    /// Modal com a execucao visual do fluxo gravado.
    var showingFlowRunner: Bool = false
    var codeSplitMode: Bool = true
    
    // --- Hierarchy ---
    var hierarchyElements: [UIElement] = []
    var selectedElement: UIElement? = nil
    var hierarchySearchText: String = ""
    var currentHierarchyXML: String? = nil
    
    // --- Automation Steps ---
    var steps: [AutomationStep] = []
    var actionsCode: String = ""
    var locatorsCode: String = ""
    
    // --- Network Traffic ---
    var httpRequests: [NetworkEvent] = []
    var selectedRequest: NetworkEvent? = nil
    var httpFilterText: String = ""
    var proxyRunning: Bool = false
    /// iOS: lendo pelo cabo o log `CFNETWORK_DIAGNOSTICS` do app em debug.
    var iosDebugNetActive: Bool = false
    
    // --- Analytics Events ---
    var analyticsEvents: [AnalyticsEvent] = []
    var selectedAnalyticsEvent: AnalyticsEvent? = nil
    var analyticsFilterText: String = ""
    var analyticsListenerActive: Bool = false
    /// iOS: iPhones por cabo disponiveis para a escuta, e qual origem usar.
    var analyticsIOSDevices: [IOSPhysicalDevice] = []
    var analyticsIOSSource: AnalyticsIOSSource = .auto
    /// Sem pymobiledevice3 no motor; a origem por cabo fica indisponivel.
    var analyticsIOSDeviceHint: String? = nil

    /// A escuta tem de onde ler: alvo da sessao, ou um iPhone por cabo no iOS.
    var canStartAnalytics: Bool {
        guard platform == .ios else { return isDeviceConnected }
        switch analyticsIOSSource {
        case .auto: return isDeviceConnected || analyticsIOSDevices.contains { $0.problem == nil }
        case .simulator: return isDeviceConnected
        case .device: return true
        }
    }
    
    // --- Metrics ---
    var fps: Int = 0
    var settleMs: Int = 0
    var latencyMs: Int = 0
    var cursorPosition: CGPoint = .zero
    var daemonStatus = DaemonStatusMap()
    var statusMessage: String = ""
    
    // --- Run State ---
    var runState: RunState = .idle
    var runLog: [LogLine] = []
    var currentRunStep: Int = 0
    
    // --- Mirror Frame ---
    var currentFrame: NSImage? = nil
    /// Resolucao real do alvo, lida do dispositivo.
    ///
    /// Antes a projecao do overlay usava 1080x1920 fixo, o que desalinhava a
    /// caixa de selecao em qualquer aparelho fora dessa proporcao, que hoje e
    /// a maioria (1080x2400, 1170x2532...).
    var deviceSize: CGSize = CGSize(width: 1080, height: 2400)

    /// Modo de interacao do espelho: inspecionar, repassar toque ou gravar passo.
    var interactionMode: InteractionMode = .forward

    /// Gravação de vídeo da tela do aparelho, feita pelo motor.
    /// Escuta passiva: grava o que a pessoa faz direto no aparelho.
    var passiveListening: Bool = false

    var screenRecording: Bool = false
    var screenRecordingPath: String?

    // --- Scrcpy (60 FPS Native Mirror) ---
    var scrcpyAvailable: Bool = false
    var scrcpyRunning: Bool = false
    
    // MARK: - Computed Properties
    
    var httpBadgeCount: Int { httpRequests.count }
    var analyticsBadgeCount: Int { analyticsEvents.count }
    var stepCount: Int { steps.count }
    
    /// O que as listas de Rede e Analytics exibem: o mais novo no topo.
    ///
    /// Com o mais novo embaixo, cada evento que chegava saía da área visível e
    /// era preciso rolar até o fim para achar a requisição que acabou de
    /// acontecer. Só a exibição inverte: `httpRequests` e `analyticsEvents`
    /// seguem em ordem de chegada, que é o que HAR, TSV e o cartão de
    /// correlação usam.
    var filteredHTTPRequests: [NetworkEvent] {
        guard !httpFilterText.isEmpty else { return httpRequests.reversed() }
        let query = httpFilterText.lowercased()
        return httpRequests.reversed().filter {
            $0.host.lowercased().contains(query) ||
            $0.path.lowercased().contains(query) ||
            $0.method.lowercased().contains(query) ||
            ("\($0.statusCode ?? 0)").contains(query)
        }
    }
    
    var filteredAnalyticsEvents: [AnalyticsEvent] {
        guard !analyticsFilterText.isEmpty else { return analyticsEvents.reversed() }
        let query = analyticsFilterText.lowercased()
        return analyticsEvents.reversed().filter {
            $0.eventName.lowercased().contains(query) ||
            $0.tag.lowercased().contains(query)
        }
    }
    
    // MARK: - Actions
    
    /// Modo Zen: esconde barra lateral e inspector e deixa espelho e
    /// workspace, que é onde o trabalho acontece.
    func toggleZenMode() {
        zenMode.toggle()
        sidebarVisibility = zenMode ? .detailOnly : .all
        inspectorVisible = !zenMode
        mirrorVisible = true
        workspaceVisible = true
    }

    func restoreAllPanels() {
        sidebarVisibility = .all
        inspectorVisible = true
        mirrorVisible = true
        workspaceVisible = true
        zenMode = false
    }
    
    func clearHTTPTraffic() {
        httpRequests.removeAll()
        selectedRequest = nil
    }
    
    func clearAnalyticsEvents() {
        analyticsEvents.removeAll()
        selectedAnalyticsEvent = nil
    }
    
    func clearSteps() {
        steps.removeAll()
        actionsCode = ""
        locatorsCode = ""
        selectedStepID = nil
    }

    // MARK: - Janela (redesenho 3.0)

    /// Barra lateral: áreas do workspace e passos do fluxo.
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    /// Inspector com a hierarquia e os atributos.
    var inspectorVisible: Bool = true
    /// Passo escolhido na seção Fluxo da barra lateral. Destaca o código dele.
    var selectedStepID: UUID? = nil
    /// Confirmação de limpeza aberta (tráfego, eventos ou passos).
    var pendingClear: ClearKind? = nil
    /// Pedido de foco no campo de busca da hierarquia (⌘F em Page Objects).
    var hierarchySearchFocusRequest: Int = 0
    /// Busca da toolbar aberta (⌘F em Rede e Analytics).
    var toolbarSearchPresented: Bool = false
    /// Ajustes › Geral › "Iniciar o espelho automaticamente".
    var autoStartStream: Bool = UserDefaults.standard.object(forKey: AppState.autoStartStreamKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoStartStream, forKey: AppState.autoStartStreamKey) }
    }

    static let autoStartStreamKey = "mobaile.espelhoAutomatico"

    var selectedStep: AutomationStep? {
        guard let selectedStepID else { return nil }
        return steps.first { $0.id == selectedStepID }
    }

    /// Nome do aparelho escolhido, e não o serial: "Pixel 7" diz mais do que
    /// "emulator-5554" para quem tem dois aparelhos na mesa.
    var selectedDeviceName: String? {
        guard let selectedDevice else { return nil }
        let match = availableDevices.first { $0.id == selectedDevice }
        if let name = match?.name, !name.isEmpty { return name }
        return selectedDevice
    }
}
