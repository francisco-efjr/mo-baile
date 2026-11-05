import SwiftUI

/// Badge do perfil de desempenho na barra de status (PERF-5).
///
/// Discreto, em mono e minúsculas como o resto da barra: `leve` ou
/// `equilibrado`; nada no completo, para não poluir. Quando quem escolheu foi
/// o Automático (sinal do Mac), um ponto na cor de aviso. O motivo vai no
/// tooltip e no VoiceOver; o clique abre Ajustes › Desempenho.
struct PerfBadge: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let perf = appState.perf
        if let rotulo = perf.badge {
            let theme = themeManager.current
            Button { openSettings() } label: {
                HStack(spacing: 4) {
                    if perf.isAutomatic {
                        Circle().fill(theme.warning).frame(width: 5, height: 5)
                    }
                    Text(rotulo)
                        .font(DSFont.mono(StatusBar.metricsFontSize))
                        .foregroundStyle(theme.labelSecondary)
                }
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help("\(perf.summary). Clique para abrir os Ajustes (aba Desempenho).")
            .accessibilityLabel("Perfil de desempenho")
            .accessibilityValue(perf.summary)
            .accessibilityHint("Abre os Ajustes")
        }
    }
}
