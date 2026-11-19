import AppKit
import SwiftUI

enum ReportDetailTab: String, CaseIterable, Identifiable {
    case block = "Bloco"
    case event = "Disparo"
    var id: String { rawValue }
}

/// Detalhe da linha escolhida: à esquerda a validação parâmetro a parâmetro;
/// à direita o bloco (o mesmo do board) e o disparo avaliado. O print do card
/// fica no inspector, como a coluna "Spec (Figma)" do board.
struct ReportDetailPane: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        if appState.reportFilter == .outOfSpec {
            if let extra = appState.selectedReportExtra {
                ReportExtraDetail(extra: extra)
            } else {
                EmptyState(icon: "info.circle", text: "Selecione um evento para ver os detalhes.", compact: true)
            }
        } else if let result = appState.selectedReportResult {
            AdaptivePair(labels: ("Validação", "Bloco e Disparo"), minSideBySide: 640) {
                ReportChecksPanel(result: result)
            } second: {
                ReportEvidencePanel(result: result)
            }
        } else {
            EmptyState(icon: "info.circle", text: "Selecione uma validação para ver os parâmetros.", compact: true)
        }
    }
}

/// Campo, obtido e esperado, com ✓ e ✗ como ícone e texto, nunca só cor.
///
/// Com itens (3.27.0), as conferências vêm agrupadas: os parâmetros do evento
/// e um grupo por item, que abre sozinho quando tem divergência. O recorte
/// "Divergentes" esconde o que confere (RE-01).
private struct ReportChecksPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let result: ReportResult

    private enum Recorte: Hashable { case todos, divergentes }
    @State private var recorte: Recorte = .todos
    @State private var abertos: Set<String> = []
    @State private var largura: CGFloat = 0

    /// Abaixo disso, obtido e esperado vão um embaixo do outro.
    private static let larguraDeTresColunas: CGFloat = 480
    static let larguraDoParametro: CGFloat = 136

    var body: some View {
        let theme = themeManager.current
        let grupos = result.checkGroups
        VStack(spacing: 0) {
            DetailHeader(
                title: "Validação",
                copyLabel: "Copiar divergências",
                onCopy: { Exporters.copy(result.divergences.isEmpty ? "Sem divergências" : result.divergences) }
            ) {
                StatusIndicator(status: result.status.daemonState, label: result.status.displayName, mono: false)
            } tabs: {
                if ReportBug.canCreate(for: result) {
                    Button {
                        appState.statusMessage = ReportBug.copy(result)
                    } label: {
                        Label("Copiar Bug", systemImage: "ladybug")
                    }
                    .controlSize(.mini)
                    .help("Copia o bug no modelo de bug, com a validação e o print do Figma, para colar no Jira ou no Azure")
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                    Text(cabecalho)
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .help(cabecalho)
                        .padding(.horizontal, DesignMetrics.Spacing.s5)
                        .padding(.top, DesignMetrics.Spacing.s5 - 2)

                    if result.status == .missing {
                        InlineError(
                            title: "Não disparado no log.",
                            text: "Nenhum \(result.event) com esse fluxo, tela e detail entre os eventos auditados. O esperado está no bloco ao lado."
                        )
                        .padding(.horizontal, DesignMetrics.Spacing.s5 - 2)
                    } else {
                        if mostraRecorte(grupos) { barraDoRecorte(grupos) }
                        conferencias(grupos)
                    }

                    ForEach(observacoes, id: \.texto) { obs in
                        Label {
                            Text(obs.texto).textSelection(.enabled).help(obs.completo ?? "")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
                        }
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelPrimary)
                        .padding(.horizontal, DesignMetrics.Spacing.s5)
                    }
                }
                .padding(.bottom, DesignMetrics.Spacing.s5 - 2)
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { largura = geo.size.width }
                        .onChange(of: geo.size.width) { _, nova in largura = nova }
                }
            }
        }
        .onAppear { preparar(grupos) }
        .onChange(of: result.id) { _, _ in preparar(result.checkGroups) }
    }

    private var estreito: Bool { largura > 0 && largura < Self.larguraDeTresColunas }

    /// Muitas linhas com divergência abrem no recorte "Divergentes"; os itens
    /// com divergência abrem, os que conferem ficam fechados.
    private func preparar(_ grupos: [ReportCheckGroup]) {
        recorte = (result.status == .error && result.checks.count > 12) ? .divergentes : .todos
        abertos = Set(grupos.filter { $0.item != nil && $0.divergent > 0 }.map(\.id))
    }

    private func mostraRecorte(_ grupos: [ReportCheckGroup]) -> Bool {
        result.checks.count > 6 || grupos.contains { $0.item != nil }
    }

    private func barraDoRecorte(_ grupos: [ReportCheckGroup]) -> some View {
        let theme = themeManager.current
        let divergentes = result.checks.filter { $0.exported && !$0.ok }.count
        let itens = grupos.filter { $0.item != nil }
        return HStack(spacing: DesignMetrics.Spacing.s4) {
            Picker("Mostrar", selection: $recorte) {
                Text("Todos \(result.checks.count)").tag(Recorte.todos)
                Text("Divergentes \(divergentes)").tag(Recorte.divergentes)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Mostrar conferências")
            Spacer(minLength: DesignMetrics.Spacing.s2)
            if !itens.isEmpty {
                let todosAbertos = itens.allSatisfy { abertos.contains($0.id) }
                Button(todosAbertos ? "Recolher Itens" : "Expandir Itens") {
                    abertos = todosAbertos ? [] : Set(itens.map(\.id))
                }
                .buttonStyle(PlainTextButtonStyle(theme: theme))
                .controlSize(.small)
            }
        }
        .padding(.horizontal, DesignMetrics.Spacing.s5)
    }

    @ViewBuilder
    private func conferencias(_ grupos: [ReportCheckGroup]) -> some View {
        let visiveis = grupos.compactMap(filtrar)
        if visiveis.isEmpty {
            EmptyState(icon: "checkmark.seal", text: "Nenhuma divergência nesta variação.",
                       actionLabel: "Mostrar Todos", action: { recorte = .todos }, compact: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignMetrics.Spacing.s5)
        } else {
            ForEach(visiveis) { grupo in
                if grupo.item == nil {
                    tabela(grupo)
                } else {
                    DisclosureGroup(isExpanded: aberto(grupo.id)) {
                        tabela(grupo)
                            .padding(.top, DesignMetrics.Spacing.s2)
                    } label: {
                        rotulo(grupo, original: grupos.first { $0.id == grupo.id } ?? grupo)
                    }
                    .padding(.horizontal, DesignMetrics.Spacing.s5)
                }
            }
        }
    }

    /// No recorte "Divergentes", o grupo só com o que diverge (ou nada).
    private func filtrar(_ grupo: ReportCheckGroup) -> ReportCheckGroup? {
        guard recorte == .divergentes else { return grupo }
        let falhas = grupo.checks.filter { $0.exported && !$0.ok }
        guard !falhas.isEmpty else { return nil }
        return ReportCheckGroup(id: grupo.id, item: grupo.item, checks: falhas, identification: grupo.identification)
    }

    private func aberto(_ id: String) -> Binding<Bool> {
        Binding(
            get: { abertos.contains(id) },
            set: { if $0 { abertos.insert(id) } else { abertos.remove(id) } }
        )
    }

    private func rotulo(_ grupo: ReportCheckGroup, original: ReportCheckGroup) -> some View {
        let theme = themeManager.current
        let total = original.checks.count
        let divergentes = original.divergent
        let resumo = divergentes > 0 ? "\(divergentes) de \(total) divergem" : "\(total) OK"
        return HStack(spacing: DesignMetrics.Spacing.s3) {
            Image(systemName: divergentes > 0 ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(divergentes > 0 ? theme.destructive : theme.success)
                .accessibilityHidden(true)
            Text("Item \((grupo.item ?? 0) + 1)")
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.labelPrimary)
            if let identificacao = grupo.identification {
                Text(identificacao)
                    .font(DSFont.mono(11))
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(identificacao)
            }
            Spacer(minLength: DesignMetrics.Spacing.s2)
            Text(resumo)
                .font(DSFont.subheadline.monospacedDigit())
                .foregroundStyle(theme.labelSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Item \((grupo.item ?? 0) + 1)\(grupo.identification.map { ", \($0)" } ?? ""), \(resumo)")
    }

    /// Colunas fixas e iguais em todos os grupos: Parâmetro com 136 pt, obtido
    /// e esperado com o resto. Estreito, obtido e esperado empilham.
    private func tabela(_ grupo: ReportCheckGroup) -> some View {
        let theme = themeManager.current
        return VStack(alignment: .leading, spacing: 0) {
            if !estreito {
                HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s5 - 2) {
                    Color.clear.frame(width: 14, height: 1)
                    Text(grupo.item == nil ? "Parâmetro" : "Campo")
                        .frame(width: Self.larguraDoParametro, alignment: .leading)
                    Text("Obtido").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Esperado").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.labelSecondary)
                .padding(.vertical, 3)
                Divider().overlay(theme.separator)
            }
            ForEach(Array(grupo.checks.enumerated()), id: \.offset) { _, check in
                ReportCheckRow(check: check, key: grupo.shortKey(check), item: grupo.item, narrow: estreito)
                Divider().overlay(theme.separator)
            }
        }
        .padding(.horizontal, DesignMetrics.Spacing.s5)
    }

    private var cabecalho: String {
        var partes = [result.section, result.cardTitle]
        if let flowLabel = result.flowLabel { partes.append(flowLabel) }
        if result.status != .missing, let hora = result.matched?.time {
            partes.append("log \(hora) · \(result.occurrences) disparo(s)")
        }
        return partes.joined(separator: " · ")
    }

    /// Observações; a de disparos anteriores mostra até 3 divergências, com o
    /// resto no tooltip (RE-14).
    private var observacoes: [(texto: String, completo: String?)] {
        var linhas: [(texto: String, completo: String?)] = []
        if let gaScreen = result.gaScreen {
            linhas.append(("O ga_screen do disparo é \(gaScreen), diferente do screen_name.", nil))
        }
        if result.olderDivergent > 0 {
            let todas = result.olderDivergences
            var texto = "\(result.olderDivergent) disparo(s) anterior(es) com outra divergência: "
                + todas.prefix(3).joined(separator: ", ")
            if todas.count > 3 { texto += " e mais \(todas.count - 3)" }
            linhas.append((texto, todas.count > 3 ? todas.joined(separator: "\n") : nil))
        }
        if let note = result.note, !note.isEmpty {
            linhas.append(("Obs. da spec: \(note)", nil))
        }
        return linhas
    }
}

/// Uma conferência: ícone, campo, obtido e esperado. Com chave a|b, o obtido
/// mostra o valor e, embaixo, por qual das chaves ele veio.
private struct ReportCheckRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let check: ReportCheck
    let key: String
    let item: Int?
    let narrow: Bool

    var body: some View {
        let theme = themeManager.current
        Group {
            if narrow {
                HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
                    icone
                    VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                        campo
                        obtido
                        (Text("esperado ").foregroundColor(theme.labelTertiary) + Text(check.expected))
                            .foregroundStyle(check.ok ? theme.labelSecondary : theme.labelPrimary)
                            .lineLimit(4)
                            .help(check.expected)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s5 - 2) {
                    icone
                    campo.frame(width: ReportChecksPanelMetrics.parametro, alignment: .leading)
                    obtido.frame(maxWidth: .infinity, alignment: .leading)
                    Text(check.expected)
                        .foregroundStyle(check.ok ? theme.labelSecondary : theme.labelPrimary)
                        .lineLimit(4)
                        .help(check.expected)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(DSFont.mono(11))
        .textSelection(.enabled)
        .padding(.vertical, DesignMetrics.Spacing.s2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rotuloFalado)
    }

    private var icone: some View {
        let theme = themeManager.current
        return Image(systemName: !check.exported ? "minus.circle" : check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(!check.exported ? theme.labelTertiary : check.ok ? theme.success : theme.destructive)
            .frame(width: 14)
            .accessibilityHidden(true)
    }

    private var campo: some View {
        Text(key)
            .foregroundStyle(themeManager.current.accentText)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(key.contains("|") ? "\(check.field): basta uma das chaves (\(ReportItemField.spoken(key)))" : check.field)
    }

    @ViewBuilder
    private var obtido: some View {
        let theme = themeManager.current
        if !check.exported {
            Text("não exportado")
                .foregroundStyle(theme.labelTertiary)
                .italic()
                .help("O export do Analytics (TSV) não traz este parâmetro")
        } else if let via = ReportItemField.viaAlternative(key: key, obtained: check.obtained) {
            VStack(alignment: .leading, spacing: 0) {
                Text(via.value)
                    .foregroundStyle(theme.labelPrimary)
                    .lineLimit(4)
                Text("via \(via.via)")
                    .font(DSFont.footnote)
                    .foregroundStyle(theme.labelTertiary)
            }
            .help(via.value)
        } else {
            Text(check.obtained ?? "ausente")
                .foregroundStyle(check.obtained == nil ? theme.labelTertiary : theme.labelPrimary)
                .italic(check.obtained == nil)
                .lineLimit(4)
                .help(check.obtained ?? "O parâmetro não veio no disparo")
        }
    }

    private var rotuloFalado: String {
        let onde = item.map { "item \($0 + 1), " } ?? ""
        let nome = ReportItemField.spoken(key)
        guard check.exported else { return "\(onde)\(nome): não exportado no TSV, esperado \(check.expected)" }
        return "\(onde)\(nome): \(check.ok ? "confere" : "diverge"), obtido \(check.obtained ?? "ausente"), esperado \(check.expected)"
    }
}

private enum ReportChecksPanelMetrics {
    /// Cabe `item_id|item_name` em SF Mono 11 (~112 pt) com folga.
    static let parametro: CGFloat = 136
}

/// Bloco | Disparo.
private struct ReportEvidencePanel: View {
    let result: ReportResult

    @State private var aba: ReportDetailTab = .block

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(
                title: aba.rawValue,
                copyLabel: "Copiar \(aba.rawValue.lowercased())",
                onCopy: { Exporters.copy(conteudoCopiavel) }
            ) {
                EmptyView()
            } tabs: {
                Picker("Conteúdo", selection: $aba) {
                    ForEach(ReportDetailTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            ScrollView {
                switch aba {
                case .block:
                    CodeBlock(text: result.block)
                case .event:
                    if let matched = result.matched, !matched.params.isEmpty {
                        ReportMatchedParams(result: result, matched: matched)
                    } else {
                        EmptyState(icon: "antenna.radiowaves.left.and.right.slash",
                                   text: "Nenhum disparo para esta variação.", compact: true)
                    }
                }
            }
            .crossfade(on: aba)
        }
    }

    private var conteudoCopiavel: String {
        switch aba {
        case .block: return result.block
        case .event:
            return (result.matched?.params ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
        }
    }
}

/// Parâmetros do disparo avaliado. `items` vira um grupo por item, com
/// item_id, item_name, price e quantity primeiro, em vez do JSON numa linha.
private struct ReportMatchedParams: View {
    @Environment(ThemeManager.self) private var themeManager
    let result: ReportResult
    let matched: ReportMatchedEvent

    @State private var abertos: Set<Int> = [0]

    var body: some View {
        let theme = themeManager.current
        let itens = result.matchedItems
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            KeyValueGrid(rows: matched.params
                .filter { itens.isEmpty || $0.key != "items" }
                .sorted { $0.key < $1.key }
                .map { ($0.key, $0.value) })
            if !itens.isEmpty {
                Text(itens.count == 1 ? "items · 1 item" : "items · \(itens.count) itens")
                    .font(DSFont.subheadlineSemibold)
                    .foregroundStyle(theme.labelSecondary)
                    .padding(.horizontal, DesignMetrics.Spacing.s5)
                ForEach(Array(itens.enumerated()), id: \.offset) { posicao, item in
                    DisclosureGroup(isExpanded: Binding(
                        get: { abertos.contains(posicao) },
                        set: { if $0 { abertos.insert(posicao) } else { abertos.remove(posicao) } }
                    )) {
                        KeyValueGrid(rows: ReportMatchedEvent.itemRows(item))
                    } label: {
                        HStack(spacing: DesignMetrics.Spacing.s3) {
                            Text("Item \(posicao + 1)")
                                .font(DSFont.subheadlineSemibold)
                                .foregroundStyle(theme.labelPrimary)
                            if let nome = item["item_id"] ?? item["item_name"] {
                                Text(nome)
                                    .font(DSFont.mono(11))
                                    .foregroundStyle(theme.labelSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.horizontal, DesignMetrics.Spacing.s5)
                }
            }
        }
        .padding(.bottom, DesignMetrics.Spacing.s5)
    }
}

/// Print do card do Figma. Lido do disco pela interface: é só exibição.
struct ReportPrintImage: View {
    @Environment(ThemeManager.self) private var themeManager
    let path: String?
    let printsDir: String?

    var body: some View {
        if let path, let imagem = NSImage(contentsOfFile: path) {
            Image(nsImage: imagem)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
                .frame(maxWidth: 420)
                .accessibilityLabel("Print do card: \((path as NSString).lastPathComponent)")
                .contextMenu {
                    Button("Mostrar no Finder") { Exporters.revealInFinder(path) }
                }
        } else {
            // Aviso em linha, e não estado vazio de painel: o inspector é
            // estreito e o resto do card continua útil sem a imagem.
            Label {
                Text(printsDir == nil
                     ? "Sem print: a spec não aponta uma pasta de prints (prints_dir)."
                     : "Sem print: este card não tem imagem na pasta da spec.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "photo").foregroundStyle(themeManager.current.labelTertiary)
            }
            .font(DSFont.callout)
            .foregroundStyle(themeManager.current.labelSecondary)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Evento fora da spec ou alerta: o que é e o que conferir.
private struct ReportExtraDetail: View {
    @Environment(ThemeManager.self) private var themeManager
    let extra: ReportExtra

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            DetailHeader(
                title: extra.isAlert ? "Alerta" : "Fora da Spec",
                copyLabel: "Copiar evento",
                onCopy: { Exporters.copy(linhas.map { "\($0.key): \($0.value)" }.joined(separator: "\n")) }
            ) {
                CountBadge(value: extra.count)
            } tabs: {
                EmptyView()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(explicacao)
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    KeyValueGrid(rows: linhas)
                }
            }
        }
    }

    private var explicacao: String {
        extra.isAlert
            ? "\(extra.event) disparou numa tela ou fluxo da spec. Erro do app durante o teste costuma esconder outros eventos."
            : "Evento dos fluxos da spec que nenhum card cobre. Confira se falta um card no Figma ou se o app dispara a mais."
    }

    private var linhas: [(key: String, value: String)] {
        [
            ("evento", extra.event),
            ("tela", extra.screenText),
            ("flow_name", extra.flowName ?? ""),
            ("component", extra.componentText),
            ("detail", extra.detailText),
            ("disparos", "\(extra.count)"),
        ].filter { !$0.1.isEmpty }
    }
}
