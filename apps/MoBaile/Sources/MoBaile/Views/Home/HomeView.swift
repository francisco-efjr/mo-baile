import AppKit
import SwiftUI

/// Tela Início: o que está pronto, o que falta instalar e o caminho para as
/// áreas. É onde o app abre na primeira vez e sempre que não há aparelho.
///
/// Três blocos, de cima para baixo: o próximo passo (um só, em destaque), as
/// áreas com o estado de cada plataforma, e o Ambiente item a item. O estado
/// vem do motor (`setup.check`); quando o motor não sobe, a tela ainda diz o
/// que falta, porque o que falta é justamente o Python dele.
/// Maquete: `docs/design/home/home-maquete.html`.
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
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    @AppStorage(LaunchDestination.seenKey) private var jaVisto = false
    /// Título de boas-vindas só na primeira visita; ele não muda enquanto a
    /// tela está aberta, mesmo depois de `jaVisto` virar `true`.
    @State private var primeiraVisita: Bool?
    @State private var erroInstalacao: String?

    private var theme: any ThemeTokens { themeManager.current }

    private var passo: HomeNextStep {
        HomeNextStep.pick(
            engineStatus: session.engineStatus,
            lastError: session.lastError,
            setup: session.setup,
            deviceName: appState.isDeviceConnected ? appState.selectedDeviceName : nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s9) {
            cabecalho
            HomeNextStepCard(passo: passo, pending: session.setup?.pending ?? 0,
                             install: instalar, erro: erroInstalacao)
            areas
            ambiente
            Text(HomeCopy.note)
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelSecondary)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, DesignMetrics.Spacing.windowMargin)
        .padding(.top, 28)
        .padding(.bottom, DesignMetrics.Spacing.windowMargin)
        .frame(maxWidth: .infinity)
        .onAppear {
            if primeiraVisita == nil { primeiraVisita = !jaVisto }
            jaVisto = true
        }
        .task { await conferir(seMaisVelhoQue: 0) }
        // Quem instala pelo Terminal volta ao app: confere de novo sem pedir.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await conferir(seMaisVelhoQue: 3) }
        }
    }

    // MARK: - Cabeçalho

    private var cabecalho: some View {
        HStack(alignment: .center, spacing: DesignMetrics.Spacing.s6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text(primeiraVisita == true ? "Boas-vindas ao Mo baile" : "Mo baile")
                    .font(DSFont.title1.weight(.bold))
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(HomeCopy.summary(passo, pending: session.setup?.pending ?? 0))
                    .font(DSFont.body)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DesignMetrics.Spacing.s4)
            VStack(alignment: .trailing, spacing: DesignMetrics.Spacing.s1) {
                Button {
                    Task {
                        await session.refreshEnvironment()
                        await session.refreshDevices()
                    }
                } label: {
                    Label("Verificar de Novo", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PlainTextButtonStyle(theme: theme))
                .controlSize(.small)
                .disabled(!session.isConnected)
                if let quando = session.lastSetupCheck {
                    Text("verificado às \(quando.formatted(date: .omitted, time: .shortened))")
                        .font(DSFont.mono(10.5))
                        .foregroundStyle(theme.labelSecondary)
                }
            }
        }
    }

    // MARK: - Áreas

    private var areas: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            Text("Áreas")
                .font(DSFont.headline)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            // Quatro lado a lado, da mesma altura: a coluna de conteúdo nunca
            // fica estreita a ponto de precisar quebrar em duas linhas.
            HStack(alignment: .top, spacing: DesignMetrics.Spacing.s5) {
                ForEach(WorkspaceTab.workspaceAreas) { area in
                    HomeAreaTile(area: area, feature: session.setup?.features.first { $0.tab == area }) {
                        appState.selectedStepID = nil
                        appState.workspaceTab = area
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Ambiente

    private var ambiente: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
            Text("Ambiente")
                .font(DSFont.headline)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            if let setup = session.setup, session.isConnected {
                ForEach(setup.groups) { grupo in
                    HomeComponentGroup(title: grupo.title, components: grupo.components,
                                       install: instalar, open: abrir)
                }
            } else {
                // Sem motor, só o Python é verificável: é ele que falta.
                HomeComponentGroup(title: "Motor", components: [componentePython],
                                   install: instalar, open: abrir)
                Text("O resto é conferido quando o motor subir.")
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.labelSecondary)
            }
        }
    }

    private var componentePython: EngineDTO.SetupComponent {
        let detalhe: String
        let estado: String
        switch passo {
        case .installPython(let motivo): detalhe = motivo; estado = "error"
        case .engineStopped(let motivo): detalhe = motivo; estado = "warn"
        default: detalhe = "Subindo o motor…"; estado = "busy"
        }
        return EngineDTO.SetupComponent(
            id: "python", label: "Python 3.10 ou mais novo", state: estado, detail: detalhe,
            required: true, install: estado == "error" ? "python" : nil, link: nil, neededFor: "o motor"
        )
    }

    // MARK: - Ações

    private func conferir(seMaisVelhoQue segundos: TimeInterval) async {
        guard session.isConnected else { return }
        if let ultima = session.lastSetupCheck, Date().timeIntervalSince(ultima) < segundos { return }
        await session.refreshSetup()
    }

    private func instalar(_ alvo: String) {
        do {
            // O Python do motor recebe os pacotes; sem motor, o script cria o do Mo baile.
            try SetupInstaller.openInTerminal(target: alvo, python: session.isConnected ? session.setup?.python.path : nil)
            erroInstalacao = nil
            appState.statusMessage = "Instalação aberta no Terminal"
        } catch {
            erroInstalacao = error.localizedDescription
        }
    }

    private func abrir(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
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

// MARK: - Área

/// Atalho para uma área, com o estado dela em cada plataforma.
struct HomeAreaTile: View {
    @Environment(ThemeManager.self) private var themeManager
    let area: WorkspaceTab
    let feature: EngineDTO.SetupFeature?
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        let theme = themeManager.current
        Button(action: action) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
                Image(systemName: area.symbolName)
                    .font(.system(size: 17))
                    .foregroundStyle(area.categoryColor(theme))
                    .accessibilityHidden(true)
                Text(area.displayName)
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                Text(HomeCopy.areaSummary(area))
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 28, alignment: .topLeading)
                if let feature {
                    ForEach(feature.platforms, id: \.platform) { linha in
                        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s2) {
                            Image(systemName: DiagnosticCard.symbol(linha.daemonState))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(HomeStateStyle.color(linha.daemonState, theme))
                            Text(rotulo(linha))
                                .font(DSFont.subheadline)
                                .foregroundStyle(theme.labelSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("Conferindo…")
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelTertiary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
            .dsCard(padding: DesignMetrics.Spacing.s6)
            .background(hover ? theme.fillQuaternary : .clear,
                        in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Ir para \(area.displayName)")
        .accessibilityLabel(area.displayName)
        .accessibilityValue(feature.map { $0.platforms.map(rotulo).joined(separator: ", ") } ?? "")
        .accessibilityHint("Abre a área")
    }

    private func rotulo(_ linha: EngineDTO.SetupFeature.PlatformState) -> String {
        let nome = HomeCopy.platformName(linha.platform)
        return nome.isEmpty ? linha.detail : "\(nome) · \(linha.detail)"
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
