import SwiftUI

/// Barra de status de 22 pt, embaixo da coluna central.
///
/// Os rotulos traziam a porta do proxy e a do WDA escritas no codigo. Se a
/// configuracao do motor apontasse para outra porta, a barra mentiria com toda
/// a confianca. Os numeros vem do proprio motor, e o estado de cada servico
/// aparece por icone e texto, nao so por cor.
struct StatusBar: View {
    @Environment(AppState.self) var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) var themeManager

    var theme: any ThemeTokens { themeManager.current }

    private var wdaLabel: String {
        guard let url = session.engineInfo?.wdaUrl,
              let port = URL(string: url)?.port else { return "WDA" }
        return "WDA \(port)"
    }

    private var proxyLabel: String {
        guard let proxy = session.engineInfo?.proxy else { return "Proxy MITM" }
        return "Proxy MITM \(proxy.port)"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Os serviços cedem espaço em vez de impor largura: com tudo em
            // `fixedSize`, a barra sozinha exigia 690 pt, e esse mínimo
            // impedia a janela de encolher numa tela de MacBook.
            ViewThatFits(in: .horizontal) {
                servicos(compacto: false)
                servicos(compacto: true)
            }
            .layoutPriority(1)

            Text(appState.statusMessage)
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
                .help(appState.statusMessage)

            if appState.isDeviceConnected {
                ViewThatFits(in: .horizontal) {
                    metricasView(metricas)
                    metricasView(metricasCurtas)
                    Color.clear.frame(width: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: DesignMetrics.Heights.statusBar)
        .background(theme.bgContentAlt)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    /// Os quatro serviços; no modo compacto, só o ícone (o nome vai no tooltip
    /// e no leitor de tela).
    private func servicos(compacto: Bool) -> some View {
        HStack(spacing: compacto ? 8 : 12) {
            servico(appState.daemonStatus.wda, wdaLabel, compacto)
            servico(appState.daemonStatus.adb, "ADB server", compacto)
            servico(appState.daemonStatus.proxy, proxyLabel, compacto)
            servico(appState.daemonStatus.fa, "FA listener", compacto)
        }
    }

    @ViewBuilder
    private func servico(_ estado: DaemonState, _ rotulo: String, _ compacto: Bool) -> some View {
        if compacto {
            Image(systemName: StatusIndicator.symbol(estado))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(cor(estado))
                .help("\(rotulo): \(StatusIndicator.word(estado))")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rotulo)
                .accessibilityValue(StatusIndicator.word(estado))
        } else {
            StatusIndicator(status: estado, label: rotulo)
        }
    }

    private func cor(_ estado: DaemonState) -> Color {
        switch estado {
        case .ok: return theme.success
        case .busy: return theme.info
        case .warn: return theme.warning
        case .error: return theme.destructive
        case .off: return theme.labelTertiary
        }
    }

    private func metricasView(_ texto: String) -> some View {
        Text(texto)
            .font(DSFont.mono(10.5).monospacedDigit())
            .foregroundStyle(theme.labelSecondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Métricas do espelho")
            .accessibilityValue(metricas)
    }

    private var metricasCurtas: String {
        "\(appState.fps) fps  \(appState.latencyMs) ms"
    }

    private var metricas: String {
        "x \(Int(appState.cursorPosition.x)) · y \(Int(appState.cursorPosition.y))  \(appState.fps) fps  settle \(appState.settleMs) ms  latência \(appState.latencyMs) ms"
    }
}
