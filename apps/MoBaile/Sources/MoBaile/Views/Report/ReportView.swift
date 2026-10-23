import SwiftUI

/// Área "Relatório": auditoria do tagueamento contra a spec do Figma.
///
/// O núcleo é o `tag_audit` (projeto bold-kepler), que roda no motor
/// (`report.*`). Esta tela só escolhe arquivos e mostra o resultado: o status de
/// cada variação, o texto das divergências e o bloco com ✓/✗ chegam prontos,
/// iguais aos do board Excalidraw e do HTML exportados.
///
/// Funciona sem aparelho: a spec e o log são arquivos, e os eventos da escuta
/// de Analytics continuam na memória do motor depois que o aparelho sai.
struct ReportView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            ReportToolbar()

            if let erro = appState.reportError {
                InlineError(title: "Não foi possível concluir.", text: erro, actionLabel: "Fechar") {
                    appState.reportError = nil
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Group {
                if let report = appState.report {
                    VStack(spacing: 0) {
                        ReportSummaryBar(report: report)
                        VerticalSplit(storageKey: "alturaTabelaRelatorio", topHeight: 120...640,
                                      idealTopHeight: 300, minBottomHeight: 140) {
                            ReportResultsTable()
                        } bottom: {
                            ReportDetailPane()
                        }
                    }
                    // Sem largura mínima, a altura mínima da janela era medida
                    // com o resumo espremido, uma contagem por linha.
                    .frame(minWidth: 440)
                } else if let spec = appState.reportSpec {
                    ReportSpecCard(spec: spec)
                } else {
                    ReportStartView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.bgContent)
        .overlay {
            if let operacao = appState.reportOperation {
                ReportBusyOverlay(message: appState.reportProgressMessage ?? operacao.message)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.reportImport != nil },
            set: { if !$0 { appState.reportImport = nil } }
        )) {
            ReportImportSheet()
                .environment(appState).environment(session).environment(themeManager)
                .tint(theme.accent)
        }
    }
}

// MARK: - Estados vazios

/// Nada aberto: abrir a spec ou gerar uma a partir dos prints.
private struct ReportStartView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.labelTertiary)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text("Nenhuma spec aberta")
                .font(DSFont.title3)
                .foregroundStyle(theme.labelPrimary)
            Text("Abra a spec de tagueamento (JSON) e audite os eventos que a escuta de Analytics capturou ou um log exportado. Sem spec, gere o rascunho a partir dos prints dos cards do Figma.")
                .font(DSFont.body)
                .foregroundStyle(theme.labelSecondary)
                .multilineTextAlignment(.center)
                // Largura mínima explícita: sem ela, o tamanho mínimo da janela
                // era medido com o texto quebrado palavra por palavra, e a
                // janela crescia para quase 2.000 pt de altura.
                .frame(minWidth: 260, maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Importar Prints do Figma…") { ReportActions.importPrints(appState, session) }
                Button("Abrir Spec…") { ReportActions.openSpec(session) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Spec aberta, ainda sem auditoria: o resumo e o botão de auditar.
private struct ReportSpecCard: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    let spec: ReportSpec

    var body: some View {
        let theme = themeManager.current
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.projeto)
                        .font(DSFont.title2)
                        .foregroundStyle(theme.labelPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text([spec.fileName, spec.versao].compactMap { $0 }.joined(separator: " · "))
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .textSelection(.enabled)
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    linha("Plataforma", (appState.reportEffectivePlatform ?? spec.plataforma).displayName)
                    linha("Cards", "\(spec.cards)")
                    linha("Validações", "\(spec.variants) (card × fluxo × variação)")
                    linha("Fluxos", spec.fluxos.isEmpty ? "—" : spec.fluxos.map(\.label).joined(separator: ", "))
                    linha("Seções", spec.sections.joined(separator: ", "))
                    linha("Prints", spec.printsDir.map { ($0 as NSString).lastPathComponent } ?? "sem pasta de prints",
                          alerta: spec.printsDir != nil && !spec.printsDirExists ? "pasta não encontrada" : nil)
                    linha("Eventos", origem)
                }
                .font(DSFont.callout)

                if case .session = appState.reportLogSource, appState.analyticsEvents.isEmpty {
                    InlineError(
                        title: "Nenhum evento capturado.",
                        text: "Inicie a escuta em Analytics com o app no fluxo da spec, ou escolha um log exportado.",
                        actionLabel: "Escolher Log…"
                    ) {
                        if let url = Exporters.chooseReportLog() { appState.reportLogSource = .file(url) }
                    }
                }

                HStack {
                    Spacer()
                    Button("Auditar") {
                        Task { await session.runReport() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!appState.canRunReport)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .dsCard()
            .padding(DesignMetrics.Spacing.windowMargin)
            .frame(maxWidth: .infinity)
        }
    }

    private var origem: String {
        switch appState.reportLogSource {
        case .session:
            let n = appState.analyticsEvents.count
            return n == 1 ? "1 evento capturado nesta sessão" : "\(n) eventos capturados nesta sessão"
        case .file(let url):
            return url.lastPathComponent
        }
    }

    private func linha(_ rotulo: String, _ valor: String, alerta: String? = nil) -> some View {
        let theme = themeManager.current
        return GridRow {
            Text(rotulo)
                .foregroundStyle(theme.labelSecondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 6) {
                Text(valor)
                    .foregroundStyle(theme.labelPrimary)
                    .textSelection(.enabled)
                if let alerta {
                    StatusIndicator(status: .warn, label: alerta, mono: false)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Operação em andamento por cima da área. Sem vidro: o conteúdo nunca usa.
private struct ReportBusyOverlay: View {
    @Environment(ThemeManager.self) private var themeManager
    let message: String

    var body: some View {
        let theme = themeManager.current
        ZStack {
            theme.bgContent.opacity(0.7)
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(message)
                    .font(DSFont.body)
                    .foregroundStyle(theme.labelPrimary)
            }
            .dsCard(padding: 14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Resumo

/// Conformidade, contagem por status (que também filtra a tabela) e de onde
/// vieram os eventos.
struct ReportSummaryBar: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let report: AuditReport

    var body: some View {
        let theme = themeManager.current
        let s = report.summary
        VStack(alignment: .leading, spacing: 8) {
            // Numa linha quando cabe; em janela estreita (monitor pequeno com
            // barra lateral e inspector), a origem sobe para a linha da
            // conformidade e as contagens quebram linha. Antes a linha única
            // exigia uns 500 pt e empurrava a largura mínima da janela.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    conformidade
                    contagens
                    Spacer(minLength: 8)
                    origemTexto
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        conformidade
                        Spacer(minLength: 8)
                        origemTexto
                    }
                    FlowRow(spacing: 12, lineSpacing: 4) { contagens }
                }
            }

            ProgressBar(value: s.total == 0 ? 0 : Double(s.ok) / Double(s.total), tint: theme.success)
                .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                filtro.pickerStyle(.segmented)
                filtro.pickerStyle(.menu)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    private var conformidade: some View {
        let theme = themeManager.current
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(percentual)
                .font(DSFont.title1.monospacedDigit())
                .foregroundStyle(theme.labelPrimary)
            Text("conforme")
                .font(DSFont.callout)
                .foregroundStyle(theme.labelSecondary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conformidade \(percentual)")
    }

    @ViewBuilder
    private var contagens: some View {
        let s = report.summary
        StatusIndicator(status: .ok, label: "\(s.ok) OK", mono: false)
        StatusIndicator(status: .error, label: plural(s.divergent, "divergente", "divergentes"), mono: false)
        StatusIndicator(status: .warn, label: plural(s.missing, "não disparada", "não disparadas"), mono: false)
        if s.extras > 0 {
            StatusIndicator(status: .off, label: "\(s.extras) fora da spec", mono: false)
        }
        if s.alerts > 0 {
            StatusIndicator(status: .error, label: plural(s.alerts, "alerta", "alertas"), mono: false)
        }
    }

    private var origemTexto: some View {
        Text(origem)
            .font(DSFont.callout)
            .foregroundStyle(themeManager.current.labelSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(ajudaOrigem)
    }

    private var filtro: some View {
        @Bindable var state = appState
        let s = report.summary
        return Picker("Mostrar", selection: $state.reportFilter) {
            Text("Todas \(s.total)").tag(ReportFilter.all)
            Text("Pedem Ação \(s.needsAction)").tag(ReportFilter.needsAction)
            Text("Divergentes \(s.divergent)").tag(ReportFilter.divergent)
            Text("Não Disparadas \(s.missing)").tag(ReportFilter.missing)
            Text("OK \(s.ok)").tag(ReportFilter.ok)
            Text("Fora da Spec \(s.extras + s.alerts)").tag(ReportFilter.outOfSpec)
        }
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel("Mostrar validações")
    }

    private var percentual: String {
        report.summary.complianceRate.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private var origem: String {
        let fonte = report.logPath.map { ($0 as NSString).lastPathComponent } ?? "eventos capturados"
        let uteis = report.logStats.useful == 1 ? "1 evento" : "\(report.logStats.useful) eventos"
        return "\(report.platform.displayName) · \(fonte) · \(uteis)"
    }

    private var ajudaOrigem: String {
        let st = report.logStats
        return "\(st.useful) eventos únicos da plataforma (\(st.duplicates) duplicados removidos de \(st.platformEvents)); \(st.totalRead) lidos no total"
    }

    private func plural(_ n: Int, _ um: String, _ varios: String) -> String {
        "\(n) \(n == 1 ? um : varios)"
    }
}

// MARK: - Tabela

/// Uma linha por variação; em "Fora da Spec", os eventos que nenhum card cobre
/// e os alertas.
struct ReportResultsTable: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    @State private var ordem = [KeyPathComparator(\ReportResult.id)]
    @State private var ordemExtras = [KeyPathComparator(\ReportExtra.id)]

    var body: some View {
        if appState.reportFilter == .outOfSpec {
            extras
        } else {
            resultados
        }
    }

    private var resultados: some View {
        let theme = themeManager.current
        let linhas = appState.filteredReportResults.sorted(using: ordem)
        return Table(linhas, selection: selecao, sortOrder: $ordem) {
            TableColumn("Status", value: \.statusRank) { r in
                StatusIndicator(status: r.status.daemonState, label: r.status.displayName, mono: false)
                    .accessibilityLabel(r.accessibilitySummary)
            }
            .width(min: 96, ideal: 116, max: 140)

            TableColumn("Seção", value: \.section) { r in
                Text(r.section).font(DSFont.callout).lineLimit(1).help(r.cardTitle)
            }
            .width(min: 70, ideal: 110)

            TableColumn("Fluxo", value: \.flowText) { r in
                Text(r.flowText).font(DSFont.callout).lineLimit(1)
            }
            .width(min: 60, ideal: 120)

            TableColumn("Evento", value: \.event) { r in
                Text(r.event)
                    .font(DSFont.mono(11, weight: .medium))
                    .foregroundStyle(theme.accentText)
                    .lineLimit(1)
                    .help(r.event)
            }
            .width(min: 120, ideal: 220)

            TableColumn("Variação", value: \.variation) { r in
                Text(r.variation).font(DSFont.mono(11)).lineLimit(1).help(r.variation)
            }
            .width(min: 100, ideal: 220)

            TableColumn("Divergências", value: \.divergences) { r in
                Text(r.status == .ok ? "" : r.divergences)
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(1)
                    .help(r.divergences)
            }
            .width(min: 120, ideal: 280)

            TableColumn("Horário", value: \.timeText) { r in
                Text(r.timeText)
                    .font(DSFont.mono(11).monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 96, max: 120)

            TableColumn("Disparos", value: \.occurrences) { r in
                Text("\(r.occurrences)")
                    .font(DSFont.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 54, ideal: 64, max: 80)
        }
        .alternatingRowBackgrounds()
        .overlay {
            if linhas.isEmpty {
                EmptyState(
                    icon: appState.reportFilterText.isEmpty ? "checkmark.seal" : "magnifyingglass",
                    text: appState.reportFilterText.isEmpty
                        ? "Nenhuma validação neste recorte."
                        : "Nenhuma validação corresponde ao filtro.",
                    compact: true
                )
                .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Validações do tagueamento")
    }

    private var extras: some View {
        let theme = themeManager.current
        let linhas = appState.filteredReportExtras.sorted(using: ordemExtras)
        return Table(linhas, selection: selecaoExtra, sortOrder: $ordemExtras) {
            TableColumn("Tipo", value: \.id) { e in
                StatusIndicator(status: e.isAlert ? .error : .off, label: e.isAlert ? "Alerta" : "Fora da spec",
                                mono: false)
            }
            .width(min: 96, ideal: 110, max: 130)

            TableColumn("Evento", value: \.event) { e in
                Text(e.event)
                    .font(DSFont.mono(11, weight: .medium))
                    .foregroundStyle(theme.accentText)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 220)

            TableColumn("Tela", value: \.screenText) { e in
                Text(e.screenText).font(DSFont.mono(11)).lineLimit(1).help(e.screenText)
            }
            .width(min: 120, ideal: 260)

            TableColumn("Componente", value: \.componentText) { e in
                Text(e.componentText).font(DSFont.callout).lineLimit(1)
            }
            .width(min: 70, ideal: 100)

            TableColumn("Detail", value: \.detailText) { e in
                Text(e.detailText).font(DSFont.mono(11)).lineLimit(1).help(e.detailText)
            }
            .width(min: 100, ideal: 200)

            TableColumn("Vezes", value: \.count) { e in
                Text("\(e.count)")
                    .font(DSFont.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 60, max: 80)
        }
        .alternatingRowBackgrounds()
        .overlay {
            if linhas.isEmpty {
                EmptyState(icon: "checkmark.seal", text: "Nenhum evento fora da spec nem alerta.", compact: true)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Eventos fora da spec e alertas")
    }

    private var selecao: Binding<ReportResult.ID?> {
        Binding(
            get: { appState.selectedReportResultID },
            set: { appState.selectedReportResultID = $0 }
        )
    }

    private var selecaoExtra: Binding<ReportExtra.ID?> {
        Binding(
            get: { appState.selectedReportExtraID },
            set: { appState.selectedReportExtraID = $0 }
        )
    }
}

// MARK: - Quebra de linha

/// Itens lado a lado que descem para a linha seguinte quando falta largura.
/// O mínimo é o item mais largo, e não a soma de todos.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let linhas = quebrar(largura: proposal.width ?? .infinity, subviews: subviews)
        let largura = linhas.map(\.largura).max() ?? 0
        let altura = linhas.map(\.altura).reduce(0, +) + lineSpacing * CGFloat(max(linhas.count - 1, 0))
        return CGSize(width: largura, height: altura)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for linha in quebrar(largura: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for indice in linha.indices {
                let tamanho = subviews[indice].sizeThatFits(.unspecified)
                subviews[indice].place(at: CGPoint(x: x, y: y + (linha.altura - tamanho.height) / 2),
                                       proposal: ProposedViewSize(tamanho))
                x += tamanho.width + spacing
            }
            y += linha.altura + lineSpacing
        }
    }

    private struct Linha {
        var indices: [Int] = []
        var largura: CGFloat = 0
        var altura: CGFloat = 0
    }

    private func quebrar(largura: CGFloat, subviews: Subviews) -> [Linha] {
        var linhas: [Linha] = []
        var atual = Linha()
        for (indice, subview) in subviews.enumerated() {
            let tamanho = subview.sizeThatFits(.unspecified)
            let nova = atual.indices.isEmpty ? tamanho.width : atual.largura + spacing + tamanho.width
            if !atual.indices.isEmpty && nova > largura {
                linhas.append(atual)
                atual = Linha()
                atual.largura = tamanho.width
            } else {
                atual.largura = nova
            }
            atual.indices.append(indice)
            atual.altura = max(atual.altura, tamanho.height)
        }
        if !atual.indices.isEmpty { linhas.append(atual) }
        return linhas
    }
}
