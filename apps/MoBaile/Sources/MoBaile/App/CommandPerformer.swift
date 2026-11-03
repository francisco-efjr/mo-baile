import SwiftUI

/// Executa uma ação do registro (FLU-1).
///
/// Cada caso faz o mesmo que o botão ou o item de menu correspondente já
/// fazia: chama a `EngineSession` ou mexe no `AppState`. Menu e paleta passam
/// por aqui, então os dois executam do mesmo jeito.
@MainActor
struct CommandPerformer {
    let appState: AppState
    let session: EngineSession
    var themeManager: ThemeManager?
    /// Ajustes só abre pelo ambiente da view (`openSettings`).
    var openSettings: () -> Void = {}

    func perform(_ id: CommandID) {
        let raw = id.rawValue
        if raw.hasPrefix("device.select:") {
            let device = String(raw.dropFirst("device.select:".count))
            Task { await session.select(deviceID: device) }
            return
        }
        for area in WorkspaceTab.allCases where id == .area(area) {
            appState.selectedStepID = nil
            appState.workspaceTab = area
            return
        }
        for plataforma in Platform.allCases where id == .switchPlatform(plataforma) {
            Task { await session.switchPlatform(to: plataforma) }
            return
        }

        switch id {
        case .palette:
            appState.commandPalettePresented.toggle()
        case .settings:
            openSettings()
        case .restartEngine:
            Task { await session.restartEngine() }

        case .inspector:
            appState.toggleInspector()
        case .mirror:
            appState.toggleMirror()
        case .workspace:
            withAnimation(Motion.smooth()) { appState.workspaceVisible.toggle() }
        case .allPanels:
            withAnimation(Motion.smooth()) { appState.restoreAllPanels() }
        case .zen:
            withAnimation(Motion.smooth()) { appState.toggleZenMode() }
        case .appearance:
            if let themeManager { themeManager.setMode(themeManager.isDark ? .light : .dark) }
        case .search:
            appState.search()

        case .refreshDevices:
            Task { await session.refreshDevices() }
        case .captureNow:
            Task { await session.captureNow() }
        case .stream:
            Task {
                if appState.streamActive { await session.stopStream() } else { await session.startStream() }
            }
        case .bootSimulator:
            Task { await session.bootSimulator() }
        case .bootEmulator:
            Task { await session.bootEmulator() }
        case .scrcpy:
            Task { await session.toggleScrcpy() }

        case .startWDA:
            Task { await session.startWDA() }
        case .proxy:
            Task { await session.toggleProxy() }
        case .debugNet:
            Task { await session.toggleDebugNet() }
        case .analytics:
            Task { await session.toggleAnalytics() }

        case .passive:
            Task {
                if appState.passiveListening { await session.stopPassive() } else { await session.startPassive() }
            }
        case .screenRecording:
            Task {
                if appState.screenRecording { await session.stopScreenRecording() } else { await session.startScreenRecording() }
            }

        case .run:
            RunAutomationButton.run(appState: appState, session: session)
        case .stopRun:
            Task { await session.stopFlow() }
        case .structure:
            appState.showingStructure = true
        case .exportFlow:
            Task {
                if let caminho = await session.exportMaestroFlow() { Exporters.revealInFinder(caminho) }
            }
        case .save:
            Task { await session.saveCode() }
        case .copyActions:
            Exporters.copy(appState.actionsCode)
            appState.statusMessage = "Código das ações copiado"
        case .copyLocators:
            Exporters.copy(appState.locatorsCode)
            appState.statusMessage = "Localizadores copiados"
        case .clearSteps:
            appState.pendingClear = .steps

        case .exportHAR:
            Exporters.exportHAR(appState)
        case .clearTraffic:
            appState.pendingClear = .network
        case .diagnoseTraffic:
            Task { await session.diagnoseTraffic() }
        case .exportAnalytics:
            Exporters.exportAnalyticsJSON(appState)
        case .clearAnalytics:
            appState.pendingClear = .analytics

        case .openSpec:
            appState.workspaceTab = .report
            appState.selectedStepID = nil
            ReportActions.openSpec(session)
        case .importPrints:
            appState.workspaceTab = .report
            appState.selectedStepID = nil
            ReportActions.importPrints(appState, session)
        case .runReport:
            appState.workspaceTab = .report
            Task { await session.runReport() }
        case .exportReport:
            ReportActions.exportTo(session)

        default:
            assertionFailure("ação sem execução: \(raw)")
        }
    }
}
