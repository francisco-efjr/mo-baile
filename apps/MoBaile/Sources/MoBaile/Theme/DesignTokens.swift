import SwiftUI

/// Tokens do design system "Mo baile · macOS 27 / Liquid Glass".
///
/// Os nomes seguem `docs/design/design-system/tokens/colors.css`. A interface é
/// neutra, levemente tingida de azul-marinho (os rótulos são o marinho do ícone
/// com opacidade), e o destaque é o flamingo escurecido `#C2456E`: o `#F389A9`
/// do ícone tem só 2,2:1 com branco e não serve para texto nem para fundo de
/// botão.
///
/// Cada aparência (Claro, Escuro) tem uma variante de Aumentar contraste, que
/// o `ThemeManager` escolhe lendo a preferência de acessibilidade do sistema.
protocol ThemeTokens {
    var name: String { get }
    var id: String { get }
    var isDark: Bool { get }
    var highContrast: Bool { get }

    // Rótulos
    var labelPrimary: Color { get }
    var labelSecondary: Color { get }
    var labelTertiary: Color { get }
    var labelQuaternary: Color { get }

    // Separadores e preenchimentos (separam elementos sobre vidro)
    var separator: Color { get }
    var separatorStrong: Color { get }
    var fillPrimary: Color { get }
    var fillSecondary: Color { get }
    var fillTertiary: Color { get }
    var fillQuaternary: Color { get }

    // Fundos
    var bgWindow: Color { get }
    var bgSidebar: Color { get }
    var bgContent: Color { get }
    var bgContentAlt: Color { get }
    var bgGroup: Color { get }
    var bgControl: Color { get }
    var bgField: Color { get }
    var bgTerminal: Color { get }
    var bgDeviceScreen: Color { get }
    var deviceBezel: Color { get }
    var controlBorder: Color { get }
    var scrim: Color { get }

    // Destaque
    var accent: Color { get }
    var accentHover: Color { get }
    var accentPressed: Color { get }
    var onAccent: Color { get }
    var accentText: Color { get }
    var accentTint: Color { get }
    var focusRing: Color { get }

    // Seleção
    var selection: Color { get }
    var selectionInactive: Color { get }
    var selectionContent: Color { get }

    // Semânticas
    var destructive: Color { get }
    var destructiveFill: Color { get }
    var success: Color { get }
    var successFill: Color { get }
    var successTint: Color { get }
    var warning: Color { get }
    var warningFill: Color { get }
    var warningTint: Color { get }
    var dangerTint: Color { get }
    var info: Color { get }
    var recording: Color { get }

    // Categorias da sidebar
    var cat1: Color { get }
    var cat2: Color { get }
    var cat3: Color { get }

    // Tipos de nó da hierarquia (TypeChip)
    var chipWindow: Color { get }
    var chipView: Color { get }
    var chipText: Color { get }
    var chipInput: Color { get }
    var chipButton: Color { get }

    // Sintaxe
    var syntaxKeyword: Color { get }
    var syntaxFunction: Color { get }
    var syntaxTypeClass: Color { get }
    var syntaxString: Color { get }
    var syntaxNumber: Color { get }
    var syntaxComment: Color { get }
    var syntaxPlain: Color { get }
    var syntaxGutter: Color { get }

    // HTTP
    var httpGet: Color { get }
    var httpPost: Color { get }
    var httpDelete: Color { get }
    var httpConnect: Color { get }
    var status2xx: Color { get }
    var status3xx: Color { get }
    var status4xx: Color { get }
}

extension ThemeTokens {
    /// Cor do método HTTP na tabela e no detalhe.
    func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET", "HEAD", "OPTIONS": return httpGet
        case "POST", "PUT", "PATCH": return httpPost
        case "DELETE": return httpDelete
        case "CONNECT": return httpConnect
        default: return labelPrimary
        }
    }

    /// Cor do status HTTP. Sem status (requisição ainda aberta), terciário.
    func statusColor(_ code: Int?) -> Color {
        guard let code else { return labelTertiary }
        switch code {
        case 400...: return status4xx
        case 300..<400: return status3xx
        default: return status2xx
        }
    }

    func chipColor(_ type: ChipType) -> Color {
        switch type {
        case .window: return chipWindow
        case .view: return chipView
        case .text: return chipText
        case .input: return chipInput
        case .button: return chipButton
        }
    }
}

/// Cores de identidade das plataformas (iguais nas duas aparências).
enum PlatformIdentity {
    static let ios = Color(hex: "#0A84FF")
    static let android = Color(hex: "#34C759")

    static func color(_ platform: Platform) -> Color {
        platform == .ios ? ios : android
    }
}

/// Paleta do terminal da execução de fluxo. O terminal é sempre escuro, nas
/// duas aparências, então as cores não mudam com o tema.
enum TerminalPalette {
    static let text = Color(hex: "#CDD6F4")
    static let dim = Color(hex: "#585B70")
    static let muted = Color(hex: "#7F849C")
    static let info = Color(hex: "#89B4FA")
    static let pass = Color(hex: "#A6E3A1")
    static let warn = Color(hex: "#F9E2AF")
    static let fail = Color(hex: "#F38BA8")
    static let rule = Color.white.opacity(0.08)

    static func color(forPrefix prefix: String) -> Color {
        switch prefix {
        case "INFO", "RUN": return info
        case "PASS": return pass
        case "HTTP", "FA", "STOP": return warn
        case "FAIL": return fail
        default: return text
        }
    }
}

/// Métricas do design system (`tokens/spacing.css` e `tokens/shape.css`).
///
/// Grade de 4 pt. Raios concêntricos: o interno é o externo menos o
/// espaçamento (janela 16 → item de sidebar 8, aparelho 40 → tela 33).
enum DesignMetrics {
    enum Radius {
        static let window: CGFloat = 16
        static let sheet: CGFloat = 16
        static let popover: CGFloat = 14
        static let card: CGFloat = 12
        static let menu: CGFloat = 10
        static let sidebarItem: CGFloat = 8
        static let menuItem: CGFloat = 6
        static let field: CGFloat = 7
        static let row: CGFloat = 6
        static let chip: CGFloat = 4
        static let deviceOuter: CGFloat = 40
        static let deviceScreen: CGFloat = 33
        static let notch: CGFloat = 11
    }

    enum Heights {
        static let toolbar: CGFloat = 52
        static let accessoryBar: CGFloat = 36
        static let statusBar: CGFloat = 22
        static let sidebarBottomBar: CGFloat = 32
        static let paneHeader: CGFloat = 30
        static let detailHeader: CGFloat = 34
        static let editorHeader: CGFloat = 30
        static let codeFooter: CGFloat = 26
        static let attributesPanel: CGFloat = 196
        static let tableRow: CGFloat = 24
        static let controlRegular: CGFloat = 24
        static let controlSmall: CGFloat = 20
        static let controlMini: CGFloat = 16
        static let controlLarge: CGFloat = 28
    }

    enum Widths {
        static let sidebarMin: CGFloat = 232
        static let sidebarIdeal: CGFloat = 240
        static let sidebarMax: CGFloat = 360
        static let inspectorMin: CGFloat = 260
        static let inspectorIdeal: CGFloat = 280
        static let inspectorMax: CGFloat = 380
        static let mirrorMin: CGFloat = 220
        static let mirrorIdeal: CGFloat = 290
        static let mirrorMax: CGFloat = 420
        /// Em Rede e Analytics o espelho fica compacto, como no original.
        static let mirrorCompactMin: CGFloat = 200
        static let mirrorCompactIdeal: CGFloat = 230
        static let mirrorCompactMax: CGFloat = 300
        static let workspaceMin: CGFloat = 360
        static let codeGutter: CGFloat = 34
        static let diagnosticCard: CGFloat = 264
    }

    enum Spacing {
        static let s1: CGFloat = 2
        static let s2: CGFloat = 4
        static let s3: CGFloat = 6
        static let s4: CGFloat = 8
        static let s5: CGFloat = 12
        static let s6: CGFloat = 14
        static let s7: CGFloat = 16
        static let s8: CGFloat = 20
        static let s9: CGFloat = 24
        static let s10: CGFloat = 32
        /// Laterais e base de janelas e formulários.
        static let windowMargin: CGFloat = 20
        static let groupBoxPadding: CGFloat = 16
    }

    enum Window {
        static let defaultSize = CGSize(width: 1280, height: 800)
        /// A toolbar nativa manda o excedente para o menu » e as colunas têm
        /// mínimo próprio, então a janela não precisa mais de 1320 pt de largura
        /// mínima, que era a soma das duas barras antigas.
        static let minSize = CGSize(width: 980, height: 600)
    }

    enum DeviceMirror {
        static let normalSize = CGSize(width: 222, height: 464)
        static let compactSize = CGSize(width: 176, height: 368)
        /// Medidas de referência da moldura de 258 pt; escalam com a largura.
        static let referenceWidth: CGFloat = 258
        static let bezelPadding: CGFloat = 7
        static let notchSize = CGSize(width: 76, height: 20)
        static let notchTop: CGFloat = 9
    }

    static let typeChip: CGFloat = 15
    static let treeIndent: CGFloat = 14
    /// Linha divisória de 1 pt (separador sob o campo, borda inferior de faixa).
    static let hairline: CGFloat = 1

    /// Sombra de painel flutuante (paleta de comandos).
    enum Shadow {
        static let floatingRadius: CGFloat = 24
        static let floatingY: CGFloat = 10
    }

    // MARK: Tokens de componente
    //
    // Terceira camada do design system: medidas específicas de um componente,
    // que não cabem na grade geral. Ficam aqui, e não espalhadas na view, para
    // a auditoria achar tudo num lugar (contrato de componente, C-13).

    /// Paleta de comandos (FLU-1, `CommandPaletteView`).
    enum CommandPalette {
        /// Largura fixa do painel (D3 da `FLUIDEZ_3.5.md`).
        static let width: CGFloat = 560
        /// Distância do topo da janela até o painel: abaixo da toolbar.
        static let topOffset: CGFloat = 56
        static let fieldHeight: CGFloat = 48
        static let footerHeight: CGFloat = 28
        static let listMaxHeight: CGFloat = 380
        /// Coluna do símbolo de cada linha, para os títulos alinharem.
        static let rowIconWidth: CGFloat = 18
        /// Espaço entre símbolo e texto, no campo e nas linhas.
        static let gap: CGFloat = 10
        /// Título e motivo de indisponibilidade quase colados.
        static let titleReasonGap: CGFloat = 1
    }

    /// Faixa do motor (FLU-2, `EngineStatusBannerView`).
    enum EngineBanner {
        static let iconWidth: CGFloat = 18
        static let gap: CGFloat = 10
        static let verticalPadding: CGFloat = 10
    }

    /// Cartão de diagnóstico do estado sem aparelho (FLU-3, `DiagnosticCard`).
    enum DiagnosticCard {
        /// Altura mínima externa: os dois cartões lado a lado ficam iguais.
        static let minHeight: CGFloat = 236
        static let platformDot: CGFloat = 8
        static let checkIconWidth: CGFloat = 14
        /// Aro do cartão "Próximo passo".
        static let recommendedStroke: CGFloat = 1.5
        static let detailGap: CGFloat = 1
    }
}

extension ThemeTokens {
    /// Véu atrás de painel flutuante. Mais leve que `scrim` (que é de sheet):
    /// a janela continua legível por trás da paleta.
    var floatingScrim: Color { Color.black.opacity(isDark ? 0.18 : 0.06) }

    /// Cor da sombra de painel flutuante, igual nas duas aparências.
    var floatingShadow: Color { Color.black.opacity(0.22) }
}

/// Molas no estilo WWDC23 ("Animate with springs").
///
/// *smooth* (0,5 s, sem quique) é o padrão de painéis e sheets; *snappy*
/// (0,35 s, quique 0,15) é para cliques, segmentados e interruptores; o
/// crossfade de 180 ms troca de seção. Com Reduzir movimento, tudo vira
/// crossfade curto.
enum Motion {
    static func smooth(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .linear(duration: 0.18) : .spring(duration: 0.5, bounce: 0)
    }

    static func snappy(reduceMotion: Bool = false) -> Animation {
        reduceMotion ? .linear(duration: 0.15) : .spring(duration: 0.35, bounce: 0.15)
    }

    static let crossfade = Animation.linear(duration: 0.18)
    static let hover = Animation.linear(duration: 0.06)
}

/// Fontes da escala do macOS (`tokens/typography.css`). SF Pro e SF Mono vêm
/// do sistema.
enum DSFont {
    static let largeTitle = Font.system(size: 26, weight: .regular)
    static let title1 = Font.system(size: 22, weight: .regular)
    static let title2 = Font.system(size: 17, weight: .semibold)
    static let title3 = Font.system(size: 15, weight: .semibold)
    static let headline = Font.system(size: 13, weight: .bold)
    static let body = Font.system(size: 13)
    static let callout = Font.system(size: 12)
    static let subheadline = Font.system(size: 11)
    static let subheadlineSemibold = Font.system(size: 11, weight: .semibold)
    static let footnote = Font.system(size: 10)

    /// Símbolos SF ao lado de texto. O tamanho acompanha o texto vizinho.
    enum Symbol {
        /// Ao lado de campo grande (⌘ do campo da paleta).
        static let field = Font.system(size: 15, weight: .medium)
        /// Ao lado de título de faixa ou alerta.
        static let banner = Font.system(size: 15, weight: .semibold)
        /// Ao lado de texto do corpo (linhas da paleta).
        static let body = Font.system(size: 13)
        /// Ao lado de texto pequeno (checagens do diagnóstico).
        static let small = Font.system(size: 12, weight: .semibold)
    }

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Convenience Color extension for hex initialization
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// `rgba(r, g, b, a)` como na CSS do design system.
    init(r: Double, g: Double, b: Double, _ opacity: Double = 1) {
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: opacity)
    }

    /// O marinho do ícone (`#141543`) com opacidade: base dos rótulos,
    /// separadores e preenchimentos da aparência clara.
    static func navy(_ opacity: Double) -> Color {
        Color(r: 20, g: 21, b: 67, opacity)
    }

    static func white(_ opacity: Double) -> Color {
        Color(r: 255, g: 255, b: 255, opacity)
    }

    /// Convert to NSColor for AppKit interop
    var nsColor: NSColor {
        NSColor(self)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1.0
        )
    }
}
