import SwiftUI

struct PraiaDarkTheme: ThemeTokens {
    let name = "dark"
    let id = "praia_dark"
    
    // Backgrounds
    let bgWindow = Color(hex: "#1E1E2E")
    let bgToolbar = Color(hex: "#181825")
    let bgPanel = Color(hex: "#181825")
    let bgPanelAlt = Color(hex: "#1E1E2E")
    let bgContent = Color(hex: "#1E1E2E")
    let bgSubtle = Color(hex: "#181825")
    let bgControl = Color(hex: "#11111B")
    let bgControlTrack = Color(hex: "#313244")
    let bgPlaceholder = Color(hex: "#1F1F30")
    let bgTerminal = Color(hex: "#0B0B12")
    let bgDeviceScreen = Color(hex: "#151520")
    let deviceBezel = Color(hex: "#11111B")
    
    // Borders
    let border = Color(hex: "#313244")
    let borderSubtle = Color(hex: "#26263A")
    let borderStrong = Color(hex: "#45475A")
    
    // Text
    let textPrimary = Color(hex: "#CDD6F4")
    let textSecondary = Color(hex: "#A6ADC8")
    let textTertiary = Color(hex: "#7F849C")
    let textLabel = Color(hex: "#6C7086")
    let textDisabled = Color(hex: "#585B70")
    
    // Accents
    let accent = Color(hex: "#89B4FA")
    let accentPressed = Color(hex: "#74A6F5")
    let accentOn = Color(hex: "#11111B")
    
    // Selection
    let selectionBg = Color(hex: "#283248")
    let selectionBorder = Color(hex: "#4A608A")
    
    // Semantic
    let success = Color(hex: "#A6E3A1")
    let successText = Color(hex: "#A6E3A1")
    let successBg = Color(hex: "#1B332A")
    let warning = Color(hex: "#F9E2AF")
    let warningText = Color(hex: "#F9E2AF")
    let warningBg = Color(hex: "#383020")
    let danger = Color(hex: "#F38BA8")
    
    // Syntax highlighting
    let syntaxKeyword = Color(hex: "#CBA6F7")
    let syntaxFunction = Color(hex: "#89B4FA")
    let syntaxTypeClass = Color(hex: "#F9E2AF")
    let syntaxString = Color(hex: "#A6E3A1")
    let syntaxNumber = Color(hex: "#FAB387")
    let syntaxComment = Color(hex: "#6C7086")
    let syntaxPlain = Color(hex: "#CDD6F4")
    let syntaxGutter = Color(hex: "#45475A")
    let syntaxGutterBg = Color(hex: "#181825")
    let fileTitleActions = Color(hex: "#89B4FA")
    let fileTitleLocators = Color(hex: "#94E2D5")
}
