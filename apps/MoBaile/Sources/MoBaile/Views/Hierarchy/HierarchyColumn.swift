import SwiftUI

struct HierarchyColumn: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("HIERARQUIA DE ACESSIBILIDADE")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundColor(themeManager.current.textLabel ?? Color.gray)
                    .tracking(0.09) // letter-spacing .09em
                
                Spacer()
                
                Text("⌥2")
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.current.textSecondary ?? Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            SearchField()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            
            HierarchyTreeView()
            
            Divider().background(themeManager.current.border ?? Color.gray)
            
            AttributesPanel()
        }
        .frame(minWidth: 240, idealWidth: 296, maxWidth: 460)
        .background(themeManager.current.bgPanel ?? Color.clear)
    }
}
