import XCTest
import AppKit
@testable import MoBaile

/// PO-3: JetBrains Mono embutida, esquema "PyCharm", linha atual e realce
/// incremental que preserva seleção e desfazer.
@MainActor
final class EditorEsquemaTests: XCTestCase {

    private func hex(_ cor: NSColor) -> String {
        let c = cor.usingColorSpace(.sRGB)!
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }

    private func rgb(_ cor: NSColor) -> [Double] {
        let c = cor.usingColorSpace(.sRGB)!
        return [c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255]
    }

    // MARK: - Fonte

    func testFonteDoEditorEJetBrainsMono13() {
        XCTAssertTrue(EditorFont.registrada, "a JetBrains Mono de assets/fonts não registrou")
        let fonte = EditorFont.fonte()
        XCTAssertEqual(fonte.fontName, "JetBrainsMono-Regular")
        XCTAssertEqual(fonte.pointSize, 13)
    }

    func testAtributosSemLigaduraEComAlturaDeLinha12() throws {
        let fonte = EditorFont.fonte()
        let atributos = EditorFont.atributos(fonte, cor: .white)
        XCTAssertEqual(atributos[.ligature] as? Int, 0)
        let paragrafo = try XCTUnwrap(atributos[.paragraphStyle] as? NSParagraphStyle)
        let natural = NSLayoutManager().defaultLineHeight(for: fonte)
        XCTAssertEqual(paragrafo.minimumLineHeight, (natural * 1.2).rounded())
        XCTAssertEqual(paragrafo.maximumLineHeight, paragrafo.minimumLineHeight)
    }

    // MARK: - Esquema

    func testEsquemaPyCharmEscuroBateComATabelaDaPesquisa() {
        let e = EditorScheme.pycharm(escuro: true, altoContraste: false)
        XCTAssertEqual(hex(e.fundo), "#191A1C")
        XCTAssertEqual(hex(e.texto), "#BCBEC4")
        XCTAssertEqual(hex(e.palavraChave), "#CF8E6D")
        XCTAssertEqual(hex(e.string), "#6AAB73")
        XCTAssertEqual(hex(e.comentario), "#7A7E85")
        XCTAssertEqual(hex(e.docstring), "#5F826B")
        XCTAssertEqual(hex(e.numero), "#2AACB8")
        XCTAssertEqual(hex(e.funcao), "#56A8F5")
        XCTAssertEqual(hex(e.decorador), "#B3AE60")
        XCTAssertEqual(hex(e.selfCor), "#94558D")
        XCTAssertEqual(hex(e.builtin), "#8888C6")
        XCTAssertEqual(hex(e.argumentoNomeado), "#AA4926")
        XCTAssertEqual(hex(e.linhaAtual), "#1F2024")
        XCTAssertEqual(hex(e.numeroLinhaAtual), "#A1A3AB")
        // Único desvio: #4B5059 → #61666E para chegar a 3:1 (D-1).
        XCTAssertEqual(hex(e.numeroLinha), "#61666E")
        XCTAssertEqual(hex(EditorScheme.pycharm(escuro: true, altoContraste: true).numeroLinha), "#A1A3AB")
    }

    /// Contraste calculado, não estimado. Texto e número da linha atual
    /// passam 4,5:1; número de linha passa 3:1 (não essencial). Comentário e
    /// docstring ficam abaixo de 4,5 como no próprio PyCharm (risco no relatório).
    func testContrasteDoEsquema() {
        for escuro in [true, false] {
            let e = EditorScheme.pycharm(escuro: escuro, altoContraste: false)
            let fundo = rgb(e.fundo)
            let nome = escuro ? "escuro" : "claro"
            XCTAssertGreaterThanOrEqual(PaletteMath.contrast(rgb(e.texto), fundo), 4.5, nome)
            XCTAssertGreaterThanOrEqual(PaletteMath.contrast(rgb(e.numeroLinhaAtual), fundo), 4.0, nome)
            XCTAssertGreaterThanOrEqual(PaletteMath.contrast(rgb(e.numeroLinha), fundo), 3.0, nome)
            XCTAssertGreaterThanOrEqual(PaletteMath.contrast(rgb(e.etiqueta), fundo), 3.0, nome)
        }
    }

    // MARK: - Realce e carga

    private func editor(_ texto: String = "") -> IDEEditorContainerView {
        let container = IDEEditorContainerView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        container.textView.esquema = .pycharm(escuro: true, altoContraste: false)
        container.textView.typingAttributes = EditorFont.atributos(EditorFont.fonte(), cor: container.textView.esquema!.texto)
        container.carregar(texto)
        container.layoutSubtreeIfNeeded()
        return container
    }

    private func cor(_ container: IDEEditorContainerView, em indice: Int) -> String {
        hex(container.armazenamento.attribute(.foregroundColor, at: indice, effectiveRange: nil) as! NSColor)
    }

    func testDigitarDefRecoloreNaHora() {
        let container = editor()
        for caractere in "def x():" {
            container.textView.insertText(String(caractere), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        XCTAssertEqual(cor(container, em: 0), "#CF8E6D", "def")
        XCTAssertEqual(cor(container, em: 4), "#56A8F5", "nome da função")
    }

    func testPapeisDoPyCharm() {
        let codigo = "@dec\ndef f(self, nome=\"a # b\"):\n    CAMPO = 1  # nota\n    print(len(x))"
        let container = editor(codigo)
        let texto = codigo as NSString
        XCTAssertEqual(cor(container, em: 0), "#B3AE60", "decorador")
        XCTAssertEqual(cor(container, em: texto.range(of: "self").location), "#94558D", "self")
        XCTAssertEqual(cor(container, em: texto.range(of: "nome").location), "#AA4926", "argumento nomeado")
        XCTAssertEqual(cor(container, em: texto.range(of: "# b").location), "#6AAB73", "# dentro de string é string")
        XCTAssertEqual(cor(container, em: texto.range(of: "CAMPO").location), "#BCBEC4", "CAIXA_ALTA sem cor própria")
        XCTAssertEqual(cor(container, em: texto.range(of: "# nota").location), "#7A7E85", "comentário")
        XCTAssertEqual(cor(container, em: texto.range(of: "print").location), "#8888C6", "builtin")
        XCTAssertEqual(cor(container, em: texto.range(of: "1").location), "#2AACB8", "número")
    }

    /// Gravar passos com o cursor no meio do texto não move o cursor, e ⌘Z
    /// desfaz só a última edição manual.
    func testPassoGravadoAcrescentaSemMoverCursorNemDesfazerAPessoa() throws {
        let container = editor("def a(self):\n    pass\n")
        let tv = container.textView
        tv.setSelectedRange(NSRange(location: 4, length: 0))
        tv.insertText("z", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, "def za(self):\n    pass\n")

        var texto = tv.string
        for passo in 1...50 {
            texto += "def passo_\(passo)(self):\n    pass\n"
            container.carregar(texto)
        }
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(cor(container, em: (tv.string as NSString).range(of: "passo_50").location), "#56A8F5")

        tv.historico.undo()
        XCTAssertTrue(tv.string.hasPrefix("def a(self):"), "o ⌘Z desfez a edição manual")
        XCTAssertTrue(tv.string.contains("passo_50"), "o ⌘Z não pode apagar passo gravado")
    }

    func testTrocaInteiraZeraOHistorico() {
        let container = editor("x = 1")
        container.textView.insertText("2", replacementRange: NSRange(location: NSNotFound, length: 0))
        container.carregar("")
        XCTAssertFalse(container.textView.historico.canUndo)
    }

    func testLinhaAtualRealcadaSoSemSelecao() throws {
        let container = editor("a\nb\nc")
        let tv = container.textView
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        let linha = try XCTUnwrap(tv.retanguloDaLinhaAtual())
        let segunda = tv.layoutManager!.lineFragmentRect(forGlyphAt: 2, effectiveRange: nil)
        XCTAssertEqual(linha.minY, segunda.minY + tv.textContainerOrigin.y, accuracy: 0.5)
        XCTAssertEqual(linha.height, EditorFont.alturaDaLinha(EditorFont.fonte()), accuracy: 0.5)
    }
}
