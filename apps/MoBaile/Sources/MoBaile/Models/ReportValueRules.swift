import Foundation

/// As regras de valor da spec (`engine/.../report/rules.py`), para o editor:
/// o menu Inserir Regra, a ajuda Regras dos Valores e o aviso de regra que não
/// existe. A conferência de verdade é do motor; aqui é só o que ajuda a digitar.
enum ReportValueRules {
    struct Rule: Identifiable, Sendable {
        /// Texto do menu, em maiúsculas de título como pede a HIG.
        let title: String
        let token: String
        let example: String
        let checks: String
        /// Como o menu aplica a regra ao valor que já está no campo.
        let apply: @Sendable (String) -> String
        var id: String { token }
    }

    /// Regras que valem para o valor inteiro, sem `|`.
    static let wholeValueTokens = ["preenchido", "numero", "data", "soma_itens"]

    static let rules: [Rule] = [
        Rule(title: "Qualquer Valor", token: "[preenchido]", example: "[preenchido]",
             checks: "o valor existe e não está vazio", apply: { _ in "[preenchido]" }),
        Rule(title: "Número", token: "[numero]", example: "[numero]",
             checks: "um número, como 12 ou 30.5", apply: { _ in "[numero]" }),
        Rule(title: "Data dd/mm/aaaa", token: "[data]", example: "[data]",
             checks: "uma data, como 19/11/2026", apply: { _ in "[data]" }),
        Rule(title: "Um dos Valores", token: "[a|b]", example: "[avulso|empresa]",
             checks: "um dos valores entre colchetes; vale também no meio do texto",
             apply: { atual in atual.isEmpty ? "[opção1|opção2]" : "[\(atual)|opção2]" }),
        Rule(title: "Expressão Regular", token: "re:", example: "re:^[A-Z]{3}$",
             checks: "a expressão regular inteira (ex.: moeda ISO 4217)",
             apply: { atual in atual.hasPrefix("re:") ? atual : "re:" + atual }),
        Rule(title: "Chave do Fluxo", token: "{fluxo}", example: "app:{fluxo}:home",
             checks: "troca pelo nome de cada fluxo da spec", apply: { atual in atual + "{fluxo}" }),
        Rule(title: "Soma de price × quantity", token: "[soma_itens]", example: "[soma_itens]",
             checks: "no value: a soma de price × quantity dos itens, sem frete nem imposto",
             apply: { _ in "[soma_itens]" }),
    ]

    /// Chaves: `item_id|item_name` aceita qualquer uma das duas.
    static let keyAlternativeHelp = "Chave a|b: basta uma das chaves atender (ex.: item_id|item_name)."

    /// A primeira regra `[palavra]` que não existe, com a sugestão mais
    /// parecida. Valor `re:` fica de fora: colchete ali é da expressão.
    static func unknownToken(in value: String) -> (token: String, suggestion: String?)? {
        guard !value.hasPrefix("re:") else { return nil }
        for match in value.matches(of: #/\[([A-Za-z_]+)\]/#) {
            let palavra = String(match.1)
            if wholeValueTokens.contains(palavra) { continue }
            let sugestao = wholeValueTokens
                .map { ($0, distance(palavra.lowercased(), $0)) }
                .filter { $0.1 <= 2 }
                .min { $0.1 < $1.1 }?.0
            return ("[\(palavra)]", sugestao.map { "[\($0)]" })
        }
        return nil
    }

    /// Distância de edição (Levenshtein): quantas letras trocar para chegar lá.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var anterior = Array(0...b.count)
        for i in 1...a.count {
            var atual = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                atual[j] = min(anterior[j] + 1, atual[j - 1] + 1, anterior[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            anterior = atual
        }
        return anterior[b.count]
    }
}

extension ReportCardDraft.Field {
    /// Linha sem chave e sem valor: sai ao gravar e não conta como problema.
    var isBlank: Bool {
        key.trimmingCharacters(in: .whitespaces).isEmpty && value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Nome para leitor de tela e tooltip: `item_id|item_name` vira "item_id ou item_name".
    func spokenName(position: Int) -> String {
        let chave = key.trimmingCharacters(in: .whitespaces)
        return chave.isEmpty ? "parâmetro \(position + 1) sem nome" : chave.replacingOccurrences(of: "|", with: " ou ")
    }
}

/// Problemas de uma linha chave e valor, cada um no seu campo.
struct ReportRowIssue: Equatable, Sendable {
    var key: FieldIssue?
    var value: FieldIssue?

    var blocking: Bool { key?.blocking == true || value?.blocking == true }
    var messages: [FieldIssue] { [key, value].compactMap { $0 } }
}

/// Problemas do card, por campo (RE-02). O `problems` deriva daqui.
struct ReportCardIssues: Equatable, Sendable {
    var evento: FieldIssue?
    var rows: [UUID: ReportRowIssue] = [:]
    /// Nome do grupo de cada linha ("Parâmetros", "Variação 2"), na ordem do card.
    var order: [(id: UUID, group: String)] = []

    static func == (lhs: ReportCardIssues, rhs: ReportCardIssues) -> Bool {
        lhs.evento == rhs.evento && lhs.rows == rhs.rows && lhs.order.map(\.id) == rhs.order.map(\.id)
    }

    var blockingCount: Int {
        (evento?.blocking == true ? 1 : 0) + rows.values.filter(\.blocking).count
    }

    /// A primeira linha com erro, na ordem do card.
    var firstBlockingRow: UUID? {
        order.first { rows[$0.id]?.blocking == true }?.id
    }
}

extension ReportCardDraft {
    func issues() -> ReportCardIssues {
        var resultado = ReportCardIssues()
        if evento.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resultado.evento = FieldIssue(message: "Informe o evento (ex.: purchase).")
        }
        let grupos = [("Parâmetros", "nos parâmetros", params)]
            + variacoes.enumerated().map { ("Variação \($0.offset + 1)", "nesta variação", $0.element.fields) }
        for (grupo, onde, campos) in grupos {
            var vistos: Set<String> = []
            for campo in campos {
                resultado.order.append((campo.id, grupo))
                guard !campo.isBlank else { continue }
                var linha = ReportRowIssue()
                let chave = campo.key.trimmingCharacters(in: .whitespaces)
                if chave.isEmpty {
                    linha.key = FieldIssue(message: "Dê um nome ao parâmetro ou remova a linha.")
                } else if !vistos.insert(chave).inserted {
                    linha.key = FieldIssue(message: "\(chave) já aparece \(onde). Renomeie ou remova uma das linhas.")
                } else if chave.split(separator: "|", omittingEmptySubsequences: false).contains(where: {
                    $0.trimmingCharacters(in: .whitespaces).isEmpty
                }) {
                    linha.key = FieldIssue(
                        message: "Falta uma chave de um dos lados da barra (ex.: item_id|item_name).", blocking: false
                    )
                }
                linha.value = Self.valueIssue(campo, chave: chave)
                if linha.key != nil || linha.value != nil { resultado.rows[campo.id] = linha }
            }
        }
        return resultado
    }

    private static func valueIssue(_ campo: Field, chave: String) -> FieldIssue? {
        let nome = chave.isEmpty ? "O valor" : chave
        if campo.isJSON {
            guard (try? JSONDecoder().decode(JSONValue.self, from: Data(campo.value.utf8))) != nil else {
                return FieldIssue(message: "\(nome) não é um JSON válido. Abra o editor de JSON para ver onde.")
            }
            if campo.value.contains("[soma_itens]") {
                return FieldIssue(message: "[soma_itens] só vale nos parâmetros do evento, não dentro de \(nome).",
                                  blocking: false)
            }
        }
        if let (token, sugestao) = ReportValueRules.unknownToken(in: campo.value) {
            let dica = sugestao.map { " Quis dizer \($0)?" } ?? ""
            return FieldIssue(message: "\(token) não é uma regra e vai ser comparado como texto.\(dica)", blocking: false)
        }
        return nil
    }
}
