import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Início no dia a dia (`maquete/Main.dc.html`): cabeçalho, aparelho, áreas,
/// "Continuar de onde parou" e novidades. Pendência de ambiente só aparece
/// onde atrapalha, na linha do alvo que ela limita, com "Resolver…".
struct HomeDailyContent: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let home: EngineDTO.HomeSummary

    /// Versão cujas novidades a pessoa dispensou. Volta na versão seguinte.
    @AppStorage("mobaile.novidadesDispensadas") private var novidadesDispensadas = ""

    private var novidades: EngineDTO.HomeWhatsNew? {
        guard let novas = home.whatsNew, novas.version != novidadesDispensadas else { return nil }
        return novas
    }

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 28) {
            HomeHeader(environment: home.environment)
            if appState.isDeviceConnected {
                HomeDeviceCard(home: home)
            } else {
                HomeTargetsBlock(home: home)
            }
            HomeAreaGrid()
            linhaDeBaixo
            Text(HomeCopy.homeNote)
                .font(DSFont.callout)
                .foregroundStyle(theme.labelSecondary)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 1080, alignment: .leading)
        .padding(.horizontal, DesignMetrics.Spacing.s10)
        .padding(.top, 36)
        .padding(.bottom, DesignMetrics.Spacing.s10)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var linhaDeBaixo: some View {
        if let novidades {
            // 2:1 lado a lado; em janela estreita, um embaixo do outro.
            HomePairLayout(trailingFraction: 1.0 / 3.0, minSideBySide: 760) {
                HomeRecentCard(recent: home.recent)
                HomeWhatsNewCard(novidades: novidades) { novidadesDispensadas = novidades.version }
            }
        } else {
            HomeRecentCard(recent: home.recent)
        }
    }
}

// MARK: - Cabeçalho

struct HomeHeader: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let environment: EngineDTO.HomeEnvironment

    var body: some View {
        let theme = themeManager.current
        HStack(alignment: .center, spacing: DesignMetrics.Spacing.s6) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text(HomeCopy.greeting())
                    .font(DSFont.largeTitle.weight(.bold))
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("O que vamos testar hoje?")
                    .font(DSFont.title3.weight(.regular))
                    .foregroundStyle(theme.labelSecondary)
            }
            Spacer(minLength: DesignMetrics.Spacing.s4)
            HomeEnvironmentPill(environment: environment)
        }
    }
}

/// Cápsula do ambiente: ponto verde (pronto) ou amarelo (pendência) e o texto
/// curto. Leva ao Ambiente. É controle, não conteúdo: cápsula de vidro.
struct HomeEnvironmentPill: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let environment: EngineDTO.HomeEnvironment

    @State private var hover = false

    var body: some View {
        let theme = themeManager.current
        Button {
            appState.selectedStepID = nil
            appState.workspaceTab = .environment
        } label: {
            HStack(spacing: DesignMetrics.Spacing.s3) {
                Circle()
                    .fill(environment.isReady ? theme.success : theme.warningFill)
                    .frame(width: 7, height: 7)
                Text(HomeCopy.environmentPill(environment))
                    .font(DSFont.mono(11))
                    .foregroundStyle(theme.labelPrimary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.labelSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .mbGlass(.capsula, in: Capsule(), interactive: true, highlighted: hover)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Abrir o Ambiente (⌘5)")
        .accessibilityLabel(HomeCopy.environmentPill(environment))
        .accessibilityHint("Abre o Ambiente")
    }
}

// MARK: - Sem aparelho

/// Dois cartões, 2:1: os alvos que dá para usar e o atalho para o Relatório.
struct HomeTargetsBlock: View {
    let home: EngineDTO.HomeSummary

    var body: some View {
        HomePairLayout(trailingFraction: 1.0 / 3.0, minSideBySide: 760) {
            HomeTargetsCard(home: home)
            HomeNoDeviceCard()
        }
    }
}

struct HomeTargetsCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let home: EngineDTO.HomeSummary

    /// O botão padrão vai no primeiro alvo sem bloqueio.
    private var padrao: String? { home.targets.first { $0.blockedBy.isEmpty }?.id }

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s5) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text("Escolha um aparelho para começar")
                    .font(DSFont.title3)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(home.targets.isEmpty
                     ? "Nenhum aparelho conectado, e nenhum simulador ou emulador encontrado nesta máquina."
                     : "Nenhum aparelho conectado. Estes estão disponíveis nesta máquina:")
                    .font(DSFont.body)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(home.targets) { alvo in
                HomeTargetRow(alvo: alvo, pending: alvo.blockedBy.compactMap(home.pending).first,
                              isDefault: alvo.id == padrao)
            }
            HomeCableRow()
            if home.targets.isEmpty {
                Button("Instalar Emulador ou Simulador…") {
                    appState.selectedStepID = nil
                    appState.workspaceTab = .environment
                }
                .buttonStyle(PlainTextButtonStyle(theme: theme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsCard()
    }
}

struct HomeTargetRow: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    let alvo: EngineDTO.HomeTarget
    let pending: EngineDTO.HomePending?
    let isDefault: Bool

    var body: some View {
        let theme = themeManager.current
        let cor = PlatformIdentity.color(alvo.appPlatform)
        HStack(alignment: .center, spacing: DesignMetrics.Spacing.s5) {
            Image(systemName: alvo.platform == "ios" ? "iphone.gen3" : "candybarphone")
                .font(.system(size: 15))
                .foregroundStyle(cor)
                .frame(width: 34, height: 34)
                .background(cor.opacity(0.16), in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.sidebarItem))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text(alvo.name)
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                Text(HomeCopy.targetDetail(alvo))
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.labelSecondary)
                if let pending {
                    HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .accessibilityHidden(true)
                        Text(HomeCopy.limitation(alvo, pending: pending))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Resolver…") {
                            appState.environmentFocus = pending.id
                            appState.selectedStepID = nil
                            appState.workspaceTab = .environment
                        }
                        .buttonStyle(PlainTextButtonStyle(theme: theme))
                    }
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.warning)
                }
            }
            Spacer(minLength: DesignMetrics.Spacing.s4)
            acao
        }
        .padding(DesignMetrics.Spacing.s4)
        .background(theme.fillQuaternary, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.menu))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(alvo.name), \(HomeCopy.targetDetail(alvo))")
    }

    @ViewBuilder
    private var acao: some View {
        let botao = Button(session.isBooting ? "Iniciando…" : HomeCopy.targetAction(alvo)) {
            Task { await session.useTarget(alvo) }
        }
        .disabled(session.isBooting)
        if isDefault {
            botao.buttonStyle(.borderedProminent)
        } else {
            botao
        }
    }
}

/// Última linha da lista, tracejada: como chegar com um aparelho de verdade.
struct HomeCableRow: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s4) {
            Image(systemName: "cable.connector")
                .font(.system(size: 13))
                .foregroundStyle(theme.labelSecondary)
                .accessibilityHidden(true)
            Text(HomeCopy.cableHint)
                .font(DSFont.callout)
                .foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignMetrics.Spacing.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: DesignMetrics.Radius.menu)
                .strokeBorder(theme.separatorStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .accessibilityHidden(true)
        }
    }
}

struct HomeNoDeviceCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            Image(systemName: WorkspaceTab.report.symbolName)
                .font(.system(size: 17))
                .foregroundStyle(WorkspaceTab.report.categoryColor(theme))
                .accessibilityHidden(true)
            Text("Sem aparelho à mão?")
                .font(DSFont.title3)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("O Relatório audita um log de eventos contra a spec dos cards do Figma, parâmetro por parâmetro. "
                 + "Não precisa de aparelho.")
                .font(DSFont.body)
                .foregroundStyle(theme.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Abrir Relatório…") {
                appState.selectedStepID = nil
                appState.workspaceTab = .report
            }
            .buttonStyle(PlainTextButtonStyle(theme: theme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsCard()
    }
}

// MARK: - Com aparelho

/// Um cartão só: o último quadro do espelho, o aparelho, o que dá para fazer
/// e o que está ligado agora (vem das notificações do motor, sem polling).
struct HomeDeviceCard: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    let home: EngineDTO.HomeSummary

    private var alvo: EngineDTO.HomeTarget? { home.targets.first { $0.connected } }
    private var limite: EngineDTO.HomePending? { alvo?.blockedBy.compactMap(home.pending).first }

    var body: some View {
        let theme = themeManager.current
        HStack(alignment: .top, spacing: DesignMetrics.Spacing.s8) {
            miniatura(theme)
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                HStack(spacing: DesignMetrics.Spacing.s4) {
                    Text(appState.selectedDeviceName ?? "Aparelho")
                        .font(DSFont.title2)
                        .foregroundStyle(theme.labelPrimary)
                        .accessibilityAddTraits(.isHeader)
                    HomePlatformChip(platform: appState.platform)
                }
                Text(status)
                    .font(DSFont.mono(11))
                    .foregroundStyle(theme.labelSecondary)
                if let limite, let alvo {
                    Text(HomeCopy.limitation(alvo, pending: limite))
                        .font(DSFont.body)
                        .foregroundStyle(theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tudo pronto. Um clique no espelho toca no aparelho e grava o passo.")
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                acoes
                    .padding(.top, DesignMetrics.Spacing.s2)
            }
            Spacer(minLength: DesignMetrics.Spacing.s4)
            vivos(theme)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsCard()
    }

    private var status: String {
        let tipo: String
        switch alvo?.kind {
        case "simulator": tipo = "simulador"
        case "emulator": tipo = "emulador"
        case "physical": tipo = "aparelho físico"
        default: tipo = appState.platform == .ios ? "iOS" : "Android"
        }
        return "\(tipo) · conectado"
    }

    private func miniatura(_ theme: any ThemeTokens) -> some View {
        ZStack {
            theme.bgDeviceScreen
            if let quadro = appState.currentFrame {
                Image(nsImage: quadro)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: 72, height: 144)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.deviceBezel, lineWidth: 3)
        }
        .accessibilityHidden(true)
    }

    private var acoes: some View {
        HStack(spacing: DesignMetrics.Spacing.s4) {
            Button("Espelhar e Gravar") { ir(.pageObjects) }
                .buttonStyle(.borderedProminent)
            Button("Ver Rede HTTP") { ir(.network) }
            Button("Escutar Analytics") { ir(.analytics) }
            Button("Rodar Flow…") { rodarFlow() }
                .help("Roda um flow do Maestro (.yaml) neste aparelho, sem internet")
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private func vivos(_ theme: any ThemeTokens) -> some View {
        let linhas: [(Bool, String)] = [
            (appState.streamActive, appState.streamActive ? "espelho a \(appState.fps) quadros" : "espelho parado"),
            (appState.proxyRunning || appState.debugNetActive, appState.proxyRunning
                ? "proxy ouvindo" : (appState.debugNetActive ? "app em debug lido" : "rede desligada")),
            (appState.analyticsListenerActive, appState.analyticsListenerActive ? "analytics escutando" : "analytics desligado"),
        ]
        return VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
            ForEach(linhas, id: \.1) { ligado, texto in
                HStack(spacing: DesignMetrics.Spacing.s3) {
                    Circle()
                        .fill(ligado ? theme.success : theme.labelQuaternary)
                        .frame(width: 6, height: 6)
                    Text(texto)
                        .font(DSFont.mono(11))
                        .foregroundStyle(ligado ? theme.labelPrimary : theme.labelSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, DesignMetrics.Spacing.s2)
    }

    private func ir(_ area: WorkspaceTab) {
        appState.selectedStepID = nil
        appState.workspaceTab = area
    }

    private func rodarFlow() {
        let painel = NSOpenPanel()
        painel.title = "Rodar Flow do Maestro"
        painel.prompt = "Rodar"
        painel.allowedContentTypes = [UTType(filenameExtension: "yaml"), UTType(filenameExtension: "yml")].compactMap { $0 }
        painel.allowsMultipleSelection = false
        guard painel.runModal() == .OK, let url = painel.url else { return }
        ir(.pageObjects)
        appState.showingFlowRunner = true
        Task { await session.runMaestroFlow(at: url) }
    }
}

struct HomePlatformChip: View {
    let platform: Platform

    var body: some View {
        let cor = PlatformIdentity.color(platform)
        Text(platform == .ios ? "iOS" : "Android")
            .font(DSFont.footnote.weight(.semibold))
            .foregroundStyle(cor)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(cor.opacity(0.16), in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.chip))
    }
}

// MARK: - Áreas

/// As quatro áreas, sem estado de instalação (ele está no Ambiente). Quatro
/// lado a lado; em janela estreita, duas por linha.
struct HomeAreaGrid: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            Text("Áreas")
                .font(DSFont.headline)
                .foregroundStyle(theme.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            HomeColumnsLayout(columns: { $0 >= 720 ? 4 : 2 }) {
                ForEach(WorkspaceTab.workspaceAreas) { area in
                    HomeAreaCard(area: area)
                }
            }
        }
    }
}

struct HomeAreaCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let area: WorkspaceTab

    @State private var hover = false

    var body: some View {
        let theme = themeManager.current
        Button {
            appState.selectedStepID = nil
            appState.workspaceTab = area
        } label: {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s3) {
                HStack {
                    Image(systemName: area.symbolName)
                        .font(.system(size: 17))
                        .foregroundStyle(area.categoryColor(theme))
                        .accessibilityHidden(true)
                    Spacer()
                    Text("⌘\(area.shortcutDigit)")
                        .font(DSFont.mono(11))
                        .foregroundStyle(theme.labelTertiary)
                        .accessibilityHidden(true)
                }
                Text(area.displayName)
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                Text(HomeCopy.areaSummary(area))
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .help("Ir para \(area.displayName) (⌘\(area.shortcutDigit))")
        .accessibilityLabel(area.displayName)
        .accessibilityValue(HomeCopy.areaSummary(area))
        .accessibilityHint("Abre a área")
    }
}

// MARK: - Recentes e novidades

struct HomeRecentCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let recent: [EngineDTO.HomeRecent]

    @State private var mostrandoTudo = false

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            HStack {
                Text("Continuar de onde parou")
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if recent.count > 5 {
                    Button("Ver Tudo") { mostrandoTudo = true }
                        .buttonStyle(PlainTextButtonStyle(theme: theme))
                        .popover(isPresented: $mostrandoTudo, arrowEdge: .bottom) {
                            ScrollView {
                                lista(recent).padding(DesignMetrics.Spacing.s5)
                            }
                            .frame(width: 420, height: 360)
                        }
                }
            }
            if recent.isEmpty {
                VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
                    Text("Nada por aqui ainda. Grave um passo ou abra um Relatório.")
                        .font(DSFont.body)
                        .foregroundStyle(theme.labelSecondary)
                    Button("Abrir Relatório…") {
                        appState.selectedStepID = nil
                        appState.workspaceTab = .report
                    }
                    .buttonStyle(PlainTextButtonStyle(theme: theme))
                }
            } else {
                lista(Array(recent.prefix(5)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsCard()
    }

    private func lista(_ itens: [EngineDTO.HomeRecent]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(itens.enumerated()), id: \.element.id) { indice, item in
                if indice > 0 {
                    Rectangle().fill(themeManager.current.separator).frame(height: DesignMetrics.hairline)
                }
                HomeRecentRow(item: item)
            }
        }
    }
}

struct HomeRecentRow: View {
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    let item: EngineDTO.HomeRecent

    @State private var hover = false

    private var simbolo: String {
        switch item.kind {
        case "report": return WorkspaceTab.report.symbolName
        case "page_object": return WorkspaceTab.pageObjects.symbolName
        case "maestro": return "play.rectangle"
        default: return "record.circle"
        }
    }

    private var arquivo: Bool { item.kind == "page_object" || item.kind == "maestro" }

    var body: some View {
        let theme = themeManager.current
        Button {
            Task { await session.openRecent(item) }
        } label: {
            HStack(spacing: DesignMetrics.Spacing.s5) {
                Image(systemName: simbolo)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.labelSecondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(arquivo ? DSFont.mono(12) : DSFont.body)
                        .foregroundStyle(theme.labelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.subtitle)
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DesignMetrics.Spacing.s4)
                Text(HomeCopy.relativeDate(item.date))
                    .font(DSFont.mono(11))
                    .foregroundStyle(theme.labelTertiary)
            }
            .padding(.vertical, DesignMetrics.Spacing.s4)
            .padding(.horizontal, DesignMetrics.Spacing.s2)
            .background(hover ? theme.fillQuaternary : .clear, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.row))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(item.path)
        .accessibilityLabel("\(item.title), \(item.subtitle), \(HomeCopy.relativeDate(item.date))")
        .accessibilityHint("Reabre")
    }
}

struct HomeWhatsNewCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let novidades: EngineDTO.HomeWhatsNew
    let dismiss: () -> Void

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Novidades da \(novidades.version)")
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.labelSecondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dispensar até a próxima versão")
                .accessibilityLabel("Dispensar novidades")
            }
            ForEach(novidades.items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.Spacing.s3) {
                    Circle().fill(theme.accent).frame(width: 4, height: 4).accessibilityHidden(true)
                    Text(item)
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let changelog = Self.changelog {
                Button("Ver Todas as Novidades…") { NSWorkspace.shared.open(changelog) }
                    .buttonStyle(PlainTextButtonStyle(theme: theme))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dsCard()
    }

    /// O CHANGELOG embutido no app (`Contents/Resources`) ou, rodando do
    /// código, o da raiz do repositório.
    static var changelog: URL? {
        if let embutido = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") { return embutido }
        guard let raiz = EngineLocator.repositoryRoot() else { return nil }
        let doRepositorio = raiz.appendingPathComponent("CHANGELOG.md")
        return FileManager.default.fileExists(atPath: doRepositorio.path) ? doRepositorio : nil
    }
}

// MARK: - Layouts

/// Dois blocos lado a lado, o de trás com uma fração da largura (2:1 é 1/3),
/// e um embaixo do outro quando a largura disponível não chega a
/// `minSideBySide`. Decide pela largura proposta, e não pela largura ideal
/// do texto em uma linha só, que é o que o `ViewThatFits` mede.
struct HomePairLayout: Layout {
    var trailingFraction: CGFloat
    var minSideBySide: CGFloat
    var spacing: CGFloat = DesignMetrics.Spacing.s7

    private func larguras(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let tras = ((total - spacing) * trailingFraction).rounded(.down)
        return (total - spacing - tras, tras)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let largura = proposal.width ?? minSideBySide
        if largura >= minSideBySide {
            let (a, b) = larguras(largura)
            let altura = max(subviews[0].sizeThatFits(.init(width: a, height: nil)).height,
                             subviews[1].sizeThatFits(.init(width: b, height: nil)).height)
            return CGSize(width: largura, height: altura)
        }
        let alturas = subviews.map { $0.sizeThatFits(.init(width: largura, height: nil)).height }
        return CGSize(width: largura, height: alturas.reduce(0, +) + spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if bounds.width >= minSideBySide {
            let (a, b) = larguras(bounds.width)
            // Mesma altura nos dois: os cartões alinham embaixo.
            subviews[0].place(at: bounds.origin, proposal: .init(width: a, height: bounds.height))
            subviews[1].place(at: CGPoint(x: bounds.minX + a + spacing, y: bounds.minY),
                              proposal: .init(width: b, height: bounds.height))
        } else {
            let alturaA = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil)).height
            subviews[0].place(at: bounds.origin, proposal: .init(width: bounds.width, height: alturaA))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + alturaA + spacing),
                              proposal: .init(width: bounds.width, height: nil))
        }
    }
}

/// Colunas de largura igual, com a mesma altura em cada linha. O número de
/// colunas sai da largura disponível (quatro áreas lado a lado; duas por
/// linha em janela estreita).
struct HomeColumnsLayout: Layout {
    var columns: (CGFloat) -> Int
    var spacing: CGFloat = DesignMetrics.Spacing.s5

    private func grade(_ largura: CGFloat, _ subviews: Subviews) -> (Int, CGFloat, [CGFloat]) {
        let n = max(1, min(columns(largura), subviews.count))
        let coluna = (largura - spacing * CGFloat(n - 1)) / CGFloat(n)
        var linhas: [CGFloat] = []
        for inicio in stride(from: 0, to: subviews.count, by: n) {
            let fim = min(inicio + n, subviews.count)
            linhas.append(subviews[inicio..<fim].map { $0.sizeThatFits(.init(width: coluna, height: nil)).height }.max() ?? 0)
        }
        return (n, coluna, linhas)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largura = proposal.width ?? 720
        let (_, _, linhas) = grade(largura, subviews)
        return CGSize(width: largura, height: linhas.reduce(0, +) + spacing * CGFloat(max(0, linhas.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (n, coluna, linhas) = grade(bounds.width, subviews)
        var y = bounds.minY
        for (indiceLinha, altura) in linhas.enumerated() {
            for coluna_i in 0..<n {
                let indice = indiceLinha * n + coluna_i
                guard indice < subviews.count else { break }
                let x = bounds.minX + CGFloat(coluna_i) * (coluna + spacing)
                subviews[indice].place(at: CGPoint(x: x, y: y), proposal: .init(width: coluna, height: altura))
            }
            y += altura + spacing
        }
    }
}
