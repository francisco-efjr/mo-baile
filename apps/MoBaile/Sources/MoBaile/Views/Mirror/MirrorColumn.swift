import SwiftUI

struct MirrorColumn: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        let theme = themeManager.current
        
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("ESPELHO · TEMPO REAL")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.09)
                    .foregroundColor(theme.textLabel)
                
                Spacer()
                
                HStack(spacing: 8) {
                    if appState.fps > 0 {
                        Text("\(appState.fps) fps")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.success.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    Text("⌥1")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Device
            DeviceBezel()
            
            // Dock
            DeviceDock()
            
            // Cartao de correlacao: so faz sentido quando a coluna da direita
            // esta mostrando rede ou analytics.
            //
            // A comparacao era feita por `String(describing:)`, que casa com o
            // nome do case por acaso: renomear um case passaria pelo compilador
            // e quebraria a tela em silencio. Comparando o enum, o compilador
            // obriga a atualizar aqui.
            if appState.workspaceTab == .network || appState.workspaceTab == .analytics {
                CorrelationCard()
                    .padding(.horizontal, 24)
            }
            
            Spacer(minLength: 0)
        }
        .frame(minWidth: 320, idealWidth: 384, maxWidth: 560)
        .background(theme.bgPanel)
    }
}
