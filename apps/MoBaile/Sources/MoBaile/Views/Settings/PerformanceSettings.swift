import SwiftUI

/// Ajustes › Desempenho (PERF-5): Automático, Completo, Equilibrado ou Leve.
///
/// A escolha manual ganha do Automático. A única exceção é o Mac em estado
/// térmico crítico, que leva ao leve em qualquer escolha. Quem decide é o motor;
/// aqui só se escolhe e se mostra o perfil em uso e o motivo.
struct PerformanceSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        let perf = appState.perf
        Form {
            Picker("Desempenho:", selection: Binding(
                get: { appState.perf.preference },
                set: { nova in Task { await session.setPerfPreference(nova) } }
            )) {
                ForEach(PerfPreference.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityHint("Automático escolhe pelo estado do Mac; as outras opções fixam o perfil")

            LabeledContent("Em uso:") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(perf.badge ?? perf.profile) · \(perf.reasonText)")
                        .font(DSFont.mono(12))
                        .foregroundStyle(theme.labelPrimary)
                    Text(Self.explicacao(perf.badge ?? perf.profile))
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                        .frame(maxWidth: 340, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Text("O modo leve diminui a cadência do espelho e o que fica na memória, e tira vidro e animações. "
                 + "Gravar, rodar flows e capturar rede e analytics continuam iguais.")
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelSecondary)
                .frame(maxWidth: 440, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.columns)
        .padding(DesignMetrics.Spacing.windowMargin)
    }

    static func explicacao(_ perfil: String) -> String {
        switch perfil {
        case "leve": return "Espelho a 2 quadros por segundo, quadro menor, sem vidro nem animações."
        case "equilibrado": return "Espelho a 4 quadros por segundo e quadro um pouco menor."
        default: return "Espelho a 6 quadros por segundo, na qualidade de sempre."
        }
    }
}
