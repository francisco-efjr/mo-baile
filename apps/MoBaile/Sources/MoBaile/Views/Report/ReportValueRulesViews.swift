import SwiftUI

/// Menu "Inserir Regra" ao lado do valor (RE-08). O SwiftUI do macOS 14 não dá
/// a posição do cursor no campo, então as regras de valor inteiro trocam o
/// valor, `re:` entra no começo e `{fluxo}` no fim.
struct ReportInsertRuleMenu: View {
    @Binding var value: String
    let fieldName: String
    var onInsert: () -> Void = {}

    var body: some View {
        Menu {
            ForEach(Array(ReportValueRules.rules.enumerated()), id: \.element.id) { posicao, regra in
                if posicao == ReportValueRules.rules.count - 1 { Divider() }
                Button("\(regra.title)   \(regra.token)") {
                    value = regra.apply(value)
                    onInsert()
                }
            }
        } label: {
            Image(systemName: "curlybraces.square")
                .frame(minWidth: 24, minHeight: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Inserir uma regra no valor de \(fieldName)")
        .accessibilityLabel("Inserir regra no valor de \(fieldName)")
    }
}

/// Botão "Regras dos Valores" com a tabela de regras num popover (RE-08).
struct ReportValueRulesHelpButton: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var aberto = false

    var body: some View {
        BarIconButton(icon: "questionmark.circle", label: "Regras dos Valores") { aberto.toggle() }
            .popover(isPresented: $aberto, arrowEdge: .bottom) {
                ReportValueRulesHelp()
                    .environment(themeManager)
            }
    }
}

/// A gramática dos valores da spec, na linguagem de quem edita.
struct ReportValueRulesHelp: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            Text("Regras dos Valores")
                .font(DSFont.headline)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DesignMetrics.Spacing.s5,
                 verticalSpacing: DesignMetrics.Spacing.s3) {
                GridRow {
                    Text("Exemplo")
                    Text("Confere")
                }
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.labelSecondary)
                ForEach(ReportValueRules.rules) { regra in
                    GridRow {
                        Text(regra.example)
                            .font(DSFont.mono(11))
                            .foregroundStyle(theme.accentText)
                            .textSelection(.enabled)
                        Text(regra.checks)
                            .font(DSFont.callout)
                            .foregroundStyle(theme.labelPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                GridRow {
                    Text("item_id|item_name")
                        .font(DSFont.mono(11))
                        .foregroundStyle(theme.accentText)
                    Text("na chave: basta uma das chaves atender (a regra do GA4 para itens)")
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Qualquer outro texto é comparado igual, sem espaços nas pontas. Em items, todos os itens do evento "
                 + "são conferidos: um objeto na lista vale para todos.")
                .font(DSFont.footnote)
                .foregroundStyle(theme.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignMetrics.Spacing.s7)
        .frame(width: 380)
    }
}
