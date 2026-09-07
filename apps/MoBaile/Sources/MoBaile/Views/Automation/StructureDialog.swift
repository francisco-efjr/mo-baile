import SwiftUI

struct StructureDialog: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Estrutura do Fluxo")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(theme.current.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(theme.current.bgPanel)
            
            Divider()
            
            // Table
            Table(appState.steps) {
                TableColumn("#") { step in
                    Text("\(step.stepNum)")
                        .font(.system(.body, design: .monospaced))
                }
                .width(30)
                
                TableColumn("Ação") { step in
                    Text(step.actionType)
                }
                .width(80)
                
                TableColumn("Elemento") { step in
                    Text(step.elementName)
                }
                .width(120)
                
                TableColumn("Estratégia") { step in
                    Text(String(describing: step.strategy))
                }
                .width(80)
                
                TableColumn("Coordenadas/Seletor") { step in
                    if let coords = step.coords {
                        Text("x: \(Int(coords.x)), y: \(Int(coords.y))")
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text(step.locatorValue)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .frame(minHeight: 300)
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                FluidPillButton(text: "Copiar resumo", style: .secondary) {
                    let summary = appState.steps.map { "\($0.stepNum). \($0.actionType) \($0.elementName)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary, forType: .string)
                }
                
                FluidPillButton(text: "Fechar", style: .primary) {
                    onClose()
                }
            }
            .padding()
            .background(theme.current.bgPanel)
        }
        .frame(width: 600)
        .background(theme.current.bgWindow)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.current.borderStrong, lineWidth: 1))
    }
}
