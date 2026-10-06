import SwiftUI

public struct FluidPillButton: View {
    @Environment(ThemeManager.self) private var theme
    
    public enum Style {
        case primary
        case secondary
        case run
        case destructiveText
        /// Preenchido de vermelho: para estado em curso que precisa ser óbvio
        /// de longe, como a gravação de tela ligada.
        case recording
        case disabled
    }
    
    let text: String
    let icon: String?
    let action: () -> Void
    let style: Style
    let accessibilityLabelText: String?
    let accessibilityValueText: String?
    let accessibilityHintText: String?
    
    @State private var isHovered = false
    
    /// Os três parâmetros de acessibilidade são opcionais e só valem quando o
    /// texto visível não basta: botão que mostra só o ícone (`text` vazio), ou
    /// interruptor que precisa dizer se está ligado. Sem eles, o leitor lê o
    /// próprio `text`, como antes.
    public init(
        text: String,
        icon: String? = nil,
        style: Style = .primary,
        accessibilityLabel: String? = nil,
        accessibilityValue: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.icon = icon
        self.style = style
        self.accessibilityLabelText = accessibilityLabel
        self.accessibilityValueText = accessibilityValue
        self.accessibilityHintText = accessibilityHint
        self.action = action
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary: return theme.current.accentOn
        case .secondary: return theme.current.textPrimary
        case .run: return Color.white
        case .destructiveText: return theme.current.danger
        case .recording: return Color.white
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
                // Rotulo de botao nao pode quebrar: "Forçar Captura" virava
                // duas linhas e "Copiar" virava "Copi" / "ar" assim que a
                // coluna apertava.
                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
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
        .modifier(PillAccessibility(
            label: accessibilityLabelText,
            value: accessibilityValueText,
            hint: accessibilityHintText
        ))
    }
}

/// Aplica só o que foi informado. `accessibilityLabel("")` não equivale a não
/// ter rótulo: ele apaga o nome que o leitor tiraria do texto do botão.
private struct PillAccessibility: ViewModifier {
    let label: String?
    let value: String?
    let hint: String?

    func body(content: Content) -> some View {
        comDica(comValor(comRotulo(content)))
    }

    @ViewBuilder
    private func comRotulo(_ content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }

    @ViewBuilder
    private func comValor(_ content: some View) -> some View {
        if let value { content.accessibilityValue(value) } else { content }
    }

    @ViewBuilder
    private func comDica(_ content: some View) -> some View {
        if let hint { content.accessibilityHint(hint) } else { content }
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
        case .recording: return theme.current.danger
        case .disabled: return theme.current.bgPlaceholder
        }
    }
}
