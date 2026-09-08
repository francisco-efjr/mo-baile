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
    var hierarchyVisible: Bool = true
    var workspaceVisible: Bool = true
    var zenMode: Bool = false
    
    // --- Streaming & Interaction ---
    var streamActive: Bool = false
    var tapForward: Bool = false
    var passiveMode: Bool = false
    
    // --- Locator & Code ---
    var locatorStrategy: LocatorStrategy = .auto
    var locatorKey: String = "onboarding_credito"
    var workspaceTab: WorkspaceTab = .pageObjects

    /// Mostra os dois editores lado a lado, ou só o de ações.
    var splitEditors: Bool = true
    /// Modal com a tabela ordenada dos passos gravados.
    var showingStructure: Bool = false
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
    
    // --- Analytics Events ---
    var analyticsEvents: [AnalyticsEvent] = []
    var selectedAnalyticsEvent: AnalyticsEvent? = nil
    var analyticsFilterText: String = ""
    var analyticsListenerActive: Bool = false
    
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
    
    // MARK: - Computed Properties
    
    var httpBadgeCount: Int { httpRequests.count }
    var analyticsBadgeCount: Int { analyticsEvents.count }
    var stepCount: Int { steps.count }
    
    var filteredHTTPRequests: [NetworkEvent] {
        guard !httpFilterText.isEmpty else { return httpRequests }
        let query = httpFilterText.lowercased()
        return httpRequests.filter {
            $0.host.lowercased().contains(query) ||
            $0.path.lowercased().contains(query) ||
            $0.method.lowercased().contains(query) ||
            ("\($0.statusCode ?? 0)").contains(query)
        }
    }
    
    var filteredAnalyticsEvents: [AnalyticsEvent] {
        guard !analyticsFilterText.isEmpty else { return analyticsEvents }
        let query = analyticsFilterText.lowercased()
        return analyticsEvents.filter {
            $0.eventName.lowercased().contains(query) ||
            $0.tag.lowercased().contains(query)
        }
    }
    
    // MARK: - Actions
    
    func toggleZenMode() {
        zenMode.toggle()
        if zenMode {
            mirrorVisible = false
            hierarchyVisible = false
        } else {
            mirrorVisible = true
            hierarchyVisible = true
        }
    }
    
    func restoreAllPanels() {
        mirrorVisible = true
        hierarchyVisible = true
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
    }
}
