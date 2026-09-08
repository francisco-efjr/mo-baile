import AppKit
import SwiftUI

/// Editor de código com Python colorido e numeração de linha real.
///
/// A versão anterior mostrava tudo numa cor só e tinha ao lado uma coluna que
/// desenhava `1` fixo — qualquer arquivo aparecia com uma linha, e o número não
/// acompanhava a rolagem. Como o produto inteiro existe para gerar Python, ler
/// o resultado sem isso era trabalho a mais no artefato final.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Environment(ThemeManager.self) var themeManager

    private static let fonte = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = CodeTextView()
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = Self.fonte
        textView.backgroundColor = .clear
        // A margem esquerda abre espaço para a numeração desenhada pelo
        // próprio text view.
        textView.textContainerInset = NSSize(width: textView.larguraDaGutter + 6, height: 12)


        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CodeTextView else { return }
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

        textView.backgroundColor = NSColor(tema.bgContent)
        nsView.backgroundColor = NSColor(tema.bgContent)
        textView.insertionPointColor = NSColor(tema.textPrimary)

        textView.corDoNumero = NSColor(tema.syntaxGutter)
        textView.corDaGutter = NSColor(tema.syntaxGutterBg)
        textView.needsDisplay = true
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
        }
    }
}
