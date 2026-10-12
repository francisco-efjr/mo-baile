import AppKit
import SwiftUI

/// Arquivo mostrado quando os editores não estão lado a lado.
enum EditorFile: String, CaseIterable, Identifiable {
    case pages, locators
    var id: String { rawValue }
}

/// Workspace "Page Objects": dois editores (pages e locators) gerados a partir
/// dos passos gravados.
///
/// Seletor, Estrutura… e Lado a lado ficam na barra acessória, só sobre o
/// conteúdo. Sem lado a lado, um segmentado alterna entre pages e locators.
struct PageObjectsView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    @State private var arquivo: EditorFile = .pages

    var body: some View {
        @Bindable var state = appState
        let theme = themeManager.current

        VStack(spacing: 0) {
            AccessoryBar {
                // Com a coluna estreita, os segmentados viram pop-up e
                // Estrutura fica só com o ícone (o tooltip continua).
                ViewThatFits(in: .horizontal) {
                    barra(compacta: false)
                    barra(compacta: true)
                }
            }

            if vazio {
                EmptyState(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Nenhum passo gravado",
                    text: "Com “Gravar passo” ativo, clique em um elemento no espelho. Cada toque vira um locator e um método do Page Object.",
                    actionLabel: appState.isDeviceConnected ? "Gravar Passo" : nil,
                    action: {
                        appState.interactionMode = .record
                        appState.statusMessage = "Gravar passo ativo: clique em um elemento no espelho"
                    }
                )
            } else {
                HStack(spacing: 0) {
                    if appState.splitEditors || arquivo == .pages {
                        CodeEditorPane(file: .pages, text: $state.actionsCode)
                    }
                    if appState.splitEditors {
                        Rectangle().fill(theme.separator).frame(width: 1)
                    }
                    if appState.splitEditors || arquivo == .locators {
                        CodeEditorPane(file: .locators, text: $state.locatorsCode)
                    }
                }
            }

            footer
        }
        .background(theme.bgContent)
    }

    private func barra(compacta: Bool) -> some View {
        @Bindable var state = appState
        let theme = themeManager.current
        return HStack(spacing: 8) {
            if !compacta {
                Text("Seletor:")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
            }
            Picker("Estratégia de seletor", selection: $state.locatorStrategy) {
                ForEach(LocatorStrategy.allCases) { estrategia in
                    Text(estrategia.displayName).tag(estrategia)
                }
            }
            .modifier(EstiloDoSeletor(compacto: compacta))
            .help("Auto: o motor escolhe o localizador único mais robusto")

            Spacer(minLength: 8)

            if !appState.splitEditors {
                Picker("Arquivo", selection: $arquivo) {
                    ForEach(EditorFile.allCases) { Text($0.rawValue).tag($0) }
                }
                .modifier(EstiloDoSeletor(compacto: compacta))
            }

            Button {
                appState.showingStructure = true
            } label: {
                if compacta {
                    Image(systemName: "list.number")
                } else {
                    Label("Estrutura…", systemImage: "list.number")
                }
            }
            .disabled(appState.steps.isEmpty)
            .help("Estrutura do fluxo: tabela ordenada dos passos gravados")
            .accessibilityLabel("Estrutura do fluxo")
            .accessibilityValue(appState.stepCount == 1 ? "1 passo" : "\(appState.stepCount) passos")

            BarIconButton(
                icon: "rectangle.split.2x1",
                label: "Lado a lado",
                isOn: appState.splitEditors
            ) {
                withAnimation(Motion.smooth()) { appState.splitEditors.toggle() }
            }
            .help(appState.splitEditors ? "Mostrar um arquivo por vez" : "Mostrar pages e locators lado a lado")
            .accessibilityValue(appState.splitEditors ? "ligado" : "desligado")
        }
    }

    /// Sem passo e sem código: nada a mostrar nos editores.
    private var vazio: Bool {
        appState.steps.isEmpty && appState.actionsCode.isEmpty && appState.locatorsCode.isEmpty
    }

    private var footer: some View {
        let theme = themeManager.current
        return HStack(spacing: 8) {
            Text(rodape)
                .font(DSFont.mono(11))
                .foregroundStyle(theme.labelSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            StatusIndicator(status: .ok, label: "Código sincronizado", mono: false)
        }
        .padding(.horizontal, 12)
        .frame(height: DesignMetrics.Heights.codeFooter)
        .background(theme.bgContent)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    private var rodape: String {
        if let passo = appState.selectedStep, let indice = appState.steps.firstIndex(where: { $0.id == passo.id }) {
            return "passo \(indice + 1) · \(passo.actionType) · \(passo.strategy.displayName.lowercased())"
        }
        guard let passo = appState.steps.last else { return "nenhum passo" }
        return "passo \(appState.stepCount) · \(passo.actionType) · \(passo.strategy.displayName.lowercased())"
    }
}

/// Um editor com cabeçalho: pasta, arquivo, linhas e as ações.
struct CodeEditorPane: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    let file: EditorFile
    @Binding var text: String

    var body: some View {
        let theme = themeManager.current
        let cor = file == .pages ? theme.syntaxFunction : theme.accentText

        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(cor)
                    Text(file.rawValue)
                        .foregroundStyle(theme.labelSecondary)
                    Text("/")
                        .foregroundStyle(theme.labelTertiary)
                    Text(nomeDoArquivo)
                        .font(DSFont.mono(11.5))
                        .foregroundStyle(cor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(DSFont.callout)
                // Os ícones eram lidos pela descrição automática do símbolo e a
                // pasta e o arquivo, como textos soltos. Vira uma frase só.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Arquivo \(file.rawValue)/\(nomeDoArquivo)")
                .accessibilityValue(text.isEmpty ? "vazio" : contagemDeLinhas)

                Spacer(minLength: 6)

                Text(contagemDeLinhas)
                    .font(DSFont.subheadline.monospacedDigit())
                    .foregroundStyle(theme.labelSecondary)
                    .accessibilityHidden(true)

                BarIconButton(icon: "doc.on.doc", label: file == .pages ? "Copiar código das ações" : "Copiar localizadores") {
                    Exporters.copy(text)
                    appState.statusMessage = "Código copiado"
                }
                .disabled(text.isEmpty)

                // Salvar e Limpar agem sobre os dois arquivos e os passos, não
                // só sobre o editor do cabeçalho: o rótulo diz o que acontece.
                BarIconButton(icon: "square.and.arrow.down", label: "Salvar pages e locators") {
                    Task { await session.saveCode() }
                }
                .disabled(appState.actionsCode.isEmpty && appState.locatorsCode.isEmpty)

                BarIconButton(icon: "trash", label: "Limpar passos e código") {
                    appState.pendingClear = .steps
                }
                .disabled(appState.steps.isEmpty && text.isEmpty)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: DesignMetrics.Heights.editorHeader)
            .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }

            CodeEditorView(
                text: $text,
                accessibilityLabel: file == .pages ? "Código das ações (pages)" : "Código dos localizadores (locators)",
                highlight: appState.selectedStep?.varName
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// O nome do arquivo carrega a chave do Page Object, que é o que dá nome
    /// aos arquivos gravados.
    private var nomeDoArquivo: String {
        "\(session.engineInfo?.pageObjectsKey ?? "feature").py"
    }

    private var contagemDeLinhas: String {
        guard !text.isEmpty else { return "0 linhas" }
        let linhas = text.split(separator: "\n", omittingEmptySubsequences: false)
        let total = (linhas.last?.isEmpty == true && linhas.count > 1) ? (linhas.count - 1) : linhas.count
        return total == 1 ? "1 linha" : "\(total) linhas"
    }
}

/// Mantido com o nome antigo para os testes que desenham os editores.
typealias DualEditorPane = PageObjectsView

/// Segmentado na barra larga, pop-up na estreita.
private struct EstiloDoSeletor: ViewModifier {
    let compacto: Bool

    func body(content: Content) -> some View {
        if compacto {
            content.pickerStyle(.menu).labelsHidden().fixedSize()
        } else {
            content.pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
}
