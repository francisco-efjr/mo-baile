import XCTest
import SwiftUI
import AppKit
@testable import MoBaile

/// R-06: custo por tecla e por movimento do cursor num `.py` de ~1 MB com
/// docstring, no editor de verdade (`CodeEditorView` numa janela, com o pai
/// que guarda o texto, como a aba Page Objects). Ferramenta de medição, não
/// asserção: roda só com `MOBAILE_BENCH=1` e imprime `BENCH ...`.
@MainActor
final class EditorBenchTests: XCTestCase {

    @Observable final class Caixa {
        var texto = ""
    }

    private struct Pai: View {
        @Bindable var caixa: Caixa
        let cursor: CursorDoEditor
        var body: some View {
            VStack(spacing: 0) {
                CodeEditorView(text: $caixa.texto, cursor: cursor)
                RodapeDoBench(cursor: cursor)
            }
        }
    }

    private struct RodapeDoBench: View {
        let cursor: CursorDoEditor
        var body: some View { Text("\(cursor.linha):\(cursor.coluna)") }
    }

    static func arquivoGrande() -> String {
        var texto = "\"\"\"Page Object de exemplo.\n\nDocstring no topo, como o PyCharm gera.\n\"\"\"\n\n"
        var n = 0
        while texto.utf8.count < 1_000_000 {
            n += 1
            texto += "def click_botao_\(n)(self):\n"
            texto += "    self.wait_to_be_visible(self.locators['tela'].BOTAO_\(n), 15)  # espera\n"
            texto += "    self.click(self.locators['tela'].BOTAO_\(n), 2)\n\n"
        }
        return texto
    }

    private func passo(_ janela: NSWindow) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        janela.displayIfNeeded()
    }

    private func mediana(_ valores: [Double]) -> Double { valores.sorted()[valores.count / 2] }

    func testCustoPorTeclaECursorEmArquivoDeUmMega() throws {
        guard ProcessInfo.processInfo.environment["MOBAILE_BENCH"] != nil else {
            throw XCTSkip("defina MOBAILE_BENCH=1 para medir")
        }
        let caixa = Caixa()
        caixa.texto = Self.arquivoGrande()
        let cursor = CursorDoEditor()
        let host = NSHostingView(rootView: Pai(caixa: caixa, cursor: cursor).environment(ThemeManager()))
        let janela = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                              backing: .buffered, defer: false)
        janela.isReleasedWhenClosed = false
        janela.contentView = host
        let inicioCarga = Date()
        passo(janela)
        let carga = Date().timeIntervalSince(inicioCarga) * 1000
        let tv = try XCTUnwrap(Self.textView(em: host))
        janela.makeFirstResponder(tv)
        let meio = (tv.string as NSString).length / 2
        tv.setSelectedRange(NSRange(location: meio, length: 0))
        tv.scrollRangeToVisible(tv.selectedRange())
        passo(janela)

        var teclas: [Double] = []
        for _ in 0..<15 {
            let t0 = Date()
            tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
            passo(janela)
            teclas.append(Date().timeIntervalSince(t0) * 1000)
        }
        var cursores: [Double] = []
        for i in 0..<15 {
            let t0 = Date()
            tv.setSelectedRange(NSRange(location: meio + (i % 2 == 0 ? 120 : 0), length: 0))
            passo(janela)
            cursores.append(Date().timeIntervalSince(t0) * 1000)
        }
        var aspas: [Double] = []
        for _ in 0..<5 {
            let t0 = Date()
            tv.insertText("'", replacementRange: NSRange(location: NSNotFound, length: 0))
            passo(janela)
            aspas.append(Date().timeIntervalSince(t0) * 1000)
        }
        print(String(format: "BENCH bytes=%d carga=%.1fms tecla_mediana=%.1fms tecla_max=%.1fms cursor_mediana=%.1fms cursor_max=%.1fms aspa_mediana=%.1fms",
                     caixa.texto.utf8.count, carga, mediana(teclas), teclas.max()!, mediana(cursores), cursores.max()!, mediana(aspas)))
        XCTAssertGreaterThan(cursor.linha, 1)
    }

    static func textView(em view: NSView) -> CodeTextView? {
        if let tv = view as? CodeTextView { return tv }
        for filho in view.subviews { if let tv = textView(em: filho) { return tv } }
        return nil
    }
}
