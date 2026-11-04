import XCTest
import AppKit
@testable import MoBaile

/// PO-1: o editor de Page Objects recebe os mesmos caracteres que o PyCharm.
///
/// Texto T1 e testes T2/T3 da seção 5 de `docs/research/pycharm-page-objects.md`.
/// O oráculo é o PyCharm: ele normaliza toda quebra de linha para `\n` no
/// documento e não aplica nenhuma substituição do sistema.
@MainActor
final class EditorCaracteresTests: XCTestCase {

    /// L1–L9 do T1, em pontos de código.
    static let t1Linhas = [
        "s = \"reta\" + 'simples'",
        "# -- ... --- fim",
        "a\tb",
        "x\u{00A0}y",
        "z\u{200B}w",
        "\u{1F600} \u{1F469}\u{200D}\u{1F4BB}",
        "c\u{00E9} ce\u{0301}",
        "def f():",
        "    return 1",
    ]

    private func editor() -> IDEEditorContainerView {
        let container = IDEEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.layoutSubtreeIfNeeded()
        return container
    }

    /// Pasteboard próprio: o teste não toca na área de transferência da pessoa.
    private func pasteboard(_ texto: String) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("mobaile.teste.\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString(texto, forType: .string)
        addTeardownBlock { pb.releaseGlobally() }
        return pb
    }

    private func escalares(_ texto: String) -> [UInt32] { texto.unicodeScalars.map(\.value) }

    // MARK: - P0-1: entrada literal

    func testTodasAsSubstituicoesDoSistemaDesligadas() {
        let tv = editor().textView
        XCTAssertFalse(tv.isRichText)
        XCTAssertFalse(tv.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(tv.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(tv.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(tv.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(tv.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(tv.isGrammarCheckingEnabled)
        XCTAssertFalse(tv.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(tv.isAutomaticDataDetectionEnabled)
        XCTAssertFalse(tv.isAutomaticTextCompletionEnabled)
        XCTAssertFalse(tv.smartInsertDeleteEnabled)
        XCTAssertEqual(tv.enabledTextCheckingTypes, 0)
        XCTAssertEqual(tv.inlinePredictionType, .no)
        if #available(macOS 15.0, *) {
            XCTAssertEqual(tv.writingToolsBehavior, .none)
        }
    }

    // MARK: - P0-2: T1 colado

    func testT1ColadoComCRLFViraLinhasUnidasPorLF() {
        let tv = editor().textView
        let colado = Self.t1Linhas.joined(separator: "\r\n")
        XCTAssertTrue(tv.readSelection(from: pasteboard(colado), type: .string))

        let esperado = Self.t1Linhas.joined(separator: "\n")
        XCTAssertEqual(escalares(tv.string), escalares(esperado))
        XCTAssertFalse(tv.string.unicodeScalars.contains("\r"))
        XCTAssertEqual(EditorText.rotuloDeLinhas(tv.string), "9 linhas")
    }

    func testCRSoltoTambemViraLF() {
        XCTAssertEqual(EditorText.normalizarQuebras("a\rb\r\nc\n\rd"), "a\nb\nc\n\nd")
        // U+2028 e U+2029 não são quebra de linha no PyCharm.
        XCTAssertEqual(EditorText.normalizarQuebras("a\u{2028}b\u{2029}c"), "a\u{2028}b\u{2029}c")
    }

    func testColarDesfazComUmCommandZ() throws {
        let tv = editor().textView
        tv.string = "inicio"
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        XCTAssertTrue(tv.readSelection(from: pasteboard("\r\nfim"), type: .string))
        XCTAssertEqual(tv.string, "inicio\nfim")
        let undo = try XCTUnwrap(tv.undoManager)
        undo.undo()
        XCTAssertEqual(tv.string, "inicio")
    }

    /// ⌘Z do menu Editar chega pelo responder chain: tem de desfazer no
    /// histórico do próprio editor, não no da janela.
    func testDesfazerPeloResponderChainUsaOHistoricoDoEditor() {
        let container = editor()
        let janela = NSWindow(contentRect: container.frame, styleMask: [.titled], backing: .buffered, defer: true)
        janela.isReleasedWhenClosed = false
        janela.contentView = container
        let tv = container.textView
        XCTAssertTrue(janela.makeFirstResponder(tv))
        tv.insertText("abc", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(tv.string, "abc")
        XCTAssertTrue(tv.tryToPerform(Selector(("undo:")), with: nil))
        XCTAssertEqual(tv.string, "")
    }

    func testContagemDeLinhasNaoTrataCRLFComoUmCaractere() {
        XCTAssertEqual(EditorText.rotuloDeLinhas(""), "0 linhas")
        XCTAssertEqual(EditorText.rotuloDeLinhas("x"), "1 linha")
        XCTAssertEqual(EditorText.rotuloDeLinhas("x\n"), "1 linha")
        XCTAssertEqual(EditorText.rotuloDeLinhas("x\ny\n"), "2 linhas")
        // Texto do Windows que escapou da normalização ainda conta certo.
        XCTAssertEqual(EditorText.rotuloDeLinhas("a\r\nb\r\nc"), "3 linhas")
        XCTAssertEqual(EditorText.linhasDoGutter("a\nb\n"), 3)
        XCTAssertEqual(EditorText.linhasDoGutter(""), 1)
    }

    // MARK: - T2 e T3: digitação

    func testT2DigitarAspasETravessoesSaiLiteral() {
        let tv = editor().textView
        for caractere in "x = \"a\" -- ..." {
            tv.insertText(String(caractere), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        XCTAssertEqual(escalares(tv.string), escalares("x = \"a\" -- ..."))
    }

    func testT3TabNoComecoDaLinhaInsereQuatroEspacos() {
        let tv = editor().textView
        tv.insertTab(nil)
        XCTAssertEqual(tv.string, "    ")
        // No meio da linha, vai até a próxima parada de 4 colunas.
        tv.string = "ab"
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        tv.insertTab(nil)
        XCTAssertEqual(tv.string, "ab  ")
    }

    // MARK: - P0-5: sem soft wrap

    func testSemQuebraAutomaticaComRolagemHorizontal() {
        let container = editor()
        let tv = container.textView
        XCTAssertTrue(container.scrollView.hasHorizontalScroller)
        XCTAssertTrue(tv.isHorizontallyResizable)
        XCTAssertEqual(tv.textContainer?.widthTracksTextView, false)

        tv.string = "    self.wait_to_be_visible(self.locators['CAMPO_MUITO_LONGO_QUE_NAO_CABE_NA_LARGURA_DO_EDITOR'])"
        let lm = try! XCTUnwrap(tv.layoutManager)
        lm.ensureLayout(for: tv.textContainer!)
        var fragmentos = 0
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { _, _, _, _, _ in
            fragmentos += 1
        }
        XCTAssertEqual(fragmentos, 1, "a linha lógica virou mais de uma linha visual")
    }

    // MARK: - P0-9: linha e coluna

    func testLinhaEColunaContaGrafemasETabAteAParada() {
        let texto = Self.t1Linhas.joined(separator: "\n") as NSString
        // Início do texto.
        XCTAssertEqual(EditorText.linhaEColuna(em: texto, posicao: 0).linha, 1)
        XCTAssertEqual(EditorText.linhaEColuna(em: texto, posicao: 0).coluna, 1)
        // Fim de L3 ("a\tb"): a, tab até a coluna 5, b, cursor na 6.
        let fimL3 = texto.range(of: "a\tb").upperBound
        let l3 = EditorText.linhaEColuna(em: texto, posicao: fimL3)
        XCTAssertEqual(l3.linha, 3)
        XCTAssertEqual(l3.coluna, 6)
        // Fim de L6: dois emojis e um espaço são três grafemas.
        let l6 = texto.range(of: "\u{1F600} \u{1F469}\u{200D}\u{1F4BB}")
        let fimL6 = EditorText.linhaEColuna(em: texto, posicao: l6.upperBound)
        XCTAssertEqual(fimL6.linha, 6)
        XCTAssertEqual(fimL6.coluna, 4)
    }
}
