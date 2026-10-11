import XCTest
import AppKit
@testable import MoBaile

/// R-01: o monitor de teclado da paleta só pega tecla que é dela.
///
/// Defeito que cobre: com a paleta aberta, ⌘, abria Ajustes (ou ⌘O abria o
/// painel de arquivo) e, nessa outra janela, setas e Esc mexiam na paleta
/// escondida e Return executava o comando selecionado na janela principal.
/// ⌘↑ e ⌥Return também eram engolidos.
final class CommandPaletteKeyboardTests: XCTestCase {

    private typealias K = CommandPaletteKeyboard

    private enum Tecla {
        static let baixo: UInt16 = 125
        static let cima: UInt16 = 126
        static let retorno: UInt16 = 36
        static let enterNumerico: UInt16 = 76
        static let esc: UInt16 = 53
        static let letraA: UInt16 = 0
    }

    /// Paleta aberta, tecla na janela dela, sem sheet nem modal.
    private let normal = K.Situation(paletteOpen: true, eventInPaletteWindow: true, modalOpen: false, sheetAttached: false)

    private func acao(_ tecla: UInt16, _ modificadores: NSEvent.ModifierFlags = [], _ situacao: K.Situation? = nil) -> K.Action {
        K.action(keyCode: tecla, modifiers: modificadores, situation: situacao ?? normal)
    }

    func testTeclasDaPaletaNaJanelaDela() {
        XCTAssertEqual(acao(Tecla.baixo), .move(1))
        XCTAssertEqual(acao(Tecla.cima), .move(-1))
        XCTAssertEqual(acao(Tecla.retorno), .execute)
        XCTAssertEqual(acao(Tecla.enterNumerico), .execute)
        XCTAssertEqual(acao(Tecla.esc), .close)
        XCTAssertEqual(acao(Tecla.letraA), .passThrough, "letra vai para o campo")
    }

    /// Setas chegam com `.numericPad` e `.function`, e ⇧ não muda o sentido.
    func testModificadoresQueNaoContam() {
        XCTAssertEqual(acao(Tecla.baixo, [.numericPad, .function]), .move(1))
        XCTAssertEqual(acao(Tecla.cima, [.shift]), .move(-1))
        XCTAssertEqual(acao(Tecla.baixo, [.capsLock]), .move(1))
    }

    func testComandoOpcaoEControlePassam() {
        XCTAssertEqual(acao(Tecla.cima, [.command, .numericPad, .function]), .passThrough, "⌘↑ é do campo")
        XCTAssertEqual(acao(Tecla.retorno, [.option]), .passThrough, "⌥Return não executa")
        XCTAssertEqual(acao(Tecla.baixo, [.control]), .passThrough)
        XCTAssertEqual(acao(Tecla.esc, [.command]), .passThrough)
    }

    func testOutraJanelaNaoEDaPaleta() {
        var s = normal
        s.eventInPaletteWindow = false
        for tecla in [Tecla.baixo, Tecla.cima, Tecla.retorno, Tecla.enterNumerico, Tecla.esc] {
            XCTAssertEqual(acao(tecla, [], s), .passThrough, "tecla \(tecla) em Ajustes mexeu na paleta")
        }
    }

    func testSheetOuModalPorCima() {
        var comSheet = normal
        comSheet.sheetAttached = true
        XCTAssertEqual(acao(Tecla.retorno, [], comSheet), .passThrough, "Return do NSOpenPanel executou o comando")
        var comModal = normal
        comModal.modalOpen = true
        XCTAssertEqual(acao(Tecla.esc, [], comModal), .passThrough)
    }

    func testPaletaFechadaNaoPegaNada() {
        var s = normal
        s.paletteOpen = false
        for tecla in [Tecla.baixo, Tecla.cima, Tecla.retorno, Tecla.esc] {
            XCTAssertEqual(acao(tecla, [], s), .passThrough)
        }
    }
}
