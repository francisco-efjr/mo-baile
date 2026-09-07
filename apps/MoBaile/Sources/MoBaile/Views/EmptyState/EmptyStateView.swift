import SwiftUI

/// Tela de quando não há dispositivo.
///
/// É a tela que mais aparece quando algo está errado, então ela precisa fazer
/// duas coisas: dizer a verdade sobre o ambiente e oferecer o caminho de saída.
/// A versão anterior fazia nem uma nem outra: os indicadores eram literais no
/// código, o horário do último scan era fixo em `14:00:00`, e os dois botões
/// tinham corpo vazio.
struct EmptyStateView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        VStack(spacing: 22) {
            deviceOutline

            VStack(spacing: 8) {
                Text("Conecte um dispositivo para começar")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(theme.textPrimary)

                Text("O Mo baile detecta simuladores, emuladores e aparelhos físicos automaticamente. Se não houver nenhum ligado, dá para abrir um daqui.")
                    .font(.system(size: 12.5))
                    .foregroundColor(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            HStack(alignment: .top, spacing: 16) {
                iosCard
                androidCard
            }
            .padding(.top, 4)

            footer
        }
        .padding(24)
        .task {
            // Sem isto o cartão fica em "verificando ambiente…" para sempre.
            await session.refreshEnvironment()
        }
    }

    // MARK: - Partes

    private var deviceOutline: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(theme.textDisabled, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .frame(width: 132, height: 264)
            Text("sem sinal")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textDisabled)
        }
        .accessibilityHidden(true)
    }

    private var iosCard: some View {
        VStack(spacing: 8) {
            DiagnosticCard(
                platform: .ios,
                diagnostics: session.diagnostics?.ios,
                isBusy: session.isBooting,
                action: { Task { await acaoIOS() } },
                actionTitle: tituloAcaoIOS,
                actionEnabled: acaoIOSHabilitada
            )

            // Menu para escolher qual, quando há mais de um. Com um só, o botão
            // do cartão já resolve e o menu seria fricção sem ganho.
            if session.simulators.count > 1 {
                Menu {
                    ForEach(session.simulators) { simulator in
                        Button {
                            Task { await session.bootSimulator(udid: simulator.udid) }
                        } label: {
                            Text(simulator.booted
                                 ? "● \(simulator.displayName)"
                                 : simulator.displayName)
                        }
                    }
                } label: {
                    Text("escolher outro simulador")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 200)
            }
        }
    }

    private var androidCard: some View {
        VStack(spacing: 8) {
            DiagnosticCard(
                platform: .android,
                diagnostics: session.diagnostics?.android,
                isBusy: session.isBooting,
                action: { Task { await session.bootEmulator() } },
                actionTitle: "Abrir emulador",
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
                    Text("escolher outro emulador")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 200)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(textoDoScan)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textLabel)

            Button {
                Task {
                    await session.refreshDevices()
                    await session.refreshEnvironment()
                }
            } label: {
                Label("Verificar de novo", systemImage: "arrow.clockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(theme.accent)
        }
        .padding(.top, 12)
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
        case "boot_simulator": return "Abrir simulador"
        case "start_wda": return "Iniciar WebDriverAgent"
        default: return primeiroSimuladorLigado == nil ? "Abrir simulador" : "Ir para o simulador"
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
