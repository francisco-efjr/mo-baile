import SwiftUI

/// Coluna direita: codigo gerado, trafego HTTP e analytics.
///
/// As abas de rede e analytics mostravam `Text("Network Inspector")` enquanto
/// as telas correspondentes ja existiam prontas no projeto. Aqui elas entram.
struct WorkspaceColumn: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabBar()

            Divider().background(themeManager.current.border)

            Group {
                switch appState.workspaceTab {
                case .pageObjects:
                    DualEditorPane()
                case .network:
                    HTTPInspectorView()
                case .analytics:
                    AnalyticsInspectorView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: Bindable(appState).showingStructure) {
                StructureDialog { appState.showingStructure = false }
                    .environment(appState)
                    .environment(themeManager)
                    .frame(minWidth: 640, minHeight: 420)
            }
            .background(themeManager.current.bgWindow)
        }
    }
}
