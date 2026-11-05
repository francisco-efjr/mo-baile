import AppKit

/// Caracteres que o PyCharm desenha como etiqueta com a abreviação Unicode
/// (PO-2), na lista de `SpecialCharacterFragment.java`: controles C0 (menos
/// tab, LF e CR), DEL e C1, NBSP, SHY, CGJ, espaços tipográficos, ZWSP, ZWNJ,
/// ZWJ, LRM, RLM, LSEP, PSEP, controles bidi, NNBSP, MMSP, WJ e ZWNBSP (BOM).
///
/// Só o desenho muda: o texto, a cópia e o que o VoiceOver lê continuam com o
/// caractere original.
enum CaracteresEspeciais {
    private static let c0 = [
        "NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL", "BS", nil, nil, "VT", "FF", nil, "SO", "SI",
        "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB", "CAN", "EM", "SUB", "ESC", "FS", "GS", "RS", "US",
    ]
    private static let c1 = [
        "PAD", "HOP", "BPH", "NBH", "IND", "NEL", "SSA", "ESA", "HTS", "HTJ", "VTS", "PLD", "PLU", "RI", "SS2", "SS3",
        "DCS", "PU1", "PU2", "STS", "CCH", "MW", "SPA", "EPA", "SOS", "SGC", "SCI", "CSI", "ST", "OSC", "PM", "APC",
    ]
    private static let espacos: [unichar: String] = [
        0x00A0: "NBSP", 0x2000: "NQSP", 0x2001: "MQSP", 0x2002: "ENSP", 0x2003: "EMSP", 0x2004: "3/MSP",
        0x2005: "4/MSP", 0x2006: "6/MSP", 0x2007: "FSP", 0x2008: "PSP", 0x2009: "THSP", 0x200A: "HSP",
        0x202F: "NNBSP", 0x205F: "MMSP",
    ]
    private static let outros: [unichar: String] = [
        0x00AD: "SHY", 0x034F: "CGJ", 0x200B: "ZWSP", 0x200C: "ZWNJ", 0x200D: "ZWJ", 0x200E: "LRM",
        0x200F: "RLM", 0x2028: "LSEP", 0x2029: "PSEP", 0x202A: "LRE", 0x202B: "RLE", 0x202C: "PDF",
        0x202D: "LRO", 0x202E: "RLO", 0x2060: "WJ", 0x2066: "LRI", 0x2067: "RLI", 0x2068: "FSI",
        0x2069: "PDI", 0xFEFF: "ZWNBSP",
    ]

    /// Abreviação a desenhar no lugar do caractere em `indice` (UTF-16), ou
    /// `nil` se ele aparece normalmente.
    static func abreviacao(em texto: NSString, indice: Int) -> String? {
        guard indice >= 0, indice < texto.length else { return nil }
        let u = texto.character(at: indice)
        if u < 0x20 { return c0[Int(u)] }
        if u == 0x7F { return "DEL" }
        if u >= 0x80, u < 0xA0 { return c1[Int(u - 0x80)] }
        if let espaco = espacos[u] {
            // Espaço seguido de marca combinante é base da marca: fica.
            return marcaCombinante(texto, indice + 1) ? nil : espaco
        }
        guard let nome = outros[u] else { return nil }
        // ZWJ e ZWNJ entre caracteres não ASCII formam emoji e escritas
        // complexas: ficam invisíveis.
        if u == 0x200C || u == 0x200D, naoASCII(texto, indice - 1) || naoASCII(texto, indice + 1) {
            return nil
        }
        return nome
    }

    private static func naoASCII(_ texto: NSString, _ indice: Int) -> Bool {
        indice >= 0 && indice < texto.length && texto.character(at: indice) > 0x7F
    }

    private static func marcaCombinante(_ texto: NSString, _ indice: Int) -> Bool {
        guard indice < texto.length, let escalar = Unicode.Scalar(texto.character(at: indice)) else { return false }
        switch escalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }
}

extension CodeLayoutManager: NSLayoutManagerDelegate {
    /// Marca o glifo do caractere especial como controle: o layout então pede
    /// a largura da etiqueta e não quebra linha em LSEP e PSEP.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let texto = textStorage?.string as NSString? else { return 0 }
        var propriedades: [NSLayoutManager.GlyphProperty]?
        for i in 0..<glyphRange.length where CaracteresEspeciais.abreviacao(em: texto, indice: charIndexes[i]) != nil {
            if propriedades == nil { propriedades = Array(UnsafeBufferPointer(start: props, count: glyphRange.length)) }
            propriedades?[i] = .controlCharacter
        }
        guard let propriedades else { return 0 }
        setGlyphs(glyphs, properties: propriedades, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let texto = textStorage?.string as NSString?,
              CaracteresEspeciais.abreviacao(em: texto, indice: charIndex) != nil else { return action }
        return .whitespace
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: NSRect,
        glyphPosition: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        guard let texto = textStorage?.string as NSString?,
              let nome = CaracteresEspeciais.abreviacao(em: texto, indice: charIndex) else {
            return NSRect(origin: glyphPosition, size: .zero)
        }
        return NSRect(origin: glyphPosition, size: NSSize(width: larguraDaEtiqueta(nome), height: proposedRect.height))
    }
}
