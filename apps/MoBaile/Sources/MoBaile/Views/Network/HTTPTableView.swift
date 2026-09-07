import SwiftUI

struct HTTPTableView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("MÉTODO").frame(width: 64, alignment: .leading)
                Text("STATUS").frame(width: 62, alignment: .leading)
                Text("HOST").frame(maxWidth: .infinity, alignment: .leading)
                Text("PATH").frame(width: 300, alignment: .leading)
                Text("TAMANHO").frame(width: 84, alignment: .trailing)
                Text("TEMPO").frame(width: 76, alignment: .trailing)
            }
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundColor(theme.current.textLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.current.bgSubtle)
            
            Divider().background(theme.current.borderSubtle)
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.filteredHTTPRequests) { event in
                        let isSelected = appState.selectedRequest?.id == event.id
                        
                        HStack(spacing: 8) {
                            Text(event.method)
                                .foregroundColor(methodColor(event.method))
                                .frame(width: 64, alignment: .leading)
                            
                            Group {
                                if let code = event.statusCode {
                                    Text("\(code)").foregroundColor(statusColor(code))
                                } else {
                                    Text("-").foregroundColor(theme.current.textTertiary)
                                }
                            }
                            .frame(width: 62, alignment: .leading)
                            
                            Text(event.host)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text(event.path)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 300, alignment: .leading)
                            
                            Text(event.formattedSize)
                                .frame(width: 84, alignment: .trailing)
                            
                            if let _ = event.durationMs {
                                Text(event.formattedDuration)
                                    .frame(width: 76, alignment: .trailing)
                            } else {
                                Text("-")
                                    .foregroundColor(theme.current.textTertiary)
                                    .frame(width: 76, alignment: .trailing)
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(isSelected ? theme.current.textPrimary : theme.current.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? theme.current.selectionBg : Color.clear)
                        .overlay(
                            Rectangle()
                                .stroke(isSelected ? theme.current.selectionBorder : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectedRequest = event
                        }
                        
                        Divider().background(theme.current.borderSubtle)
                    }
                }
            }
        }
        .background(theme.current.bgContent)
    }
    
    private func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return theme.current.accent
        case "POST", "PUT", "PATCH": return theme.current.warning
        case "DELETE": return theme.current.danger
        case "CONNECT", "OPTIONS", "HEAD": return theme.current.syntaxString
        default: return theme.current.textPrimary
        }
    }
    
    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200...299: return theme.current.success
        case 300...399: return theme.current.warning
        case 400...599: return theme.current.danger
        default: return theme.current.textSecondary
        }
    }
}
