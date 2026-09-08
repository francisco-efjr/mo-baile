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

    /// Abaixo desta largura a barra nao cabe inteira e passa a esconder o que
    /// e decorativo: o subtitulo e parte da largura reservada ao nome do
    /// aparelho. O conteudo somado pede cerca de 1380 pontos; sem isto, os
    /// controles das pontas eram cortados pela borda da janela.
    private static let larguraParaBarraCompleta: CGFloat = 1400

    /// Largura medida da barra, usada só para decidir o modo compacto.
    @State private var largura: CGFloat = 1440

    var body: some View {
        conteudo(compacto: largura < Self.larguraParaBarraCompleta)
            .frame(height: 52)
            .background(theme.bgToolbar)
            // A medição vai no `background` de propósito. Envolver a barra num
            // `GeometryReader` a deixa sem altura intrínseca e ela some do
            // `VStack` da janela — foi o que aconteceu quando o modo compacto
            // entrou. No fundo, o leitor recebe o tamanho já resolvido e não
            // participa do layout.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { largura = geo.size.width }
                        .onChange(of: geo.size.width) { _, nova in largura = nova }
                }
            )
            .overlay(Divider().background(theme.border), alignment: .bottom)
    }

    @ViewBuilder
    private func conteudo(compacto: Bool) -> some View {
        @Bindable var state = appState

        HStack(alignment: .center, spacing: 0) {
            // Espaco dos semaforos da janela.
            Spacer().frame(width: 72)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mo baile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if !compacto {
                    Text("Element Recorder")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer().frame(width: 14)

            SegmentedControl(items: ["iOS", "Android"], selectedIndex: platformBinding)
                .accessibilityLabel("Plataforma")

            Spacer().frame(width: 14)

            deviceMenu(compacto: compacto)

            Spacer().frame(width: 14)

            // "Espelho" e "Streaming" saíram daqui. O primeiro só mostrava e
            // escondia a coluna, o que os botões de painel à direita já fazem;
            // o segundo era opção para algo que hoje começa sozinho ao conectar
            // um aparelho. Os dois nomes eram parecidos e faziam coisas
            // diferentes, o que sobrava como armadilha e não como controle.
            interactionPicker

            Spacer()

            // Escuta passiva: grava o que a pessoa faz direto no aparelho.
            // É o modo em que não se clica no espelho, então precisa de um
            // controle próprio e de um estado visível de longe.
            FluidPillButton(
                text: appState.passiveListening
                    ? (compacto ? "Parar" : "Parar captura")
                    : (compacto ? "Do aparelho" : "Gravar do aparelho"),
                icon: appState.passiveListening ? "stop.circle" : "hand.tap",
                style: botaoDeEscutaPassiva
            ) {
                Task {
                    if appState.passiveListening {
                        await session.stopPassive()
                    } else {
                        await session.startPassive()
                    }
                }
            }
            .disabled(!appState.isDeviceConnected)
            .help(appState.passiveListening
                  ? "Para de gravar os toques feitos no aparelho"
                  : "Grava o que você fizer direto no aparelho, sem clicar no espelho")

            Spacer().frame(width: 8)

            FluidPillButton(
                text: appState.screenRecording ? "Parar de gravar" : "Gravar a tela",
                style: botaoDeGravacao,
                action: {
                    Task {
                        if appState.screenRecording {
                            await session.stopScreenRecording()
                        } else {
                            await session.startScreenRecording()
                        }
                    }
                }
            )
            .disabled(!appState.isDeviceConnected)
            .help(appState.screenRecording
                  ? "Encerra a gravação e salva o vídeo"
                  : "Grava vídeo da tela do aparelho")

            Spacer().frame(width: 8)

            Rectangle()
                .fill(theme.borderStrong)
                .frame(width: 1, height: 28)

            Spacer().frame(width: 8)

            PanelToggles(
                mirrorVisible: Bindable(state).mirrorVisible,
                hierarchyVisible: Bindable(state).hierarchyVisible,
                workspaceVisible: Bindable(state).workspaceVisible
            )

            Spacer().frame(width: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// Vermelho enquanto grava: é estado que precisa ser óbvio de longe, porque
    /// esquecer a gravação ligada custa espaço em disco e privacidade.
    private var botaoDeEscutaPassiva: FluidPillButton.Style {
        guard appState.isDeviceConnected else { return .disabled }
        return appState.passiveListening ? .recording : .secondary
    }

    private var botaoDeGravacao: FluidPillButton.Style {
        guard appState.isDeviceConnected else { return .disabled }
        return appState.screenRecording ? .recording : .primary
    }

    @ViewBuilder
    private func deviceMenu(compacto: Bool) -> some View {
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
            .frame(minWidth: compacto ? 132 : 210, alignment: .leading)
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

    /// Seletor do que o clique no espelho faz.
    ///
    /// Um clique no espelho pode significar tres coisas diferentes, e um
    /// interruptor de duas posicoes escondia a terceira. Com tres estados
    /// visiveis, o usuario sabe o que o proximo clique vai fazer.
    ///
    /// Era um `Picker(.segmented)`, controle do AppKit, preso a
    /// `.frame(width: 150)`. Os três rótulos ("Inspecionar", "Repassar toque",
    /// "Gravar") precisam de mais que o dobro disso, e o AppKit não comprime
    /// texto para caber: ele desenha para fora da moldura. O layout reservava
    /// 150 pontos e o controle pintava por cima do interruptor "Streaming" à
    /// esquerda e do botão "Forçar Captura" à direita.
    ///
    /// O `SegmentedControl` da casa é SwiftUI puro e se dimensiona pelo
    /// conteúdo, então a barra volta a ser uma conta que fecha.
    private var interactionPicker: some View {
        SegmentedControl(
            items: InteractionMode.allCases.map(\.displayName),
            selectedIndex: interactionIndexBinding
        )
        .disabled(!appState.isDeviceConnected)
        .opacity(appState.isDeviceConnected ? 1 : 0.5)
        .help("Define o que acontece ao clicar no espelho")
        .accessibilityLabel("Acao do clique no espelho")
    }

    private var interactionIndexBinding: Binding<Int> {
        Binding(
            get: { InteractionMode.allCases.firstIndex(of: appState.interactionMode) ?? 0 },
            set: { index in
                guard InteractionMode.allCases.indices.contains(index) else { return }
                appState.interactionMode = InteractionMode.allCases[index]
            }
        )
    }

}
