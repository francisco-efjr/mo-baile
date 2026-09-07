import SwiftUI

struct AnalyticsToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.analyticsListenerActive ? theme.current.success : theme.current.danger)
                    .frame(width: 6, height: 6)
                Text(appState.analyticsListenerActive ? "FA Listener ativo" : "FA Listener inativo")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.current.textSecondary)
            }
            .frame(width: 140, alignment: .leading)
            
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(theme.current.textTertiary)
                @Bindable var state = appState
                TextField("Filtrar eventos e tags", text: $state.analyticsFilterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(theme.current.textPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(theme.current.bgControl)
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(theme.current.borderSubtle, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            
            HStack(spacing: 8) {
                FluidPillButton(text: "Copiar TSV", style: .secondary) {
                    // Action for copying TSV
                }
                FluidPillButton(text: "Exportar JSON", style: .secondary) {
                    // Action for exporting JSON
                }
                FluidPillButton(text: "Limpar", style: .destructiveText) {
                    appState.clearAnalyticsEvents()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.current.bgPanel)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(theme.current.border),
            alignment: .bottom
        )
    }
}
