import SwiftUI

public struct FluidPillButton: View {
    @Environment(ThemeManager.self) private var theme
    
    public enum Style {
        case primary
        case secondary
        case run
        case destructiveText
        case disabled
    }
    
    let text: String
    let icon: String?
    let action: () -> Void
    let style: Style
    
    @State private var isHovered = false
    
    public init(text: String, icon: String? = nil, style: Style = .primary, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary: return theme.current.accentOn
        case .secondary: return theme.current.textPrimary
        case .run: return Color.white
        case .destructiveText: return theme.current.danger
        case .disabled: return theme.current.textDisabled
        }
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if style == .run {
                    Text("▶")
                } else if let icon = icon {
                    Image(systemName: icon)
                }
                Text(text)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(foregroundColor)
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
        }
        .buttonStyle(FluidPillButtonStyle(theme: theme, style: style, isHovered: isHovered))
        .disabled(style == .disabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct FluidPillButtonStyle: ButtonStyle {
    var theme: ThemeManager
    var style: FluidPillButton.Style
    var isHovered: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(style == .secondary ? theme.current.border : Color.clear, lineWidth: 1)
            )
            .opacity(isHovered && style != .disabled && !configuration.isPressed ? 0.94 : 1.0)
    }
    
    private func backgroundColor(isPressed: Bool) -> Color {
        switch style {
        case .primary: return isPressed ? theme.current.accentPressed : theme.current.accent
        case .secondary: return Color.clear
        case .run: return theme.current.success
        case .destructiveText: return Color.clear
        case .disabled: return theme.current.bgPlaceholder
        }
    }
}
