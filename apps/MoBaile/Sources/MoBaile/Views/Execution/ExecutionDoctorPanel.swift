import SwiftUI

/// Doctor: uma linha por checagem (ok, atenção, falha, pulada), com mensagem
/// e dica. Nada instala, apaga ou reinicia; o motor só lê.
struct ExecutionDoctorPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        let ex = appState.execution
        VStack(spacing: 0) {
            PaneHeader(title: "Doctor") {
                if let doctor = ex.doctor, !ex.doctorRunning {
                    Text(ExecutionDoctorCopy.summary(doctor.summary))
                        .font(DSFont.subheadline.monospacedDigit())
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
                Button {
                    Task { await session.runDoctor() }
                } label: {
                    Label("Verificar de Novo", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(ex.doctorRunning || ex.currentProjectID == nil || ex.operation != nil || !session.isConnected)
                .help("Verificar de Novo: confere os pré-requisitos do projeto")
                .accessibilityLabel("Verificar de Novo")
            }
            Rectangle().fill(theme.separator).frame(height: 1)
            if ex.doctorRunning {
                HStack(spacing: DesignMetrics.Spacing.s4) {
                    ProgressView().controlSize(.small)
                    Text(ex.doctorProgress ?? "Conferindo…")
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignMetrics.Spacing.s5)
                .padding(.vertical, DesignMetrics.Spacing.s3)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
            if let doctor = ex.doctor {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if doctor.needsTrust {
                            ExecutionDoctorTrustRow()
                        }
                        ForEach(doctor.checks) { check in
                            ExecutionDoctorRow(check: check)
                            Rectangle().fill(theme.separator).frame(height: 0.5).padding(.leading, 36)
                        }
                    }
                }
                .opacity(ex.doctorRunning ? 0.55 : 1)
            } else if !ex.doctorRunning {
                EmptyState(icon: "stethoscope", text: "O doctor confere o projeto antes de rodar.",
                           actionLabel: session.isConnected && ex.currentProjectID != nil ? "Verificar" : nil,
                           action: { Task { await session.runDoctor() } }, compact: true)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.crossfade, value: ex.doctorRunning)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Doctor")
    }
}

/// Checagens puladas esperando a confiança no projeto (revisão da B1).
private struct ExecutionDoctorTrustRow: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        // Texto em cima e botão embaixo: lado a lado, numa coluna estreita, o
        // botão espremia a frase em quatro linhas.
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
                Text("Algumas checagens rodam o Python do projeto e esperam você confiar nele.")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Confiar no Projeto e Verificar…") { Task { await session.requestTrustForDoctor() } }
                    .controlSize(.small)
                    .disabled(appState.execution.operation != nil || appState.execution.doctorRunning
                              || appState.execution.isRunning || appState.execution.starting)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignMetrics.Spacing.s5)
        .background(theme.warningTint)
    }
}

private struct ExecutionDoctorRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let check: EngineDTO.ProjectDoctor.Check

    var body: some View {
        let theme = themeManager.current
        let estado = ExecutionDoctorCopy.daemonState(check.state)
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
            Image(systemName: StatusIndicator.symbol(estado))
                .font(DSFont.Symbol.small)
                .foregroundStyle(cor(estado, theme))
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.label)
                    .font(DSFont.callout.weight(.semibold))
                    .foregroundStyle(check.state == "skip" ? theme.labelSecondary : theme.labelPrimary)
                if !check.message.isEmpty {
                    Text(check.message)
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let dica = check.hint, !dica.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s2) {
                        Image(systemName: "lightbulb").font(.system(size: 10)).accessibilityHidden(true)
                        Text(dica)
                            .font(DSFont.mono(10.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .foregroundStyle(theme.accentText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DesignMetrics.Spacing.s5)
        .padding(.vertical, DesignMetrics.Spacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(check.label): \(ExecutionDoctorCopy.word(check.state))")
        .accessibilityValue([check.message, check.hint.map { "Dica: \($0)" }].compactMap { $0 }.joined(separator: ". "))
    }

    private func cor(_ estado: DaemonState, _ theme: any ThemeTokens) -> Color {
        switch estado {
        case .ok: return theme.success
        case .warn: return theme.warning
        case .error: return theme.destructive
        case .busy: return theme.info
        case .off: return theme.labelTertiary
        }
    }
}

enum ExecutionDoctorCopy {
    /// O estado do doctor no vocabulário do `StatusIndicator` (ícone e cor).
    static func daemonState(_ state: String) -> DaemonState {
        switch state {
        case "ok": return .ok
        case "warn": return .warn
        case "fail": return .error
        default: return .off
        }
    }

    static func word(_ state: String) -> String {
        switch state {
        case "ok": return "ok"
        case "warn": return "atenção"
        case "fail": return "falha"
        default: return "pulada"
        }
    }

    /// "6 ok · 1 atenção · 1 falha · 3 puladas", sem os zeros.
    static func summary(_ s: EngineDTO.ProjectDoctor.Summary) -> String {
        var partes: [String] = []
        if s.ok > 0 { partes.append("\(s.ok) ok") }
        if s.warn > 0 { partes.append("\(s.warn) atenção") }
        if s.fail > 0 { partes.append(s.fail == 1 ? "1 falha" : "\(s.fail) falhas") }
        if s.skip > 0 { partes.append(s.skip == 1 ? "1 pulada" : "\(s.skip) puladas") }
        return partes.joined(separator: " · ")
    }
}
