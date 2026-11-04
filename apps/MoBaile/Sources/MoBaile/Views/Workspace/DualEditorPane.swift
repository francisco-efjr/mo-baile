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
    /// Árvore Projeto e arquivos abertos dela, em abas (PO-5).
    @State private var projeto = ProjetoModelo()
    /// Aba suja esperando "Salvar / Descartar / Cancelar" para fechar (R-02).
    @State private var fechando: String?
    @SceneStorage("larguraProjeto") private var larguraProjeto = 220.0
    /// Abaixo disto a árvore não aparece: o editor ficaria estreito demais.
    static let larguraMinimaComArvore: CGFloat = 640
    /// Posição do cursor no último editor que mexeu (rodapé, PO-4). Só o
    /// rodapé lê: mover o cursor não reavalia esta view (R-06).
    @State private var cursor = CursorDoEditor()

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

            GeometryReader { geo in
                // Coluna estreita (espelho e inspector abertos): a árvore sai
                // de cena e o editor fica com o espaço; a escolha continua.
                let cabe = geo.size.width >= Self.larguraMinimaComArvore
                HStack(spacing: 0) {
                    ToolWindowStripe(semEspaco: appState.projectTreeVisible && !cabe)
                    if appState.projectTreeVisible && cabe {
                        ProjectTreeView(
                            modelo: projeto, arquivoAberto: appState.arquivoAtivo ?? caminhoDoPageObject,
                            abrir: abrir, ocultar: { appState.projectTreeVisible = false }
                        )
                        .frame(width: min(larguraProjeto, geo.size.width * 0.32))
                        .overlay(alignment: .trailing) { DivisoriaDoProjeto(largura: $larguraProjeto) }
                    }
                    VStack(spacing: 0) {
                        if !appState.arquivosAbertos.isEmpty { abas }
                        editor
                    }
                }
            }

            footer
        }
        .background(theme.bgContent)
        // O interpretador do rodapé vem do `setup.check`, que o Início já pede.
        .task {
            await projetoRecarregar()
            if session.setup == nil { await session.refreshSetup() }
        }
        // Salvar o Page Object cria ou muda arquivos da árvore.
        .onChange(of: appState.codigoSalvo) { Task { await projetoRecarregar() } }
        .confirmationDialog(
            "Salvar as alterações em \(fechando ?? "")?", isPresented: fechandoBinding, presenting: fechando
        ) { id in
            Button("Salvar") {
                Task { if await appState.salvarArquivo(id, sessao: session) { appState.fecharArquivo(id) } }
            }
            Button("Descartar Alterações", role: .destructive) { appState.fecharArquivo(id) }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("Se não salvar, o que você mudou nesta aba se perde.")
        }
        .alert(
            "\(appState.conflitoDeArquivo ?? "") mudou no disco", isPresented: conflitoBinding,
            presenting: appState.conflitoDeArquivo
        ) { id in
            Button("Recarregar do Disco") { Task { await appState.recarregarArquivo(id, sessao: session) } }
            Button("Sobrescrever", role: .destructive) {
                Task { await appState.salvarArquivo(id, sessao: session, sobrescrever: true) }
            }
            Button("Cancelar", role: .cancel) { appState.conflitoDeArquivo = nil }
        } message: { _ in
            Text("Outro programa gravou o arquivo depois que ele foi aberto aqui. Recarregar descarta o que você mudou nesta aba; sobrescrever apaga a versão do disco.")
        }
    }

    private var fechandoBinding: Binding<Bool> {
        Binding(get: { fechando != nil }, set: { if !$0 { fechando = nil } })
    }

    private var conflitoBinding: Binding<Bool> {
        Binding(get: { appState.conflitoDeArquivo != nil }, set: { if !$0 { appState.conflitoDeArquivo = nil } })
    }

    @ViewBuilder
    private var editor: some View {
        @Bindable var state = appState
        let theme = themeManager.current
        ZStack {
            if appState.arquivoAtivo == nil {
                editorDoPageObject
            }
            // Um editor por aba, todos vivos e só o da frente visível: cada
            // arquivo guarda o próprio desfazer, cursor e rolagem (R-03).
            ForEach($state.arquivosAbertos) { $aberto in
                let ligado = appState.arquivoAtivo == aberto.id
                ArquivoAbertoPane(aberto: $aberto, cursor: cursor)
                    .id(aberto.id)
                    .opacity(ligado ? 1 : 0)
                    .allowsHitTesting(ligado)
                    .accessibilityHidden(!ligado)
            }
        }
        .background(theme.bgContent)
    }

    @ViewBuilder
    private var editorDoPageObject: some View {
        @Bindable var state = appState
        let theme = themeManager.current
        if vazio {
            VStack(spacing: 0) {
                EmptyState(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Nenhum passo gravado",
                    text: "Clique em um elemento no espelho. O toque vai para o aparelho e vira um locator e um método do Page Object.",
                    actionLabel: appState.isDeviceConnected ? "Gravar Passo" : nil,
                    action: {
                        appState.statusMessage = "Clique em um elemento no espelho: ele vira um passo"
                    }
                )
                .frame(maxHeight: 260)
                DicasDoEditorVazio()
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 0) {
                if appState.splitEditors || arquivo == .pages {
                    CodeEditorPane(file: .pages, text: $state.actionsCode, cursor: cursor)
                }
                if appState.splitEditors {
                    Rectangle().fill(theme.separator).frame(width: 1)
                }
                if appState.splitEditors || arquivo == .locators {
                    CodeEditorPane(file: .locators, text: $state.locatorsCode, cursor: cursor)
                }
            }
        }
    }

    /// Abas como as do PyCharm: o Page Object da sessão e os arquivos abertos
    /// da árvore, cada um com ×.
    private var abas: some View {
        let theme = themeManager.current
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                aba(titulo: "Page Object", id: nil, sujo: false, fechar: nil)
                ForEach(appState.arquivosAbertos) { aberto in
                    aba(titulo: aberto.arquivo.path, id: aberto.id, sujo: aberto.sujo) { pedirParaFechar(aberto.id) }
                }
            }
        }
        .frame(height: 28)
        .background(theme.bgContent)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    private func aba(titulo: String, id: String?, sujo: Bool, fechar: (() -> Void)?) -> some View {
        let theme = themeManager.current
        let ligada = appState.arquivoAtivo == id
        return HStack(spacing: 4) {
            // "•" antes do nome: alteração não salva, como o asterisco do PyCharm.
            Button(sujo ? "• \(titulo)" : titulo) { appState.arquivoAtivo = id }
                .accessibilityLabel(titulo)
                .accessibilityValue(sujo ? "não salvo" : "")
                .buttonStyle(.plain)
                .font(DSFont.mono(11.5))
                .foregroundStyle(ligada ? theme.labelPrimary : theme.labelSecondary)
                .accessibilityAddTraits(ligada ? .isSelected : [])
            if let fechar {
                Button(action: fechar) { Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.labelTertiary)
                    .help("Fechar \(titulo)")
                    .accessibilityLabel("Fechar \(titulo)")
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) { if ligada { Rectangle().fill(theme.accentText).frame(height: 2) } }
    }

    /// `pages/<chave>.py` e `locators/<chave>.py` da sessão vão para o editor
    /// do Page Object; o resto abre numa aba, lido pelo motor.
    private func abrir(_ caminho: String) {
        let chave = session.engineInfo?.pageObjectsKey ?? "feature"
        if let proprio = EditorFile.allCases.first(where: { caminho == "\($0.rawValue)/\(chave).py" }) {
            arquivo = proprio
            appState.arquivoAtivo = nil
            return
        }
        Task { await appState.abrirArquivo(caminho, sessao: session) }
    }

    /// × numa aba suja pergunta antes (R-02); limpa fecha direto.
    private func pedirParaFechar(_ id: String) {
        guard let indice = appState.indiceDoArquivo(id), appState.arquivosAbertos[indice].sujo else {
            appState.fecharArquivo(id)
            return
        }
        fechando = id
    }

    private func projetoRecarregar() async {
        guard session.isConnected else { return }
        do {
            projeto.receber(try await session.workspaceTree())
        } catch is CancellationError {
        } catch {
            projeto.erro = error.localizedDescription
        }
    }

    private var caminhoDoPageObject: String {
        "\(arquivo.rawValue)/\(session.engineInfo?.pageObjectsKey ?? "feature").py"
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
            // Status do editor como no PyCharm, no lugar do "Código
            // sincronizado" fixo, que dizia "sincronizado" mesmo sem salvar.
            ViewThatFits(in: .horizontal) {
                statusDoEditor(compacto: false)
                statusDoEditor(compacto: true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: DesignMetrics.Heights.codeFooter)
        .background(theme.bgContent)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    private func statusDoEditor(compacto: Bool) -> some View {
        let aberto = appState.arquivosAbertos.first { $0.id == appState.arquivoAtivo }
        return EditorStatusBar(
            cursor: cursor,
            python: session.setup?.python.version, pythonPath: session.setup?.python.path,
            salvamento: aberto.map(\.salvamento) ?? EditorStatus.salvamento(
                acoes: appState.actionsCode, locators: appState.locatorsCode, salvo: appState.codigoSalvo
            ),
            caminho: aberto?.arquivo.path ?? appState.codigoSalvo?.caminho, compacto: compacto,
            separador: aberto?.arquivo.lineSeparator ?? "LF", codificacao: aberto?.arquivo.encoding ?? "UTF-8"
        )
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
    var cursor: CursorDoEditor? = nil

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
                highlight: appState.selectedStep?.varName,
                cursor: cursor
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// O nome do arquivo carrega a chave do Page Object, que é o que dá nome
    /// aos arquivos gravados.
    private var nomeDoArquivo: String {
        "\(session.engineInfo?.pageObjectsKey ?? "feature").py"
    }

    private var contagemDeLinhas: String { EditorText.rotuloDeLinhas(text) }
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
