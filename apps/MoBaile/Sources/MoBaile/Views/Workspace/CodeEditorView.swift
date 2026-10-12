import AppKit
import SwiftUI

/// Editor de código com Python colorido e numeração de linha real no estilo IDE.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    /// Nome da área de texto para o leitor de tela. Com dois editores lado a
    /// lado, "área de texto" sem nome não diz qual é qual.
    var accessibilityLabel: String = "Editor de código"
    /// Trecho a destacar (o locator do passo escolhido na barra lateral). As
    /// linhas que o contêm ganham o fundo de seleção de conteúdo.
    var highlight: String? = nil
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
        textView.setAccessibilityLabel(accessibilityLabel)

        return container
    }

    func updateNSView(_ container: IDEEditorContainerView, context: Context) {
        let textView = container.textView
        let tema = themeManager.current
        textView.setAccessibilityLabel(accessibilityLabel)

        context.coordinator.aplicando = true
        defer { context.coordinator.aplicando = false }

        let destaqueMudou = context.coordinator.destaque != highlight || context.coordinator.temaID != tema.id + "\(tema.highContrast)"
        if textView.string != text || destaqueMudou {
            // A posição do cursor é preservada: sem isso, cada passo gravado
            // jogava o cursor para o início enquanto alguém editava.
            let selecao = textView.selectedRange()
            let colorido = NSMutableAttributedString(
                attributedString: PythonHighlighter.destacar(text, tema: tema, fonte: Self.fonte)
            )
            let primeira = Self.destacarLinhas(contendo: highlight, em: colorido, cor: NSColor(tema.selectionContent))
            textView.textStorage?.setAttributedString(colorido)
            let limite = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: min(selecao.location, limite), length: 0))
            if destaqueMudou, let primeira {
                textView.scrollRangeToVisible(primeira)
            }
            context.coordinator.destaque = highlight
            context.coordinator.temaID = tema.id + "\(tema.highContrast)"
        }

        let bgEditor = NSColor(tema.bgContent)
        textView.backgroundColor = bgEditor
        container.scrollView.backgroundColor = bgEditor
        textView.insertionPointColor = NSColor(tema.labelPrimary)

        // Numeração de linha no fundo do editor, separada por 1 pt.
        container.gutterView.gutterBackgroundColor = bgEditor
        container.gutterView.separatorColor = NSColor(tema.separator)
        container.gutterView.textColor = NSColor(tema.syntaxGutter)

        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        container.updateGutterWidth(forLineCount: lineCount)
        container.gutterView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Pinta o fundo das linhas que contêm `trecho`. Devolve a primeira.
    static func destacarLinhas(contendo trecho: String?, em texto: NSMutableAttributedString, cor: NSColor) -> NSRange? {
        guard let trecho, !trecho.isEmpty else { return nil }
        let conteudo = texto.string as NSString
        var primeira: NSRange?
        conteudo.enumerateSubstrings(in: NSRange(location: 0, length: conteudo.length), options: .byLines) { linha, faixa, faixaComQuebra, _ in
            guard let linha, linha.contains(trecho) else { return }
            texto.addAttribute(.backgroundColor, value: cor, range: faixaComQuebra)
            if primeira == nil { primeira = faixa }
        }
        return primeira
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        /// Evita que a recoloração dispare o callback de edição de volta.
        var aplicando = false
        /// Último destaque e tema aplicados, para recolorir só quando mudam.
        var destaque: String?
        var temaID: String?

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
