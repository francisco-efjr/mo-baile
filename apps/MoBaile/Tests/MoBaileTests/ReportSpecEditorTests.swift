import XCTest
@testable import MoBaile

/// Editor de spec dentro do app: a spec inteira lida por `report.cards` e os
/// cards alterados gravados juntos por `report.cards_update`.
@MainActor
final class ReportSpecEditorTests: XCTestCase {

    private func spec() throws -> ReportSpecDraft {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.cards"])
        return try JSONDecoder().decode(EngineDTO.ReportCardsPayload.self, from: dados).toModel()
    }

    func testSpecInteiraChegaComCardsFluxosEPrints() throws {
        let spec = try spec()
        XCTAssertNil(spec.specError)
        XCTAssertEqual(spec.cards.map(\.cardIndex), Array(0..<spec.cards.count))
        XCTAssertEqual(spec.cards.count, 3)
        XCTAssertFalse(spec.fluxos.isEmpty)
        XCTAssertFalse(spec.isDirty)
        XCTAssertFalse(spec.canSave, "sem alteração não há o que gravar")
        let comPrint = try XCTUnwrap(spec.cards.first { $0.printName != nil })
        XCTAssertEqual(spec.printPath(of: comPrint), (try XCTUnwrap(spec.printsDir) as NSString)
            .appendingPathComponent(try XCTUnwrap(comPrint.printName)))
    }

    func testSoOCardAlteradoVaiParaOMotor() throws {
        var spec = try spec()
        spec.cards[1].titulo = "Parcelas novas"
        XCTAssertTrue(spec.isDirty)
        XCTAssertTrue(spec.isDirty(1))
        XCTAssertFalse(spec.isDirty(0))
        XCTAssertEqual(spec.dirtyCards.map(\.cardIndex), [1])
        XCTAssertTrue(spec.canSave)
    }

    func testProblemaNoCardAlteradoBarraOSalvar() throws {
        var spec = try spec()
        spec.cards[0].evento = " "
        spec.cards[0].params.append(.init(key: spec.cards[0].params[0].key, value: "x"))
        spec.cards[0].params.append(.init(key: "", value: "y"))
        let problemas = spec.cards[0].problems
        XCTAssertTrue(problemas.contains("Informe o evento (ex.: purchase)."), "\(problemas)")
        XCTAssertTrue(problemas.contains { $0.hasSuffix("Renomeie ou remova uma das linhas.") }, "\(problemas)")
        XCTAssertTrue(problemas.contains { $0.hasSuffix("Dê um nome ao parâmetro ou remova a linha.") }, "\(problemas)")
        XCTAssertFalse(spec.canSave)

        var json = try self.spec()
        let items = try XCTUnwrap(json.cards[2].params.firstIndex { $0.isJSON })
        json.cards[2].params[items].value = "[{quebrado"
        XCTAssertTrue(json.cards[2].problems.contains { $0.contains("não é um JSON válido") })
    }

    func testCardApontadoPeloMotor() {
        let rascunho = ReportSpecDraft(
            path: "/Users/qa/rascunho.json", projeto: nil,
            specError: "Campo obrigatório ausente na spec: 'card 3.evento'.",
            printsDir: nil, fluxos: [], cards: [], saved: []
        )
        XCTAssertEqual(rascunho.invalidCardIndex, 2)
    }

    func testGravarMandaSoOsAlteradosEAuditaDeNovo() async throws {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        estado.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/log.json"))
        await sessao.runReport()

        await sessao.openReportSpecEditor(path: try XCTUnwrap(estado.reportSpec?.path))
        XCTAssertEqual(estado.reportSpecEditor?.cards.count, 3)
        estado.reportSpecEditor?.cards[0].secao = "Início revisado"
        let gravou = await sessao.saveReportSpecEditor()
        XCTAssertTrue(gravou)

        let enviado = await motor.parametros(de: "report.cards_update")
        guard case .array(let cards)? = enviado?["cards"], case .object(let primeiro)? = cards.first else {
            return XCTFail("formato inesperado: \(String(describing: enviado))")
        }
        XCTAssertEqual(cards.count, 1, "só o card alterado")
        XCTAssertEqual(primeiro["card_index"], .int(0))
        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.suffix(2), ["report.cards_update", "report.audit"], "gravou e auditou de novo")
        XCTAssertEqual(estado.reportSpecEditor?.isDirty, false, "o editor fica com o que foi gravado")
        XCTAssertNil(estado.reportOperation)
        XCTAssertNil(estado.reportError)
    }

    func testErroAoGravarMantemOEditorComAsAlteracoes() async throws {
        let erro = EngineError.engine(code: "invalid_input", message: "card 1: o evento não pode ficar vazio.")
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures(), erros: ["report.cards_update": erro])
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.openReportSpecEditor(path: "/Users/qa/spec.json")
        estado.reportSpecEditor?.cards[0].titulo = "Outro"
        let gravou = await sessao.saveReportSpecEditor()
        XCTAssertFalse(gravou)
        XCTAssertEqual(estado.reportSpecEditor?.cards[0].titulo, "Outro")
        XCTAssertEqual(estado.reportSpecEditor?.isDirty, true)
        XCTAssertTrue(estado.reportError?.contains("evento") == true, estado.reportError ?? "")
        XCTAssertNil(estado.reportOperation)
    }
}
