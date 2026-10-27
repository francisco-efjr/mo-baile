import XCTest
import AppKit
@testable import MoBaile

/// Edição do card da spec no app e bug copiado a partir de uma validação.
///
/// O cenário é o das fixtures do motor: card 2 (`add_to_cart`) com `items` em
/// JSON e parâmetros próprios do fluxo pessoal; a validação divergente de
/// `interaction_pedido_empresa` (component toggle em vez de button) e as não
/// disparadas, sem `checks`.
@MainActor
final class ReportCardAndBugTests: XCTestCase {

    private func relatorio() throws -> AuditReport {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.audit"])
        return try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
    }

    private func divergente() throws -> ReportResult {
        try XCTUnwrap(try relatorio().results.first { $0.status == .error && $0.variation == "click:parcelas" })
    }

    private func naoDisparada() throws -> ReportResult {
        try XCTUnwrap(try relatorio().results.first { $0.status == .missing && $0.flow == "empresa" })
    }

    private func card() throws -> ReportCardDraft {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.card"])
        return try JSONDecoder().decode(EngineDTO.ReportCardPayload.self, from: dados).toModel()
    }

    // MARK: - Card

    func testCardChegaNaOrdemDoJSONComOQueNaoEditaMarcado() throws {
        let card = try card()
        XCTAssertEqual(card.cardIndex, 2)
        XCTAssertEqual(card.evento, "add_to_cart")
        XCTAssertEqual(card.params.map(\.key), ["screen_name", "flow_name", "insurance", "value", "items"])
        let items = try XCTUnwrap(card.params.last)
        XCTAssertTrue(items.isJSON, "lista volta como JSON, e não como texto")
        XCTAssertEqual(items.value, #"[{"item_id":"[preenchido]","item_name":"pedido-{fluxo}"}]"#)
        XCTAssertFalse(card.params[2].isJSON, "[0|1] é gramática da spec, não JSON")
        XCTAssertEqual(card.paramsPerFlow, ["pessoal"])
    }

    func testCardVoltaParaOMotorComTextoComoTextoEJSONComoJSON() throws {
        var card = try card()
        card.titulo = "Carrinho"
        card.params[2].value = "[0|1|2]"
        let enviado = try card.rpcCard()
        guard case .object(let objeto) = enviado, case .array(let params)? = objeto["params"] else {
            return XCTFail("formato inesperado: \(enviado)")
        }
        XCTAssertEqual(objeto["titulo"], .string("Carrinho"))
        XCTAssertEqual(params[2], .object(["key": .string("insurance"), "value": .string("[0|1|2]")]))
        guard case .object(let items) = params[4], case .array(let lista)? = items["value"] else {
            return XCTFail("items precisa voltar como lista")
        }
        XCTAssertEqual(lista.count, 1)
        XCTAssertNotNil(objeto["obs"], "obs em texto vai junto")
    }

    func testCardInvalidoNaoSaiDoApp() throws {
        var card = try card()
        card.params[4].value = "[{quebrado"
        XCTAssertThrowsError(try card.rpcCard()) { erro in
            XCTAssertEqual(erro as? ReportCardDraft.Problem, .invalidJSON("items"))
        }
        card = try self.card()
        card.evento = "  "
        XCTAssertThrowsError(try card.rpcCard()) { erro in
            XCTAssertEqual(erro as? ReportCardDraft.Problem, .emptyEvent)
        }
    }

    func testGravarCardMandaOIndiceReauditaEMantemALinha() async throws {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        estado.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/log.json"))
        await sessao.runReport()
        let escolhida = try divergente()
        estado.selectedReportResultID = escolhida.id

        let rascunho = await sessao.loadReportCard(escolhida.cardIndex)
        var card = try XCTUnwrap(rascunho)
        let lido = await motor.parametros(de: "report.card")
        XCTAssertEqual(lido?["card_index"], .int(escolhida.cardIndex), "pede o card da linha escolhida")
        card.titulo = "Parcelas"
        let gravou = await sessao.saveReportCard(card)
        XCTAssertTrue(gravou)

        let enviado = await motor.parametros(de: "report.card_update")
        XCTAssertEqual(enviado?["spec_path"], .string(estado.reportSpec?.path ?? ""))
        XCTAssertEqual(enviado?["card_index"], .int(card.cardIndex), "grava no card que foi lido")
        XCTAssertNotNil(enviado?["card"])
        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.suffix(2), ["report.card_update", "report.audit"], "gravou e auditou de novo")
        XCTAssertEqual(estado.selectedReportResult?.cardIndex, escolhida.cardIndex, "a linha escolhida continua")
        XCTAssertEqual(estado.selectedReportResult?.variation, escolhida.variation)
        XCTAssertNil(estado.reportOperation)
        XCTAssertNil(estado.reportError)
    }

    func testErroAoGravarFicaEmLinhaENaoReaudita() async throws {
        let erro = EngineError.engine(code: "invalid_input", message: "card 2: o evento não pode ficar vazio.")
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures(), erros: ["report.card_update": erro])
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        let gravou = await sessao.saveReportCard(try card())
        XCTAssertFalse(gravou)
        XCTAssertTrue(estado.reportError?.contains("evento") == true, estado.reportError ?? "")
        XCTAssertNil(estado.reportOperation, "a aba volta a aceitar comandos")
        let chamadas = await motor.chamadas
        XCTAssertFalse(chamadas.contains("report.audit"))
    }

    // MARK: - Bug

    func testNaoDisparadaTrazOEsperadoDoMotor() throws {
        let linha = try naoDisparada()
        XCTAssertTrue(linha.checks.isEmpty)
        XCTAssertEqual(linha.expected.first, ReportParam(key: "screen_name", value: "app:pedido:empresa:simulacao"))
    }

    func testBugDeDivergenciaNoModeloDoTime() throws {
        let texto = ReportBug.text(for: try divergente(), printName: "simulacao.png")
        for rotulo in ["Resultado Obtido *:", "Usuário, Conta e Cooperativa *:", "Base *:",
                       "Passos para reproduzir problema *:", "Possui imagem/vídeo para similar problema:", "Versão:"] {
            XCTAssertTrue(texto.contains(rotulo), "falta \(rotulo)")
        }
        XCTAssertTrue(texto.contains(#"- component: obtido "toggle", esperado "button""#), texto)
        XCTAssertFalse(texto.contains("- screen_name"), "só o que diverge vai no resultado")
        XCTAssertTrue(texto.contains("1. Abrir o app no fluxo PDE · pedido-empresa."), texto)
        XCTAssertTrue(texto.contains("2. Ir até a tela app:pedido:empresa:simulacao."), texto)
        XCTAssertTrue(texto.contains("3. Executar a ação click:parcelas."), texto)
        XCTAssertTrue(texto.contains("card do Figma (simulacao.png)"))
        XCTAssertTrue(texto.hasSuffix("Tag: automacao"), "erro pego pela automação leva a tag")
    }

    func testBugDeNaoDisparadoListaOEsperado() throws {
        let texto = ReportBug.text(for: try naoDisparada())
        XCTAssertTrue(texto.contains("não foi disparado"), texto)
        XCTAssertTrue(texto.contains("- detail: click:[numero]-parcela-sem-seguro"), texto)
        XCTAssertTrue(texto.contains("Executar a ação click:[numero]-parcela-sem-seguro."), texto)
    }

    func testValidacaoOKNaoViraBug() throws {
        let ok = try XCTUnwrap(try relatorio().results.first { $0.status == .ok })
        XCTAssertFalse(ReportBug.canCreate(for: ok))
        XCTAssertTrue(ReportBug.canCreate(for: try divergente()))
    }

    func testClipboardLevaTextoRicoHTMLComImagemETextoPuro() throws {
        let quadro = NSPasteboard(name: NSPasteboard.Name("mobaile.testes.\(UUID().uuidString)"))
        defer { quadro.releaseGlobally() }
        let linha = try divergente()
        let anexos = ReportBug.attachments(for: linha)
        XCTAssertEqual(anexos.first?.name, "validacao.png", "a validação é desenhada mesmo sem print")
        XCTAssertGreaterThan(anexos.first?.png.count ?? 0, 1000)

        ReportBug.write(text: ReportBug.text(for: linha), attachments: anexos, to: quadro)
        let item = try XCTUnwrap(quadro.pasteboardItems?.first)
        XCTAssertEqual(quadro.pasteboardItems?.count, 1, "um item só: cada destino escolhe a forma")
        XCTAssertNotNil(item.data(forType: .rtfd))
        XCTAssertTrue(item.string(forType: .html)?.contains("data:image/png;base64,") == true)
        XCTAssertTrue(item.string(forType: .html)?.contains("<b>Resultado Obtido *:</b>") == true)
        XCTAssertTrue(item.string(forType: .string)?.hasPrefix("Resultado Obtido *:") == true)
    }

    func testCopiarImagensPoeUmaImagemSo() throws {
        let quadro = NSPasteboard(name: NSPasteboard.Name("mobaile.testes.\(UUID().uuidString)"))
        defer { quadro.releaseGlobally() }
        let mensagem = ReportBug.copyImages(try divergente(), to: quadro)
        XCTAssertEqual(mensagem, "Imagens do bug copiadas")
        let png = try XCTUnwrap(quadro.pasteboardItems?.first?.data(forType: .png))
        XCTAssertNotNil(NSImage(data: png))
    }

    func testHTMLEscapaOTextoDoLog() {
        let html = ReportBug.html(text: "Resultado Obtido *: <script>&", attachments: [])
        XCTAssertTrue(html.contains("&lt;script&gt;&amp;"))
        XCTAssertFalse(html.contains("<script>"))
    }
}
