import XCTest
@testable import MoBaile

/// Ajuda por área (LIB-2), aviso de beta e Relatar um Problema (LIB-3).
@MainActor
final class HelpAndBugReportTests: XCTestCase {

    private var raiz: URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" && !FileManager.default.fileExists(atPath: url.appendingPathComponent("engine/src/mobaile").path) {
            url.deleteLastPathComponent()
        }
        return url
    }

    private var pastaAjuda: URL { raiz.appendingPathComponent("docs/ajuda") }

    // MARK: - Ajuda: um guia por área, no formato que o app lê

    func testTodaAreaTemSeuGuiaNoFormatoCerto() throws {
        XCTAssertEqual(HelpLibrary.topics.count, WorkspaceTab.allCases.count + 2)
        for topico in HelpLibrary.topics {
            let doc = try XCTUnwrap(HelpLibrary.load(topico, in: pastaAjuda), "falta docs/ajuda/\(topico).md")
            XCTAssertEqual(doc.area, topico, "front matter area de \(topico)")
            XCTAssertFalse(doc.title.isEmpty, topico)
            XCTAssertFalse(doc.summary.isEmpty, topico)
            XCTAssertLessThanOrEqual(doc.summary.count, 110, "resumo de \(topico)")
            XCTAssertEqual(doc.headings, HelpDocument.sections, "seções de \(topico)")
            XCTAssertEqual(doc.unsupported, [], "Markdown fora do subconjunto em \(topico)")
            let palavras = doc.plainText.split(whereSeparator: { $0.isWhitespace }).count
            XCTAssertTrue((120...450).contains(palavras), "\(topico) tem \(palavras) palavras")
        }
    }

    func testAtalhosCitadosNaAjudaBatemComOsDaBarraLateral() throws {
        for area in WorkspaceTab.allCases {
            let doc = try XCTUnwrap(HelpLibrary.load(area.rawValue, in: pastaAjuda))
            let texto = doc.plainText
            for outra in WorkspaceTab.allCases where texto.contains("**\(outra.displayName)** (⌘") {
                XCTAssertTrue(texto.contains("**\(outra.displayName)** (⌘\(outra.shortcutDigit))"),
                              "\(area.rawValue): atalho de \(outra.displayName) diverge")
            }
        }
    }

    func testParserReconheceOSubconjuntoERecusaOResto() {
        let doc = HelpDocument.parse("""
        ---
        area: x
        titulo: Teste
        resumo: R
        ---

        ## O que é

        Parágrafo em
        duas linhas.

        - item **um**
        - item `dois`

        1. primeiro
        2. segundo

        > Dica: não precisa de aparelho.

        ```
        python -m mobaile.web
        ```

        | tabela | não |
        ### nível três não
        """)
        XCTAssertEqual(doc.title, "Teste")
        XCTAssertEqual(doc.blocks, [
            .heading("O que é"),
            .paragraph("Parágrafo em duas linhas."),
            .bullets(["item **um**", "item `dois`"]),
            .steps(["primeiro", "segundo"]),
            .note(.tip, "Dica: não precisa de aparelho."),
            .code("python -m mobaile.web"),
        ])
        XCTAssertEqual(doc.unsupported.count, 2)
    }

    func testLinkInternoDaAjudaViraTopico() throws {
        XCTAssertEqual(HelpLibrary.topic(from: try XCTUnwrap(URL(string: "mobaile://ajuda/relatar-problema"))), "relatar-problema")
        XCTAssertNil(HelpLibrary.topic(from: try XCTUnwrap(URL(string: "mobaile://ajuda/nao-existe"))))
        XCTAssertNil(HelpLibrary.topic(from: try XCTUnwrap(URL(string: "https://ajuda/report"))))
    }

    func testEmpacotamentoLevaAAjudaParaOApp() throws {
        let script = try String(contentsOf: raiz.appendingPathComponent("tools/package_macos_app.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("docs/ajuda"), "package_macos_app.sh precisa copiar docs/ajuda para Contents/Resources/ajuda")
    }

    // MARK: - Beta

    func testAvisoBetaUmaVezPorVersaoMaior() {
        let d = UserDefaults(suiteName: "mobaile.testes.\(UUID().uuidString)")!
        XCTAssertEqual(BetaNotice.major("3.23.0"), "3")
        XCTAssertEqual(BetaNotice.major(nil), "dev")
        XCTAssertTrue(BetaNotice.shouldShow(version: "3.23.0", defaults: d))
        BetaNotice.markSeen(version: "3.23.0", defaults: d)
        XCTAssertFalse(BetaNotice.shouldShow(version: "3.24.0", defaults: d), "3.23 → 3.24 não mostra de novo")
        XCTAssertTrue(BetaNotice.shouldShow(version: "4.0.0", defaults: d), "versão maior nova mostra")
    }

    func testTestesNaoVeemOAvisoBeta() {
        XCTAssertFalse(AppState().betaNoticeEnabled)
        XCTAssertTrue(AppState.atLaunch().betaNoticeEnabled)
    }

    func testSobreDizQueEBetaETemBugs() {
        let texto = AboutPanel.credits(commit: "abcdef1234")
        XCTAssertTrue(texto.contains("beta"))
        XCTAssertTrue(texto.contains("bugs"))
        XCTAssertTrue(texto.contains("abcdef1"))
        XCTAssertFalse(texto.contains("abcdef12"), "commit curto")
    }

    // MARK: - Relatar um Problema

    private let env = BugReport.Environment(appVersion: "3.24.0", commit: "abc1234", macOS: "macOS 26.1.0",
                                            macModel: "Mac14,2, Apple Silicon", device: "Pixel 7")

    func testValidaTituloEOQueAconteceu() {
        var d = BugReport.Draft()
        XCTAssertEqual(d.validationErrors().map(\.0), [.title, .happened])
        d.title = String(repeating: "a", count: 121)
        d.happened = "Travou"
        XCTAssertEqual(d.validationErrors().map(\.0), [.title])
        XCTAssertTrue(d.validationErrors()[0].1.contains("121"))
        d.title = "A Rede HTTP fica vazia"
        XCTAssertTrue(d.validationErrors().isEmpty)
    }

    func testDadosDoAmbienteSoEntramSeMarcados() {
        var d = BugReport.Draft(title: "t", area: .network, happened: "vazio")
        let sem = d.markdown(env)
        for dado in ["3.24.0", "macOS", "Mac14,2", "Pixel 7"] { XCTAssertFalse(sem.contains(dado), dado) }
        XCTAssertTrue(sem.contains("### Área\nRede HTTP"))
        XCTAssertTrue(sem.contains("### O que eu fiz\nNão informado"))

        d.includeVersion = true
        d.includeMac = true
        d.includeDevice = true
        let com = d.markdown(env)
        XCTAssertTrue(com.contains("- Mo baile 3.24.0 (commit abc1234)"))
        XCTAssertTrue(com.contains("- macOS 26.1.0"))
        XCTAssertTrue(com.contains("- Mac14,2, Apple Silicon"))
        XCTAssertTrue(com.contains("- Aparelho: Pixel 7"))
    }

    func testURLDaIssueUsaOsIdsDoFormularioECodificaTudo() throws {
        let d = BugReport.Draft(title: "C++ & proxy = vazio", area: .network, didWhat: "1. abri", expected: "ver", happened: "a+b?")
        let (url, cortou) = d.issueURL(env)
        XCTAssertFalse(cortou)
        let texto = url.absoluteString
        XCTAssertTrue(texto.hasPrefix("https://github.com/francisco-efjr/mo-baile/issues/new?template=bug-app.yml&title="))
        XCTAssertTrue(texto.contains("C%2B%2B%20%26%20proxy%20%3D%20vazio"), texto)
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let itens = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(itens["title"], "[bug] C++ & proxy = vazio")
        XCTAssertEqual(itens["aconteceu"], "a+b?")
        XCTAssertEqual(itens["area"], "Rede HTTP")
        XCTAssertNil(itens["ambiente"], "sem dados marcados, o campo não vai")

        // Os ids usados na URL existem no formulário bug-app.yml.
        let form = try String(contentsOf: raiz.appendingPathComponent(".github/ISSUE_TEMPLATE/bug-app.yml"), encoding: .utf8)
        for id in ["aconteceu", "fez", "esperava", "area", "ambiente", "anexos"] {
            XCTAssertTrue(form.contains("id: \(id)"), "bug-app.yml sem o campo \(id)")
        }
    }

    func testRelatoLongoECortadoECopiado() {
        let d = BugReport.Draft(title: "longo", happened: String(repeating: "texto ", count: 3_000))
        let (url, cortou) = d.issueURL(env)
        XCTAssertTrue(cortou)
        XCTAssertLessThanOrEqual(url.absoluteString.count, BugReport.maxURLLength)
    }

    func testCorteContaOTamanhoCodificadoComAcentoEEmoji() {
        let pesado = String(repeating: "ação “ok” 🚀 ", count: 400)
        let d = BugReport.Draft(title: String(repeating: "é", count: 120), area: .report,
                                didWhat: pesado, expected: pesado, happened: pesado)
        let (url, cortou) = d.issueURL(env)
        XCTAssertTrue(cortou)
        XCTAssertLessThanOrEqual(url.absoluteString.count, BugReport.maxURLLength)
    }

    func testAnexosRespeitamTipoTamanhoQuantidadeEDuplicados() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("relato-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }
        func arquivo(_ nome: String, bytes: Int = 10, cabecalho: [UInt8] = []) throws -> URL {
            let url = pasta.appendingPathComponent(nome)
            try (Data(cabecalho) + Data(count: bytes)).write(to: url)
            return url
        }
        let assinaturaPNG: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

        var lista: [BugReport.Attachment] = []
        let png = try arquivo("tela.png", cabecalho: assinaturaPNG)
        guard case .success(let a) = BugReport.validate(png, against: lista) else { return XCTFail("png aceito") }
        lista.append(a)
        XCTAssertEqual(BugReport.validate(png, against: lista), .failure(.duplicate("tela.png")))
        try FileManager.default.createDirectory(at: pasta.appendingPathComponent("outra"), withIntermediateDirectories: true)
        let mesmoNome = try arquivo("outra/Tela.PNG", cabecalho: assinaturaPNG)
        XCTAssertEqual(BugReport.validate(mesmoNome, against: lista), .failure(.duplicate("Tela.PNG")),
                       "mesmo nome em outra pasta, só com maiúsculas diferentes, colidiria na pasta do relato")
        XCTAssertEqual(BugReport.validate(try arquivo("programa.png"), against: lista), .failure(.type("programa.png")),
                       "extensão de imagem sem assinatura de PNG")
        let executavel = try arquivo("captura.jpg", cabecalho: [0xFF, 0xD8, 0xFF])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executavel.path)
        XCTAssertEqual(BugReport.validate(executavel, against: lista), .failure(.executable("captura.jpg")))
        XCTAssertEqual(BugReport.validate(try arquivo("x.sh"), against: lista), .failure(.executable("x.sh")))
        XCTAssertEqual(BugReport.validate(try arquivo("x.docx"), against: lista), .failure(.type("x.docx")))
        XCTAssertEqual(BugReport.validate(pasta.appendingPathComponent("sumiu.log"), against: lista), .failure(.unreadable("sumiu.log")))
        let grande = try arquivo("grande.mp4", bytes: Int(BugReport.Limits.bytesPerFile) + 1)
        if case .failure(.tooLarge(let nome, _)) = BugReport.validate(grande, against: lista) {
            XCTAssertEqual(nome, "grande.mp4")
        } else { XCTFail("arquivo grande recusado") }

        let cinco = try (1...5).map { try BugReport.Attachment(url: arquivo("\($0).txt"), size: 1) }
        XCTAssertEqual(BugReport.validate(try arquivo("sexto.txt"), against: cinco), .failure(.count))
    }

    func testPastaDoRelatoTemOTextoEAsCopias() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("relatos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let anexo = base.appendingPathComponent("origem/log.txt")
        try FileManager.default.createDirectory(at: anexo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "linha".write(to: anexo, atomically: true, encoding: .utf8)

        let d = BugReport.Draft(title: "Falha", happened: "quebrou", attachments: [BugReport.Attachment(url: anexo, size: 5)])
        let pasta = try BugReport.saveFolder(d, env: env, base: base, now: Date(timeIntervalSince1970: 0))
        let relato = try String(contentsOf: pasta.appendingPathComponent("relato.md"), encoding: .utf8)
        XCTAssertTrue(relato.hasPrefix("# Falha"))
        XCTAssertTrue(relato.contains("### Anexos\n- log.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pasta.appendingPathComponent("log.txt").path))
    }

    func testModeloComecaNaAreaAtivaEGuardaORascunho() {
        let m = BugReportModel()
        m.prepare(area: .analytics, device: nil)
        XCTAssertEqual(m.draft.area, .analytics)
        m.draft.title = "rascunho"
        m.prepare(area: .report, device: "Pixel 7")
        XCTAssertEqual(m.draft.area, .analytics, "rascunho em andamento não muda de área")
        XCTAssertEqual(m.device, "Pixel 7")
        XCTAssertEqual(m.validate(), .happened)
        m.reset()
        XCTAssertTrue(m.draft.isEmpty)
    }
}
