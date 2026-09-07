import SwiftUI

struct NetworkToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        HStack(spacing: 12) {
            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.proxyRunning ? theme.current.success : theme.current.danger)
                    .frame(width: 6, height: 6)
                Text(appState.proxyRunning ? "Proxy 8082 ativo" : "Proxy 8082 inativo")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.current.textSecondary)
            }
            .frame(width: 140, alignment: .leading)
            
            // Filter
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(theme.current.textTertiary)
                @Bindable var state = appState
                TextField("Filtrar host, path ou status", text: $state.httpFilterText)
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
            
            // Buttons
            HStack(spacing: 8) {
                FluidPillButton(text: "Configurar proxy", style: .secondary) {
                    // Action for proxy configuration
                }
                FluidPillButton(text: "Exportar HAR", style: .secondary) {
                    // Action for exporting HAR
                }
                FluidPillButton(text: "Limpar tráfego", style: .destructiveText) {
                    appState.clearHTTPTraffic()
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
