import Foundation

/// Junta os pedaços do stderr do motor e devolve linhas inteiras.
///
/// O cano entrega pedaços de tamanho arbitrário, sem respeitar linha nem
/// caractere. Decodificar cada pedaço sozinho descartava o pedaço inteiro
/// quando ele terminava no meio de um caractere UTF-8 (um "á" partido entre
/// dois pedaços sumia com tudo em volta). Aqui os bytes esperam o `\n`, e só a
/// linha completa vira texto; byte inválido vira caractere de substituição em
/// vez de apagar a linha.
struct EngineLogLines: Sendable {
    /// Linha sem `\n` que passar disto sai assim mesmo: um motor que despeja
    /// binário no stderr não pode fazer o buffer crescer sem fim.
    static let maxLineBytes = 64 * 1024

    private var pendente = Data()

    /// Acrescenta um pedaço e devolve as linhas que ele completou, sem o `\n`.
    mutating func append(_ chunk: Data) -> [String] {
        pendente.append(chunk)
        var linhas: [String] = []
        while let quebra = pendente.firstIndex(of: 0x0A) {
            linhas.append(Self.texto(pendente[pendente.startIndex..<quebra]))
            pendente = Data(pendente[pendente.index(after: quebra)...])
        }
        if pendente.count > Self.maxLineBytes {
            linhas.append(Self.texto(pendente))
            pendente = Data()
        }
        return linhas
    }

    /// Fim do cano: o resto sem `\n` (a última linha de um traceback, por
    /// exemplo) sai uma vez só.
    mutating func finish() -> String? {
        guard !pendente.isEmpty else { return nil }
        defer { pendente = Data() }
        return Self.texto(pendente)
    }

    private static func texto(_ bytes: Data) -> String {
        let linha = bytes.last == 0x0D ? bytes.dropLast() : bytes
        return String(decoding: linha, as: UTF8.self)
    }
}
