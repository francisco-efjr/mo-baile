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
    /// Pendência que o Ambiente deve mostrar ao abrir (o "Resolver…" da
    /// Início leva até o cartão dela). Consumida pela tela.
    var environmentFocus: String? = nil
    var tapForward: Bool = false
    var passiveMode: Bool = false
    
    // --- Locator & Code ---
    /// Começa no "Seletor padrão" de Ajustes › Geral.
    var locatorStrategy: LocatorStrategy = LocatorStrategy.storedDefault
    var locatorKey: String = "minha_tela"
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
    /// Escopo da tabela de Rede (Todos · API · Mídia · Erros · Lentas).
    var networkScope: NetworkScope = .all
    var proxyRunning: Bool = false
    /// Resposta do último `proxy.diagnose` e se o popover dela está aberto.
    var trafficDiagnosis: EngineDTO.TrafficDiagnosis? = nil
    var trafficDiagnosisPresented: Bool = false
    /// Tráfego do app em debug, sem proxy: no iOS, o log `CFNETWORK_DIAGNOSTICS`
    /// pelo cabo; no Android, o log do OkHttp pelo logcat.
    var debugNetActive: Bool = false
    
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
    
    // --- Relatório (auditoria de tagueamento) ---
    /// Spec-modelo aberta. A auditoria sempre relê o arquivo no motor: o que
    /// vale é o que está no disco, inclusive ajuste feito à mão depois de abrir.
    var reportSpec: ReportSpec? = nil
    var reportLogSource: ReportLogSource = .session
    /// Plataforma auditada; `nil` usa a da spec.
    var reportPlatform: Platform? = nil
    var report: AuditReport? = nil
    var selectedReportResultID: ReportResult.ID? = nil
    var selectedReportExtraID: ReportExtra.ID? = nil
    var reportFilter: ReportFilter = .all
    var reportFilterText: String = ""
    var reportOperation: ReportOperation? = nil
    /// Andamento que o motor emite (`$/progress`) na operação em curso.
    var reportProgressMessage: String? = nil
    var reportError: String? = nil
    var reportLastExport: ReportExport? = nil
    /// Importação recém-feita, aberta na sheet de revisão.
    var reportImport: ReportImport? = nil

    /// Plataforma que a próxima auditoria vai usar.
    var reportEffectivePlatform: Platform? { reportPlatform ?? reportSpec?.plataforma }

    var canRunReport: Bool {
        guard reportSpec != nil, reportOperation == nil else { return false }
        if case .session = reportLogSource { return !analyticsEvents.isEmpty }
        return true
    }

    /// Linhas da tabela: filtro por status e busca da toolbar.
    var filteredReportResults: [ReportResult] {
        guard let report else { return [] }
        let busca = SearchQuery(reportFilterText)
        return report.results.filter { result in
            reportFilter.includes(result) && (busca.isEmpty || busca.matchesLiteral(result.searchableFields))
        }
    }

    /// Eventos fora da spec e alertas, com a mesma busca.
    var filteredReportExtras: [ReportExtra] {
        guard let report else { return [] }
        let busca = SearchQuery(reportFilterText)
        guard !busca.isEmpty else { return report.extras }
        return report.extras.filter {
            busca.matchesLiteral([$0.event, $0.screenText, $0.detailText, $0.componentText, $0.flowName ?? ""])
        }
    }

    var selectedReportResult: ReportResult? {
        guard let selectedReportResultID else { return nil }
        return report?.results.first { $0.id == selectedReportResultID }
    }

    var selectedReportExtra: ReportExtra? {
        guard let selectedReportExtraID else { return nil }
        return report?.extras.first { $0.id == selectedReportExtraID }
    }

    /// Contagem da barra lateral: o que pede ação.
    var reportBadgeCount: Int { report?.summary.needsAction ?? 0 }

    /// A área atual filtra pela busca da toolbar (Rede, Analytics, Relatório).
    /// Nas outras, a lupa leva à busca da hierarquia, no inspector.
    var usesToolbarSearch: Bool {
        workspaceTab == .report || (isDeviceConnected && workspaceTab != .pageObjects)
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
    /// `total` do último `flow.step`; 0 antes do primeiro.
    var runStepTotal: Int = 0
    var runSource: RunSource = .recordedSteps
    /// Início da execução. O `runLog` tem teto: a primeira linha guardada não é
    /// necessariamente a do começo.
    var runStartedAt: Date?
    
    // --- Mirror Frame ---
    var currentFrame: NSImage? = nil
    /// Resolucao real do alvo, lida do dispositivo.
    ///
    /// Antes a projecao do overlay usava 1080x1920 fixo, o que desalinhava a
    /// caixa de selecao em qualquer aparelho fora dessa proporcao, que hoje e
    /// a maioria (1080x2400, 1170x2532...).
    var deviceSize: CGSize = CGSize(width: 1080, height: 2400)

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
        let busca = SearchQuery(httpFilterText)
        let escopo = networkScope
        let janela = correlation.map { Set($0.requests) }
        if busca.isEmpty && escopo == .all && janela == nil { return httpRequests.reversed() }
        return httpRequests.reversed().filter {
            (janela?.contains($0.id) ?? true) && escopo.includes($0) && (busca.isEmpty || busca.matches($0))
        }
    }

    var filteredAnalyticsEvents: [AnalyticsEvent] {
        let busca = SearchQuery(analyticsFilterText)
        let janela = correlation.map { Set($0.events) }
        if busca.isEmpty && janela == nil { return analyticsEvents.reversed() }
        return analyticsEvents.reversed().filter { (janela?.contains($0.id) ?? true) && (busca.isEmpty || busca.matches($0)) }
    }
    
    // MARK: - Actions
    
    /// Modo Zen: esconde barra lateral e inspector e deixa espelho e
    /// workspace, que é onde o trabalho acontece. Ao sair, o inspector volta
    /// como estava antes: sair do Zen não abre a hierarquia sozinho.
    func toggleZenMode() {
        zenMode.toggle()
        sidebarVisibility = zenMode ? .detailOnly : .all
        if zenMode {
            inspectorAntesDoZen = inspectorVisible
            inspectorVisible = false
        } else {
            inspectorVisible = inspectorAntesDoZen
        }
        mirrorVisible = true
        workspaceVisible = true
    }

    @ObservationIgnored private var inspectorAntesDoZen = false

    func restoreAllPanels() {
        sidebarVisibility = .all
        inspectorVisible = true
        mirrorVisible = true
        workspaceVisible = true
        zenMode = false
    }
    
    func clearHTTPTraffic() {
        httpRequests.removeAll()
        correlation = nil
        selectedRequest = nil
    }
    
    func clearAnalyticsEvents() {
        analyticsEvents.removeAll()
        correlation = nil
        selectedAnalyticsEvent = nil
    }
    
    func clearSteps() {
        steps.removeAll()
        actionsCode = ""
        locatorsCode = ""
        selectedStepID = nil
        correlation = nil
    }

    // MARK: - Janela (redesenho 3.0)

    /// Barra lateral: áreas do workspace e passos do fluxo.
    var sidebarVisibility: NavigationSplitViewVisibility = .all
    /// Inspector com a hierarquia e os atributos. É a escolha da pessoa; o que
    /// aparece na janela é `inspectorShown`. O app abre com ele fechado
    /// (`atLaunch`), e só a pessoa o abre: botão da toolbar, ⌥⌘I, ⌘F na
    /// hierarquia ou Mostrar Todos os Painéis.
    var inspectorVisible: Bool = true
    /// Sem aparelho, numa área que precisa de um, o inspector só repetiria o
    /// "Conecte um aparelho" do estado vazio. Ele sai da janela e volta ao
    /// conectar, sem mexer na escolha da pessoa, como o Xcode faz (D3).
    /// No Início também: ele mostra o ambiente, e não há seleção a inspecionar.
    var inspectorSuppressed: Bool {
        workspaceTab == .home || workspaceTab == .environment || (!isDeviceConnected && workspaceTab.needsDevice)
    }
    var inspectorShown: Bool { inspectorVisible && !inspectorSuppressed }

    func toggleInspector() {
        guard !inspectorSuppressed else { return }
        inspectorVisible.toggle()
    }

    /// O espelho (o telefone) só existe com aparelho, nas áreas que precisam
    /// dele. Esconder deixa o workspace com a coluna inteira; ⌥1.
    var canToggleMirror: Bool { isDeviceConnected && workspaceTab.needsDevice }

    func toggleMirror() {
        guard canToggleMirror else { return }
        withAnimation(Motion.smooth()) { mirrorVisible.toggle() }
    }

    /// Estado da janela ao abrir o app: sempre no Início e com a hierarquia
    /// fechada. O padrão do modelo (Page Objects, inspector aberto) continua
    /// o das prévias e dos testes.
    static func atLaunch() -> AppState {
        let estado = AppState()
        estado.workspaceTab = .home
        estado.inspectorVisible = false
        return estado
    }

    /// A busca da hierarquia mora no inspector: sem ele na janela não há
    /// campo para focar (COD-4).
    var canSearchHierarchy: Bool { !inspectorSuppressed }

    /// Abre o inspector e pede foco no campo de busca da hierarquia.
    ///
    /// Com o inspector suprimido, não faz nada: antes, o pedido de foco ficava
    /// pendente e roubava o foco de repente ao conectar o aparelho, e a
    /// escolha `inspectorVisible` mudava sem a pessoa ter pedido.
    func requestHierarchySearch() {
        guard canSearchHierarchy else { return }
        inspectorVisible = true
        hierarchySearchFocusRequest += 1
    }

    /// ⌘F: em Rede, Analytics e Relatório, a busca da toolbar; nas outras, a
    /// da hierarquia, no inspector.
    var canSearch: Bool { usesToolbarSearch || canSearchHierarchy }

    func search() {
        if usesToolbarSearch {
            toolbarSearchPresented = true
        } else {
            requestHierarchySearch()
        }
    }
    /// Passo escolhido na seção Fluxo da barra lateral. Destaca o código dele.
    var selectedStepID: UUID? = nil
    /// Janela correlacionada de um passo (`session.correlate`): enquanto houver
    /// uma, Rede e Analytics mostram só o que caiu nela. Independe da seleção
    /// na barra lateral, para sobreviver à troca de área.
    var correlation: EngineDTO.Correlation? = nil

    var correlatedStep: AutomationStep? {
        guard let correlation else { return nil }
        return steps.first { $0.stepNum == correlation.stepNum }
    }

    func clearCorrelation() {
        correlation = nil
    }
    /// Confirmação de limpeza aberta (tráfego, eventos ou passos).
    var pendingClear: ClearKind? = nil
    /// Pedido de foco no campo de busca da hierarquia (⌘F em Page Objects).
    var hierarchySearchFocusRequest: Int = 0
    /// Busca da toolbar aberta (⌘F em Rede e Analytics).
    var toolbarSearchPresented: Bool = false
    /// Paleta de comandos aberta (⇧⌘P).
    var commandPalettePresented: Bool = false
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
