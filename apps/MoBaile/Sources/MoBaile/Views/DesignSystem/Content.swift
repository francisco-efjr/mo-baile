import SwiftUI

/// Estado vazio ou carregando: ícone discreto, uma frase e, opcionalmente, a
/// ação principal ("Nenhum passo gravado" + "Gravar Passo").
struct EmptyState: View {
    @Environment(ThemeManager.self) private var themeManager

    var icon: String = "info.circle"
    var title: String? = nil
    var text: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil
    var loading: Bool = false
    var compact: Bool = false

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: compact ? 4 : 6) {
            Group {
                if loading {
                    ProgressView().controlSize(compact ? .small : .regular)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: compact ? 20 : 28, weight: .light))
                        .foregroundStyle(theme.labelTertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.bottom, 4)

            if let title {
                Text(title)
                    .font(compact ? .system(size: 13, weight: .semibold) : DSFont.title3)
                    .foregroundStyle(theme.labelPrimary)
                    .multilineTextAlignment(.center)
            }
            if let text {
                Text(text)
                    .font(compact ? DSFont.callout : DSFont.body)
                    .foregroundStyle(theme.labelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .padding(.top, 8)
            }
        }
        .padding(compact ? 16 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Erro em linha, perto de onde aconteceu: o que houve e o que fazer.
struct InlineError: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: String
    var text: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        let theme = themeManager.current
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(theme.destructive)
                .accessibilityHidden(true)
            (Text(title).fontWeight(.semibold).foregroundColor(theme.destructive)
                + Text(text.map { " \($0)" } ?? "").foregroundColor(theme.labelPrimary))
                .font(DSFont.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel, let action {
                Button(actionLabel, action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.dangerTint, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Cartão: fundo `bg-group`, borda interna de 0,5 pt, raio 12, sem sombra.
struct DSCard: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    var padding: CGFloat = DesignMetrics.Spacing.groupBoxPadding

    func body(content: Content) -> some View {
        let theme = themeManager.current
        content
            .padding(padding)
            .background(theme.bgGroup, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous)
                    .strokeBorder(theme.highContrast ? theme.separatorStrong : theme.separator,
                                  lineWidth: theme.highContrast ? 1 : 0.5)
            )
    }
}

extension View {
    func dsCard(padding: CGFloat = DesignMetrics.Spacing.groupBoxPadding) -> some View {
        modifier(DSCard(padding: padding))
    }
}

/// Bloco de código ou de texto bruto (body de requisição, log do Firebase).
struct CodeBlock: View {
    @Environment(ThemeManager.self) private var themeManager
    let text: String

    var body: some View {
        let theme = themeManager.current
        Text(text)
            .font(DSFont.mono(11))
            .lineSpacing(3)
            .foregroundStyle(theme.labelPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(theme.bgContentAlt, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)
    }
}

/// Lista de chave e valor em fonte mono (headers, parâmetros).
struct KeyValueGrid: View {
    @Environment(ThemeManager.self) private var themeManager
    let rows: [(key: String, value: String)]

    var body: some View {
        let theme = themeManager.current
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.key)
                        .foregroundStyle(theme.accentText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(minWidth: 90, alignment: .leading)
                    Text(row.value)
                        .foregroundStyle(theme.labelPrimary)
                        .lineLimit(3)
                        .padding(.trailing, 12)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(row.value)
                }
                .font(DSFont.mono(11))
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
                Divider().overlay(theme.separator).gridCellUnsizedAxes(.horizontal)
            }
        }
    }
}
