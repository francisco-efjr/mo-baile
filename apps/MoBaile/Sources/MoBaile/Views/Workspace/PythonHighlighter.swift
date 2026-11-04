import AppKit

/// Colore código Python no editor, com os papéis do esquema do PyCharm (PO-3).
///
/// É um colorizador léxico, não um parser: cobre o que aparece em Page Object
/// gerado. Só troca a cor de uma faixa do texto (o parágrafo editado, ou tudo),
/// sem recriar o texto: a seleção e o desfazer ficam intactos.
///
/// Diferenças para a versão anterior, para bater com o PyCharm: `self` tem cor
/// própria, CAIXA_ALTA e nome de classe ficam na cor do texto, decorador,
/// builtin e argumento nomeado ganham cor, e string e comentário são lidos
/// numa passada só (um `#` dentro de string não vira comentário).
///
/// Desempenho (R-06): os papéis vão primeiro para um vetor de uma posição por
/// unidade UTF-16 e só depois para o armazenamento, em ordem e uma vez por
/// trecho de mesma cor. Pintar passada por passada no armazenamento custava
/// segundos num arquivo de 1 MB.
enum PythonHighlighter {

    /// Marca as unidades dentro de uma string de aspas triplas: a edição dentro
    /// dela recolore a docstring inteira, e não o arquivo todo.
    static let literalTriplo = NSAttributedString.Key("mobaile.literalTriplo")

    private static let palavrasChave: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
        "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import",
        "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return",
        "True", "try", "while", "with", "yield",
    ]
    private static let builtins: Set<String> = [
        "abs", "all", "any", "bool", "dict", "enumerate", "Exception", "filter", "float", "format",
        "getattr", "hasattr", "int", "isinstance", "iter", "len", "list", "map", "max", "min", "next",
        "object", "open", "print", "range", "repr", "round", "set", "setattr", "sorted", "str", "sum",
        "super", "tuple", "type", "zip",
    ]

    private static func regex(_ padrao: String, _ opcoes: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: padrao, options: opcoes)
    }

    private static let identificador = regex(#"\b[A-Za-z_][A-Za-z0-9_]*\b"#)
    private static let numero = regex(#"\b\d+(\.\d+)?\b"#)
    private static let nomeDeFuncao = regex(#"\bdef[ \t]+([A-Za-z_][A-Za-z0-9_]*)"#)
    private static let decorador = regex(#"^[ \t]*@[A-Za-z_][\w.]*"#, .anchorsMatchLines)
    private static let argumentoNomeado = regex(#"[(,][ \t]*([A-Za-z_]\w*)[ \t]*=(?!=)"#)
    /// String ou comentário, o que vier primeiro.
    private static let literal = regex(#"#[^\n]*|"""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z)|"(?:[^"\\\n]|\\.)*"?|'(?:[^'\\\n]|\\.)*'?"#)
    private static let inicioDeInstrucao = regex(#"^[ \t]*$"#)

    /// Papel de cada unidade UTF-16 na faixa.
    private enum Papel: UInt8 {
        case texto, palavraChave, selfCor, builtin, numero, funcao, decorador, argumento, string, docstring, comentario
    }

    /// Trocar estes caracteres pode abrir ou fechar uma string e mudar a cor
    /// até o fim do arquivo.
    static func mexeEmLiteral(_ texto: String) -> Bool {
        texto.utf8.contains { $0 == 0x22 || $0 == 0x27 || $0 == 0x5C || $0 == 0x23 }
    }

    /// A faixa a recolorir depois de uma edição: o parágrafo, estendido até
    /// cobrir a string de aspas triplas em que ele estiver. Se a edição pôs ou
    /// tirou aspas e o arquivo tem aspas triplas, vai até o fim do arquivo.
    static func faixaParaRecolorir(_ armazenamento: NSAttributedString, editada: NSRange, mexeuEmAspas: Bool) -> NSRange {
        let texto = armazenamento.string as NSString
        let total = texto.length
        let local = min(editada.location, total)
        var faixa = texto.paragraphRange(for: NSRange(location: local, length: min(editada.length, total - local)))
        let tudo = NSRange(location: 0, length: total)
        for indice in [faixa.location - 1, faixa.location, NSMaxRange(faixa) - 1, NSMaxRange(faixa)] where indice >= 0 && indice < total {
            // A faixa mais longa só para quem está numa docstring: pedida num
            // ponto sem o atributo, ela percorreria o arquivo inteiro.
            guard armazenamento.attribute(literalTriplo, at: indice, effectiveRange: nil) != nil else { continue }
            var efetiva = NSRange()
            _ = armazenamento.attribute(literalTriplo, at: indice, longestEffectiveRange: &efetiva, in: tudo)
            faixa = NSUnionRange(faixa, efetiva)
        }
        faixa = texto.paragraphRange(for: faixa)
        if mexeuEmAspas, texto.range(of: "\"\"\"").location != NSNotFound || texto.range(of: "'''").location != NSNotFound {
            return NSRange(location: faixa.location, length: total - faixa.location)
        }
        return faixa
    }

    /// Pinta `faixa` de `texto` com o `esquema`. Mexe só na cor.
    static func colorir(_ texto: NSMutableAttributedString, faixa: NSRange, esquema: EditorScheme) {
        guard faixa.length > 0 else { return }
        let fonte = texto.string as NSString
        let corpo = texto.string
        var papeis = [Papel](repeating: .texto, count: faixa.length)
        var triplo = [Bool](repeating: false, count: faixa.length)
        func marcar(_ r: NSRange, _ papel: Papel) {
            let inicio = max(r.location, faixa.location) - faixa.location
            let fim = min(NSMaxRange(r), NSMaxRange(faixa)) - faixa.location
            guard inicio < fim else { return }
            for i in inicio..<fim { papeis[i] = papel }
        }

        for m in identificador.matches(in: corpo, range: faixa) where m.range.length <= 10 {
            let palavra = fonte.substring(with: m.range)
            if palavrasChave.contains(palavra) { marcar(m.range, .palavraChave) }
            else if palavra == "self" { marcar(m.range, .selfCor) }
            else if builtins.contains(palavra) { marcar(m.range, .builtin) }
        }
        for m in numero.matches(in: corpo, range: faixa) { marcar(m.range, .numero) }
        for m in nomeDeFuncao.matches(in: corpo, range: faixa) { marcar(m.range(at: 1), .funcao) }
        for m in decorador.matches(in: corpo, range: faixa) { marcar(m.range, .decorador) }
        for m in argumentoNomeado.matches(in: corpo, range: faixa) { marcar(m.range(at: 1), .argumento) }
        for m in literal.matches(in: corpo, range: faixa) {
            let primeiro = fonte.character(at: m.range.location)
            if primeiro == 0x23 { marcar(m.range, .comentario); continue }
            let tresAspas = m.range.length >= 3 && ["\"\"\"", "'''"].contains(fonte.substring(with: NSRange(location: m.range.location, length: 3)))
            marcar(m.range, tresAspas && docstring(fonte, m.range) ? .docstring : .string)
            if tresAspas {
                let inicio = m.range.location - faixa.location
                for i in inicio..<min(inicio + m.range.length, triplo.count) { triplo[i] = true }
            }
        }

        let cores: [Papel: NSColor] = [
            .texto: esquema.texto, .palavraChave: esquema.palavraChave, .selfCor: esquema.selfCor,
            .builtin: esquema.builtin, .numero: esquema.numero, .funcao: esquema.funcao,
            .decorador: esquema.decorador, .argumento: esquema.argumentoNomeado, .string: esquema.string,
            .docstring: esquema.docstring, .comentario: esquema.comentario,
        ]
        texto.beginEditing()
        defer { texto.endEditing() }
        texto.removeAttribute(literalTriplo, range: faixa)
        var inicio = 0
        while inicio < papeis.count {
            var fim = inicio + 1
            while fim < papeis.count, papeis[fim] == papeis[inicio], triplo[fim] == triplo[inicio] { fim += 1 }
            let r = NSRange(location: faixa.location + inicio, length: fim - inicio)
            texto.addAttribute(.foregroundColor, value: cores[papeis[inicio]] ?? esquema.texto, range: r)
            if triplo[inicio] { texto.addAttribute(literalTriplo, value: true, range: r) }
            inicio = fim
        }
    }

    /// Aspas triplas no começo da instrução são docstring no PyCharm.
    private static func docstring(_ texto: NSString, _ r: NSRange) -> Bool {
        let linha = texto.lineRange(for: NSRange(location: r.location, length: 0))
        let antes = NSRange(location: linha.location, length: r.location - linha.location)
        return inicioDeInstrucao.firstMatch(in: texto as String, range: antes) != nil
    }
}
