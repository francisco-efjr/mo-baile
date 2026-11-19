import SwiftUI

/// Problema de um campo de edição: erro que impede gravar ou aviso que só alerta.
///
/// É o `.mb-field.is-invalid` do design system (`components/mb.css`) levado ao
/// SwiftUI: borda no próprio campo e a frase logo abaixo dele, com ícone e
/// texto, nunca só cor.
struct FieldIssue: Equatable, Sendable {
    let message: String
    /// Falso: aviso em `warning`, que não impede gravar.
    var blocking: Bool = true
}

private struct DSFieldIssueModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    let issue: FieldIssue?

    func body(content: Content) -> some View {
        content.modifier(DSFieldIssueThemedModifier(issue: issue, theme: themeManager.current))
    }
}

/// O mesmo, com o tema dado: célula de `Table` nem sempre recebe o
/// `ThemeManager` do ambiente (a Tabela do editor de spec caía ao encolher a janela).
private struct DSFieldIssueThemedModifier: ViewModifier {
    let issue: FieldIssue?
    let theme: any ThemeTokens

    func body(content: Content) -> some View {
        content
            .overlay {
                if let issue {
                    RoundedRectangle(cornerRadius: DesignMetrics.Radius.field)
                        .strokeBorder(issue.blocking ? theme.destructive : theme.warning, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            // `accessibilityValue` num TextField trocaria o texto digitado: o
            // problema vai como dica.
            .accessibilityHint(issue?.message ?? "")
            .onChange(of: issue?.message) { _, nova in
                if let nova { AccessibilityNotification.Announcement(nova).post() }
            }
    }
}

extension View {
    /// Borda de erro (ou de aviso) no campo. `nil` não muda nada.
    func dsFieldIssue(_ issue: FieldIssue?) -> some View {
        modifier(DSFieldIssueModifier(issue: issue))
    }

    /// Com o tema explícito, para dentro de célula de `Table`.
    func dsFieldIssue(_ issue: FieldIssue?, theme: any ThemeTokens) -> some View {
        modifier(DSFieldIssueThemedModifier(issue: issue, theme: theme))
    }
}

/// A frase do problema, logo abaixo do campo: o que houve e o que fazer.
struct FieldMessage: View {
    @Environment(ThemeManager.self) private var themeManager
    let issue: FieldIssue

    var body: some View {
        let theme = themeManager.current
        Label {
            Text(issue.message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: issue.blocking ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
        }
        .font(DSFont.subheadline)
        .foregroundStyle(issue.blocking ? theme.destructive : theme.warning)
        .accessibilityElement(children: .combine)
    }
}
