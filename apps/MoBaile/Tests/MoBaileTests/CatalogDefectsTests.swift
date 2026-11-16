import XCTest
@testable import MoBaile

/// Defeitos achados no catálogo de telas de 09/10/2026
/// (`docs/design/telas/CHECKLIST.md`).
final class CatalogDefectsTests: XCTestCase {

    // MARK: - JSON da Rede (04b)

    /// Defeito: `28.4` virava `28.399999999999999` e a ordem das chaves mudava,
    /// porque o corpo passava por `JSONSerialization` ida e volta.
    func testJSONFormatadoMantemNumerosEOrdem() {
        let corpo = #"{"valor_parcela":487.32,"cet_anual":28.4,"parcelas":12,"ok":true,"nada":null}"#
        let formatado = NetworkEvent.prettyBody(corpo)
        XCTAssertTrue(formatado.contains(#""valor_parcela": 487.32"#), formatado)
        XCTAssertTrue(formatado.contains(#""cet_anual": 28.4"#), formatado)
        XCTAssertFalse(formatado.contains("28.39999"), formatado)
        let ordem = ["valor_parcela", "cet_anual", "parcelas", "ok", "nada"].compactMap { formatado.range(of: $0)?.lowerBound }
        XCTAssertEqual(ordem, ordem.sorted(), "a ordem do servidor é mantida")
    }

    func testJSONFormatadoIndentaENaoMexeEmString() {
        let corpo = #"{"texto":"a, b: {c} [d] \"e\"","lista":[1,{"x":[]}],"vazio":{}}"#
        let esperado = """
        {
          "texto": "a, b: {c} [d] \\"e\\"",
          "lista": [
            1,
            {
              "x": []
            }
          ],
          "vazio": {}
        }
        """
        XCTAssertEqual(NetworkEvent.prettyBody(corpo), esperado)
    }

    func testCorpoQueNaoEJSONFicaComoVeio() {
        XCTAssertEqual(NetworkEvent.prettyBody("valor=1&b=2"), "valor=1&b=2")
        XCTAssertEqual(NetworkEvent.prettyBody("{quebrado"), "{quebrado")
        XCTAssertEqual(NetworkEvent.prettyBody(""), "")
    }

    // MARK: - Passo por coordenada (03b, 08)

    /// Defeito: o passo por coordenada aparecia como "click position", o valor
    /// interno do motor.
    func testPassoPorCoordenadaTemNomeLegivel() {
        let passo = AutomationStep(
            stepNum: 6, actionType: "click", varName: "TOQUE_FECHAR", elementName: "position",
            className: "XCUIElementTypeButton", strategy: .coords, locatorValue: "position",
            coords: CGPoint(x: 1095, y: 210), inputText: nil, package: "app", platform: .ios
        )
        XCTAssertEqual(passo.displayElement, "toque em 1095, 210")
        XCTAssertFalse(passo.summarySentence.contains("position"), passo.summarySentence)
    }

    func testPassoComElementoContinuaComONome() {
        let passo = AutomationStep(
            stepNum: 1, actionType: "click", varName: "BOTAO_CONTINUAR", elementName: "Continuar",
            className: "XCUIElementTypeButton", strategy: .id, locatorValue: "Continuar",
            coords: nil, inputText: nil, package: "app", platform: .ios
        )
        XCTAssertEqual(passo.displayElement, "Continuar")
        XCTAssertEqual(passo.summarySentence, "click Continuar · ID")
    }
}
