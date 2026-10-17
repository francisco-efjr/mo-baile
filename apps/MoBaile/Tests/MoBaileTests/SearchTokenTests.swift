import XCTest
@testable import MoBaile

/// F12: tokens `chave:valor` na busca, escopo da Rede e a combinação dos dois.
@MainActor
final class SearchTokenTests: XCTestCase {

    private func requisicao(_ id: Int, metodo: String = "GET", url: String, status: Int? = 200,
                            tipo: String = "application/json", duracao: Int? = 120, erro: String? = nil) -> NetworkEvent {
        let componentes = URLComponents(string: url)
        return NetworkEvent(
            id: id, timestamp: Date(), timeStr: "13:02:1\(id)", method: metodo, url: url,
            host: componentes?.host ?? "", path: componentes?.path ?? "", statusCode: status, statusText: "",
            requestHeaders: [:], requestBody: "", responseHeaders: ["content-type": tipo],
            responseBody: "{}", durationMs: duracao, protocol: "HTTP/1.1", isTunnel: false, error: erro
        )
    }

    private func evento(_ id: Int, _ nome: String, _ params: [String: String], tag: String = "FA") -> AnalyticsEvent {
        AnalyticsEvent(id: id, timestamp: Date(), timeStr: "10:00:0\(id)", tag: tag, eventName: nome,
                       params: params, rawLog: "", platform: .android)
    }

    private func rede() -> [NetworkEvent] {
        [
            requisicao(1, url: "https://api.demoapp.test/v2/clientes/me", status: 200),
            requisicao(2, metodo: "POST", url: "https://api.demoapp.test/v2/pedido", status: 422),
            requisicao(3, url: "https://cdn.demoapp.test/logo.png", status: 200, tipo: "image/png", duracao: 40),
            requisicao(4, url: "https://api.demoapp.test/v2/lento", status: 500, duracao: 2400),
            requisicao(5, url: "https://api.demoapp.test/v2/caiu", status: nil, duracao: nil, erro: "ConnectionResetError"),
        ]
    }

    // MARK: - Parsing

    func testTokenConhecidoViraFiltroEDesconhecidoViraPalavra() {
        let q = SearchQuery("status:4xx método:POST a:b pedido")
        XCTAssertEqual(q.filters.map(\.key), [.status, .method])
        XCTAssertEqual(q.terms, ["a:b", "pedido"])
    }

    func testChaveSemValorNaoViraFiltro() {
        let q = SearchQuery("status:")
        XCTAssertTrue(q.filters.isEmpty)
        XCTAssertEqual(q.terms, ["status:"])
    }

    // MARK: - Rede

    func testStatusPorCentenaENumero() {
        let r = rede()
        XCTAssertEqual(r.filter { SearchQuery("status:4xx").matches($0) }.map(\.id), [2])
        XCTAssertEqual(r.filter { SearchQuery("status:500").matches($0) }.map(\.id), [4])
        XCTAssertEqual(r.filter { SearchQuery("status:erro").matches($0) }.map(\.id), [2, 4])
    }

    func testMetodoHostETipo() {
        let r = rede()
        XCTAssertEqual(r.filter { SearchQuery("metodo:post").matches($0) }.map(\.id), [2])
        XCTAssertEqual(r.filter { SearchQuery("host:cdn").matches($0) }.map(\.id), [3])
        XCTAssertEqual(r.filter { SearchQuery("tipo:imagem").matches($0) }.map(\.id), [3])
        XCTAssertEqual(r.filter { SearchQuery("tipo:json").matches($0) }.count, 4)
    }

    func testTokenEPalavraLivreSeCombinam() {
        let r = rede()
        XCTAssertEqual(r.filter { SearchQuery("status:2xx clientes").matches($0) }.map(\.id), [1])
    }

    func testEscopoDaRede() {
        let r = rede()
        XCTAssertEqual(r.filter { NetworkScope.api.includes($0) }.map(\.id), [1, 2, 4, 5])
        XCTAssertEqual(r.filter { NetworkScope.media.includes($0) }.map(\.id), [3])
        XCTAssertEqual(r.filter { NetworkScope.errors.includes($0) }.map(\.id), [2, 4, 5])
        XCTAssertEqual(r.filter { NetworkScope.slow.includes($0) }.map(\.id), [4])
    }

    func testEstadoCombinaEscopoEBusca() {
        let estado = AppState()
        estado.httpRequests = rede()
        estado.networkScope = .errors
        estado.httpFilterText = "metodo:GET"
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [5, 4])
        estado.networkScope = .all
        estado.httpFilterText = ""
        XCTAssertEqual(estado.filteredHTTPRequests.count, 5)
    }

    // MARK: - Analytics

    func testEventoParamEOrigem() {
        let eventos = [
            evento(1, "screen_view", ["ga_screen": "home"]),
            evento(2, "select_item", ["item_id": "42", "item_name": "Tênis"], tag: "FA-SVC"),
            evento(3, "screen_view", ["ga_screen": "pedido"]),
        ]
        XCTAssertEqual(eventos.filter { SearchQuery("evento:screen").matches($0) }.map(\.id), [1, 3])
        XCTAssertEqual(eventos.filter { SearchQuery("param:item_id").matches($0) }.map(\.id), [2])
        XCTAssertEqual(eventos.filter { SearchQuery("param:ga_screen=pedido").matches($0) }.map(\.id), [3])
        XCTAssertEqual(eventos.filter { SearchQuery("origem:svc").matches($0) }.map(\.id), [2])
        XCTAssertEqual(eventos.filter { SearchQuery("parametro:item_name=tenis").matches($0) }.map(\.id), [2])
    }

    func testParamComChaveVaziaNaoDerrubaNemCasa() {
        // REV-1: "param:=42" aparece no meio da digitação e derrubava o app.
        let eventos = [evento(1, "select_item", ["item_id": "42"])]
        XCTAssertTrue(eventos.filter { SearchQuery("param:=").matches($0) }.isEmpty)
        XCTAssertTrue(eventos.filter { SearchQuery("param:=42").matches($0) }.isEmpty)
        XCTAssertEqual(eventos.filter { SearchQuery("param:item_id=").matches($0) }.map(\.id), [1])
    }

    func testRelatorioTrataTokenComoTextoLiteral() {
        // REV-9: no Relatório não há filtros; "evento:login" procura o texto, não mostra tudo.
        let q = SearchQuery("evento:login")
        XCTAssertFalse(q.isEmpty)
        XCTAssertTrue(q.matchesLiteral(["evento:login na tela"]))
        XCTAssertFalse(q.matchesLiteral(["login"]))
        XCTAssertTrue(SearchQuery("login").matchesLiteral(["evento:login"]))
    }

    func testFiltroDeRedeNaoCasaEmAnalyticsNemOContrario() {
        XCTAssertFalse(SearchQuery("status:200").matches(evento(1, "x", [:])))
        XCTAssertFalse(SearchQuery("evento:x").matches(requisicao(1, url: "https://a.test/x")))
    }
}
