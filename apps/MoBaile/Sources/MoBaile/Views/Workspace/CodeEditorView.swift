import AppKit
import SwiftUI

/// Editor de código no modelo do PyCharm: JetBrains Mono 13, esquema
/// "PyCharm", linha atual realçada, realce incremental e caracteres literais.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    /// Nome da área de texto para o leitor de tela. Com dois editores lado a
    /// lado, "área de texto" sem nome não diz qual é qual.
    var accessibilityLabel: String = "Editor de código"
    /// Trecho a destacar (o locator do passo escolhido na barra lateral). As
    /// linhas que o contêm ganham o fundo de seleção de conteúdo.
    var highlight: String? = nil
    /// Python colorido. Falso para YAML e texto abertos da árvore Projeto.
    var python = true
    var editable = true
    /// Linha e coluna do cursor (a partir de 1), para o rodapé.
    var onCursor: ((Int, Int) -> Void)? = nil
    @Environment(ThemeManager.self) var themeManager
    @AppStorage(EditorScheme.chave) private var escolhaDeEsquema = EditorScheme.pycharmID

    func makeNSView(context: Context) -> IDEEditorContainerView {
        let container = IDEEditorContainerView()
        // A entrada literal (PO-1) já vem do contêiner.
        container.textView.delegate = context.coordinator
        container.textView.setAccessibilityLabel(accessibilityLabel)
        return container
    }

    func updateNSView(_ container: IDEEditorContainerView, context: Context) {
        let textView = container.textView
        let tema = themeManager.current
        let coordinator = context.coordinator
        coordinator.parent = self
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.isEditable = editable

        // Texto que chega com CR ou CRLF entra como o PyCharm guardaria: `\n`.
        let normalizado = EditorText.normalizarQuebras(text)
        if normalizado != text {
            DispatchQueue.main.async { self.text = normalizado }
        }

        let esquema = EditorScheme.atual(tema, escolha: escolhaDeEsquema)
        let fonte = EditorFont.fonte()
        let assinatura = "\(escolhaDeEsquema)|\(tema.id)|\(tema.isDark)|\(tema.highContrast)|\(python)|\(fonte.fontName)"
        let esquemaMudou = coordinator.assinatura != assinatura
        textView.esquema = esquema
        textView.python = python
        textView.font = fonte
        textView.typingAttributes = EditorFont.atributos(fonte, cor: esquema.texto)

        coordinator.aplicando = true
        let recriou = container.carregar(normalizado)
        coordinator.aplicando = false

        let destaqueMudou = coordinator.destaque != highlight
        if esquemaMudou || destaqueMudou || (recriou && highlight != nil) {
            // Só atributos: o texto, a seleção e o desfazer ficam.
            let tudo = NSRange(location: 0, length: container.armazenamento.length)
            container.armazenamento.setAttributes(textView.typingAttributes, range: tudo)
            textView.recolorir(nil)
            let primeira = Self.destacarLinhas(contendo: highlight, em: container.armazenamento, cor: NSColor(tema.selectionContent))
            if destaqueMudou, let primeira { textView.scrollRangeToVisible(primeira) }
            coordinator.assinatura = assinatura
            coordinator.destaque = highlight
        }

        textView.backgroundColor = esquema.fundo
        container.scrollView.backgroundColor = esquema.fundo
        textView.insertionPointColor = esquema.texto
        container.layoutManager.corDaEtiqueta = esquema.etiqueta
        container.gutterView.gutterBackgroundColor = esquema.fundo
        container.gutterView.separatorColor = esquema.fundo
        container.gutterView.textColor = esquema.numeroLinha
        container.gutterView.currentLineTextColor = esquema.numeroLinhaAtual
        container.gutterView.font = EditorFont.fonte(tamanho: EditorFont.tamanho - 1)
        container.gutterView.needsDisplay = true
        textView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Pinta o fundo das linhas que contêm `trecho`. Devolve a primeira.
    @discardableResult
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
        /// Evita que a carga vinda do estado dispare o callback de edição de volta.
        var aplicando = false
        /// Último destaque e esquema aplicados, para recolorir só quando mudam.
        var destaque: String?
        var assinatura: String?

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !aplicando, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            if let container = textView.enclosingScrollView?.superview as? IDEEditorContainerView {
                container.updateGutterWidth(forLineCount: EditorText.linhasDoGutter(textView.string))
                container.gutterView.needsDisplay = true
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let onCursor = parent.onCursor else { return }
            let posicao = EditorText.linhaEColuna(em: textView.string as NSString, posicao: textView.selectedRange().location)
            DispatchQueue.main.async { onCursor(posicao.linha, posicao.coluna) }
        }
    }
}
