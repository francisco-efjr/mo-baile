import AppKit
import SwiftUI

struct NetworkToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
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
                FluidPillButton(
                    text: appState.proxyRunning ? "Parar proxy" : "Configurar proxy",
                    icon: "network",
                    style: appState.proxyRunning ? .primary : .secondary
                ) {
                    Task {
                        await session.toggleProxy()
                    }
                }
                .help(appState.proxyRunning ? "Encerra o proxy e desfaz a rota reversa no aparelho" : "Inicia o proxy MITM e configura a rota reversa no aparelho")

                FluidPillButton(
                    text: "Exportar HAR",
                    icon: "square.and.arrow.up",
                    style: .secondary
                ) {
                    exportHAR()
                }
                .disabled(appState.httpRequests.isEmpty)
                .help("Exporta o tráfego HTTP capturado no formato HAR 1.2")

                FluidPillButton(text: "Limpar tráfego", style: .destructiveText) {
                    Task {
                        await session.clearTraffic()
                    }
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

    private func exportHAR() {
        if appState.httpRequests.isEmpty {
            appState.statusMessage = "Nenhuma requisição para exportar"
            return
        }
        guard let data = HARExporter.generateHAR(from: appState.httpRequests) else {
            appState.statusMessage = "Erro ao gerar arquivo HAR"
            return
        }
        let panel = NSSavePanel()
        panel.title = "Exportar Tráfego HAR"
        panel.nameFieldStringValue = "network_traffic.har"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                appState.statusMessage = "✓ HAR salvo em: \(url.lastPathComponent)"
            } catch {
                appState.statusMessage = "Erro ao salvar HAR: \(error.localizedDescription)"
            }
        }
    }
}
