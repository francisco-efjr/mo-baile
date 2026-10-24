import AppKit
import SwiftUI

/// Tela Ambiente (3.11.0, `docs/design/home/maquete/Ambiente.dc.html`): o
/// diagnóstico de instalação que ficava na Início. O que está instalado nesta
/// máquina, o que falta e o que cada área consegue fazer em cada plataforma.
///
/// Os dados vêm do motor: `setup.check` (grupos, componentes e a tabela de
/// áreas) e `home.summary` (pendências com o que cada uma bloqueia). Nada é
/// decidido aqui. Item fixo no rodapé da barra lateral, ⌘5.
struct EnvironmentView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollViewReader { leitor in
            ScrollView {
                EnvironmentContent()
            }
            .background(themeManager.current.bgContent)
            .onAppear { rolarParaFoco(leitor) }
            .onChange(of: appState.environmentFocus) { _, _ in rolarParaFoco(leitor) }
            .onChange(of: session.home?.environment.pending.count) { _, _ in rolarParaFoco(leitor) }
        }
    }

    /// O "Resolver…" da Início chega aqui com a pendência a mostrar.
    private func rolarParaFoco(_ leitor: ScrollViewProxy) {
        guard let foco = appState.environmentFocus,
              session.home?.environment.pending.contains(where: { $0.id == foco }) == true else { return }
        withAnimation(Motion.smooth()) { leitor.scrollTo(EnvironmentContent.anchor(foco), anchor: .top) }
        appState.environmentFocus = nil
    }
}

/// O conteúdo do Ambiente, sem a rolagem (os testes desenham com `ImageRenderer`).
struct EnvironmentContent: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    @State private var erroInstalacao: String?

    static func anchor(_ pendencia: String) -> String { "pendencia-\(pendencia)" }

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s9) {
            cabecalho
            if let setup = session.setup, session.isConnected {
                resumo(setup)
                pendencias(setup)
                if let erroInstalacao {
                    InlineError(title: "Não deu para abrir o Terminal.", text: erroInstalacao)
                }
                EnvironmentAreaMatrix(features: setup.features)
                componentes(setup)
            } else {
                // Sem motor, só o Python é verificável: é ele que falta.
                HomeNextStepCard(
                    passo: HomeNextStep.pick(engineStatus: session.engineStatus, lastError: session.lastError,
                                             setup: nil, deviceName: nil),
                    pending: 1, install: instalar, erro: erroInstalacao
                )
                Text("O resto é conferido quando o motor subir.")
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.labelSecondary)
            }
            Text(HomeCopy.note)
                .font(DSFont.callout)
                .foregroundStyle(theme.labelSecondary)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 860, alignment: .leading)
        .padding(.horizontal, DesignMetrics.Spacing.s10)
        .padding(.top, 32)
        .padding(.bottom, DesignMetrics.Spacing.s10)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cabeçalho

    private var cabecalho: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s5) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text("Ambiente")
                    .font(DSFont.title1.weight(.bold))
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("O que está instalado nesta máquina e o que cada área precisa.")
                    .font(DSFont.body)
                    .foregroundStyle(theme.labelSecondary)
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
                .disabled(!session.isConnected)
                if let quando = session.lastSetupCheck {
                    Text("verificado às \(quando.formatted(date: .omitted, time: .shortened))")
                        .font(DSFont.mono(11))
                        .foregroundStyle(theme.labelSecondary)
                }
            }
        }
    }

    // MARK: - Resumo

    private func resumo(_ setup: EngineDTO.Setup) -> some View {
        HStack(alignment: .top, spacing: DesignMetrics.Spacing.s5) {
            ForEach(setup.groups) { grupo in
                EnvironmentSummaryTile(group: grupo)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Pendências

    @ViewBuilder
    private func pendencias(_ setup: EngineDTO.Setup) -> some View {
        let lista = session.home?.environment.pending ?? []
        if !lista.isEmpty {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
                ForEach(lista) { pendencia in
                    EnvironmentPendingCard(
                        pending: pendencia, component: setup.component(pendencia.id), total: lista.count,
                        python: setup.python.path, install: instalar
                    )
                    .id(Self.anchor(pendencia.id))
                }
            }
        }
    }

    // MARK: - Componentes

    private func componentes(_ setup: EngineDTO.Setup) -> some View {
        // Grupo com pendência vem antes.
        let pendentes = Set((session.home?.environment.pending ?? []).map(\.id))
        let grupos = setup.groups.sorted { a, b in
            let pa = a.components.contains { pendentes.contains($0.id) }
            let pb = b.components.contains { pendentes.contains($0.id) }
            return pa && !pb
        }
        return VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s7) {
            ForEach(grupos) { grupo in
                HomeComponentGroup(title: grupo.title, components: grupo.components, install: instalar, open: abrir)
            }
        }
    }

    // MARK: - Ações

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

/// Um grupo no resumo: Motor, Android, iOS ou Extras, com quantos estão prontos.
struct EnvironmentSummaryTile: View {
    @Environment(ThemeManager.self) private var themeManager
    let group: EngineDTO.SetupGroup

    private var obrigatorios: [EngineDTO.SetupComponent] { group.components.filter(\.required) }
    private var faltam: Int { obrigatorios.filter { $0.daemonState != .ok }.count }
    private var opcional: Bool { obrigatorios.isEmpty }

    private var texto: String {
        if opcional {
            let prontos = group.components.filter { $0.daemonState == .ok }.count
            return "\(prontos) de \(group.components.count)"
        }
        return faltam == 0 ? "pronto" : (faltam == 1 ? "falta 1 item" : "faltam \(faltam)")
    }

    var body: some View {
        let theme = themeManager.current
        let pendente = !opcional && faltam > 0
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s2) {
            Text(group.title)
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.labelSecondary)
            HStack(spacing: DesignMetrics.Spacing.s2) {
                Image(systemName: pendente ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(pendente ? theme.warning : (opcional ? theme.labelSecondary : theme.success))
                    .accessibilityHidden(true)
                Text(texto)
                    .font(DSFont.headline)
                    .foregroundStyle(pendente ? theme.warning : theme.labelPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: DesignMetrics.Spacing.s5)
        .overlay {
            if pendente {
                RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous)
                    .strokeBorder(theme.warningFill.opacity(0.35), lineWidth: 1)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title): \(texto)")
    }
}

/// Uma pendência obrigatória: o que faz falta, o comando e os botões. É o
/// destino do "Resolver…" da Início.
struct EnvironmentPendingCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let pending: EngineDTO.HomePending
    let component: EngineDTO.SetupComponent?
    let total: Int
    let python: String?
    let install: (String) -> Void

    private var comando: String? {
        guard let alvo = pending.install else { return nil }
        return SetupInstaller.copyableCommand(target: alvo, python: python)
    }

    private var titulo: String {
        pending.install != nil ? "Instalar \(pending.title)" : pending.title
    }

    /// O detalhe do componente já diz o efeito; sem detalhe, vale o que a
    /// pendência bloqueia.
    private var explicacao: String {
        if let detalhe = component?.detail, !detalhe.isEmpty { return detalhe }
        return pending.blocks.first.map { "Sem ele: \($0.effect)." } ?? ""
    }

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            Text(total == 1 ? "Falta 1 item" : "Faltam \(total) itens")
                .font(DSFont.subheadlineSemibold)
                .foregroundStyle(theme.accentText)
            Text(titulo)
                .font(DSFont.title3)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(explicacao)
                .font(DSFont.body)
                .foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let comando {
                Text(comando)
                    .font(DSFont.mono(11.5))
                    .foregroundStyle(theme.labelPrimary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .padding(.horizontal, DesignMetrics.Spacing.s4)
                    .padding(.vertical, DesignMetrics.Spacing.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.fillTertiary, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.field))
                    .accessibilityLabel("Comando: \(comando)")
            }
            HStack(spacing: DesignMetrics.Spacing.s4) {
                if let alvo = pending.install {
                    Button("Instalar no Terminal…") { install(alvo) }
                        .buttonStyle(.borderedProminent)
                    if let comando {
                        Button("Copiar Comando") {
                            Exporters.copy(comando)
                            appState.statusMessage = "Comando copiado"
                        }
                        .help("Copia o comando para rodar você mesmo no Terminal")
                    }
                } else if let link = pending.link, let url = URL(string: link) {
                    Button(HomeCopy.linkTitle(link)) { NSWorkspace.shared.open(url) }
                        .buttonStyle(.borderedProminent)
                }
            }
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
        .accessibilityLabel("Pendência: \(titulo)")
    }
}

/// O que funciona em cada área: Área × iOS × Android, com o estado e o texto
/// que o motor manda (`setup.check`, campo `features`).
struct EnvironmentAreaMatrix: View {
    @Environment(ThemeManager.self) private var themeManager
    let features: [EngineDTO.SetupFeature]

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            Text("O que funciona em cada área")
                .font(DSFont.headline)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Grid(alignment: .leading, horizontalSpacing: DesignMetrics.Spacing.s7, verticalSpacing: 0) {
                GridRow {
                    ForEach(["Área", "iOS", "Android"], id: \.self) { titulo in
                        Text(titulo)
                            .font(DSFont.subheadlineSemibold)
                            .foregroundStyle(theme.labelSecondary)
                    }
                }
                .padding(.vertical, DesignMetrics.Spacing.s3)
                ForEach(features) { feature in
                    Divider().gridCellColumns(3)
                    GridRow {
                        Text(feature.tab?.displayName ?? feature.id)
                            .font(DSFont.body)
                            .foregroundStyle(theme.labelPrimary)
                        celula(feature, "ios", theme)
                        celula(feature, "android", theme)
                    }
                    .padding(.vertical, DesignMetrics.Spacing.s3)
                }
            }
            .padding(.horizontal, DesignMetrics.Spacing.s7)
            .padding(.vertical, DesignMetrics.Spacing.s2)
            .dsCard(padding: 0)
        }
    }

    @ViewBuilder
    private func celula(_ feature: EngineDTO.SetupFeature, _ plataforma: String, _ theme: any ThemeTokens) -> some View {
        // O Relatório vale para as duas (`any`).
        if let linha = feature.platforms.first(where: { $0.platform == plataforma || $0.platform == "any" }) {
            HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s2) {
                Image(systemName: DiagnosticCard.symbol(linha.daemonState))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(HomeStateStyle.color(linha.daemonState, theme))
                    .accessibilityHidden(true)
                Text(linha.detail)
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(plataforma == "ios" ? "iOS" : "Android"): \(StatusIndicator.word(linha.daemonState)), \(linha.detail)")
        } else {
            Text("—").foregroundStyle(theme.labelTertiary)
        }
    }
}
