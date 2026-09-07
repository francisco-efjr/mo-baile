import SwiftUI

struct TerminalView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(".flow_runner.py")
                Spacer()
                Text("stdout · streaming")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(theme.current.textLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.current.bgTerminal.opacity(0.5))
            
            // Log Content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(appState.runLog) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(line.timestamp.formatted(date: .omitted, time: .standard))
                                    .foregroundColor(theme.current.textDisabled)
                                
                                Text("[\(line.prefix)]")
                                    .foregroundColor(prefixColor(for: line.prefix))
                                
                                Text(line.message)
                                    .foregroundColor(theme.current.textSecondary)
                            }
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineSpacing(1.75 - 1.0)
                            .id(line.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: appState.runLog.count) {
                    if let lastId = appState.runLog.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(theme.current.bgTerminal)
        .cornerRadius(10)
    }
    
    private func prefixColor(for prefix: String) -> Color {
        switch prefix {
        case "INFO", "RUN": return theme.current.accent
        case "PASS": return theme.current.success
        case "FAIL": return theme.current.danger
        case "HTTP", "FA": return theme.current.warning
        default: return theme.current.textSecondary
        }
    }
}
