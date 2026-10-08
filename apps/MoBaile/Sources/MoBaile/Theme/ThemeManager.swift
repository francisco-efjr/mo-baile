import SwiftUI
import AppKit

/// Escolhe o conjunto de tokens em uso.
///
/// Combina três entradas: a aparência pedida em Ajustes (Sistema, Claro ou
/// Escuro), a aparência efetiva do macOS (quando o pedido é Sistema) e a opção
/// de acessibilidade Aumentar contraste, que troca os rótulos, separadores e o
/// destaque por versões mais fortes.
@Observable
class ThemeManager {
    private(set) var mode: ThemeMode = .system
    private(set) var increaseContrast = false
    private(set) var current: any ThemeTokens = PraiaLightTheme()

    @ObservationIgnored private var appearanceObserver: NSKeyValueObservation?
    @ObservationIgnored private var contrastObserver: NSObjectProtocol?
    @ObservationIgnored private let defaults: UserDefaults

    static let modeKey = "mobaile.aparencia"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let salvo = defaults.string(forKey: Self.modeKey), let modo = ThemeMode(rawValue: salvo) {
            mode = modo
        }
        increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        updateTheme()

        if let app = NSApp {
            appearanceObserver = app.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in self?.updateTheme() }
            }
        }
        contrastObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                self?.updateTheme()
            }
        }
    }

    deinit {
        if let contrastObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(contrastObserver)
        }
    }

    func setMode(_ newMode: ThemeMode) {
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Self.modeKey)
        updateTheme()
    }

    private func updateTheme() {
        let dark: Bool
        switch mode {
        case .system:
            if let app = NSApp {
                dark = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            } else {
                dark = false
            }
        case .dark:
            dark = true
        case .light:
            dark = false
        }
        current = dark
            ? PraiaDarkTheme(highContrast: increaseContrast)
            : PraiaLightTheme(highContrast: increaseContrast)
    }

    var isDark: Bool { current.isDark }

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
