import AppKit
import SwiftUI

/// Aba Execução (B1, 3.23.0, ⌘6): roda o `main` do projeto de automação do
/// dono, como a run configuration do PyCharm faria.
///
/// Cabeçalho com o projeto, banner do último resultado, barra Rodar/Parar e,
/// embaixo, a coluna Projeto (o `main` resumido, sem executar nada) ao lado
/// de Doctor e Console. Em coluna estreita, `AdaptivePair` troca o lado a lado
/// por abas; Doctor e Console dividem a altura com `VerticalSplit` (nada de
/// `HSplitView`/`VSplitView` dentro da NavigationSplitView, ver D1).
struct ExecutionView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    /// Abaixo disto, Projeto e Doctor/Console viram abas.
    static let minSideBySide: CGFloat = 720

    var body: some View {
        let ex = appState.execution
        Group {
            // Rodando sem projeto atual (execução achada pelo `run.status`):
            // a barra com Parar continua à vista (revisão FR-03).
            if ex.currentProject == nil && !ex.isRunning {
                ExecutionEmptyView()
            } else {
                VStack(spacing: 0) {
                    ExecutionHeader()
                    if let resultado = ex.lastResult, !ex.isRunning {
                        ExecutionResultBanner(summary: ExecutionResultSummary(resultado)) {
                            withAnimation(Motion.smooth()) { ex.lastResult = nil }
                        }
                        .transition(.opacity)
                    }
                    ExecutionRunBar()
                    if let erro = ex.error {
                        InlineError(title: "Não deu.", text: erro, actionLabel: "Dispensar") { ex.error = nil }
                            .padding(.horizontal, DesignMetrics.Spacing.s5)
                            .padding(.bottom, DesignMetrics.Spacing.s4)
                    }
                    Rectangle().fill(themeManager.current.separator).frame(height: 1)
                    AdaptivePair(labels: ("Projeto", "Doctor e Console"), minSideBySide: Self.minSideBySide) {
                        ExecutionProjectColumn()
                    } second: {
                        VerticalSplit(storageKey: "execucaoDoctor", topHeight: 96...480, idealTopHeight: 230,
                                      minBottomHeight: 120) {
                            ExecutionDoctorPanel()
                        } bottom: {
                            ExecutionConsolePanel()
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .animation(Motion.smooth(), value: ex.lastResult?.runId)
                .animation(Motion.crossfade, value: ex.error)
            }
        }
        .background(themeManager.current.bgContent)
        .task(id: session.isConnected) {
            if session.isConnected { await session.loadExecution() }
        }
        .sheet(item: Binding(get: { ex.confirmation }, set: { ex.confirmation = $0 })) { pedido in
            ExecutionConfirmationSheet(confirmation: pedido)
                .environment(appState).environment(session).environment(themeManager)
                .tint(themeManager.current.accent)
        }
    }
}

// MARK: - Abrir projeto

enum ExecutionPanels {
    /// Só pasta: o projeto que o dono abre no PyCharm.
    @MainActor
    static func chooseProjectFolder() -> URL? {
        let painel = NSOpenPanel()
        painel.title = "Abrir Projeto de Automação"
        painel.message = "Escolha a pasta do projeto que você roda no PyCharm (a que tem o main.py)."
        painel.prompt = "Abrir"
        painel.canChooseDirectories = true
        painel.canChooseFiles = false
        painel.allowsMultipleSelection = false
        return painel.runModal() == .OK ? painel.url : nil
    }

    /// Um executável Python. Sem resolver o link: `.venv/bin/python` aponta
    /// para o Python do sistema, e resolvido perderia o venv (o motor guarda
    /// o caminho como veio).
    @MainActor
    static func chooseInterpreter(startingAt root: String?) -> URL? {
        let painel = NSOpenPanel()
        painel.title = "Escolher Interpretador"
        painel.message = "Escolha o python do projeto (por exemplo, .venv/bin/python)."
        painel.prompt = "Escolher"
        painel.canChooseDirectories = false
        painel.canChooseFiles = true
        painel.allowsMultipleSelection = false
        painel.resolvesAliases = false
        painel.showsHiddenFiles = true
        painel.treatsFilePackagesAsDirectories = true
        if let root { painel.directoryURL = URL(fileURLWithPath: root, isDirectory: true) }
        return painel.runModal() == .OK ? painel.url : nil
    }
}

/// Sem projeto: uma frase e a ação, e os projetos já abertos.
struct ExecutionEmptyView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        let ex = appState.execution
        VStack(spacing: 0) {
            EmptyState(
                icon: "play.rectangle.on.rectangle",
                title: "Nenhum projeto aberto",
                text: "Abra a pasta do projeto de automação que você roda no PyCharm. O Mo baile lê o main sem "
                    + "executar nada e mostra configs, suítes e o que falta para rodar.",
                actionLabel: session.isConnected ? "Abrir Projeto…" : nil,
                action: session.isConnected ? { abrir() } : nil,
                loading: ex.operation == .loading || ex.operation == .opening
            )
            .frame(maxHeight: 320)
            if !ex.projects.isEmpty {
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
                    Text("Abertos antes")
                        .font(DSFont.subheadlineSemibold)
                        .foregroundStyle(theme.labelSecondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(ex.projects) { projeto in
                        Button {
                            Task { await session.openProject(path: projeto.root) }
                        } label: {
                            HStack(spacing: DesignMetrics.Spacing.s4) {
                                Image(systemName: "folder")
                                    .foregroundStyle(WorkspaceTab.execution.categoryColor(theme))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(projeto.name).font(DSFont.body).foregroundStyle(theme.labelPrimary)
                                    Text(ExecutionCopy.abbreviate(projeto.root))
                                        .font(DSFont.mono(11)).foregroundStyle(theme.labelSecondary)
                                        .truncationMode(.middle)
                                }
                                .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!session.isConnected || ex.operation != nil)
                        .help("Abrir \(projeto.root)")
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
                .dsCard()
                .padding(.horizontal, DesignMetrics.Spacing.s9)
            }
            if let erro = ex.error {
                InlineError(title: "Não deu.", text: erro)
                    .frame(maxWidth: 420)
                    .padding(.top, DesignMetrics.Spacing.s5)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func abrir() {
        guard let url = ExecutionPanels.chooseProjectFolder() else { return }
        Task { await session.openProject(path: url.path) }
    }
}

// MARK: - Cabeçalho

/// Projeto atual, recentes, Abrir Projeto… e Esquecer.
struct ExecutionHeader: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        let ex = appState.execution
        let bloqueio = ex.projectLockReason
        let livre = session.isConnected && bloqueio == nil
        HStack(spacing: DesignMetrics.Spacing.s5) {
            Image(systemName: "folder.fill")
                .font(.system(size: 18))
                .foregroundStyle(WorkspaceTab.execution.categoryColor(theme))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Text(ex.currentProject?.name ?? "")
                        .font(DSFont.headline)
                        .foregroundStyle(theme.labelPrimary)
                    if ex.currentProject?.trusted == true {
                        Label("Confiável", systemImage: "checkmark.shield")
                            .font(DSFont.footnote)
                            .foregroundStyle(theme.labelSecondary)
                            .help("Você já confirmou que este projeto pode rodar nesta máquina")
                    }
                    if ex.operation == .inspecting || ex.operation == .configuring {
                        ProgressView().controlSize(.mini).accessibilityLabel("Lendo o projeto")
                    }
                }
                Text(ExecutionCopy.abbreviate(ex.currentProject?.root ?? ""))
                    .font(DSFont.mono(11))
                    .foregroundStyle(theme.labelSecondary)
                    .truncationMode(.middle)
                    .help(ex.currentProject?.root ?? "")
            }
            .lineLimit(1)
            .frame(minWidth: 80, alignment: .leading)
            .layoutPriority(-1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Projeto \(ex.currentProject?.name ?? "")")

            Spacer(minLength: DesignMetrics.Spacing.s4)

            Menu {
                ForEach(ex.projects) { projeto in
                    Button {
                        Task { await session.openProject(path: projeto.root) }
                    } label: {
                        Text(projeto.id == ex.currentProjectID ? "\(projeto.name) (atual)" : projeto.name)
                    }
                    .disabled(projeto.id == ex.currentProjectID)
                }
                if ex.projects.isEmpty { Text("Nenhum projeto aberto antes") }
            } label: {
                Label("Recentes", systemImage: "clock")
            }
            .fixedSize()
            .disabled(!livre)
            .help(bloqueio ?? "Projetos já abertos")

            Button {
                guard let url = ExecutionPanels.chooseProjectFolder() else { return }
                Task { await session.openProject(path: url.path) }
            } label: {
                Label("Abrir Projeto…", systemImage: "folder.badge.plus")
            }
            .fixedSize()
            .disabled(!livre)
            .help(bloqueio ?? "Abre outra pasta de projeto")

            Button {
                Task { await session.forgetCurrentProject() }
            } label: {
                Label("Esquecer", systemImage: "minus.circle")
            }
            .labelStyle(.iconOnly)
            .disabled(!livre)
            .help(bloqueio ?? "Esquecer: tira o projeto da lista. Nada na pasta dele é apagado.")
            .accessibilityLabel("Esquecer Projeto")
        }
        .controlSize(.small)
        .padding(.horizontal, DesignMetrics.Spacing.s5)
        .padding(.vertical, DesignMetrics.Spacing.s4)
        .frame(minHeight: 48)
    }
}

// MARK: - Barra Rodar

/// Aparelho alvo, Gravar vídeo, tempo decorrido e Rodar/Parar.
struct ExecutionRunBar: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.controlActiveState) private var estadoDaJanela

    var body: some View {
        let theme = themeManager.current
        let ex = appState.execution
        let bloqueio = ex.isRunning ? nil : ex.runBlockReason(engineConnected: session.isConnected)
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            HStack(spacing: DesignMetrics.Spacing.s5) {
                if let ativa = ex.activeRun {
                    // Rodando, o menu desabilitado não basta: o aparelho em uso
                    // fica escrito (revisão FR-06).
                    Label("Rodando em \(nomeDoAparelho(ativa.deviceId))", systemImage: "iphone")
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(minWidth: 80, alignment: .leading)
                        .layoutPriority(-1)
                        .help("Aparelho da execução: \(ativa.deviceId ?? "o motor decidiu")")
                        .accessibilityLabel("Aparelho alvo")
                        .accessibilityValue(nomeDoAparelho(ativa.deviceId))
                } else {
                // Menu, e não Picker: o pop-up do Picker sumia na aparência
                // clara das capturas, e o Menu é o mesmo controle de Recentes.
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Text("Aparelho").font(DSFont.body).foregroundStyle(theme.labelPrimary).fixedSize()
                    Menu {
                        Toggle(rotuloAutomatico(ex), isOn: Binding(
                            get: { ex.targetDeviceID == nil }, set: { if $0 { ex.targetDeviceID = nil } }
                        ))
                        if !appState.availableDevices.isEmpty { Divider() }
                        ForEach(appState.availableDevices, id: \.id) { device in
                            Toggle(device.name.isEmpty ? device.id : device.name, isOn: Binding(
                                get: { ex.targetDeviceID == device.id }, set: { if $0 { ex.targetDeviceID = device.id } }
                            ))
                        }
                    } label: {
                        Label(rotuloAlvo(ex), systemImage: "iphone")
                    }
                    // Largura do rótulo, como Recentes: com largura flexível o
                    // pop-up não era desenhado na aparência clara.
                    .fixedSize()
                    .accessibilityLabel("Aparelho alvo")
                    .accessibilityValue(rotuloAlvo(ex))
                }
                .disabled(ex.isRunning)
                .help("Aparelho onde o main roda. Automático: o udid da config ativa, senão o aparelho escolhido no app.")
                }

                Toggle("Gravar vídeo", isOn: Binding(get: { ex.recordVideo }, set: { ex.recordVideo = $0 }))
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .disabled(ex.isRunning)
                    .help("Grava a tela do aparelho junto com a execução (video.mp4 na pasta da execução)")

                Spacer(minLength: DesignMetrics.Spacing.s4)

                if let ativa = ex.activeRun {
                    TimelineView(.periodic(from: ativa.startedAt, by: 1)) { contexto in
                        let decorrido = ExecutionResultSummary.elapsed(contexto.date.timeIntervalSince(ativa.startedAt))
                        Text(decorrido)
                            .font(DSFont.mono(12).monospacedDigit())
                            .foregroundStyle(theme.labelSecondary)
                            // Rótulo e valor: só o rótulo apagava o tempo do
                            // leitor de tela (revisão FR-10).
                            .accessibilityLabel("Tempo decorrido")
                            .accessibilityValue(decorrido)
                    }
                    .fixedSize()
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                }

                if ex.isRunning {
                    Button(role: .destructive) {
                        Task { await session.stopRun() }
                    } label: {
                        Label(ex.stopping ? "Parando…" : "Parar", systemImage: "stop.fill")
                    }
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(ex.stopping)
                    .help("Para o main e os processos que ele abriu")
                } else {
                    let pode = bloqueio == nil
                    Button {
                        Task { await session.startRun() }
                    } label: {
                        Label(ex.starting ? "Iniciando…" : "Rodar", systemImage: "play.fill")
                    }
                    .mbProminentGlassButton(pode && !ex.starting && estadoDaJanela != .inactive)
                    .fixedSize()
                    .disabled(!pode || ex.starting)
                    .help(bloqueio ?? "Roda o main do projeto, como a run configuration do PyCharm")
                }
            }
            if let bloqueio {
                Label(bloqueio, systemImage: "lock.fill")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let aviso = ex.activeRun?.videoWarning {
                Label(aviso, systemImage: "video.slash")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DesignMetrics.Spacing.s5)
        .padding(.vertical, DesignMetrics.Spacing.s4)
    }

    private func nomeDoAparelho(_ id: String?) -> String {
        guard let id else { return "aparelho escolhido pelo motor" }
        let nome = appState.availableDevices.first { $0.id == id }?.name
        return (nome?.isEmpty == false ? nome : nil) ?? id
    }

    /// Curto: o menu tem a largura do rótulo.
    private func rotuloAlvo(_ ex: ExecutionState) -> String {
        guard let alvo = ex.targetDeviceID else { return rotuloAutomatico(ex) }
        let nome = appState.availableDevices.first { $0.id == alvo }?.name
        let texto = (nome?.isEmpty == false ? nome : nil) ?? alvo
        return texto.count > 28 ? String(texto.prefix(27)) + "…" : texto
    }

    private func rotuloAutomatico(_ ex: ExecutionState) -> String {
        if let udid = ex.inspection?.activeConfiguration?.values["udid"], udid != "dinâmico" {
            return "Automático (\(udid))"
        }
        return "Automático"
    }
}

// MARK: - Resultado

/// Banner do `run.finished`: Passou, Falhou, Indeterminado ou Cancelado.
struct ExecutionResultBanner: View {
    @Environment(ThemeManager.self) private var themeManager
    let summary: ExecutionResultSummary
    let onDismiss: () -> Void

    var body: some View {
        let theme = themeManager.current
        HStack(alignment: .top, spacing: DesignMetrics.Spacing.s5) {
            Image(systemName: summary.symbol)
                .font(DSFont.Symbol.banner)
                .foregroundStyle(cor(theme))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
                HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
                    Text(summary.title)
                        .font(DSFont.headline)
                        .foregroundStyle(theme.labelPrimary)
                    if let duracao = summary.duration {
                        Text(duracao).font(DSFont.mono(11)).foregroundStyle(theme.labelSecondary)
                    }
                    if let mensagem = summary.message {
                        Text(mensagem)
                            .font(DSFont.callout)
                            .foregroundStyle(theme.labelSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(mensagem)
                    }
                }
                if !summary.counts.isEmpty {
                    Text(summary.counts.joined(separator: " · "))
                        .font(DSFont.callout.monospacedDigit())
                        .foregroundStyle(theme.labelPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let aviso = summary.videoWarning {
                    Label(aviso, systemImage: "video.slash")
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(1)
                        .help(aviso)
                }
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            VStack(alignment: .trailing, spacing: DesignMetrics.Spacing.s3) {
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Button {
                        if let pasta = summary.folder { NSWorkspace.shared.open(URL(fileURLWithPath: pasta, isDirectory: true)) }
                    } label: {
                        Label("Abrir Pasta da Execução", systemImage: "folder")
                    }
                    .disabled(summary.folder == nil)
                    .help(summary.folder ?? "Sem pasta da execução")
                    Button {
                        if let video = summary.video { NSWorkspace.shared.open(URL(fileURLWithPath: video)) }
                    } label: {
                        Label("Abrir Vídeo", systemImage: "play.rectangle")
                    }
                    .disabled(summary.video == nil)
                    .help(summary.video == nil ? (summary.videoWarning ?? "Sem vídeo nesta execução") : "Abre o video.mp4")
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Dispensar o resultado")
                    .accessibilityLabel("Dispensar Resultado")
                }
                .labelStyle(AdaptiveLabelStyle())
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.horizontal, DesignMetrics.Spacing.s5)
        .padding(.vertical, DesignMetrics.Spacing.s4)
        .background(fundo(theme), in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))
        .padding(.horizontal, DesignMetrics.Spacing.s5)
        .padding(.top, DesignMetrics.Spacing.s2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Resultado: \(summary.title)")
    }

    private func cor(_ theme: any ThemeTokens) -> Color {
        switch summary.kind {
        case .passed: return theme.success
        case .failed: return theme.destructive
        case .indeterminate: return theme.warning
        case .cancelled: return theme.labelSecondary
        }
    }

    private func fundo(_ theme: any ThemeTokens) -> Color {
        switch summary.kind {
        case .passed: return theme.successTint
        case .failed: return theme.dangerTint
        case .indeterminate: return theme.warningTint
        case .cancelled: return theme.fillQuaternary
        }
    }
}

/// Ícone e título com folga; só o ícone (e o tooltip) quando a coluna aperta.
private struct AdaptiveLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { configuration.icon; configuration.title }
            configuration.icon
        }
    }
}

// MARK: - Confirmações

/// "Confiar neste projeto?" (antes de rodar ou de verificar) e "Rodar mesmo
/// assim?" (hub não confirmado).
struct ExecutionConfirmationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    let confirmation: ExecutionConfirmation

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
            HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
                Image(systemName: icone)
                    .font(DSFont.Symbol.banner)
                    .foregroundStyle(theme.warning)
                    .accessibilityHidden(true)
                Text(titulo)
                    .font(DSFont.title3)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            switch confirmation {
            case .trust(let pedido):
                Text("Rodar executa o código de \(pedido.projectName) nesta máquina, com as suas permissões, "
                     + "como o PyCharm faz. Confie só em projetos que você conhece.")
                    .font(DSFont.body)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: DesignMetrics.Spacing.s5, verticalSpacing: DesignMetrics.Spacing.s3) {
                    linha("Interpretador", pedido.interpreter ?? "não encontrado")
                    linha("Arquivo de entrada", pedido.entry ?? "não encontrado")
                    linha("Pasta de trabalho", pedido.workingDir ?? "")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard(padding: DesignMetrics.Spacing.s5)
            case .unknownHub(let mensagem, _):
                Text("Não consegui provar que a config ativa roda só nesta máquina. Rodar mesmo assim?")
                    .font(DSFont.body)
                    .foregroundStyle(theme.labelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(mensagem)
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) {
                    appState.execution.confirmation = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(confirmar) {
                    let pedido = confirmation
                    Task { await session.confirmExecutionDialog(pedido) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignMetrics.Spacing.windowMargin)
        .frame(width: 480)
    }

    private var titulo: String {
        switch confirmation {
        case .trust: return "Confiar neste projeto?"
        case .unknownHub: return "Rodar mesmo assim?"
        }
    }

    private var icone: String {
        switch confirmation {
        case .trust: return "checkmark.shield"
        case .unknownHub: return "questionmark.circle"
        }
    }

    private var confirmar: String {
        switch confirmation {
        case .trust(let pedido): return pedido.then == .run ? "Confiar e Rodar" : "Confiar e Verificar"
        case .unknownHub: return "Rodar Mesmo Assim"
        }
    }

    @ViewBuilder
    private func linha(_ rotulo: String, _ valor: String) -> some View {
        let theme = themeManager.current
        GridRow {
            Text(rotulo).font(DSFont.callout).foregroundStyle(theme.labelSecondary)
            Text(valor)
                .font(DSFont.mono(11))
                .foregroundStyle(theme.labelPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(valor)
        }
    }
}
