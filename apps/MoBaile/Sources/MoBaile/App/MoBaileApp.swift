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

    init() {
        let state = AppState()
        _appState = State(initialValue: state)
        _session = State(initialValue: EngineSession(state: state))
    }

    var body: some Scene {
        Window("Mo baile", id: "main") {
            ContentView()
                .environment(appState)
                .environment(session)
                .environment(themeManager)
                .frame(
                    minWidth: DesignMetrics.Window.minSize.width,
                    minHeight: DesignMetrics.Window.minSize.height
                )
                .preferredColorScheme(themeManager.preferredColorScheme)
                .onAppear { delegate.session = session }
        }
        .defaultSize(DesignMetrics.Window.defaultSize)
        .windowToolbarStyle(.unified)
        .commands {
            MoBaileCommands(appState: appState, session: session, themeManager: themeManager)
        }

        Settings {
            SettingsView()
                .environment(appState)
                .environment(session)
                .environment(themeManager)
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

    private var contexto: CommandContext { .current(appState, session, themeManager) }
    private var performer: CommandPerformer {
        CommandPerformer(appState: appState, session: session, themeManager: themeManager)
    }

    var body: some Commands {
        let c = contexto
        SidebarCommands()

        // MARK: Arquivo
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {
            item(.save, c)
        }
        CommandGroup(replacing: .importExport) {
            item(.openSpec, c)
            item(.importPrints, c)
            item(.exportReport, c)
            Divider()
            item(.exportHAR, c)
            item(.exportAnalytics, c)
        }

        // MARK: Editar
        CommandGroup(after: .pasteboard) {
            Divider()
            item(.search, c)
            Divider()
            item(.clearTraffic, c)
            item(.clearAnalytics, c)
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

            ForEach(InteractionMode.allCases) { modo in
                Toggle(modo.menuTitle, isOn: Binding(
                    get: { appState.interactionMode == modo },
                    set: { if $0 { performer.perform(.interaction(modo)) } }
                ))
                .disabled(!c.deviceConnected)
            }

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

extension InteractionMode {
    /// Título no menu Dispositivo, com maiúscula em cada palavra principal.
    var menuTitle: String {
        switch self {
        case .forward: return "Repassar Toque"
        case .record: return "Gravar Passo"
        }
    }
}
