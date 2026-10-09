import Foundation

/// Busca da toolbar em Rede, Analytics e Relatório.
///
/// Procurava só no nome do evento (Analytics) ou em host, path e status (Rede).
/// Quem depura tagueamento procura pelo valor ("app:credito:home", um
/// `item_id`, um trecho do log); quem depura rede procura por um header, um
/// campo do corpo ou a query da URL. Agora qualquer dado capturado entra.
///
/// Cada palavra digitada precisa aparecer em algum campo, sem diferenciar
/// maiúsculas nem acentos, como na busca do Finder e do Mail: "simulacao 422"
/// acha a requisição de simulação que voltou 422.
struct SearchQuery: Equatable, Sendable {
    let terms: [String]

    init(_ text: String) {
        terms = text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var isEmpty: Bool { terms.isEmpty }

    func matches(_ fields: [String]) -> Bool {
        terms.allSatisfy { termo in
            fields.contains { $0.range(of: termo, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
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
}

extension AnalyticsEvent {
    /// Tudo o que a busca de Analytics olha: nome, origem, horário, cada
    /// parâmetro como "chave: valor" e o log bruto do SDK.
    var searchableFields: [String] {
        [eventName, tag, timeStr, rawLog, platform.displayName]
            + params.map { "\($0.key): \($0.value)" }
    }
}
