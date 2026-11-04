import XCTest
import AppKit
@testable import MoBaile

/// Correções da revisão das abas da árvore Projeto (R-01 a R-08).
@MainActor
final class ArquivosAbertosTests: XCTestCase {

    private func lido(_ caminho: String, _ texto: String, mtime: Int = 100) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "path": caminho, "text": texto, "encoding": "UTF-8", "line_separator": "LF",
            "bom": false, "read_only": false, "size": texto.utf8.count, "mtime_ns": mtime,
        ])
    }

    private func ambiente(erros: [String: EngineError] = [:]) throws -> (AppState, EngineSession, FakeEngine) {
        let estado = AppState()
        let motor = FakeEngine(respostas: [
            "workspace.read": try lido("flows/a.yaml", "a: 1\n"),
            "workspace.write": try JSONSerialization.data(withJSONObject: [
                "path": "flows/a.yaml", "saved": true, "bytes": 5, "mtime_ns": 200,
            ]),
        ], erros: erros)
        return (estado, EngineSession(state: estado, client: motor), motor)
    }

    /// R-01: as abas moram no AppState, e não na view que some ao trocar de área.
    func testAbasSobrevivemATrocaDeArea() async throws {
        let (estado, sessao, _) = try ambiente()
        await estado.abrirArquivo("flows/a.yaml", sessao: sessao)
        estado.arquivosAbertos[0].texto = "a: 2\n"
        estado.workspaceTab = .network
        estado.workspaceTab = .pageObjects
        XCTAssertEqual(estado.arquivoAtivo, "flows/a.yaml")
        XCTAssertEqual(estado.arquivosAbertos.first?.texto, "a: 2\n")
        XCTAssertTrue(estado.arquivosAbertos[0].sujo)
    }

    /// R-08: dois ↩ rápidos no mesmo arquivo abrem uma aba só.
    func testAbrirDuasVezesAoMesmoTempoAbreUmaAba() async throws {
        let (estado, sessao, motor) = try ambiente()
        await motor.reter("workspace.read")
        async let primeiro: Void = estado.abrirArquivo("flows/a.yaml", sessao: sessao)
        async let segundo: Void = estado.abrirArquivo("flows/a.yaml", sessao: sessao)
        while await motor.quantasRetidas("workspace.read") < 2 { await Task.yield() }
        await motor.liberar("workspace.read")
        _ = await (primeiro, segundo)
        XCTAssertEqual(estado.arquivosAbertos.count, 1)
    }

    /// R-07: fechar a aba durante a gravação não derruba nem suja outra aba.
    func testFecharDuranteAGravacaoNaoQuebra() async throws {
        let (estado, sessao, motor) = try ambiente()
        await estado.abrirArquivo("flows/a.yaml", sessao: sessao)
        estado.arquivosAbertos[0].texto = "a: 2\n"
        await motor.reter("workspace.write")
        async let salvo = estado.salvarArquivo("flows/a.yaml", sessao: sessao)
        while await motor.quantasRetidas("workspace.write") < 1 { await Task.yield() }
        estado.fecharArquivo("flows/a.yaml")
        await motor.liberar("workspace.write")
        _ = await salvo
        XCTAssertTrue(estado.arquivosAbertos.isEmpty)
    }

    /// R-04: o write leva o mtime lido; depois de salvar, a aba fica limpa com o mtime novo.
    func testSalvarMandaOMtimeLidoEAtualiza() async throws {
        let (estado, sessao, motor) = try ambiente()
        await estado.abrirArquivo("flows/a.yaml", sessao: sessao)
        estado.arquivosAbertos[0].texto = "a: 2\n"
        let ok = await estado.salvarArquivo("flows/a.yaml", sessao: sessao)
        XCTAssertTrue(ok)
        let params = await motor.parametros(de: "workspace.write")
        XCTAssertEqual(params?["expected_mtime_ns"], .int(100))
        XCTAssertFalse(estado.arquivosAbertos[0].sujo)
        XCTAssertEqual(estado.arquivosAbertos[0].arquivo.mtimeNs, 200)
    }

    func testConflitoMarcaAAbaESobrescreverNaoMandaOMtime() async throws {
        let (estado, sessao, motor) = try ambiente(erros: ["workspace.write": .engine(code: "file_changed", message: "mudou")])
        await estado.abrirArquivo("flows/a.yaml", sessao: sessao)
        estado.arquivosAbertos[0].texto = "a: 2\n"
        let ok = await estado.salvarArquivo("flows/a.yaml", sessao: sessao)
        XCTAssertFalse(ok)
        XCTAssertEqual(estado.conflitoDeArquivo, "flows/a.yaml")
        XCTAssertTrue(estado.arquivosAbertos[0].sujo, "a edição continua na aba")
        _ = await estado.salvarArquivo("flows/a.yaml", sessao: sessao, sobrescrever: true)
        let params = await motor.parametros(de: "workspace.write")
        XCTAssertNil(params?["expected_mtime_ns"])
    }

    func testRecarregarDescartaAEdicaoELimpaOConflito() async throws {
        let (estado, sessao, _) = try ambiente()
        await estado.abrirArquivo("flows/a.yaml", sessao: sessao)
        estado.arquivosAbertos[0].texto = "a: 2\n"
        estado.conflitoDeArquivo = "flows/a.yaml"
        await estado.recarregarArquivo("flows/a.yaml", sessao: sessao)
        XCTAssertEqual(estado.arquivosAbertos[0].texto, "a: 1\n")
        XCTAssertNil(estado.conflitoDeArquivo)
    }

    // MARK: - R-05: ⌘S contextual

    func testCommandSSalvaAAbaDaFrenteOuOPageObject() {
        var c = CommandContext()
        c.hasCode = true
        XCTAssertEqual(CommandRegistry.command(.save, in: c)?.title, "Salvar Page Object")
        c.openFileTab = "flows/a.yaml"
        c.openFileDirty = true
        XCTAssertEqual(CommandRegistry.command(.save, in: c)?.title, "Salvar flows/a.yaml")
        XCTAssertNil(CommandRegistry.command(.save, in: c)?.disabledReason)
        XCTAssertEqual(CommandRegistry.command(.save, in: c)?.shortcut, .cmd("s"))
        c.openFileDirty = false
        XCTAssertNotNil(CommandRegistry.command(.save, in: c)?.disabledReason, "nada a salvar na aba")
    }

    // MARK: - R-06: realce incremental com docstring

    private func editor(_ texto: String) -> IDEEditorContainerView {
        let container = IDEEditorContainerView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        container.textView.esquema = .pycharm(escuro: true, altoContraste: false)
        container.textView.typingAttributes = EditorFont.atributos(EditorFont.fonte(), cor: container.textView.esquema!.texto)
        container.carregar(texto)
        return container
    }

    private func cor(_ c: IDEEditorContainerView, _ indice: Int) -> NSColor? {
        c.armazenamento.attribute(.foregroundColor, at: indice, effectiveRange: nil) as? NSColor
    }

    func testDigitarDentroDaDocstringMantemACorEFecharAspasRecoloreOResto() {
        let codigo = "\"\"\"Doc\n\nmais\"\"\"\ndef f(self):\n    return 1\n"
        let c = editor(codigo)
        let tv = c.textView
        let esquema = tv.esquema!
        // Dentro da docstring, numa linha do meio.
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(cor(c, 6), esquema.docstring)
        XCTAssertEqual(cor(c, (tv.string as NSString).range(of: "def").location), esquema.palavraChave)
        // Apagar as aspas de fechamento abre a docstring até o fim do arquivo.
        let fechamento = (tv.string as NSString).range(of: "\"\"\"", options: .backwards)
        tv.setSelectedRange(fechamento)
        tv.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(cor(c, (tv.string as NSString).range(of: "def").location), esquema.docstring)
    }

    func testContadorIncrementalBateComAContagemCompleta() {
        let c = editor((1...300).map { "linha \($0)" }.joined(separator: "\n"))
        let tv = c.textView
        for posicao in [0, 500, 1200, 30, 2000, 1999, 7] {
            tv.setSelectedRange(NSRange(location: posicao, length: 0))
            XCTAssertEqual(tv.linhaEColunaDoCursor().linha,
                           EditorText.linhaEColuna(em: tv.string as NSString, posicao: posicao).linha, "posição \(posicao)")
        }
        tv.setSelectedRange(NSRange(location: 10, length: 0))
        tv.insertText("\n\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        tv.setSelectedRange(NSRange(location: 1500, length: 0))
        XCTAssertEqual(tv.linhaEColunaDoCursor().linha, EditorText.linhaEColuna(em: tv.string as NSString, posicao: 1500).linha)
        XCTAssertEqual(tv.totalDeLinhas, 302)
    }
}
