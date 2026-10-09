import SwiftUI

/// Paletas alternativas do design system (`docs/design/paletas/`).
///
/// Nove temas inspirados em designers de interiores, quatro claros, quatro
/// escuros e um extra. Cada um substitui os mesmos tokens da Praia e tem uma
/// variante de Aumentar contraste. Os valores e as fórmulas são os de
/// `paletas-data.js`: só as cores de base são declaradas, o resto (rótulos,
/// preenchimentos, tintas, hover, pressionado) é derivado delas.
///
/// Uma paleta é clara ou escura, e escolhê-la define a aparência do app. A
/// Praia, padrão, continua tendo as duas versões e segue Ajustes › Aparência.
struct PaletteSpec: Identifiable, Equatable, Sendable {
    enum Mode: String, Sendable { case light, dark }

    let id: String
    let name: String
    let designer: String
    let ref: String
    let mode: Mode
    var extra: Bool = false
    /// Cor da tinta (texto) em RGB 0–255; rótulos e preenchimentos são ela com opacidade.
    let ink: [Double]
    let window: String
    let content: String
    let alt: String
    let side: String
    /// Papel de parede atrás da janela (só aparece na prévia).
    let desk: String
    let accent: String
    var onAccent: String = "#FFFFFF"
    let accentText: String
    let destructive: String
    let success: String
    let warning: String
    let info: String
    let cats: [String]

    var isDark: Bool { mode == .dark }
}

extension PaletteSpec {
    /// Identificador da paleta padrão (os temas Praia claro e escuro).
    static let praiaID = "praia"

    static let all: [PaletteSpec] = [
        PaletteSpec(id: "salvia", name: "Sálvia & Palha", designer: "Imagem de referência",
                    ref: "Parede verde-sálvia, rattan, poltrona rosé e madeira clara.", mode: .light,
                    ink: [34, 45, 33], window: "#E7EBE2", content: "#FBFBF7", alt: "#F3F4EE", side: "#DFE4D8", desk: "#9DB497",
                    accent: "#8E4A63", accentText: "#8E4A63", destructive: "#C8102E", success: "#2F6B3A", warning: "#7A5800",
                    info: "#2D6680", cats: ["#8E4A63", "#4E7A52", "#A9602F"]),
        PaletteSpec(id: "bergamin", name: "Azulejo", designer: "Sig Bergamin",
                    ref: "Maximalismo brasileiro: porcelana azul e branca com toques de coral.", mode: .light,
                    ink: [18, 28, 66], window: "#ECEEF3", content: "#FFFFFF", alt: "#F5F6FA", side: "#E3E6EF", desk: "#BFCBEA",
                    accent: "#2B4FB3", accentText: "#2A4BAA", destructive: "#C8102E", success: "#2E7A3E", warning: "#8A5A00",
                    info: "#1F6F92", cats: ["#2B4FB3", "#C24A33", "#2E7A3E"]),
        PaletteSpec(id: "draper", name: "Hampshire", designer: "Dorothy Draper",
                    ref: "Preto e branco de alto contraste, verde laqueado e rosa.", mode: .light,
                    ink: [20, 24, 22], window: "#EEEDEA", content: "#FFFFFF", alt: "#F6F5F2", side: "#E6E4DF", desk: "#E7B9C2",
                    accent: "#14705F", accentText: "#11685A", destructive: "#C8102E", success: "#5C7A12", warning: "#8A5A00",
                    info: "#2468A0", cats: ["#14705F", "#C2456E", "#3A3A3A"]),
        PaletteSpec(id: "mahdavi", name: "Veludo Rosé", designer: "India Mahdavi",
                    ref: "Rosa empoeirado da Gallery do Sketch, ameixa, mostarda e verde.", mode: .light,
                    ink: [52, 24, 40], window: "#F3E9E6", content: "#FFFCFB", alt: "#FAF2EF", side: "#EEDFDB", desk: "#E9B8B0",
                    accent: "#8B356B", accentText: "#82305F", destructive: "#C8102E", success: "#2F6B3A", warning: "#7A5800",
                    info: "#2D6680", cats: ["#8B356B", "#9A7012", "#2F6B4F"]),
        PaletteSpec(id: "wearstler", name: "Terracota", designer: "Kelly Wearstler",
                    ref: "Espresso, terracota, latão escovado e pedra californiana.", mode: .dark,
                    ink: [255, 246, 236], window: "#2A2420", content: "#1C1815", alt: "#221D19", side: "#302925", desk: "#3B2A20",
                    accent: "#B4532F", accentText: "#EE9B73", destructive: "#FF4D6A", success: "#8FD685", warning: "#F5C451",
                    info: "#9BCFE0", cats: ["#EE9B73", "#C9B07A", "#A9C49A"]),
        PaletteSpec(id: "garcia", name: "Costes", designer: "Jacques Garcia",
                    ref: "Vermelho sangue-de-boi, veludo e dourado do Hôtel Costes.", mode: .dark,
                    ink: [255, 242, 236], window: "#2A1C1F", content: "#1B1113", alt: "#221619", side: "#321F23", desk: "#3E1A20",
                    accent: "#D2AE5C", onAccent: "#24170E", accentText: "#E3C27A", destructive: "#FF5E7A", success: "#7FD6A8",
                    warning: "#FF8A3D", info: "#9BCFE0", cats: ["#E3C27A", "#E08A8A", "#9BB89A"]),
        PaletteSpec(id: "hicks", name: "Geométrico", designer: "David Hicks",
                    ref: "Berinjela, violeta, laranja e rosa-choque em padrões geométricos.", mode: .dark,
                    ink: [246, 240, 255], window: "#251F2C", content: "#17131C", alt: "#1D1823", side: "#2C2534", desk: "#2E1F3A",
                    accent: "#7B54C8", accentText: "#C2A5FF", destructive: "#FF6961", success: "#8FD685", warning: "#F5C451",
                    info: "#9BCFE0", cats: ["#C2A5FF", "#FF9466", "#FF8FC7"]),
        PaletteSpec(id: "dirand", name: "Mármore", designer: "Joseph Dirand",
                    ref: "Monocromia de mármore escuro, pedra clara e azul ardósia.", mode: .dark,
                    ink: [240, 244, 248], window: "#232528", content: "#151618", alt: "#1B1C1F", side: "#2A2C30", desk: "#2C3036",
                    accent: "#476C96", accentText: "#9DBEE3", destructive: "#FF6961", success: "#8FD685", warning: "#F5C451",
                    info: "#9BDCD0", cats: ["#9DBEE3", "#C9BBA4", "#9ACBB5"]),
        PaletteSpec(id: "tudisco", name: "Jardim Digital", designer: "Antoni Tudisco",
                    ref: "Céu lavanda, violeta elétrico, flor de cerejeira e vermelho de esmalte.", mode: .light, extra: true,
                    ink: [30, 20, 70], window: "#ECE9F6", content: "#FFFFFF", alt: "#F6F4FC", side: "#E4DFF3", desk: "#C9C2EE",
                    accent: "#5A3CC8", accentText: "#5234B8", destructive: "#C8102E", success: "#2E7A3E", warning: "#8A5A00",
                    info: "#1F6F92", cats: ["#5A3CC8", "#C2457F", "#1F7A86"]),
    ]

    static func find(_ id: String) -> PaletteSpec? {
        all.first { $0.id == id }
    }

    /// As 11 amostras do cartão, na ordem do design.
    var swatches: [(name: String, hex: String)] {
        [("Janela", window), ("Conteúdo", content), ("Sidebar", side), ("Texto", PaletteMath.hex(ink)),
         ("Destaque", accent), ("Link", accentText), ("Cat. 2", cats[1]), ("Cat. 3", cats[2]),
         ("Sucesso", success), ("Aviso", warning), ("Erro", destructive)]
    }
}

// MARK: - Tema derivado

/// Tokens de uma paleta alternativa.
///
/// O que a paleta não declara (sintaxe, chips além do botão, GET/POST/CONNECT,
/// terminal, moldura do aparelho) vem da Praia da mesma aparência, como no CSS,
/// em que `palettes.css` é carregado depois de `tokens/colors.css`.
struct PaletteTheme: ThemeTokens {
    let spec: PaletteSpec
    let highContrast: Bool
    private let base: any ThemeTokens

    init(spec: PaletteSpec, highContrast: Bool = false) {
        self.spec = spec
        self.highContrast = highContrast
        self.base = spec.isDark ? PraiaDarkTheme(highContrast: highContrast) : PraiaLightTheme(highContrast: highContrast)
    }

    var name: String { spec.name }
    var id: String { "paleta_\(spec.id)" }
    var isDark: Bool { spec.isDark }

    private var light: Bool { !spec.isDark }
    private func ink(_ a: Double) -> Color { PaletteMath.color(spec.ink, a) }
    private func c(_ hex: String) -> Color { Color(hex: hex) }
    /// Destaque escurecido 16%: o pressionado e, no alto contraste, o próprio destaque.
    private var accentDarkened: String { PaletteMath.mix(spec.accent, "#000000", 0.16) }

    // Rótulos
    var labelPrimary: Color {
        guard highContrast else { return ink(0.90) }
        return light ? c(PaletteMath.hex(spec.ink)) : .white
    }
    var labelSecondary: Color { ink(highContrast ? 0.82 : (light ? 0.68 : 0.60)) }
    var labelTertiary: Color { ink(highContrast ? 0.62 : (light ? 0.42 : 0.34)) }
    var labelQuaternary: Color { ink(light ? 0.20 : 0.17) }

    // Separadores e preenchimentos
    var separator: Color { ink(highContrast ? 0.34 : (light ? 0.11 : 0.10)) }
    var separatorStrong: Color { ink(highContrast ? 0.55 : (light ? 0.20 : 0.18)) }
    var fillPrimary: Color { ink(light ? 0.10 : 0.12) }
    var fillSecondary: Color { ink(light ? 0.07 : 0.08) }
    var fillTertiary: Color { ink(light ? 0.045 : 0.05) }
    var fillQuaternary: Color { ink(light ? 0.025 : 0.03) }

    // Fundos
    var bgWindow: Color { c(spec.window) }
    var bgSidebar: Color { c(spec.side) }
    var bgContent: Color { c(spec.content) }
    var bgContentAlt: Color { c(spec.alt) }
    var bgGroup: Color { ink(light ? 0.035 : 0.04) }
    var bgControl: Color { light ? c(spec.content) : ink(0.10) }
    var bgField: Color { light ? c(spec.content) : ink(0.06) }
    var bgTerminal: Color { base.bgTerminal }
    var bgDeviceScreen: Color { base.bgDeviceScreen }
    var deviceBezel: Color { base.deviceBezel }
    var controlBorder: Color { ink(highContrast ? 0.60 : (light ? 0.14 : 0.12)) }
    var scrim: Color { light ? ink(0.18) : Color(r: 0, g: 0, b: 0, 0.35) }

    // Destaque
    var accent: Color { c(highContrast ? accentDarkened : spec.accent) }
    var accentHover: Color {
        c(light ? PaletteMath.mix(spec.accent, "#000000", 0.07) : PaletteMath.mix(spec.accent, "#FFFFFF", 0.08))
    }
    var accentPressed: Color { c(accentDarkened) }
    var onAccent: Color { c(spec.onAccent) }
    var accentText: Color {
        guard highContrast else { return c(spec.accentText) }
        return c(light
                 ? PaletteMath.mix(spec.accentText, PaletteMath.hex(spec.ink), 0.3)
                 : PaletteMath.mix(spec.accentText, "#FFFFFF", 0.35))
    }
    /// Tinta do destaque: o destaque no claro, o texto de destaque no escuro.
    private var tintBase: String { light ? spec.accent : spec.accentText }
    var accentTint: Color { PaletteMath.color(PaletteMath.rgb(tintBase), light ? 0.16 : 0.22) }
    var focusRing: Color { PaletteMath.color(PaletteMath.rgb(tintBase), light ? 0.55 : 0.60) }

    // Seleção
    var selection: Color { accent }
    var selectionInactive: Color { ink(light ? 0.10 : 0.12) }
    var selectionContent: Color { PaletteMath.color(PaletteMath.rgb(tintBase), light ? 0.14 : 0.20) }

    // Semânticas
    var destructive: Color { c(spec.destructive) }
    var destructiveFill: Color { light ? c(spec.destructive) : c("#E5303F") }
    var success: Color { c(spec.success) }
    var successFill: Color { base.successFill }
    var successTint: Color { PaletteMath.color(PaletteMath.rgb(spec.success), light ? 0.16 : 0.18) }
    var warning: Color { c(spec.warning) }
    var warningFill: Color { base.warningFill }
    var warningTint: Color { PaletteMath.color(PaletteMath.rgb(spec.warning), 0.16) }
    var dangerTint: Color { PaletteMath.color(PaletteMath.rgb(spec.destructive), light ? 0.10 : 0.14) }
    var info: Color { c(spec.info) }
    var recording: Color { c(spec.destructive) }

    // Categorias
    var cat1: Color { c(spec.cats[0]) }
    var cat2: Color { c(spec.cats[1]) }
    var cat3: Color { c(spec.cats[2]) }

    // Tipos de nó: só o botão segue a paleta.
    var chipWindow: Color { base.chipWindow }
    var chipView: Color { base.chipView }
    var chipText: Color { base.chipText }
    var chipInput: Color { base.chipInput }
    var chipButton: Color { c(spec.accentText) }

    // Sintaxe (da Praia)
    var syntaxKeyword: Color { base.syntaxKeyword }
    var syntaxFunction: Color { base.syntaxFunction }
    var syntaxTypeClass: Color { base.syntaxTypeClass }
    var syntaxString: Color { base.syntaxString }
    var syntaxNumber: Color { base.syntaxNumber }
    var syntaxComment: Color { base.syntaxComment }
    var syntaxPlain: Color { base.syntaxPlain }
    var syntaxGutter: Color { base.syntaxGutter }

    // HTTP
    var httpGet: Color { base.httpGet }
    var httpPost: Color { base.httpPost }
    var httpDelete: Color { c(spec.destructive) }
    var httpConnect: Color { base.httpConnect }
    var status2xx: Color { c(spec.success) }
    var status3xx: Color { c(spec.warning) }
    var status4xx: Color { c(spec.destructive) }
}

// MARK: - Checagens de contraste

/// Uma checagem do cartão da paleta: contraste WCAG ou distância de cor.
struct PaletteCheck: Identifiable, Equatable {
    let name: String
    let value: Double
    let minimum: Double
    let label: String
    var ok: Bool { value >= minimum }
    var id: String { name }
}

extension PaletteSpec {
    /// As oito checagens do design: contraste dos textos (7:1 no principal,
    /// 4,5:1 nos demais) e a distância OKLab entre o destaque e as cores de
    /// estado, para o destaque nunca ser lido como erro, aviso ou sucesso.
    var checks: [PaletteCheck] {
        typealias M = PaletteMath
        let content = M.rgb(self.content), window = M.rgb(self.window), accentRGB = M.rgb(accent)
        let textos: [(String, Double, Double)] = [
            ("Texto principal", M.contrast(M.over(ink, 0.9, content), content), 7),
            ("Texto secundário", M.contrast(M.over(ink, isDark ? 0.6 : 0.68, window), window), 4.5),
            ("Texto sobre destaque", M.contrast(M.rgb(onAccent), accentRGB), 4.5),
            ("Link / texto de destaque", M.contrast(M.rgb(accentText), window), 4.5),
            ("Erro", M.contrast(M.rgb(destructive), content), 4.5),
            ("Sucesso", M.contrast(M.rgb(success), content), 4.5),
            ("Aviso", M.contrast(M.rgb(warning), content), 4.5),
        ]
        var resultado = textos.map { nome, valor, minimo in
            PaletteCheck(name: nome, value: valor, minimum: minimo, label: String(format: "%.1f:1", valor))
        }
        let link = M.rgb(accentText)
        let distancia = [
            M.deltaE(accentRGB, M.rgb(destructive)), M.deltaE(accentRGB, M.rgb(success)), M.deltaE(accentRGB, M.rgb(warning)),
            M.deltaE(link, M.rgb(destructive)), M.deltaE(link, M.rgb(warning)),
        ].min() ?? 0
        resultado.append(PaletteCheck(name: "Destaque ≠ erro/aviso/sucesso", value: distancia, minimum: 0.1,
                                      label: String(format: "ΔE %.2f", distancia)))
        return resultado
    }
}

// MARK: - Matemática de cor (a mesma de paletas-data.js)

enum PaletteMath {
    static func rgb(_ hex: String) -> [Double] {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        return [Double(v >> 16 & 0xFF), Double(v >> 8 & 0xFF), Double(v & 0xFF)]
    }

    static func hex(_ rgb: [Double]) -> String {
        "#" + rgb.map { String(format: "%02X", Int(max(0, min(255, $0)).rounded())) }.joined()
    }

    /// Mistura linear em sRGB: `t` = 0 devolve `a`, 1 devolve `b`.
    static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        let x = rgb(a), y = rgb(b)
        return hex(zip(x, y).map { $0 * (1 - t) + $1 * t })
    }

    static func color(_ rgb: [Double], _ opacity: Double) -> Color {
        Color(r: rgb[0], g: rgb[1], b: rgb[2], opacity)
    }

    static func over(_ fg: [Double], _ alpha: Double, _ bg: [Double]) -> [Double] {
        zip(fg, bg).map { $0 * alpha + $1 * (1 - alpha) }
    }

    private static func linear(_ c: Double) -> Double {
        let v = c / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ rgb: [Double]) -> Double {
        0.2126 * linear(rgb[0]) + 0.7152 * linear(rgb[1]) + 0.0722 * linear(rgb[2])
    }

    /// Razão de contraste WCAG 2.
    static func contrast(_ a: [Double], _ b: [Double]) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    static func oklab(_ rgb: [Double]) -> [Double] {
        let r = linear(rgb[0]), g = linear(rgb[1]), b = linear(rgb[2])
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [
            0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
        ]
    }

    /// Distância euclidiana em OKLab.
    static func deltaE(_ a: [Double], _ b: [Double]) -> Double {
        let x = oklab(a), y = oklab(b)
        return sqrt(pow(x[0] - y[0], 2) + pow(x[1] - y[1], 2) + pow(x[2] - y[2], 2))
    }
}
