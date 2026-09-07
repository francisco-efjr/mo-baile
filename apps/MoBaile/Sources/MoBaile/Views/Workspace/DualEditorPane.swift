import SwiftUI

struct DualEditorPane: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        @Bindable var state = appState
        
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left Editor
                VStack(spacing: 0) {
                    editorHeader(title: "pages/feature.py", color: themeManager.current.fileTitleActions ?? Color.blue)
                    CodeEditorContainer(text: $state.actionsCode)
                }
                
                Divider().background(themeManager.current.border ?? Color.gray)
                
                // Right Editor
                VStack(spacing: 0) {
                    editorHeader(title: "locators/feature.py", color: themeManager.current.fileTitleLocators ?? Color.orange)
                    CodeEditorContainer(text: $state.locatorsCode)
                }
            }
            
            Divider().background(themeManager.current.border ?? Color.gray)
            
            CodeFooter()
        }
    }
    
    @ViewBuilder
    func editorHeader(title: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(color)
            
            Spacer()
            
            HStack(spacing: 8) {
                Button("Copiar") { }
                Button("Salvar") { }
                Button("Limpar") { }
            }
            .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundColor(themeManager.current.textSecondary ?? Color.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(themeManager.current.bgSubtle ?? Color.clear)
    }
}

struct CodeEditorContainer: View {
    @Binding var text: String
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        HStack(spacing: 0) {
            CodeGutter()
            CodeEditorView(text: $text)
        }
    }
}
