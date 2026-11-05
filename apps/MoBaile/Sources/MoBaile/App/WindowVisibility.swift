import AppKit

/// Observa se a janela principal está à vista (PERF-1).
///
/// `occlusionState` cobre os quatro casos de uma vez: janela coberta por outra
/// (o PyCharm em cima), minimizada, app oculto (⌘H) e janela em outro Espaço.
/// É o sinal que a Apple recomenda para "trabalhar só quando visível". Com a
/// janela fora da vista, o espelho para de capturar no motor; ao voltar, retoma.
@MainActor
final class WindowVisibility {
    static let shared = WindowVisibility()

    private weak var window: NSWindow?
    private var observer: NSObjectProtocol?

    func observe(_ window: NSWindow, session: EngineSession) {
        guard window !== self.window else { return }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        self.window = window
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self, weak session] _ in
            // O observador é desta janela, na fila principal: lê o estado dela.
            MainActor.assumeIsolated {
                guard let janela = self?.window else { return }
                let visivel = janela.occlusionState.contains(.visible)
                Task { await session?.setWindowVisible(visivel) }
            }
        }
        // Estado de agora, e não só as mudanças: a janela pode já nascer
        // coberta (R6).
        let visivel = window.occlusionState.contains(.visible)
        Task { await session.setWindowVisible(visivel) }
    }
}
