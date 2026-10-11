import AppKit

/// Decide o que o monitor de teclado da paleta faz com cada tecla (R-01).
///
/// Função pura, separada da view para ser testada sem janela. O monitor local
/// do AppKit vê as teclas de todas as janelas do app; sem estas regras, com a
/// paleta aberta, setas, Esc e Return em Ajustes ou num painel de arquivo
/// mexiam na paleta escondida, e ⌘↑ e ⌥Return eram engolidos.
enum CommandPaletteKeyboard {
    /// O que fazer com a tecla.
    enum Action: Equatable {
        /// Move a seleção (1 para baixo, -1 para cima). A tecla é consumida.
        case move(Int)
        /// Executa a linha selecionada. A tecla é consumida.
        case execute
        /// Fecha a paleta. A tecla é consumida.
        case close
        /// Não é da paleta: a tecla segue para quem ia recebê-la.
        case passThrough
    }

    /// Onde a tecla chegou, lido do AppKit no momento do evento.
    struct Situation: Equatable {
        /// `AppState.commandPalettePresented`.
        var paletteOpen: Bool
        /// A janela do evento é a janela onde a paleta abriu.
        var eventInPaletteWindow: Bool
        /// Há uma janela modal do app (`NSApp.modalWindow`).
        var modalOpen: Bool
        /// A janela da paleta tem uma sheet por cima (`attachedSheet`).
        var sheetAttached: Bool
    }

    /// Códigos de tecla do teclado ANSI que a paleta usa.
    enum Key {
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
    }

    /// Modificadores que tiram a tecla da paleta. ⇧, Caps Lock e as marcas
    /// `.numericPad` e `.function` (que as setas sempre trazem) não contam.
    static let blockingModifiers: NSEvent.ModifierFlags = [.command, .option, .control]

    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, situation: Situation) -> Action {
        guard situation.paletteOpen,
              situation.eventInPaletteWindow,
              !situation.modalOpen,
              !situation.sheetAttached,
              modifiers.intersection(blockingModifiers).isEmpty
        else { return .passThrough }

        switch keyCode {
        case Key.down: return .move(1)
        case Key.up: return .move(-1)
        case Key.returnKey, Key.keypadEnter: return .execute
        case Key.escape: return .close
        default: return .passThrough
        }
    }
}
