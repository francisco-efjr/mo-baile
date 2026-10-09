import SwiftUI

/// Cartão de diagnóstico de uma plataforma (iOS · WebDriverAgent, Android · ADB).
///
/// As linhas vêm de `diagnostics.check`, medido pelo motor, e o botão faz o
/// que promete. Cada checagem usa ícone, cor e texto juntos: o ✓ ! ✕ do
/// original dependia só da cor para ser lido.
struct DiagnosticCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let platform: Platform
    let diagnostics: EngineDTO.PlatformDiagnostics?
    let isBusy: Bool
    let action: () -> Void
    let actionTitle: String
    let actionEnabled: Bool

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(PlatformIdentity.color(platform))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(diagnostics?.title ?? platform.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if diagnostics?.ready == true {
                    Label("Pronto", systemImage: "checkmark")
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.success)
                }
            }

            if let checks = diagnostics?.checks, !checks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(checks) { check in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: Self.symbol(check.daemonState))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(cor(check.daemonState))
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(check.label)
                                    .font(DSFont.body)
                                    .foregroundStyle(theme.labelPrimary)
                                // O detalhe é o que transforma "algo está errado"
                                // em "faça isto".
                                if !check.detail.isEmpty {
                                    Text(check.detail)
                                        .font(DSFont.subheadline)
                                        .foregroundStyle(theme.labelSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(check.label). \(StatusIndicator.word(check.daemonState)). \(check.detail)")
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Verificando ambiente…")
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                }
            }

            Spacer(minLength: 0)

            Button(isBusy ? "Iniciando…" : actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(!actionEnabled || isBusy)
        }
        .frame(width: DesignMetrics.Widths.diagnosticCard - 2 * DesignMetrics.Spacing.groupBoxPadding,
               alignment: .topLeading)
        .frame(minHeight: 236 - 2 * DesignMetrics.Spacing.groupBoxPadding, alignment: .topLeading)
        .dsCard()
    }

    static func symbol(_ status: DaemonState) -> String {
        switch status {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .busy: return "arrow.triangle.2.circlepath"
        case .off: return "minus.circle"
        }
    }

    private func cor(_ status: DaemonState) -> Color {
        switch status {
        case .ok: return theme.success
        case .warn: return theme.warning
        case .error: return theme.destructive
        case .busy: return theme.info
        case .off: return theme.labelTertiary
        }
    }
}

/// Tela de quando não há dispositivo.
///
/// É a tela que mais aparece quando algo está errado, então ela precisa fazer
/// duas coisas: dizer a verdade sobre o ambiente e oferecer o caminho de saída.
struct NoDeviceView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.labelQuaternary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 92, height: 184)
                    .overlay(
                        Image(systemName: "iphone")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(theme.labelTertiary)
                    )
                    .padding(.bottom, 18)
                    .accessibilityHidden(true)

                Text("Conecte um dispositivo para começar")
                    .font(DSFont.title2)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("O Mo baile detecta simuladores, emuladores e aparelhos físicos automaticamente. Se não houver nenhum ligado, dá para abrir um daqui.")
                    .font(DSFont.body)
                    .foregroundStyle(theme.labelSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .padding(.bottom, 20)

                HStack(alignment: .top, spacing: 14) {
                    iosCard
                    androidCard
                }

                HStack(spacing: 10) {
                    Text(textoDoScan)
                        .font(DSFont.mono(11).monospacedDigit())
                        .foregroundStyle(theme.labelSecondary)
                    Button {
                        Task {
                            await session.refreshDevices()
                            await session.refreshEnvironment()
                        }
                    } label: {
                        Label("Verificar de Novo", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(PlainTextButtonStyle(theme: theme))
                    .controlSize(.small)
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bgContent)
        .task {
            // Sem isto o cartão fica em "Verificando ambiente…" para sempre.
            await session.refreshEnvironment()
        }
    }

    // MARK: - Cartões

    private var iosCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticCard(
                platform: .ios,
                diagnostics: session.diagnostics?.ios,
                isBusy: session.isBooting,
                action: { Task { await acaoIOS() } },
                actionTitle: tituloAcaoIOS,
                actionEnabled: acaoIOSHabilitada
            )

            // Escolher qual, quando há mais de um. Com um só, o botão do
            // cartão já resolve e o menu seria fricção sem ganho.
            if session.simulators.count > 1 {
                Menu {
                    ForEach(session.simulators) { simulator in
                        Toggle(simulator.displayName, isOn: Binding(
                            get: { simulator.booted },
                            set: { _ in Task { await session.bootSimulator(udid: simulator.udid) } }
                        ))
                    }
                } label: {
                    Text("Simulador: \(primeiroSimuladorLigado?.displayName ?? session.simulators[0].displayName)")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Escolher simulador")
            }
        }
    }

    private var androidCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            DiagnosticCard(
                platform: .android,
                diagnostics: session.diagnostics?.android,
                isBusy: session.isBooting,
                action: { Task { await session.bootEmulator() } },
                actionTitle: "Abrir Emulador",
                actionEnabled: !session.avds.isEmpty
            )

            if session.avds.count > 1 {
                Menu {
                    ForEach(session.avds, id: \.self) { avd in
                        Button(avd) {
                            Task { await session.bootEmulator(name: avd) }
                        }
                    }
                } label: {
                    Text("Emulador: \(session.avds[0])")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Escolher emulador")
            }
        }
    }

    // MARK: - Apoio

    private var primeiroSimuladorLigado: EngineDTO.Simulator? {
        session.simulators.first { $0.booted }
    }

    /// O motor marca a checagem que tem conserto com um identificador de ação.
    /// A interface obedece a isso em vez de reimplementar a mesma decisão.
    private var acaoPendenteIOS: String? {
        session.diagnostics?.ios.checks.compactMap(\.action).first
    }

    /// Um botão só, que faz o próximo passo necessário. Dois botões lado a lado
    /// obrigariam o usuário a saber qual é a vez de qual.
    private var tituloAcaoIOS: String {
        switch acaoPendenteIOS {
        case "boot_simulator": return "Abrir Simulador"
        case "start_wda": return "Iniciar WebDriverAgent"
        default: return primeiroSimuladorLigado == nil ? "Abrir Simulador" : "Ir para o Simulador"
        }
    }

    private var acaoIOSHabilitada: Bool {
        acaoPendenteIOS == "start_wda" || !session.simulators.isEmpty
    }

    private func acaoIOS() async {
        if acaoPendenteIOS == "start_wda" {
            await session.startWDA()
        } else {
            await session.bootSimulator()
        }
    }

    /// Horário real da última varredura. O antigo era a string `14:00:00`.
    private var textoDoScan: String {
        guard let lastScan = session.lastScan else { return "procurando dispositivos…" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "último scan \(formatter.string(from: lastScan))"
    }
}
