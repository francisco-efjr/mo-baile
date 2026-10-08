import SwiftUI

/// Detalhe da resposta: status e tempo, Headers | Body (abre no Body) e
/// Copiar. O túnel HTTPS tem estado próprio.
struct ResponseDetailView: View {
    @Environment(ThemeManager.self) private var themeManager
    let event: NetworkEvent

    @State private var aba: DetailTab = .body

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            DetailHeader(
                title: "Response",
                copyLabel: "Copiar resposta",
                onCopy: { Exporters.copy(conteudoAtual) }
            ) {
                Text("\(event.statusCode.map(String.init) ?? "—") · \(event.formattedDuration)")
                    .font(DSFont.mono(10.5).monospacedDigit())
                    .foregroundStyle(theme.statusColor(event.statusCode))
            } tabs: {
                DetailTabPicker(aba: $aba, contagemHeaders: event.responseHeaders.count)
            }

            if let erro = event.error, !erro.isEmpty {
                InlineError(title: "A requisição falhou.", text: erro)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
            }

            ScrollView {
                switch aba {
                case .headers:
                    if event.responseHeaders.isEmpty {
                        EmptyState(icon: "tag", text: "Sem headers na resposta.", compact: true)
                    } else {
                        KeyValueGrid(rows: event.responseHeaders.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
                    }
                case .body:
                    if event.isHTTPSTunnel {
                        EmptyState(
                            icon: "lock.shield",
                            title: "Túnel HTTPS estabelecido",
                            text: "Conexão criptografada de ponta a ponta. \(event.statusCode ?? 200) Connection Established · \(event.formattedDuration).",
                            compact: true
                        )
                    } else if event.responseBody.isEmpty {
                        EmptyState(icon: "doc.text", text: "Resposta sem corpo.", compact: true)
                    } else {
                        CodeBlock(text: NetworkEvent.prettyBody(event.responseBody))
                    }
                }
            }
        }
    }

    private var conteudoAtual: String {
        switch aba {
        case .headers:
            return event.responseHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        case .body:
            if event.isHTTPSTunnel {
                return "HTTP/1.1 \(event.statusCode ?? 200) Connection Established\nDuration: \(event.formattedDuration)"
            }
            return NetworkEvent.prettyBody(event.responseBody)
        }
    }
}
