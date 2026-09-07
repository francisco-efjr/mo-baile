import SwiftUI

struct CorrelationCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        let theme = themeManager.current
        
        VStack(alignment: .leading, spacing: 12) {
            Text("CORRELAÇÃO")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.09)
                .foregroundColor(theme.textLabel)
            
            VStack(alignment: .leading, spacing: 8) {
                // Safely unwrap and format the last step if possible. Using String(describing:) as fallback.
                let stepDesc = appState.steps.last.map { String(describing: $0) } ?? "Nenhuma ação recente"
                Text(stepDesc)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.accent)
                
                HStack(spacing: 16) {
                    Text("\(appState.httpRequests.count) requisições")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                    
                    Text("\(appState.analyticsEvents.count) eventos de analytics")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                }
            }
            
            FluidPillButton(
                text: "Gerar asserção de contrato",
                icon: "doc.text.magnifyingglass",
                style: .secondary
            ) {
                // Action
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(theme.bgPanel)
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}
