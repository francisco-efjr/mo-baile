import XCTest
import AppKit
import SwiftUI
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

    // MARK: - A11Y-01: o foco não sai da paleta

    func testTabEShiftTabFicamNoCampo() {
        let tab: UInt16 = 48
        XCTAssertEqual(acao(tab), .keepFocus)
        XCTAssertEqual(acao(tab, [.shift]), .keepFocus, "⇧Tab saía para a toolbar")
        XCTAssertEqual(acao(tab, [.control]), .keepFocus, "⌃Tab também tira o foco do campo no AppKit")
        var outra = normal
        outra.eventInPaletteWindow = false
        XCTAssertEqual(acao(tab, [], outra), .passThrough, "Tab em Ajustes é de Ajustes")
    }
}

/// A11Y-01: com a paleta aberta, o conteúdo de trás sai da árvore do
/// VoiceOver; ao fechar, o foco volta para onde estava.
@MainActor
final class CommandPaletteModalTests: XCTestCase {

    private struct Fundo: View {
        var body: some View {
            VStack {
                Button("Botão do fundo") {}
                    .modifier(HiddenBehindCommandPalette())
                Text("Fora do fundo")
            }
        }
    }

    func testFundoSomeDoVoiceOverComAPaletaAberta() throws {
        let estado = AppState()
        estado.commandPalettePresented = true
        let aberta = try AccessibilityInspector.arvore(de: Fundo().environment(estado))
        XCTAssertNil(aberta.node(label: "Botão do fundo"), "o VoiceOver ainda navega pelo fundo:\n\(aberta.dump)")
        XCTAssertFalse(aberta.all.filter { $0.label == "Fora do fundo" || $0.value == "Fora do fundo" }.isEmpty)

        estado.commandPalettePresented = false
        let fechada = try AccessibilityInspector.arvore(de: Fundo().environment(estado))
        XCTAssertNotNil(fechada.node(label: "Botão do fundo"), "o fundo não voltou ao fechar:\n\(fechada.dump)")
    }

    /// Campo em edição: o primeiro responder é o editor de campo compartilhado
    /// da janela, e devolver o foco a ele não volta ao campo. Volta o campo.
    func testFocoAnteriorDeCampoEmEdicaoEOProprioCampo() {
        let janela = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        janela.isReleasedWhenClosed = false
        defer { janela.close() }
        let campo = NSTextField(frame: NSRect(x: 10, y: 10, width: 120, height: 22))
        janela.contentView?.addSubview(campo)
        XCTAssertTrue(janela.makeFirstResponder(campo))

        let editor = janela.firstResponder
        XCTAssertTrue((editor as? NSTextView)?.isFieldEditor == true, "o AppKit não pôs o editor de campo: \(String(describing: editor))")
        XCTAssertTrue(CommandPaletteFocus.restorable(editor, in: janela) === campo)
    }

    func testFocoAnteriorDeOutraJanelaOuSemJanelaNaoVolta() {
        let janela = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        janela.isReleasedWhenClosed = false
        defer { janela.close() }
        let solto = NSButton(frame: .zero)
        XCTAssertNil(CommandPaletteFocus.restorable(solto, in: janela), "view fora da janela")
        XCTAssertNil(CommandPaletteFocus.restorable(nil, in: janela))
        let botao = NSButton(frame: NSRect(x: 0, y: 0, width: 40, height: 20))
        janela.contentView?.addSubview(botao)
        XCTAssertTrue(CommandPaletteFocus.restorable(botao, in: janela) === botao)
        XCTAssertNil(CommandPaletteFocus.restorable(botao, in: nil))
    }

    // MARK: - A11Y-02: VO-Espaço numa linha executa

    /// Procura o elemento de acessibilidade com este rótulo.
    private func elemento(_ rotulo: String, em objeto: NSObject, nivel: Int = 0) -> NSObject? {
        let seletorRotulo = Selector(("accessibilityLabel"))
        if objeto.responds(to: seletorRotulo),
           (objeto.perform(seletorRotulo)?.takeUnretainedValue() as? String) == rotulo {
            return objeto
        }
        let seletorFilhos = Selector(("accessibilityChildren"))
        guard nivel < 40, objeto.responds(to: seletorFilhos),
              let filhos = objeto.perform(seletorFilhos)?.takeUnretainedValue() as? [Any]
        else { return nil }
        for case let filho as NSObject in filhos {
            if let achado = elemento(rotulo, em: filho, nivel: nivel + 1) { return achado }
        }
        return nil
    }

    func testLinhaExecutaPeloVoiceOver() throws {
        let comando = AppCommand(id: .proxy, title: "Iniciar Proxy", category: .services, symbol: "network")
        var executou = 0
        let linha = CommandPaletteRow(command: comando, selected: false) { executou += 1 }
            .environment(ThemeManager(preview: PraiaLightTheme()))
        // Monta e confere que a árvore existe; o inspetor pula sem sessão gráfica.
        _ = try AccessibilityInspector.arvore(de: linha, largura: 560, altura: 60)

        let host = NSHostingView(rootView: linha.frame(width: 560, height: 60))
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 60)
        let janela = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        janela.isReleasedWhenClosed = false
        janela.contentView = host
        defer { janela.close() }
        janela.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let rotulo = CommandPaletteRow.spokenLabel(comando)
        let no = try XCTUnwrap(elemento(rotulo, em: host), "linha não encontrada na árvore")
        // VO-Espaço é o AXPress do elemento (`accessibilityPerformPress`).
        let pressionou = (no as AnyObject).accessibilityPerformPress?() ?? false
        XCTAssertTrue(pressionou, "a linha não aceita AXPress")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(executou, 1, "VO-Espaço não executou a ação")
    }
}
