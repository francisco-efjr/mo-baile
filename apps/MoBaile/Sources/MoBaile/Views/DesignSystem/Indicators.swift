import SwiftUI

/// Estado de um serviço (WDA, ADB, Proxy, FA, aparelho).
///
/// Cor, forma do ícone e texto juntos: nunca só cor. A versão anterior era um
/// ponto colorido de 6 pt, que não diz nada para quem não distingue verde de
/// vermelho.
struct StatusIndicator: View {
    @Environment(ThemeManager.self) private var themeManager

    let status: DaemonState
    let label: String
    var detail: String? = nil
    var mono: Bool = true

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Self.symbol(status))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(label)
                .font(mono ? DSFont.mono(11) : DSFont.subheadline)
                .foregroundStyle(theme.labelSecondary)
                .lineLimit(1)
        }
        .fixedSize()
        .help(ajuda)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Self.word(status))
    }

    private var ajuda: String {
        var texto = "\(label): \(Self.word(status))"
        if let detail, !detail.isEmpty { texto += ". \(detail)" }
        return texto
    }

    private var color: Color {
        switch status {
        case .ok: return theme.success
        case .busy: return theme.info
        case .warn: return theme.warning
        case .error: return theme.destructive
        case .off: return theme.labelTertiary
        }
    }

    static func symbol(_ status: DaemonState) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .busy: return "arrow.triangle.2.circlepath"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .off: return "minus.circle"
        }
    }

    static func word(_ status: DaemonState) -> String {
        switch status {
        case .ok: return "ok"
        case .busy: return "ocupado"
        case .warn: return "atenção"
        case .error: return "erro"
        case .off: return "inativo"
        }
    }
}

/// Chip do tipo de nó da hierarquia: letra e cor (W, V, T, I, B).
struct TypeChip: View {
    @Environment(ThemeManager.self) var themeManager
    let type: ChipType

    var body: some View {
        let color = themeManager.current.chipColor(type)
        Text(type.rawValue)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .frame(width: DesignMetrics.typeChip, height: DesignMetrics.typeChip)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.chip))
            .help(type.displayName)
            .accessibilityLabel(type.displayName)
    }
}

extension ChipType {
    var displayName: String {
        switch self {
        case .window: return "Janela"
        case .view: return "Contêiner"
        case .text: return "Texto"
        case .input: return "Campo"
        case .button: return "Botão"
        }
    }
}

/// Contador em texto secundário, com algarismos tabulares.
struct CountBadge: View {
    @Environment(ThemeManager.self) private var themeManager
    let value: Int?

    var body: some View {
        if let value {
            Text("\(value)")
                .font(DSFont.callout.monospacedDigit())
                .foregroundStyle(themeManager.current.labelSecondary)
        }
    }
}

/// Barra de progresso de 5 pt, na cor do destaque ou do resultado.
struct ProgressBar: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double
    var tint: Color? = nil

    var body: some View {
        let theme = themeManager.current
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.fillPrimary)
                Capsule()
                    .fill(tint ?? theme.accent)
                    .frame(width: max(0, geo.size.width * min(max(value, 0), 1)))
                    .animation(Motion.smooth(reduceMotion: reduceMotion), value: value)
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel("Progresso")
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) por cento")
    }
}
