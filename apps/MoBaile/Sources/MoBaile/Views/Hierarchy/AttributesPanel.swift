import SwiftUI

struct AttributesPanel: View {
    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var themeManager
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("ATRIBUTOS")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundColor(themeManager.current.textLabel ?? Color.gray)
                    .tracking(0.09) // letter-spacing .09em
                
                Spacer()
                
                Button(action: copyAll) {
                    Text("Copiar tudo")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(themeManager.current.accent ?? Color.blue)
                }
                .buttonStyle(.plain)
            }
            
            if let element = appState.selectedElement {
                ScrollView {
                    VStack(spacing: 4) {
                        AttributeRow(key: "type", value: element.className ?? "-")
                        AttributeRow(key: "name", value: element.resourceId ?? "-")
                        AttributeRow(key: "label", value: element.text ?? element.contentDesc ?? "-")
                        AttributeRow(key: "bounds", value: string(from: element.bounds))
                        AttributeRow(key: "center", value: string(from: element.center))
                        AttributeRow(key: "enabled", value: element.clickable == true ? "true" : "false")
                    }
                }
            } else {
                Text("Nenhum elemento selecionado")
                    .font(.system(size: 10.5))
                    .foregroundColor(themeManager.current.textSecondary ?? Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding()
        .frame(minHeight: 38)
        .background(themeManager.current.bgPanel ?? Color.clear)
    }
    
    private func copyAll() {
        // Implement copy all
    }
    
    private func string(from rect: CGRect?) -> String {
        guard let rect = rect else { return "-" }
        return "[\(Int(rect.minX)),\(Int(rect.minY))][\(Int(rect.maxX)),\(Int(rect.maxY))]"
    }
    
    private func string(from point: CGPoint?) -> String {
        guard let point = point else { return "-" }
        return "[\(Int(point.x)),\(Int(point.y))]"
    }
}

struct AttributeRow: View {
    @Environment(ThemeManager.self) var themeManager
    let key: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(themeManager.current.textLabel ?? Color.gray)
                .frame(width: 82, alignment: .leading)
            
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(themeManager.current.textPrimary ?? Color.primary)
                .lineSpacing(1.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
