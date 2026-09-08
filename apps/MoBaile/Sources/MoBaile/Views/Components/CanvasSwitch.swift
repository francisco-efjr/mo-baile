import SwiftUI

public struct CanvasSwitch: View {
    @Environment(ThemeManager.self) private var theme
    
    let label: String
    @Binding var isOn: Bool
    
    public init(label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Sem isto o rotulo quebra no meio da palavra quando a barra fica
            // apertada: "Streaming" virava "Streamin" / "g" em duas linhas.
            // O texto e curto e fixo, entao vale mais manter a largura
            // intrinseca e deixar a barra comprimir o que e elastico.
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(theme.current.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? theme.current.accent : theme.current.bgControlTrack)
                    .frame(width: 34, height: 20)
                
                Circle()
                    .fill(isOn ? Color.white : theme.current.bgControl)
                    .frame(width: 16, height: 16)
                    .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
                    .offset(x: isOn ? 7 : -7)
            }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.16)) {
                    isOn.toggle()
                }
            }
        }
    }
}
