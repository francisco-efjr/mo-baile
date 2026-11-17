import XCTest
@testable import MoBaile

/// Log em TSV de uma exploração do GA4: o motor confere só as dimensões
/// exportadas e marca o resto como "não exportado" (fixture
/// `report.audit_ga4_tsv`, gerada pelo motor de verdade).
@MainActor
final class ReportGa4TsvTests: XCTestCase {

    private func relatorio(_ chave: String) throws -> AuditReport {
        let dados = try XCTUnwrap(try resultadosDasFixtures()[chave])
        return try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
    }

    func testDecodificaOsCamposExportadosEONaoExportado() throws {
        let r = try relatorio("report.audit_ga4_tsv")
        XCTAssertEqual(r.exportedFields, ["ga_screen", "flow_name"])
        let sacola = try XCTUnwrap(r.results.first { $0.event == "add_to_cart" && $0.status == .ok })
        let porCampo = Dictionary(uniqueKeysWithValues: sacola.checks.map { ($0.field, $0) })
        XCTAssertEqual(porCampo["screen_name"]?.exported, true)
        XCTAssertEqual(porCampo["flow_name"]?.exported, true)
        for campo in ["insurance", "value", "items[0].item_id", "items[0].item_name"] {
            XCTAssertEqual(porCampo[campo]?.exported, false, campo)
            XCTAssertEqual(porCampo[campo]?.ok, true, campo)
            XCTAssertNil(porCampo[campo]?.obtained, campo)
        }
    }

    func testLogcatNaoTemCamposExportados() throws {
        let r = try relatorio("report.audit")
        XCTAssertNil(r.exportedFields)
        XCTAssertTrue(r.results.flatMap(\.checks).allSatisfy(\.exported))
    }
}
