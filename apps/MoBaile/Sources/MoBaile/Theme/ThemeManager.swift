import SwiftUI
import AppKit

/// Escolhe o conjunto de tokens em uso.
///
/// Combina quatro entradas: a paleta escolhida em Ajustes › Paletas, a
/// aparência pedida em Ajustes › Geral (Sistema, Claro ou Escuro), a aparência
/// efetiva do macOS (quando o pedido é Sistema) e a opção de acessibilidade
/// Aumentar contraste, que troca os rótulos, separadores e o destaque por
/// versões mais fortes.
///
/// A Praia, padrão, tem versão clara e escura e segue a aparência. As paletas
/// alternativas são só claras ou só escuras, e escolher uma define a aparência
/// do app.
@Observable
class ThemeManager {
    private(set) var mode: ThemeMode = .system
    private(set) var paletteID: String = PaletteSpec.praiaID
    private(set) var increaseContrast = false
    private(set) var current: any ThemeTokens = PraiaLightTheme()

    @ObservationIgnored private var appearanceObserver: NSKeyValueObservation?
    @ObservationIgnored private var contrastObserver: NSObjectProtocol?
    @ObservationIgnored private let defaults: UserDefaults
    /// Tema fixo de uma prévia (cartão da galeria). Não lê nem grava ajustes.
    @ObservationIgnored private let fixed: (any ThemeTokens)?

    static let modeKey = "mobaile.aparencia"
    static let paletteKey = "mobaile.paleta"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.fixed = nil
        if let salvo = defaults.string(forKey: Self.modeKey), let modo = ThemeMode(rawValue: salvo) {
            mode = modo
        }
        if let salva = defaults.string(forKey: Self.paletteKey), PaletteSpec.find(salva) != nil {
            paletteID = salva
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

    /// Gerenciador de prévia: devolve sempre `theme`, para desenhar um cartão
    /// da galeria com os componentes de verdade nas cores de outra paleta.
    init(preview theme: any ThemeTokens) {
        self.defaults = .standard
        self.fixed = theme
        self.current = theme
        self.mode = theme.isDark ? .dark : .light
    }

    deinit {
        if let contrastObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(contrastObserver)
        }
    }

    func setMode(_ newMode: ThemeMode) {
        guard fixed == nil else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: Self.modeKey)
        updateTheme()
    }

    /// Escolhe a paleta. `PaletteSpec.praiaID` volta para a Praia.
    func setPalette(_ id: String) {
        guard fixed == nil else { return }
        paletteID = PaletteSpec.find(id) == nil ? PaletteSpec.praiaID : id
        defaults.set(paletteID, forKey: Self.paletteKey)
        updateTheme()
    }

    /// Paleta alternativa em uso, ou `nil` na Praia.
    var palette: PaletteSpec? { PaletteSpec.find(paletteID) }

    private func updateTheme() {
        if let fixed {
            current = fixed
            return
        }
        if let palette {
            current = PaletteTheme(spec: palette, highContrast: increaseContrast)
            return
        }
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
    /// Uma paleta alternativa impõe a aparência dela. Na Praia, `nil` no modo
    /// sistema e intencional: deixa o macOS decidir, que e o que faz a janela
    /// acompanhar a troca automatica de aparencia ao anoitecer.
    var preferredColorScheme: ColorScheme? {
        if let palette { return palette.isDark ? .dark : .light }
        if fixed != nil { return current.isDark ? .dark : .light }
        switch mode {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}
