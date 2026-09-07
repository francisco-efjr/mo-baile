import SwiftUI

/// Barra inferior de diagnostico.
///
/// Os rotulos traziam a porta do proxy e a do WDA escritas no codigo. Se a
/// configuracao do motor apontasse para outra porta, a barra mentiria com toda
/// a confianca. Agora os numeros vem do proprio motor.
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
        HStack {
            // Left: daemon indicators
            HStack(spacing: 12) {
                DaemonIndicator(title: wdaLabel, status: appState.daemonStatus.wda)
                DaemonIndicator(title: "ADB server", status: appState.daemonStatus.adb)
                DaemonIndicator(title: proxyLabel, status: appState.daemonStatus.proxy)
                DaemonIndicator(title: "FA listener", status: appState.daemonStatus.fa)
            }
            
            Spacer()
            
            // Right: metrics
            HStack(spacing: 12) {
                if !appState.statusMessage.isEmpty {
                    Text(appState.statusMessage)
                }
                Text("x \(Int(appState.cursorPosition.x)) · y \(Int(appState.cursorPosition.y))")
                Text("\(appState.fps) fps")
                Text("settle \(appState.settleMs) ms")
                Text("latência \(appState.latencyMs) ms")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 26)
        .background(theme.bgTerminal)
    }
}

struct DaemonIndicator: View {
    @Environment(ThemeManager.self) var themeManager
    var theme: any ThemeTokens { themeManager.current }
    
    let title: String
    let status: DaemonState
    
    func dotColor() -> Color {
        switch status {
        case .ok: return theme.success
        case .busy: return theme.accent
        case .warn: return theme.warning
        case .error: return theme.danger
        case .off: return theme.textLabel
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor())
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textSecondary)
        }
    }
}
