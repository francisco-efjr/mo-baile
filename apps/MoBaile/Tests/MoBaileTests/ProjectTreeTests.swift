import XCTest
import SwiftUI
@testable import MoBaile

/// PO-5: árvore Projeto. Contrato `workspace.*` decodificado das fixtures do
/// motor e o comportamento da tool window Project do PyCharm (expandir e
/// recolher tudo, localizar arquivo aberto, speed search).
final class ProjectTreeTests: XCTestCase {

    private func resultado<T: Decodable>(_ nome: String, _ tipo: T.Type) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine_payloads", withExtension: "json"))
        let raiz = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let resposta = try XCTUnwrap(raiz[nome] as? [String: Any], "fixture ausente: \(nome)")
        let dados = try JSONSerialization.data(withJSONObject: try XCTUnwrap(resposta["result"]))
        return try JSONDecoder().decode(tipo, from: dados)
    }

    // MARK: - Contrato

    func testContratoDaArvore() throws {
        let arvore = try resultado("workspace.tree", EngineDTO.WorkspaceTree.self)
        XCTAssertEqual(arvore.name, "Mo baile")
        XCTAssertTrue(arvore.exists)
        XCTAssertEqual(arvore.nodes.map(\.name), ["flows", "pages"])
        XCTAssertEqual(arvore.nodes[1].children?.first?.path, "pages/feature.py")
        XCTAssertEqual(arvore.nodes[1].children?.first?.isDirectory, false)
    }

    func testContratoDeLerEGravar() throws {
        let lido = try resultado("workspace.read", EngineDTO.WorkspaceFile.self)
        XCTAssertEqual(lido.text, "def tocar(self):\n    pass\n")
        XCTAssertEqual(lido.lineSeparator, "CRLF")
        XCTAssertFalse(lido.readOnly)
        let gravado = try resultado("workspace.write", EngineDTO.WorkspaceWrite.self)
        XCTAssertTrue(gravado.saved)
    }

    // MARK: - Modelo

    private func modelo() throws -> ProjetoModelo {
        let m = ProjetoModelo()
        m.receber(try resultado("workspace.tree", EngineDTO.WorkspaceTree.self))
        return m
    }

    func testAbreComAsPastasDePrimeiroNivelExpandidas() throws {
        XCTAssertEqual(try modelo().linhas.map(\.id), ["flows", "flows/login.yaml", "pages", "pages/feature.py"])
    }

    func testRecolherEExpandirTudo() throws {
        let m = try modelo()
        m.recolherTudo()
        XCTAssertEqual(m.linhas.map(\.id), ["flows", "pages"])
        m.expandirTudo()
        XCTAssertEqual(m.linhas.count, 4)
    }

    func testLocalizarArquivoAbertoAbreAsPastasESeleciona() throws {
        let m = try modelo()
        m.recolherTudo()
        m.revelar("pages/feature.py")
        XCTAssertEqual(m.selecionado, "pages/feature.py")
        XCTAssertTrue(m.linhas.contains { $0.id == "pages/feature.py" })
    }

    /// Digitar "feat" com foco na árvore seleciona `feature.py` (aceite P1-1).
    func testSpeedSearchSelecionaOPrimeiroQueCasaEPassaEntreEles() throws {
        let m = try modelo()
        for letra in ["f", "e", "a", "t"] { m.digitar(letra) }
        XCTAssertEqual(m.selecionado, "pages/feature.py")
        XCTAssertNotNil(m.casa("feature.py"))
        XCTAssertNil(m.casa("login.yaml"))

        m.busca = ""
        m.digitar("s")  // flows e pages
        XCTAssertEqual(m.selecionado, "flows")
        m.proximoQueCasa(paraBaixo: true)
        XCTAssertEqual(m.selecionado, "pages")
        m.proximoQueCasa(paraBaixo: true)
        XCTAssertEqual(m.selecionado, "flows", "volta ao primeiro, como no PyCharm")
    }

    // MARK: - Editor vazio

    /// As dicas mostram os atalhos reais do Mo baile (D-2), lidos do registro.
    func testDicasDoEditorVazioUsamOsAtalhosDoRegistro() {
        XCTAssertEqual(DicasDoEditorVazio.atalho(.palette), "⇧⌘P")
        XCTAssertEqual(DicasDoEditorVazio.atalho(.stream), "⌘E")
        XCTAssertEqual(DicasDoEditorVazio.atalho(.save), "⌘S")
        XCTAssertEqual(DicasDoEditorVazio.atalho(.projectTree), "paleta ⇧⌘P", "⌘1 é Page Objects: sem atalho próprio")
    }

    func testComandoDaPaletaAlternaOProjeto() {
        var c = CommandContext()
        XCTAssertEqual(CommandRegistry.command(.projectTree, in: c)?.title, "Ocultar Projeto")
        c.projectTreeVisible = false
        XCTAssertEqual(CommandRegistry.command(.projectTree, in: c)?.title, "Mostrar Projeto")
        XCTAssertNil(CommandRegistry.command(.projectTree, in: c)?.shortcut)
    }
}
