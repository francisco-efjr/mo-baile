import SwiftUI

/// Aparência Escura (`[data-theme="dark"]` em `tokens/colors.css`), com a
/// variante de Aumentar contraste.
struct PraiaDarkTheme: ThemeTokens {
    let name = "dark"
    let id = "praia_dark"
    let isDark = true
    var highContrast: Bool = false

    init(highContrast: Bool = false) {
        self.highContrast = highContrast
    }

    // Rótulos
    var labelPrimary: Color { highContrast ? .white : .white(0.90) }
    var labelSecondary: Color { highContrast ? .white(0.82) : .white(0.60) }
    var labelTertiary: Color { highContrast ? .white(0.62) : .white(0.34) }
    let labelQuaternary = Color.white(0.17)

    // Separadores e preenchimentos
    var separator: Color { highContrast ? .white(0.34) : .white(0.10) }
    var separatorStrong: Color { highContrast ? .white(0.55) : .white(0.18) }
    let fillPrimary = Color.white(0.12)
    let fillSecondary = Color.white(0.08)
    let fillTertiary = Color.white(0.05)
    let fillQuaternary = Color.white(0.03)

    // Fundos
    let bgWindow = Color(hex: "#24242C")
    var bgSidebar: Color { highContrast ? Color(hex: "#2C2C36") : Color(hex: "#2A2A33") }
    let bgContent = Color(hex: "#18181E")
    let bgContentAlt = Color(hex: "#1E1E25")
    let bgGroup = Color.white(0.04)
    let bgControl = Color.white(0.10)
    let bgField = Color.white(0.06)
    let bgTerminal = Color(hex: "#0E0F18")
    let bgDeviceScreen = Color(hex: "#1E3A48")
    let deviceBezel = Color(hex: "#0B0C14")
    var controlBorder: Color { highContrast ? .white(0.62) : .white(0.12) }
    let scrim = Color(r: 0, g: 0, b: 0, 0.35)

    // Destaque
    var accent: Color { highContrast ? Color(hex: "#D9567F") : Color(hex: "#C2456E") }
    let accentHover = Color(hex: "#CC5079")
    let accentPressed = Color(hex: "#A8365C")
    let onAccent = Color.white
    var accentText: Color { highContrast ? Color(hex: "#FFB3C9") : Color(hex: "#F389A9") }
    let accentTint = Color(r: 243, g: 137, b: 169, 0.26)
    let focusRing = Color(r: 243, g: 137, b: 169, 0.60)

    // Seleção
    var selection: Color { accent }
    var selectionInactive: Color { highContrast ? .white(0.26) : .white(0.12) }
    let selectionContent = Color(r: 243, g: 137, b: 169, 0.20)

    // Semânticas
    let destructive = Color(hex: "#FF6961")
    let destructiveFill = Color(hex: "#E5303F")
    let success = Color(hex: "#8FD685")
    let successFill = Color(hex: "#7EC674")
    let successTint = Color(r: 126, g: 198, b: 116, 0.18)
    let warning = Color(hex: "#F5C451")
    let warningFill = Color(hex: "#F5C451")
    let warningTint = Color(r: 245, g: 196, b: 81, 0.16)
    let dangerTint = Color(r: 255, g: 105, b: 97, 0.14)
    let info = Color(hex: "#9BDCF3")
    let recording = Color(hex: "#FF453A")

    // Categorias da sidebar
    let cat1 = Color(hex: "#F389A9")
    let cat2 = Color(hex: "#7EC674")
    let cat3 = Color(hex: "#7FCFEC")

    // Tipos de nó
    let chipWindow = Color.white(0.55)
    let chipView = Color(hex: "#7FCFEC")
    let chipText = Color(hex: "#F5C451")
    let chipInput = Color(hex: "#8FD685")
    let chipButton = Color(hex: "#F389A9")

    // Sintaxe (de PraiaDarkTheme, versão 2)
    let syntaxKeyword = Color(hex: "#CBA6F7")
    let syntaxFunction = Color(hex: "#89B4FA")
    let syntaxTypeClass = Color(hex: "#F9E2AF")
    let syntaxString = Color(hex: "#A6E3A1")
    let syntaxNumber = Color(hex: "#FAB387")
    let syntaxComment = Color(hex: "#7F849C")
    let syntaxPlain = Color(hex: "#CDD6F4")
    let syntaxGutter = Color(hex: "#585B70")

    // HTTP
    let httpGet = Color(hex: "#7FCFEC")
    let httpPost = Color(hex: "#F5C451")
    let httpDelete = Color(hex: "#FF6961")
    let httpConnect = Color(hex: "#94E2D5")
    let status2xx = Color(hex: "#8FD685")
    let status3xx = Color(hex: "#F5C451")
    let status4xx = Color(hex: "#FF6961")
}
