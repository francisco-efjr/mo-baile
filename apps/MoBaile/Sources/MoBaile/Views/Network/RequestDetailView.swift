import SwiftUI

/// Abas Headers | Body dos painéis de detalhe.
enum DetailTab: String, CaseIterable, Identifiable {
    case headers = "Headers"
    case body = "Body"
    var id: String { rawValue }
}

/// Detalhe da requisição: método, Headers | Body e Copiar.
struct RequestDetailView: View {
    @Environment(ThemeManager.self) private var themeManager
    let event: NetworkEvent

    @State private var aba: DetailTab = .headers

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            DetailHeader(
                title: "Request",
                copyLabel: "Copiar requisição",
                onCopy: { Exporters.copy(conteudoAtual) }
            ) {
                Text(event.method)
                    .font(DSFont.mono(10.5, weight: .semibold))
                    .foregroundStyle(theme.methodColor(event.method))
            } tabs: {
                DetailTabPicker(aba: $aba, contagemHeaders: event.requestHeaders.count)
            }

            ScrollView {
                switch aba {
                case .headers:
                    if event.requestHeaders.isEmpty {
                        EmptyState(icon: "tag", text: "Sem headers na requisição.", compact: true)
                    } else {
                        KeyValueGrid(rows: event.requestHeaders.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
                    }
                case .body:
                    if event.requestBody.isEmpty {
                        EmptyState(icon: "doc.text", text: "Requisição sem corpo.", compact: true)
                    } else {
                        CodeBlock(text: NetworkEvent.prettyBody(event.requestBody))
                    }
                }
            }
        }
    }

    private var conteudoAtual: String {
        switch aba {
        case .headers:
            return event.requestHeaders.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        case .body:
            return NetworkEvent.prettyBody(event.requestBody)
        }
    }
}

/// Segmentado pequeno Headers | Body, com a contagem de headers.
struct DetailTabPicker: View {
    @Binding var aba: DetailTab
    var contagemHeaders: Int

    var body: some View {
        Picker("Conteúdo", selection: $aba) {
            Text(contagemHeaders > 0 ? "Headers \(contagemHeaders)" : "Headers").tag(DetailTab.headers)
            Text("Body").tag(DetailTab.body)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }
}
