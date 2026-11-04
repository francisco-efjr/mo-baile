import AppKit
import SwiftUI

/// Estado da árvore Projeto (PO-5): o que está aberto, a seleção e a busca
/// rápida (speed search) como na tool window Project do PyCharm. Sem view,
/// para ser testado.
@Observable
final class ProjetoModelo {
    var arvore: EngineDTO.WorkspaceTree?
    var carregando = false
    var erro: String?
    /// Pastas abertas, pelo caminho relativo. Começa com as de primeiro nível.
    var expandidas: Set<String> = []
    var selecionado: String?
    /// Busca rápida: o que a pessoa digitou com o foco na árvore.
    var busca = ""

    struct Linha: Identifiable, Equatable {
        let no: EngineDTO.WorkspaceNode
        let nivel: Int
        var id: String { no.path }
    }

    func receber(_ nova: EngineDTO.WorkspaceTree) {
        if arvore == nil { expandidas = Set(nova.nodes.map(\.path)) }
        arvore = nova
        erro = nil
    }

    /// Linhas visíveis, só dentro das pastas abertas (o PyCharm também só
    /// procura nos nós expandidos).
    var linhas: [Linha] { achatar(arvore?.nodes ?? [], nivel: 0, todas: false) }

    private func achatar(_ nos: [EngineDTO.WorkspaceNode], nivel: Int, todas: Bool) -> [Linha] {
        nos.flatMap { no -> [Linha] in
            var saida = [Linha(no: no, nivel: nivel)]
            if let filhos = no.children, todas || expandidas.contains(no.path) {
                saida += achatar(filhos, nivel: nivel + 1, todas: todas)
            }
            return saida
        }
    }

    func alternar(_ caminho: String) {
        if expandidas.contains(caminho) { expandidas.remove(caminho) } else { expandidas.insert(caminho) }
    }

    func expandirTudo() {
        expandidas = Set(achatar(arvore?.nodes ?? [], nivel: 0, todas: true).filter(\.no.isDirectory).map(\.id))
    }

    func recolherTudo() { expandidas = [] }

    /// Localizar arquivo aberto: abre as pastas acima e seleciona.
    func revelar(_ caminho: String) {
        var partes = caminho.split(separator: "/").map(String.init)
        partes.removeLast()
        var atual = ""
        for parte in partes {
            atual = atual.isEmpty ? parte : "\(atual)/\(parte)"
            expandidas.insert(atual)
        }
        selecionado = caminho
    }

    /// O nome casa com a busca? Sem caixa, em qualquer posição.
    func casa(_ nome: String) -> Range<String.Index>? {
        busca.isEmpty ? nil : nome.range(of: busca, options: [.caseInsensitive, .diacriticInsensitive])
    }

    /// Digitar na árvore: acrescenta à busca e pula para o primeiro que casa.
    func digitar(_ texto: String) {
        busca += texto
        if let atual = selecionado, let linha = linhas.first(where: { $0.id == atual }), casa(linha.no.name) != nil {
            return
        }
        selecionado = linhas.first { casa($0.no.name) != nil }?.id
    }

    /// ↑ e ↓ com a busca aberta passam só pelos que casam.
    func proximoQueCasa(paraBaixo: Bool) {
        let candidatas = linhas.filter { casa($0.no.name) != nil }
        guard !candidatas.isEmpty else { return }
        let indice = candidatas.firstIndex { $0.id == selecionado }
        let proximo = indice.map { (paraBaixo ? $0 + 1 : $0 - 1 + candidatas.count) % candidatas.count } ?? 0
        selecionado = candidatas[proximo].id
    }
}

/// Painel Projeto: a pasta de trabalho servida pelo motor (`workspace.tree`),
/// no modelo da tool window Project do PyCharm. Sem vidro: é conteúdo (ADR 0006).
struct ProjectTreeView: View {
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    let modelo: ProjetoModelo
    /// Caminho do arquivo no editor, para "Localizar Arquivo Aberto".
    let arquivoAberto: String?
    let abrir: (String) -> Void
    let ocultar: () -> Void

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            // Cabeçalho próprio, e não `PaneHeader`: com cinco ações o título
            // quebrava em "Projet/o" na largura padrão do painel.
            HStack(spacing: 4) {
                Text("Projeto")
                    .font(DSFont.subheadlineSemibold)
                    .foregroundStyle(theme.labelSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                acoes
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(height: DesignMetrics.Heights.paneHeader)
            Rectangle().fill(theme.separator).frame(height: 1)
            conteudo.frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.bgContent)
        // Primeira leitura aqui só se ninguém leu ainda; quem carrega é a
        // aba Page Objects, que fica de pé quando o painel some e volta.
        .task { if modelo.arvore == nil, modelo.erro == nil { await recarregar() } }
    }

    private var acoes: some View {
        HStack(spacing: 0) {
            BarIconButton(icon: "scope", label: "Localizar Arquivo Aberto") {
                if let arquivoAberto { modelo.revelar(arquivoAberto) }
            }
            .disabled(arquivoAberto == nil)
            BarIconButton(icon: "rectangle.expand.vertical", label: "Expandir Tudo") { modelo.expandirTudo() }
            BarIconButton(icon: "rectangle.compress.vertical", label: "Recolher Tudo") { modelo.recolherTudo() }
            Menu {
                Button("Atualizar") { Task { await recarregar() } }
                Button("Revelar no Finder") { revelarNoFinder(modelo.selecionado) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Opções")
            .accessibilityLabel("Opções do Projeto")
            BarIconButton(icon: "minus", label: "Ocultar Projeto", action: ocultar)
        }
    }

    @ViewBuilder
    private var conteudo: some View {
        if !session.isConnected {
            EmptyState(icon: "bolt.horizontal", text: "Motor não conectado.", compact: true)
        } else if let erro = modelo.erro {
            InlineError(title: "Não deu para ler a pasta", text: erro, actionLabel: "Tentar de Novo") {
                Task { await recarregar() }
            }
        } else if let arvore = modelo.arvore {
            if !arvore.exists || arvore.nodes.isEmpty {
                EmptyState(
                    icon: "folder",
                    text: "A pasta \(abreviar(arvore.root)) ainda não tem pages, locators nem flows. Salve um Page Object (⌘S) para criá-la.",
                    compact: true
                )
            } else {
                lista(arvore)
            }
        } else {
            EmptyState(text: "Lendo a pasta…", loading: true, compact: true)
        }
    }

    private func lista(_ arvore: EngineDTO.WorkspaceTree) -> some View {
        @Bindable var modelo = modelo
        let theme = themeManager.current
        return List(selection: $modelo.selecionado) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(theme.accentText).accessibilityHidden(true)
                Text(arvore.name).foregroundStyle(theme.labelPrimary)
                Text(abreviar(arvore.root)).foregroundStyle(theme.labelTertiary).lineLimit(1).truncationMode(.middle)
            }
            .font(DSFont.callout)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Projeto \(arvore.name), \(abreviar(arvore.root))")
            .selectionDisabled()
            ForEach(modelo.linhas) { linha in
                linhaView(linha).tag(linha.id)
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 22)
        .accessibilityLabel("Árvore do projeto")
        .contextMenu(forSelectionType: String.self) { selecao in
            Button("Revelar no Finder") { revelarNoFinder(selecao.first) }
        } primaryAction: { selecao in
            guard let caminho = selecao.first else { return }
            if modelo.linhas.first(where: { $0.id == caminho })?.no.isDirectory == true {
                modelo.alternar(caminho)
            } else {
                modelo.busca = ""
                abrir(caminho)
            }
        }
        .onKeyPress(phases: .down) { tecla in teclado(tecla) }
        .overlay(alignment: .top) { campoDeBusca }
    }

    private func linhaView(_ linha: ProjetoModelo.Linha) -> some View {
        let theme = themeManager.current
        let no = linha.no
        let aberta = modelo.expandidas.contains(no.path)
        return HStack(spacing: 4) {
            if no.isDirectory {
                Button { modelo.alternar(no.path) } label: {
                    Image(systemName: aberta ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.labelTertiary)
                .accessibilityHidden(true)
            } else {
                Color.clear.frame(width: 12)
            }
            Image(systemName: icone(no))
                .foregroundStyle(no.isDirectory ? theme.labelSecondary : theme.syntaxFunction)
                .accessibilityHidden(true)
            Text(nomeRealcado(no.name))
                .lineLimit(1)
        }
        .font(DSFont.callout)
        .padding(.leading, CGFloat(linha.nivel) * 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(no.isDirectory ? "pasta \(no.name)" : "arquivo \(no.name)")
        .accessibilityValue(no.isDirectory ? (aberta ? "expandida" : "recolhida") : "")
    }

    /// Parte casada com a busca rápida realçada, como no PyCharm.
    private func nomeRealcado(_ nome: String) -> AttributedString {
        var texto = AttributedString(nome)
        if let faixa = modelo.casa(nome), let inicio = AttributedString.Index(faixa.lowerBound, within: texto),
           let fim = AttributedString.Index(faixa.upperBound, within: texto) {
            texto[inicio..<fim].backgroundColor = themeManager.current.warning.opacity(0.35)
        }
        return texto
    }

    @ViewBuilder
    private var campoDeBusca: some View {
        if !modelo.busca.isEmpty {
            let theme = themeManager.current
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                Text(modelo.busca)
            }
            .font(DSFont.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.bgContentAlt, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.separator))
            .padding(6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Busca rápida na árvore")
            .accessibilityValue(modelo.busca)
        }
    }

    /// Letras abrem a busca rápida; ← → recolhem e expandem; com a busca
    /// aberta, ↑ ↓ passam entre os que casam e ⎋ fecha.
    private func teclado(_ tecla: KeyPress) -> KeyPress.Result {
        let buscando = !modelo.busca.isEmpty
        switch tecla.key {
        case .escape where buscando: modelo.busca = ""; return .handled
        case .upArrow where buscando: modelo.proximoQueCasa(paraBaixo: false); return .handled
        case .downArrow where buscando: modelo.proximoQueCasa(paraBaixo: true); return .handled
        case .leftArrow, .rightArrow:
            guard let caminho = modelo.selecionado,
                  modelo.linhas.first(where: { $0.id == caminho })?.no.isDirectory == true else { return .ignored }
            if (tecla.key == .rightArrow) != modelo.expandidas.contains(caminho) { modelo.alternar(caminho) }
            return .handled
        case .delete where buscando:
            modelo.busca.removeLast()
            return .handled
        default:
            break
        }
        // ⌘+ e ⌘- expandem e recolhem tudo, como no PyCharm.
        if tecla.modifiers == .command, tecla.characters == "+" || tecla.characters == "=" { modelo.expandirTudo(); return .handled }
        if tecla.modifiers == .command, tecla.characters == "-" { modelo.recolherTudo(); return .handled }
        guard tecla.modifiers.isDisjoint(with: [.command, .control, .option]),
              let escalar = tecla.characters.unicodeScalars.first,
              tecla.characters.unicodeScalars.count == 1,
              CharacterSet.alphanumerics.union(.punctuationCharacters).contains(escalar) else { return .ignored }
        modelo.digitar(tecla.characters)
        return .handled
    }

    private func icone(_ no: EngineDTO.WorkspaceNode) -> String {
        if no.isDirectory { return "folder" }
        return no.name.hasSuffix(".py") ? "chevron.left.forwardslash.chevron.right" : "doc.text"
    }

    private func abreviar(_ caminho: String) -> String {
        let casa = NSHomeDirectory()
        return caminho.hasPrefix(casa) ? "~" + caminho.dropFirst(casa.count) : caminho
    }

    private func revelarNoFinder(_ relativo: String?) {
        guard let raiz = modelo.arvore?.root else { return }
        let url = URL(fileURLWithPath: raiz).appendingPathComponent(relativo ?? "")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func recarregar() async {
        guard session.isConnected else { return }
        modelo.carregando = true
        defer { modelo.carregando = false }
        do {
            modelo.receber(try await session.workspaceTree())
        } catch {
            modelo.erro = error.localizedDescription
        }
    }
}

/// Faixa de tool windows à esquerda da área (PO-5), como a do PyCharm:
/// Projeto alterna a árvore e Hierarquia alterna o inspector que já existe.
struct ToolWindowStripe: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    /// Projeto ligado, mas a coluna está estreita demais para mostrá-lo.
    var semEspaco = false

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 4) {
            BarIconButton(icon: "folder", label: "Projeto", isOn: appState.projectTreeVisible) {
                withAnimation(Motion.smooth()) { appState.projectTreeVisible.toggle() }
            }
            .help(semEspaco ? "Projeto: sem espaço nesta largura. Oculte o espelho ou o inspector" : "Projeto")
            .accessibilityValue(semEspaco ? "sem espaço" : (appState.projectTreeVisible ? "ligado" : "desligado"))
            BarIconButton(icon: "list.bullet.indent", label: "Hierarquia", isOn: appState.inspectorShown) {
                appState.toggleInspector()
            }
            .disabled(appState.inspectorSuppressed)
            .accessibilityValue(appState.inspectorShown ? "ligado" : "desligado")
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: 32)
        .background(theme.bgContent)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.separator).frame(width: 1) }
    }
}
