import SwiftUI

public struct UnderlineTabBar: View {
    @Environment(ThemeManager.self) private var theme
    
    let tabs: [String]
    @Binding var selectedIndex: Int
    let height: CGFloat
    
    @Namespace private var animation
    
    public init(tabs: [String], selectedIndex: Binding<Int>, height: CGFloat = 30) {
        self.tabs = tabs
        self._selectedIndex = selectedIndex
        self.height = height
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<tabs.count, id: \.self) { index in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedIndex = index
                    }
                }) {
                    VStack(spacing: 0) {
                        Spacer()
                        Text(tabs[index])
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(selectedIndex == index ? theme.current.textPrimary : theme.current.textLabel)
                            .padding(.bottom, 6)
                        
                        if selectedIndex == index {
                            Rectangle()
                                .fill(theme.current.accent)
                                .frame(height: 1.5)
                                .matchedGeometryEffect(id: "underline", in: animation)
                        } else {
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 1.5)
                        }
                    }
                    .frame(height: height)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}
