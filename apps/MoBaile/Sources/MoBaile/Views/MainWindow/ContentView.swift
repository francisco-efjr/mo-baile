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
                .navigationSplitViewColumnWidth(
                    min: DesignMetrics.Widths.sidebarMin,
                    ideal: DesignMetrics.Widths.sidebarIdeal,
                    max: DesignMetrics.Widths.sidebarMax
                )
        } detail: {
            DetailColumn()
                .modifier(SectionSearch())
                .modifier(ToolbarTitle(title: windowTitle, subtitle: windowSubtitle))
                .toolbar { MainToolbar(title: windowTitle, subtitle: windowSubtitle) }
                .inspector(isPresented: $state.inspectorVisible) {
                    InspectorContent()
                        .inspectorColumnWidth(
                            min: DesignMetrics.Widths.inspectorMin,
                            ideal: DesignMetrics.Widths.inspectorIdeal,
                            max: DesignMetrics.Widths.inspectorMax
                        )
                        .toolbar {
                            ToolbarItem(placement: .automatic) { InspectorToggleButton() }
                        }
                }
        }
        .tint(theme.accent)
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
        .onDisappear {
            Task { await session.disconnect() }
        }
    }

    // MARK: - Título

    /// O título mostra a seção, nunca o nome do app.
    private var windowTitle: String {
        if !appState.workspaceTab.needsDevice { return appState.workspaceTab.displayName }
        return appState.isDeviceConnected ? appState.workspaceTab.displayName : "Sem dispositivo"
    }

    private var windowSubtitle: String {
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
            Group {
                if !appState.workspaceTab.needsDevice {
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

        HSplitView {
            if appState.mirrorVisible {
                MirrorPane(compact: compacto && mostraWorkspace)
                    .frame(
                        minWidth: compacto ? DesignMetrics.Widths.mirrorCompactMin : DesignMetrics.Widths.mirrorMin,
                        idealWidth: compacto ? DesignMetrics.Widths.mirrorCompactIdeal : DesignMetrics.Widths.mirrorIdeal,
                        maxWidth: mostraWorkspace
                            ? (compacto ? DesignMetrics.Widths.mirrorCompactMax : DesignMetrics.Widths.mirrorMax)
                            : .infinity
                    )
            }
            if mostraWorkspace {
                WorkspacePane()
                    .frame(minWidth: DesignMetrics.Widths.workspaceMin, maxWidth: .infinity)
            }
        }
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
                prompt: "Buscar em URL, headers e corpo"
            )
        } else if appState.isDeviceConnected && appState.workspaceTab == .analytics {
            content.searchable(
                text: $state.analyticsFilterText,
                isPresented: $state.toolbarSearchPresented,
                placement: .toolbar,
                prompt: "Buscar em eventos, parâmetros e log"
            )
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
