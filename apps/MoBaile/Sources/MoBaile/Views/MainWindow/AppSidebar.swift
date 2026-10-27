import SwiftUI

/// O que está escolhido na barra lateral: uma área do workspace ou um passo.
enum SidebarSelection: Hashable {
    case area(WorkspaceTab)
    case step(UUID)
}

/// Barra lateral: seção Workspace (Page Objects, Rede HTTP, Analytics) e
/// seção Fluxo (passos gravados). A barra inferior grava um passo e mostra o
/// estado do aparelho.
///
/// Os passos antes só apareciam dentro do modal de execução. Na barra lateral
/// eles ficam à vista o tempo todo, e escolher um destaca o código dele.
struct AppSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        List(selection: selecao) {
            // Início fica acima das áreas, sem seção e sem contagem: é o ponto de
            // partida. O que falta instalar conta no Ambiente, no rodapé (3.11.0).
            Label {
                Text(WorkspaceTab.home.displayName)
            } icon: {
                Image(systemName: WorkspaceTab.home.symbolName)
                    .foregroundStyle(WorkspaceTab.home.categoryColor(theme))
            }
            .tag(SidebarSelection.area(.home))

            Section("Workspace") {
                ForEach(WorkspaceTab.workspaceAreas) { area in
                    Label {
                        HStack(spacing: DesignMetrics.Spacing.s3) {
                            Text(area.displayName)
                            Spacer(minLength: DesignMetrics.Spacing.s2)
                            // O atalho aparece enquanto não há contagem: com
                            // contagem, ela é a informação que importa.
                            if contagem(area) == 0 {
                                Text("⌘\(area.shortcutDigit)")
                                    .font(DSFont.mono(10.5))
                                    .foregroundStyle(theme.labelTertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                    } icon: {
                        Image(systemName: area.symbolName)
                            .foregroundStyle(area.categoryColor(theme))
                    }
                    .badge(contagem(area))
                    .tag(SidebarSelection.area(area))
                    .accessibilityValue(contagem(area) == 0 ? "" : "\(contagem(area))")
                }
            }

            Section("Fluxo · \(session.engineInfo?.pageObjectsKey ?? "fluxo")") {
                if appState.steps.isEmpty {
                    Text("Nenhum passo gravado.")
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelSecondary)
                        .selectionDisabled()
                } else {
                    ForEach(Array(appState.steps.enumerated()), id: \.element.id) { indice, passo in
                        StepSidebarRow(passo: passo, numero: indice + 1)
                            .tag(SidebarSelection.step(passo.id))
                            .contextMenu { menu(do: passo) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // A Praia usa o material do sistema (vibrancy), que já é o fundo
        // dela. Uma paleta alternativa tem cor própria de barra lateral.
        .scrollContentBackground(themeManager.palette == nil ? .automatic : .hidden)
        .background(themeManager.palette == nil ? Color.clear : theme.bgSidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                SidebarEnvironmentItem(pending: contagem(.environment))
                SidebarBottomBar()
            }
        }
    }

    private var selecao: Binding<SidebarSelection?> {
        Binding(
            get: {
                if let id = appState.selectedStepID { return .step(id) }
                return .area(appState.workspaceTab)
            },
            set: { nova in
                switch nova {
                case .area(let area):
                    appState.selectedStepID = nil
                    appState.workspaceTab = area
                case .step(let id):
                    appState.selectedStepID = id
                    appState.workspaceTab = .pageObjects
                    correlacionar(id)
                case nil:
                    break
                }
            }
        )
    }

    private func contagem(_ area: WorkspaceTab) -> Int {
        switch area {
        case .home: return 0
        case .environment: return session.home?.environment.pending.count ?? session.setup?.pending ?? 0
        case .pageObjects: return appState.steps.count
        case .network: return appState.httpRequests.count
        case .analytics: return appState.analyticsEvents.count
        case .report: return appState.reportBadgeCount
        }
    }

    /// Pede ao motor a janela do passo; sem hora gravada (passo antigo) não há o que correlacionar.
    private func correlacionar(_ id: UUID) {
        guard let passo = appState.steps.first(where: { $0.id == id }), passo.recordedAt != nil else {
            appState.correlation = nil
            return
        }
        Task { await session.correlate(step: passo) }
    }

    @ViewBuilder
    private func menu(do passo: AutomationStep) -> some View {
        Button("Mostrar no Código") {
            appState.selectedStepID = passo.id
            appState.workspaceTab = .pageObjects
            correlacionar(passo.id)
        }
        Button("Ver na Rede") {
            appState.selectedStepID = passo.id
            correlacionar(passo.id)
            appState.workspaceTab = .network
        }
        .disabled(passo.recordedAt == nil)
        Button("Ver em Analytics") {
            appState.selectedStepID = passo.id
            correlacionar(passo.id)
            appState.workspaceTab = .analytics
        }
        .disabled(passo.recordedAt == nil)
        Button("Copiar Locator") {
            Exporters.copy(passo.varName)
            appState.statusMessage = "Locator \(passo.varName) copiado"
        }
        Button("Copiar Seletor") {
            Exporters.copy(passo.selectorDescription)
            appState.statusMessage = "Seletor copiado"
        }
        Divider()
        Button("Limpar Passos…", role: .destructive) {
            appState.pendingClear = .steps
        }
    }
}

/// Linha de um passo: ícone da ação, "click BOTAO", e o texto digitado
/// mascarado. O texto de um passo de digitação pode ser CPF ou senha, e a
/// barra lateral fica à vista o tempo todo.
private struct StepSidebarRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let passo: AutomationStep
    let numero: Int

    var body: some View {
        let theme = themeManager.current
        Label {
            HStack(spacing: 6) {
                Text("\(passo.actionType) \(passo.displayElement)")
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let mascara = passo.maskedInput {
                    Text(mascara)
                        .font(DSFont.mono(10.5))
                        .foregroundStyle(theme.labelTertiary)
                        .accessibilityLabel("texto digitado oculto")
                }
            }
        } icon: {
            Image(systemName: passo.symbolName)
                .foregroundStyle(theme.labelSecondary)
        }
        .help("Passo \(numero) · \(passo.actionType) · \(passo.strategy.displayName)")
        .accessibilityLabel("Passo \(numero): \(passo.actionType) \(passo.displayElement)")
    }
}

/// Ambiente, fixo no rodapé da barra lateral, acima da barra inferior: fica à
/// vista mesmo com muitos passos na seção Fluxo. A contagem amarela é o que
/// falta instalar e some quando é zero. ⌘5.
private struct SidebarEnvironmentItem: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    let pending: Int

    @State private var hover = false

    var body: some View {
        let theme = themeManager.current
        let escolhido = appState.workspaceTab == .environment && appState.selectedStepID == nil
        Button {
            appState.selectedStepID = nil
            appState.workspaceTab = .environment
        } label: {
            HStack(spacing: DesignMetrics.Spacing.s4) {
                Image(systemName: WorkspaceTab.environment.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(escolhido ? theme.onAccent : theme.labelSecondary)
                    .frame(width: 18)
                Text(WorkspaceTab.environment.displayName)
                    .font(DSFont.body)
                    .foregroundStyle(escolhido ? theme.onAccent : theme.labelPrimary)
                Spacer(minLength: DesignMetrics.Spacing.s2)
                if pending > 0 {
                    Text("\(pending)")
                        .font(DSFont.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.black.opacity(0.78))
                        .padding(.horizontal, 6)
                        .frame(minHeight: 16)
                        .background(theme.warningFill, in: Capsule())
                } else {
                    Text("⌘5")
                        .font(DSFont.mono(10.5))
                        .foregroundStyle(escolhido ? theme.onAccent.opacity(0.8) : theme.labelTertiary)
                }
            }
            .padding(.horizontal, DesignMetrics.Spacing.s4)
            .frame(height: 28)
            .background(
                escolhido ? theme.selection : (hover ? theme.fillSecondary : .clear),
                in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.sidebarItem, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.horizontal, 10)
        .padding(.vertical, DesignMetrics.Spacing.s2)
        .help("Ambiente: o que está instalado nesta máquina (⌘5)")
        .accessibilityLabel("Ambiente")
        .accessibilityValue(pending == 0 ? "tudo pronto" : (pending == 1 ? "1 pendente" : "\(pending) pendentes"))
        .accessibilityAddTraits(escolhido ? [.isButton, .isSelected] : .isButton)
    }
}

/// Barra inferior de 32 pt: Gravar Passo e o estado do aparelho.
private struct SidebarBottomBar: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 1) {
            Button {
                appState.workspaceTab = .pageObjects
                appState.selectedStepID = nil
                appState.statusMessage = "Clique em um elemento no espelho: ele vira um passo"
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 31, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BarIconButtonStyle(theme: theme))
            .disabled(!appState.isDeviceConnected)
            .help("Gravar Passo: cada clique no espelho vira um passo")
            .accessibilityLabel("Gravar Passo")

            Spacer(minLength: 6)

            StatusIndicator(status: estado, label: rotulo, mono: false)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 8)
        .frame(height: DesignMetrics.Heights.sidebarBottomBar)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    private var estado: DaemonState {
        if appState.isDeviceConnected { return .ok }
        return session.lastScan == nil ? .busy : .off
    }

    private var rotulo: String {
        if let nome = appState.selectedDeviceName { return "\(nome) conectado" }
        return session.lastScan == nil ? "Procurando…" : "Sem aparelho"
    }
}

extension WorkspaceTab {
    var symbolName: String {
        switch self {
        case .home: return "house"
        case .pageObjects: return "chevron.left.forwardslash.chevron.right"
        case .network: return "network"
        case .analytics: return "chart.xyaxis.line"
        case .report: return "checklist"
        case .environment: return "slider.horizontal.3"
        }
    }

    /// As áreas têm cor por categoria (flamingo, azul, verde). O Relatório é a
    /// auditoria do Analytics e fica na mesma categoria.
    func categoryColor(_ theme: any ThemeTokens) -> Color {
        switch self {
        case .home: return theme.accent
        case .pageObjects: return theme.cat1
        case .network: return theme.cat3
        case .analytics, .report: return theme.cat2
        case .environment: return theme.labelSecondary
        }
    }
}

extension AutomationStep {
    /// Nome que o passo mostra: o elemento, ou o seletor quando não há nome.
    /// O passo por coordenada não tem elemento: o motor chama de `position`,
    /// que é valor interno. Na interface ele é "toque em x, y".
    var displayElement: String {
        if strategy == .coords || elementName == "position" {
            if let coords { return "toque em \(Int(coords.x)), \(Int(coords.y))" }
            return "toque por coordenada"
        }
        return elementName.isEmpty ? locatorValue : elementName
    }

    /// Frase curta do passo, para a Correlação e o leitor de tela.
    var summarySentence: String {
        "\(actionType) \(displayElement) · \(strategy.displayName)"
    }

    var symbolName: String {
        if strategy == .coords { return "viewfinder" }
        return actionType == "send_keys" ? "keyboard" : "cursorarrow.click"
    }

    /// O texto digitado nunca aparece: só o tamanho, em pontos.
    var maskedInput: String? {
        guard let inputText, !inputText.isEmpty else { return nil }
        return String(repeating: "•", count: min(inputText.count, 6))
    }

    var selectorDescription: String {
        if let coords { return "x: \(Int(coords.x)), y: \(Int(coords.y))" }
        return locatorValue
    }
}
