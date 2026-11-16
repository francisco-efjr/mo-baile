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
    var cursor: CursorDoEditor? = nil
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

        let esquema = EditorScheme.atual(tema, escolha: escolhaDeEsquema)
        let fonte = EditorFont.fonte()
        let assinatura = "\(escolhaDeEsquema)|\(tema.id)|\(tema.isDark)|\(tema.highContrast)|\(python)|\(fonte.fontName)"
        let esquemaMudou = coordinator.assinatura != assinatura
        textView.esquema = esquema
        textView.python = python
        // Atribuir `font` repinta o armazenamento inteiro: só quando muda (R-06).
        if textView.font != fonte { textView.font = fonte }
        textView.typingAttributes = EditorFont.atributos(fonte, cor: esquema.texto)

        // Caminho rápido (R-06): o texto é o que este editor mandou ao estado
        // na última tecla (mesmo armazenamento, comparação O(1)). Nada a
        // normalizar nem a recarregar.
        var recriou = false
        if text != coordinator.ultimoTexto {
            // Texto que chega com CR ou CRLF entra como o PyCharm guardaria: `\n`.
            let normalizado = EditorText.normalizarQuebras(text)
            if normalizado != text {
                DispatchQueue.main.async { self.text = normalizado }
            }
            coordinator.aplicando = true
            recriou = container.carregar(normalizado)
            coordinator.aplicando = false
            coordinator.ultimoTexto = normalizado
        }

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
        if esquemaMudou || recriou {
            container.gutterView.needsDisplay = true
            textView.needsDisplay = true
        }
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
        /// O último texto que este editor carregou ou mandou ao estado.
        var ultimoTexto: String?

        init(_ parent: CodeEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !aplicando, let textView = notification.object as? CodeTextView else { return }
            // Cópia nativa uma vez por tecla: o `updateNSView` seguinte
            // reconhece o mesmo armazenamento sem comparar caractere a caractere.
            let novo = EditorText.copiaNativa(textView.textStorage?.string ?? textView.string)
            ultimoTexto = novo
            parent.text = novo
            if let container = textView.enclosingScrollView?.superview as? IDEEditorContainerView {
                container.updateGutterWidth(forLineCount: textView.totalDeLinhas)
                container.gutterView.needsDisplay = true
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView, let cursor = parent.cursor else { return }
            let posicao = textView.linhaEColunaDoCursor()
            DispatchQueue.main.async {
                if cursor.linha != posicao.linha { cursor.linha = posicao.linha }
                if cursor.coluna != posicao.coluna { cursor.coluna = posicao.coluna }
            }
        }
    }
}
