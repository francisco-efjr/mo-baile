import SwiftUI

public struct ActivityBadge: View {
    @Environment(ThemeManager.self) private var theme
    
    public enum Style {
        case network
        case analytics
        case `default`
    }
    
    let count: Int
    let style: Style
    
    public init(count: Int, style: Style = .default) {
        self.count = count
        self.style = style
    }
    
    private var backgroundColor: Color {
        switch style {
        case .network: return theme.current.accent
        case .analytics: return theme.current.warningBg
        case .default: return theme.current.bgControlTrack
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .network: return theme.current.accentOn
        case .analytics: return theme.current.warningText
        case .default: return theme.current.textSecondary
        }
    }
    
    public var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(foregroundColor)
            .padding(.vertical, 1)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundColor)
            )
    }
}
