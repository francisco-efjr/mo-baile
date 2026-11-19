import SwiftUI

/// Formulário do card no inspector: corrige o que o OCR leu do print do Figma
/// sem abrir o JSON. Grava pela `report.card_update`, que mexe só nestes
/// campos e valida a spec inteira antes de trocar o arquivo.
///
/// Cada problema aparece no próprio campo (RE-02): o Salvar fica desligado
/// enquanto houver erro, e ⌘S com erro mostra todos. O erro do motor ao gravar
/// aparece aqui, acima do rodapé, e não no topo da coluna central.
struct ReportCardEditor: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @Binding var draft: ReportCardDraft
    let onCancel: () -> Void
    let onSave: () -> Void

    private enum Foco: Hashable { case secao, titulo, evento, obs }
    @FocusState private var foco: Foco?
    @State private var eventoTocado = false
    @State private var tentouGravar = false
    /// O erro do motor só é deste formulário depois de um Salvar enviado daqui.
    @State private var enviou = false
    /// Campos das linhas chave e valor em edição: Esc termina o campo em vez
    /// de cancelar o card.
    @State private var linhasEmEdicao = 0

    var body: some View {
        let theme = themeManager.current
        let gravando = appState.reportOperation == .savingCard
        let problemas = draft.issues()
        let contexto = "card \(draft.cardIndex + 1)"
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s6) {
                    campo("Seção", texto: $draft.secao, foco: .secao)
                    campo("Título", texto: $draft.titulo, dica: "Vazio: usa o evento", foco: .titulo)
                    campo("Evento", texto: $draft.evento, mono: true, foco: .evento,
                          issue: (eventoTocado || tentouGravar) ? problemas.evento : nil)

                    secao("Parâmetros") {
                        ReportFieldRows(
                            fields: $draft.params, addLabel: "Adicionar Parâmetro",
                            issues: problemas.rows, revealAll: tentouGravar, context: contexto,
                            onEditingChange: editando
                        )
                        if !draft.paramsPerFlow.isEmpty {
                            nota("Parâmetros próprios de \(draft.paramsPerFlow.joined(separator: ", ")) ficam no JSON.")
                        }
                    }

                    secao("Variações") {
                        ForEach($draft.variacoes) { $variacao in
                            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
                                HStack {
                                    Text("Variação \(posicao(variacao) + 1)")
                                        .font(DSFont.subheadlineSemibold)
                                        .foregroundStyle(theme.labelSecondary)
                                    Spacer()
                                    BarIconButton(icon: "minus.circle", label: "Remover a variação \(posicao(variacao) + 1)") {
                                        draft.variacoes.removeAll { $0.id == variacao.id }
                                    }
                                }
                                ReportFieldRows(
                                    fields: $variacao.fields, addLabel: "Adicionar Campo",
                                    issues: problemas.rows, revealAll: tentouGravar,
                                    context: "\(contexto), variação \(posicao(variacao) + 1)",
                                    onEditingChange: editando
                                )
                            }
                            .padding(DesignMetrics.Spacing.s4)
                            .background(theme.bgContentAlt, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
                        }
                        Button {
                            draft.variacoes.append(.init(fields: [.init(key: "detail", value: "")]))
                        } label: {
                            Label("Adicionar Variação", systemImage: "plus")
                        }
                        .buttonStyle(PlainTextButtonStyle(theme: theme))
                        .controlSize(.small)
                    }

                    secao("Observação") {
                        if draft.obsPerFlow {
                            nota("A observação deste card é por fluxo e fica no JSON.")
                        } else {
                            // Cresce com o texto, sem rolagem própria dentro do formulário.
                            TextField("Observação", text: $draft.obs, prompt: Text("Sem observação"), axis: .vertical)
                                .lineLimit(2...12)
                                .textFieldStyle(.roundedBorder)
                                .font(DSFont.callout)
                                .focused($foco, equals: .obs)
                                .accessibilityLabel("Observação")
                        }
                    }

                    nota("Regras: [preenchido], [numero], [data], [a|b], re:…, {fluxo} e [soma_itens]. "
                         + "Na chave, a|b aceita uma das duas (ex.: item_id|item_name).")
                }
                .padding(DesignMetrics.Spacing.s6)
            }

            if enviou, !gravando, let erro = appState.reportError {
                InlineError(title: "Não deu para gravar.", text: erro)
                    .padding(.horizontal, DesignMetrics.Spacing.s5)
                    .padding(.vertical, DesignMetrics.Spacing.s3)
            }

            Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)
            HStack(spacing: DesignMetrics.Spacing.s4) {
                if gravando { ProgressView().controlSize(.small) }
                if problemas.blockingCount > 0 && tentouGravar {
                    StatusIndicator(status: .error, label: Self.paraCorrigir(problemas.blockingCount), mono: false)
                }
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(editandoAlgo ? nil : .cancelAction)
                Button("Salvar") {
                    if problemas.blockingCount > 0 {
                        tentouGravar = true
                    } else {
                        enviou = true
                        onSave()
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help(problemas.blockingCount > 0
                      ? "Corrija os campos marcados antes de gravar"
                      : "Grava o card na spec e audita de novo (⌘S)")
            }
            .disabled(gravando)
            .padding(.horizontal, DesignMetrics.Spacing.s6)
            .padding(.vertical, DesignMetrics.Spacing.s5 - 2)
        }
        .onChange(of: foco) { antigo, _ in
            if antigo == .evento { eventoTocado = true }
        }
        .onExitCommand { foco = nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editar card \(draft.cardIndex + 1) de \(draft.totalCards)")
    }

    private var editandoAlgo: Bool { foco != nil || linhasEmEdicao > 0 }

    private func editando(_ ativo: Bool) {
        linhasEmEdicao = max(0, linhasEmEdicao + (ativo ? 1 : -1))
    }

    static func paraCorrigir(_ n: Int) -> String {
        n == 1 ? "1 campo para corrigir" : "\(n) campos para corrigir"
    }

    private func posicao(_ variacao: ReportCardDraft.Variation) -> Int {
        draft.variacoes.firstIndex { $0.id == variacao.id } ?? 0
    }

    private func campo(
        _ rotulo: String, texto: Binding<String>, dica: String? = nil, mono: Bool = false, foco alvo: Foco,
        issue: FieldIssue? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            Text(rotulo)
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(themeManager.current.labelSecondary)
            TextField(rotulo, text: texto, prompt: dica.map { Text($0) }, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .font(mono ? DSFont.mono(11) : DSFont.callout)
                .autocorrectionDisabled(mono)
                .labelsHidden()
                .focused($foco, equals: alvo)
                .onChange(of: texto.wrappedValue) { _, novo in
                    if novo.contains(where: \.isNewline) { texto.wrappedValue = novo.filter { !$0.isNewline } }
                }
                .dsFieldIssue(issue)
                .accessibilityLabel(rotulo)
            if let issue { FieldMessage(issue: issue) }
        }
    }

    private func secao<Conteudo: View>(_ titulo: String, @ViewBuilder conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
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
