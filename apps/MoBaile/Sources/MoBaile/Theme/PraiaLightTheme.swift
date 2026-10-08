import SwiftUI

/// Aparência Clara (`:root` em `tokens/colors.css`), com a variante de
/// Aumentar contraste (`[data-contrast="high"]`).
struct PraiaLightTheme: ThemeTokens {
    let name = "light"
    let id = "praia_light"
    let isDark = false
    var highContrast: Bool = false

    init(highContrast: Bool = false) {
        self.highContrast = highContrast
    }

    // Rótulos
    var labelPrimary: Color { highContrast ? Color(hex: "#0B0C2E") : .navy(0.90) }
    var labelSecondary: Color { highContrast ? Color(r: 11, g: 12, b: 46, 0.80) : .navy(0.62) }
    var labelTertiary: Color { highContrast ? Color(r: 11, g: 12, b: 46, 0.62) : .navy(0.40) }
    let labelQuaternary = Color.navy(0.20)

    // Separadores e preenchimentos
    var separator: Color { highContrast ? Color(r: 11, g: 12, b: 46, 0.34) : .navy(0.11) }
    var separatorStrong: Color { highContrast ? Color(r: 11, g: 12, b: 46, 0.55) : .navy(0.20) }
    let fillPrimary = Color.navy(0.10)
    let fillSecondary = Color.navy(0.07)
    let fillTertiary = Color.navy(0.045)
    let fillQuaternary = Color.navy(0.025)

    // Fundos
    let bgWindow = Color(hex: "#ECECF1")
    var bgSidebar: Color { highContrast ? Color(hex: "#E2E3EB") : Color(hex: "#E6E7EE") }
    let bgContent = Color(hex: "#FFFFFF")
    let bgContentAlt = Color(hex: "#F6F6F9")
    let bgGroup = Color.navy(0.035)
    let bgControl = Color(hex: "#FFFFFF")
    let bgField = Color(hex: "#FFFFFF")
    let bgTerminal = Color(hex: "#15182B")
    let bgDeviceScreen = Color(hex: "#A8E1F2")
    let deviceBezel = Color(hex: "#15182B")
    var controlBorder: Color { highContrast ? Color(r: 11, g: 12, b: 46, 0.60) : .navy(0.14) }
    let scrim = Color.navy(0.18)

    // Destaque
    var accent: Color { highContrast ? Color(hex: "#A8365C") : Color(hex: "#C2456E") }
    let accentHover = Color(hex: "#B73F67")
    let accentPressed = Color(hex: "#A8365C")
    let onAccent = Color.white
    var accentText: Color { highContrast ? Color(hex: "#8E2A4C") : Color(hex: "#B23A63") }
    let accentTint = Color(r: 243, g: 137, b: 169, 0.20)
    let focusRing = Color(r: 194, g: 69, b: 110, 0.55)

    // Seleção
    var selection: Color { accent }
    var selectionInactive: Color { highContrast ? Color(r: 11, g: 12, b: 46, 0.22) : .navy(0.10) }
    let selectionContent = Color(r: 243, g: 137, b: 169, 0.18)

    // Semânticas
    let destructive = Color(hex: "#D70015")
    let destructiveFill = Color(hex: "#D70015")
    let success = Color(hex: "#3E7A45")
    let successFill = Color(hex: "#7EC674")
    let successTint = Color(r: 126, g: 198, b: 116, 0.20)
    let warning = Color(hex: "#8A6100")
    let warningFill = Color(hex: "#F5C451")
    let warningTint = Color(r: 245, g: 196, b: 81, 0.24)
    let dangerTint = Color(r: 215, g: 0, b: 21, 0.10)
    let info = Color(hex: "#1F6F92")
    let recording = Color(hex: "#D70015")

    // Categorias da sidebar
    let cat1 = Color(hex: "#C94C75")
    let cat2 = Color(hex: "#4A8550")
    let cat3 = Color(hex: "#2878A3")

    // Tipos de nó
    let chipWindow = Color.navy(0.55)
    let chipView = Color(hex: "#2878A3")
    let chipText = Color(hex: "#8A6100")
    let chipInput = Color(hex: "#3E7A45")
    let chipButton = Color(hex: "#B23A63")

    // Sintaxe (de PraiaLightTheme, versão 2)
    let syntaxKeyword = Color(hex: "#C2557A")
    let syntaxFunction = Color(hex: "#2E7FA6")
    let syntaxTypeClass = Color(hex: "#7B62B8")
    let syntaxString = Color(hex: "#3F8F4E")
    let syntaxNumber = Color(hex: "#A8601E")
    let syntaxComment = Color(hex: "#7A8E98")
    let syntaxPlain = Color(hex: "#17323F")
    let syntaxGutter = Color(hex: "#9AAAB4")

    // HTTP
    let httpGet = Color(hex: "#2878A3")
    let httpPost = Color(hex: "#8A6100")
    let httpDelete = Color(hex: "#D70015")
    let httpConnect = Color(hex: "#1E7F74")
    let status2xx = Color(hex: "#3E7A45")
    let status3xx = Color(hex: "#8A6100")
    let status4xx = Color(hex: "#D70015")
}
