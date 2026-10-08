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
            MoBaileCommands(appState: appState, session: session)
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
struct MoBaileCommands: Commands {
    let appState: AppState
    let session: EngineSession

    var body: some Commands {
        SidebarCommands()

        // MARK: Arquivo
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {
            Button("Salvar Page Object") {
                Task { await session.saveCode() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState.actionsCode.isEmpty && appState.locatorsCode.isEmpty)
        }
        CommandGroup(replacing: .importExport) {
            Button("Exportar HAR…") { Exporters.exportHAR(appState) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.httpRequests.isEmpty)
            Button("Exportar JSON de Analytics…") { Exporters.exportAnalyticsJSON(appState) }
                .disabled(appState.analyticsEvents.isEmpty)
        }

        // MARK: Editar
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Buscar") { buscar() }
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Button("Limpar Tráfego…") { appState.pendingClear = .network }
                .disabled(appState.httpRequests.isEmpty)
            Button("Limpar Eventos…") { appState.pendingClear = .analytics }
                .disabled(appState.analyticsEvents.isEmpty)
        }

        // MARK: Visualizar
        CommandGroup(after: .sidebar) {
            Button(appState.inspectorVisible ? "Ocultar Inspector" : "Mostrar Inspector") {
                appState.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            Button(appState.mirrorVisible ? "Ocultar Espelho" : "Mostrar Espelho") {
                withAnimation(Motion.smooth()) { appState.mirrorVisible.toggle() }
            }
            .keyboardShortcut("1", modifiers: .option)
            Button(appState.workspaceVisible ? "Ocultar Workspace" : "Mostrar Workspace") {
                withAnimation(Motion.smooth()) { appState.workspaceVisible.toggle() }
            }
            .keyboardShortcut("2", modifiers: .option)
            Button("Mostrar Todos os Painéis") {
                withAnimation(Motion.smooth()) { appState.restoreAllPanels() }
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            Button(appState.zenMode ? "Sair do Modo Zen" : "Modo Zen") {
                withAnimation(Motion.smooth()) { appState.toggleZenMode() }
            }
            .keyboardShortcut("z", modifiers: [.command, .control])
            Divider()
            ForEach(Array(WorkspaceTab.allCases.enumerated()), id: \.element) { indice, area in
                Toggle(area.displayName, isOn: Binding(
                    get: { appState.workspaceTab == area && appState.selectedStepID == nil },
                    set: { _ in
                        appState.selectedStepID = nil
                        appState.workspaceTab = area
                    }
                ))
                .keyboardShortcut(KeyEquivalent(Character("\(indice + 1)")), modifiers: .command)
            }
        }

        // MARK: Dispositivo
        CommandMenu("Dispositivo") {
            Button("Atualizar Lista") {
                Task { await session.refreshDevices() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Atualizar Tela") {
                Task { await session.captureNow() }
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(!appState.isDeviceConnected)

            Button(appState.streamActive ? "Parar Espelho" : "Iniciar Espelho") {
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

            Divider()

            ForEach(InteractionMode.allCases) { modo in
                Toggle(modo.menuTitle, isOn: Binding(
                    get: { appState.interactionMode == modo },
                    set: { if $0 { appState.interactionMode = modo } }
                ))
                .disabled(!appState.isDeviceConnected)
            }

            Divider()

            Button(appState.passiveListening ? "Parar Captura do Aparelho" : "Gravar do Aparelho") {
                Task {
                    if appState.passiveListening { await session.stopPassive() } else { await session.startPassive() }
                }
            }
            .disabled(!appState.isDeviceConnected)
            Button(appState.screenRecording ? "Parar de Gravar a Tela" : "Gravar a Tela") {
                Task {
                    if appState.screenRecording { await session.stopScreenRecording() } else { await session.startScreenRecording() }
                }
            }
            .disabled(!appState.isDeviceConnected)
            Toggle("Espelho 60 FPS (scrcpy)", isOn: Binding(
                get: { appState.scrcpyRunning },
                set: { _ in Task { await session.toggleScrcpy() } }
            ))
            .disabled(!appState.isDeviceConnected || appState.platform != .android || !appState.scrcpyAvailable)
        }

        // MARK: Automação
        CommandMenu("Automação") {
            Button("Estrutura do Fluxo…") { appState.showingStructure = true }
                .disabled(appState.steps.isEmpty)
            Button("Rodar Automação") {
                RunAutomationButton.run(appState: appState, session: session)
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!RunAutomationButton.podeRodar(appState))
            Divider()
            Button("Limpar Passos…") { appState.pendingClear = .steps }
                .disabled(appState.steps.isEmpty)
        }

        // MARK: Janela
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Mostrar Splash") { SplashController.shared.show() }
        }
    }

    /// ⌘F: em Rede e Analytics, a busca da toolbar; nas outras, a da
    /// hierarquia, no inspector.
    private func buscar() {
        if appState.isDeviceConnected && appState.workspaceTab != .pageObjects {
            appState.toolbarSearchPresented = true
        } else {
            appState.inspectorVisible = true
            appState.hierarchySearchFocusRequest += 1
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
