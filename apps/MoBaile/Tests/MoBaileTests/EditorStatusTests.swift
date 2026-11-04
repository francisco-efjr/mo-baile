import XCTest
@testable import MoBaile

/// PO-4: rodapé do editor como a status bar do PyCharm, no lugar do
/// "Código sincronizado" fixo.
final class EditorStatusTests: XCTestCase {
    private let quatorzeETrinta: Date = {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (2026, 11, 4, 14, 32)
        return Calendar.current.date(from: c)!
    }()

    func testSemCodigoNaoDizNada() {
        XCTAssertNil(EditorStatus.salvamento(acoes: "", locators: "", salvo: nil))
    }

    func testCodigoNuncaSalvoENaoSalvo() {
        let estado = EditorStatus.salvamento(acoes: "def a(): pass", locators: "", salvo: nil)
        XCTAssertEqual(estado?.texto, "não salvo")
        XCTAssertEqual(estado?.sujo, true)
    }

    func testDepoisDoSalvarMostraAHoraEVoltaANaoSalvoAoEditar() {
        let salvo = CodigoSalvo(acoes: "a", locators: "b", em: quatorzeETrinta, caminho: "/x/pages/f.py")
        let limpo = EditorStatus.salvamento(acoes: "a", locators: "b", salvo: salvo)
        XCTAssertEqual(limpo?.texto, "salvo às 14:32")
        XCTAssertEqual(limpo?.sujo, false)
        XCTAssertEqual(EditorStatus.salvamento(acoes: "a!", locators: "b", salvo: salvo)?.texto, "não salvo")
    }

    func testInterpretadorDoSetup() {
        XCTAssertEqual(EditorStatus.interpretador(versao: "3.13.1"), "Python 3.13.1")
        XCTAssertEqual(EditorStatus.interpretador(versao: nil), "Python")
    }
}
