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

struct HierarchyTreeView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager

    var body: some View {
        let tree = Self.buildTree(
            from: appState.hierarchyElements,
            filterText: appState.hierarchySearchText
        )

        if appState.hierarchyElements.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 24))
                    .foregroundColor(themeManager.current.textDisabled)
                Text(appState.isDeviceConnected ? "Hierarquia vazia ou carregando…" : "Conecte um dispositivo")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.current.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tree.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundColor(themeManager.current.textDisabled)
                Text("Nenhum elemento encontrado")
                    .font(.system(size: 11))
                    .foregroundColor(themeManager.current.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(tree, children: \.children) { node in
                HierarchyRow(node: node, selectedElement: appState.selectedElement) {
                    appState.selectedElement = node.element
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 22)
        }
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
    let selectedElement: UIElement?
    let action: () -> Void

    var isSelected: Bool {
        selectedElement?.id == node.element.id
    }

    var body: some View {
        HStack(spacing: 6) {
            TypeChip(type: node.element.chipType)
            Text(node.element.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(themeManager.current.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isSelected ? themeManager.current.selectionBg : Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? themeManager.current.selectionBorder : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
