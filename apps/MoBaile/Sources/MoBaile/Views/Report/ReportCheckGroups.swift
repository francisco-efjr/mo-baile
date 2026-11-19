import Foundation

/// Campo de item da auditoria: `items[3].item_id|item_name` → item 3, chave
/// `item_id|item_name`. Desde a 3.27.0 o motor confere todos os itens, e a
/// lista plana de conferências chegava a dezenas de linhas (RE-01).
enum ReportItemField {
    static func split(_ field: String) -> (item: Int, key: String)? {
        guard let m = field.wholeMatch(of: #/items\[(\d+)\]\.(.+)/#), let i = Int(m.1) else { return nil }
        return (i, String(m.2))
    }

    /// `item_id|item_name` → ["item_id", "item_name"]; chave simples → [chave].
    static func alternatives(_ key: String) -> [String] {
        key.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// O obtido de uma chave com alternativas vem como `item_name=Tee`: devolve
    /// o valor e a chave que atendeu. `nil` quando não está nesse formato.
    static func viaAlternative(key: String, obtained: String?) -> (value: String, via: String)? {
        let alternativas = alternatives(key)
        guard alternativas.count > 1, let obtained, let igual = obtained.firstIndex(of: "=") else { return nil }
        let chave = String(obtained[..<igual])
        guard alternativas.contains(chave) else { return nil }
        return (String(obtained[obtained.index(after: igual)...]), chave)
    }

    /// Para o leitor de tela: `|` vira " ou ".
    static func spoken(_ key: String) -> String {
        key.replacingOccurrences(of: "|", with: " ou ")
    }
}

/// Conferências de um grupo: os parâmetros do evento ou um item.
struct ReportCheckGroup: Identifiable {
    /// "evento" ou "items[3]".
    let id: String
    /// `nil` no grupo do evento; a posição do item, a partir de 0.
    let item: Int?
    let checks: [ReportCheck]
    /// O que identifica o item: item_id ou item_name obtido.
    let identification: String?

    var divergent: Int { checks.filter { $0.exported && !$0.ok }.count }

    /// Chave como aparece dentro do grupo: no item, sem o `items[i].`.
    func shortKey(_ check: ReportCheck) -> String {
        guard item != nil, let partes = ReportItemField.split(check.field) else { return check.field }
        return partes.key
    }
}

extension ReportResult {
    /// Os parâmetros do evento primeiro, depois um grupo por item, na ordem.
    var checkGroups: [ReportCheckGroup] {
        var doEvento: [ReportCheck] = []
        var porItem: [Int: [ReportCheck]] = [:]
        for check in checks {
            if let (i, _) = ReportItemField.split(check.field) {
                porItem[i, default: []].append(check)
            } else {
                doEvento.append(check)
            }
        }
        let itensDoDisparo = matchedItems
        var grupos: [ReportCheckGroup] = []
        if !doEvento.isEmpty {
            grupos.append(ReportCheckGroup(id: "evento", item: nil, checks: doEvento, identification: nil))
        }
        for i in porItem.keys.sorted() {
            let doItem = porItem[i] ?? []
            grupos.append(ReportCheckGroup(
                id: "items[\(i)]", item: i, checks: doItem,
                identification: Self.identification(doItem, disparo: itensDoDisparo.indices.contains(i) ? itensDoDisparo[i] : nil)
            ))
        }
        return grupos
    }

    /// Os itens do disparo avaliado, cada um como chave e valor em texto.
    var matchedItems: [[String: String]] {
        guard let texto = matched?.params["items"],
              let valor = try? JSONDecoder().decode(JSONValue.self, from: Data(texto.utf8)),
              case .array(let lista) = valor else { return [] }
        return lista.compactMap { item in
            guard case .object(let campos) = item else { return nil }
            return campos.mapValues(\.displayText)
        }
    }

    private static func identification(_ checks: [ReportCheck], disparo: [String: String]?) -> String? {
        for check in checks {
            guard let (_, chave) = ReportItemField.split(check.field), let obtido = check.obtained, !obtido.isEmpty else { continue }
            if let via = ReportItemField.viaAlternative(key: chave, obtained: obtido) { return via.value }
            if chave == "item_id" || chave == "item_name" { return obtido }
        }
        return disparo?["item_id"] ?? disparo?["item_name"]
    }

    /// "value · items: 3 itens · +2 anteriores": o que diverge, curto, para a
    /// coluna Divergências (RE-04). O texto inteiro continua no tooltip.
    var divergenceSummary: String {
        switch status {
        case .missing: return "Não disparado no log"
        case .ok: return ""
        default: break
        }
        var nomes: [String] = []
        var itens = Set<Int>()
        for falha in checks where falha.exported && !falha.ok {
            if let (i, _) = ReportItemField.split(falha.field) { itens.insert(i) } else { nomes.append(falha.field) }
        }
        if !itens.isEmpty { nomes.append(itens.count == 1 ? "items: 1 item" : "items: \(itens.count) itens") }
        if olderDivergent > 0 { nomes.append("+\(olderDivergent) anteriores") }
        return nomes.isEmpty ? divergences : nomes.joined(separator: " · ")
    }

    /// Tooltip da coluna Divergências: as 4 primeiras, uma por linha.
    var divergenceTooltip: String {
        let falhas = checks.filter { $0.exported && !$0.ok }
        guard !falhas.isEmpty else { return divergences }
        var linhas = falhas.prefix(4).map { "\($0.field): obtido \($0.obtained ?? "ausente"), esperado \($0.expected)" }
        if falhas.count > 4 { linhas.append("e mais \(falhas.count - 4) no painel Validação") }
        return linhas.joined(separator: "\n")
    }
}

extension ReportMatchedEvent {
    /// Ordem das chaves de um item no Disparo: as que identificam e dão o
    /// valor primeiro, depois as outras em ordem alfabética.
    static func itemRows(_ item: [String: String]) -> [(key: String, value: String)] {
        let primeiro = ["item_id", "item_name", "price", "quantity"]
        let comecam = primeiro.compactMap { chave in item[chave].map { (key: chave, value: $0) } }
        let resto = item.filter { !primeiro.contains($0.key) }.sorted { $0.key < $1.key }.map { (key: $0.key, value: $0.value) }
        return comecam + resto
    }
}
