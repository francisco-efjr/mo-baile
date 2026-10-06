import SwiftUI

public struct SegmentedControl: View {
    @Environment(ThemeManager.self) private var theme
    
    let items: [String]
    @Binding var selectedIndex: Int
    var badges: [Int?]?
    
    public init(items: [String], selectedIndex: Binding<Int>, badges: [Int?]? = nil) {
        self.items = items
        self._selectedIndex = selectedIndex
        self.badges = badges
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<items.count, id: \.self) { index in
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedIndex = index
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(items[index])
                            .font(.system(size: 11.5, weight: selectedIndex == index ? .medium : .regular))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        if let badges = badges, index < badges.count, let badge = badges[index] {
                            Text("\(badge)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(selectedIndex == index ? theme.current.accent : theme.current.bgSubtle)
                                .foregroundColor(selectedIndex == index ? theme.current.accentOn : theme.current.textSecondary)
                                .cornerRadius(5)
                        }
                    }
                    .foregroundColor(selectedIndex == index ? theme.current.textPrimary : theme.current.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selectedIndex == index ? theme.current.bgControl : Color.clear)
                            .shadow(color: selectedIndex == index ? Color.black.opacity(0.1) : Color.clear, radius: 1, y: 1)
                    )
                }
                .buttonStyle(.plain)
                // O segmento escolhido só se distinguia pela cor e pela sombra.
                // O leitor de tela precisa do estado, e a cada segmento cabe o
                // próprio nome.
                .accessibilityAddTraits(selectedIndex == index ? .isSelected : [])
            }
        }
        // Sem virar um elemento de grupo, o `.accessibilityLabel` que quem usa o
        // controle aplica de fora ("Plataforma") era herdado por cada segmento, e
        // "iOS" e "Android" saíam do leitor com o mesmo nome. Como grupo, o
        // rótulo de fora descreve o conjunto e cada botão mantém o seu.
        .accessibilityElement(children: .contain)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.current.bgControlTrack)
        )
    }
}
