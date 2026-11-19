import XCTest
@testable import MoBaile

/// Edição na aba Relatório (3.28.0): problema no campo, regras dos valores,
/// linha vazia, resumo do JSON e conferências agrupadas por item.
/// Recomendações RE-01 a RE-08 de docs/melhorias/2026-11-19-relatorio-edicao.
@MainActor
final class ReportEditingTests: XCTestCase {

    private func card() throws -> ReportCardDraft {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.card"])
        return try JSONDecoder().decode(EngineDTO.ReportCardPayload.self, from: dados).toModel()
    }

    // MARK: - Problema no campo (RE-02)

    func testProblemaFicaNoCampoQueCausou() throws {
        var card = try card()
        card.evento = ""
        card.params.append(.init(key: "", value: "x"))
        let semNome = try XCTUnwrap(card.params.last).id
        card.params.append(.init(key: "screen_name", value: "outra"))
        let repetido = try XCTUnwrap(card.params.last).id
        let problemas = card.issues()

        XCTAssertEqual(problemas.evento?.message, "Informe o evento (ex.: purchase).")
        XCTAssertEqual(problemas.rows[semNome]?.key?.message, "Dê um nome ao parâmetro ou remova a linha.")
        XCTAssertNil(problemas.rows[semNome]?.value)
        XCTAssertTrue(try XCTUnwrap(problemas.rows[repetido]?.key?.message).hasPrefix("screen_name já aparece"))
        XCTAssertEqual(problemas.blockingCount, 3)
        XCTAssertEqual(problemas.firstBlockingRow, semNome, "a primeira linha com erro, na ordem do card")
        XCTAssertEqual(card.problems.count, 3, "problems e issues contam o mesmo")
    }

    func testJSONQuebradoAcusaNoValor() throws {
        var card = try card()
        let items = try XCTUnwrap(card.params.firstIndex { $0.isJSON })
        card.params[items].value = "[{quebrado"
        let problema = try XCTUnwrap(card.issues().rows[card.params[items].id])
        XCTAssertNil(problema.key)
        XCTAssertEqual(problema.value?.message, "items não é um JSON válido. Abra o editor de JSON para ver onde.")
        XCTAssertTrue(problema.blocking)
    }

    // MARK: - Linha vazia (D3)

    func testLinhaVaziaNaoEProblemaESaiAoGravar() throws {
        var card = try card()
        let antes = card.params.count
        card.params.append(.init(key: "", value: ""))
        card.params.append(.init(key: "  ", value: " "))
        card.variacoes.append(.init(fields: [.init(key: "", value: "")]))
        XCTAssertTrue(card.problems.isEmpty, "\(card.problems)")

        guard case .object(let enviado) = try card.rpcCard(),
              case .array(let params)? = enviado["params"],
              case .array(let variacoes)? = enviado["variacoes"] else {
            return XCTFail("formato inesperado")
        }
        XCTAssertEqual(params.count, antes)
        XCTAssertEqual(variacoes.count, card.variacoes.count - 1, "variação só com linha vazia não vai")
    }

    // MARK: - Regras dos valores (RE-08)

    func testRegraDesconhecidaVemComSugestao() {
        XCTAssertEqual(ReportValueRules.unknownToken(in: "[soma_item]")?.token, "[soma_item]")
        XCTAssertEqual(ReportValueRules.unknownToken(in: "[soma_item]")?.suggestion, "[soma_itens]")
        XCTAssertEqual(ReportValueRules.unknownToken(in: "app:[preenchida]")?.suggestion, "[preenchido]")
        XCTAssertNil(ReportValueRules.unknownToken(in: "[campanha]")?.suggestion, "longe de todas: sem sugestão")
        XCTAssertNotNil(ReportValueRules.unknownToken(in: "[campanha]"))
    }

    func testRegrasConhecidasNaoAvisam() {
        for valor in ["[preenchido]", "[numero]", "[data]", "[soma_itens]", "[0|1]", "app:[avulso|empresa]:home",
                      "re:^[A-Z]{3}$", #"[{"item_id":"[preenchido]"}]"#, #"["a","b"]"#] {
            XCTAssertNil(ReportValueRules.unknownToken(in: valor), valor)
        }
    }

    func testAvisoNaoBarraOSalvar() throws {
        var card = try card()
        card.params[0].value = "[soma_item]"
        let problema = try XCTUnwrap(card.issues().rows[card.params[0].id]?.value)
        XCTAssertFalse(problema.blocking)
        XCTAssertTrue(problema.message.contains("Quis dizer [soma_itens]?"))
        XCTAssertTrue(card.problems.isEmpty, "aviso não entra em problems")
    }

    func testSomaDentroDeItemsEChaveComLadoVazioAvisam() throws {
        var card = try card()
        let items = try XCTUnwrap(card.params.firstIndex { $0.isJSON })
        card.params[items].value = #"[{"item_id":"[preenchido]","price":"[soma_itens]"}]"#
        card.params.append(.init(key: "item_id|", value: "[preenchido]"))
        let problemas = card.issues()
        XCTAssertEqual(problemas.rows[card.params[items].id]?.value?.blocking, false)
        XCTAssertEqual(problemas.rows[try XCTUnwrap(card.params.last).id]?.key?.blocking, false)
    }

    func testMenuDeRegrasAplicaNoValor() throws {
        let regra = { (token: String) in try XCTUnwrap(ReportValueRules.rules.first { $0.token == token }) }
        XCTAssertEqual(try regra("re:").apply("^[A-Z]{3}$"), "re:^[A-Z]{3}$")
        XCTAssertEqual(try regra("re:").apply("re:x"), "re:x", "não repete o prefixo")
        XCTAssertEqual(try regra("{fluxo}").apply("app:"), "app:{fluxo}")
        XCTAssertEqual(try regra("[soma_itens]").apply("72.05"), "[soma_itens]")
        XCTAssertEqual(ReportValueRules.rules.last?.token, "[soma_itens]", "soma fica depois do divisor")
    }

    // MARK: - JSON (RE-03)

    func testResumoDoJSON() {
        XCTAssertEqual(ReportJSONSummary.text(#"[{"item_id":"1","price":"2"},{"item_id":"3"}]"#),
                       "lista · 2 itens · item_id, price")
        XCTAssertEqual(ReportJSONSummary.text(#"{"a":1}"#), "objeto · 1 campo")
        XCTAssertEqual(ReportJSONSummary.text("[{quebrado"), "JSON inválido")
    }

    func testValidacaoDoJSONDizOQueHouve() throws {
        if case .failure(let erro) = ReportJSONSummary.validate(#"[{"a":1"#) {
            XCTAssertFalse(erro.message.isEmpty)
        } else {
            XCTFail("lista sem fechar não é JSON")
        }
        if case .failure(let erro) = ReportJSONSummary.validate(#""texto""#) {
            XCTAssertTrue(erro.message.contains("lista"))
        } else {
            XCTFail("texto solto não serve como valor JSON")
        }
        XCTAssertNotNil(try? ReportJSONSummary.validate(ReportJSONSummary.pretty(#"[{"b":1,"a":2}]"#)).get())
    }

    // MARK: - Conferências por item (RE-01, RE-04)

    func testCampoDeItemEAlternativa() throws {
        let partes = try XCTUnwrap(ReportItemField.split("items[11].item_id|item_name"))
        XCTAssertEqual(partes.item, 11)
        XCTAssertEqual(partes.key, "item_id|item_name")
        XCTAssertNil(ReportItemField.split("value"))
        let via = try XCTUnwrap(ReportItemField.viaAlternative(key: "item_id|item_name", obtained: "item_name=Tee=1"))
        XCTAssertEqual(via.value, "Tee=1")
        XCTAssertEqual(via.via, "item_name")
        XCTAssertNil(ReportItemField.viaAlternative(key: "item_id", obtained: "item_id=1"), "sem alternativa, nada muda")
        XCTAssertEqual(ReportItemField.spoken("item_id|item_name"), "item_id ou item_name")
    }

    func testGruposEResumoDaDivergencia() {
        let checks = [
            ReportCheck(field: "value", expected: "soma dos itens: 72.05", obtained: "999.99", ok: false),
            ReportCheck(field: "currency", expected: "USD", obtained: "USD", ok: true),
            ReportCheck(field: "items[0].item_id|item_name", expected: "[preenchido]", obtained: "item_name=Tee", ok: true),
            ReportCheck(field: "items[1].item_id|item_name", expected: "[preenchido]", obtained: nil, ok: false),
            ReportCheck(field: "items[2].price", expected: "[numero]", obtained: "x", ok: false),
        ]
        let resultado = ReportResult(
            id: 1, cardIndex: 0, section: "Checkout", cardTitle: "Compra", printPath: nil, flow: nil, flowLabel: nil,
            event: "purchase", variation: "", status: .error, checks: checks, matched: nil, occurrences: 1,
            olderDivergent: 2, olderDivergences: ["value=1"], gaScreen: nil, note: nil,
            divergences: "value, items[1].item_id|item_name, items[2].price", block: ""
        )
        let grupos = resultado.checkGroups
        XCTAssertEqual(grupos.map(\.id), ["evento", "items[0]", "items[1]", "items[2]"])
        XCTAssertEqual(grupos[1].identification, "Tee")
        XCTAssertEqual(grupos[1].shortKey(checks[2]), "item_id|item_name")
        XCTAssertEqual(grupos.map(\.divergent), [1, 0, 1, 1])
        XCTAssertEqual(resultado.divergenceSummary, "value · items: 2 itens · +2 anteriores")
        XCTAssertTrue(resultado.divergenceTooltip.hasPrefix("value: obtido 999.99, esperado soma dos itens: 72.05"))
    }
}
