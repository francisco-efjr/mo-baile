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
            StatusIndicator(status: appState.daemonStatus.wda, label: wdaLabel)
            StatusIndicator(status: appState.daemonStatus.adb, label: "ADB server")
            StatusIndicator(status: appState.daemonStatus.proxy, label: proxyLabel)
            StatusIndicator(status: appState.daemonStatus.fa, label: "FA listener")

            Spacer(minLength: 8)

            Text(appState.statusMessage)
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.updatesFrequently)
                .help(appState.statusMessage)

            if appState.isDeviceConnected {
                Text(metricas)
                    .font(DSFont.mono(10.5).monospacedDigit())
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("Métricas do espelho")
                    .accessibilityValue(metricas)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: DesignMetrics.Heights.statusBar)
        .background(theme.bgContentAlt)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    private var metricas: String {
        "x \(Int(appState.cursorPosition.x)) · y \(Int(appState.cursorPosition.y))  \(appState.fps) fps  settle \(appState.settleMs) ms  latência \(appState.latencyMs) ms"
    }
}
