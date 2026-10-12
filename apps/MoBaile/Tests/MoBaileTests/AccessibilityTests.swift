import XCTest
import SwiftUI
import AppKit
@testable import MoBaile

/// Confere o que o leitor de tela recebe de cada tela, lendo a árvore de
/// acessibilidade do próprio macOS (ver `AccessibilityInspector`).
///
/// Cada teste nomeia o defeito que cobre. Os rótulos esperados estão em
/// português porque é o que a pessoa ouve.
@MainActor
final class AccessibilityTests: XCTestCase {

    // MARK: - Ambiente

    private func elemento(
        _ classe: String, id: String = "", texto: String = "", desc: String = "",
        pai: Int? = nil, bounds: CGRect = CGRect(x: 10, y: 10, width: 100, height: 100)
    ) -> UIElement {
        UIElement(
            tag: classe, className: classe, resourceId: id, text: texto, contentDesc: desc,
            clickable: true, bounds: bounds, area: Int(bounds.width * bounds.height),
            package: "com.app", platform: .android, depth: 0, parentIndex: pai
        )
    }

    private func ambiente() -> (AppState, EngineSession, ThemeManager) {
        let estado = AppState()
        estado.selectedDevice = "7303D258"
        estado.availableDevices = [(id: "7303D258", name: "Pixel 7")]
        estado.platform = .android
        estado.hierarchyElements = [
            elemento("android.widget.FrameLayout", bounds: CGRect(x: 0, y: 0, width: 1080, height: 2400)),
            elemento("android.widget.Button", id: "com.app:id/btn_comprar", texto: "Comprar", pai: 0),
        ]
        estado.selectedElement = estado.hierarchyElements[1]
        estado.httpRequests = [
            NetworkEvent(id: 1, timestamp: Date(), timeStr: "10:00", method: "GET", url: "https://a.com/x",
                         host: "a.com", path: "/x", statusCode: 200, statusText: "OK", requestHeaders: [:],
                         requestBody: "", responseHeaders: [:], responseBody: "{}", durationMs: 12,
                         protocol: "HTTP/1.1", isTunnel: false),
            NetworkEvent(id: 2, timestamp: Date(), timeStr: "10:01", method: "POST", url: "https://a.com/y",
                         host: "a.com", path: "/y", statusCode: 500, statusText: "ERR", requestHeaders: [:],
                         requestBody: "x", responseHeaders: [:], responseBody: "", durationMs: 30,
                         protocol: "HTTP/1.1", isTunnel: false),
        ]
        estado.selectedRequest = estado.httpRequests[0]
        estado.analyticsEvents = [
            AnalyticsEvent(id: 1, timestamp: Date(), timeStr: "10:00:00", tag: "FA", eventName: "screen_view",
                           params: ["a": "1"], rawLog: "raw", platform: .android),
        ]
        estado.selectedAnalyticsEvent = estado.analyticsEvents[0]
        estado.actionsCode = "def x():\n    pass\n"
        estado.locatorsCode = "A = 1\n"
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        return (estado, sessao, ThemeManager())
    }

    private func arvore<V: View>(
        _ view: V, largura: CGFloat = 900, altura: CGFloat = 600,
        ajuste: (AppState) -> Void = { _ in }
    ) throws -> AXNode {
        let (estado, sessao, tema) = ambiente()
        ajuste(estado)
        return try AccessibilityInspector.arvore(
            de: view.environment(estado).environment(sessao).environment(tema),
            largura: largura, altura: altura
        )
    }

    // MARK: - Segmentos

    /// Defeito: o nome aplicado ao seletor segmentado era herdado por cada
    /// segmento, e o leitor anunciava o nome do grupo várias vezes sem dizer
    /// qual era qual. Vale para a estratégia de seletor e o modo do clique.
    func testSegmentosDaEstrategiaTemNomeProprio() throws {
        let ax = try arvore(PageObjectsView(), largura: 900, altura: 400)
        let rotulos = ax.all.map(\.label)
        for esperado in ["Auto", "ID", "XPath", "Coords"] {
            XCTAssertTrue(rotulos.contains(esperado), "segmento \(esperado) sem nome próprio: \(rotulos)")
        }
        XCTAssertNotNil(ax.node(label: "Estratégia de seletor"), "o grupo perdeu o nome\n\(ax.dump)")
    }

    // MARK: - Botões só com ícone

    /// Defeito: na coluna estreita os botões da barra do workspace perdiam o
    /// texto. O leitor anunciava o nome do símbolo ("rectangle.split.2x1"), um
    /// número solto ("0") e o nome padrão do ícone.
    func testBarraDoWorkspaceEstreitaNaoAnunciaNomeDeSimbolo() throws {
        let ax = try arvore(PageObjectsView(), largura: 440, altura: 300)
        let rotulos = ax.buttons.map(\.label)

        XCTAssertFalse(rotulos.contains("rectangle.split.2x1"), "nome de símbolo vazou: \(rotulos)")
        XCTAssertFalse(rotulos.contains("0"), "contador sem contexto: \(rotulos)")
        XCTAssertTrue(rotulos.contains("Estrutura do fluxo"), "falta Estrutura: \(rotulos)")
        XCTAssertTrue(rotulos.contains("Lado a lado"), "falta Lado a lado: \(rotulos)")
    }

    /// Defeito: "Split" é um interruptor, mas o leitor não dizia se estava ligado.
    func testBotaoLadoALadoInformaEstado() throws {
        let ligado = try arvore(PageObjectsView(), largura: 1100, altura: 300) { $0.splitEditors = true }
        let desligado = try arvore(PageObjectsView(), largura: 1100, altura: 300) { $0.splitEditors = false }

        XCTAssertEqual(ligado.node(label: "Lado a lado")?.value, "ligado", ligado.dump)
        XCTAssertEqual(desligado.node(label: "Lado a lado")?.value, "desligado", desligado.dump)
    }

    // MARK: - Editores

    /// Defeito: os cabeçalhos dos dois editores diziam "Mover, pages, /, Código
    /// Incorporado, feature.py" (descrições automáticas dos ícones), e os
    /// botões Copiar/Salvar/Limpar eram idênticos nos dois lados.
    func testEditoresTemCabecalhoLegivelEBotoesDistintos() throws {
        let ax = try arvore(DualEditorPane()) { $0.splitEditors = true }

        XCTAssertNil(ax.node(label: "Mover"), "ícone decorativo anunciado como 'Mover'\n\(ax.dump)")
        XCTAssertNil(ax.node(label: "Código Incorporado"), "ícone decorativo anunciado\n\(ax.dump)")

        // Salvar e Limpar agem sobre os dois arquivos, então repetir o rótulo é
        // honesto. "Copiar" age só sobre o editor do cabeçalho: tem de dizer qual.
        let rotulos = ax.buttons.map(\.label)
        XCTAssertFalse(rotulos.contains("Copiar"), "botão Copiar sem dizer o que copia: \(rotulos)")
        XCTAssertTrue(rotulos.contains("Copiar código das ações"), "\(rotulos)")
        XCTAssertTrue(rotulos.contains("Copiar localizadores"), "\(rotulos)")
    }

    /// Defeito: as duas áreas de código eram anunciadas apenas como "área de
    /// texto", sem dizer qual era qual.
    func testAreasDeCodigoTemNome() throws {
        let ax = try arvore(DualEditorPane()) { $0.splitEditors = true }
        let areas = ax.all.filter { $0.role == "AXTextArea" }

        XCTAssertEqual(areas.count, 2, ax.dump)
        XCTAssertEqual(Set(areas.map(\.label)).count, 2, "áreas de código sem nomes distintos\n\(ax.dump)")
        XCTAssertFalse(areas.contains { $0.label.isEmpty }, ax.dump)
    }

    // MARK: - Tabelas e filtros

    /// Todo o texto que o leitor encontra dentro de um nó (linha da tabela).
    private func texto(_ no: AXNode) -> String {
        no.all.map { "\($0.label) \($0.value)" }.joined(separator: " ")
    }

    /// Defeito: cada célula da tabela HTTP era um texto solto ("GET", "200",
    /// "a.com"...) e a linha selecionada só se distinguia pela cor. A tabela
    /// agora é a do sistema: cada requisição é uma linha (AXRow) com estado de
    /// seleção, e a primeira célula lê a requisição inteira.
    func testLinhaDaTabelaHTTPEUmElementoComEstadoDeSelecao() throws {
        let ax = try arvore(HTTPTableView(), largura: 900, altura: 300)
        let linhas = ax.all.filter { $0.role == "AXRow" }
        let linha = linhas.first { texto($0).contains("GET") && texto($0).contains("a.com") }

        XCTAssertNotNil(linha, "linha da requisição não virou uma linha da tabela\n\(ax.dump)")
        XCTAssertEqual(linha?.isSelected, true, ax.dump)
        let outra = linhas.first { texto($0).contains("POST") }
        XCTAssertEqual(outra?.isSelected, false, ax.dump)
        XCTAssertTrue(linha.map(texto)?.contains("status 200") == true, "falta o status: \(linha.map(texto) ?? "-")")
    }

    func testLinhaDeAnalyticsEUmElementoComEstadoDeSelecao() throws {
        let ax = try arvore(AnalyticsInspectorView(), largura: 1100, altura: 700)
        let linha = ax.all.first { $0.role == "AXRow" && texto($0).contains("screen_view") }

        XCTAssertNotNil(linha, ax.dump)
        XCTAssertEqual(linha?.isSelected, true, ax.dump)
    }

    /// Defeito: os campos de busca não tinham nome (só o texto-sugestão, que
    /// some ao digitar) e a lupa era anunciada como imagem. O filtro de Rede e
    /// Analytics virou a busca nativa da toolbar; o campo que sobra no conteúdo
    /// é o da hierarquia.
    func testCampoDeBuscaDaHierarquiaTemNome() throws {
        let ax = try arvore(InspectorPane(), largura: 300, altura: 700)
        let campos = ax.all.filter { $0.role == "AXTextField" }
        XCTAssertFalse(campos.isEmpty, "sem campo\n\(ax.dump)")
        XCTAssertTrue(campos.contains { $0.label == "Buscar na hierarquia" }, "campo de busca sem nome\n\(ax.dump)")
        XCTAssertNil(ax.node(label: "Lupa"), "ícone decorativo anunciado\n\(ax.dump)")
    }

    /// Defeito: o "Copiar tudo" dos atributos não fazia nada. Agora copia, e
    /// os chips de tipo dizem o que são.
    func testInspectorNomeiaChipsEAtributos() throws {
        let ax = try arvore(InspectorPane(), largura: 300, altura: 700)
        XCTAssertNotNil(ax.node(label: "Copiar Tudo"), ax.dump)
        XCTAssertTrue(ax.all.contains { $0.label.contains("Botão") }, "chip de tipo sem nome\n\(ax.dump)")
    }

    /// Defeito: os botões "Copiar" de Request e Response eram idênticos.
    func testBotoesCopiarDeRequisicaoEResposta() throws {
        let ax = try arvore(HTTPInspectorView(), largura: 1100, altura: 700)
        let rotulos = ax.buttons.map(\.label)

        XCTAssertTrue(rotulos.contains("Copiar requisição"), "\(rotulos)")
        XCTAssertTrue(rotulos.contains("Copiar resposta"), "\(rotulos)")
    }

    // MARK: - Espelho

    /// Defeito: o espelho era anunciado como elemento "desconhecido".
    func testEspelhoTemPapelEDizOModoDoClique() throws {
        let ax = try arvore(MirrorColumn(), largura: 400, altura: 780) {
            $0.interactionMode = .record
            $0.currentFrame = NSImage(size: NSSize(width: 10, height: 20))
        }
        let espelho = ax.node(label: "Espelho do dispositivo")

        XCTAssertNotNil(espelho, ax.dump)
        XCTAssertNotEqual(espelho?.role, "AXUnknown", ax.dump)
        XCTAssertTrue(espelho?.value.contains("Gravar passo") == true, "o modo do clique não é dito: \(espelho?.value ?? "-")")
    }
}
