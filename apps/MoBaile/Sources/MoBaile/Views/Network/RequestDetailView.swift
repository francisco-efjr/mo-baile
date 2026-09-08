import AppKit
import SwiftUI

struct RequestDetailView: View {
    @Environment(ThemeManager.self) private var theme
    let event: NetworkEvent
    
    @State private var selectedTab = 0
    @State private var copiedFeedback = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Centralizado, informativo e clean
            HStack(spacing: 8) {
                // Lado esquerdo: Título e Método
                HStack(spacing: 6) {
                    Text("Request")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(theme.current.textPrimary)
                    
                    Text(event.method)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(methodColor(event.method).opacity(0.18))
                        .foregroundColor(methodColor(event.method))
                        .cornerRadius(4)
                }
                
                Spacer(minLength: 8)
                
                // Centro: Seletor de abas centralizado
                SegmentedControl(
                    items: ["Headers", "Body"],
                    selectedIndex: $selectedTab,
                    badges: [event.requestHeaders.count, event.requestBody.isEmpty ? nil : 1]
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
                .help("Copiar conteúdo atual da requisição")
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
                    headersView(event.requestHeaders)
                } else {
                    bodyView(event.requestBody)
                }
            }
        }
        .background(theme.current.bgPanel)
    }
    
    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return theme.current.accent
        case "POST", "PUT", "PATCH": return theme.current.warning
        case "DELETE": return theme.current.danger
        case "CONNECT": return theme.current.syntaxString
        default: return theme.current.textSecondary
        }
    }
    
    private func copyActiveContent() {
        let textToCopy: String
        if selectedTab == 0 {
            textToCopy = event.requestHeaders.sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
        } else {
            textToCopy = formatBody(event.requestBody)
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
                Text("Sem headers na requisição")
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
    private func bodyView(_ text: String) -> some View {
        let formatted = formatBody(text)
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
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 24))
                    .foregroundColor(theme.current.textTertiary.opacity(0.6))
                Text("Sem corpo (body)")
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
