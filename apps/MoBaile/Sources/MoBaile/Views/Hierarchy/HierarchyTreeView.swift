import SwiftUI

struct TreeNode: Identifiable, Equatable {
    var id: UUID { element.id }
    let element: UIElement
    var children: [TreeNode]?

    init(element: UIElement, children: [TreeNode]? = nil) {
        self.element = element
        self.children = children
    }

    static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs.element.id == rhs.element.id
    }
}

/// Árvore de acessibilidade: a mesma que o Appium enxerga, igual para iOS e
/// Android. Lista nativa com triângulos de expandir, setas do teclado e menu
/// de contexto.
struct HierarchyTreeView: View {
    @Environment(AppState.self) var appState
    @Environment(EngineSession.self) var session
    @Environment(ThemeManager.self) var themeManager

    var body: some View {
        let tree = Self.buildTree(
            from: appState.hierarchyElements,
            filterText: appState.hierarchySearchText
        )

        if !appState.isDeviceConnected {
            EmptyState(icon: "list.bullet.indent", text: "Conecte um aparelho para ver a hierarquia da tela.", compact: true)
        } else if appState.hierarchyElements.isEmpty {
            EmptyState(text: "Lendo a hierarquia…", loading: true, compact: true)
        } else if tree.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "Nenhum elemento encontrado",
                text: "Nada corresponde a “\(appState.hierarchySearchText)”.",
                compact: true
            )
        } else {
            let linhas = Self.flatten(tree, recolhidos: buscando ? [] : recolhidos)
            List(selection: selecao) {
                ForEach(linhas) { linha in
                    HierarchyRow(
                        node: linha.node,
                        depth: buscando ? 0 : linha.depth,
                        hasChildren: !buscando && linha.temFilhos,
                        expanded: !recolhidos.contains(linha.id),
                        toggle: { alternar(linha.id) }
                    )
                    .tag(linha.id)
                    .contextMenu { menu(linha.node.element) }
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 24)
            .accessibilityLabel("Árvore de acessibilidade")
            // ← recolhe e → expande o nó escolhido, como no Finder.
            .onKeyPress(.leftArrow) {
                guard let id = appState.selectedElement?.id else { return .ignored }
                recolhidos.insert(id)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard let id = appState.selectedElement?.id else { return .ignored }
                recolhidos.remove(id)
                return .handled
            }
        }
    }

    /// Nós recolhidos. A árvore abre expandida, como no Appium Inspector: o
    /// elemento escolhido no espelho fica à vista sem precisar abrir pasta.
    @State private var recolhidos: Set<UUID> = []

    private var buscando: Bool {
        !appState.hierarchySearchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func alternar(_ id: UUID) {
        if recolhidos.contains(id) { recolhidos.remove(id) } else { recolhidos.insert(id) }
    }

    struct Linha: Identifiable {
        let node: TreeNode
        let depth: Int
        var id: UUID { node.id }
        var temFilhos: Bool { node.children?.isEmpty == false }
    }

    /// Achata a árvore em linhas com profundidade, pulando os filhos dos nós
    /// recolhidos.
    static func flatten(_ nodes: [TreeNode], recolhidos: Set<UUID>, depth: Int = 0) -> [Linha] {
        nodes.flatMap { node -> [Linha] in
            var linhas = [Linha(node: node, depth: depth)]
            if let filhos = node.children, !recolhidos.contains(node.id) {
                linhas += flatten(filhos, recolhidos: recolhidos, depth: depth + 1)
            }
            return linhas
        }
    }

    private var selecao: Binding<UUID?> {
        Binding(
            get: { appState.selectedElement?.id },
            set: { id in
                appState.selectedElement = id.flatMap { alvo in
                    appState.hierarchyElements.first { $0.id == alvo }
                }
            }
        )
    }

    @ViewBuilder
    private func menu(_ element: UIElement) -> some View {
        Button("Copiar Locator") {
            Exporters.copy(element.locatorValue)
            appState.statusMessage = "Locator copiado"
        }
        Button("Copiar XPath") {
            Exporters.copy(element.xpath)
            appState.statusMessage = "XPath copiado"
        }
        Button("Copiar Atributos") {
            Exporters.copy(element.attributesText)
            appState.statusMessage = "Atributos copiados"
        }
        Divider()
        // Gravar também toca no aparelho, como o clique no espelho em "Gravar
        // passo": gravar um fluxo exige navegar por ele.
        Button("Gravar como Passo") {
            appState.workspaceTab = .pageObjects
            Task { await session.record(at: element.center) }
        }
        .disabled(!appState.isDeviceConnected)
    }

    /// Constrói a árvore de acessibilidade real respeitando o parentIndex de cada elemento.
    ///
    /// Antes devolvia todos os nós com `children: nil` e simulava o aninhamento com recuo
    /// artificial, sem triângulos de expansão/recolhimento.
    static func buildTree(from elements: [UIElement], filterText: String = "") -> [TreeNode] {
        guard !elements.isEmpty else { return [] }

        var childrenMap = [Int: [Int]]()
        var isChild = [Bool](repeating: false, count: elements.count)

        for (idx, elem) in elements.enumerated() {
            if let p = elem.parentIndex, p >= 0, p < elements.count, p != idx {
                childrenMap[p, default: []].append(idx)
                isChild[idx] = true
            }
        }

        var visited = Set<Int>()

        func buildNode(at index: Int) -> TreeNode {
            visited.insert(index)
            let elem = elements[index]
            let childIndices = (childrenMap[index] ?? []).filter { !visited.contains($0) }
            let children: [TreeNode]? = childIndices.isEmpty ? nil : childIndices.map { buildNode(at: $0) }
            return TreeNode(element: elem, children: children)
        }

        var roots: [TreeNode] = []
        for idx in 0..<elements.count {
            if !isChild[idx] && !visited.contains(idx) {
                roots.append(buildNode(at: idx))
            }
        }
        // Fallback defensivo para qualquer nó não visitado (ex.: ciclos ou índices quebrados)
        for idx in 0..<elements.count {
            if !visited.contains(idx) {
                roots.append(buildNode(at: idx))
            }
        }

        let termo = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !termo.isEmpty else { return roots }

        // Filtra preservando os ancestrais dos nós que casam com o termo
        func filterNode(_ node: TreeNode) -> TreeNode? {
            let matches = node.element.displayName.lowercased().contains(termo) ||
                          node.element.resourceId.lowercased().contains(termo) ||
                          node.element.className.lowercased().contains(termo) ||
                          node.element.contentDesc.lowercased().contains(termo) ||
                          node.element.text.lowercased().contains(termo)

            let filteredChildren = node.children?.compactMap { filterNode($0) }

            if matches || (filteredChildren != nil && !filteredChildren!.isEmpty) {
                return TreeNode(
                    element: node.element,
                    children: (filteredChildren?.isEmpty == false) ? filteredChildren : nil
                )
            }
            return nil
        }

        return roots.compactMap { filterNode($0) }
    }
}

struct HierarchyRow: View {
    @Environment(ThemeManager.self) var themeManager
    let node: TreeNode
    var depth: Int = 0
    var hasChildren: Bool = false
    var expanded: Bool = true
    var toggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 5) {
            Color.clear.frame(width: CGFloat(depth) * DesignMetrics.treeIndent, height: 1)
            Group {
                if hasChildren {
                    Button(action: toggle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .animation(Motion.snappy(), value: expanded)
                            .frame(width: 12, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "Recolher" : "Expandir")
                } else {
                    Color.clear.frame(width: 12, height: 1)
                }
            }
            TypeChip(type: node.element.chipType)
            Text(node.element.displayName)
                .font(DSFont.callout)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(node.element.className)
        .accessibilityElement(children: .combine)
        .accessibilityValue(hasChildren ? (expanded ? "expandido" : "recolhido") : "")
    }
}

extension UIElement {
    /// O que o motor usaria como localizador por ID: o identificador, ou o
    /// texto quando não há identificador.
    var locatorValue: String {
        if !resourceId.isEmpty { return resourceId }
        if !contentDesc.isEmpty { return contentDesc }
        return text
    }

    /// XPath pelo atributo que identifica o elemento em cada plataforma.
    var xpath: String {
        let atributo = platform == .ios ? "name" : "resource-id"
        if !resourceId.isEmpty { return "//\(className)[@\(atributo)=\"\(resourceId)\"]" }
        if !text.isEmpty { return "//\(className)[@\(platform == .ios ? "label" : "text")=\"\(text)\"]" }
        if !contentDesc.isEmpty { return "//\(className)[@\(platform == .ios ? "label" : "content-desc")=\"\(contentDesc)\"]" }
        return "//\(className)"
    }

    /// Atributos na ordem do painel. "clickable" é o que o motor informa; não
    /// há "enabled" na árvore, e o rótulo antigo dizia o contrário.
    var attributeRows: [(key: String, value: String)] {
        [
            ("type", className),
            ("name", resourceId),
            ("label", text.isEmpty ? contentDesc : text),
            ("bounds", "[\(Int(bounds.minX)),\(Int(bounds.minY))][\(Int(bounds.maxX)),\(Int(bounds.maxY))]"),
            ("center", "[\(Int(center.x)),\(Int(center.y))]"),
            ("clickable", clickable ? "true" : "false"),
        ]
    }

    var attributesText: String {
        attributeRows.map { "\($0.key): \($0.value.isEmpty ? "—" : $0.value)" }.joined(separator: "\n")
    }
}
