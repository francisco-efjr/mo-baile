import SwiftUI

struct SearchField: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        @Bindable var state = appState
        
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(themeManager.current.textSecondary ?? Color.secondary)
            
            TextField("Buscar texto, ID ou XPath", text: $state.hierarchySearchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(themeManager.current.textPrimary ?? Color.primary)
            
            Text("⌘F")
                .font(.system(size: 9, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(themeManager.current.bgControlTrack ?? Color.gray.opacity(0.3))
                .cornerRadius(4)
                .foregroundColor(themeManager.current.textSecondary ?? Color.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(themeManager.current.bgControl ?? Color.clear)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(themeManager.current.border ?? Color.gray, lineWidth: 1)
        )
    }
}
