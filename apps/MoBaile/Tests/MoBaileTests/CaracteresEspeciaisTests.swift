import XCTest
import AppKit
@testable import MoBaile

/// PO-2: caracteres especiais visíveis como no PyCharm (`SpecialCharacterFragment`).
/// O desenho muda; o texto, a cópia e o que o VoiceOver lê, não.
@MainActor
final class CaracteresEspeciaisTests: XCTestCase {

    private func abrev(_ texto: String, _ indice: Int = 1) -> String? {
        CaracteresEspeciais.abreviacao(em: texto as NSString, indice: indice)
    }

    func testConjuntoDoPyCharm() {
        XCTAssertEqual(abrev("x\u{00A0}y"), "NBSP")
        XCTAssertEqual(abrev("z\u{200B}w"), "ZWSP")
        XCTAssertEqual(abrev("a\u{00AD}b"), "SHY")
        XCTAssertEqual(abrev("a\u{2009}b"), "THSP")
        XCTAssertEqual(abrev("a\u{200E}b"), "LRM")
        XCTAssertEqual(abrev("a\u{202E}b"), "RLO")
        XCTAssertEqual(abrev("a\u{2066}b"), "LRI")
        XCTAssertEqual(abrev("a\u{2028}b"), "LSEP")
        XCTAssertEqual(abrev("a\u{202F}b"), "NNBSP")
        XCTAssertEqual(abrev("a\u{2060}b"), "WJ")
        XCTAssertEqual(abrev("a\u{FEFF}b"), "ZWNBSP")
        XCTAssertEqual(abrev("a\u{0000}b"), "NUL")
        XCTAssertEqual(abrev("a\u{001B}b"), "ESC")
        XCTAssertEqual(abrev("a\u{007F}b"), "DEL")
        XCTAssertEqual(abrev("a\u{0085}b"), "NEL")
    }

    func testTabQuebraEEspacoComumNaoViramEtiqueta() {
        XCTAssertNil(abrev("a\tb"))
        XCTAssertNil(abrev("a\nb"))
        XCTAssertNil(abrev("a b"))
        XCTAssertNil(abrev("aéb"))
    }

    func testExcecoesDoPyCharm() {
        // NBSP antes de marca combinante não vira etiqueta.
        XCTAssertNil(abrev("x\u{00A0}\u{0301}"))
        // ZWJ e ZWNJ vizinhos de caractere não ASCII ficam invisíveis: o emoji
        // 👩‍💻 aparece inteiro.
        let emoji = "\u{1F469}\u{200D}\u{1F4BB}" as NSString
        XCTAssertNil(CaracteresEspeciais.abreviacao(em: emoji, indice: 2))
        XCTAssertNil(abrev("\u{0915}\u{200C}a"))
        // Entre letras ASCII, ZWJ aparece.
        XCTAssertEqual(abrev("a\u{200D}b"), "ZWJ")
    }

    // MARK: - No editor

    private func editor(_ texto: String) -> IDEEditorContainerView {
        let container = IDEEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.textView.string = texto
        container.layoutSubtreeIfNeeded()
        container.layoutManager.ensureLayout(for: container.textView.textContainer!)
        return container
    }

    func testEtiquetaOcupaLarguraSemMudarOTexto() {
        let comNBSP = editor("x\u{00A0}y")
        let comEspaco = editor("x y")
        let lm = comNBSP.layoutManager
        let glifo = lm.glyphIndexForCharacter(at: 1)
        XCTAssertEqual(lm.propertyForGlyph(at: glifo), .controlCharacter)
        let larguraNBSP = lm.boundingRect(forGlyphRange: NSRange(location: glifo, length: 1), in: comNBSP.textView.textContainer!).width
        let larguraEspaco = comEspaco.layoutManager.boundingRect(
            forGlyphRange: NSRange(location: 1, length: 1), in: comEspaco.textView.textContainer!
        ).width
        XCTAssertGreaterThan(larguraNBSP, larguraEspaco * 2, "a etiqueta NBSP precisa de espaço próprio")
        XCTAssertEqual(comNBSP.textView.string.unicodeScalars.map(\.value), [0x78, 0xA0, 0x79])
    }

    func testEmojiComZWJNaoViraEtiqueta() {
        let container = editor("\u{1F469}\u{200D}\u{1F4BB}")
        let lm = container.layoutManager
        for indice in 0..<lm.numberOfGlyphs {
            XCTAssertNotEqual(lm.propertyForGlyph(at: indice), .controlCharacter)
        }
    }

    func testLSEPNaoQuebraALinha() {
        let container = editor("a\u{2028}b")
        let lm = container.layoutManager
        var fragmentos = 0
        lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { _, _, _, _, _ in
            fragmentos += 1
        }
        XCTAssertEqual(fragmentos, 1, "LSEP é etiqueta no PyCharm, não quebra de linha")
    }

    func testCopiarDevolveOCaractereOriginal() {
        let container = editor("x\u{00A0}y z\u{200B}w")
        let tv = container.textView
        tv.selectAll(nil)
        let pb = NSPasteboard(name: NSPasteboard.Name("mobaile.teste.\(UUID().uuidString)"))
        addTeardownBlock { pb.releaseGlobally() }
        pb.clearContents()
        // O que ⌘C escreve: os tipos que o próprio editor oferece.
        XCTAssertTrue(tv.writeSelection(to: pb, types: tv.writablePasteboardTypes))
        XCTAssertEqual(pb.string(forType: .string)?.unicodeScalars.map(\.value),
                       [0x78, 0xA0, 0x79, 0x20, 0x7A, 0x200B, 0x77])
    }

    func testLeitorDeTelaRecebeOTextoReal() {
        let container = editor("x\u{00A0}y")
        XCTAssertEqual(container.textView.accessibilityValue() as? String, "x\u{00A0}y")
    }

    func testDesenharEtiquetasNaoQuebra() {
        let container = editor("x\u{00A0}y\nz\u{200B}w\n\u{1F469}\u{200D}\u{1F4BB}")
        let tv = container.textView
        let rep = try! XCTUnwrap(tv.bitmapImageRepForCachingDisplay(in: tv.bounds))
        tv.cacheDisplay(in: tv.bounds, to: rep)
    }
}
