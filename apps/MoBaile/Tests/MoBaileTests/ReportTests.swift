import XCTest
import SwiftUI
@testable import MoBaile

/// Aba Relatório: o front decodifica o que o motor produz em `report.*`,
/// recorta a tabela sem recalcular nada e manda os parâmetros certos.
///
/// O cenário das fixtures é o mesmo dos testes do motor
/// (`engine/tests/unit/relatorio_dados.py`): 7 validações, 3 OK, 2 divergentes,
/// 2 não disparadas, 3 eventos fora da spec e 1 alerta.
final class ReportContractTests: XCTestCase {

    private func resultado<T: Decodable>(_ nome: String, como tipo: T.Type) throws -> T {
        let dados = try XCTUnwrap(try resultadosDasFixtures()[nome], "fixture ausente: \(nome)")
        return try JSONDecoder().decode(T.self, from: dados)
    }

    func testResumoDaSpec() throws {
        let spec = try resultado("report.spec", como: EngineDTO.ReportSpecPayload.self).toModel()
        XCTAssertEqual(spec.projeto, "Teste")
        XCTAssertEqual(spec.plataforma, .android)
        XCTAssertEqual(spec.cards, 3)
        XCTAssertEqual(spec.variants, 7)
        XCTAssertEqual(spec.fluxos.map(\.key), ["pessoal", "investimentos"], "a ordem dos fluxos é a das colunas")
        XCTAssertEqual(spec.sections, ["Home", "Simulação"])
        XCTAssertEqual(spec.fileName, "spec.json")
        XCTAssertTrue(spec.printsDirExists)
    }

    func testAuditoriaMapeiaResumoELinhas() throws {
        let relatorio = try resultado("report.audit", como: EngineDTO.ReportAuditPayload.self).toModel()
        XCTAssertEqual(relatorio.summary.total, 7)
        XCTAssertEqual(relatorio.summary.ok, 3)
        XCTAssertEqual(relatorio.summary.divergent, 2)
        XCTAssertEqual(relatorio.summary.missing, 2)
        XCTAssertEqual(relatorio.summary.needsAction, 4)
        XCTAssertEqual(relatorio.summary.complianceRate, 42.9, accuracy: 0.001)
        XCTAssertEqual(relatorio.logStats, ReportLogStats(totalRead: 12, platformEvents: 11, duplicates: 1, useful: 10))
        XCTAssertEqual(relatorio.results.count, 7)
        XCTAssertEqual(Set(relatorio.results.map(\.status)), [.ok, .error, .missing])
        XCTAssertEqual(relatorio.outOfSpec.count, 3)
        XCTAssertEqual(relatorio.alerts.map(\.event), ["app_exception"])
        XCTAssertEqual(Set(relatorio.extras.map(\.id)).count, 4, "fora da spec e alertas precisam de ids distintos")
        XCTAssertEqual(relatorio.tsv.split(separator: "\n").count, 8)
        XCTAssertTrue(relatorio.markdown.hasPrefix("# Auditoria de Tagueamento"))
    }

    func testLinhaDivergenteTrazOQueCorrigir() throws {
        let relatorio = try resultado("report.audit", como: EngineDTO.ReportAuditPayload.self).toModel()
        let erro = try XCTUnwrap(relatorio.results.first {
            $0.status == .error && $0.flow == "investimentos" && $0.variation == "click:parcelas"
        })
        XCTAssertEqual(erro.flowLabel, "CPAGI · credito-investimentos")
        XCTAssertEqual(erro.checks.filter { !$0.ok }.map(\.field), ["component"])
        XCTAssertEqual(erro.checks.first { $0.field == "component" }?.obtained, "toggle")
        XCTAssertEqual(erro.divergences, "component: obtido toggle, esperado button")
        XCTAssertTrue(erro.block.contains("✗"))
        XCTAssertEqual(erro.matched?.time, "10:02:00.000")
    }

    func testParametroAninhadoDoDisparoViraTexto() throws {
        let relatorio = try resultado("report.audit", como: EngineDTO.ReportAuditPayload.self).toModel()
        let carrinho = try XCTUnwrap(relatorio.results.first { $0.event == "add_to_cart" && $0.flow == "pessoal" })
        let items = try XCTUnwrap(carrinho.matched?.params["items"])
        XCTAssertTrue(items.contains("credito-pessoal"), items)
        XCTAssertEqual(carrinho.olderDivergent, 1)
    }

    func testNaoDisparadaNaoTemDisparo() throws {
        let relatorio = try resultado("report.audit", como: EngineDTO.ReportAuditPayload.self).toModel()
        let ausente = try XCTUnwrap(relatorio.results.first { $0.status == .missing })
        XCTAssertNil(ausente.matched)
        XCTAssertTrue(ausente.checks.isEmpty)
        XCTAssertTrue(ausente.block.contains("NÃO DISPARADO"))
    }

    func testPrintSoQuandoOArquivoExiste() throws {
        let relatorio = try resultado("report.audit", como: EngineDTO.ReportAuditPayload.self).toModel()
        XCTAssertEqual(relatorio.results.first { $0.cardIndex == 0 }?.printPath.map { ($0 as NSString).lastPathComponent },
                       "home.png")
        XCTAssertNil(relatorio.results.first { $0.cardIndex == 1 }?.printPath)
    }

    func testExportacao() throws {
        let exportado = try resultado("report.export", como: EngineDTO.ReportExportPayload.self).toModel()
        XCTAssertEqual(exportado.files.map(\.kind), ["board", "html", "markdown", "tsv"])
        XCTAssertEqual(exportado.file("html")?.name, "relatorio_auditoria.html")
        XCTAssertTrue(exportado.files.allSatisfy { $0.bytes > 0 && $0.path.hasPrefix(exportado.directory) })
    }

    func testImportacao() throws {
        let importado = try resultado("report.import", como: EngineDTO.ReportImportPayload.self).toModel()
        XCTAssertTrue(importado.specPath.hasSuffix(".json"))
        XCTAssertTrue(importado.reviewPath.hasSuffix(".revisao.md"))
        XCTAssertNotNil(importado.spec)
        XCTAssertNil(importado.specError)
        XCTAssertEqual(importado.review.count, 2)
        XCTAssertEqual(importado.doubtsTotal, importado.review.reduce(0) { $0 + $1.doubts.count })
    }

    func testSessaoSemEventosChegaComoErroDeEntrada() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine_payloads", withExtension: "json"))
        let raiz = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let dados = try JSONSerialization.data(withJSONObject: try XCTUnwrap(raiz["erro_report_sessao_vazia"]))
        XCTAssertThrowsError(try EngineClient.decodeResult(dados, as: EngineDTO.ReportAuditPayload.self)) { erro in
            guard case .engine(let codigo, let mensagem) = erro as? EngineError else {
                return XCTFail("esperava erro de domínio, veio \(erro)")
            }
            XCTAssertEqual(codigo, "invalid_input")
            XCTAssertTrue(mensagem.contains("Analytics"), "a mensagem precisa dizer o que fazer: \(mensagem)")
        }
    }

    func testMetodosDoRelatorioNaTabelaDoHello() throws {
        let hello = try resultado("engine.hello", como: EngineDTO.Hello.self)
        for metodo in ["report.spec", "report.audit", "report.export", "report.import"] {
            XCTAssertEqual(hello.methods[metodo]?.lane, "report", metodo)
        }
        XCTAssertEqual(hello.methods["report.import"]?.progress, true)
        XCTAssertGreaterThan(hello.methods["report.import"]?.timeoutS ?? 0, 300, "o OCR compila o leitor na primeira vez")
    }
}

/// Recortes da tabela e regras de habilitação, sem motor.
@MainActor
final class ReportStateTests: XCTestCase {

    private func estadoComRelatorio() throws -> AppState {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.audit"])
        let relatorio = try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
        let estado = AppState()
        estado.reportSpec = relatorio.spec
        estado.report = relatorio
        return estado
    }

    func testFiltrosPorStatus() throws {
        let estado = try estadoComRelatorio()
        let contagem: [ReportFilter: Int] = [.all: 7, .needsAction: 4, .divergent: 2, .missing: 2, .ok: 3, .outOfSpec: 0]
        for (filtro, esperado) in contagem {
            estado.reportFilter = filtro
            XCTAssertEqual(estado.filteredReportResults.count, esperado, filtro.title)
        }
    }

    func testBuscaProcuraEmEventoVariacaoEDivergencia() throws {
        let estado = try estadoComRelatorio()
        estado.reportFilterText = "TOGGLE"
        XCTAssertEqual(estado.filteredReportResults.map(\.variation), ["click:parcelas"])
        estado.reportFilterText = "add_to_cart"
        XCTAssertEqual(estado.filteredReportResults.count, 2)
        estado.reportFilterText = "modal_view"
        XCTAssertTrue(estado.filteredReportResults.isEmpty)
        XCTAssertEqual(estado.filteredReportExtras.map(\.event), ["modal_view"])
    }

    func testContagemDaBarraLateralEOQuePedeAcao() throws {
        let estado = try estadoComRelatorio()
        XCTAssertEqual(estado.reportBadgeCount, 4)
        XCTAssertEqual(AppState().reportBadgeCount, 0)
    }

    func testAuditarPrecisaDeSpecEDeEventos() throws {
        let estado = try estadoComRelatorio()
        estado.reportLogSource = .session
        XCTAssertFalse(estado.canRunReport, "sem eventos capturados, a sessão não tem o que auditar")
        estado.reportLogSource = .file(URL(fileURLWithPath: "/tmp/log_obtido.json"))
        XCTAssertTrue(estado.canRunReport)
        estado.reportOperation = .exporting
        XCTAssertFalse(estado.canRunReport, "uma operação de cada vez")
        estado.reportOperation = nil
        estado.reportSpec = nil
        XCTAssertFalse(estado.canRunReport)
    }

    func testPlataformaEfetivaVemDaSpecQuandoNaoHaEscolha() throws {
        let estado = try estadoComRelatorio()
        XCTAssertEqual(estado.reportEffectivePlatform, .android)
        estado.reportPlatform = .ios
        XCTAssertEqual(estado.reportEffectivePlatform, .ios)
    }

    func testRelatorioNaoPrecisaDeAparelhoEUsaABuscaDaToolbar() {
        let estado = AppState()
        XCTAssertFalse(WorkspaceTab.report.needsDevice)
        XCTAssertTrue(WorkspaceTab.allCases.filter { $0 != .report }.allSatisfy(\.needsDevice))
        estado.workspaceTab = .report
        XCTAssertNil(estado.selectedDevice)
        XCTAssertTrue(estado.usesToolbarSearch, "sem aparelho, ⌘F no Relatório filtra a tabela")
        estado.workspaceTab = .pageObjects
        XCTAssertFalse(estado.usesToolbarSearch)
    }

    func testStatusTemIconeCorETexto() {
        XCTAssertEqual(ReportStatus.ok.daemonState, .ok)
        XCTAssertEqual(ReportStatus.error.daemonState, .error)
        XCTAssertEqual(ReportStatus.missing.daemonState, .warn)
        XCTAssertEqual(ReportStatus.allCases.map(\.displayName), ["OK", "Divergente", "Não disparado"])
        XCTAssertLessThan(ReportStatus.error.sortRank, ReportStatus.ok.sortRank, "o que pede ação vem primeiro")
    }
}

/// A sessão traduz os gestos da aba em `report.*` com os parâmetros certos.
@MainActor
final class ReportSessionTests: XCTestCase {

    private func ambiente(erros: [String: EngineError] = [:]) throws -> (AppState, EngineSession, FakeEngine) {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures(), erros: erros)
        return (estado, EngineSession(state: estado, client: motor), motor)
    }

    func testAbrirSpecMostraOResumoSemAuditar() async throws {
        let (estado, sessao, motor) = try ambiente()
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        XCTAssertEqual(estado.reportSpec?.projeto, "Teste")
        XCTAssertNil(estado.report)
        XCTAssertNil(estado.reportOperation)
        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas, ["report.spec"])
        let params = await motor.parametros(de: "report.spec")
        XCTAssertEqual(params?["path"], .string("/Users/qa/spec.json"))
    }

    func testAuditarComArquivoMandaCaminhoEPlataforma() async throws {
        let (estado, sessao, motor) = try ambiente()
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        estado.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/log_obtido.json"))
        estado.reportPlatform = .ios
        await sessao.runReport()

        let enviados = await motor.parametros(de: "report.audit")
        let params = try XCTUnwrap(enviados)
        XCTAssertEqual(params["source"], .string("file"))
        XCTAssertEqual(params["log_path"], .string("/Users/qa/log_obtido.json"))
        XCTAssertEqual(params["platform"], .string("ios"))
        XCTAssertNotNil(params["progress_token"], "auditoria longa precisa de andamento")
        XCTAssertEqual(estado.report?.summary.total, 7)
        XCTAssertNil(estado.reportOperation)
        XCTAssertNil(estado.reportError)
    }

    func testAuditarDaSessaoNaoMandaArquivoNemPlataforma() async throws {
        let (estado, sessao, motor) = try ambiente()
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        estado.reportLogSource = .session
        await sessao.runReport()
        let enviados = await motor.parametros(de: "report.audit")
        let params = try XCTUnwrap(enviados)
        XCTAssertEqual(params["source"], .string("session"))
        XCTAssertNil(params["log_path"])
        XCTAssertNil(params["platform"], "sem escolha, vale a plataforma da spec, decidida pelo motor")
    }

    func testTrocarDeSpecDescartaORelatorioDaAnterior() async throws {
        let (estado, sessao, _) = try ambiente()
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        await sessao.runReport()
        XCTAssertNotNil(estado.report)
        estado.reportSpec = ReportSpec(
            path: "/outra/spec.json", projeto: "Outra", versao: nil, plataforma: .ios, printsDir: nil,
            printsDirExists: false, fluxos: [], cards: 1, variants: 1, sections: []
        )
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        XCTAssertNil(estado.report, "números de outra spec não podem continuar na tela")
    }

    func testErroDoMotorFicaEmLinhaENaoTrava() async throws {
        let erro = EngineError.engine(code: "invalid_input", message: "A spec não tem cards.")
        let (estado, sessao, _) = try ambiente(erros: ["report.spec": erro])
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/vazia.json"))
        XCTAssertNotNil(estado.reportError)
        XCTAssertTrue(estado.reportError?.contains("não tem cards") == true, estado.reportError ?? "")
        XCTAssertNil(estado.reportOperation, "a aba precisa voltar a aceitar comandos depois do erro")
        XCTAssertNil(estado.reportSpec)
    }

    func testExportarGuardaOsArquivos() async throws {
        let (estado, sessao, motor) = try ambiente()
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        estado.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/log.json"))
        await sessao.runReport()
        let exportado = await sessao.exportReport(to: URL(fileURLWithPath: "/Users/qa/saida"))
        XCTAssertEqual(exportado?.files.count, 4)
        XCTAssertEqual(estado.reportLastExport, exportado)
        let params = await motor.parametros(de: "report.export")
        XCTAssertEqual(params?["directory"], .string("/Users/qa/saida"))
    }

    func testExportarSemDestinoDeixaOMotorEscolher() async throws {
        let (estado, sessao, motor) = try ambiente()
        await sessao.openReportSpec(at: URL(fileURLWithPath: "/Users/qa/spec.json"))
        estado.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/log.json"))
        await sessao.runReport()
        await sessao.exportReport(to: nil)
        let params = await motor.parametros(de: "report.export")
        XCTAssertNil(params?["directory"], "a pasta padrão é regra do motor, não da interface")
    }

    func testImportarAbreARevisaoEUsarCarregaARascunho() async throws {
        let (estado, sessao, motor) = try ambiente()
        await sessao.importReportPrints(from: URL(fileURLWithPath: "/Users/qa/prints"), projeto: nil, platform: .ios)
        let importado = try XCTUnwrap(estado.reportImport)
        XCTAssertEqual(importado.review.count, 2)
        let params = await motor.parametros(de: "report.import")
        XCTAssertEqual(params?["platform"], .string("ios"))
        XCTAssertNil(params?["projeto"], "sem nome, o motor usa o nome da pasta")

        await sessao.useImportedSpec()
        XCTAssertNil(estado.reportImport)
        let caminho = await motor.parametros(de: "report.spec")?["path"]
        XCTAssertEqual(caminho, .string(importado.specPath))
    }
}

/// O que o leitor de tela recebe da aba (ver `AccessibilityInspector`).
@MainActor
final class ReportAccessibilityTests: XCTestCase {

    private func arvore<V: View>(_ view: V, largura: CGFloat = 1100, altura: CGFloat = 700) throws -> AXNode {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.audit"])
        let relatorio = try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
        let estado = AppState()
        estado.workspaceTab = .report
        estado.reportSpec = relatorio.spec
        estado.report = relatorio
        estado.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/log_obtido.json"))
        estado.selectedReportResultID = relatorio.results.first {
            $0.status == .error && $0.flow == "investimentos" && $0.variation == "click:parcelas"
        }?.id
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        return try AccessibilityInspector.arvore(
            de: view.environment(estado).environment(sessao).environment(ThemeManager()),
            largura: largura, altura: altura
        )
    }

    /// Menus e botões da barra dizem o que são, e não o nome do símbolo.
    func testBarraTemNomesProprios() throws {
        let ax = try arvore(ReportToolbar(), largura: 1100, altura: 60)
        for nome in ["Spec de tagueamento", "Origem dos eventos", "Plataforma auditada", "Auditar",
                     "Exportar relatório", "Copiar relatório"] {
            XCTAssertNotNil(ax.node(label: nome), "falta \(nome)\n\(ax.dump)")
        }
        XCTAssertFalse(ax.all.map(\.label).contains("checklist"), "nome de símbolo vazou\n\(ax.dump)")
    }

    /// Cada variação é uma linha com estado de seleção, e a primeira célula lê
    /// o status em palavra (não só a cor do ícone) e a divergência.
    func testLinhaDaValidacaoLeStatusEDivergencia() throws {
        let ax = try arvore(ReportView())
        let linha = ax.all.first { no in
            no.role == "AXRow" && no.all.contains { $0.label.contains("Divergente: interaction_credito_investimentos") }
        }
        XCTAssertNotNil(linha, ax.dump)
        XCTAssertEqual(linha?.isSelected, true, ax.dump)
        XCTAssertTrue(linha?.all.contains { $0.label.contains("component: obtido toggle") } == true, ax.dump)
    }

    /// No Relatório o inspector mostra o card do Figma da validação, e não a
    /// hierarquia vazia de "Conecte um aparelho".
    func testInspectorMostraOCardDaValidacao() throws {
        let ax = try arvore(ReportCardInspector(), largura: 280, altura: 500)
        XCTAssertNotNil(ax.node(label: "Card do Figma"), ax.dump)
        // Texto estático expõe o conteúdo em `value`, que é o que o VoiceOver lê.
        let textos = ax.all.map { "\($0.label) \($0.value)" }.joined(separator: " | ")
        XCTAssertTrue(textos.contains("interaction_credito_investimentos"), textos)
        XCTAssertTrue(textos.contains("CPAGI · credito-investimentos"), textos)
        XCTAssertTrue(textos.contains("Sem print"), "falta dizer por que não há print:\n\(ax.dump)")
        XCTAssertFalse(textos.contains("Conecte um aparelho"), textos)
    }

    /// O parâmetro divergente é anunciado com "diverge" e os dois valores.
    func testParametroDivergenteEAnunciado() throws {
        let ax = try arvore(ReportView())
        XCTAssertNotNil(ax.node(label: "component: diverge, obtido toggle, esperado button"), ax.dump)
        XCTAssertNotNil(ax.node(label: "flow_name: confere, obtido credito-investimentos, esperado credito-investimentos"),
                        ax.dump)
    }
}
