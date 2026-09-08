import SwiftUI

struct FlowRunnerModal: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var theme
    
    let locatorKey: String
    let onClose: () -> Void
    
    var body: some View {
        ZStack {
            // Scrim
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture {
                    if appState.runState != .running {
                        withAnimation(.easeIn(duration: 0.15)) { onClose() }
                    }
                }
            
            // Modal Panel
            VStack(spacing: 0) {
                // Header (44px)
                HStack {
                    Text("Executar fluxo · \(locatorKey)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.current.textPrimary)
                    
                    // Status Badge
                    statusBadge
                        .padding(.leading, 8)
                    
                    Spacer()
                    
                    // Preconditions
                    HStack(spacing: 12) {
                        if appState.platform == .android {
                            Text("ADB \(appState.daemonStatus.adb == .ok ? "✓" : "✗")")
                        } else {
                            Text("WDA 8100 \(appState.daemonStatus.wda == .ok ? "✓" : "✗")")
                        }
                        Text("·")
                        Text("Proxy 8082 \(appState.daemonStatus.proxy == .ok ? "✓" : "✗")")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(theme.current.textSecondary)
                }
                .frame(height: 44)
                .padding(.horizontal, 16)
                .background(theme.current.bgPanel)
                
                Divider().background(theme.current.borderStrong)
                
                // Progress
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.current.bgControlTrack)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.current.success)
                                .frame(width: max(0, geo.size.width * progressPercentage))
                                .animation(.spring(), value: progressPercentage)
                        }
                    }
                    .frame(height: 5)
                    
                    HStack {
                        Spacer()
                        Text("passo \(appState.currentRunStep) / \(max(1, appState.stepCount))")
                            .font(.system(size: 10))
                            .foregroundColor(theme.current.textLabel)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // Body Columns
                HStack(spacing: 16) {
                    // Left Column (Steps)
                    StepsList()
                        .frame(width: 334)
                        .background(theme.current.bgContent)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.current.border, lineWidth: 1)
                        )
                    
                    // Right Column (Terminal)
                    TerminalView()
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
                
                Divider().background(theme.current.borderStrong)
                    .padding(.top, 16)
                
                // Footer (52px)
                HStack {
                    // Summary
                    Text("\(appState.steps.filter { $0.actionType != "fail" }.count) aprovados · \(appState.runState == .failed ? 1 : 0) falhas · tempo 0.0 s")
                        .font(.system(size: 12))
                        .foregroundColor(theme.current.textSecondary)
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        FluidPillButton(text: "Abrir log", icon: "doc.plaintext", style: .secondary) {
                            abrirLog()
                        }
                        
                        if appState.runState == .running {
                            FluidPillButton(text: "Interromper", icon: "stop.fill", style: .destructiveText) {
                                Task { await session.stopFlow() }
                            }
                        } else {
                            FluidPillButton(text: "Concluir", style: .primary) {
                                withAnimation(.easeIn(duration: 0.15)) { onClose() }
                            }
                        }
                    }
                }
                .frame(height: 52)
                .padding(.horizontal, 16)
                .background(theme.current.bgPanel)
            }
            .frame(width: 860, height: 580)
            .background(theme.current.bgWindow)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(theme.current.borderStrong, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
        }
    }

    private func abrirLog() {
        let texto = appState.runLog.map {
            "[\($0.timestamp.formatted(date: .omitted, time: .standard))] [\($0.prefix)] \($0.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mobaile-flow-run.log")
        try? texto.write(to: tempURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(tempURL)
        appState.statusMessage = "Log copiado e aberto no editor"
    }
    
    private var statusBadge: some View {
        Group {
            switch appState.runState {
            case .running:
                Text("EM EXECUÇÃO")
                    .foregroundColor(theme.current.successText)
                    .background(theme.current.successBg)
            case .passed:
                Text("CONCLUÍDO")
                    .foregroundColor(theme.current.successText)
                    .background(theme.current.successBg)
            case .failed:
                Text("FALHA")
                    .foregroundColor(.white)
                    .background(theme.current.danger)
            case .idle:
                Text("PRONTO")
                    .foregroundColor(theme.current.textSecondary)
                    .background(theme.current.bgControlTrack)
            }
        }
        .font(.system(size: 10, weight: .bold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .cornerRadius(4)
    }
    
    private var progressPercentage: CGFloat {
        guard appState.stepCount > 0 else { return 0 }
        return CGFloat(appState.currentRunStep) / CGFloat(appState.stepCount)
    }
}
