import Foundation

/// Busca aproximada da paleta de comandos (FLU-1).
///
/// Português do Brasil, sem diferença de acento nem de maiúsculas. Cada termo
/// digitado precisa casar com alguma palavra do título, da categoria ou dos
/// sinônimos. A pontuação, da maior para a menor, é: palavra igual, mesmo
/// grupo de sinônimos, prefixo, prefixo de sinônimo, um erro de digitação,
/// trecho no meio e letras na ordem dentro do título.
enum CommandSearch {

    /// Verbos e nomes que as pessoas trocam entre si.
    static let synonymGroups: [[String]] = [
        ["iniciar", "ligar", "comecar", "abrir", "subir", "ativar", "start"],
        ["parar", "desligar", "encerrar", "fechar", "interromper", "desativar", "stop"],
        ["buscar", "procurar", "pesquisar", "filtrar", "localizar", "achar", "find"],
        ["ajustes", "preferencias", "configuracoes", "opcoes", "settings"],
        ["gravar", "capturar", "registrar", "record"],
        ["rodar", "executar", "play", "run"],
        ["limpar", "apagar", "zerar", "esvaziar"],
        ["exportar", "salvar", "baixar"],
        ["aparelho", "dispositivo", "device", "celular", "telefone"],
        ["mostrar", "exibir", "ver"],
        ["ocultar", "esconder"],
        ["reiniciar", "reconectar", "restart"],
    ]

    private static let grupoDaPalavra: [String: Int] = {
        var mapa: [String: Int] = [:]
        for (indice, grupo) in synonymGroups.enumerated() {
            for palavra in grupo { mapa[palavra] = indice }
        }
        return mapa
    }()

    // MARK: - Normalização

    /// Sem acento, minúsculas, só letras e números.
    static func normalize(_ texto: String) -> String {
        let dobrado = texto.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                    locale: Locale(identifier: "pt_BR"))
        return String(dobrado.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
    }

    static func words(_ texto: String) -> [String] {
        normalize(texto).split(separator: " ").map(String.init)
    }

    // MARK: - Pontuação

    /// Pontos de uma ação para a busca, ou `nil` se algum termo não casou.
    static func score(_ command: AppCommand, query: String) -> Int? {
        let termos = words(query)
        guard !termos.isEmpty else { return 0 }
        let titulo = words(command.title)
        let extras = words(command.category.rawValue) + command.keywords.flatMap(words)
        let tituloColado = titulo.joined()

        var total = 0
        for termo in termos {
            let noTitulo = titulo.map { pontos(termo, $0) }.max() ?? 0
            // Sinônimo e categoria valem um pouco menos que o título.
            let nosExtras = (extras.map { pontos(termo, $0) }.max() ?? 0) * 8 / 10
            var melhor = max(noTitulo, nosExtras)
            if melhor == 0, termo.count >= 2, isSubsequence(termo, of: tituloColado) {
                melhor = 15
            }
            guard melhor > 0 else { return nil }
            total += melhor
        }
        // Quem digita o começo do título quer essa ação.
        if normalize(command.title).trimmingCharacters(in: .whitespaces).hasPrefix(termos.joined(separator: " ")) {
            total += 25
        }
        return total
    }

    private static func pontos(_ termo: String, _ palavra: String) -> Int {
        if palavra == termo { return 100 }
        let grupoTermo = grupoDaPalavra[termo]
        if let grupoTermo, grupoTermo == grupoDaPalavra[palavra] { return 90 }
        if palavra.hasPrefix(termo) { return 75 }
        if let grupoPalavra = grupoDaPalavra[palavra],
           synonymGroups[grupoPalavra].contains(where: { $0.hasPrefix(termo) }), termo.count >= 2 {
            return 60
        }
        if termo.count >= 4, palavra.count >= termo.count - 1,
           distance(termo, String(palavra.prefix(termo.count))) <= 1 {
            return 45
        }
        if termo.count >= 3, palavra.contains(termo) { return 40 }
        return 0
    }

    private static func isSubsequence(_ agulha: String, of palheiro: String) -> Bool {
        var resto = agulha[...]
        for letra in palheiro where letra == resto.first {
            resto = resto.dropFirst()
            if resto.isEmpty { return true }
        }
        return resto.isEmpty
    }

    /// Distância de edição (Levenshtein), para termos curtos.
    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var anterior = Array(0...y.count)
        for i in 1...x.count {
            var atual = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                atual[j] = min(anterior[j] + 1, atual[j - 1] + 1, anterior[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            anterior = atual
        }
        return anterior[y.count]
    }

    // MARK: - Resultado

    struct Section: Equatable, Identifiable {
        let title: String
        let commands: [AppCommand]
        var id: String { title }
    }

    /// O que a paleta mostra.
    ///
    /// Sem termo: as recentes no topo e o resto por categoria, na ordem do
    /// registro. Com termo: uma seção só, pela pontuação; no empate vence a
    /// usada mais recentemente, depois a ordem do registro.
    static func sections(_ commands: [AppCommand], query: String, recents: [CommandID]) -> [Section] {
        let visiveis = commands.filter { !$0.hiddenFromPalette }
        let termos = words(query)

        if termos.isEmpty {
            let porID = Dictionary(visiveis.map { ($0.id, $0) }, uniquingKeysWith: { primeiro, _ in primeiro })
            let recentes = recents.compactMap { porID[$0] }
            let jaListadas = Set(recentes.map(\.id))
            var secoes: [Section] = []
            if !recentes.isEmpty { secoes.append(Section(title: "Recentes", commands: recentes)) }
            for categoria in CommandCategory.allCases {
                let doGrupo = visiveis.filter { $0.category == categoria && !jaListadas.contains($0.id) }
                if !doGrupo.isEmpty { secoes.append(Section(title: categoria.rawValue, commands: doGrupo)) }
            }
            return secoes
        }

        let posicaoRecente = Dictionary(recents.enumerated().map { ($1, $0) }, uniquingKeysWith: { primeiro, _ in primeiro })
        let pontuadas = visiveis.enumerated().compactMap { indice, comando -> (AppCommand, Int, Int, Int)? in
            guard let pontos = score(comando, query: query) else { return nil }
            return (comando, pontos, posicaoRecente[comando.id] ?? Int.max, indice)
        }
        let ordenadas = pontuadas.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.2 != b.2 { return a.2 < b.2 }
            return a.3 < b.3
        }
        guard !ordenadas.isEmpty else { return [] }
        return [Section(title: "Resultados", commands: ordenadas.map(\.0))]
    }
}

/// Ações usadas por último, a mais recente primeiro (FLU-1).
///
/// Ficam no `UserDefaults`: repetir uma ação custa ⇧⌘P e Enter, mesmo
/// depois de reabrir o app.
final class CommandRecents {
    static let key = "mobaile.paleta.recentes"
    static let limit = 5

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var ids: [CommandID] {
        (defaults.stringArray(forKey: Self.key) ?? []).map(CommandID.init(rawValue:))
    }

    func record(_ id: CommandID) {
        var lista = ids.filter { $0 != id }
        lista.insert(id, at: 0)
        defaults.set(Array(lista.prefix(Self.limit)).map(\.rawValue), forKey: Self.key)
    }
}
