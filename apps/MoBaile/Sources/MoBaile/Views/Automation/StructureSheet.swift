import AppKit
import SwiftUI

/// Sheet "Estrutura do fluxo": a tabela ordenada dos passos gravados.
struct StructureSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @State private var selecao: Set<AutomationStep.ID> = []

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 0) {
            Text("Estrutura do fluxo")
                .font(DSFont.headline)
                .padding(.bottom, 4)
            Text("\(chave) · \(appState.steps.count == 1 ? "1 passo" : "\(appState.steps.count) passos").")
                .font(DSFont.body)
                .foregroundStyle(theme.labelSecondary)
                .padding(.bottom, 12)

            Table(linhas, selection: $selecao) {
                TableColumn("#") { linha in
                    Text("\(linha.numero)")
                        .font(DSFont.callout.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(34)
                TableColumn("Ação") { linha in
                    Text(linha.passo.actionType).font(DSFont.mono(11))
                }
                .width(min: 70, ideal: 90)
                TableColumn("Elemento") { linha in
                    Text(linha.passo.displayElement).lineLimit(1)
                }
                .width(min: 100, ideal: 160)
                TableColumn("Estratégia") { linha in
                    Text(linha.passo.strategy.displayName)
                }
                .width(min: 60, ideal: 80)
                TableColumn("Coordenadas/Seletor") { linha in
                    Text(linha.passo.selectorDescription)
                        .font(DSFont.mono(11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .alternatingRowBackgrounds()
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.separator, lineWidth: 0.5))

            HStack(spacing: 12) {
                Button("Copiar Resumo") {
                    let resumo = appState.steps.enumerated()
                        .map { "\($0.offset + 1). \($0.element.actionType) \($0.element.displayElement)" }
                        .joined(separator: "\n")
                    Exporters.copy(resumo)
                    appState.statusMessage = "Resumo do fluxo copiado"
                }
                Spacer()
                Button("Rodar…") {
                    dismiss()
                    RunAutomationButton.run(appState: appState, session: session)
                }
                .frame(minWidth: 84)
                .disabled(!RunAutomationButton.podeRodar(appState))
                Button("Concluir") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .frame(minWidth: 84)
            }
            .padding(.top, 20)
        }
        .padding(DesignMetrics.Spacing.windowMargin)
        .frame(width: 680)
    }

    private var chave: String {
        session.engineInfo?.pageObjectsKey ?? "fluxo"
    }

    private struct Linha: Identifiable {
        let numero: Int
        let passo: AutomationStep
        var id: UUID { passo.id }
    }

    private var linhas: [Linha] {
        appState.steps.enumerated().map { Linha(numero: $0.offset + 1, passo: $0.element) }
    }
}
