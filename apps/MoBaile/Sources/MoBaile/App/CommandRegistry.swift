import SwiftUI

/// Registro único das ações do app (FLU-1).
///
/// Cada ação que menus, toolbar e botões oferecem tem aqui um título, uma
/// categoria, sinônimos de busca, o atalho e a disponibilidade no contexto. A
/// paleta de comandos lista daqui, e o menu lê título, atalho e
/// disponibilidade daqui também, para os dois não divergirem.
///
/// Nada aqui é regra de negócio nova. A disponibilidade repete as condições
/// `.disabled` que já existiam nas views, e a execução (`CommandPerformer`)
/// chama a `EngineSession` como os botões já faziam.

// MARK: - Identificadores

/// Identificador estável da ação. É o que vai para as recentes, então não
/// pode mudar à toa.
struct CommandID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { rawValue = value }

    static let palette: CommandID = "app.palette"
    static let settings: CommandID = "app.settings"
    static let restartEngine: CommandID = "app.restartEngine"

    static func area(_ area: WorkspaceTab) -> CommandID { CommandID(rawValue: "area.\(area.rawValue)") }

    static let inspector: CommandID = "view.inspector"
    static let mirror: CommandID = "view.mirror"
    static let workspace: CommandID = "view.workspace"
    static let allPanels: CommandID = "view.allPanels"
    static let zen: CommandID = "view.zen"
    static let appearance: CommandID = "view.appearance"
    static let search: CommandID = "view.search"

    static func selectDevice(_ id: String) -> CommandID { CommandID(rawValue: "device.select:\(id)") }
    static func switchPlatform(_ platform: Platform) -> CommandID { CommandID(rawValue: "device.platform.\(platform.rawValue)") }
    static let refreshDevices: CommandID = "device.refreshList"
    static let captureNow: CommandID = "device.captureNow"
    static let stream: CommandID = "device.stream"
    static func interaction(_ mode: InteractionMode) -> CommandID { CommandID(rawValue: "device.mode.\(mode.rawValue)") }
    static let bootSimulator: CommandID = "device.bootSimulator"
    static let bootEmulator: CommandID = "device.bootEmulator"
    static let scrcpy: CommandID = "device.scrcpy"

    static let startWDA: CommandID = "services.wda"
    static let proxy: CommandID = "services.proxy"
    static let debugNet: CommandID = "services.debugNet"
    static let analytics: CommandID = "services.analytics"

    static let passive: CommandID = "recording.passive"
    static let screenRecording: CommandID = "recording.screen"

    static let run: CommandID = "automation.run"
    static let stopRun: CommandID = "automation.stop"
    static let structure: CommandID = "automation.structure"
    static let save: CommandID = "automation.save"
    static let copyActions: CommandID = "automation.copyActions"
    static let copyLocators: CommandID = "automation.copyLocators"
    static let clearSteps: CommandID = "automation.clearSteps"

    static let exportHAR: CommandID = "network.exportHAR"
    static let clearTraffic: CommandID = "network.clear"

    static let exportAnalytics: CommandID = "analytics.exportJSON"
    static let clearAnalytics: CommandID = "analytics.clear"

    static let openSpec: CommandID = "report.openSpec"
    static let importPrints: CommandID = "report.importPrints"
    static let runReport: CommandID = "report.run"
    static let exportReport: CommandID = "report.export"
}

enum CommandCategory: String, CaseIterable, Sendable {
    case areas = "Áreas"
    case view = "Visualizar"
    case device = "Aparelho"
    case services = "Serviços"
    case recording = "Gravação"
    case automation = "Automação"
    case network = "Rede"
    case analytics = "Analytics"
    case report = "Relatório"
    case app = "App"
}

/// Atalho de teclado, no formato que o menu e a paleta usam.
struct CommandShortcut: Equatable, Sendable {
    let key: Character
    let modifiers: EventModifiers

    var keyEquivalent: KeyEquivalent { KeyEquivalent(key) }

    /// "⇧⌘P", na ordem do macOS: ⌃ ⌥ ⇧ ⌘.
    var display: String {
        var texto = ""
        if modifiers.contains(.control) { texto += "⌃" }
        if modifiers.contains(.option) { texto += "⌥" }
        if modifiers.contains(.shift) { texto += "⇧" }
        if modifiers.contains(.command) { texto += "⌘" }
        return texto + String(key).uppercased()
    }

    /// O que o VoiceOver lê: "Shift Command P".
    var spoken: String {
        var partes: [String] = []
        if modifiers.contains(.control) { partes.append("Control") }
        if modifiers.contains(.option) { partes.append("Option") }
        if modifiers.contains(.shift) { partes.append("Shift") }
        if modifiers.contains(.command) { partes.append("Command") }
        partes.append(key == "," ? "vírgula" : String(key).uppercased())
        return partes.joined(separator: " ")
    }

    static func cmd(_ key: Character) -> CommandShortcut { CommandShortcut(key: key, modifiers: .command) }
    static func cmdShift(_ key: Character) -> CommandShortcut { CommandShortcut(key: key, modifiers: [.command, .shift]) }
    static func cmdOption(_ key: Character) -> CommandShortcut { CommandShortcut(key: key, modifiers: [.command, .option]) }
    static func option(_ key: Character) -> CommandShortcut { CommandShortcut(key: key, modifiers: .option) }
}

/// Uma ação no contexto atual.
struct AppCommand: Identifiable, Equatable, Sendable {
    let id: CommandID
    let title: String
    let category: CommandCategory
    let symbol: String
    var keywords: [String] = []
    var shortcut: CommandShortcut? = nil
    /// Por que a ação não pode rodar agora, em texto para a pessoa. `nil` é
    /// disponível.
    var disabledReason: String? = nil
    /// Fica no registro (o menu lê), mas não aparece na paleta.
    var hiddenFromPalette = false

    var isEnabled: Bool { disabledReason == nil }
}

// MARK: - Contexto

/// Fotografia do estado que decide título e disponibilidade das ações.
///
/// É um valor simples para o registro ser uma função pura e testável sem
/// janela nem motor.
struct CommandContext: Equatable, Sendable {
    var engineConnected = true
    var engineRestarting = false
    var platform: Platform = .ios
    var workspaceTab: WorkspaceTab = .pageObjects
    var devices: [DeviceOption] = []
    var selectedDevice: String? = nil
    var stepCount = 0
    var hasCode = false
    var hasActionsCode = false
    var hasLocatorsCode = false
    var running = false
    var streamActive = false
    var interactionMode: InteractionMode = .forward
    var proxyRunning = false
    var debugNetActive = false
    var analyticsActive = false
    var canStartAnalytics = false
    var passiveListening = false
    /// No iOS, a escuta passiva só existe no Simulator.
    var passiveSupported = true
    var screenRecording = false
    var scrcpyAvailable = false
    var scrcpyRunning = false
    var httpCount = 0
    var analyticsCount = 0
    var inspectorShown = true
    var inspectorSuppressed = false
    var mirrorVisible = true
    var workspaceVisible = true
    var zenMode = false
    var usesToolbarSearch = false
    var paletteActive = false
    var isDark = false
    var hasSimulators = false
    var hasAvds = false
    var isBooting = false
    var wdaRunning = false
    var reportBusy = false
    var hasReportSpec = false
    var canRunReport = false
    var hasReport = false

    struct DeviceOption: Equatable, Sendable {
        let id: String
        let name: String
    }

    var deviceConnected: Bool { selectedDevice != nil }
}

extension CommandContext {
    /// Lê o contexto do estado real do app.
    @MainActor
    static func current(_ appState: AppState, _ session: EngineSession, _ theme: ThemeManager?) -> CommandContext {
        var c = CommandContext()
        c.engineConnected = session.isConnected
        c.engineRestarting = session.isRecovering
        c.platform = appState.platform
        c.workspaceTab = appState.workspaceTab
        c.devices = appState.availableDevices.map { DeviceOption(id: $0.id, name: $0.name.isEmpty ? $0.id : $0.name) }
        c.selectedDevice = appState.selectedDevice
        c.stepCount = appState.steps.count
        c.hasActionsCode = !appState.actionsCode.isEmpty
        c.hasLocatorsCode = !appState.locatorsCode.isEmpty
        c.hasCode = c.hasActionsCode || c.hasLocatorsCode
        c.running = appState.runState == .running
        c.streamActive = appState.streamActive
        c.interactionMode = appState.interactionMode
        c.proxyRunning = appState.proxyRunning
        c.debugNetActive = appState.debugNetActive
        c.analyticsActive = appState.analyticsListenerActive
        c.canStartAnalytics = appState.canStartAnalytics
        c.passiveListening = appState.passiveListening
        c.passiveSupported = appState.platform != .ios
            || session.simulators.contains { $0.udid == appState.selectedDevice }
        c.screenRecording = appState.screenRecording
        c.scrcpyAvailable = appState.scrcpyAvailable
        c.scrcpyRunning = appState.scrcpyRunning
        c.httpCount = appState.httpRequests.count
        c.analyticsCount = appState.analyticsEvents.count
        c.inspectorShown = appState.inspectorShown
        c.inspectorSuppressed = appState.inspectorSuppressed
        c.mirrorVisible = appState.mirrorVisible
        c.workspaceVisible = appState.workspaceVisible
        c.zenMode = appState.zenMode
        c.usesToolbarSearch = appState.usesToolbarSearch
        c.paletteActive = theme?.palette != nil
        c.isDark = theme?.isDark ?? false
        c.hasSimulators = !session.simulators.isEmpty
        c.hasAvds = !session.avds.isEmpty
        c.isBooting = session.isBooting
        c.wdaRunning = appState.daemonStatus.wda == .ok
        c.reportBusy = appState.reportOperation != nil
        c.hasReportSpec = appState.reportSpec != nil
        c.canRunReport = appState.canRunReport
        c.hasReport = appState.report != nil
        return c
    }
}

// MARK: - Registro

enum CommandRegistry {
    /// Motivos repetidos, num lugar só para o texto não variar.
    enum Motivo {
        static let semAparelho = "Conecte um aparelho"
        static let motorParado = "O motor está parado"
        static let motorReiniciando = "O motor está reiniciando"
        static let semPassos = "Grave ao menos um passo"
        static let semCodigo = "Ainda não há código gerado"
        static let semTrafego = "Nenhuma requisição capturada"
        static let semEventos = "Nenhum evento capturado"
        static let relatorioOcupado = "Espere a operação do relatório terminar"
    }

    /// Todas as ações, na ordem em que a paleta mostra sem busca.
    static func commands(in c: CommandContext) -> [AppCommand] {
        let motor: String? = c.engineConnected ? nil : (c.engineRestarting ? Motivo.motorReiniciando : Motivo.motorParado)
        let aparelho: String? = motor ?? (c.deviceConnected ? nil : Motivo.semAparelho)

        var lista: [AppCommand] = []

        // Áreas
        for (indice, area) in WorkspaceTab.allCases.enumerated() {
            lista.append(AppCommand(
                id: .area(area), title: "Ir para \(area.displayName)", category: .areas, symbol: area.symbolName,
                keywords: area.keywords + ["área", "aba", "seção"],
                shortcut: .cmd(Character("\(indice + 1)")),
                disabledReason: c.workspaceTab == area ? "Você já está em \(area.displayName)" : nil
            ))
        }

        // Visualizar
        lista += [
            AppCommand(
                id: .inspector, title: c.inspectorShown ? "Ocultar Inspector" : "Mostrar Inspector",
                category: .view, symbol: "sidebar.right",
                keywords: ["hierarquia", "atributos", "painel", "lateral", "alternar"],
                shortcut: .cmdOption("i"),
                disabledReason: c.inspectorSuppressed ? "O inspector volta ao conectar um aparelho" : nil
            ),
            AppCommand(
                id: .mirror, title: c.mirrorVisible ? "Ocultar Espelho" : "Mostrar Espelho",
                category: .view, symbol: "iphone", keywords: ["tela", "painel", "alternar"], shortcut: .option("1")
            ),
            AppCommand(
                id: .workspace, title: c.workspaceVisible ? "Ocultar Workspace" : "Mostrar Workspace",
                category: .view, symbol: "rectangle.split.2x1", keywords: ["código", "editor", "painel", "alternar"],
                shortcut: .option("2")
            ),
            AppCommand(
                id: .allPanels, title: "Mostrar Todos os Painéis", category: .view, symbol: "rectangle.3.group",
                keywords: ["restaurar", "painéis", "layout"], shortcut: .cmdOption("f")
            ),
            AppCommand(
                id: .zen, title: c.zenMode ? "Sair do Modo Zen" : "Modo Zen", category: .view, symbol: "rectangle.inset.filled",
                keywords: ["foco", "tela cheia", "esconder", "concentrar"],
                shortcut: CommandShortcut(key: "z", modifiers: [.command, .control])
            ),
            AppCommand(
                id: .appearance, title: c.isDark ? "Usar Aparência Clara" : "Usar Aparência Escura",
                category: .view, symbol: c.isDark ? "sun.max" : "moon",
                keywords: ["tema", "modo escuro", "modo claro", "dark", "light", "aparência", "alternar"],
                disabledReason: c.paletteActive ? "A paleta escolhida em Ajustes define a aparência" : nil
            ),
        ]
        if c.usesToolbarSearch {
            lista.append(AppCommand(
                id: .search, title: "Buscar em \(c.workspaceTab.displayName)", category: .view, symbol: "magnifyingglass",
                keywords: ["filtro", "filtrar", "localizar"], shortcut: .cmd("f")
            ))
        } else {
            lista.append(AppCommand(
                id: .search, title: "Buscar na Hierarquia", category: .view, symbol: "magnifyingglass",
                keywords: ["elemento", "árvore", "filtro", "localizar", "inspector"], shortcut: .cmd("f"),
                disabledReason: c.inspectorSuppressed ? Motivo.semAparelho : nil
            ))
        }

        // Aparelho
        for device in c.devices {
            lista.append(AppCommand(
                id: .selectDevice(device.id), title: "Usar \(device.name)", category: .device,
                symbol: c.platform == .ios ? "iphone" : "smartphone",
                keywords: ["aparelho", "dispositivo", "selecionar", "trocar", "conectar", device.id, c.platform.displayName],
                disabledReason: motor ?? (c.selectedDevice == device.id ? "Já é o aparelho em uso" : nil)
            ))
        }
        let outra: Platform = c.platform == .ios ? .android : .ios
        lista += [
            AppCommand(
                id: .switchPlatform(outra), title: "Procurar Aparelhos \(outra.displayName)", category: .device,
                symbol: "arrow.left.arrow.right", keywords: ["plataforma", "trocar", "dispositivo", outra.displayName],
                disabledReason: motor
            ),
            AppCommand(
                id: .refreshDevices, title: "Atualizar Lista de Aparelhos", category: .device, symbol: "arrow.clockwise",
                keywords: ["dispositivos", "recarregar", "verificar", "detectar"], shortcut: .cmdShift("r"),
                disabledReason: motor
            ),
            AppCommand(
                id: .captureNow, title: "Atualizar Tela", category: .device, symbol: "camera.viewfinder",
                keywords: ["espelho", "captura", "screenshot", "recarregar", "hierarquia"], shortcut: .cmd("k"),
                disabledReason: aparelho
            ),
            AppCommand(
                id: .stream, title: c.streamActive ? "Parar Espelho" : "Iniciar Espelho", category: .device,
                symbol: c.streamActive ? "pause.circle" : "play.circle", keywords: ["tela", "ao vivo", "stream", "espelhar"],
                shortcut: .cmd("e"), disabledReason: aparelho
            ),
        ]
        for modo in InteractionMode.allCases {
            lista.append(AppCommand(
                id: .interaction(modo), title: "Clique no Espelho: \(modo.menuTitle)", category: .device, symbol: modo.symbolName,
                keywords: ["modo", "clique", "toque", "tap"],
                disabledReason: aparelho ?? (c.interactionMode == modo ? "Já é o modo em uso" : nil)
            ))
        }
        lista += [
            AppCommand(
                id: .bootSimulator, title: "Abrir Simulador", category: .device, symbol: "iphone.gen3",
                keywords: ["simulator", "ios", "xcode", "ligar"],
                disabledReason: motor ?? (c.isBooting ? "Outro aparelho está iniciando" : (c.hasSimulators ? nil : "Nenhum simulador instalado"))
            ),
            AppCommand(
                id: .bootEmulator, title: "Abrir Emulador Android", category: .device, symbol: "smartphone",
                keywords: ["avd", "android studio", "ligar"],
                disabledReason: motor ?? (c.isBooting ? "Outro aparelho está iniciando" : (c.hasAvds ? nil : "Nenhum emulador (AVD) criado"))
            ),
            AppCommand(
                id: .scrcpy, title: c.scrcpyRunning ? "Fechar Espelho 60 FPS" : "Abrir Espelho 60 FPS (scrcpy)",
                category: .device, symbol: c.scrcpyRunning ? "bolt.fill" : "bolt", keywords: ["scrcpy", "fps", "nativo", "rápido"],
                disabledReason: aparelho ?? (c.platform != .android ? "Só no Android"
                    : (c.scrcpyAvailable ? nil : "Instale o scrcpy com brew install scrcpy"))
            ),
        ]

        // Serviços
        lista += [
            AppCommand(
                id: .startWDA, title: "Iniciar WebDriverAgent", category: .services, symbol: "antenna.radiowaves.left.and.right",
                keywords: ["wda", "appium", "ios", "ligar"],
                disabledReason: motor ?? (c.platform != .ios ? "Só no iOS"
                    : (c.wdaRunning ? "O WebDriverAgent já está no ar" : (c.isBooting ? "Outra operação está iniciando" : nil)))
            ),
            AppCommand(
                id: .proxy, title: c.proxyRunning ? "Parar Proxy" : "Iniciar Proxy", category: .services, symbol: "network",
                keywords: ["mitm", "rede", "http", "https", "tráfego", "interceptar"], disabledReason: motor
            ),
            AppCommand(
                id: .debugNet, title: c.debugNetActive ? "Parar Leitura do App em Debug" : "Ler Tráfego do App em Debug",
                category: .services, symbol: c.debugNetActive ? "stop.circle" : DebugNetCopy(c.platform).icone,
                keywords: ["debug", "okhttp", "cfnetwork", "rede", "tráfego", "sem proxy"],
                disabledReason: motor ?? ((c.platform == .android && !c.deviceConnected && !c.debugNetActive) ? Motivo.semAparelho : nil)
            ),
            AppCommand(
                id: .analytics, title: c.analyticsActive ? "Parar Escuta de Analytics" : "Iniciar Escuta de Analytics",
                category: .services, symbol: "chart.bar", keywords: ["firebase", "fa", "eventos", "tagueamento", "listener", "escutar"],
                disabledReason: motor ?? ((c.analyticsActive || c.canStartAnalytics) ? nil : Motivo.semAparelho)
            ),
        ]

        // Gravação
        lista += [
            AppCommand(
                id: .passive, title: c.passiveListening ? "Parar Captura do Aparelho" : "Gravar do Aparelho",
                category: .recording, symbol: c.passiveListening ? "stop.circle.fill" : "hand.tap",
                keywords: ["passos", "toques", "escuta passiva", "gravar"],
                disabledReason: aparelho ?? (c.passiveSupported ? nil : "No iPhone físico, use o clique no espelho")
            ),
            AppCommand(
                id: .screenRecording, title: c.screenRecording ? "Parar de Gravar a Tela" : "Gravar a Tela",
                category: .recording, symbol: c.screenRecording ? "stop.circle.fill" : "video",
                keywords: ["vídeo", "filmar", "gravação"], disabledReason: aparelho
            ),
        ]

        // Automação
        lista += [
            AppCommand(
                id: .run, title: "Rodar Automação", category: .automation, symbol: "play.fill",
                keywords: ["executar", "fluxo", "teste", "play", "replay"], shortcut: .cmd("r"),
                disabledReason: c.stepCount == 0 ? Motivo.semPassos : (aparelho ?? (c.running ? "Já está rodando" : nil))
            ),
            AppCommand(
                id: .stopRun, title: "Interromper Execução", category: .automation, symbol: "stop.fill",
                keywords: ["parar", "cancelar", "fluxo"], disabledReason: c.running ? motor : "Nada está rodando"
            ),
            AppCommand(
                id: .structure, title: "Estrutura do Fluxo…", category: .automation, symbol: "list.number",
                keywords: ["passos", "tabela", "resumo"], disabledReason: c.stepCount == 0 ? Motivo.semPassos : nil
            ),
            AppCommand(
                id: .save, title: "Salvar Page Object", category: .automation, symbol: "square.and.arrow.down",
                keywords: ["código", "gerar", "pages", "locators", "arquivo", "exportar"], shortcut: .cmd("s"),
                disabledReason: motor ?? (c.hasCode ? nil : Motivo.semCodigo)
            ),
            AppCommand(
                id: .copyActions, title: "Copiar Código das Ações", category: .automation, symbol: "doc.on.doc",
                keywords: ["page object", "pages", "código", "clipboard"], disabledReason: c.hasActionsCode ? nil : Motivo.semCodigo
            ),
            AppCommand(
                id: .copyLocators, title: "Copiar Localizadores", category: .automation, symbol: "doc.on.doc",
                keywords: ["locators", "seletores", "código", "clipboard"], disabledReason: c.hasLocatorsCode ? nil : Motivo.semCodigo
            ),
            AppCommand(
                id: .clearSteps, title: "Limpar Passos…", category: .automation, symbol: "trash",
                keywords: ["apagar", "zerar", "fluxo", "código"], disabledReason: c.stepCount == 0 ? Motivo.semPassos : nil
            ),
        ]

        // Rede e Analytics
        lista += [
            AppCommand(
                id: .exportHAR, title: "Exportar HAR…", category: .network, symbol: "square.and.arrow.up",
                keywords: ["tráfego", "salvar", "arquivo", "http"], shortcut: .cmdShift("e"),
                disabledReason: c.httpCount == 0 ? Motivo.semTrafego : nil
            ),
            AppCommand(
                id: .clearTraffic, title: "Limpar Tráfego…", category: .network, symbol: "trash",
                keywords: ["apagar", "requisições", "http"], disabledReason: c.httpCount == 0 ? Motivo.semTrafego : nil
            ),
            AppCommand(
                id: .exportAnalytics, title: "Exportar JSON de Analytics…", category: .analytics, symbol: "square.and.arrow.up",
                keywords: ["eventos", "salvar", "arquivo", "firebase"], disabledReason: c.analyticsCount == 0 ? Motivo.semEventos : nil
            ),
            AppCommand(
                id: .clearAnalytics, title: "Limpar Eventos…", category: .analytics, symbol: "trash",
                keywords: ["apagar", "eventos", "firebase"], disabledReason: c.analyticsCount == 0 ? Motivo.semEventos : nil
            ),
        ]

        // Relatório
        lista += [
            AppCommand(
                id: .openSpec, title: "Abrir Spec de Tagueamento…", category: .report, symbol: "doc.text",
                keywords: ["figma", "spec", "json", "arquivo"], shortcut: .cmd("o"),
                disabledReason: c.reportBusy ? Motivo.relatorioOcupado : nil
            ),
            AppCommand(
                id: .importPrints, title: "Importar Prints do Figma…", category: .report, symbol: "photo.on.rectangle",
                keywords: ["figma", "imagens", "cards"], disabledReason: c.reportBusy ? Motivo.relatorioOcupado : nil
            ),
            AppCommand(
                id: .runReport, title: "Auditar Tagueamento", category: .report, symbol: "checklist",
                keywords: ["relatório", "validar", "conferir", "auditoria"],
                disabledReason: c.canRunReport ? motor
                    : (!c.hasReportSpec ? "Abra uma spec de tagueamento"
                       : (c.reportBusy ? Motivo.relatorioOcupado : "Capture eventos de analytics ou escolha um arquivo de log"))
            ),
            AppCommand(
                id: .exportReport, title: "Exportar Relatório…", category: .report, symbol: "square.and.arrow.up",
                keywords: ["html", "excalidraw", "salvar"],
                disabledReason: !c.hasReport ? "Rode a auditoria antes" : (c.reportBusy ? Motivo.relatorioOcupado : nil)
            ),
        ]

        // App
        lista += [
            AppCommand(
                id: .settings, title: "Ajustes…", category: .app, symbol: "gearshape",
                keywords: ["preferências", "configurações", "paletas", "conexões", "portas"],
                shortcut: .cmd(",")
            ),
            AppCommand(
                id: .restartEngine, title: "Reiniciar Motor", category: .app, symbol: "arrow.triangle.2.circlepath",
                keywords: ["engine", "python", "reconectar", "travou"],
                disabledReason: c.engineRestarting ? Motivo.motorReiniciando : nil
            ),
            AppCommand(
                id: .palette, title: "Paleta de Comandos…", category: .app, symbol: "command",
                keywords: ["ações", "comandos"], shortcut: .cmdShift("p"), hiddenFromPalette: true
            ),
        ]
        return lista
    }

    /// A ação com este identificador no contexto, para o menu.
    static func command(_ id: CommandID, in c: CommandContext) -> AppCommand? {
        commands(in: c).first { $0.id == id }
    }
}

extension WorkspaceTab {
    /// Outros nomes que as pessoas usam para a área.
    var keywords: [String] {
        switch self {
        case .pageObjects: return ["código", "passos", "fluxo", "locators", "automação"]
        case .network: return ["http", "proxy", "tráfego", "requisições"]
        case .analytics: return ["firebase", "eventos", "tagueamento"]
        case .report: return ["auditoria", "spec", "figma", "tagueamento"]
        }
    }
}
