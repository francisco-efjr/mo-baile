import AppKit

/// `NSTextView` que desenha a numeração de linha na própria margem esquerda.
///
/// A primeira tentativa usou `NSRulerView`, que é o caminho idiomático do
/// AppKit. Dentro do `HSplitView` da janela ele quebrou o layout inteiro:
/// ligar `rulersVisible` fazia o `NSScrollView` pedir uma altura enorme, e o
/// `VStack` da coluna dava tudo a ele — a barra de abas e os cabeçalhos dos
/// editores eram espremidos a zero e a coluna parecia vazia.
///
/// O sintoma não aparecia em teste de renderização isolada, porque o
/// `ImageRenderer` não desenha view do AppKit: só na janela real.
///
/// Desenhar na margem do próprio text view não mexe em nenhuma métrica de
/// layout, e a numeração rola junto com o texto de graça.
final class CodeTextView: NSTextView {
    var larguraDaGutter: CGFloat = 34
    var corDoNumero: NSColor = .secondaryLabelColor
    var corDaGutter: NSColor = .clear
    var fonteDoNumero: NSFont = .monospacedSystemFont(ofSize: 10, weight: .regular)

    override func draw(_ dirtyRect: NSRect) {
        corDaGutter.setFill()
        NSRect(x: 0, y: dirtyRect.minY, width: larguraDaGutter, height: dirtyRect.height).fill()
        super.draw(dirtyRect)
        desenharNumeros(em: dirtyRect)
    }

    private func desenharNumeros(em rect: NSRect) {
        guard let layout = layoutManager, let container = textContainer else { return }
        let texto = string as NSString
        let recuo = textContainerInset.height

        var linha = 1
        var inicio = 0
        while inicio <= texto.length {
            let faixa = texto.lineRange(for: NSRange(location: inicio, length: 0))
            let glifos = layout.glyphRange(forCharacterRange: faixa, actualCharacterRange: nil)
            let caixa = layout.boundingRect(forGlyphRange: glifos, in: container)
            let y = caixa.minY + recuo

            if y + caixa.height >= rect.minY, y <= rect.maxY {
                desenhar(numero: linha, emY: y)
            }

            linha += 1
            let proximo = NSMaxRange(faixa)
            if proximo <= inicio { break }
            inicio = proximo
        }

        // Documento vazio ainda tem a linha 1.
        if texto.length == 0 {
            desenhar(numero: 1, emY: recuo)
        }
    }

    private func desenhar(numero: Int, emY y: CGFloat) {
        let rotulo = NSAttributedString(
            string: "\(numero)",
            attributes: [.font: fonteDoNumero, .foregroundColor: corDoNumero]
        )
        rotulo.draw(at: NSPoint(x: larguraDaGutter - rotulo.size().width - 8, y: y))
    }
}
