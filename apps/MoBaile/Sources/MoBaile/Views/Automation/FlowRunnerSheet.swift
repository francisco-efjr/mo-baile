import SwiftUI

/// Sheet "Executar fluxo": progresso, passos e o stdout do runner.
///
/// Interromper é destrutivo e nunca é o botão padrão. Concluir fica
/// desabilitado até o fim. O rodapé conta o que aconteceu de fato: a versão
/// anterior dizia "aprovados" contando os passos gravados, e o tempo era a
/// string fixa "0.0 s".
struct FlowRunnerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = themeManager.current
        let rodando = appState.runState == .running

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Executar fluxo · \(session.engineInfo?.pageObjectsKey ?? "fluxo")")
                    .font(DSFont.headline)
                StatusIndicator(status: badge.status, label: badge.texto, mono: false)
                Spacer()
                if appState.platform == .android {
                    StatusIndicator(status: appState.daemonStatus.adb, label: "ADB")
                } else {
                    StatusIndicator(status: appState.daemonStatus.wda, label: wdaLabel)
                }
                StatusIndicator(status: appState.daemonStatus.proxy, label: proxyLabel)
            }
            .padding(.bottom, 10)

            HStack(spacing: 10) {
                ProgressBar(value: progresso, tint: corDoProgresso)
                Text("passo \(passoAtual) de \(appState.steps.count)")
                    .font(DSFont.subheadline.monospacedDigit())
                    .foregroundStyle(theme.labelSecondary)
            }
            .padding(.bottom, 14)

            HStack(alignment: .top, spacing: 12) {
                listaDePassos
                    .frame(width: 280)
                terminal
            }
            .frame(height: 300)

            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { contexto in
                    Text(resumo(agora: contexto.date))
                        .font(DSFont.callout.monospacedDigit())
                        .foregroundStyle(theme.labelSecondary)
                }
                Spacer()
                Button {
                    Exporters.openRunLog(appState)
                } label: {
                    Label("Abrir Log", systemImage: "terminal")
                }
                .disabled(appState.runLog.isEmpty)
                if rodando {
                    Button("Interromper", role: .destructive) {
                        Task { await session.stopFlow() }
                    }
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Interromper (⌘.)")
                }
                Button("Concluir") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rodando)
                    .frame(minWidth: 84)
            }
            .padding(.top, 20)
        }
        .padding(DesignMetrics.Spacing.windowMargin)
        .frame(width: 820)
        .interactiveDismissDisabled(rodando)
    }

    // MARK: - Partes

    private var listaDePassos: some View {
        let theme = themeManager.current
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(appState.steps.enumerated()), id: \.element.id) { indice, passo in
                    let estado = estadoDoPasso(indice + 1)
                    HStack(spacing: 8) {
                        icone(estado)
                            .frame(width: 14)
                        Text("\(passo.actionType) \(passo.displayElement)")
                            .font(DSFont.body)
                            .foregroundStyle(estado == .pendente ? theme.labelSecondary : theme.labelPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        if let mascara = passo.maskedInput {
                            Text(mascara)
                                .font(DSFont.mono(11))
                                .foregroundStyle(theme.labelSecondary)
                                .accessibilityLabel("texto digitado oculto")
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: DesignMetrics.Radius.row)
                            .fill(estado == .rodando ? theme.selectionContent : .clear)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(estado.descricao)
                }
            }
            .padding(4)
        }
        .background(theme.bgContent, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.separator, lineWidth: 0.5))
    }

    private var terminal: some View {
        let theme = themeManager.current
        return VStack(spacing: 0) {
            HStack {
                Text(".flow_runner.py")
                Spacer()
                Text("stdout · streaming")
            }
            .font(DSFont.mono(10.5))
            .foregroundStyle(TerminalPalette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(TerminalPalette.rule).frame(height: 1) }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appState.runLog) { line in
                            (Text(line.timestamp.formatted(date: .omitted, time: .standard)).foregroundColor(TerminalPalette.dim)
                                + Text(" [\(line.prefix)] ").foregroundColor(TerminalPalette.color(forPrefix: line.prefix))
                                + Text(line.message).foregroundColor(TerminalPalette.text))
                                .font(DSFont.mono(11))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onChange(of: appState.runLog.count) {
                    if let lastId = appState.runLog.last?.id {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
        .background(theme.bgTerminal, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Saída do runner")
    }

    // MARK: - Estado

    enum EstadoDoPasso {
        case ok, falhou, rodando, pendente
        var descricao: String {
            switch self {
            case .ok: return "aprovado"
            case .falhou: return "falhou"
            case .rodando: return "em execução"
            case .pendente: return "pendente"
            }
        }
    }

    private func estadoDoPasso(_ numero: Int) -> EstadoDoPasso {
        switch appState.runState {
        case .passed: return .ok
        case .running:
            if numero < appState.currentRunStep { return .ok }
            return numero == appState.currentRunStep ? .rodando : .pendente
        case .failed:
            if numero < appState.currentRunStep { return .ok }
            return numero == appState.currentRunStep ? .falhou : .pendente
        case .idle:
            return .pendente
        }
    }

    @ViewBuilder
    private func icone(_ estado: EstadoDoPasso) -> some View {
        let theme = themeManager.current
        switch estado {
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.success)
        case .falhou:
            Image(systemName: "xmark.circle.fill").foregroundStyle(theme.destructive)
        case .rodando:
            ProgressView().controlSize(.mini)
        case .pendente:
            Image(systemName: "circle.dotted").foregroundStyle(theme.labelTertiary)
        }
    }

    private var aprovados: Int {
        switch appState.runState {
        case .passed: return appState.steps.count
        case .running, .failed: return max(0, appState.currentRunStep - 1)
        case .idle: return 0
        }
    }

    private var passoAtual: Int {
        min(max(appState.currentRunStep, appState.runState == .passed ? appState.steps.count : 0), appState.steps.count)
    }

    private var progresso: Double {
        guard !appState.steps.isEmpty else { return 0 }
        return Double(aprovados) / Double(appState.steps.count)
    }

    private var corDoProgresso: Color? {
        let theme = themeManager.current
        switch appState.runState {
        case .failed: return theme.destructive
        case .passed: return theme.success
        default: return nil
        }
    }

    private var badge: (texto: String, status: DaemonState) {
        switch appState.runState {
        case .running: return ("Em execução", .busy)
        case .passed: return ("Concluído", .ok)
        case .failed: return ("Falha", .error)
        case .idle: return ("Pronto", .off)
        }
    }

    /// Tempo do primeiro ao último registro do runner; enquanto roda, até agora.
    private func resumo(agora: Date) -> String {
        let falhas = appState.runState == .failed ? 1 : 0
        var segundos = 0.0
        if let inicio = appState.runLog.first?.timestamp {
            let fim = appState.runState == .running ? agora : (appState.runLog.last?.timestamp ?? inicio)
            segundos = max(0, fim.timeIntervalSince(inicio))
        }
        let tempo = String(format: "%.1f", segundos).replacingOccurrences(of: ".", with: ",")
        return "\(aprovados) aprovados · \(falhas) \(falhas == 1 ? "falha" : "falhas") · tempo \(tempo) s"
    }

    private var wdaLabel: String {
        guard let url = session.engineInfo?.wdaUrl, let port = URL(string: url)?.port else { return "WDA" }
        return "WDA \(port)"
    }

    private var proxyLabel: String {
        guard let proxy = session.engineInfo?.proxy else { return "Proxy" }
        return "Proxy \(proxy.port)"
    }
}
