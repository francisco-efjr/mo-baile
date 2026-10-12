import SwiftUI

/// Inspector do Relatório: o card do Figma da validação escolhida.
///
/// É a coluna "Spec (Figma)" do board: o print do card ao lado do resultado,
/// para conferir o que a spec pede sem sair do app. Os dados do card vêm da
/// linha que o motor devolveu; a imagem é lida do disco só para exibição.
struct ReportCardInspector: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Card do Figma")
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle().fill(theme.separator).frame(height: 1)

            if let result = appState.selectedReportResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        KeyValueGrid(rows: linhas(result))
                            .padding(.top, 4)
                        ReportPrintImage(path: result.printPath, printsDir: appState.reportSpec?.printsDir)
                            .padding(.horizontal, 12)
                        if let note = result.note, !note.isEmpty {
                            Text("Obs. da spec: \(note)")
                                .font(DSFont.callout)
                                .foregroundStyle(theme.labelSecondary)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                        }
                    }
                    .padding(.bottom, 12)
                }
            } else {
                EmptyState(
                    icon: "photo.on.rectangle",
                    text: appState.reportSpec == nil
                        ? "Abra uma spec para ver os cards."
                        : "Selecione uma validação para ver o card da spec.",
                    compact: true
                )
            }
        }
    }

    private func linhas(_ result: ReportResult) -> [(key: String, value: String)] {
        var linhas: [(key: String, value: String)] = [
            ("seção", result.section),
            ("card", result.cardTitle),
            ("evento", result.event),
        ]
        if let fluxo = result.flowLabel { linhas.append(("fluxo", fluxo)) }
        if !result.variation.isEmpty { linhas.append(("variação", result.variation)) }
        if let print = result.printPath { linhas.append(("print", (print as NSString).lastPathComponent)) }
        return linhas
    }
}
