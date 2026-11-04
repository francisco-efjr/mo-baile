import AppKit
import CoreText
import SwiftUI

/// Fonte do editor de Page Objects (PO-3, D-1): JetBrains Mono 13, altura de
/// linha 1,2 e sem ligaduras, os padrões do PyCharm (`FontPreferences.java`).
///
/// A fonte vai embutida no app (`Contents/Resources/fonts`, licença SIL OFL
/// 1.1 em `assets/fonts/OFL.txt`) e é registrada só para este processo. Se o
/// arquivo faltar ou o registro falhar, o editor usa SF Mono.
@MainActor
enum EditorFont {
    static let tamanho: CGFloat = 13
    static let alturaDeLinha: CGFloat = 1.2
    static let nome = "JetBrainsMono-Regular"

    /// Registra uma vez, na primeira fonte pedida.
    static let registrada: Bool = registrar()

    /// Onde procurar os `.ttf`: no app empacotado, em `Resources/fonts`; no
    /// repositório (testes e `swift run`), em `assets/fonts`.
    static func pastas() -> [URL] {
        var pastas: [URL] = []
        if let recursos = Bundle.main.resourceURL { pastas.append(recursos.appendingPathComponent("fonts")) }
        var raiz = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { raiz.deleteLastPathComponent() }
        pastas.append(raiz.appendingPathComponent("assets/fonts"))
        return pastas
    }

    private static func registrar() -> Bool {
        for pasta in pastas() {
            let arquivos = ((try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "ttf" && $0.lastPathComponent.hasPrefix("JetBrainsMono-") }
            guard !arquivos.isEmpty else { continue }
            for arquivo in arquivos {
                // "Já registrada" (outra janela, ou a fonte instalada) também serve.
                CTFontManagerRegisterFontsForURL(arquivo as CFURL, .process, nil)
            }
            if NSFont(name: nome, size: tamanho) != nil { return true }
        }
        return NSFont(name: nome, size: tamanho) != nil
    }

    static func fonte(tamanho: CGFloat = tamanho) -> NSFont {
        guard registrada, let jetbrains = NSFont(name: nome, size: tamanho) else {
            return .monospacedSystemFont(ofSize: tamanho, weight: .regular)
        }
        return jetbrains
    }

    /// Parágrafo com a altura de linha do PyCharm: a altura natural da fonte
    /// vezes 1,2, fixa, para o gutter e a linha atual baterem com o texto.
    static func paragrafo(_ fonte: NSFont) -> NSParagraphStyle {
        let estilo = NSMutableParagraphStyle()
        let altura = alturaDaLinha(fonte)
        estilo.minimumLineHeight = altura
        estilo.maximumLineHeight = altura
        return estilo
    }

    static func alturaDaLinha(_ fonte: NSFont) -> CGFloat {
        (NSLayoutManager().defaultLineHeight(for: fonte) * alturaDeLinha).rounded()
    }

    /// Sobe o glifo metade do espaço extra: o PyCharm centraliza a linha.
    static func deslocamentoDaLinhaDeBase(_ fonte: NSFont) -> CGFloat {
        ((alturaDaLinha(fonte) - NSLayoutManager().defaultLineHeight(for: fonte)) / 2).rounded()
    }

    /// Atributos de digitação: fonte, altura, ligaduras desligadas e cor.
    static func atributos(_ fonte: NSFont, cor: NSColor) -> [NSAttributedString.Key: Any] {
        [
            .font: fonte, .foregroundColor: cor, .ligature: 0,
            .paragraphStyle: paragrafo(fonte), .baselineOffset: deslocamentoDaLinhaDeBase(fonte),
        ]
    }
}

/// Cores do editor (PO-3, D-1). "PyCharm" é o padrão: Islands Dark no escuro
/// (`IslandSchemeDark.xml` + `PythonDarcula.xml`, tabela 2.5 da pesquisa) e
/// IntelliJ Light no claro. "Tema" usa as cores de sintaxe da paleta do app.
struct EditorScheme {
    static let chave = "mobaile.esquemaEditor"
    static let pycharmID = "pycharm"
    static let temaID = "tema"

    let fundo, texto, palavraChave, selfCor, string, docstring, comentario, numero: NSColor
    let funcao, decorador, builtin, argumentoNomeado, linhaAtual, numeroLinha, numeroLinhaAtual, etiqueta: NSColor

    /// Número de linha do PyCharm escuro (`#4B5059`) dá 2,15:1 sobre `#191A1C`.
    /// O ajuste mínimo para 3:1 (texto não essencial) é `#61666E` (3,01:1).
    /// No claro, `#AEB3C2` dá 2,09:1 sobre branco; ajuste `#9094A4` (3,02:1).
    static func pycharm(escuro: Bool, altoContraste: Bool) -> EditorScheme {
        if escuro {
            return EditorScheme(
                fundo: hex(0x191A1C), texto: hex(0xBCBEC4), palavraChave: hex(0xCF8E6D), selfCor: hex(0x94558D),
                string: hex(0x6AAB73), docstring: hex(0x5F826B), comentario: hex(0x7A7E85), numero: hex(0x2AACB8),
                funcao: hex(0x56A8F5), decorador: hex(0xB3AE60), builtin: hex(0x8888C6), argumentoNomeado: hex(0xAA4926),
                linhaAtual: hex(0x1F2024), numeroLinha: hex(altoContraste ? 0xA1A3AB : 0x61666E),
                numeroLinhaAtual: hex(0xA1A3AB), etiqueta: hex(altoContraste ? 0xA1A3AB : 0x6F737A)
            )
        }
        // IntelliJ Light (New UI). Valores Inferidos: conferir com
        // `expUI_lightScheme.xml` antes de dar por fiel (pendência no relatório).
        return EditorScheme(
            fundo: hex(0xFFFFFF), texto: hex(0x080808), palavraChave: hex(0x0033B3), selfCor: hex(0x94558D),
            string: hex(0x067D17), docstring: hex(0x8C8C8C), comentario: hex(0x8C8C8C), numero: hex(0x1750EB),
            funcao: hex(0x00627A), decorador: hex(0x9E880D), builtin: hex(0x000080), argumentoNomeado: hex(0x660099),
            linhaAtual: hex(0xF5F8FE), numeroLinha: hex(altoContraste ? 0x767A8A : 0x9094A4),
            numeroLinhaAtual: hex(0x767A8A), etiqueta: hex(altoContraste ? 0x767A8A : 0x9094A4)
        )
    }

    /// As cores de sintaxe da paleta do app, como antes desta rodada.
    static func tema(_ t: any ThemeTokens) -> EditorScheme {
        let c = { (cor: SwiftUI.Color) in NSColor(cor) }
        return EditorScheme(
            fundo: c(t.bgContent), texto: c(t.syntaxPlain), palavraChave: c(t.syntaxKeyword), selfCor: c(t.syntaxKeyword),
            string: c(t.syntaxString), docstring: c(t.syntaxString), comentario: c(t.syntaxComment), numero: c(t.syntaxNumber),
            funcao: c(t.syntaxFunction), decorador: c(t.syntaxTypeClass), builtin: c(t.syntaxPlain),
            argumentoNomeado: c(t.syntaxPlain), linhaAtual: c(t.bgContentAlt), numeroLinha: c(t.syntaxGutter),
            numeroLinhaAtual: c(t.labelSecondary), etiqueta: c(t.syntaxGutter)
        )
    }

    static func atual(_ t: any ThemeTokens, escolha: String?) -> EditorScheme {
        escolha == temaID ? tema(t) : pycharm(escuro: t.isDark, altoContraste: t.highContrast)
    }

    static func hex(_ valor: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat(valor >> 16 & 0xFF) / 255, green: CGFloat(valor >> 8 & 0xFF) / 255,
            blue: CGFloat(valor & 0xFF) / 255, alpha: 1
        )
    }
}
