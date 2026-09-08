import AppKit
import SwiftUI

/// Editor de código com Python colorido e numeração de linha real no estilo IDE.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Environment(ThemeManager.self) var themeManager

    private static let fonte = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)

    func makeNSView(context: Context) -> IDEEditorContainerView {
        let container = IDEEditorContainerView()
        let textView = container.textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = Self.fonte
        textView.backgroundColor = .clear

        return container
    }

    func updateNSView(_ container: IDEEditorContainerView, context: Context) {
        let textView = container.textView
        let tema = themeManager.current

        context.coordinator.aplicando = true
        defer { context.coordinator.aplicando = false }

        if textView.string != text {
            // A posição do cursor é preservada: sem isso, cada passo gravado
            // jogava o cursor para o início enquanto alguém editava.
            let selecao = textView.selectedRange()
            textView.textStorage?.setAttributedString(
                PythonHighlighter.destacar(text, tema: tema, fonte: Self.fonte)
            )
            let limite = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selecao.location, limite), length: 0))
        }

        let bgEditor = NSColor(tema.bgContent)
        textView.backgroundColor = bgEditor
        container.scrollView.backgroundColor = bgEditor
        textView.insertionPointColor = NSColor(tema.textPrimary)

        // Configuração visual da barra lateral de linhas (IDE Gutter)
        container.gutterView.gutterBackgroundColor = NSColor(tema.syntaxGutterBg)
        container.gutterView.separatorColor = NSColor(tema.borderSubtle)
        container.gutterView.textColor = NSColor(tema.textTertiary)

        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        container.updateGutterWidth(forLineCount: lineCount)
        container.gutterView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        /// Evita que a recoloração dispare o callback de edição de volta.
        var aplicando = false

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !aplicando, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            if let container = textView.superview?.superview?.superview as? IDEEditorContainerView {
                let lineCount = textView.string.split(separator: "\n", omittingEmptySubsequences: false).count
                container.updateGutterWidth(forLineCount: lineCount)
                container.gutterView.needsDisplay = true
            }
        }
    }
}
