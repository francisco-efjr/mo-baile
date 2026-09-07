import SwiftUI

/// Cartão de diagnóstico de uma plataforma.
///
/// A versão anterior recebia uma lista escrita à mão na `EmptyStateView`, com
/// um visto verde fixo em "Dispositivo conectado". A tela afirmava que havia
/// dispositivo conectado justamente quando não havia, que é o pior momento
/// possível para um diagnóstico mentir.
///
/// Agora as linhas vêm de `diagnostics.check`, medido pelo motor, e o botão de
/// ação faz o que promete.
struct DiagnosticCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let platform: Platform
    let diagnostics: EngineDTO.PlatformDiagnostics?
    let isBusy: Bool
    let action: () -> Void
    let actionTitle: String
    let actionEnabled: Bool

    private var theme: any ThemeTokens { themeManager.current }

    private var platformColor: Color {
        platform == .ios
            ? Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
            : Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(platformColor)
                    .frame(width: 8, height: 8)
                Text(diagnostics?.title ?? (platform == .ios ? "iOS" : "Android"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                if diagnostics?.ready == true {
                    Text("pronto")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.success.opacity(0.14))
                        .foregroundColor(theme.success)
                        .cornerRadius(4)
                }
            }

            if let checks = diagnostics?.checks, !checks.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(checks) { check in
                        HStack(alignment: .top, spacing: 8) {
                            statusIcon(for: check.daemonState)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.label)
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.textSecondary)
                                // O detalhe é o que transforma "algo está errado"
                                // em "faça isto".
                                if !check.detail.isEmpty {
                                    Text(check.detail)
                                        .font(.system(size: 10))
                                        .foregroundColor(theme.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(check.label). \(estado(check.daemonState)). \(check.detail)")
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("verificando ambiente…")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                }
            }

            Spacer(minLength: 0)

            FluidPillButton(
                text: isBusy ? "Iniciando…" : actionTitle,
                style: actionEnabled && !isBusy ? .primary : .disabled,
                action: action
            )
            .disabled(!actionEnabled || isBusy)
        }
        .padding(16)
        .frame(width: 268, height: 264, alignment: .topLeading)
        .background(theme.bgPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private func estado(_ status: DaemonState) -> String {
        switch status {
        case .ok: return "ok"
        case .warn: return "atenção"
        case .error: return "erro"
        case .busy: return "ocupado"
        case .off: return "inativo"
        }
    }

    @ViewBuilder
    private func statusIcon(for status: DaemonState) -> some View {
        switch status {
        case .ok:
            Text("✓").font(.system(size: 12, weight: .bold)).foregroundColor(theme.success)
        case .warn:
            Text("!").font(.system(size: 12, weight: .bold)).foregroundColor(theme.warning)
        case .error:
            Text("✕").font(.system(size: 12, weight: .bold)).foregroundColor(theme.danger)
        case .off, .busy:
            Text("·").font(.system(size: 12, weight: .bold)).foregroundColor(theme.textLabel)
        }
    }
}
