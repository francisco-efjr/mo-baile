import SwiftUI

public struct CollapsedRail: View {
    @Environment(ThemeManager.self) private var theme
    
    let label: String
    let shortcut: String
    @Binding var isExpanded: Bool
    let dotColor: Color?
    
    @State private var isHovered = false
    
    public init(label: String, shortcut: String, isExpanded: Binding<Bool>, dotColor: Color? = nil) {
        self.label = label
        self.shortcut = shortcut
        self._isExpanded = isExpanded
        self.dotColor = dotColor
    }
    
    public var body: some View {
        Button(action: {
            withAnimation {
                isExpanded = true
            }
        }) {
            VStack(spacing: 0) {
                Text("›")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(isHovered ? theme.current.textPrimary : theme.current.textLabel)
                    .padding(.top, 12)
                
                Spacer()
                
                Text("\(label) \(shortcut)")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.9)
                    .foregroundColor(isHovered ? theme.current.textPrimary : theme.current.textLabel)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 30)
                
                Spacer()
                
                if let dotColor = dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                        .padding(.bottom, 12)
                }
            }
            .frame(width: 30)
            .frame(maxHeight: .infinity)
            .background(isHovered ? theme.current.bgPanelAlt : theme.current.bgPanel)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
