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
        let theme = themeManager.current
        if appState.reportFilter == .outOfSpec {
            if let extra = appState.selectedReportExtra {
                ReportExtraDetail(extra: extra)
            } else {
                EmptyState(icon: "info.circle", text: "Selecione um evento para ver os detalhes.", compact: true)
            }
        } else if let result = appState.selectedReportResult {
            HStack(spacing: 0) {
                ReportChecksPanel(result: result)
                    .frame(maxWidth: .infinity)
                Rectangle().fill(theme.separator).frame(width: 1)
                ReportEvidencePanel(result: result)
                    .frame(maxWidth: .infinity)
            }
        } else {
            EmptyState(icon: "info.circle", text: "Selecione uma validação para ver os parâmetros.", compact: true)
        }
    }
}

/// Campo, obtido e esperado, com ✓ e ✗ como ícone e texto, nunca só cor.
private struct ReportChecksPanel: View {
    @Environment(ThemeManager.self) private var themeManager
    let result: ReportResult

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            DetailHeader(
                title: "Validação",
                copyLabel: "Copiar divergências",
                onCopy: { Exporters.copy(result.divergences.isEmpty ? "Sem divergências" : result.divergences) }
            ) {
                StatusIndicator(status: result.status.daemonState, label: result.status.displayName, mono: false)
            } tabs: {
                EmptyView()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(cabecalho)
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)

                    if result.status == .missing {
                        InlineError(
                            title: "Não disparado no log.",
                            text: "Nenhum \(result.event) com esse fluxo, tela e detail entre os eventos auditados. O esperado está no bloco ao lado."
                        )
                        .padding(.horizontal, 10)
                    } else {
                        grade
                    }

                    ForEach(observacoes, id: \.self) { texto in
                        Label {
                            Text(texto).textSelection(.enabled)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
                        }
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelPrimary)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    private var cabecalho: String {
        var partes = [result.section, result.cardTitle]
        if let flowLabel = result.flowLabel { partes.append(flowLabel) }
        if result.status != .missing, let hora = result.matched?.time {
            partes.append("log \(hora) · \(result.occurrences) disparo(s)")
        }
        return partes.joined(separator: " · ")
    }

    private var grade: some View {
        let theme = themeManager.current
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                Text("")
                Text("Parâmetro")
                Text("Obtido")
                Text("Esperado")
            }
            .font(DSFont.subheadlineSemibold)
            .foregroundStyle(theme.labelSecondary)
            .padding(.vertical, 3)
            Divider().overlay(theme.separator).gridCellUnsizedAxes(.horizontal)
            ForEach(result.checks) { check in
                GridRow {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(check.ok ? theme.success : theme.destructive)
                        .accessibilityHidden(true)
                    Text(check.field)
                        .foregroundStyle(theme.accentText)
                    Text(check.obtained ?? "ausente")
                        .foregroundStyle(check.obtained == nil ? theme.labelTertiary : theme.labelPrimary)
                        .italic(check.obtained == nil)
                        .lineLimit(3)
                        .help(check.obtained ?? "O parâmetro não veio no disparo")
                    Text(check.expected)
                        .foregroundStyle(check.ok ? theme.labelSecondary : theme.labelPrimary)
                        .lineLimit(3)
                        .help(check.expected)
                }
                .font(DSFont.mono(11))
                .textSelection(.enabled)
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(check.field): \(check.ok ? "confere" : "diverge"), obtido \(check.obtained ?? "ausente"), esperado \(check.expected)"
                )
                Divider().overlay(theme.separator).gridCellUnsizedAxes(.horizontal)
            }
        }
        .padding(.horizontal, 12)
    }

    private var observacoes: [String] {
        var linhas: [String] = []
        if let gaScreen = result.gaScreen {
            linhas.append("O ga_screen do disparo é \(gaScreen), diferente do screen_name.")
        }
        if result.olderDivergent > 0 {
            linhas.append("\(result.olderDivergent) disparo(s) anterior(es) com outra divergência: "
                          + result.olderDivergences.joined(separator: ", "))
        }
        if let note = result.note, !note.isEmpty {
            linhas.append("Obs. da spec: \(note)")
        }
        return linhas
    }
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
                        KeyValueGrid(rows: matched.params.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
                    } else {
                        EmptyState(icon: "antenna.radiowaves.left.and.right.slash",
                                   text: "Nenhum disparo para esta variação.", compact: true)
                    }
                }
            }
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
