import SwiftUI

/// Formulário do card no inspector: corrige o que o OCR leu do print do Figma
/// sem abrir o JSON. Grava pela `report.card_update`, que mexe só nestes
/// campos e valida a spec inteira antes de trocar o arquivo.
struct ReportCardEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @Binding var draft: ReportCardDraft
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        let theme = themeManager.current
        let gravando = appState.reportOperation == .savingCard
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    campo("Seção", texto: $draft.secao)
                    campo("Título", texto: $draft.titulo, dica: "Vazio: usa o evento")
                    campo("Evento", texto: $draft.evento, mono: true)

                    secao("Parâmetros") {
                        FieldRows(fields: $draft.params, addLabel: "Adicionar Parâmetro")
                        if !draft.paramsPerFlow.isEmpty {
                            nota("Parâmetros próprios de \(draft.paramsPerFlow.joined(separator: ", ")) ficam no JSON.")
                        }
                    }

                    secao("Variações") {
                        ForEach($draft.variacoes) { $variacao in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Variação \(posicao(variacao) + 1)")
                                        .font(DSFont.subheadlineSemibold)
                                        .foregroundStyle(theme.labelSecondary)
                                    Spacer()
                                    Button {
                                        draft.variacoes.removeAll { $0.id == variacao.id }
                                    } label: {
                                        Label("Remover Variação", systemImage: "minus.circle")
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .help("Remover a variação \(posicao(variacao) + 1)")
                                }
                                FieldRows(fields: $variacao.fields, addLabel: "Adicionar Campo")
                            }
                            .padding(8)
                            .background(theme.bgContentAlt, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
                        }
                        Button {
                            draft.variacoes.append(.init(fields: [.init(key: "detail", value: "")]))
                        } label: {
                            Label("Adicionar Variação", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }

                    secao("Observação") {
                        if draft.obsPerFlow {
                            nota("A observação deste card é por fluxo e fica no JSON.")
                        } else {
                            TextEditor(text: $draft.obs)
                                .font(DSFont.callout)
                                .frame(minHeight: 54)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(theme.bgField, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
                                .overlay {
                                    RoundedRectangle(cornerRadius: DesignMetrics.Radius.field)
                                        .strokeBorder(theme.separator)
                                }
                                .accessibilityLabel("Observação")
                        }
                    }

                    nota("Valores aceitam a mesma gramática da spec: [a|b], [numero], [preenchido], re:… e {fluxo}.")
                }
                .padding(14)
            }

            Rectangle().fill(theme.separator).frame(height: 1)
            HStack {
                if gravando { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Salvar", action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("Grava o card na spec e audita de novo (⌘S)")
            }
            .disabled(gravando)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editar card \(draft.cardIndex + 1) de \(draft.totalCards)")
    }

    private func posicao(_ variacao: ReportCardDraft.Variation) -> Int {
        draft.variacoes.firstIndex { $0.id == variacao.id } ?? 0
    }

    private func campo(_ rotulo: String, texto: Binding<String>, dica: String? = nil, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rotulo)
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(themeManager.current.labelSecondary)
            TextField(rotulo, text: texto, prompt: dica.map { Text($0) })
                .textFieldStyle(.roundedBorder)
                .font(mono ? DSFont.mono(11) : DSFont.callout)
                .labelsHidden()
                .accessibilityLabel(rotulo)
        }
    }

    private func secao<Conteudo: View>(_ titulo: String, @ViewBuilder conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo)
                .font(DSFont.headline)
                .foregroundStyle(themeManager.current.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            conteudo()
        }
    }

    private func nota(_ texto: String) -> some View {
        Text(texto)
            .font(DSFont.footnote)
            .foregroundStyle(themeManager.current.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Linhas chave e valor com remover e adicionar.
private struct FieldRows: View {
    @Environment(ThemeManager.self) private var themeManager
    @Binding var fields: [ReportCardDraft.Field]
    let addLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($fields) { $field in
                HStack(spacing: 4) {
                    TextField("Parâmetro", text: $field.key)
                        .frame(width: 92)
                        .accessibilityLabel("Nome do parâmetro")
                    TextField("Valor", text: $field.value)
                        .foregroundStyle(field.isJSON ? themeManager.current.accentText : themeManager.current.labelPrimary)
                        .help(field.isJSON ? "Valor em JSON (lista ou objeto)" : field.value)
                        .accessibilityLabel("Valor de \(field.key)")
                    Button {
                        fields.removeAll { $0.id == field.id }
                    } label: {
                        Label("Remover \(field.key)", systemImage: "minus.circle")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Remover \(field.key)")
                }
                .textFieldStyle(.roundedBorder)
                .font(DSFont.mono(11))
                .controlSize(.small)
            }
            Button {
                fields.append(.init(key: "", value: ""))
            } label: {
                Label(addLabel, systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}
