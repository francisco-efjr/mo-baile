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
        WindowGroup {
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
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            MoBaileCommands(appState: appState, session: session)
        }
    }
}

/// Menus nativos.
///
/// Atalho de aplicativo Mac vive no menu, e nao em `Button` invisivel dentro da
/// hierarquia de views: no menu ele aparece descoberto pelo usuario, funciona
/// com foco em qualquer painel e e lido por tecnologia assistiva.
struct MoBaileCommands: Commands {
    let appState: AppState
    let session: EngineSession

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Espelho") { appState.mirrorVisible.toggle() }
                .keyboardShortcut("1", modifiers: .option)
            Button("Workspace") { appState.workspaceVisible.toggle() }
                .keyboardShortcut("2", modifiers: .option)
            Divider()
            Button("Mostrar todos os paineis") { appState.restoreAllPanels() }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button(appState.zenMode ? "Sair do modo Zen" : "Modo Zen") { appState.toggleZenMode() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandMenu("Dispositivo") {
            Button("Atualizar lista") {
                Task { await session.refreshDevices() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Atualizar tela") {
                Task { await session.captureNow() }
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(!appState.isDeviceConnected)

            Divider()

            Button(appState.streamActive ? "Parar espelho" : "Iniciar espelho") {
                Task {
                    if appState.streamActive {
                        await session.stopStream()
                    } else {
                        await session.startStream()
                    }
                }
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!appState.isDeviceConnected)
        }
    }
}
