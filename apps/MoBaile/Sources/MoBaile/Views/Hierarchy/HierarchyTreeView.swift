import SwiftUI

struct TreeNode: Identifiable {
    let id = UUID()
    let element: UIElement
    var children: [TreeNode]? = nil
}

struct HierarchyTreeView: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        let tree = buildTree()
        
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
    
    func buildTree() -> [TreeNode] {
        let elements = appState.hierarchyElements
        let searchText = appState.hierarchySearchText.lowercased()
        
        var filteredElements = elements
        if !searchText.isEmpty {
            filteredElements = elements.filter {
                $0.text.lowercased().contains(searchText) ||
                $0.resourceId.lowercased().contains(searchText) ||
                $0.className.lowercased().contains(searchText) ||
                $0.contentDesc.lowercased().contains(searchText)
            }
        }
        
        return filteredElements.map { TreeNode(element: $0, children: nil) }
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
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? themeManager.current.selectionBg : Color.clear)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? themeManager.current.selectionBorder : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .padding(.leading, CGFloat(node.element.depth) * 18.0)
    }
}
