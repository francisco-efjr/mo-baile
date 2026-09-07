import SwiftUI

/// Barra unificada da janela.
///
/// Diagnostico da versao anterior: todos os controles aqui mexiam apenas em
/// `AppState`. Trocar a plataforma nao avisava o motor, escolher o aparelho
/// so guardava o identificador, o interruptor de streaming nao ligava nada e o
/// botao "Forcar Captura" tinha corpo vazio. Cada controle agora chama a
/// sessao, que e quem conversa com o motor.
struct UnifiedToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        @Bindable var state = appState

        HStack(alignment: .center, spacing: 0) {
            // Espaco dos semaforos da janela.
            Spacer().frame(width: 72)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mo baile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Text("Element Recorder")
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
            }
            .accessibilityElement(children: .combine)

            Spacer().frame(width: 14)

            SegmentedControl(items: ["iOS", "Android"], selectedIndex: platformBinding)
                .accessibilityLabel("Plataforma")

            Spacer().frame(width: 14)

            deviceMenu

            Spacer().frame(width: 14)

            CanvasSwitch(label: "Espelho", isOn: Bindable(state).mirrorVisible)
            CanvasSwitch(label: "Streaming", isOn: streamingBinding)

            Spacer().frame(width: 10)

            interactionPicker

            Spacer()

            FluidPillButton(
                text: "Forçar Captura",
                style: appState.isDeviceConnected ? .primary : .disabled,
                action: { Task { await session.captureNow() } }
            )
            .disabled(!appState.isDeviceConnected)
            .help("Captura a tela e recarrega a hierarquia (⌘K)")

            Spacer().frame(width: 8)

            Rectangle()
                .fill(theme.borderStrong)
                .frame(width: 1, height: 28)

            Spacer().frame(width: 8)

            PanelToggleGroup(
                mirrorVisible: Bindable(state).mirrorVisible,
                hierarchyVisible: Bindable(state).hierarchyVisible,
                workspaceVisible: Bindable(state).workspaceVisible
            )

            Spacer().frame(width: 16)
        }
        .frame(height: 52)
        .background(theme.bgToolbar)
        .overlay(Divider().background(theme.border), alignment: .bottom)
    }

    // MARK: - Ligacoes com a sessao

    private var platformBinding: Binding<Int> {
        Binding(
            get: { appState.platform == .ios ? 0 : 1 },
            set: { index in
                let platform: Platform = index == 0 ? .ios : .android
                guard platform != appState.platform else { return }
                Task { await session.switchPlatform(to: platform) }
            }
        )
    }

    private var streamingBinding: Binding<Bool> {
        Binding(
            get: { appState.streamActive },
            set: { shouldStream in
                Task {
                    if shouldStream {
                        await session.startStream()
                    } else {
                        await session.stopStream()
                    }
                }
            }
        )
    }

    @ViewBuilder
    private var deviceMenu: some View {
        Menu {
            if appState.availableDevices.isEmpty {
                Text("Nenhum dispositivo")
            } else {
                ForEach(appState.availableDevices, id: \.id) { device in
                    Button(device.name.isEmpty ? device.id : device.name) {
                        Task { await session.select(deviceID: device.id) }
                    }
                }
            }
            Divider()
            Button("Atualizar lista") {
                Task { await session.refreshDevices() }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isDeviceConnected ? theme.success : theme.danger)
                    .frame(width: 6, height: 6)
                Text(selectedDeviceLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(minWidth: 210, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dispositivo selecionado")
        .accessibilityValue(selectedDeviceLabel)
    }

    /// Mostra o nome do aparelho, e nao o serial: "Pixel 7" diz mais do que
    /// "emulator-5554" para quem tem dois aparelhos na mesa.
    private var selectedDeviceLabel: String {
        guard let selected = appState.selectedDevice else { return "Nenhum dispositivo" }
        let match = appState.availableDevices.first { $0.id == selected }
        return match?.name.isEmpty == false ? match!.name : selected
    }

    /// Substitui o interruptor "Tap forward".
    ///
    /// Um clique no espelho pode significar tres coisas diferentes, e um
    /// interruptor de duas posicoes escondia a terceira. Com tres estados
    /// visiveis, o usuario sabe o que o proximo clique vai fazer, que e o
    /// principio de feedback do HIG.
    @ViewBuilder
    private var interactionPicker: some View {
        Picker("Clique no espelho", selection: interactionBinding) {
            ForEach(InteractionMode.allCases) { mode in
                Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
        .disabled(!appState.isDeviceConnected)
        .help("Define o que acontece ao clicar no espelho")
        .accessibilityLabel("Acao do clique no espelho")
    }

    private var interactionBinding: Binding<InteractionMode> {
        Binding(
            get: { appState.interactionMode },
            set: { appState.interactionMode = $0 }
        )
    }
}
