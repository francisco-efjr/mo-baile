import SwiftUI

/// Coluna Projeto: o `main` resumido, sem executar nada. Entrada,
/// interpretador, configs (a ativa destacada, as comentadas em segundo plano),
/// suítes com as features e os cenários, e os problemas da análise.
struct ExecutionProjectColumn: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let ex = appState.execution
        ScrollView {
            if let leitura = ex.inspection {
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s8) {
                    ExecutionEntrySection(inspection: leitura)
                    ExecutionInterpreterSection(inspection: leitura)
                    ExecutionConfigsSection(inspection: leitura)
                    ExecutionSuitesSection(inspection: leitura)
                    if !leitura.problems.isEmpty {
                        ExecutionProblemsSection(problems: leitura.problems)
                    }
                }
                .padding(DesignMetrics.Spacing.s7)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if ex.operation != nil {
                EmptyState(icon: "doc.text.magnifyingglass", text: "Lendo o main do projeto…", loading: true, compact: true)
                    .padding(.top, DesignMetrics.Spacing.s10)
            } else {
                // A leitura foi interrompida (sair da aba, motor reiniciando):
                // sempre há saída (revisão FR-01).
                EmptyState(icon: "doc.text.magnifyingglass", text: "O main do projeto ainda não foi lido.",
                           actionLabel: session.isConnected ? "Ler o Projeto" : nil,
                           action: { Task { await session.inspectProject(); await session.runDoctor() } },
                           compact: true)
                    .padding(.top, DesignMetrics.Spacing.s10)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Projeto")
    }
}

/// Título de seção da coluna.
struct ExecutionSectionTitle: View {
    @Environment(ThemeManager.self) private var themeManager
    let title: String
    var detail: String? = nil

    var body: some View {
        let theme = themeManager.current
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s3) {
            Text(title)
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.labelSecondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail).font(DSFont.subheadline).foregroundStyle(theme.labelTertiary).lineLimit(1)
            }
        }
    }
}

/// Selo pequeno (Ativa, Local, Nuvem (bloqueada)…).
struct ExecutionTag: View {
    let text: String
    var symbol: String? = nil
    let foreground: Color
    let background: Color

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).accessibilityHidden(true) }
            Text(text)
        }
        .font(DSFont.footnote.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 6)
        .frame(minHeight: 16)
        .background(background, in: Capsule())
        .fixedSize()
    }
}

// MARK: - Entrada

private struct ExecutionEntrySection: View {
    @Environment(ThemeManager.self) private var themeManager
    let inspection: EngineDTO.ProjectInspection

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            ExecutionSectionTitle(title: "Entrada")
            if inspection.entry.found, let arquivo = inspection.entry.file {
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Image(systemName: "doc.text").foregroundStyle(theme.labelSecondary).accessibilityHidden(true)
                    Text(arquivo).font(DSFont.mono(12)).foregroundStyle(theme.labelPrimary)
                    if let funcao = inspection.entry.function {
                        Text("→ \(funcao)()").font(DSFont.mono(12)).foregroundStyle(theme.accentText)
                    }
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            } else {
                Label("Não achei o arquivo de entrada (main.py, run.py ou __main__.py na raiz).",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pasta = inspection.workingDir {
                linha("Pasta de trabalho", ExecutionCopy.abbreviate(pasta), theme)
            }
            if let rc = inspection.runConfiguration {
                linha("Run configuration", rc.name ?? rc.file ?? "", theme)
                if !rc.envNames.isEmpty {
                    // Só os nomes: os valores ficam no motor.
                    linha("Variáveis (só nomes)", rc.envNames.joined(separator: ", "), theme)
                }
            }
        }
    }

    private func linha(_ rotulo: String, _ valor: String, _ theme: any ThemeTokens) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
            Text(rotulo).font(DSFont.callout).foregroundStyle(theme.labelSecondary).fixedSize()
            Text(valor)
                .font(DSFont.mono(11))
                .foregroundStyle(theme.labelPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(valor)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Interpretador

private struct ExecutionInterpreterSection: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    let inspection: EngineDTO.ProjectInspection

    var body: some View {
        let theme = themeManager.current
        let interp = inspection.interpreter
        let ex = appState.execution
        let ocupado = ex.operation != nil || ex.isRunning || ex.starting || !session.isConnected
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            ExecutionSectionTitle(title: "Interpretador", detail: ExecutionCopy.interpreterSource(interp.source))
            if let caminho = interp.path {
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Image(systemName: interp.exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(interp.exists ? theme.success : theme.destructive)
                        .accessibilityHidden(true)
                    Text(ExecutionCopy.abbreviate(caminho))
                        .font(DSFont.mono(11))
                        .foregroundStyle(theme.labelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(caminho)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(interp.exists ? "existe" : "não existe nesta máquina")
                if !interp.exists {
                    Text("Esse caminho não existe nesta máquina.")
                        .font(DSFont.callout).foregroundStyle(theme.destructive)
                }
            } else {
                Text("Nenhum interpretador encontrado na run configuration, no SDK do PyCharm nem em .venv/venv.")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !interp.usable && !interp.candidates.isEmpty {
                Text("Pythons desta máquina")
                    .font(DSFont.callout.weight(.semibold))
                    .foregroundStyle(theme.labelPrimary)
                    .padding(.top, DesignMetrics.Spacing.s2)
                ForEach(interp.candidates) { candidato in
                    HStack(spacing: DesignMetrics.Spacing.s4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidato.path).font(DSFont.mono(11)).foregroundStyle(theme.labelPrimary)
                                .lineLimit(1).truncationMode(.middle)
                            HStack(spacing: DesignMetrics.Spacing.s3) {
                                if let versao = candidato.version {
                                    Text("Python \(versao)").font(DSFont.subheadline).foregroundStyle(theme.labelSecondary)
                                }
                                if let behave = candidato.behave {
                                    Text("behave \(behave)").font(DSFont.subheadline).foregroundStyle(theme.success)
                                } else {
                                    Text("sem behave").font(DSFont.subheadline).foregroundStyle(theme.warning)
                                }
                            }
                        }
                        .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
                        Button("Usar") {
                            Task { await session.configureInterpreter(.string(candidato.path)) }
                        }
                        .controlSize(.small)
                        .disabled(ocupado)
                        .help("Usar \(candidato.path) neste projeto")
                        .accessibilityLabel("Usar \(candidato.path)")
                    }
                    .padding(DesignMetrics.Spacing.s4)
                    .background(theme.fillQuaternary, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
                }
            }
            HStack(spacing: DesignMetrics.Spacing.s4) {
                Button(interp.usable ? "Trocar…" : "Escolher…") {
                    guard let url = ExecutionPanels.chooseInterpreter(startingAt: inspection.project.root) else { return }
                    Task { await session.configureInterpreter(.string(url.path)) }
                }
                .help("Escolhe o python do projeto (por exemplo, .venv/bin/python)")
                if interp.isManual {
                    Button("Voltar à Detecção") {
                        Task { await session.configureInterpreter(.null) }
                    }
                    .help("Esquece a escolha e volta ao interpretador detectado")
                }
            }
            .controlSize(.small)
            .disabled(ocupado)
        }
    }
}

// MARK: - Configs

private struct ExecutionConfigsSection: View {
    @Environment(ThemeManager.self) private var themeManager
    let inspection: EngineDTO.ProjectInspection

    @State private var abertas: Set<String> = []

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            ExecutionSectionTitle(title: "Configs", detail: inspection.activeConfig.map { "ativa: \($0)" })
            if inspection.configs.isEmpty {
                Text(inspection.activeConfig == nil
                     ? "O main não tem init(...) ativo nem comentado."
                     : "Não achei a definição de \(inspection.activeConfig ?? "") nos arquivos do projeto.")
                    .font(DSFont.callout).foregroundStyle(theme.labelSecondary)
            }
            ForEach(inspection.configs) { config in
                ExecutionConfigCard(config: config, expanded: config.active || abertas.contains(config.id)) {
                    withAnimation(Motion.snappy()) {
                        if abertas.contains(config.id) { abertas.remove(config.id) } else { abertas.insert(config.id) }
                    }
                }
            }
        }
    }
}

private struct ExecutionConfigCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let config: EngineDTO.ProjectInspection.Config
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            HStack(spacing: DesignMetrics.Spacing.s3) {
                if !config.active {
                    Button(action: toggle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.labelSecondary)
                    .accessibilityLabel(expanded ? "Recolher \(config.name)" : "Expandir \(config.name)")
                }
                Text(config.name)
                    .font(DSFont.mono(12, weight: config.active ? .semibold : .regular))
                    .foregroundStyle(config.active ? theme.labelPrimary : theme.labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 40, alignment: .leading)
                    .layoutPriority(-1)
                Spacer(minLength: DesignMetrics.Spacing.s2)
                if config.active {
                    ExecutionTag(text: "Ativa", foreground: theme.onAccent, background: theme.accent)
                } else {
                    ExecutionTag(text: "Comentada", foreground: theme.labelSecondary, background: theme.fillSecondary)
                }
                hubTag(theme)
            }
            .accessibilityElement(children: .combine)
            Text(resumo)
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(config.orderedValues, id: \.key) { par in
                        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
                            Text(par.key)
                                .foregroundStyle(theme.accentText)
                                .frame(width: 118, alignment: .leading)
                            Text(par.value)
                                .foregroundStyle(par.value == "dinâmico" ? theme.labelTertiary : theme.labelPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(par.value)
                        }
                        .font(DSFont.mono(11))
                        .textSelection(.enabled)
                        .accessibilityElement(children: .combine)
                    }
                    let nomes = config.nameOnlyKeys
                    if !nomes.isEmpty {
                        // Chaves sensíveis (senha, token, usuário da nuvem) ficam
                        // só pelo nome: o valor nunca sai do motor.
                        (Text("Só pelo nome: ").foregroundColor(theme.labelSecondary)
                            + Text(nomes.joined(separator: ", ")).foregroundColor(theme.labelTertiary))
                            .font(DSFont.mono(10.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(DesignMetrics.Spacing.s5)
        .background(config.active ? theme.bgGroup : theme.fillQuaternary,
                    in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous)
                .strokeBorder(config.active ? theme.accent.opacity(0.55) : theme.separator,
                              lineWidth: config.active ? 1 : 0.5)
        )
        .opacity(config.active ? 1 : 0.86)
    }

    private var resumo: String {
        var partes: [String] = []
        if let p = ExecutionCopy.platform(config.platform) { partes.append(p) }
        if let hub = config.hub { partes.append(hub) }
        if let arquivo = config.file { partes.append(config.line.map { "\(arquivo):\($0)" } ?? arquivo) }
        if !config.found { partes.append("definição não encontrada") }
        return partes.joined(separator: " · ")
    }

    @ViewBuilder
    private func hubTag(_ theme: any ThemeTokens) -> some View {
        switch config.hubKind {
        case .local:
            ExecutionTag(text: "Local", foreground: theme.success, background: theme.successTint)
                .help("O hub desta config fica nesta máquina")
        case .cloud:
            ExecutionTag(text: "Nuvem (bloqueada)", symbol: "lock.fill", foreground: theme.destructive,
                         background: theme.dangerTint)
                .help("Config de nuvem (Kobiton ou hub fora desta máquina): esta versão não roda na nuvem")
        case .unknown:
            ExecutionTag(text: "Não confirmado", symbol: "questionmark", foreground: theme.warning,
                         background: theme.warningTint)
                .help("O motor não conseguiu provar que o hub desta config fica nesta máquina")
        }
    }
}

// MARK: - Suítes

private struct ExecutionSuitesSection: View {
    @Environment(ThemeManager.self) private var themeManager
    let inspection: EngineDTO.ProjectInspection

    var body: some View {
        let theme = themeManager.current
        let total = inspection.runCount
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
            ExecutionSectionTitle(title: "Suítes",
                                  detail: total == 0 ? nil : (total == 1 ? "1 execução" : "\(total) execuções"))
            if inspection.suites.isEmpty {
                Text("O main não chama nenhuma suíte com executar(squad, feature).")
                    .font(DSFont.callout).foregroundStyle(theme.labelSecondary)
            }
            ForEach(Array(inspection.suites.enumerated()), id: \.offset) { indice, suite in
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
                    HStack(spacing: DesignMetrics.Spacing.s3) {
                        Text("\(indice + 1).").font(DSFont.mono(11)).foregroundStyle(theme.labelTertiary)
                        Text(suite.name).font(DSFont.mono(12, weight: .semibold)).foregroundStyle(theme.labelPrimary)
                            .lineLimit(1).truncationMode(.middle)
                        if !suite.defined {
                            ExecutionTag(text: "não definida", foreground: theme.warning, background: theme.warningTint)
                        }
                    }
                    ForEach(Array(suite.runs.enumerated()), id: \.offset) { _, run in
                        ExecutionRunRow(run: run)
                    }
                }
            }
            if !inspection.unusedSuites.isEmpty {
                (Text("Definidas e não chamadas pelo main: ").foregroundColor(theme.labelSecondary)
                    + Text(inspection.unusedSuites.joined(separator: ", ")).foregroundColor(theme.labelTertiary))
                    .font(DSFont.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ExecutionRunRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let run: EngineDTO.ProjectInspection.Run

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: DesignMetrics.Spacing.s3) {
                Image(systemName: run.found ? "doc.text" : "questionmark.folder")
                    .foregroundStyle(run.found ? theme.labelSecondary : theme.warning)
                    .accessibilityHidden(true)
                Text([run.squad, run.feature].compactMap { $0 }.joined(separator: " · "))
                    .font(DSFont.mono(11))
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if run.found {
                Text(run.title ?? run.path ?? "")
                    .font(DSFont.callout.weight(.semibold))
                    .foregroundStyle(theme.labelPrimary)
                    .lineLimit(2)
                ForEach(Array(run.scenarios.enumerated()), id: \.offset) { _, cenario in
                    HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s3) {
                        Text("•").foregroundStyle(theme.labelTertiary).accessibilityHidden(true)
                        Text(cenario).foregroundStyle(theme.labelPrimary).lineLimit(2)
                    }
                    .font(DSFont.callout)
                }
            } else {
                Text("Não achei \(run.feature ?? "a feature") (procurei em features/, \(run.squad ?? "<squad>")/, "
                     + "\(run.squad ?? "<squad>")/features/ e na raiz).")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, DesignMetrics.Spacing.s7)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Problemas

private struct ExecutionProblemsSection: View {
    @Environment(ThemeManager.self) private var themeManager
    let problems: [EngineDTO.ProjectInspection.Problem]

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            ExecutionSectionTitle(title: "Problemas", detail: "\(problems.count)")
            ForEach(Array(problems.enumerated()), id: \.offset) { _, problema in
                HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        if let local = problema.location {
                            Text(local).font(DSFont.mono(11)).foregroundStyle(theme.labelSecondary)
                        }
                        Text(problema.message)
                            .font(DSFont.callout)
                            .foregroundStyle(theme.labelPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
