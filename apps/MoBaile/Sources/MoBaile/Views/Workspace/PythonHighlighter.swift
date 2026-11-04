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
enum PythonHighlighter {

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
    private static let nomeDeFuncao = regex(#"(?<=\bdef\s)[A-Za-z_][A-Za-z0-9_]*"#)
    private static let decorador = regex(#"^[ \t]*@[A-Za-z_][\w.]*"#, .anchorsMatchLines)
    private static let argumentoNomeado = regex(#"(?<=[(,][ \t]{0,40})[A-Za-z_]\w*(?=[ \t]*=(?!=))"#)
    /// String ou comentário, o que vier primeiro.
    private static let literal = regex(#"#[^\n]*|"""[\s\S]*?(?:"""|\z)|'''[\s\S]*?(?:'''|\z)|"(?:[^"\\\n]|\\.)*"?|'(?:[^'\\\n]|\\.)*'?"#)
    private static let inicioDeInstrucao = regex(#"^[ \t]*$"#)

    /// A faixa a recolorir depois de uma edição: o parágrafo, ou o texto todo
    /// se houver aspas triplas (uma docstring muda as linhas seguintes).
    static func faixaParaRecolorir(_ texto: NSString, editada: NSRange) -> NSRange {
        if texto.range(of: "\"\"\"").location != NSNotFound || texto.range(of: "'''").location != NSNotFound {
            return NSRange(location: 0, length: texto.length)
        }
        let segura = NSRange(location: min(editada.location, texto.length), length: 0)
        return texto.paragraphRange(for: NSRange(
            location: segura.location, length: min(editada.length, texto.length - segura.location)
        ))
    }

    /// Pinta `faixa` de `texto` com o `esquema`. Mexe só na cor.
    static func colorir(_ texto: NSMutableAttributedString, faixa: NSRange, esquema: EditorScheme) {
        guard faixa.length > 0 else { return }
        let fonte = texto.string as NSString
        let pintar = { (cor: NSColor, r: NSRange) in texto.addAttribute(.foregroundColor, value: cor, range: r) }
        texto.beginEditing()
        defer { texto.endEditing() }
        pintar(esquema.texto, faixa)

        for m in identificador.matches(in: texto.string, range: faixa) {
            let palavra = fonte.substring(with: m.range)
            if palavrasChave.contains(palavra) { pintar(esquema.palavraChave, m.range) }
            else if palavra == "self" { pintar(esquema.selfCor, m.range) }
            else if builtins.contains(palavra) { pintar(esquema.builtin, m.range) }
        }
        for m in numero.matches(in: texto.string, range: faixa) { pintar(esquema.numero, m.range) }
        for m in nomeDeFuncao.matches(in: texto.string, range: faixa) { pintar(esquema.funcao, m.range) }
        for m in decorador.matches(in: texto.string, range: faixa) { pintar(esquema.decorador, m.range) }
        for m in argumentoNomeado.matches(in: texto.string, range: faixa) { pintar(esquema.argumentoNomeado, m.range) }
        for m in literal.matches(in: texto.string, range: faixa) {
            let primeiro = fonte.character(at: m.range.location)
            if primeiro == 0x23 { pintar(esquema.comentario, m.range); continue }
            pintar(docstring(fonte, m.range) ? esquema.docstring : esquema.string, m.range)
        }
    }

    /// Aspas triplas no começo da instrução são docstring no PyCharm.
    private static func docstring(_ texto: NSString, _ r: NSRange) -> Bool {
        guard r.length >= 3, ["\"\"\"", "'''"].contains(texto.substring(with: NSRange(location: r.location, length: 3))) else {
            return false
        }
        let linha = texto.lineRange(for: NSRange(location: r.location, length: 0))
        let antes = NSRange(location: linha.location, length: r.location - linha.location)
        return inicioDeInstrucao.firstMatch(in: texto as String, range: antes) != nil
    }
}
