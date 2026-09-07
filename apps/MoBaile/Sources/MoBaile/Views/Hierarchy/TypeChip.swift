import SwiftUI

struct TypeChip: View {
    @Environment(ThemeManager.self) var themeManager
    let type: ChipType
    
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(foregroundColor)
            .frame(width: 15, height: 15)
            .background(backgroundColor)
            .cornerRadius(4)
    }
    
    var text: String {
        switch type {
        case .window: return "W"
        case .view: return "V"
        case .text: return "T"
        case .input: return "I"
        case .button: return "B"
        }
    }
    
    var backgroundColor: Color {
        let tokens = themeManager.current
        switch type {
        case .window, .view: return tokens.bgControlTrack ?? Color.gray.opacity(0.3)
        case .text: return tokens.warningBg ?? Color.yellow.opacity(0.3)
        case .input: return tokens.successBg ?? Color.green.opacity(0.3)
        case .button: return tokens.accent ?? Color.blue
        }
    }
    
    var foregroundColor: Color {
        let tokens = themeManager.current
        switch type {
        case .window, .view: return tokens.textSecondary ?? Color.secondary
        case .text: return tokens.warningText ?? Color.yellow
        case .input: return tokens.successText ?? Color.green
        case .button: return tokens.accentOn ?? Color.white
        }
    }
}
