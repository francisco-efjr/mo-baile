import SwiftUI

/// Toolbar unificada da janela (Liquid Glass no macOS 26).
///
/// Ordem do design system: título e subtítulo da seção · aparelho (pop-up
/// agrupado por iOS e Android) · Repassar toque | Gravar passo · [Gravar do
/// aparelho, Gravar a tela, 60 FPS no Android] · Rodar (a única cápsula
/// tingida) · Buscar · Inspector. Com pouco espaço, o próprio macOS manda os
/// itens de menor prioridade para o menu ».
///
/// A seleção iOS | Android saiu da barra: ela foi absorvida pelo pop-up de
/// aparelhos, que agrupa por plataforma. Cada controle continua chamando a
/// sessão, que é quem conversa com o motor.
struct MainToolbar: ToolbarContent {
    let title: String
    let subtitle: String

    var body: some ToolbarContent {
        if #available(macOS 15.0, *) {
            ToolbarItem(placement: .navigation) {
                SectionTitleView(title: title, subtitle: subtitle)
            }
        }
        ToolbarItem(placement: .navigation) {
            DeviceMenu()
        }
        ToolbarItem(placement: .navigation) {
            InteractionModePicker()
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            PassiveCaptureButton()
            ScreenRecordingButton()
            ScrcpyButton()
        }
        ToolbarItem(placement: .primaryAction) {
            RunAutomationButton()
        }
        ToolbarItem(placement: .primaryAction) {
            HierarchySearchButton()
        }
    }
}

// MARK: - Título

/// Título e subtítulo da seção, à esquerda do aparelho e do modo do clique.
struct SectionTitleView: View {
    @Environment(ThemeManager.self) private var themeManager
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DSFont.headline)
                .foregroundStyle(themeManager.current.labelPrimary)
            Text(subtitle)
                .font(DSFont.subheadline.monospacedDigit())
                .foregroundStyle(themeManager.current.labelSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Aparelho

/// Pop-up de aparelhos, agrupado por plataforma.
///
/// O motor lista os aparelhos de uma plataforma por vez. A seção da outra
/// plataforma oferece trocar para ela, e aí a lista dela aparece.
struct DeviceMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        let conectado = appState.isDeviceConnected
        Menu {
            secao(.ios)
            secao(.android)
            Divider()
            Button("Atualizar Lista") {
                Task { await session.refreshDevices() }
            }
        } label: {
            Label {
                Text(rotulo)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: conectado ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(conectado ? theme.success : theme.destructive)
            }
            .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("Escolhe o aparelho. Os aparelhos ficam agrupados por plataforma.")
        .accessibilityLabel("Dispositivo")
        .accessibilityValue(rotulo)
    }

    private var rotulo: String {
        appState.selectedDeviceName ?? "Nenhum dispositivo"
    }

    @ViewBuilder
    private func secao(_ plataforma: Platform) -> some View {
        Section(plataforma.displayName) {
            if appState.platform == plataforma {
                if appState.availableDevices.isEmpty {
                    Text("Nenhum aparelho \(plataforma.displayName)")
                } else {
                    ForEach(appState.availableDevices, id: \.id) { device in
                        Toggle(device.name.isEmpty ? device.id : device.name, isOn: Binding(
                            get: { appState.selectedDevice == device.id },
                            set: { escolhido in
                                guard escolhido else { return }
                                Task { await session.select(deviceID: device.id) }
                            }
                        ))
                    }
                }
            } else {
                Button("Procurar Aparelhos \(plataforma.displayName)") {
                    Task { await session.switchPlatform(to: plataforma) }
                }
            }
        }
    }
}

// MARK: - Modo do clique

/// O que um clique no espelho faz: repassar o toque ou gravar um passo.
struct InteractionModePicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        Picker("Ação do clique no espelho", selection: $state.interactionMode) {
            ForEach(InteractionMode.allCases) { modo in
                Label(modo.displayName, systemImage: modo.symbolName)
                    .tag(modo)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
        .labelsHidden()
        .fixedSize()
        .disabled(!appState.isDeviceConnected)
        .help("Define o que acontece ao clicar no espelho")
    }
}

// MARK: - Gravação

/// Escuta passiva: grava o que a pessoa faz direto no aparelho.
struct PassiveCaptureButton: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let ativo = appState.passiveListening
        Button {
            Task {
                if ativo { await session.stopPassive() } else { await session.startPassive() }
            }
        } label: {
            Label(ativo ? "Parar Captura" : "Gravar do Aparelho", systemImage: ativo ? "stop.circle.fill" : "hand.tap")
                .foregroundStyle(ativo ? themeManager.current.recording : Color.primary)
        }
        .disabled(!disponivel)
        .help(dica)
    }

    private var disponivel: Bool {
        guard appState.isDeviceConnected else { return false }
        if appState.platform == .ios {
            // No iOS, escuta passiva depende do Simulator via Quartz no macOS.
            // O iOS físico não expõe toques via USB.
            return session.simulators.contains { $0.udid == appState.selectedDevice }
        }
        return true
    }

    private var dica: String {
        if appState.isDeviceConnected && appState.platform == .ios && !disponivel {
            return "No iPhone físico, use o clique no espelho: o iOS não expõe os toques pelo cabo."
        }
        return appState.passiveListening
            ? "Para de gravar os toques feitos no aparelho"
            : "Grava o que você fizer direto no aparelho, sem clicar no espelho"
    }
}

/// Gravação de vídeo da tela do aparelho. Vermelho enquanto grava: esquecer
/// ligada custa espaço em disco e privacidade.
struct ScreenRecordingButton: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let gravando = appState.screenRecording
        Button {
            Task {
                if gravando { await session.stopScreenRecording() } else { await session.startScreenRecording() }
            }
        } label: {
            Label(gravando ? "Parar de Gravar a Tela" : "Gravar a Tela", systemImage: gravando ? "stop.circle.fill" : "video")
                .foregroundStyle(gravando ? themeManager.current.recording : Color.primary)
        }
        .disabled(!appState.isDeviceConnected)
        .help(gravando ? "Encerra a gravação e salva o vídeo" : "Grava vídeo da tela do aparelho")
    }
}

/// Espelho nativo a 60 FPS pelo scrcpy. Só existe no Android.
struct ScrcpyButton: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        if appState.platform == .android {
            let ativo = appState.scrcpyRunning
            Button {
                Task { await session.toggleScrcpy() }
            } label: {
                Label(ativo ? "Fechar Espelho 60 FPS" : "Espelho 60 FPS", systemImage: ativo ? "bolt.fill" : "bolt")
                    .foregroundStyle(ativo ? themeManager.current.accentText : Color.primary)
            }
            .disabled(!appState.isDeviceConnected || !appState.scrcpyAvailable)
            .help(appState.scrcpyAvailable
                  ? (ativo ? "Fecha o espelho nativo a 60 FPS (scrcpy)" : "Abre o espelho nativo a 60 FPS (scrcpy)")
                  : "scrcpy não encontrado. Instale com brew install scrcpy para espelhar a 60 FPS.")
            .accessibilityValue(ativo ? "ligado" : "desligado")
        }
    }
}

// MARK: - Rodar

/// A única cápsula tingida da toolbar.
struct RunAutomationButton: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session

    var body: some View {
        Button {
            RunAutomationButton.run(appState: appState, session: session)
        } label: {
            Label("Rodar Automação", systemImage: "play.fill")
        }
        .prominentGlassButton()
        .disabled(!Self.podeRodar(appState))
        .help(dica)
    }

    static func podeRodar(_ state: AppState) -> Bool {
        !state.steps.isEmpty && state.isDeviceConnected && state.runState != .running
    }

    @MainActor
    static func run(appState: AppState, session: EngineSession) {
        guard podeRodar(appState) else { return }
        appState.showingFlowRunner = true
        Task { await session.runFlow() }
    }

    private var dica: String {
        if appState.steps.isEmpty { return "Grave ao menos um passo para poder rodar" }
        if !appState.isDeviceConnected { return "Conecte um aparelho para rodar o fluxo" }
        if appState.runState == .running { return "Execução em andamento" }
        return "Rodar Automação (⌘R): executa os passos gravados no aparelho"
    }
}

// MARK: - Busca e inspector

/// Em Page Objects a busca é a da hierarquia, que fica no inspector. Em Rede e
/// Analytics a toolbar ganha o campo de filtro (`.searchable`) no lugar deste
/// botão.
struct HierarchySearchButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !(appState.isDeviceConnected && appState.workspaceTab != .pageObjects) {
            Button {
                appState.inspectorVisible = true
                appState.hierarchySearchFocusRequest += 1
            } label: {
                Label("Buscar na Hierarquia", systemImage: "magnifyingglass")
            }
            .help("Buscar na hierarquia (⌘F)")
        }
    }
}

struct InspectorToggleButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.inspectorVisible.toggle()
        } label: {
            Label(appState.inspectorVisible ? "Ocultar Inspector" : "Mostrar Inspector", systemImage: "sidebar.right")
        }
        .help(appState.inspectorVisible ? "Ocultar Inspector (⌥⌘I)" : "Mostrar Inspector (⌥⌘I)")
        .accessibilityValue(appState.inspectorVisible ? "visível" : "oculto")
    }
}

extension View {
    /// Botão primário tingido: vidro tingido no macOS 26, preenchido antes.
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
