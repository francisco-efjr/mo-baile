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
    /// Pedido do "N para corrigir": o Quadro rola até o card, a Tabela seleciona a linha.
    @State private var pedido: ReportSpecJump?
    /// Depois do "N para corrigir" ou do ⌘S com erro, todo erro aparece, tocado ou não.
    @State private var revelarProblemas = false

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
                    ReportSpecBoard(editor: editor, visiveis: visiveis, card: binding,
                                    pedido: pedido, revelarProblemas: revelarProblemas)
                } else {
                    ReportSpecTable(editor: editor, visiveis: visiveis, card: binding, pedido: pedido)
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
        let paraCorrigir = Self.problemas(editor)
        return HStack(spacing: DesignMetrics.Spacing.s4) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
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

            Spacer(minLength: DesignMetrics.Spacing.s4)

            if paraCorrigir > 0 {
                Button {
                    irParaPrimeiroProblema(editor)
                } label: {
                    StatusIndicator(status: .error, label: "\(paraCorrigir) para corrigir", mono: false)
                }
                .buttonStyle(.plain)
                .help("Mostra o primeiro campo com erro")
                .accessibilityHint("Mostra o primeiro campo com erro")
            }

            ReportValueRulesHelpButton()

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
                if paraCorrigir > 0 {
                    irParaPrimeiroProblema(editor)
                } else {
                    Task { await session.saveReportSpecEditor() }
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!editor.isDirty || ocupado)
            .help(ajudaSalvar(editor, paraCorrigir: paraCorrigir))
        }
        .controlSize(.small)
        .padding(.horizontal, DesignMetrics.Spacing.s5)
        .padding(.vertical, DesignMetrics.Spacing.s4)
    }

    /// Erros dos cards alterados: só eles barram o Salvar (`canSave`).
    static func problemas(_ editor: ReportSpecDraft) -> Int {
        editor.dirtyCards.reduce(0) { $0 + $1.issues().blockingCount }
    }

    /// Rola o Quadro até o primeiro card com erro, ou seleciona a linha na
    /// Tabela, e passa a mostrar todos os erros.
    private func irParaPrimeiroProblema(_ editor: ReportSpecDraft) {
        revelarProblemas = true
        guard let card = editor.dirtyCards.first(where: { $0.issues().blockingCount > 0 }) else { return }
        pedido = ReportSpecJump(cardIndex: card.cardIndex, fieldID: card.issues().firstBlockingRow)
    }

    private func situacao(_ editor: ReportSpecDraft) -> String {
        var partes = [editor.projeto ?? "sem projeto", editor.fileName, Self.contagem(editor.cards.count, verbo: nil)]
        let alterados = editor.dirtyCards.count
        if alterados > 0 { partes.append(Self.contagem(alterados)) }
        return partes.joined(separator: " · ")
    }

    private func ajudaSalvar(_ editor: ReportSpecDraft, paraCorrigir: Int) -> String {
        if !editor.isDirty { return "Nada alterado" }
        if paraCorrigir > 0 {
            return paraCorrigir == 1 ? "Corrija o campo marcado antes de gravar" : "Corrija os \(paraCorrigir) campos marcados antes de gravar"
        }
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

/// Pedido para mostrar um problema: o card e, se houver, a linha com erro.
struct ReportSpecJump: Equatable {
    let cardIndex: Int
    let fieldID: UUID?
    /// Muda a cada clique, para o mesmo card poder ser pedido de novo.
    let token = UUID()
}

// MARK: - Quadro

/// Um quadro por card, no jeito de uma caixa de classe da UML: nome em cima,
/// depois os compartimentos de parâmetros, variações e observação.
private struct ReportSpecBoard: View {
    @Environment(ThemeManager.self) private var themeManager
    let editor: ReportSpecDraft
    let visiveis: [ReportCardDraft]
    let card: (ReportCardDraft) -> Binding<ReportCardDraft>
    let pedido: ReportSpecJump?
    let revelarProblemas: Bool

    private let colunas = [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: DesignMetrics.Spacing.s5, alignment: .top)]

    var body: some View {
        let theme = themeManager.current
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignMetrics.Spacing.s8 - 2) {
                    ForEach(editor.sections, id: \.self) { secao in
                        let daSecao = visiveis.filter { $0.secao == secao }
                        if !daSecao.isEmpty {
                            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                                HStack(spacing: DesignMetrics.Spacing.s3) {
                                    Text(secao.isEmpty ? "Sem seção" : secao)
                                        .font(DSFont.title3)
                                        .foregroundStyle(theme.labelPrimary)
                                        .lineLimit(2)
                                        .accessibilityAddTraits(.isHeader)
                                    Text(ReportSpecEditorView.contagem(daSecao.count, verbo: nil))
                                        .font(DSFont.subheadline)
                                        .foregroundStyle(theme.labelTertiary)
                                }
                                LazyVGrid(columns: colunas, alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                                    ForEach(daSecao, id: \.cardIndex) { item in
                                        let alterado = editor.isDirty(item.cardIndex)
                                        ReportSpecCardBox(
                                            card: card(item),
                                            printPath: editor.printPath(of: item),
                                            printsDir: editor.printsDir,
                                            alterado: alterado,
                                            apontadoPeloMotor: editor.invalidCardIndex == item.cardIndex,
                                            // Card que veio assim do disco mostra o erro de cara:
                                            // não foi a pessoa que digitou.
                                            revelar: revelarProblemas || !alterado
                                        )
                                        .id(item.cardIndex)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(DesignMetrics.Spacing.s5)
            }
            .onChange(of: pedido?.token) { _, _ in
                guard let pedido else { return }
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(pedido.cardIndex, anchor: .top) }
            }
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
    let revelar: Bool

    @State private var mostrandoPrint = false
    @FocusState private var eventoEmFoco: Bool
    @State private var eventoTocado = false

    var body: some View {
        let theme = themeManager.current
        let problemas = card.issues()
        let comErro = problemas.blockingCount > 0 || apontadoPeloMotor
        VStack(alignment: .leading, spacing: 0) {
            nome(problemas)
            divisor
            compartimento("Parâmetros") {
                ReportFieldRows(
                    fields: $card.params, addLabel: "Adicionar Parâmetro",
                    issues: problemas.rows, revealAll: revelar, context: contexto
                )
                if !card.paramsPerFlow.isEmpty {
                    nota("Parâmetros próprios de \(card.paramsPerFlow.joined(separator: ", ")) ficam no JSON.")
                }
            }
            divisor
            variacoes(problemas)
            divisor
            compartimento("Observação") {
                if card.obsPerFlow {
                    nota("A observação deste card é por fluxo e fica no JSON.")
                } else {
                    TextField("Observação", text: $card.obs, prompt: Text("Sem observação"), axis: .vertical)
                        .lineLimit(1...6)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .font(DSFont.callout)
                        .accessibilityLabel("Observação do card \(card.cardIndex + 1)")
                }
            }
        }
        .background(theme.bgContent)
        .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.card)
                .strokeBorder(comErro ? theme.destructive : theme.separatorStrong, lineWidth: comErro ? 1.5 : 1)
        }
        .onChange(of: eventoEmFoco) { antes, _ in if antes { eventoTocado = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card \(card.cardIndex + 1): \(card.displayTitle)")
    }

    private var contexto: String { "card \(card.cardIndex + 1) · \(card.evento)" }

    @ViewBuilder
    private func nome(_ problemas: ReportCardIssues) -> some View {
        let theme = themeManager.current
        let erroDoEvento = (revelar || eventoTocado) ? problemas.evento : nil
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            HStack(spacing: DesignMetrics.Spacing.s3) {
                Text("Card \(card.cardIndex + 1)")
                    .font(DSFont.subheadlineSemibold)
                    .foregroundStyle(theme.labelTertiary)
                if alterado {
                    StatusIndicator(status: .warn, label: "Alterado", mono: false)
                }
                if problemas.blockingCount > 0 {
                    StatusIndicator(status: .error, label: ReportCardEditor.paraCorrigir(problemas.blockingCount), mono: false)
                }
                Spacer(minLength: DesignMetrics.Spacing.s2)
                if printPath != nil {
                    BarIconButton(icon: "photo", label: "Ver o print do card (\(card.printName ?? ""))") {
                        mostrandoPrint = true
                    }
                    .popover(isPresented: $mostrandoPrint, arrowEdge: .trailing) {
                        ReportPrintImage(path: printPath, printsDir: printsDir)
                            .padding(DesignMetrics.Spacing.s5)
                            .frame(maxWidth: 460, maxHeight: 620)
                            .environment(themeManager)
                    }
                }
            }
            TextField("Título", text: $card.titulo, prompt: Text("Título (vazio: usa o evento)"), axis: .vertical)
                .lineLimit(1...2)
                .font(DSFont.callout.weight(.semibold))
                .accessibilityLabel("Título do card \(card.cardIndex + 1)")
            TextField("Evento", text: $card.evento, prompt: Text("evento"))
                .font(DSFont.mono(11, weight: .medium))
                .autocorrectionDisabled()
                .focused($eventoEmFoco)
                .dsFieldIssue(erroDoEvento)
                .help(card.evento.count > 30 ? card.evento : "")
                .accessibilityLabel("Evento do card \(card.cardIndex + 1)")
            if let erroDoEvento { FieldMessage(issue: erroDoEvento) }
            TextField("Seção", text: $card.secao, prompt: Text("Seção"))
                .font(DSFont.callout)
                .help(card.secao.count > 30 ? card.secao : "")
                .accessibilityLabel("Seção do card \(card.cardIndex + 1)")
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .padding(DesignMetrics.Spacing.s5 - 2)
        .background(theme.bgContentAlt)
    }

    private func variacoes(_ problemas: ReportCardIssues) -> some View {
        compartimento("Variações") {
            ForEach($card.variacoes) { $variacao in
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
                    HStack {
                        Text("Variação \(posicao(variacao) + 1)")
                            .font(DSFont.subheadline)
                            .foregroundStyle(themeManager.current.labelSecondary)
                        Spacer()
                        BarIconButton(icon: "minus.circle", label: "Remover a variação \(posicao(variacao) + 1)") {
                            card.variacoes.removeAll { $0.id == variacao.id }
                        }
                    }
                    ReportFieldRows(
                        fields: $variacao.fields, addLabel: "Adicionar Campo",
                        issues: problemas.rows, revealAll: revelar,
                        context: "\(contexto), variação \(posicao(variacao) + 1)"
                    )
                }
            }
            Button {
                card.variacoes.append(.init(fields: [.init(key: "detail", value: "")]))
            } label: {
                Label("Adicionar Variação", systemImage: "plus")
            }
            .buttonStyle(PlainTextButtonStyle(theme: themeManager.current))
            .controlSize(.small)
        }
    }

    private var divisor: some View {
        Rectangle().fill(themeManager.current.separator).frame(height: DesignMetrics.hairline)
    }

    private func posicao(_ variacao: ReportCardDraft.Variation) -> Int {
        card.variacoes.firstIndex { $0.id == variacao.id } ?? 0
    }

    private func compartimento<Conteudo: View>(_ titulo: String, @ViewBuilder conteudo: () -> Conteudo) -> some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            Text(titulo.uppercased())
                .font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(themeManager.current.labelTertiary)
                .accessibilityAddTraits(.isHeader)
            conteudo()
        }
        .padding(DesignMetrics.Spacing.s5 - 2)
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
///
/// A primeira coluna diz se a linha tem erro ou foi alterada; a barra de baixo
/// mostra o erro da linha escolhida, porque erro não pode ficar só no tooltip.
private struct ReportSpecTable: View {
    @Environment(ThemeManager.self) private var themeManager
    let editor: ReportSpecDraft
    let visiveis: [ReportCardDraft]
    let card: (ReportCardDraft) -> Binding<ReportCardDraft>
    let pedido: ReportSpecJump?

    @State private var selecao: UUID?
    @State private var jsonEmEdicao: Linha?

    struct Linha: Identifiable {
        let id: UUID
        let cardIndex: Int
        let secao: String
        let titulo: String
        let evento: String
        /// `nil` nos parâmetros do card; a posição nas variações.
        let variacao: Int?
        let isJSON: Bool
        let chave: String
        let issue: ReportRowIssue?
        let alterado: Bool

        var onde: String { variacao.map { "Variação \($0 + 1)" } ?? "Parâmetro" }
        var contexto: String { "card \(cardIndex + 1) · \(evento)" }
    }

    var body: some View {
        let theme = themeManager.current
        let todas = linhas
        VStack(spacing: 0) {
            Table(todas, selection: $selecao) {
                TableColumn("") { linha in
                    situacao(linha)
                }
                .width(22)

                TableColumn("Card") { linha in
                    Text("\(linha.cardIndex + 1) · \(linha.titulo)")
                        .font(DSFont.callout)
                        .lineLimit(1)
                        .help("\(linha.secao) · \(linha.titulo)")
                }
                .width(min: 70, ideal: 100)

                TableColumn("Evento") { linha in
                    Text(linha.evento)
                        .font(DSFont.mono(11, weight: .medium))
                        .foregroundStyle(theme.accentText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(linha.evento)
                }
                .width(min: 90, ideal: 120)

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
                        .autocorrectionDisabled()
                        .dsFieldIssue(linha.issue?.key, theme: theme)
                        .help(linha.chave.count > 16 ? linha.chave : "")
                        .accessibilityLabel("Nome do parâmetro, \(linha.contexto)")
                }
                .width(min: 90, ideal: 130)

                TableColumn("Valor") { linha in
                    valor(linha)
                }
                .width(min: 160, ideal: 240)
            }
            .alternatingRowBackgrounds()
            .accessibilityLabel("Parâmetros da spec")

            barraDoProblema(todas)
        }
        .onChange(of: pedido?.token) { _, _ in
            if let alvo = pedido?.fieldID { selecao = alvo }
        }
        .sheet(item: $jsonEmEdicao) { linha in
            ReportJSONValueSheet(key: linha.chave, context: linha.contexto, value: campo(linha).value)
                .environment(themeManager)
        }
    }

    @ViewBuilder
    private func situacao(_ linha: Linha) -> some View {
        let theme = themeManager.current
        if let issue = linha.issue, let primeira = issue.messages.first {
            Image(systemName: issue.blocking ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.blocking ? theme.destructive : theme.warning)
                .help(issue.messages.map(\.message).joined(separator: "\n"))
                .accessibilityLabel(issue.blocking ? "Problema: \(primeira.message)" : "Aviso: \(primeira.message)")
        } else if linha.alterado {
            Image(systemName: "pencil")
                .foregroundStyle(theme.labelSecondary)
                .help("Card alterado")
                .accessibilityLabel("Alterado")
        }
    }

    @ViewBuilder
    private func valor(_ linha: Linha) -> some View {
        let theme = themeManager.current
        let atual = campo(linha).wrappedValue.value
        if linha.isJSON {
            Button {
                jsonEmEdicao = linha
            } label: {
                HStack(spacing: DesignMetrics.Spacing.s2) {
                    Image(systemName: "curlybraces").foregroundStyle(theme.labelSecondary).accessibilityHidden(true)
                    Text(ReportJSONSummary.text(atual))
                        .font(DSFont.mono(11))
                        .foregroundStyle(theme.accentText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dsFieldIssue(linha.issue?.value, theme: theme)
            .help("Editar o JSON de \(linha.chave)")
            .accessibilityLabel("Valor JSON de \(linha.chave), \(linha.contexto)")
            .accessibilityValue(ReportJSONSummary.text(atual))
        } else {
            TextField("Valor", text: campo(linha).value)
                .font(DSFont.mono(11))
                .autocorrectionDisabled()
                .dsFieldIssue(linha.issue?.value, theme: theme)
                .help(atual.count > 25 ? atual : "")
                .accessibilityLabel("Valor de \(linha.chave.replacingOccurrences(of: "|", with: " ou ")), \(linha.contexto)")
        }
    }

    /// Barra de 26 pt: a frase do erro da linha escolhida e Próximo Problema.
    private func barraDoProblema(_ todas: [Linha]) -> some View {
        let theme = themeManager.current
        let comProblema = todas.filter { $0.issue != nil }
        let escolhida = todas.first { $0.id == selecao }
        return VStack(spacing: 0) {
            Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)
            HStack(spacing: DesignMetrics.Spacing.s4) {
                if let issue = escolhida?.issue?.messages.first {
                    FieldMessage(issue: issue)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(comProblema.isEmpty ? "Nenhum problema nas linhas." : "\(comProblema.count) linha(s) com problema.")
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                }
                Spacer(minLength: DesignMetrics.Spacing.s4)
                Button("Próximo Problema") {
                    let depois = comProblema.drop { $0.id != selecao }.dropFirst().first
                    selecao = (depois ?? comProblema.first)?.id
                }
                .buttonStyle(PlainTextButtonStyle(theme: theme))
                .controlSize(.small)
                .keyboardShortcut("'", modifiers: .command)
                .disabled(comProblema.isEmpty)
                .help("Seleciona a próxima linha com problema (⌘')")
            }
            .padding(.horizontal, DesignMetrics.Spacing.s5)
            .frame(height: DesignMetrics.Heights.codeFooter)
        }
    }

    private var linhas: [Linha] {
        visiveis.flatMap { card -> [Linha] in
            let problemas = card.issues()
            let alterado = editor.isDirty(card.cardIndex)
            let grupos: [(Int?, [ReportCardDraft.Field])] =
                [(nil, card.params)] + card.variacoes.enumerated().map { ($0.offset, $0.element.fields) }
            return grupos.flatMap { variacao, campos in
                campos.map {
                    Linha(id: $0.id, cardIndex: card.cardIndex, secao: card.secao, titulo: card.displayTitle,
                          evento: card.evento, variacao: variacao, isJSON: $0.isJSON, chave: $0.key,
                          issue: problemas.rows[$0.id], alterado: alterado)
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
