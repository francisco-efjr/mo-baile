import SwiftUI

/// Janela principal.
///
/// Antes, as tres colunas eram literalmente `Text("Mirror")`, `Text("Hierarchy")`
/// e `Text("Workspace")`: as telas existiam no projeto, prontas, mas nenhuma
/// estava ligada. Aqui elas entram, dentro de um `HSplitView`, que e o
/// comportamento que o usuario de Mac espera de painel lateral e o que o
/// documento de design pede ("paineis redimensionaveis").
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        @Bindable var state = appState

        ZStack {
            VStack(spacing: 0) {
                UnifiedToolbar()

                if appState.isDeviceConnected {
                    HSplitView {
                        if appState.mirrorVisible {
                            MirrorColumn()
                        } else {
                            CollapsedRail(label: "Espelho", shortcut: "⌥1", isExpanded: $state.mirrorVisible)
                        }

                        if appState.hierarchyVisible {
                            HierarchyColumn()
                        } else {
                            CollapsedRail(label: "Hierarquia", shortcut: "⌥2", isExpanded: $state.hierarchyVisible)
                        }

                        if appState.workspaceVisible {
                            WorkspaceColumn()
                                .frame(minWidth: 420)
                        } else {
                            CollapsedRail(label: "Workspace", shortcut: "⌥3", isExpanded: $state.workspaceVisible)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                StatusBar()
            }

            if appState.showingFlowRunner {
                FlowRunnerModal(
                    locatorKey: session.engineInfo?.pageObjectsKey ?? "fluxo",
                    onClose: {
                        withAnimation(.easeIn(duration: 0.15)) {
                            appState.showingFlowRunner = false
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)
            }
        }
        .background(theme.bgWindow)
        .task {
            // Sobe o motor junto com a janela. Sem isto, a aplicacao ficava
            // permanentemente no estado vazio.
            await session.connect()
        }
        .onDisappear {
            Task { await session.disconnect() }
        }
    }
}
