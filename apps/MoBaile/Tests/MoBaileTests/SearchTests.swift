import XCTest
@testable import MoBaile

/// Busca da toolbar: qualquer dado capturado entra, não só o nome.
///
/// Defeito que cobre: em Analytics a busca olhava só o nome do evento e a tag,
/// e em Rede só host, path, método e status. Procurar "app:credito:home" (um
/// valor de parâmetro) ou um header não achava nada.
@MainActor
final class SearchTests: XCTestCase {

    private func requisicao(_ id: Int, metodo: String = "POST", url: String, status: Int? = 201,
                            headers: [String: String] = [:], corpo: String = "", resposta: String = "") -> NetworkEvent {
        let componentes = URLComponents(string: url)
        return NetworkEvent(
            id: id, timestamp: Date(), timeStr: "13:02:1\(id)", method: metodo, url: url,
            host: componentes?.host ?? "", path: componentes?.path ?? "", statusCode: status, statusText: "",
            requestHeaders: headers, requestBody: corpo, responseHeaders: ["Content-Type": "application/json"],
            responseBody: resposta, durationMs: 100, protocol: "HTTP/1.1", isTunnel: false
        )
    }

    private func evento(_ id: Int, _ nome: String, _ params: [String: String], raw: String = "") -> AnalyticsEvent {
        AnalyticsEvent(id: id, timestamp: Date(), timeStr: "10:00:0\(id)", tag: "FA-SVC", eventName: nome,
                       params: params, rawLog: raw, platform: .android)
    }

    private func estadoDeRede() -> AppState {
        let estado = AppState()
        estado.httpRequests = [
            requisicao(1, metodo: "GET", url: "https://api.banco.com.br/v2/clientes/me?canal=app_ios", status: 200,
                       headers: ["X-Request-Id": "req-7f3a"], resposta: #"{"nome": "Ana"}"#),
            requisicao(2, url: "https://api.banco.com.br/v2/credito/simulacao", status: 422,
                       headers: ["Content-Type": "application/json"], corpo: #"{"valor": 5000}"#,
                       resposta: #"{"erro": "limite_excedido"}"#),
        ]
        return estado
    }

    // MARK: - Rede

    func testRedeAchaPorValorDeHeader() {
        let estado = estadoDeRede()
        estado.httpFilterText = "req-7f3a"
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [1])
    }

    func testRedeAchaPorCampoDoCorpoEPorQueryDaURL() {
        let estado = estadoDeRede()
        estado.httpFilterText = "limite_excedido"
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [2], "corpo da resposta")
        estado.httpFilterText = "canal=app_ios"
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [1], "query da URL")
    }

    func testRedeExigeTodasAsPalavrasEmQualquerCampo() {
        let estado = estadoDeRede()
        estado.httpFilterText = "simulacao 422"
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [2])
        estado.httpFilterText = "simulacao 200"
        XCTAssertTrue(estado.filteredHTTPRequests.isEmpty)
    }

    func testBuscaIgnoraMaiusculasEAcentos() {
        let estado = estadoDeRede()
        estado.httpFilterText = "SIMULAÇÃO"
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [2])
    }

    func testBuscaSoComEspacosMostraTudo() {
        let estado = estadoDeRede()
        estado.httpFilterText = "   "
        XCTAssertEqual(estado.filteredHTTPRequests.map(\.id), [2, 1])
    }

    // MARK: - Analytics

    func testAnalyticsAchaPorValorDeParametro() {
        let estado = AppState()
        estado.analyticsEvents = [
            evento(1, "screen_view", ["ga_screen": "app:credito:home", "flow_name": "credito"]),
            evento(2, "interaction", ["detail": "click:parcelas", "component": "button"]),
        ]
        estado.analyticsFilterText = "app:credito:home"
        XCTAssertEqual(estado.filteredAnalyticsEvents.map(\.id), [1])
        estado.analyticsFilterText = "click:parcelas"
        XCTAssertEqual(estado.filteredAnalyticsEvents.map(\.id), [2])
    }

    func testAnalyticsAchaPorChaveEPeloLogBruto() {
        let estado = AppState()
        estado.analyticsEvents = [
            evento(1, "add_to_cart", ["items": #"[{"item_id": "14063"}]"#],
                   raw: "10-08 10:04:00.000 V/FA-SVC: Logging event: origin=app,name=add_to_cart"),
            evento(2, "screen_view", ["ga_screen": "app:home"]),
        ]
        estado.analyticsFilterText = "14063"
        XCTAssertEqual(estado.filteredAnalyticsEvents.map(\.id), [1], "valor dentro de items")
        estado.analyticsFilterText = "ga_screen"
        XCTAssertEqual(estado.filteredAnalyticsEvents.map(\.id), [2], "nome do parâmetro")
        estado.analyticsFilterText = "origin=app"
        XCTAssertEqual(estado.filteredAnalyticsEvents.map(\.id), [1], "trecho do log bruto")
    }

    func testBuscaPorNomeContinuaFuncionando() {
        let estado = AppState()
        estado.analyticsEvents = [evento(1, "screen_view", [:]), evento(2, "purchase", [:])]
        estado.analyticsFilterText = "purchase"
        XCTAssertEqual(estado.filteredAnalyticsEvents.map(\.id), [2])
    }
}
