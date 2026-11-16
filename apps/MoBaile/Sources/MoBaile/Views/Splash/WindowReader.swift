import AppKit
import SwiftUI

/// Entrega a `NSWindow` que hospeda a view assim que ela entra na janela,
/// antes do primeiro desenho.
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Leitor(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Leitor: NSView {
        let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
