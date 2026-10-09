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
            Section("Workspace") {
                ForEach(WorkspaceTab.allCases) { area in
                    Label {
                        Text(area.displayName)
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
            SidebarBottomBar()
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
                case nil:
                    break
                }
            }
        )
    }

    private func contagem(_ area: WorkspaceTab) -> Int {
        switch area {
        case .pageObjects: return appState.steps.count
        case .network: return appState.httpRequests.count
        case .analytics: return appState.analyticsEvents.count
        case .report: return appState.reportBadgeCount
        }
    }

    @ViewBuilder
    private func menu(do passo: AutomationStep) -> some View {
        Button("Mostrar no Código") {
            appState.selectedStepID = passo.id
            appState.workspaceTab = .pageObjects
        }
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

/// Barra inferior de 32 pt: Gravar Passo e o estado do aparelho.
private struct SidebarBottomBar: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        HStack(spacing: 1) {
            Button {
                appState.interactionMode = .record
                appState.workspaceTab = .pageObjects
                appState.selectedStepID = nil
                appState.statusMessage = "Gravar passo: clique em um elemento no espelho"
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 31, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BarIconButtonStyle(theme: theme))
            .disabled(!appState.isDeviceConnected)
            .help("Gravar Passo: o próximo clique no espelho vira um passo")
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
        case .pageObjects: return "chevron.left.forwardslash.chevron.right"
        case .network: return "network"
        case .analytics: return "chart.xyaxis.line"
        case .report: return "checklist"
        }
    }

    /// As áreas têm cor por categoria (flamingo, azul, verde). O Relatório é a
    /// auditoria do Analytics e fica na mesma categoria.
    func categoryColor(_ theme: any ThemeTokens) -> Color {
        switch self {
        case .pageObjects: return theme.cat1
        case .network: return theme.cat3
        case .analytics, .report: return theme.cat2
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
