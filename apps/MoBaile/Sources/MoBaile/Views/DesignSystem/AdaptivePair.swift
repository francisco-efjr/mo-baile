import SwiftUI

/// Dois painéis de detalhe lado a lado (Request | Response, Validação | Bloco)
/// que viram abas quando a coluna fica estreita.
///
/// Lado a lado, os cabeçalhos dos dois painéis somam mais de 500 pt, e um
/// `.frame(minWidth:maxWidth:)` acima deles não repassa esse mínimo à janela: o
/// conteúdo transbordava a coluna num monitor pequeno, o espelho ia para baixo
/// da barra lateral e o inspector saía pela borda. Abaixo de `minSideBySide`,
/// mostra um painel por vez com um seletor em cima.
struct AdaptivePair<First: View, Second: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    let labels: (String, String)
    let minSideBySide: CGFloat
    private let first: First
    private let second: Second

    @State private var mostraSegundo = false

    init(
        labels: (String, String),
        minSideBySide: CGFloat,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        self.labels = labels
        self.minSideBySide = minSideBySide
        self.first = first()
        self.second = second()
    }

    var body: some View {
        let theme = themeManager.current
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                first.frame(maxWidth: .infinity)
                Rectangle().fill(theme.separator).frame(width: 1)
                second.frame(maxWidth: .infinity)
            }
            // A largura ideal é o que decide se cabe; o conteúdo não conta.
            .frame(minWidth: minSideBySide, idealWidth: minSideBySide, maxWidth: .infinity)

            VStack(spacing: 0) {
                Picker("Painel", selection: $mostraSegundo) {
                    Text(labels.0).tag(false)
                    Text(labels.1).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
                if mostraSegundo { second } else { first }
            }
            .frame(idealWidth: 0, maxWidth: .infinity)
        }
    }
}
