import SwiftUI

struct HTTPInspectorView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        VStack(spacing: 0) {
            NetworkToolbar()
            
            VSplitView {
                HTTPTableView()
                    .frame(minHeight: 150)
                
                if let selected = appState.selectedRequest {
                    HStack(spacing: 0) {
                        RequestDetailView(event: selected)
                            .frame(maxWidth: .infinity)
                        
                        Divider().background(theme.current.border)
                        
                        ResponseDetailView(event: selected)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 150)
                } else {
                    VStack {
                        Text("Selecione uma requisição para ver os detalhes")
                            .font(.system(size: 12))
                            .foregroundColor(theme.current.textTertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.current.bgPanel)
                }
            }
        }
        .background(theme.current.bgWindow)
    }
}
