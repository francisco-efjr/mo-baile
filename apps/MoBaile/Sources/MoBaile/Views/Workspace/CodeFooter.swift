import SwiftUI

struct CodeFooter: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        HStack {
            if let step = appState.steps.last {
                Text("passo \(appState.stepCount) · \(step.actionType) · \(step.elementName) · \(step.strategy)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(themeManager.current.textPrimary)
            } else {
                Text("nenhum passo")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(themeManager.current.textSecondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(themeManager.current.success)
                    .frame(width: 6, height: 6)
                
                Text("código sincronizado")
                    .font(.system(size: 10.5))
                    .foregroundColor(themeManager.current.success)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(themeManager.current.bgSubtle)
    }
}
