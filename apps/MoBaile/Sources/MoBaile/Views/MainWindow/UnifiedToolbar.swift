import SwiftUI

/// Toolbar unificada da janela (Liquid Glass no macOS 26).
///
/// Ordem do design system: título e subtítulo da seção · aparelho (pop-up
/// agrupado por iOS e Android) · [Gravar do aparelho, Gravar a tela, 60 FPS
/// no Android] · Rodar (a única cápsula tingida) · Buscar · Espelho · Inspector.
///
/// O seletor Repassar toque | Gravar passo saiu na 3.10.0: um clique no
/// espelho sempre faz as duas coisas (toca no aparelho e grava o passo), e
/// ao lado do título fica só a escolha do aparelho. Com pouco espaço, o próprio macOS manda os
/// itens de menor prioridade para o menu ».
///
/// A seleção iOS | Android saiu da barra: ela foi absorvida pelo pop-up de
/// aparelhos, que agrupa por plataforma. Cada controle continua chamando a
/// sessão, que é quem conversa com o motor.
struct MainToolbar: ToolbarContent {
    let title: String
    let subtitle: String

    var body: some ToolbarContent {
        // No macOS 26 cada item ganha uma cápsula de vidro; o título é texto da
        // janela, não controle, e fica sem ela.
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                SectionTitleView(title: title, subtitle: subtitle)
            }
            .sharedBackgroundVisibility(.hidden)
        } else if #available(macOS 15.0, *) {
            ToolbarItem(placement: .navigation) {
                SectionTitleView(title: title, subtitle: subtitle)
            }
        }
        ToolbarItem(placement: .navigation) {
            DeviceMenu()
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            PassiveCaptureButton()
            ScreenRecordingButton()
            ScrcpyButton()
        }
        // O Rodar desenha a própria cápsula de vidro tingido; no macOS 26 fica
        // fora da cápsula compartilhada, senão seria vidro sobre vidro.
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                RunAutomationButton()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                RunAutomationButton()
            }
        }
        ToolbarItem(placement: .primaryAction) {
            HierarchySearchButton()
        }
        // Os painéis que se escondem ficam no fim da barra principal: o
        // espelho (o telefone) e o inspector, que não é mais o `.inspector` do
        // SwiftUI e sim um painel da área.
        ToolbarItem(placement: .primaryAction) {
            MirrorToggleButton()
        }
        ToolbarItem(placement: .primaryAction) {
            InspectorToggleButton()
        }
    }
}

// MARK: - Título

/// Título e subtítulo da seção, à esquerda do aparelho.
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

/// A única cápsula tingida da toolbar (`mbProminentGlassButton`).
struct RunAutomationButton: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(\.controlActiveState) private var estadoDaJanela

    var body: some View {
        Button {
            RunAutomationButton.run(appState: appState, session: session)
        } label: {
            Label("Rodar Automação", systemImage: "play.fill")
        }
        .mbProminentGlassButton(Self.podeRodar(appState) && estadoDaJanela != .inactive)
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

/// Em Page Objects a busca é a da hierarquia, que fica no inspector. Em Rede,
/// Analytics e Relatório a toolbar ganha o campo de filtro (`.searchable`) no
/// lugar deste botão.
struct HierarchySearchButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !appState.usesToolbarSearch {
            Button {
                appState.requestHierarchySearch()
            } label: {
                Label("Buscar na Hierarquia", systemImage: "magnifyingglass")
            }
            // Como o botão do inspector: sem aparelho, a hierarquia não existe.
            .disabled(!appState.canSearchHierarchy)
            .help(appState.canSearchHierarchy
                  ? "Buscar na hierarquia (⌘F)"
                  : "Conecte um aparelho para buscar na hierarquia")
        }
    }
}

/// Esconde e mostra o espelho do aparelho. O ícone diz o estado: o telefone
/// riscado é o espelho oculto.
struct MirrorToggleButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.toggleMirror()
        } label: {
            Label(appState.mirrorVisible ? "Ocultar Espelho" : "Mostrar Espelho",
                  systemImage: appState.mirrorVisible ? "iphone" : "iphone.slash")
        }
        .disabled(!appState.canToggleMirror)
        .help(appState.canToggleMirror
              ? (appState.mirrorVisible ? "Ocultar o espelho do aparelho (⌥1)" : "Mostrar o espelho do aparelho (⌥1)")
              : "O espelho aparece com um aparelho conectado, em Page Objects, Rede e Analytics")
        .accessibilityValue(appState.mirrorVisible ? "visível" : "oculto")
    }
}

struct InspectorToggleButton: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Button {
            appState.toggleInspector()
        } label: {
            Label(appState.inspectorShown ? "Ocultar Inspector" : "Mostrar Inspector", systemImage: "sidebar.right")
        }
        .disabled(appState.inspectorSuppressed)
        .help(appState.inspectorSuppressed
              ? "O inspector volta ao conectar um aparelho"
              : (appState.inspectorShown ? "Ocultar Inspector (⌥⌘I)" : "Mostrar Inspector (⌥⌘I)"))
        .accessibilityValue(appState.inspectorShown ? "visível" : "oculto")
    }
}
