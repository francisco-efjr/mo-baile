import Foundation

/// Regras de texto do editor de Page Objects, iguais às do PyCharm (PO-1).
///
/// Ficam fora das views para serem testadas sem janela. Contam em escalares
/// Unicode e UTF-16, nunca em `Character`: no Swift `"\r\n"` é um grafema só,
/// e `split(separator: "\n")` dizia "1 linha" para um texto colado do Windows.
enum EditorText {
    /// Largura do recuo e da parada de tab (Python, PEP 8).
    static let recuo = 4

    /// CRLF e CR soltos viram LF, como no documento do PyCharm. Nada mais muda:
    /// tab, NBSP, ZWSP, emoji, NFD e U+2028 ficam como vieram.
    static func normalizarQuebras(_ texto: String) -> String {
        guard texto.utf8.contains(0x0D) else { return texto }
        var saida = String.UnicodeScalarView()
        var anteriorCR = false
        for escalar in texto.unicodeScalars {
            if escalar == "\r" {
                saida.append("\n")
                anteriorCR = true
                continue
            }
            if !(escalar == "\n" && anteriorCR) { saida.append(escalar) }
            anteriorCR = false
        }
        return String(saida)
    }

    /// Quebras de linha (LF, CRLF ou CR) no texto.
    private static func quebras(_ texto: String) -> Int {
        var total = 0
        var anteriorCR = false
        for byte in texto.utf8 {
            if byte == 0x0D { total += 1 } else if byte == 0x0A, !anteriorCR { total += 1 }
            anteriorCR = byte == 0x0D
        }
        return total
    }

    /// Linhas numeradas no gutter: a última, vazia depois de um `\n`, conta.
    static func linhasDoGutter(_ texto: String) -> Int { quebras(texto) + 1 }

    /// "9 linhas" do cabeçalho. Uma quebra no fim não abre linha nova.
    static func rotuloDeLinhas(_ texto: String) -> String {
        guard !texto.isEmpty else { return "0 linhas" }
        let fimComQuebra = texto.utf8.last == 0x0A || texto.utf8.last == 0x0D
        let total = quebras(texto) + (fimComQuebra ? 0 : 1)
        return total == 1 ? "1 linha" : "\(total) linhas"
    }

    /// Linha e coluna (a partir de 1) da posição UTF-16, como a status bar do
    /// PyCharm: a coluna conta grafemas, e o tab avança até a próxima parada.
    static func linhaEColuna(em texto: NSString, posicao: Int) -> (linha: Int, coluna: Int) {
        let alvo = min(max(posicao, 0), texto.length)
        var linha = 1
        var inicioDaLinha = 0
        for indice in 0..<alvo where texto.character(at: indice) == 0x0A {
            linha += 1
            inicioDaLinha = indice + 1
        }
        let trecho = texto.substring(with: NSRange(location: inicioDaLinha, length: alvo - inicioDaLinha))
        var coluna = 0
        for grafema in trecho {
            coluna = grafema == "\t" ? (coluna / recuo + 1) * recuo : coluna + 1
        }
        return (linha, coluna + 1)
    }
}
