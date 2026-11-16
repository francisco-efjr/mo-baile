import SwiftUI

/// Revisão do rascunho que o OCR gerou a partir dos prints do Figma.
///
/// O OCR pode trocar uma letra ou pular uma linha sem aviso, então o rascunho
/// nunca vira a spec da aba sozinho: a sheet mostra o que o leitor corrigiu ou
/// achou ambíguo, card a card, e a pessoa escolhe usar, editar ou fechar.
struct ReportImportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = themeManager.current
        if let importado = appState.reportImport {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rascunho da spec gerado")
                        .font(DSFont.title3)
                        .foregroundStyle(theme.labelPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(resumo(importado))
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let erro = importado.specError {
                    InlineError(title: "O rascunho ainda não valida.", text: erro)
                }

                List(importado.review) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(card.event.isEmpty ? "(evento não lido)" : card.event)
                                .font(DSFont.mono(11.5, weight: .medium))
                                .foregroundStyle(card.event.isEmpty ? theme.destructive : theme.accentText)
                            Spacer(minLength: 6)
                            Text(card.print)
                                .font(DSFont.subheadline)
                                .foregroundStyle(theme.labelTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if card.doubts.isEmpty {
                            StatusIndicator(status: .ok, label: "nada a conferir", mono: false)
                        } else {
                            ForEach(card.doubts, id: \.self) { duvida in
                                Label {
                                    Text(duvida).textSelection(.enabled)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
                                }
                                .font(DSFont.callout)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 220)

                HStack(spacing: 8) {
                    Button("Mostrar no Finder") { Exporters.revealInFinder(importado.specPath) }
                    Button("Abrir no Editor") {
                        let caminho = importado.specPath
                        Task {
                            await session.openReportSpecEditor(path: caminho)
                            // Só fecha se abriu: num JSON quebrado o erro aparece aqui.
                            if appState.reportSpecEditor != nil { dismiss() }
                        }
                    }
                    .disabled(appState.reportOperation != nil)
                    .help("Abre o rascunho no editor do app para corrigir o que o OCR leu")
                    if let checklist = importado.checklistPath {
                        Menu("Checklist") {
                            Button("Exportar em HTML (Design System)") {
                                Task { await session.exportReportChecklist(at: URL(fileURLWithPath: checklist)) }
                            }
                            Button("Abrir o Markdown") { Exporters.openFile(checklist) }
                            Button("Mostrar no Finder") { Exporters.revealInFinder(checklist) }
                        }
                        .fixedSize()
                        .disabled(appState.reportOperation != nil)
                        .help("O checklist de conferência (.checklist.md) gerado com o rascunho, e o HTML no padrão do design system")
                    }
                    Spacer()
                    Button("Fechar", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Usar Esta Spec") {
                        Task { await session.useImportedSpec() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(importado.spec == nil)
                    .help(importado.spec == nil
                          ? "Corrija o rascunho no editor; ele ainda não é uma spec válida"
                          : "Abre o rascunho como a spec da aba Relatório")
                }
            }
            .padding(DesignMetrics.Spacing.windowMargin)
            .frame(width: 640, height: 520)
        }
    }

    private func resumo(_ importado: ReportImport) -> String {
        let prints = importado.review.count == 1 ? "1 print lido" : "\(importado.review.count) prints lidos"
        let pontos = importado.doubtsTotal == 1 ? "1 ponto para conferir" : "\(importado.doubtsTotal) pontos para conferir"
        let nome = (importado.specPath as NSString).lastPathComponent
        return "\(prints) · \(pontos). Gravado em \(nome), com o checklist de conferência ao lado, sem tocar em spec existente. Confira antes de auditar: o OCR pode trocar uma letra ou pular uma linha."
    }
}
