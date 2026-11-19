import Foundation
import SwiftUI

/// Resumo de um valor JSON numa linha: o que a célula mostra no lugar do JSON
/// compacto, que só deixava ver uns 20 caracteres (RE-03).
enum ReportJSONSummary {
    enum Shape: Equatable {
        case list(count: Int, keys: [String])
        case object(count: Int)
        case invalid
    }

    static func shape(_ text: String) -> Shape {
        guard let valor = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { return .invalid }
        switch valor {
        case .array(let lista):
            var chaves: [String] = []
            if case .object(let primeiro)? = lista.first { chaves = primeiro.keys.sorted() }
            return .list(count: lista.count, keys: chaves)
        case .object(let objeto):
            return .object(count: objeto.count)
        default:
            return .invalid
        }
    }

    /// "lista · 2 itens · item_id|item_name, price, quantity"
    static func text(_ json: String) -> String {
        switch shape(json) {
        case .list(let n, let chaves):
            let itens = n == 1 ? "1 item" : "\(n) itens"
            return chaves.isEmpty ? "lista · \(itens)" : "lista · \(itens) · \(chaves.joined(separator: ", "))"
        case .object(let n):
            return n == 1 ? "objeto · 1 campo" : "objeto · \(n) campos"
        case .invalid:
            return "JSON inválido"
        }
    }

    /// O JSON em várias linhas, para editar. Inválido volta como veio.
    static func pretty(_ json: String) -> String {
        guard let objeto = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let data = try? JSONSerialization.data(
                withJSONObject: objeto, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ) else { return json }
        return String(decoding: data, as: UTF8.self)
    }

    /// Válido (lista ou objeto) ou a mensagem do leitor de JSON, que diz a
    /// linha e a coluna quando sabe.
    static func validate(_ json: String) -> Result<JSONValue, ValidationError> {
        do {
            let objeto = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
            guard objeto is [Any] || objeto is [String: Any],
                  let valor = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else {
                return .failure(ValidationError(message: "O valor precisa ser uma lista [...] ou um objeto {...}."))
            }
            return .success(valor)
        } catch {
            let ns = error as NSError
            let detalhe = (ns.userInfo[NSDebugDescriptionErrorKey] as? String) ?? ns.localizedDescription
            return .failure(ValidationError(message: portugues(detalhe)))
        }
    }

    /// A mensagem do leitor de JSON do sistema vem em inglês: traduz os casos
    /// comuns e mantém a linha e a coluna, que é o que ajuda a achar o erro.
    static func portugues(_ detalhe: String) -> String {
        var onde = ""
        if let m = detalhe.firstMatch(of: #/line (\d+), column (\d+)/#) {
            onde = " Perto da linha \(m.1), coluna \(m.2)."
        }
        let causa: String
        if detalhe.contains("end of file") || detalhe.contains("Unexpected end") {
            causa = "O JSON termina antes de fechar todos os [ ] e { }."
        } else if let m = detalhe.firstMatch(of: #/[Uu]nexpected character '(.)'/#) {
            causa = "Caractere inesperado: \(m.1)."
        } else if detalhe.contains("Badly formed") || detalhe.contains("object") {
            causa = "Objeto mal formado: confira as aspas, os dois-pontos e as vírgulas."
        } else {
            causa = "O texto não é um JSON válido."
        }
        return causa + onde
    }

    struct ValidationError: Error, Equatable {
        let message: String
    }
}

/// Folha para editar o JSON de um valor (`items`): JSON formatado, conferido a
/// cada tecla, e só volta para o card quando é válido. Folha e não popover: um
/// clique fora do popover perderia o rascunho sem aviso.
struct ReportJSONValueSheet: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    let key: String
    let context: String
    @Binding var value: String

    @State private var rascunho = ""

    private var nome: String { key.isEmpty ? "valor" : key }

    var body: some View {
        let theme = themeManager.current
        let validacao = ReportJSONSummary.validate(rascunho)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DesignMetrics.Spacing.s1) {
                Text("Editar JSON de \(nome)")
                    .font(DSFont.headline)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !context.isEmpty {
                    Text(context)
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, DesignMetrics.Spacing.s7)
            .padding(.vertical, DesignMetrics.Spacing.s5)

            Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)

            CodeEditorView(text: $rascunho, accessibilityLabel: "JSON de \(nome)", python: false)
                .frame(minHeight: 200)

            Text("Com itens, o último objeto da lista vale para os itens a mais do evento. "
                 + "item_id|item_name: basta um dos dois. [soma_itens] não vale dentro de items.")
                .font(DSFont.footnote)
                .foregroundStyle(theme.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DesignMetrics.Spacing.s7)
                .padding(.vertical, DesignMetrics.Spacing.s4)

            Rectangle().fill(theme.separator).frame(height: DesignMetrics.hairline)

            HStack(alignment: .center, spacing: DesignMetrics.Spacing.s4) {
                switch validacao {
                case .success:
                    // O resumo pode ser longo (as chaves do item): corta no fim e
                    // não empurra os botões para fora da folha.
                    Label {
                        Text("JSON válido · \(ReportJSONSummary.text(rascunho))")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(ReportJSONSummary.text(rascunho))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.success)
                    }
                    .font(DSFont.subheadline)
                    .foregroundStyle(theme.labelSecondary)
                    .layoutPriority(-1)
                case .failure(let erro):
                    InlineError(title: "JSON inválido.", text: erro.message)
                        .layoutPriority(-1)
                }
                Spacer(minLength: DesignMetrics.Spacing.s4)
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Aplicar") {
                    if case .success(let valor) = validacao { value = valor.jsonText }
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled((try? validacao.get()) == nil)
                .help("Volta o JSON para o card (⌘↩)")
            }
            .padding(.horizontal, DesignMetrics.Spacing.s7)
            .padding(.vertical, DesignMetrics.Spacing.s5)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 320, idealHeight: 420)
        .background(theme.bgContent)
        .onAppear { rascunho = ReportJSONSummary.pretty(value) }
    }
}
