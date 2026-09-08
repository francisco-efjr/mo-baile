import AppKit
import SwiftUI

/// Colore código Python para exibição.
///
/// O editor mostrava tudo numa cor só. Como o produto inteiro existe para
/// produzir Python, ler o resultado sem distinguir palavra-chave de string era
/// trabalho a mais justamente no artefato final.
///
/// É um colorizador léxico, não um parser: cobre o que aparece em Page Object
/// gerado — comentário, string, palavra-chave, número, nome de função e classe.
enum PythonHighlighter {

    private static let palavrasChave: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del",
        "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import",
        "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return",
        "True", "try", "while", "with", "yield", "self",
    ]

    /// Ordem importa: string e comentário são aplicados por último para vencer
    /// palavra-chave e número que apareçam dentro deles.
    static func destacar(_ codigo: String, tema: any ThemeTokens, fonte: NSFont) -> NSAttributedString {
        let texto = NSMutableAttributedString(
            string: codigo,
            attributes: [.font: fonte, .foregroundColor: NSColor(tema.syntaxPlain)]
        )
        let inteiro = NSRange(location: 0, length: (codigo as NSString).length)

        aplicar(#"\b[A-Za-z_][A-Za-z0-9_]*\b"#, em: texto, escopo: inteiro) { trecho, faixa in
            guard palavrasChave.contains(trecho) else { return }
            texto.addAttribute(.foregroundColor, value: NSColor(tema.syntaxKeyword), range: faixa)
        }
        aplicar(#"\b\d+(\.\d+)?\b"#, em: texto, escopo: inteiro) { _, faixa in
            texto.addAttribute(.foregroundColor, value: NSColor(tema.syntaxNumber), range: faixa)
        }
        // Nome logo após `def` e `class`.
        aplicar(#"(?<=\bdef\s)[A-Za-z_][A-Za-z0-9_]*"#, em: texto, escopo: inteiro) { _, faixa in
            texto.addAttribute(.foregroundColor, value: NSColor(tema.syntaxFunction), range: faixa)
        }
        aplicar(#"(?<=\bclass\s)[A-Za-z_][A-Za-z0-9_]*"#, em: texto, escopo: inteiro) { _, faixa in
            texto.addAttribute(.foregroundColor, value: NSColor(tema.syntaxTypeClass), range: faixa)
        }
        // CONSTANTES_EM_CAIXA_ALTA são o nome dos locators gerados.
        aplicar(#"\b[A-Z][A-Z0-9_]{2,}\b"#, em: texto, escopo: inteiro) { _, faixa in
            texto.addAttribute(.foregroundColor, value: NSColor(tema.syntaxTypeClass), range: faixa)
        }
        aplicar(#"("""[\s\S]*?"""|'''[\s\S]*?'''|"[^"\n]*"|'[^'\n]*')"#, em: texto, escopo: inteiro) { _, faixa in
            texto.addAttribute(.foregroundColor, value: NSColor(tema.syntaxString), range: faixa)
        }
        aplicar(#"#[^\n]*"#, em: texto, escopo: inteiro) { _, faixa in
            texto.addAttribute(.foregroundColor, value: NSColor(tema.syntaxComment), range: faixa)
        }

        let paragrafo = NSMutableParagraphStyle()
        paragrafo.lineHeightMultiple = 1.35
        texto.addAttribute(.paragraphStyle, value: paragrafo, range: inteiro)
        return texto
    }

    private static func aplicar(
        _ padrao: String,
        em texto: NSMutableAttributedString,
        escopo: NSRange,
        acao: (String, NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: padrao) else { return }
        let fonte = texto.string as NSString
        for casamento in regex.matches(in: texto.string, range: escopo) {
            acao(fonte.substring(with: casamento.range), casamento.range)
        }
    }
}
