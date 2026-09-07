import SwiftUI

struct WorkspaceTabBar: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        HStack {
            // Segments placeholder
            Text("Tabs: Page Objects | Rede HTTP | Analytics")
                .font(.caption)
            
            Spacer()
            
            if appState.workspaceTab == .pageObjects {
                Text("Strategy: ID | XPath | Coords")
                    .font(.caption)
            }
            
            Spacer()
            
            // Buttons placeholder
            HStack(spacing: 8) {
                Button("Estrutura · N") { }
                Button("Split") { }
                Button("▶ Rodar") { }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(themeManager.current.bgSubtle ?? Color.clear)
    }
}
