import SwiftUI

/// Coluna do workspace: Page Objects, Rede HTTP ou Analytics, conforme a área
/// escolhida na barra lateral. Trocar de área é um crossfade de 180 ms.
///
/// A barra de abas que ficava aqui saiu: as áreas estão na barra lateral, com
/// contagem, e o seletor de estratégia foi para a barra acessória de Page
/// Objects, que é a única área que gera código.
struct WorkspacePane: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ZStack {
            switch appState.workspaceTab {
            case .pageObjects:
                PageObjectsView().transition(.opacity)
            case .network:
                HTTPInspectorView().transition(.opacity)
            case .analytics:
                AnalyticsInspectorView().transition(.opacity)
            }
        }
        .animation(Motion.crossfade, value: appState.workspaceTab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.bgContent)
    }
}

/// Mantido com o nome antigo para os testes e snapshots que desenham a coluna.
typealias WorkspaceColumn = WorkspacePane
