import SwiftUI

/// Inspector recolhível (⌥⌘I): hierarquia de acessibilidade com busca (⌘F) e
/// atributos do elemento escolhido.
///
/// A coluna de hierarquia existia no código e nunca era mostrada: o estado que
/// a ligava começava desligado e nenhum controle o mudava.
struct InspectorPane: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @FocusState private var buscaFocada: Bool

    var body: some View {
        @Bindable var state = appState
        let theme = themeManager.current

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Hierarquia")
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !appState.hierarchyElements.isEmpty {
                    CountBadge(value: appState.hierarchyElements.count)
                        .accessibilityLabel("\(appState.hierarchyElements.count) elementos")
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            DSSearchField(
                text: $state.hierarchySearchText,
                prompt: "Buscar texto, ID ou XPath",
                shortcut: "⌘F",
                accessibilityLabel: "Buscar na hierarquia",
                focus: $buscaFocada
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Rectangle().fill(theme.separator).frame(height: 1)

            HierarchyTreeView()
                .frame(maxHeight: .infinity)

            Rectangle().fill(theme.separator).frame(height: 1)

            AttributesPanel()
                .frame(height: DesignMetrics.Heights.attributesPanel)
        }
        .background(theme.bgContent)
        .onChange(of: appState.hierarchySearchFocusRequest) { _, _ in
            buscaFocada = true
        }
        .onAppear {
            // A janela entrega o foco ao primeiro campo de texto que encontra,
            // e o campo da busca acendia o anel ao abrir o app. A busca só
            // ganha foco quando pedida (⌘F ou clique).
            DispatchQueue.main.async { buscaFocada = false }
        }
    }
}

/// Atributos do elemento escolhido, em fonte mono e selecionáveis.
struct AttributesPanel: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Atributos")
                    .font(DSFont.subheadlineSemibold)
                    .foregroundStyle(theme.labelSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Copiar Tudo") { copiarTudo() }
                    .buttonStyle(PlainTextButtonStyle(theme: theme))
                    .controlSize(.mini)
                    .disabled(appState.selectedElement == nil)
                    .help("Copia todos os atributos do elemento")
            }

            if let element = appState.selectedElement {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                        ForEach(element.attributeRows, id: \.key) { row in
                            GridRow {
                                Text(row.key)
                                    .foregroundStyle(theme.labelSecondary)
                                    .frame(width: 64, alignment: .trailing)
                                Text(row.value.isEmpty ? "—" : row.value)
                                    .foregroundStyle(theme.labelPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .help(row.value)
                            }
                            .font(DSFont.mono(11))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } else {
                Text("Nenhum elemento selecionado")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func copiarTudo() {
        guard let element = appState.selectedElement else { return }
        Exporters.copy(element.attributesText)
        appState.statusMessage = "Atributos copiados"
    }
}
