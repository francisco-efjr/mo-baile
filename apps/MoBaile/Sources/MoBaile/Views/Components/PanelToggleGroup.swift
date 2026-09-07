import SwiftUI

public struct PanelToggleGroup: View {
    @Environment(ThemeManager.self) private var theme
    
    @Binding var mirrorVisible: Bool
    @Binding var hierarchyVisible: Bool
    @Binding var workspaceVisible: Bool
    
    public init(mirrorVisible: Binding<Bool>, hierarchyVisible: Binding<Bool>, workspaceVisible: Binding<Bool>) {
        self._mirrorVisible = mirrorVisible
        self._hierarchyVisible = hierarchyVisible
        self._workspaceVisible = workspaceVisible
    }
    
    public var body: some View {
        HStack(spacing: 2) {
            PanelToggleButton(isActive: $mirrorVisible, position: .left, theme: theme)
            PanelToggleButton(isActive: $hierarchyVisible, position: .center, theme: theme)
            PanelToggleButton(isActive: $workspaceVisible, position: .right, theme: theme)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.current.bgControlTrack)
        )
    }
}

struct PanelToggleButton: View {
    @Binding var isActive: Bool
    let position: Position
    let theme: ThemeManager
    
    enum Position {
        case left, center, right
    }
    
    var body: some View {
        Button(action: {
            isActive.toggle()
        }) {
            PanelGlyph(position: position, isActive: isActive, theme: theme)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? theme.current.bgControl : Color.clear)
                        .shadow(color: isActive ? Color.black.opacity(0.1) : Color.clear, radius: 1, y: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct PanelGlyph: View {
    let position: PanelToggleButton.Position
    let isActive: Bool
    let theme: ThemeManager
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(isActive ? theme.current.textPrimary : theme.current.textLabel, lineWidth: 1.4)
                .frame(width: 13, height: 11)
            
            // Solid bar
            Group {
                switch position {
                case .left:
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isActive ? theme.current.textPrimary : theme.current.textLabel)
                        .frame(width: 4, height: 11)
                        .offset(x: -4.5)
                case .center:
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isActive ? theme.current.textPrimary : theme.current.textLabel)
                        .frame(width: 13, height: 4)
                        .offset(y: 3.5)
                case .right:
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isActive ? theme.current.textPrimary : theme.current.textLabel)
                        .frame(width: 4, height: 11)
                        .offset(x: 4.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
        }
    }
}
