import Foundation

/// Um guia da Ajuda (LIB-2), lido de `docs/ajuda/<tópico>.md`. O formato é um
/// subconjunto pequeno de Markdown, de propósito: o teste rejeita o resto, e o
/// mesmo arquivo serve ao app, ao GitHub e a quem usa a versão web.
struct HelpDocument: Equatable {
    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case bullets([String])
        case steps([String])
        case code(String)
        case note(NoteKind, String)
    }

    enum NoteKind: Equatable { case tip, warning, plain }

    var meta: [String: String]
    var blocks: [Block]
    /// Linhas que o parser não reconhece (tabela, imagem, HTML, `#`, `###`):
    /// o teste exige que fique vazio.
    var unsupported: [String] = []

    var area: String { meta["area"] ?? "" }
    var title: String { meta["titulo"] ?? area }
    var summary: String { meta["resumo"] ?? "" }
    var needs: String { meta["precisa"] ?? "" }

    /// As seções obrigatórias, nesta ordem.
    static let sections = ["O que é", "Quando usar", "Passo a passo", "Exemplo prático", "Recursos", "Problemas comuns"]

    var headings: [String] {
        blocks.compactMap { if case .heading(let t) = $0 { return t } else { return nil } }
    }

    /// Texto corrido, para a busca e a contagem de palavras.
    var plainText: String {
        blocks.map { bloco in
            switch bloco {
            case .heading(let t), .paragraph(let t), .code(let t), .note(_, let t): return t
            case .bullets(let l), .steps(let l): return l.joined(separator: "\n")
            }
        }.joined(separator: "\n")
    }

    static func parse(_ texto: String) -> HelpDocument {
        var linhas = texto.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var meta: [String: String] = [:]
        if linhas.first == "---", let fim = linhas.dropFirst().firstIndex(of: "---") {
            for linha in linhas[1..<fim] {
                guard let sep = linha.range(of: ": ") else { continue }
                meta[String(linha[..<sep.lowerBound])] = String(linha[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            linhas = Array(linhas[(fim + 1)...])
        }

        var doc = HelpDocument(meta: meta, blocks: [])
        var paragrafo: [String] = []
        var lista: [String] = []
        var numerada = false
        var codigo: [String]?

        func fechar() {
            if !paragrafo.isEmpty { doc.blocks.append(.paragraph(paragrafo.joined(separator: " "))); paragrafo = [] }
            if !lista.isEmpty { doc.blocks.append(numerada ? .steps(lista) : .bullets(lista)); lista = [] }
        }

        for linha in linhas {
            if var bloco = codigo {
                if linha.hasPrefix("```") { doc.blocks.append(.code(bloco.joined(separator: "\n"))); codigo = nil }
                else { bloco.append(linha); codigo = bloco }
                continue
            }
            let t = linha.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { fechar(); continue }
            if t.hasPrefix("```") { fechar(); codigo = []; continue }
            if t.hasPrefix("## ") { fechar(); doc.blocks.append(.heading(String(t.dropFirst(3)))); continue }
            if t.hasPrefix("#") || t.hasPrefix("|") || t.hasPrefix("![") || t.hasPrefix("<") {
                doc.unsupported.append(t); continue
            }
            if t.hasPrefix("> ") {
                fechar()
                let corpo = String(t.dropFirst(2))
                let tipo: NoteKind = corpo.hasPrefix("Dica:") ? .tip : (corpo.hasPrefix("Atenção:") ? .warning : .plain)
                doc.blocks.append(.note(tipo, corpo)); continue
            }
            if t.hasPrefix("- ") {
                if !paragrafo.isEmpty || (numerada && !lista.isEmpty) { fechar() }
                numerada = false; lista.append(String(t.dropFirst(2))); continue
            }
            if let ponto = t.firstIndex(of: "."), t[..<ponto].allSatisfy(\.isNumber), !t[..<ponto].isEmpty,
               t[t.index(after: ponto)...].hasPrefix(" ") {
                if !paragrafo.isEmpty || (!numerada && !lista.isEmpty) { fechar() }
                numerada = true; lista.append(String(t[t.index(ponto, offsetBy: 2)...])); continue
            }
            if !lista.isEmpty { fechar() }
            paragrafo.append(t)
        }
        if let bloco = codigo { doc.blocks.append(.code(bloco.joined(separator: "\n"))) }
        fechar()
        return doc
    }
}

/// Onde ficam os guias e quais são.
enum HelpLibrary {
    /// Primeiros passos, as áreas na ordem da barra lateral e o relato.
    static var topics: [String] {
        ["comecando"] + WorkspaceTab.allCases.map(\.rawValue) + ["relatar-problema"]
    }

    /// `Contents/Resources/ajuda` no app; rodando do código, `docs/ajuda`.
    static func folder(bundle: URL? = Bundle.main.resourceURL, repositoryRoot: URL? = EngineLocator.repositoryRoot()) -> URL? {
        if let embutida = bundle?.appendingPathComponent("ajuda", isDirectory: true),
           FileManager.default.fileExists(atPath: embutida.path) {
            return embutida
        }
        guard let raiz = repositoryRoot else { return nil }
        let doRepositorio = raiz.appendingPathComponent("docs/ajuda", isDirectory: true)
        return FileManager.default.fileExists(atPath: doRepositorio.path) ? doRepositorio : nil
    }

    static func load(_ topic: String, in folder: URL? = HelpLibrary.folder()) -> HelpDocument? {
        guard let folder,
              let texto = try? String(contentsOf: folder.appendingPathComponent("\(topic).md"), encoding: .utf8) else { return nil }
        return HelpDocument.parse(texto)
    }

    /// Tópico a partir de `mobaile://ajuda/<tópico>`.
    static func topic(from url: URL) -> String? {
        guard url.scheme == "mobaile", url.host == "ajuda" else { return nil }
        let nome = url.lastPathComponent
        return topics.contains(nome) ? nome : nil
    }
}
