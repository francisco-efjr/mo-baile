import SwiftUI

/// Editor de spec dentro do app: os cards da spec em quadro (um quadro por
/// card, agrupado por seção, com o print ao alcance) ou em tabela (uma linha
/// por parâmetro). Substitui o "Abrir no Editor" que jogava o JSON para fora.
///
/// Lê por `report.cards`, que abre também o rascunho da importação que ainda
/// não valida, e grava por `report.cards_update`, que aplica todos os cards
/// alterados e valida a spec inteira uma vez. A busca da toolbar filtra os
/// cards nos dois modos.
struct ReportSpecEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    @State private var confirmandoDescarte = false

    var body: some View {
        let theme = themeManager.current
        if let editor = appState.reportSpecEditor {
            VStack(spacing: 0) {
                cabecalho(editor)
                Rectangle().fill(theme.separator).frame(height: 1)

                if let erro = editor.specError {
                    InlineError(title: "A spec ainda não é válida.", text: erro)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }

                let visiveis = cardsVisiveis(editor)
                if visiveis.isEmpty {
                    EmptyState(icon: "magnifyingglass", text: "Nenhum card corresponde ao filtro.", compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.reportSpecEditorMode == .board {
                    ReportSpecBoard(editor: editor, visiveis: visiveis, card: binding)
                } else {
                    ReportSpecTable(editor: editor, visiveis: visiveis, card: binding)
                }
            }
            .crossfade(on: appState.reportSpecEditorMode)
            .frame(minWidth: 440)
            .confirmationDialog(
                "Descartar as alterações da spec?",
                isPresented: $confirmandoDescarte
            ) {
                Button("Descartar", role: .destructive) { appState.reportSpecEditor = nil }
                Button("Continuar Editando", role: .cancel) {}
            } message: {
                Text("\(Self.contagem(editor.dirtyCards.count)) sem gravar em \(editor.fileName).")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Editor da spec \(editor.fileName)")
        }
    }

    // MARK: - Cabeçalho

    private func cabecalho(_ editor: ReportSpecDraft) -> some View {
        @Bindable var state = appState
        let theme = themeManager.current
        let ocupado = appState.reportOperation != nil
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Editar Spec")
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(situacao(editor))
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(editor.path)
            }
            .layoutPriority(-1)

            Spacer(minLength: 8)

            Picker("Modo", selection: $state.reportSpecEditorMode) {
                ForEach(ReportSpecEditorMode.allCases) { modo in
                    Text(modo.title).tag(modo)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Modo do editor")

            Button("Fechar") {
                if editor.isDirty { confirmandoDescarte = true } else { appState.reportSpecEditor = nil }
            }
            .keyboardShortcut(.cancelAction)
            .help("Volta para a auditoria")

            Button("Salvar") {
                Task { await session.saveReportSpecEditor() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!editor.canSave || ocupado)
            .help(ajudaSalvar(editor))
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func situacao(_ editor: ReportSpecDraft) -> String {
        var partes = [editor.projeto ?? "sem projeto", editor.fileName, Self.contagem(editor.cards.count, verbo: nil)]
        let alterados = editor.dirtyCards.count
        if alterados > 0 { partes.append(Self.contagem(alterados)) }
        return partes.joined(separator: " · ")
    }

    private func ajudaSalvar(_ editor: ReportSpecDraft) -> String {
        if !editor.isDirty { return "Nada alterado" }
        if !editor.canSave { return "Corrija os cards marcados antes de gravar" }
        return "Grava os cards alterados na spec e audita de novo (⌘S)"
    }

    static func contagem(_ n: Int, verbo: String? = "alterado") -> String {
        let cards = n == 1 ? "1 card" : "\(n) cards"
        guard let verbo else { return cards }
        return "\(cards) \(verbo)\(n == 1 ? "" : "s")"
    }

    // MARK: - Dados

    private func cardsVisiveis(_ editor: ReportSpecDraft) -> [ReportCardDraft] {
        let busca = SearchQuery(appState.reportFilterText)
        guard !busca.isEmpty else { return editor.cards }
        return editor.cards.filter { busca.matchesLiteral($0.searchableFields) }
    }

    /// Card pelo índice na spec. O `get` devolve o último valor conhecido se o
    /// editor fechar com um campo ainda em foco.
    private func binding(_ card: ReportCardDraft) -> Binding<ReportCardDraft> {
        let indice = card.cardIndex
        return Binding(
            get: {
                guard let cards = appState.reportSpecEditor?.cards, cards.indices.contains(indice) else { return card }
                return cards[indice]
            },
            set: { novo in
                guard appState.reportSpecEditor?.cards.indices.contains(indice) == true else { return }
                appState.reportSpecEditor?.cards[indice] = novo
            }
        )
    }
}

// MARK: - Quadro

/// Um quadro por card, no jeito de uma caixa de classe da UML: nome em cima,
/// depois os compartimentos de parâmetros, variações e observação.
private struct ReportSpecBoard: View {
    @Environment(ThemeManager.self) private var themeManager
    let editor: ReportSpecDraft
    let visiveis: [ReportCardDraft]
    let card: (ReportCardDraft) -> Binding<ReportCardDraft>

    private let colunas = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 12, alignment: .top)]

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(editor.sections, id: \.self) { secao in
                    let daSecao = visiveis.filter { $0.secao == secao }
                    if !daSecao.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(secao.isEmpty ? "Sem seção" : secao)
                                    .font(DSFont.title3)
                                    .foregroundStyle(theme.labelPrimary)
                                    .accessibilityAddTraits(.isHeader)
                                Text(ReportSpecEditorView.contagem(daSecao.count, verbo: nil))
                                    .font(DSFont.subheadline)
                                    .foregroundStyle(theme.labelTertiary)
                            }
                            LazyVGrid(columns: colunas, alignment: .leading, spacing: 12) {
                                ForEach(daSecao, id: \.cardIndex) { item in
                                    ReportSpecCardBox(
                                        card: card(item),
                                        printPath: editor.printPath(of: item),
                                        printsDir: editor.printsDir,
                                        alterado: editor.isDirty(item.cardIndex),
                                        apontadoPeloMotor: editor.invalidCardIndex == item.cardIndex
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct ReportSpecCardBox: View {
    @Environment(ThemeManager.self) private var themeManager
    @Binding var card: ReportCardDraft
    let printPath: String?
    let printsDir: String?
    let alterado: Bool
    let apontadoPeloMotor: Bool

    @State private var mostrandoPrint = false

    var body: some View {
        let theme = themeManager.current
        let problemas = card.problems
        let comErro = !problemas.isEmpty || apontadoPeloMotor
        VStack(alignment: .leading, spacing: 0) {
            // Nome
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Card \(card.cardIndex + 1)")
                        .font(DSFont.subheadlineSemibold)
                        .foregroundStyle(theme.labelTertiary)
                    if alterado {
                        StatusIndicator(status: .warn, label: "Alterado", mono: false)
                    }
                    Spacer(minLength: 4)
                    if printPath != nil {
                        Button {
                            mostrandoPrint = true
                        } label: {
                            Label("Ver Print", systemImage: "photo")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Mostra o print do card (\(card.printName ?? ""))")
                        .popover(isPresented: $mostrandoPrint, arrowEdge: .trailing) {
                            ReportPrintImage(path: printPath, printsDir: printsDir)
                                .padding(12)
                                .frame(maxWidth: 460, maxHeight: 620)
                                .environment(themeManager)
                        }
                    }
                }
                TextField("Título", text: $card.titulo, prompt: Text("Título (vazio: usa o evento)"))
                    .font(DSFont.callout.weight(.semibold))
                    .accessibilityLabel("Título do card \(card.cardIndex + 1)")
                TextField("Evento", text: $card.evento, prompt: Text("evento"))
                    .font(DSFont.mono(11, weight: .medium))
                    .accessibilityLabel("Evento do card \(card.cardIndex + 1)")
                TextField("Seção", text: $card.secao, prompt: Text("Seção"))
                    .font(DSFont.callout)
                    .accessibilityLabel("Seção do card \(card.cardIndex + 1)")
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .padding(10)
            .background(theme.bgContentAlt)

            divisor

            compartimento("Parâmetros") {
                ReportFieldRows(fields: $card.params, addLabel: "Adicionar Parâmetro", keyWidth: 104)
                if !card.paramsPerFlow.isEmpty {
                    nota("Parâmetros próprios de \(card.paramsPerFlow.joined(separator: ", ")) ficam no JSON.")
                }
            }

            divisor

            compartimento("Variações") {
                ForEach($card.variacoes) { $variacao in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Variação \(posicao(variacao) + 1)")
                                .font(DSFont.subheadline)
                                .foregroundStyle(theme.labelSecondary)
                            Spacer()
                            Button {
                                card.variacoes.removeAll { $0.id == variacao.id }
                            } label: {
                                Label("Remover Variação", systemImage: "minus.circle")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Remover a variação \(posicao(variacao) + 1)")
                        }
                        ReportFieldRows(fields: $variacao.fields, addLabel: "Adicionar Campo", keyWidth: 104)
                    }
                }
                Button {
                    card.variacoes.append(.init(fields: [.init(key: "detail", value: "")]))
                } label: {
                    Label("Adicionar Variação", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            divisor

            compartimento("Observação") {
                if card.obsPerFlow {
                    nota("A observação deste card é por fluxo e fica no JSON.")
                } else {
                    TextField("Observação", text: $card.obs, prompt: Text("Sem observação"), axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .font(DSFont.callout)
                        .accessibilityLabel("Observação do card \(card.cardIndex + 1)")
                }
            }

            if !problemas.isEmpty {
                divisor
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(problemas, id: \.self) { problema in
                        Label(problema, systemImage: "exclamationmark.circle.fill")
                            .font(DSFont.subheadline)
                            .foregroundStyle(theme.destructive)
                    }
                }
                .padding(10)
                .accessibilityElement(children: .combine)
            }
        }
        .background(theme.bgContent)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.card)
                .strokeBorder(comErro ? theme.destructive : theme.separatorStrong, lineWidth: comErro ? 1.5 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card \(card.cardIndex + 1): \(card.displayTitle)")
    }

    private var divisor: some View {
        Rectangle().fill(themeManager.current.separator).frame(height: 1)
    }

    private func posicao(_ variacao: ReportCardDraft.Variation) -> Int {
        card.variacoes.firstIndex { $0.id == variacao.id } ?? 0
    }

    private func compartimento<Conteudo: View>(_ titulo: String, @ViewBuilder conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo.uppercased())
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(themeManager.current.labelTertiary)
                .accessibilityAddTraits(.isHeader)
            conteudo()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nota(_ texto: String) -> some View {
        Text(texto)
            .font(DSFont.footnote)
            .foregroundStyle(themeManager.current.labelTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Tabela

/// Uma linha por parâmetro ou campo de variação, com nome e valor editáveis
/// na célula. Acrescentar e remover linhas é no Quadro.
private struct ReportSpecTable: View {
    @Environment(ThemeManager.self) private var themeManager
    let editor: ReportSpecDraft
    let visiveis: [ReportCardDraft]
    let card: (ReportCardDraft) -> Binding<ReportCardDraft>

    struct Linha: Identifiable {
        let id: UUID
        let cardIndex: Int
        let secao: String
        let titulo: String
        let evento: String
        /// `nil` nos parâmetros do card; a posição nas variações.
        let variacao: Int?
        let isJSON: Bool

        var onde: String { variacao.map { "Variação \($0 + 1)" } ?? "Parâmetro" }
    }

    var body: some View {
        let theme = themeManager.current
        Table(linhas) {
            TableColumn("Card") { linha in
                Text("\(linha.cardIndex + 1) · \(linha.titulo)")
                    .font(DSFont.callout)
                    .lineLimit(1)
                    .help("\(linha.secao) · \(linha.titulo)")
            }
            .width(min: 80, ideal: 120)

            TableColumn("Evento") { linha in
                Text(linha.evento)
                    .font(DSFont.mono(11, weight: .medium))
                    .foregroundStyle(theme.accentText)
                    .lineLimit(1)
                    .help(linha.evento)
            }
            .width(min: 90, ideal: 150)

            TableColumn("Onde") { linha in
                Text(linha.onde)
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(1)
            }
            .width(min: 64, ideal: 76, max: 96)

            TableColumn("Parâmetro") { linha in
                TextField("Parâmetro", text: campo(linha).key)
                    .font(DSFont.mono(11))
                    .accessibilityLabel("Nome do parâmetro, card \(linha.cardIndex + 1)")
            }
            .width(min: 80, ideal: 120)

            TableColumn("Valor") { linha in
                TextField("Valor", text: campo(linha).value)
                    .font(DSFont.mono(11))
                    .foregroundStyle(linha.isJSON ? theme.accentText : theme.labelPrimary)
                    .help(linha.isJSON ? "Valor em JSON (lista ou objeto)" : "")
                    .accessibilityLabel("Valor do parâmetro, card \(linha.cardIndex + 1)")
            }
            .width(min: 140, ideal: 220)
        }
        .alternatingRowBackgrounds()
        .accessibilityLabel("Parâmetros da spec")
    }

    private var linhas: [Linha] {
        visiveis.flatMap { card -> [Linha] in
            let grupos: [(Int?, [ReportCardDraft.Field])] =
                [(nil, card.params)] + card.variacoes.enumerated().map { ($0.offset, $0.element.fields) }
            return grupos.flatMap { variacao, campos in
                campos.map {
                    Linha(id: $0.id, cardIndex: card.cardIndex, secao: card.secao, titulo: card.displayTitle,
                          evento: card.evento, variacao: variacao, isJSON: $0.isJSON)
                }
            }
        }
    }

    /// O campo da linha dentro do card, achado pelo `id`: a posição muda quando
    /// o Quadro acrescenta ou remove linhas.
    private func campo(_ linha: Linha) -> Binding<ReportCardDraft.Field> {
        guard let original = visiveis.first(where: { $0.cardIndex == linha.cardIndex }) else {
            return .constant(.init(key: "", value: ""))
        }
        let alvo = card(original)
        return Binding(
            get: {
                let atual = alvo.wrappedValue
                let campos = linha.variacao.map { atual.variacoes.indices.contains($0) ? atual.variacoes[$0].fields : [] }
                    ?? atual.params
                return campos.first { $0.id == linha.id } ?? .init(key: "", value: "")
            },
            set: { novo in
                var atual = alvo.wrappedValue
                if let v = linha.variacao {
                    guard atual.variacoes.indices.contains(v),
                          let i = atual.variacoes[v].fields.firstIndex(where: { $0.id == linha.id }) else { return }
                    atual.variacoes[v].fields[i] = novo
                } else {
                    guard let i = atual.params.firstIndex(where: { $0.id == linha.id }) else { return }
                    atual.params[i] = novo
                }
                alvo.wrappedValue = atual
            }
        )
    }
}
