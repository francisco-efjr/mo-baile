import SwiftUI
import AppKit

@Observable
class ThemeManager {
    var mode: ThemeMode = .system
    
    private(set) var current: any ThemeTokens = PraiaDarkTheme()
    
    private var appearanceObserver: NSKeyValueObservation?
    
    init() {
        updateTheme()
        // Observe system appearance changes
        if let app = NSApp {
            appearanceObserver = app.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in
                    self?.updateTheme()
                }
            }
        }
    }
    
    func setMode(_ newMode: ThemeMode) {
        mode = newMode
        updateTheme()
    }
    
    private func updateTheme() {
        switch mode {
        case .system:
            if let app = NSApp {
                let appearance = app.effectiveAppearance
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                current = isDark ? PraiaDarkTheme() : PraiaLightTheme()
            } else {
                current = PraiaDarkTheme() // fallback for tests
            }
        case .dark:
            current = PraiaDarkTheme()
        case .light:
            current = PraiaLightTheme()
        }
    }
    
    var isDark: Bool {
        current.id == "praia_dark"
    }

    /// Esquema entregue ao SwiftUI.
    ///
    /// `nil` no modo sistema e intencional: deixa o macOS decidir, que e o que
    /// faz a janela acompanhar a troca automatica de aparencia ao anoitecer.
    var preferredColorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
