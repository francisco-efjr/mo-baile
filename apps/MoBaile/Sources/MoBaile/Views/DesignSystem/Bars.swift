import SwiftUI

/// Barra acessória de 36 pt, só sobre o conteúdo (nunca na toolbar): seletor
/// de estratégia, Estrutura…, ações de rede e de analytics.
///
/// Rótulos secundários somem em larguras estreitas (o ícone e o tooltip
/// ficam): o pai informa a largura disponível pelo ambiente `accessoryWidth`.
struct AccessoryBar<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    @ViewBuilder var content: () -> Content

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 8) {
            content()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(height: DesignMetrics.Heights.accessoryBar)
        .frame(maxWidth: .infinity)
        .background(theme.bgContent)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
    }
}

/// Cabeçalho de 30 pt de uma coluna ("Espelho", "Atributos").
struct PaneHeader<Trailing: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 6) {
            Text(title)
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.labelSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: DesignMetrics.Heights.paneHeader)
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

/// Cabeçalho de 34 pt de um painel de detalhe (Request, Response,
/// Parâmetros, Log Bruto): título, informação curta, segmentado e Copiar.
struct DetailHeader<Extra: View, Tabs: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    let title: String
    let copyLabel: String
    let onCopy: () -> Void
    var copyDisabled: Bool = false
    @ViewBuilder var extra: () -> Extra
    @ViewBuilder var tabs: () -> Tabs

    @State private var copiado = false

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.labelPrimary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            extra()
                .lineLimit(1)
            Spacer(minLength: 4)
            tabs()
            Button {
                onCopy()
                copiado = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copiado = false
                }
            } label: {
                Label(copiado ? "Copiado" : "Copiar", systemImage: copiado ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.mini)
            .disabled(copyDisabled)
            .help(copyLabel)
            .accessibilityLabel(copiado ? "Copiado" : copyLabel)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: DesignMetrics.Heights.detailHeader)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
    }
}

/// Botão só com ícone das barras de conteúdo (cabeçalho do editor, barra
/// acessória): fundo aparece no hover, escurece ao pressionar, sem ripple.
struct BarIconButton: View {
    @Environment(ThemeManager.self) private var themeManager
    let icon: String
    let label: String
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12.5))
                .frame(minWidth: 24, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(BarIconButtonStyle(theme: themeManager.current, isOn: isOn))
        .help(label)
        .accessibilityLabel(label)
    }
}

struct BarIconButtonStyle: ButtonStyle {
    let theme: any ThemeTokens
    var isOn: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        BarIconButtonBody(configuration: configuration, theme: theme, isOn: isOn)
    }

    private struct BarIconButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let theme: any ThemeTokens
        let isOn: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isOn ? theme.accentText : theme.labelPrimary)
                .padding(.horizontal, 4)
                .background(
                    Capsule().fill(configuration.isPressed ? theme.fillPrimary : (hover ? theme.fillSecondary : .clear))
                )
                .opacity(isEnabled ? 1 : 0.38)
                .onHover { hover = $0 }
        }
    }
}

/// Botão "plano" do design system: texto no destaque (ou destrutivo), sem
/// fundo, que ganha preenchimento no hover. Usado em "Copiar Tudo",
/// "Verificar de Novo", "Limpar Tráfego".
struct PlainTextButtonStyle: ButtonStyle {
    let theme: any ThemeTokens
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        PlainTextBody(configuration: configuration, theme: theme, destructive: destructive)
    }

    private struct PlainTextBody: View {
        let configuration: ButtonStyleConfiguration
        let theme: any ThemeTokens
        let destructive: Bool
        @State private var hover = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize

        var body: some View {
            configuration.label
                .font(controlSize == .mini ? DSFont.subheadline : (controlSize == .small ? DSFont.callout : DSFont.body))
                .foregroundStyle(destructive ? theme.destructive : theme.accentText)
                .padding(.horizontal, 6)
                .frame(minHeight: controlSize == .mini ? 16 : (controlSize == .small ? 20 : 24))
                .background(
                    Capsule().fill(configuration.isPressed ? theme.fillPrimary : (hover ? theme.fillSecondary : .clear))
                )
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.42)
                .onHover { hover = $0 }
        }
    }
}

/// Campo de busca em cápsula (hierarquia): lupa, texto, limpar e o atalho.
struct DSSearchField: View {
    @Environment(ThemeManager.self) private var themeManager
    @Binding var text: String
    let prompt: String
    var shortcut: String? = nil
    var accessibilityLabel: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.labelSecondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(DSFont.body)
                .focused(focus)
                .accessibilityLabel(accessibilityLabel)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar busca")
            } else if let shortcut {
                Text(shortcut)
                    .font(DSFont.footnote)
                    .foregroundStyle(theme.labelTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .frame(height: DesignMetrics.Heights.controlRegular)
        .background(
            Capsule().fill(focus.wrappedValue ? theme.bgField : theme.fillSecondary)
        )
        .overlay(
            Capsule().strokeBorder(focus.wrappedValue ? theme.focusRing : .clear, lineWidth: 3)
                .padding(-3)
        )
    }
}
