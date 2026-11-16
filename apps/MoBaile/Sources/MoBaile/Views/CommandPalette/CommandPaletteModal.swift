import AppKit
import SwiftUI

/// Tira o conteúdo de trás da árvore do VoiceOver enquanto a paleta está
/// aberta (A11Y-01).
///
/// `.accessibilityAddTraits(.isModal)` no painel não basta no SwiftUI
/// hospedado pelo AppKit: o VoiceOver seguia navegando pela janela de trás.
/// Aplicado a cada coluna da janela principal (`ContentView`). A toolbar é do
/// AppKit e fica de fora.
struct HiddenBehindCommandPalette: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content.accessibilityHidden(appState.commandPalettePresented)
    }
}

/// Onde o foco estava antes de a paleta abrir, para devolver ao fechar (A11Y-01).
enum CommandPaletteFocus {
    /// O responder a devolver, ou `nil` se não houver um que ainda sirva.
    ///
    /// Campo em edição: o primeiro responder é o editor de campo, que a janela
    /// compartilha entre todos os campos; devolver o foco a ele não volta ao
    /// campo. Volta o próprio campo. Uma view que saiu da janela, ou de outra
    /// janela, não recebe o foco.
    static func restorable(_ responder: NSResponder?, in window: NSWindow?) -> NSResponder? {
        guard let responder, let window else { return nil }
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            guard let campo = editor.delegate as? NSView, campo.window === window else { return nil }
            return campo
        }
        if responder === window { return window }
        if let view = responder as? NSView, view.window === window { return view }
        return nil
    }
}
