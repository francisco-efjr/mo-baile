import AppKit
import SwiftUI

struct ResponseDetailView: View {
    @Environment(ThemeManager.self) private var theme
    let event: NetworkEvent
    
    // Por default abre no Body (índice 1), conforme solicitado
    @State private var selectedTab = 1
    @State private var copiedFeedback = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Centralizado, informativo e clean
            HStack(spacing: 8) {
                // Lado esquerdo: Título, Status Code e Duração
                HStack(spacing: 6) {
                    Text("Response")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(theme.current.textPrimary)
                    
                    if let status = event.statusCode {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(status))
                                .frame(width: 6, height: 6)
                            Text("\(status)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(statusColor(status))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(status).opacity(0.15))
                        .cornerRadius(4)
                    }
                    
                    if !event.formattedDuration.isEmpty {
                        Text(event.formattedDuration)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(theme.current.textTertiary)
                    }
                }
                
                Spacer(minLength: 8)
                
                // Centro: Seletor de abas centralizado
                SegmentedControl(
                    items: ["Headers", "Body"],
                    selectedIndex: $selectedTab,
                    badges: [event.responseHeaders.count, event.responseBody.isEmpty ? nil : 1]
                )
                .fixedSize()
                
                Spacer(minLength: 8)
                
                // Lado direito: Botão Copiar
                Button(action: copyActiveContent) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copiedFeedback ? "Copiado" : "Copiar")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(theme.current.bgControlTrack)
                    .cornerRadius(5)
                    .foregroundColor(copiedFeedback ? theme.current.success : theme.current.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Copiar conteúdo atual da resposta")
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(theme.current.bgSubtle)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(theme.current.borderSubtle),
                alignment: .bottom
            )
            
            // Conteúdo principal
            ScrollView {
                if selectedTab == 0 {
                    headersView(event.responseHeaders)
                } else {
                    bodyView(event)
                }
            }
        }
        .background(theme.current.bgPanel)
    }
    
    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: return theme.current.success
        case 300..<400: return theme.current.accent
        case 400..<500: return theme.current.warning
        case 500..<600: return theme.current.danger
        default: return theme.current.textSecondary
        }
    }
    
    private func copyActiveContent() {
        let textToCopy: String
        if selectedTab == 0 {
            textToCopy = event.responseHeaders.sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
        } else {
            if event.method.uppercased() == "CONNECT" && event.responseBody.isEmpty {
                textToCopy = "HTTP/1.1 \(event.statusCode ?? 200) Connection Established\nDuration: \(event.formattedDuration)"
            } else {
                textToCopy = formatBody(event.responseBody)
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedFeedback = false
        }
    }
    
    @ViewBuilder
    private func headersView(_ headers: [String: String]) -> some View {
        if headers.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 24))
                    .foregroundColor(theme.current.textTertiary.opacity(0.6))
                Text("Sem headers na resposta")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.current.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(headers.sorted(by: { $0.key < $1.key }).enumerated()), id: \.element.key) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.key)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.current.accent)
                            .frame(width: 140, alignment: .leading)
                        
                        Text(item.value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(theme.current.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(index % 2 == 1 ? theme.current.bgContent.opacity(0.4) : Color.clear)
                    
                    Divider().background(theme.current.borderSubtle.opacity(0.5))
                }
            }
            .padding(.vertical, 6)
        }
    }
    
    @ViewBuilder
    private func bodyView(_ event: NetworkEvent) -> some View {
        let formatted = formatBody(event.responseBody)
        if !formatted.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(formatted)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.current.textPrimary)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.current.bgContent)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.current.borderSubtle, lineWidth: 1)
            )
            .padding(12)
        } else if event.method.uppercased() == "CONNECT" {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(theme.current.syntaxString)
                
                Text("Túnel HTTPS Estabelecido")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(theme.current.textPrimary)
                
                Text("Conexão criptografada de ponta a ponta estabelecida com sucesso.")
                    .font(.system(size: 11))
                    .foregroundColor(theme.current.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text("STATUS")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.current.textTertiary)
                        Text("\(event.statusCode ?? 200) Connection Established")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.current.success)
                    }
                    
                    Divider().frame(height: 24)
                    
                    VStack(spacing: 2) {
                        Text("DURAÇÃO")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(theme.current.textTertiary)
                        Text(event.formattedDuration.isEmpty ? "-" : event.formattedDuration)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.current.textPrimary)
                    }
                }
                .padding(10)
                .background(theme.current.bgSubtle)
                .cornerRadius(6)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(20)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 24))
                    .foregroundColor(theme.current.textTertiary.opacity(0.6))
                Text("Sem corpo (body) na resposta")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.current.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding()
        }
    }
    
    private func formatBody(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return text
        }
        return prettyString
    }
}
