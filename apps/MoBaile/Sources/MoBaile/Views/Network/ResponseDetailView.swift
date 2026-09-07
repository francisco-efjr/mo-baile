import SwiftUI

struct ResponseDetailView: View {
    @Environment(ThemeManager.self) private var theme
    let event: NetworkEvent
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Response")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.current.textPrimary)
                Spacer()
                if let status = event.statusCode {
                    Text("\(status) · \(event.formattedDuration)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.current.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            UnderlineTabBar(tabs: ["Headers", "Body"], selectedIndex: $selectedTab)
                .padding(.horizontal, 12)
            
            Divider().background(theme.current.borderSubtle)
            
            ScrollView {
                if selectedTab == 0 {
                    headersView(event.responseHeaders)
                } else {
                    bodyView(event.responseBody)
                }
            }
        }
        .background(theme.current.bgPanel)
    }
    
    @ViewBuilder
    private func headersView(_ headers: [String: String]) -> some View {
        if headers.isEmpty {
            Text("Sem headers")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.current.textTertiary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(alignment: .top, spacing: 8) {
                        Text(key + ":")
                            .foregroundColor(theme.current.accent)
                        Text(value)
                            .foregroundColor(theme.current.textPrimary)
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    @ViewBuilder
    private func bodyView(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(theme.current.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Sem corpo (body)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(theme.current.textTertiary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
