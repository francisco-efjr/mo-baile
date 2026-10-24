import SwiftUI

/// Janela principal: Sidebar | Espelho + Workspace | Inspector.
///
/// Até a 2.x a janela tinha duas barras empilhadas (a do app e a do
/// workspace), trilhos laterais de 30 pt para os painéis recolhidos e a
/// hierarquia escondida. O redesenho 3.0 segue o HIG do macOS: barra lateral
/// com as áreas e os passos do fluxo, uma toolbar unificada (Liquid Glass no
/// macOS 26) e o inspector com hierarquia e atributos. Os controles são os do
/// sistema sempre que existe um; o design system só desenha o que o AppKit não
/// tem (indicador de status, chip de tipo, cartão de diagnóstico).
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView(columnVisibility: $state.sidebarVisibility) {
            AppSidebar()
                .modifier(HiddenBehindCommandPalette())
                .navigationSplitViewColumnWidth(
                    min: DesignMetrics.Widths.sidebarMin,
                    ideal: DesignMetrics.Widths.sidebarIdeal,
                    max: DesignMetrics.Widths.sidebarMax
                )
        } detail: {
            // Inspector próprio, e não `.inspector`: a NavigationSplitView com
            // um inspector aninhado mede o mínimo das colunas pelo tamanho ideal
            // do conteúdo e conta a barra lateral em dobro. Com o Relatório
            // aberto a janela pedia 1.743 pt de largura, mais que a tela de um
            // MacBook Air; com o painel no HStack, a soma dos mínimos declarados.
            HStack(spacing: 0) {
                DetailColumn()
                    .modifier(HiddenBehindCommandPalette())
                if appState.inspectorShown {
                    let limites = DesignMetrics.Widths.inspectorMin...DesignMetrics.Widths.inspectorMax
                    let largura = CGFloat(larguraInspector).clamped(to: limites)
                    PaneDivider(largura: largura, limites: limites, sentido: -1) { larguraInspector = $0 }
                    InspectorContent()
                        .modifier(HiddenBehindCommandPalette())
                        // Como o espelho: na largura arrastada quando há folga,
                        // cede até o mínimo antes de a janela crescer. A
                        // prioridade faz o HStack medir o painel depois de
                        // reservar o mínimo da área; sem ela o inspector ficava
                        // na largura ideal e a área transbordava a coluna.
                        .frame(minWidth: limites.lowerBound, idealWidth: largura, maxWidth: largura)
                        .layoutPriority(1)
                        .frame(maxHeight: .infinity)
                        .background(theme.bgContent)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Inspector")
                }
            }
            .modifier(SectionSearch())
            .modifier(ToolbarTitle(title: windowTitle, subtitle: windowSubtitle))
            .toolbar { MainToolbar(title: windowTitle, subtitle: windowSubtitle) }
        }
        .tint(theme.accent)
        // Paleta de comandos (⇧⌘P), por cima de tudo na janela.
        .overlay { CommandPaletteOverlay().tint(theme.accent) }
        .animation(Motion.crossfade, value: appState.commandPalettePresented)
        .sheet(isPresented: $state.showingStructure) {
            StructureSheet()
                .environment(appState).environment(session).environment(themeManager)
                .tint(theme.accent)
        }
        .sheet(isPresented: $state.showingFlowRunner) {
            FlowRunnerSheet()
                .environment(appState).environment(session).environment(themeManager)
                .tint(theme.accent)
        }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { appState.pendingClear != nil },
                set: { if !$0 { appState.pendingClear = nil } }
            ),
            presenting: appState.pendingClear
        ) { kind in
            Button(confirmTitle(kind), role: .destructive) { clear(kind) }
            Button("Cancelar", role: .cancel) {}
        } message: { kind in
            Text(alertMessage(kind))
        }
        .task {
            // Sobe o motor junto com a janela. Sem isto, a aplicacao ficava
            // permanentemente no estado vazio.
            await session.connect()
        }
        // Onde a janela abre: no Início na primeira vez, com o motor parado ou
        // sem aparelho; em Page Objects com aparelho (`LaunchDestination`).
        .onChange(of: session.launchPhase) { _, fase in
            let destino = LaunchDestination.pick(
                firstRun: !UserDefaults.standard.bool(forKey: LaunchDestination.seenKey),
                phase: fase,
                deviceConnected: appState.isDeviceConnected,
                current: appState.workspaceTab
            )
            if let destino, appState.selectedStepID == nil { appState.workspaceTab = destino }
        }
        .onDisappear {
            Task { await session.disconnect() }
        }
    }

    @SceneStorage("larguraInspector") private var larguraInspector = Double(DesignMetrics.Widths.inspectorIdeal)

    // MARK: - Título

    /// O título mostra a seção, nunca o nome do app.
    private var windowTitle: String {
        if !appState.workspaceTab.needsDevice { return appState.workspaceTab.displayName }
        return appState.isDeviceConnected ? appState.workspaceTab.displayName : "Sem dispositivo"
    }

    private var windowSubtitle: String {
        if appState.workspaceTab == .home { return HomeCopy.subtitle(setup: session.setup, engineRunning: session.isConnected) }
        if appState.workspaceTab == .report { return reportSubtitle }
        guard appState.isDeviceConnected else { return "Nenhum dispositivo" }
        switch appState.workspaceTab {
        case .pageObjects:
            let total = appState.steps.count
            var passos = total == 1 ? "1 passo" : "\(total) passos"
            if let id = appState.selectedStepID, let indice = appState.steps.firstIndex(where: { $0.id == id }) {
                passos = "Passo \(indice + 1) de \(total)"
            }
            return "\(passos) · \(appState.selectedDeviceName ?? "")"
        case .network:
            let n = appState.httpRequests.count
            return n == 1 ? "1 requisição" : "\(n) requisições"
        case .analytics:
            let n = appState.analyticsEvents.count
            return n == 1 ? "1 evento" : "\(n) eventos"
        case .report:
            return reportSubtitle
        case .home:
            return HomeCopy.subtitle(setup: session.setup, engineRunning: session.isConnected)
        }
    }

    private var reportSubtitle: String {
        if let report = appState.report {
            let taxa = report.summary.complianceRate.formatted(.number.precision(.fractionLength(1)))
            return "\(report.spec.projeto) · \(report.summary.total) validações · \(taxa)% conforme"
        }
        return appState.reportSpec?.projeto ?? "Nenhuma spec"
    }

    // MARK: - Confirmações

    private var alertTitle: String {
        switch appState.pendingClear {
        case .network: return "Limpar o tráfego capturado?"
        case .analytics: return "Limpar os eventos capturados?"
        case .steps: return "Limpar todos os passos do fluxo?"
        case nil: return ""
        }
    }

    private func confirmTitle(_ kind: ClearKind) -> String {
        switch kind {
        case .network: return "Limpar Tráfego"
        case .analytics: return "Limpar Eventos"
        case .steps: return "Limpar Passos"
        }
    }

    /// O motor apaga de verdade, então o texto não promete desfazer.
    private func alertMessage(_ kind: ClearKind) -> String {
        switch kind {
        case .network:
            let n = appState.httpRequests.count
            return "\(n == 1 ? "1 requisição será removida" : "\(n) requisições serão removidas"). Essa ação não pode ser desfeita."
        case .analytics:
            let n = appState.analyticsEvents.count
            return "\(n == 1 ? "1 evento será removido" : "\(n) eventos serão removidos"). Essa ação não pode ser desfeita."
        case .steps:
            return "Os passos, o Page Object e os locators gerados serão esvaziados. Essa ação não pode ser desfeita."
        }
    }

    private func clear(_ kind: ClearKind) {
        appState.pendingClear = nil
        Task {
            switch kind {
            case .network: await session.clearTraffic()
            case .analytics: await session.clearAnalytics()
            case .steps: await session.clearSteps()
            }
        }
    }
}

/// Coluna central: espelho e workspace lado a lado, ou o diagnóstico quando
/// não há aparelho. A barra de status fica embaixo, só nesta coluna.
struct DetailColumn: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            EngineStatusBanner()

            Group {
                if appState.workspaceTab == .home {
                    HomeView()
                } else if !appState.workspaceTab.needsDevice {
                    // Relatório ocupa a coluna inteira: o espelho não ajuda a
                    // ler uma auditoria, e a aba funciona sem aparelho.
                    ReportView()
                } else if appState.isDeviceConnected {
                    connected
                } else {
                    NoDeviceView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatusBar()
        }
        .background(theme.bgContent)
    }

    @ViewBuilder
    private var connected: some View {
        let compacto = appState.workspaceTab != .pageObjects
        let mostraWorkspace = appState.workspaceVisible || !appState.mirrorVisible

        // HStack com divisória própria, e não HSplitView: dentro da
        // NavigationSplitView o NSSplitView aninhado somava 529 pt à largura
        // mínima da janela (D1). A largura do espelho é a que a pessoa arrastou,
        // guardada por cena e limitada ao mínimo e ao máximo do modo atual.
        HStack(spacing: 0) {
            if appState.mirrorVisible {
                let limites = compacto
                    ? DesignMetrics.Widths.mirrorCompactMin...DesignMetrics.Widths.mirrorCompactMax
                    : DesignMetrics.Widths.mirrorMin...DesignMetrics.Widths.mirrorMax
                let largura = CGFloat(compacto ? larguraEspelhoCompacto : larguraEspelho)
                    .clamped(to: limites)
                MirrorPane(compact: compacto && mostraWorkspace)
                    // Com folga fica na largura arrastada; sem folga cede até o
                    // mínimo antes de a janela crescer.
                    .frame(
                        minWidth: limites.lowerBound,
                        idealWidth: largura,
                        maxWidth: mostraWorkspace ? largura : .infinity
                    )
                    // Mede depois de reservar o mínimo do workspace (ver o
                    // inspector em ContentView).
                    .layoutPriority(1)
                if mostraWorkspace {
                    PaneDivider(largura: largura, limites: limites) { nova in
                        if compacto { larguraEspelhoCompacto = nova } else { larguraEspelho = nova }
                    }
                }
            }
            if mostraWorkspace {
                WorkspacePane()
                    .frame(minWidth: DesignMetrics.Widths.workspaceMin, maxWidth: .infinity)
            }
        }
    }

    @SceneStorage("larguraEspelho") private var larguraEspelho = Double(DesignMetrics.Widths.mirrorIdeal)
    @SceneStorage("larguraEspelhoCompacto") private var larguraEspelhoCompacto = Double(DesignMetrics.Widths.mirrorCompactIdeal)
}

/// Divisória vertical arrastável entre o espelho e o workspace, e entre a área
/// e o inspector: linha de 1 pt com área de toque de 7 pt e o cursor de
/// redimensionar, como a do NSSplitView.
private struct PaneDivider: View {
    @Environment(ThemeManager.self) private var themeManager
    let largura: CGFloat
    let limites: ClosedRange<CGFloat>
    /// 1 quando o painel medido fica à esquerda (espelho); -1 quando fica à
    /// direita (inspector), que cresce ao arrastar para a esquerda.
    var sentido: CGFloat = 1
    let mudou: (Double) -> Void

    @State private var inicio: CGFloat?
    /// O push do cursor que esta divisória deve ao NSCursor (COD-3).
    @State private var cursor = PaneDividerCursor()

    var body: some View {
        Rectangle()
            .fill(themeManager.current.separator)
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .padding(.horizontal, -3)
            .onHover { dentro in
                if dentro { cursor.enter() } else { cursor.leave() }
            }
            // Esconder o workspace (⌥2, modo Zen) com o ponteiro em cima tira
            // a divisória da janela sem `onHover(false)`, e o cursor de
            // redimensionar ficava preso até outro push/pop casar.
            .onDisappear { cursor.leave() }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { arraste in
                        let base = inicio ?? largura
                        if inicio == nil { inicio = largura }
                        mudou(Double((base + sentido * arraste.translation.width).clamped(to: limites)))
                    }
                    .onEnded { _ in inicio = nil }
            )
            .accessibilityHidden(true)
    }
}

/// Push e pop do cursor de redimensionar, sempre em par.
///
/// Só faz pop do que empurrou: sair duas vezes, ou sumir depois de já ter
/// saído, não tira da pilha o cursor de outra view.
final class PaneDividerCursor {
    private(set) var pushed = false
    private let push: () -> Void
    private let pop: () -> Void

    init(push: @escaping () -> Void = { NSCursor.resizeLeftRight.push() },
         pop: @escaping () -> Void = { NSCursor.pop() }) {
        self.push = push
        self.pop = pop
    }

    func enter() {
        guard !pushed else { return }
        push()
        pushed = true
    }

    func leave() {
        guard pushed else { return }
        pop()
        pushed = false
    }
}

extension Comparable {
    func clamped(to limites: ClosedRange<Self>) -> Self {
        min(max(self, limites.lowerBound), limites.upperBound)
    }
}

/// Busca da toolbar: filtra a tabela em Rede, Analytics e Relatório. Em Page
/// Objects a lupa da toolbar leva à busca da hierarquia, no inspector.
private struct SectionSearch: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        @Bindable var state = appState
        if appState.isDeviceConnected && appState.workspaceTab == .network {
            content.searchable(
                text: $state.httpFilterText,
                isPresented: $state.toolbarSearchPresented,
                placement: .toolbar,
                prompt: "Buscar ou filtrar: status:4xx metodo:POST tipo:json"
            )
            .searchSuggestions {
                sugestoes(SearchQuery.networkSuggestions, texto: appState.httpFilterText)
            }
        } else if appState.isDeviceConnected && appState.workspaceTab == .analytics {
            content.searchable(
                text: $state.analyticsFilterText,
                isPresented: $state.toolbarSearchPresented,
                placement: .toolbar,
                prompt: "Buscar ou filtrar: evento:screen_view param:chave=valor"
            )
            .searchSuggestions {
                sugestoes(SearchQuery.analyticsSuggestions, texto: appState.analyticsFilterText)
            }
        } else if appState.workspaceTab == .report {
            content.searchable(
                text: $state.reportFilterText,
                isPresented: $state.toolbarSearchPresented,
                placement: .toolbar,
                prompt: "Buscar em eventos, parâmetros e divergências"
            )
        } else {
            content
        }
    }
}

/// Tokens sugeridos no campo de busca, como o Console.app: aparecem enquanto
/// o campo está vazio ou termina em espaço, e completam o texto.
@ViewBuilder
private func sugestoes(_ tokens: [String], texto: String) -> some View {
    if texto.isEmpty || texto.hasSuffix(" ") {
        ForEach(tokens, id: \.self) { token in
            Text(token)
                .font(DSFont.mono(12))
                .searchCompletion(texto + token + (token.hasSuffix(":") ? "" : " "))
        }
    }
}

/// O título da janela continua sendo a seção (o menu Janela e o Mission
/// Control mostram "Rede HTTP", não "Mo baile"). No macOS 15 ou mais novo, o
/// título nativo sai da toolbar e o `MainToolbar` desenha título e subtítulo
/// antes do aparelho, na ordem do design system.
private struct ToolbarTitle: ViewModifier {
    let title: String
    let subtitle: String

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbar(removing: .title)
        } else {
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
        }
    }
}

/// O inspector mostra o detalhe da seleção da área: a hierarquia e os
/// atributos do aparelho, ou, no Relatório, o card do Figma da validação.
private struct InspectorContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.workspaceTab == .report {
            ReportCardInspector()
        } else {
            InspectorPane()
        }
    }
}
