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
                gerarAssercaoDeContrato()
            }
            .padding(.top, 4)
            .help("Gera código de asserção de contrato HTTP correlacionando o passo atual com o tráfego interceptado")
        }
        .padding(16)
        .background(theme.bgPanel)
        .cornerRadius(9)
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func gerarAssercaoDeContrato() {
        let snippet: String
        if let lastReq = appState.httpRequests.last {
            let path = URL(string: lastReq.url)?.path ?? lastReq.url
            let cleanPath = path.isEmpty ? "/" : path
            let status = lastReq.statusCode ?? 200
            snippet = """

        # Asserção de contrato de API correlacionada (MITM)
        response = self.network_interceptor.wait_for_request('\(cleanPath)', timeout=5.0)
        assert response.status_code == \(status)

"""
        } else {
            snippet = """

        # Asserção de contrato de API correlacionada (MITM)
        response = self.network_interceptor.wait_for_request('/v2/credito/simulacao', timeout=5.0)
        assert response.status_code == 200

"""
        }
        appState.actionsCode += snippet
        appState.statusMessage = "Asserção de contrato gerada e inserida no código!"
    }
}
