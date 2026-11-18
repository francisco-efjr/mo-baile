import SwiftUI

@main
struct MoBaileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// Estado da interface e coordenador do motor sao criados uma vez e
    /// injetados pelo ambiente. O coordenador recebe o estado no construtor
    /// porque a direcao da dependencia importa: ele escreve no estado, o
    /// estado nunca chama o coordenador.
    @State private var appState: AppState
    @State private var session: EngineSession
    @State private var themeManager = ThemeManager()
    /// Aviso e instalação de versão nova (LIB-4, ADR 0008): confere o GitHub a
    /// cada duas horas com o app aberto, avisa por faixa e notificação, e pode
    /// ser desligado em Ajustes › Geral.
    @State private var updates: UpdateState
    /// Ajuda por área (LIB-2) e relato de bug (LIB-3): estado que sobrevive a
    /// fechar e reabrir as janelas durante a sessão.
    @State private var help = HelpNavigator()
    @State private var bugReport = BugReportModel()

    init() {
        let state = AppState.atLaunch()
        _appState = State(initialValue: state)
        _session = State(initialValue: EngineSession(state: state))
        _updates = State(initialValue: UpdateState())
        // O delegado das notificações entra antes de o app terminar de abrir:
        // assim o clique em Atualizar que abriu o app não se perde. O estado
        // é ligado na janela, com a instância que a cena guardou.
        UpdateNotifier.shared.configure()
    }

    var body: some Scene {
        Window("Mo baile", id: "main") {
            ContentView()
                .environment(appState)
                .environment(session)
                .environment(themeManager)
                .environment(updates)
                .environment(help)
                .frame(
                    minWidth: DesignMetrics.Window.minSize.width,
                    minHeight: DesignMetrics.Window.minSize.height
                )
                .preferredColorScheme(themeManager.preferredColorScheme)
                .onAppear { delegate.session = session }
                // A janela espera o splash de abertura sair (SplashController).
                .background(WindowReader { SplashController.shared.hold($0) })
                // Janela oculta pausa o espelho no motor (PERF-1).
                .background(WindowReader { WindowVisibility.shared.observe($0, session: session) })
                .task {
                    UpdateNotifier.shared.attach(updates)
                    updates.startAutomaticChecks()
                }
        }
        .defaultSize(DesignMetrics.Window.defaultSize)
        .windowToolbarStyle(.unified)
        .commands {
            MoBaileCommands(appState: appState, session: session, themeManager: themeManager, updates: updates, help: help)
        }

        // Ajuda do Mo baile (⌘?): guias curtos por área, de `docs/ajuda`.
        Window("Ajuda do Mo baile", id: "ajuda") {
            HelpWindow()
                .environment(appState)
                .environment(help)
                .environment(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .tint(themeManager.current.accent)
        }
        .defaultSize(width: 760, height: 560)

        // Relatar um Problema (⇧⌘B): vira uma issue no GitHub.
        Window("Relatar um Problema", id: "relato") {
            BugReportWindow()
                .environment(bugReport)
                .environment(themeManager)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .tint(themeManager.current.accent)
                .onAppear { bugReport.prepare(area: appState.workspaceTab, device: appState.selectedDeviceName) }
        }
        .defaultSize(width: 540, height: 680)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environment(appState)
                .environment(session)
                .environment(themeManager)
                .environment(updates)
                .preferredColorScheme(themeManager.preferredColorScheme)
                .tint(themeManager.current.accent)
        }
    }
}

/// Menus nativos.
///
/// Atalho de aplicativo Mac vive no menu, e nao em `Button` invisivel dentro da
/// hierarquia de views: no menu ele aparece descoberto pelo usuario, funciona
/// com foco em qualquer painel e e lido por tecnologia assistiva. Toda acao da
/// toolbar tambem aparece aqui.
///
/// Título, atalho e disponibilidade de cada item vêm do `CommandRegistry`, o
/// mesmo que a paleta de comandos lê (FLU-1), e a execução passa pelo
/// `CommandPerformer`. Ficam como `Toggle` próprios só os itens com marca de
/// seleção (área, modo do clique, 60 FPS).
struct MoBaileCommands: Commands {
    let appState: AppState
    let session: EngineSession
    let themeManager: ThemeManager
    let updates: UpdateState
    let help: HelpNavigator

    private var contexto: CommandContext { .current(appState, session, themeManager) }
    private var performer: CommandPerformer {
        CommandPerformer(appState: appState, session: session, themeManager: themeManager)
    }

    var body: some Commands {
        let c = contexto
        SidebarCommands()

        // Sobre, atualizações e Ajuda (LIB-2, LIB-3, LIB-4).
        SupportCommands(appState: appState, updates: updates, help: help)

        // MARK: Arquivo
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {
            item(.save, c)
        }
        CommandGroup(replacing: .importExport) {
            item(.openSpec, c)
            item(.importPrints, c)
            item(.exportReport, c)
            item(.exportChecklist, c)
            Divider()
            item(.exportHAR, c)
            item(.exportAnalytics, c)
            item(.exportFlow, c)
        }

        // MARK: Editar
        CommandGroup(after: .pasteboard) {
            Divider()
            item(.search, c)
            Divider()
            item(.clearTraffic, c)
            item(.clearAnalytics, c)
            Divider()
            item(.diagnoseTraffic, c)
        }

        // MARK: Visualizar
        CommandGroup(after: .sidebar) {
            item(.palette, c)
            Divider()
            item(.inspector, c)
            item(.mirror, c)
            item(.workspace, c)
            item(.allPanels, c)
            item(.zen, c)
            Divider()
            ForEach(WorkspaceTab.allCases, id: \.self) { area in
                let atalho = CommandRegistry.command(.area(area), in: c)?.shortcut
                Toggle(area.displayName, isOn: Binding(
                    get: { appState.workspaceTab == area && appState.selectedStepID == nil },
                    set: { _ in performer.perform(.area(area)) }
                ))
                .keyboardShortcut(atalho?.keyEquivalent ?? KeyEquivalent(" "), modifiers: atalho?.modifiers ?? [])
            }
        }

        // MARK: Dispositivo
        CommandMenu("Dispositivo") {
            item(.refreshDevices, c)
            item(.captureNow, c)
            item(.stream, c)

            Divider()

            item(.passive, c)
            item(.screenRecording, c)
            Toggle("Espelho 60 FPS (scrcpy)", isOn: Binding(
                get: { appState.scrcpyRunning },
                set: { _ in performer.perform(.scrcpy) }
            ))
            .disabled(!(CommandRegistry.command(.scrcpy, in: c)?.isEnabled ?? false))

            Divider()
            item(.restartEngine, c)
        }

        // MARK: Automação
        CommandMenu("Automação") {
            item(.structure, c)
            item(.run, c)
            item(.exportFlow, c)
            Divider()
            item(.clearSteps, c)
        }

        // MARK: Janela
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Mostrar Splash") { SplashController.shared.show() }
        }
    }

    /// Item de menu lido do registro: título, atalho e disponibilidade.
    @ViewBuilder
    private func item(_ id: CommandID, _ c: CommandContext) -> some View {
        if let comando = CommandRegistry.command(id, in: c) {
            let botao = Button(comando.title) { performer.perform(id) }
                .disabled(!comando.isEnabled)
            if let atalho = comando.shortcut {
                botao.keyboardShortcut(atalho.keyEquivalent, modifiers: atalho.modifiers)
            } else {
                botao
            }
        }
    }
}

/// Menus de apoio: Sobre, Buscar Atualizações e Ajuda. Ficam num `Commands`
/// próprio porque o construtor de comandos aceita no máximo 10 grupos.
struct SupportCommands: Commands {
    let appState: AppState
    let updates: UpdateState
    let help: HelpNavigator

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // MARK: Mo baile
        CommandGroup(replacing: .appInfo) {
            Button("Sobre o Mo baile") { AboutPanel.show() }
        }
        CommandGroup(after: .appInfo) {
            Button("Buscar Atualizações…") {
                Task { @MainActor in
                    let resultado = await updates.checkNow()
                    UpdateAlert.show(resultado, installed: updates.currentVersion)
                }
            }
            .disabled(updates.checking)
        }

        // MARK: Ajuda (LIB-2, LIB-3)
        CommandGroup(replacing: .help) {
            Button("Ajuda do Mo baile") {
                help.topic = appState.workspaceTab.rawValue
                openWindow(id: "ajuda")
            }
            .keyboardShortcut("?", modifiers: .command)
            Button("Todos os Tópicos") {
                help.topic = "comecando"
                openWindow(id: "ajuda")
            }
            Divider()
            Button("Relatar um Problema…") { openWindow(id: "relato") }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            if let changelog = HomeWhatsNewCard.changelog {
                Button("Novidades da Versão") { NSWorkspace.shared.open(changelog) }
            }
        }
    }
}
