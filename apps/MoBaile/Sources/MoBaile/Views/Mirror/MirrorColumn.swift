import SwiftUI

/// Coluna do espelho ao vivo: tela do aparelho; um clique vira toque ou passo.
///
/// Nas áreas de Rede e Analytics o espelho fica compacto, como no original, e
/// ganha o botão de Correlação, que abre um popover (antes era um cartão fixo
/// embaixo da moldura).
struct MirrorPane: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var compact: Bool = false

    @State private var correlacaoAberta = false

    var body: some View {
        let theme = themeManager.current

        VStack(spacing: 0) {
            PaneHeader(title: "Espelho") {
                if appState.fps > 0 {
                    Text("\(appState.fps) fps")
                        .font(DSFont.subheadline.monospacedDigit())
                        .foregroundStyle(theme.labelSecondary)
                        .accessibilityLabel("\(appState.fps) quadros por segundo")
                }
            }

            // A moldura recebe a folga da coluna: era ela que ficava fixa
            // enquanto o Spacer de baixo engolia todo o espaço extra.
            DeviceBezel(isCompact: compact)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                MirrorRefreshButton()
                if appState.workspaceTab == .network || appState.workspaceTab == .analytics {
                    Button {
                        correlacaoAberta.toggle()
                    } label: {
                        Label("Correlação", systemImage: "link")
                    }
                    .controlSize(.small)
                    .disabled(!appState.isDeviceConnected)
                    .help("Correlação do último passo com o tráfego e os eventos")
                    .popover(isPresented: $correlacaoAberta, arrowEdge: .top) {
                        CorrelationPopover { correlacaoAberta = false }
                            .environment(appState)
                            .environment(themeManager)
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgContentAlt)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Espelho")
    }
}

/// Mantido com o nome antigo para os testes e snapshots que desenham a coluna.
typealias MirrorColumn = MirrorPane
