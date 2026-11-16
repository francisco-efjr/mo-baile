import Foundation

struct UIElement: Identifiable, Hashable, Sendable {
    let id: UUID = UUID()
    let tag: String
    let className: String
    let resourceId: String
    let text: String
    let contentDesc: String
    let clickable: Bool
    let bounds: CGRect
    let area: Int
    let package: String
    let platform: Platform
    let depth: Int
    let parentIndex: Int?
    
    var chipType: ChipType {
        let lower = className.lowercased()
        if lower.contains("button") || lower.contains("xcuielementtypebutton") {
            return .button
        } else if lower.contains("edittext") || lower.contains("textfield") || lower.contains("xcuielementtypetextfield") || lower.contains("xcuielementtypesecuretextfield") {
            return .input
        } else if lower.contains("textview") || lower.contains("xcuielementtypestatictext") {
            return .text
        } else if lower.contains("window") || lower.contains("xcuielementtypewindow") || lower.contains("xcuielementtypeapplication") {
            return .window
        } else {
            return .view
        }
    }
    
    var center: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }
    
    var displayName: String {
        if !text.isEmpty { return text }
        if !contentDesc.isEmpty { return contentDesc }
        if !resourceId.isEmpty {
            // Extract short ID after the last '/'
            if let lastSlash = resourceId.lastIndex(of: "/") {
                return String(resourceId[resourceId.index(after: lastSlash)...])
            }
            return resourceId
        }
        return className
    }
    
    // Children are computed from the flat list using parentIndex
    func children(in elements: [UIElement]) -> [UIElement] {
        let selfIdx = elements.firstIndex(where: { $0.id == self.id })
        guard let idx = selfIdx else { return [] }
        return elements.filter { $0.parentIndex == idx }
    }
}
