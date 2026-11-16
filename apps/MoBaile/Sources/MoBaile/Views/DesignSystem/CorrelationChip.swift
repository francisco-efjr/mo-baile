import SwiftUI

/// "Passo 3 · tocar Entrar · 2 requisições · 1 evento": a janela correlacionada
/// que está filtrando a tabela, com o botão para voltar a ver tudo.
struct CorrelationChip: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        if let c = appState.correlation {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(theme.accentText)
                Text(Self.texto(c, passo: appState.correlatedStep))
                    .font(DSFont.callout.monospacedDigit())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Mostrar tudo") { appState.clearCorrelation() }
                    .buttonStyle(.link)
                    .font(DSFont.callout)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.accentText.opacity(0.10), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Filtrado pelo passo: \(Self.texto(c, passo: appState.correlatedStep))")
            .help("Rede e Analytics mostram só o que aconteceu na janela deste passo (atribuição por tempo)")
        }
    }

    static func texto(_ c: EngineDTO.Correlation, passo: AutomationStep?) -> String {
        let nome = passo.map { " · \($0.elementName)" } ?? ""
        let r = c.requests.count == 1 ? "1 requisição" : "\(c.requests.count) requisições"
        let e = c.events.count == 1 ? "1 evento" : "\(c.events.count) eventos"
        return "Passo \(c.stepNum)\(nome) · \(r) · \(e)"
    }
}
