import SwiftUI

struct StepsList: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(appState.steps) { step in
                    StepRow(
                        step: step,
                        isActive: appState.runState == .running && appState.steps.firstIndex(where: { $0.id == step.id }) == appState.currentRunStep,
                        isDone: appState.steps.firstIndex(where: { $0.id == step.id }) ?? 0 < appState.currentRunStep
                    )
                }
            }
            .padding(10)
        }
    }
}

private struct StepRow: View {
    @Environment(ThemeManager.self) private var theme
    let step: AutomationStep
    let isActive: Bool
    let isDone: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Group {
                if isDone {
                    Text("✓")
                        .foregroundColor(theme.current.success)
                        .frame(width: 16, height: 16)
                        .background(theme.current.bgPanel)
                        .cornerRadius(8)
                } else if isActive {
                    Text("◐")
                        .foregroundColor(theme.current.accent)
                        .frame(width: 16, height: 16)
                        .background(theme.current.selectionBg)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.current.selectionBorder, lineWidth: 1)
                        )
                        .fontWeight(.semibold)
                } else {
                    Text("·")
                        .foregroundColor(theme.current.textTertiary)
                        .frame(width: 16, height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.current.borderSubtle, lineWidth: 1)
                        )
                }
            }
            .font(.system(size: 11))
            
            // Description
            Text("\(step.actionType) \(step.elementName.isEmpty ? step.locatorValue : step.elementName)")
                .font(.system(size: 12))
                .foregroundColor(isActive ? theme.current.textPrimary : theme.current.textSecondary)
                .lineLimit(1)
            
            Spacer()
            
            // Optional input
            if let input = step.inputText {
                Text(input)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.current.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(isActive ? theme.current.selectionBg : Color.clear)
        .cornerRadius(8)
    }
}
