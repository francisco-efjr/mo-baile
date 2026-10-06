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

    /// Defeito: o `.accessibilityLabel("Plataforma")` aplicado ao seletor
    /// segmentado era herdado por cada segmento. O leitor anunciava "Plataforma,
    /// botão" duas vezes e a pessoa não tinha como saber qual era iOS e qual
    /// era Android. O mesmo valia para aba do workspace, estratégia e modo do clique.
    func testSegmentosDoSeletorTemNomeProprio() throws {
        let (estado, sessao, tema) = ambiente()
        var indice = 0
        let seletor = SegmentedControl(items: ["iOS", "Android"], selectedIndex: Binding(get: { indice }, set: { indice = $0 }))
            .accessibilityLabel("Plataforma")
            .environment(estado).environment(sessao).environment(tema)
        let ax = try AccessibilityInspector.arvore(de: seletor, largura: 300, altura: 60)

        let rotulos = ax.buttons.map(\.label)
        XCTAssertTrue(rotulos.contains("iOS"), "segmento iOS sem nome próprio: \(rotulos)")
        XCTAssertTrue(rotulos.contains("Android"), "segmento Android sem nome próprio: \(rotulos)")
        XCTAssertNotNil(ax.node(label: "Plataforma"), "o grupo perdeu o nome do seletor\n\(ax.dump)")
    }

    /// Defeito: o segmento escolhido só era distinguido pela cor/sombra.
    func testSegmentoEscolhidoEExpostoComoSelecionado() throws {
        let (estado, sessao, tema) = ambiente()
        var indice = 1
        let seletor = SegmentedControl(items: ["iOS", "Android"], selectedIndex: Binding(get: { indice }, set: { indice = $0 }))
            .environment(estado).environment(sessao).environment(tema)
        let ax = try AccessibilityInspector.arvore(de: seletor, largura: 300, altura: 60)

        XCTAssertEqual(ax.node(label: "Android")?.isSelected, true, ax.dump)
        XCTAssertEqual(ax.node(label: "iOS")?.isSelected, false, ax.dump)
    }

    func testBarraSuperiorNomeiaPlataformaEModoDoClique() throws {
        let ax = try arvore(UnifiedToolbar(), largura: 1500, altura: 60)
        let rotulos = ax.buttons.map(\.label)
        for esperado in ["iOS", "Android", "Repassar toque", "Gravar passo"] {
            XCTAssertTrue(rotulos.contains(esperado), "falta '\(esperado)' na barra: \(rotulos)")
        }
        // O nome do grupo do modo de clique ficava sem acento.
        XCTAssertNotNil(ax.node(label: "Ação do clique no espelho"), ax.dump)
    }

    // MARK: - Botões só com ícone

    /// Defeito: na coluna estreita os botões da barra do workspace perdiam o
    /// texto. O leitor anunciava o nome do símbolo ("rectangle.split.2x1"), um
    /// número solto ("0") e o nome padrão do play ("Reproduzir").
    func testBarraDoWorkspaceEstreitaNaoAnunciaNomeDeSimbolo() throws {
        let ax = try arvore(WorkspaceTabBar(), largura: 440, altura: 120)
        let rotulos = ax.buttons.map(\.label)

        XCTAssertFalse(rotulos.contains("rectangle.split.2x1"), "nome de símbolo vazou: \(rotulos)")
        XCTAssertFalse(rotulos.contains("0"), "contador sem contexto: \(rotulos)")
        XCTAssertFalse(rotulos.contains("Reproduzir"), "rótulo genérico do ícone: \(rotulos)")
        XCTAssertTrue(rotulos.contains(where: { $0.hasPrefix("Estrutura") }), "falta Estrutura: \(rotulos)")
        XCTAssertTrue(rotulos.contains("Dividir editores"), "falta Dividir editores: \(rotulos)")
        XCTAssertTrue(rotulos.contains("Rodar fluxo"), "falta Rodar fluxo: \(rotulos)")
    }

    /// Defeito: "Split" é um interruptor, mas o leitor não dizia se estava ligado.
    func testBotaoDividirEditoresInformaEstado() throws {
        let ligado = try arvore(WorkspaceTabBar(), largura: 1100, altura: 60) { $0.splitEditors = true }
        let desligado = try arvore(WorkspaceTabBar(), largura: 1100, altura: 60) { $0.splitEditors = false }

        XCTAssertEqual(ligado.node(label: "Dividir editores")?.value, "ligado", ligado.dump)
        XCTAssertEqual(desligado.node(label: "Dividir editores")?.value, "desligado", desligado.dump)
    }

    // MARK: - Editores

    /// Defeito: os cabeçalhos dos dois editores diziam "Mover, pages, /, Código
    /// Incorporado, feature.py" (descrições automáticas dos ícones), e os
    /// botões Copiar/Salvar/Limpar eram idênticos nos dois lados.
    func testEditoresTemCabecalhoLegivelEBotoesDistintos() throws {
        let ax = try arvore(DualEditorPane())

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
        let ax = try arvore(DualEditorPane())
        let areas = ax.all.filter { $0.role == "AXTextArea" }

        XCTAssertEqual(areas.count, 2, ax.dump)
        XCTAssertEqual(Set(areas.map(\.label)).count, 2, "áreas de código sem nomes distintos\n\(ax.dump)")
        XCTAssertFalse(areas.contains { $0.label.isEmpty }, ax.dump)
    }

    // MARK: - Tabelas e filtros

    /// Defeito: cada célula da tabela HTTP era um texto solto ("GET", "200",
    /// "a.com"...) e a linha selecionada só se distinguia pela cor.
    func testLinhaDaTabelaHTTPEUmElementoComEstadoDeSelecao() throws {
        let ax = try arvore(HTTPTableView(), largura: 900, altura: 300)
        let linha = ax.all.first { $0.label.contains("GET") && $0.label.contains("a.com") }

        XCTAssertNotNil(linha, "linha da requisição não virou um elemento único\n\(ax.dump)")
        XCTAssertEqual(linha?.isSelected, true, ax.dump)
        let outra = ax.all.first { $0.label.contains("POST") && $0.label.contains("a.com") }
        XCTAssertEqual(outra?.isSelected, false, ax.dump)
        XCTAssertTrue(linha?.label.contains("200") == true, "falta o status: \(linha?.label ?? "-")")
    }

    func testLinhaDeAnalyticsEUmElementoComEstadoDeSelecao() throws {
        let ax = try arvore(AnalyticsInspectorView(), largura: 1100, altura: 700)
        let linha = ax.all.first { $0.label.contains("screen_view") }

        XCTAssertNotNil(linha, ax.dump)
        XCTAssertEqual(linha?.isSelected, true, ax.dump)
    }

    /// Defeito: os campos de filtro de rede e analytics não tinham nome (só o
    /// texto-sugestão, que some ao digitar) e a lupa/filtro eram anunciados
    /// como imagem "Filtro".
    func testCamposDeFiltroTemNome() throws {
        for (nome, view) in [
            ("rede", AnyView(HTTPInspectorView())),
            ("analytics", AnyView(AnalyticsInspectorView())),
        ] {
            let ax = try arvore(view, largura: 1100, altura: 700)
            let campos = ax.all.filter { $0.role == "AXTextField" }
            XCTAssertFalse(campos.isEmpty, "\(nome): sem campo\n\(ax.dump)")
            XCTAssertFalse(campos.contains { $0.label.isEmpty }, "\(nome): campo de filtro sem nome\n\(ax.dump)")
            XCTAssertNil(ax.node(label: "Filtro"), "\(nome): ícone decorativo anunciado\n\(ax.dump)")
        }
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
