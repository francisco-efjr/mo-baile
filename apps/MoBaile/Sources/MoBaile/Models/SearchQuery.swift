import Foundation

/// Busca da toolbar em Rede, Analytics e Relatório.
///
/// Cada palavra digitada precisa aparecer em algum campo, sem diferenciar
/// maiúsculas nem acentos, como na busca do Finder e do Mail: "simulacao 422"
/// acha a requisição de simulação que voltou 422.
///
/// Desde a 3.6 a busca entende tokens `chave:valor`, como o Console.app:
/// `status:4xx método:POST host:api tipo:json` na Rede, `evento:screen_view
/// param:item_id=42 origem:FA` em Analytics. Uma chave desconhecida vira
/// palavra comum ("a:b" procura "a:b"). O que não é token continua valendo
/// para todos os campos.
struct SearchQuery: Equatable, Sendable {
    enum Key: String, CaseIterable, Sendable {
        case status, method, host, type, event, param, origin

        /// Nomes aceitos em português e inglês, já sem acento e em minúsculas.
        var aliases: [String] {
            switch self {
            case .status: return ["status"]
            case .method: return ["metodo", "method", "verbo"]
            case .host: return ["host", "dominio", "domain"]
            case .type: return ["tipo", "type"]
            case .event: return ["evento", "event"]
            case .param: return ["param", "parametro", "parameter"]
            case .origin: return ["origem", "origin", "tag"]
            }
        }

        static func named(_ nome: String) -> Key? {
            let chave = nome.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            return allCases.first { $0.aliases.contains(chave) }
        }
    }

    struct Filter: Equatable, Sendable {
        let key: Key
        let value: String
        /// O token como foi digitado (`evento:login`), para áreas sem filtro.
        let text: String
    }

    let terms: [String]
    let filters: [Filter]

    init(_ text: String) {
        var terms: [String] = []
        var filters: [Filter] = []
        for parte in text.split(whereSeparator: \.isWhitespace) {
            let palavra = String(parte)
            if let dois = palavra.firstIndex(of: ":"), dois > palavra.startIndex {
                let chave = String(palavra[..<dois])
                let valor = String(palavra[palavra.index(after: dois)...])
                if let key = Key.named(chave), !valor.isEmpty {
                    filters.append(Filter(key: key, value: valor, text: palavra))
                    continue
                }
            }
            terms.append(palavra)
        }
        self.terms = terms
        self.filters = filters
    }

    var isEmpty: Bool { terms.isEmpty && filters.isEmpty }

    /// As palavras livres contra os campos.
    func matches(_ fields: [String]) -> Bool {
        terms.allSatisfy { termo in
            fields.contains { Self.contains($0, termo) }
        }
    }

    /// Para áreas sem filtros próprios (Relatório): um token `chave:valor`
    /// vale como texto literal, em vez de ser ignorado e mostrar tudo.
    func matchesLiteral(_ fields: [String]) -> Bool {
        let literais = terms + filters.map(\.text)
        return literais.allSatisfy { termo in
            fields.contains { Self.contains($0, termo) }
        }
    }

    func matches(_ event: NetworkEvent) -> Bool {
        filters.allSatisfy { filtro in
            switch filtro.key {
            case .status: return Self.statusMatches(event.statusCode, filtro.value)
            case .method: return Self.same(event.method, filtro.value)
            case .host: return Self.contains(event.host, filtro.value)
            case .type: return Self.contentTypeMatches(event, filtro.value)
            case .event, .param, .origin: return false
            }
        } && matches(event.searchableFields)
    }

    func matches(_ event: AnalyticsEvent) -> Bool {
        filters.allSatisfy { filtro in
            switch filtro.key {
            case .event: return Self.contains(event.eventName, filtro.value)
            case .origin: return Self.contains(event.tag, filtro.value)
            case .param:
                // `omittingEmptySubsequences: false`: "param:=42" tem chave vazia e
                // `partes[0]` num array vazio derrubava o app no meio da digitação.
                let partes = filtro.value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    .map(String.init)
                guard let chave = partes.first, !chave.isEmpty else { return false }
                // "param:chave=" (valor vazio) vale como "a chave existe".
                let esperado = partes.count > 1 ? partes[1] : ""
                return event.params.contains { nome, valor in
                    guard Self.contains(nome, chave) else { return false }
                    return esperado.isEmpty || Self.contains(valor, esperado)
                }
            case .status, .method, .host, .type: return false
            }
        } && matches(event.searchableFields)
    }

    // MARK: - Critérios

    static func contains(_ campo: String, _ termo: String) -> Bool {
        campo.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// `4xx` casa a centena; `422` casa o número; `erro` casa 400 em diante.
    static func statusMatches(_ status: Int?, _ valor: String) -> Bool {
        guard let status else { return false }
        let v = valor.lowercased()
        if v == "erro" || v == "error" { return status >= 400 }
        if v.hasSuffix("xx"), let centena = Int(v.dropLast(2)) { return status / 100 == centena }
        if let n = Int(v) { return status == n }
        return false
    }

    static func contentTypeMatches(_ event: NetworkEvent, _ valor: String) -> Bool {
        let tipo = event.contentType.lowercased()
        switch valor.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased() {
        case "json": return tipo.contains("json")
        case "xml": return tipo.contains("xml")
        case "html": return tipo.contains("html")
        case "form": return tipo.contains("form")
        case "imagem", "image": return tipo.hasPrefix("image/")
        case "video": return tipo.hasPrefix("video/")
        case "fonte", "font": return tipo.contains("font")
        case "texto", "text": return tipo.hasPrefix("text/")
        default: return tipo.contains(valor.lowercased())
        }
    }

    /// Sugestões mostradas no campo de busca de cada área.
    static let networkSuggestions = ["status:4xx", "status:5xx", "metodo:POST", "host:", "tipo:json"]
    static let analyticsSuggestions = ["evento:screen_view", "param:", "origem:FA"]
}

/// Escopo da tabela de Rede, acima dela: o JSON da API deixa de dividir a
/// lista com imagens e telemetria.
enum NetworkScope: String, CaseIterable, Identifiable, Sendable {
    case all, api, media, errors, slow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .api: return "API"
        case .media: return "Mídia"
        case .errors: return "Erros"
        case .slow: return "Lentas"
        }
    }

    var help: String {
        switch self {
        case .all: return "Todas as requisições"
        case .api: return "JSON, XML e formulários"
        case .media: return "Imagens, vídeo e fontes"
        case .errors: return "Status 4xx e 5xx, ou erro de conexão"
        case .slow: return "Mais de 1 segundo"
        }
    }

    func includes(_ event: NetworkEvent) -> Bool {
        let tipo = event.contentType.lowercased()
        switch self {
        case .all: return true
        case .api: return tipo.contains("json") || tipo.contains("xml") || tipo.contains("form")
        case .media: return tipo.hasPrefix("image/") || tipo.hasPrefix("video/") || tipo.contains("font")
        case .errors: return (event.statusCode ?? 0) >= 400 || event.error != nil
        case .slow: return (event.durationMs ?? 0) > 1000
        }
    }
}

extension NetworkEvent {
    /// Tudo o que a busca da Rede olha: linha de requisição, status, headers
    /// (nome e valor) e os dois corpos, já redigidos pelo motor.
    var searchableFields: [String] {
        var campos = [method, url, host, path, statusText, `protocol`, timeStr, requestBody, responseBody]
        if let statusCode { campos.append(String(statusCode)) }
        if let error { campos.append(error) }
        campos += requestHeaders.map { "\($0.key): \($0.value)" }
        campos += responseHeaders.map { "\($0.key): \($0.value)" }
        return campos
    }

    /// `Content-Type` da resposta ou, sem ele, do pedido; sem diferenciar
    /// maiúsculas no nome do header.
    var contentType: String {
        func acha(_ headers: [String: String]) -> String? {
            headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
        }
        return acha(responseHeaders) ?? acha(requestHeaders) ?? ""
    }
}

extension AnalyticsEvent {
    /// Tudo o que a busca de Analytics olha: nome, origem, horário, cada
    /// parâmetro como "chave: valor" e o log bruto do SDK.
    var searchableFields: [String] {
        [eventName, tag, timeStr, rawLog, platform.displayName]
            + params.map { "\($0.key): \($0.value)" }
    }
}
