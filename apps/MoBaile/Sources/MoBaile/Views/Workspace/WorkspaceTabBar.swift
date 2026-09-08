import SwiftUI

/// Barra da coluna de workspace.
///
/// Era duas linhas de texto literal — `Text("Tabs: Page Objects | Rede HTTP |
/// Analytics")` e `Text("Strategy: ID | XPath | Coords")` — mais três botões com
/// corpo vazio. Parecia controle e não era: a troca de aba acontecia por outro
/// caminho e esta barra não participava dela.
struct WorkspaceTabBar: View {
    @Environment(AppState.self) var appState
    @Environment(EngineSession.self) var session
    @Environment(ThemeManager.self) var themeManager

    /// Abaixo disto a barra não cabe em uma linha. A coluna do workspace fica
    /// em 440pt quando as três colunas estão abertas, e nessa largura o
    /// conteúdo transbordava para fora dos dois lados: "Page Objects" saía pela
    /// esquerda e os botões pela direita, e a coluna parecia vazia.
    private static let larguraParaUmaLinha: CGFloat = 1040

    @State private var largura: CGFloat = 1040

    var body: some View {
        conteudo(estreita: largura < Self.larguraParaUmaLinha)
            .background(themeManager.current.bgSubtle ?? Color.clear)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { largura = geo.size.width }
                        .onChange(of: geo.size.width) { _, nova in largura = nova }
                }
            )
    }

    @ViewBuilder
    private func conteudo(estreita: Bool) -> some View {
        if estreita {
            VStack(spacing: 6) {
                abas
                HStack(spacing: 8) {
                    if appState.workspaceTab == .pageObjects { seletorDeEstrategiaCompacto }
                    Spacer(minLength: 4)
                    acoes(compactas: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else {
            linhaUnica
        }
    }

    private var linhaUnica: some View {
        HStack(spacing: 12) {
            abas

            Spacer(minLength: 8)

            // O seletor de estratégia só faz sentido na aba que gera código.
            if appState.workspaceTab == .pageObjects {
                SegmentedControl(
                    items: LocatorStrategy.allCases.map(\.displayName),
                    selectedIndex: estrategiaBinding
                )
                .accessibilityLabel("Estratégia de localizador")
            }

            Spacer(minLength: 8)

            acoes(compactas: false)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    private var abas: some View {
        SegmentedControl(
            items: WorkspaceTab.allCases.map(\.displayName),
            selectedIndex: abaBinding,
            badges: contagens
        )
        .accessibilityLabel("Aba do workspace")
    }

    /// Na coluna estreita a estratégia vira menu: quatro segmentos de texto
    /// sozinhos já passam de 300pt.
    private var seletorDeEstrategiaCompacto: some View {
        Menu {
            ForEach(LocatorStrategy.allCases) { estrategia in
                Button(estrategia.displayName) { appState.locatorStrategy = estrategia }
            }
        } label: {
            Text("Seletor: \(appState.locatorStrategy.displayName)")
                .font(.system(size: 11))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Estratégia de localizador")
    }

    @ViewBuilder
    private func acoes(compactas: Bool) -> some View {
            HStack(spacing: 8) {
                FluidPillButton(
                    text: compactas ? "\(appState.stepCount)" : "Estrutura · \(appState.stepCount)",
                    icon: compactas ? "list.number" : nil,
                    style: appState.steps.isEmpty ? .disabled : .secondary
                ) {
                    appState.showingStructure = true
                }
                .disabled(appState.steps.isEmpty)
                .help("Tabela ordenada dos passos gravados")

                FluidPillButton(
                    text: compactas ? "" : "Split",
                    icon: compactas ? "rectangle.split.2x1" : nil,
                    style: appState.splitEditors ? .primary : .secondary
                ) {
                    withAnimation(.easeOut(duration: 0.15)) { appState.splitEditors.toggle() }
                }
                .help("Mostra os dois editores lado a lado, ou só o de ações")

                FluidPillButton(
                    text: compactas ? "" : "Rodar",
                    icon: compactas ? "play.fill" : nil,
                    style: podeRodar ? .run : .disabled
                ) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        appState.showingFlowRunner = true
                    }
                    Task { await session.runFlow() }
                }
                .disabled(!podeRodar)
                .help(dicaDoRodar)
            }
    }

    /// Contagem por aba, para não ser preciso entrar na aba para saber se há o
    /// que ver nela.
    private var contagens: [Int?] {
        [
            appState.steps.isEmpty ? nil : appState.steps.count,
            appState.httpRequests.isEmpty ? nil : appState.httpRequests.count,
            appState.analyticsEvents.isEmpty ? nil : appState.analyticsEvents.count,
        ]
    }

    private var podeRodar: Bool {
        !appState.steps.isEmpty && appState.isDeviceConnected && appState.runState != .running
    }

    private var dicaDoRodar: String {
        if appState.steps.isEmpty { return "Grave ao menos um passo para poder rodar" }
        if !appState.isDeviceConnected { return "Conecte um aparelho para rodar o fluxo" }
        if appState.runState == .running { return "Execução em andamento" }
        return "Executa os passos gravados no aparelho"
    }

    private var abaBinding: Binding<Int> {
        Binding(
            get: { WorkspaceTab.allCases.firstIndex(of: appState.workspaceTab) ?? 0 },
            set: { indice in
                guard WorkspaceTab.allCases.indices.contains(indice) else { return }
                appState.workspaceTab = WorkspaceTab.allCases[indice]
            }
        )
    }

    private var estrategiaBinding: Binding<Int> {
        Binding(
            get: { LocatorStrategy.allCases.firstIndex(of: appState.locatorStrategy) ?? 0 },
            set: { indice in
                guard LocatorStrategy.allCases.indices.contains(indice) else { return }
                appState.locatorStrategy = LocatorStrategy.allCases[indice]
            }
        )
    }
}
