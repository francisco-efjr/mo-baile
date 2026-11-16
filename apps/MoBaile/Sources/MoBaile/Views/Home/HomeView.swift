import AppKit
import SwiftUI

/// Tela Início (3.11.0): boas-vindas útil no dia a dia. Escolher ou usar o
/// aparelho, entrar numa área, continuar o trabalho recente. O diagnóstico de
/// instalação foi para a tela Ambiente (`EnvironmentView`).
///
/// O motor decide o estado (`home.summary`): `first_run` quando nenhuma
/// plataforma serve nesta máquina, `daily` quando pelo menos uma serve. Com o
/// motor parado, a tela ainda diz o que fazer, porque o que falta costuma ser
/// justamente o Python dele.
/// Especificação: `docs/design/home/README.md`; maquetes em `docs/design/home/maquete/`.
struct HomeView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView {
            HomeContent()
        }
        .background(themeManager.current.bgContent)
    }
}

/// O conteúdo do Início, sem a rolagem: é o que os testes desenham com o
/// `ImageRenderer`, que não desenha `ScrollView`.
struct HomeContent: View {
    @Environment(EngineSession.self) private var session

    @AppStorage(LaunchDestination.seenKey) private var jaVisto = false

    var body: some View {
        Group {
            if session.isConnected, let home = session.home {
                if home.isFirstRun {
                    HomeFirstRunContent(home: home)
                } else {
                    HomeDailyContent(home: home)
                }
            } else {
                HomeEngineContent()
            }
        }
        // A Primeira vez vira o uso diário sozinha, com o crossfade de 180 ms.
        .animation(Motion.crossfade, value: session.home?.state)
        .onAppear { jaVisto = true }
        .task { await conferir(seMaisVelhoQue: 0) }
        // Quem instala pelo Terminal volta ao app: confere de novo sem pedir.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await conferir(seMaisVelhoQue: 3) }
        }
    }

    private func conferir(seMaisVelhoQue segundos: TimeInterval) async {
        guard session.isConnected else { return }
        if let ultima = session.lastSetupCheck, Date().timeIntervalSince(ultima) < segundos { return }
        await session.refreshSetup()
    }
}

/// Início com o motor parado ou subindo: o único passo que resta (instalar o
/// Python, reiniciar o motor) ou "Conferindo…".
struct HomeEngineContent: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    @State private var erroInstalacao: String?

    private var theme: any ThemeTokens { themeManager.current }

    private var passo: HomeNextStep {
        HomeNextStep.pick(engineStatus: session.engineStatus, lastError: session.lastError, setup: nil, deviceName: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s9) {
            HStack(alignment: .center, spacing: DesignMetrics.Spacing.s6) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                    Text("Mo baile")
                        .font(DSFont.largeTitle.weight(.bold))
                        .foregroundStyle(theme.labelPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(HomeCopy.summary(passo))
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HomeNextStepCard(passo: passo, pending: 0, install: instalar, erro: erroInstalacao)
            Text(HomeCopy.note)
                .font(DSFont.callout)
                .foregroundStyle(theme.labelSecondary)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, DesignMetrics.Spacing.s10)
        .padding(.top, 36)
        .padding(.bottom, DesignMetrics.Spacing.s10)
        .frame(maxWidth: .infinity)
    }

    private func instalar(_ alvo: String) {
        do {
            // Sem motor, o script cria o Python do Mo baile.
            try SetupInstaller.openInTerminal(target: alvo, python: nil)
            erroInstalacao = nil
            appState.statusMessage = "Instalação aberta no Terminal"
        } catch {
            erroInstalacao = error.localizedDescription
        }
    }
}

// MARK: - Próximo passo

/// O único cartão em destaque da tela, com aro no destaque e o botão padrão.
struct HomeNextStepCard: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    let passo: HomeNextStep
    let pending: Int
    let install: (String) -> Void
    var erro: String? = nil

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            Text(rotulo)
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.accentText)
            Text(titulo)
                .font(DSFont.title3)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(texto)
                .font(DSFont.body)
                .foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 600, alignment: .leading)
            if let comando {
                Text(comando)
                    .font(DSFont.mono(11.5))
                    .foregroundStyle(theme.labelPrimary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .padding(.horizontal, DesignMetrics.Spacing.s4)
                    .padding(.vertical, DesignMetrics.Spacing.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.fillTertiary, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
                    .accessibilityLabel("Comando: \(comando)")
            }
            if let erro {
                InlineError(title: "Não deu para abrir o Terminal.", text: erro)
            }
            HStack(spacing: DesignMetrics.Spacing.s4) { botoes }
                .padding(.top, DesignMetrics.Spacing.s2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous)
                .strokeBorder(theme.accent, lineWidth: DesignMetrics.DiagnosticCard.recommendedStroke)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Próximo passo")
    }

    private var rotulo: String {
        switch passo {
        case .connected: return "Aparelho conectado"
        case .checking: return "Conferindo"
        default: return "Próximo passo"
        }
    }

    private var titulo: String {
        switch passo {
        case .installPython: return "Instalar o Python do Mo baile"
        case .engineStopped: return "Reiniciar o motor"
        case .checking: return "Conferindo o ambiente…"
        case .install(let proximo): return proximo.install != nil ? "Instalar: \(proximo.label)" : proximo.label
        case .connectDevice: return "Conectar um aparelho"
        case .connected(let nome): return nome
        }
    }

    private var texto: String {
        switch passo {
        case .installPython:
            return "Cria um Python só para o Mo baile, com Pillow e requests, e não mexe nos outros Pythons do Mac. "
                + "Precisa de internet só agora. Quando terminar, clique em Reiniciar Motor."
        case .engineStopped(let motivo):
            return motivo
        case .checking:
            return "Leva menos de um segundo depois que o motor sobe."
        case .install(let proximo):
            return proximo.detail
        case .connectDevice:
            return "Plugue um aparelho com depuração USB, ou abra um simulador ou emulador. O Mo baile detecta sozinho."
        case .connected:
            return "O espelho começa ao abrir uma área, e o clique no espelho vira toque no aparelho."
        }
    }

    /// O alvo de instalação deste passo, quando há um.
    private var alvo: String? {
        switch passo {
        case .installPython: return "python"
        case .install(let proximo): return proximo.install
        default: return nil
        }
    }

    private var python: String? { session.isConnected ? session.setup?.python.path : nil }

    private var comando: String? {
        guard let alvo else { return nil }
        return SetupInstaller.copyableCommand(target: alvo, python: python)
    }

    @ViewBuilder
    private var botoes: some View {
        switch passo {
        case .installPython:
            Button("Instalar no Terminal…") { install("python") }
                .buttonStyle(.borderedProminent)
            copiar
            Button("Reiniciar Motor") { Task { await session.restartEngine() } }
                .disabled(session.isRestarting)
        case .engineStopped:
            Button("Reiniciar Motor") { Task { await session.restartEngine() } }
                .buttonStyle(.borderedProminent)
                .disabled(session.isRestarting)
        case .checking:
            ProgressView().controlSize(.small)
        case .install(let proximo):
            if let alvo = proximo.install {
                Button("Instalar no Terminal…") { install(alvo) }
                    .buttonStyle(.borderedProminent)
                copiar
            } else if let link = proximo.link, let url = URL(string: link) {
                Button(HomeCopy.linkTitle(link)) { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }
        case .connectDevice:
            if !session.simulators.isEmpty {
                Button(session.isBooting ? "Iniciando…" : "Abrir Simulador") { Task { await session.bootSimulator() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isBooting)
            }
            if !session.avds.isEmpty {
                Button(session.isBooting ? "Iniciando…" : "Abrir Emulador") { Task { await session.bootEmulator() } }
                    .disabled(session.isBooting)
            }
        case .connected:
            Button("Abrir Page Objects") { appState.workspaceTab = .pageObjects }
                .buttonStyle(.borderedProminent)
            Button("Abrir Rede HTTP") { appState.workspaceTab = .network }
        }
    }

    @ViewBuilder
    private var copiar: some View {
        if let comando {
            Button("Copiar Comando") {
                Exporters.copy(comando)
                appState.statusMessage = "Comando copiado"
            }
            .help("Copia o comando para rodar você mesmo no Terminal")
        }
    }
}

// MARK: - Ambiente

/// Um grupo do Ambiente (Motor, Android, iOS, Extras) num cartão, uma linha
/// por item, com o botão que resolve quando há um.
struct HomeComponentGroup: View {
    @Environment(ThemeManager.self) private var themeManager
    let title: String
    let components: [EngineDTO.SetupComponent]
    let install: (String) -> Void
    let open: (String) -> Void

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            Text(title)
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.labelSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(components.enumerated()), id: \.element.id) { indice, item in
                    if indice > 0 {
                        Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)
                    }
                    HomeComponentRow(item: item, install: install, open: open)
                }
            }
            .dsCard(padding: 0)
        }
    }
}

struct HomeComponentRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let item: EngineDTO.SetupComponent
    let install: (String) -> Void
    let open: (String) -> Void

    var body: some View {
        let theme = themeManager.current
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
            Image(systemName: DiagnosticCard.symbol(item.daemonState))
                .font(DSFont.Symbol.small)
                .foregroundStyle(HomeStateStyle.color(item.daemonState, theme))
                .frame(width: DesignMetrics.DiagnosticCard.checkIconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.DiagnosticCard.detailGap) {
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Text(item.label)
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelPrimary)
                    if !item.required {
                        Text("Opcional")
                            .font(DSFont.footnote.weight(.semibold))
                            .foregroundStyle(theme.labelSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(theme.fillSecondary, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.chip))
                    }
                }
                Text(item.detail)
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: DesignMetrics.Spacing.s4)
            botao
        }
        .padding(.horizontal, DesignMetrics.Spacing.s6)
        .padding(.vertical, DesignMetrics.Spacing.s5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label)\(item.required ? "" : ", opcional"). \(StatusIndicator.word(item.daemonState)). \(item.detail)")
    }

    /// Só o que falta tem botão: o que está pronto não precisa de ação.
    @ViewBuilder
    private var botao: some View {
        if item.daemonState != .ok && item.daemonState != .busy {
            if let alvo = item.install {
                Button("Instalar no Terminal…") { install(alvo) }
                    .controlSize(.small)
                    .accessibilityLabel("Instalar \(item.label) no Terminal")
            } else if let link = item.link {
                Button(HomeCopy.linkTitle(link)) { open(link) }
                    .controlSize(.small)
            }
        }
    }
}

/// Cor de cada estado de checagem, a mesma do cartão de diagnóstico.
enum HomeStateStyle {
    static func color(_ status: DaemonState, _ theme: any ThemeTokens) -> Color {
        switch status {
        case .ok: return theme.success
        case .warn: return theme.warning
        case .error: return theme.destructive
        case .busy: return theme.info
        case .off: return theme.labelTertiary
        }
    }
}
