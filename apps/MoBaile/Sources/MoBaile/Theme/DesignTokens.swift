import SwiftUI

/// Design token protocol defining all visual properties for a theme
protocol ThemeTokens {
    var name: String { get }
    var id: String { get }
    
    // Backgrounds
    var bgWindow: Color { get }
    var bgToolbar: Color { get }
    var bgPanel: Color { get }
    var bgPanelAlt: Color { get }
    var bgContent: Color { get }
    var bgSubtle: Color { get }
    var bgControl: Color { get }
    var bgControlTrack: Color { get }
    var bgPlaceholder: Color { get }
    var bgTerminal: Color { get }
    var bgDeviceScreen: Color { get }
    var deviceBezel: Color { get }
    
    // Borders
    var border: Color { get }
    var borderSubtle: Color { get }
    var borderStrong: Color { get }
    
    // Text
    var textPrimary: Color { get }
    var textSecondary: Color { get }
    var textTertiary: Color { get }
    var textLabel: Color { get }
    var textDisabled: Color { get }
    
    // Accents
    var accent: Color { get }
    var accentPressed: Color { get }
    var accentOn: Color { get }
    
    // Selection
    var selectionBg: Color { get }
    var selectionBorder: Color { get }
    
    // Semantic
    var success: Color { get }
    var successText: Color { get }
    var successBg: Color { get }
    var warning: Color { get }
    var warningText: Color { get }
    var warningBg: Color { get }
    var danger: Color { get }
    
    // Syntax highlighting
    var syntaxKeyword: Color { get }
    var syntaxFunction: Color { get }
    var syntaxTypeClass: Color { get }
    var syntaxString: Color { get }
    var syntaxNumber: Color { get }
    var syntaxComment: Color { get }
    var syntaxPlain: Color { get }
    var syntaxGutter: Color { get }
    var syntaxGutterBg: Color { get }
    var fileTitleActions: Color { get }
    var fileTitleLocators: Color { get }
}

/// Platform identity colors (NOT theme-dependent)
enum PlatformIdentity {
    static let ios = Color(hex: "#0A84FF")
    static let android = Color(hex: "#34C759")
}

/// Traffic light colors
enum TrafficLights {
    static let close = Color(hex: "#FF5F57")
    static let minimize = Color(hex: "#FEBC2E")
    static let zoom = Color(hex: "#28C840")
}

/// Shared metrics from the design spec
enum DesignMetrics {
    enum Radius {
        static let segmentItem: CGFloat = 6
        static let control: CGFloat = 8
        static let field: CGFloat = 7
        static let card: CGFloat = 12
        static let panelCard: CGFloat = 9
        static let modal: CGFloat = 14
        static let deviceOuter: CGFloat = 40
        static let deviceScreen: CGFloat = 33
        static let notch: CGFloat = 11
        static let pillBadge: CGFloat = 5
    }
    
    enum Heights {
        static let toolbar: CGFloat = 52
        static let panelHeader: CGFloat = 34
        static let tabBar: CGFloat = 40
        static let editorHeader: CGFloat = 30
        static let elementDetailsFooter: CGFloat = 38
        static let statusBar: CGFloat = 26
        static let modalHeader: CGFloat = 44
        static let modalFooter: CGFloat = 52
        static let toggleTrack: CGFloat = 20
        static let collapsedRailWidth: CGFloat = 30
    }
    
    enum Widths {
        static let panelDevice: CGFloat = 376
        static let panelDeviceMin: CGFloat = 340
        static let panelDeviceCompact: CGFloat = 280
        static let panelHierarchy: CGFloat = 290
        static let panelHierarchyMin: CGFloat = 260
        static let workspaceMin: CGFloat = 520
        static let codeGutter: CGFloat = 34
        static let deviceDropdownMin: CGFloat = 210
    }
    
    enum Padding {
        static let toolbarX: CGFloat = 16
        static let panelX: CGFloat = 14
        static let editorX: CGFloat = 12
        static let tableRowY: CGFloat = 7
        static let modalX: CGFloat = 16
    }
    
    enum Gaps {
        static let toolbarItems: CGFloat = 14
        static let toolbarGroup: CGFloat = 8
        static let segmentItems: CGFloat = 2
        static let panelStack: CGFloat = 9
        static let cardGrid: CGFloat = 14
    }
    
    enum Toggle {
        static let trackSize = CGSize(width: 34, height: 20)
        static let knobSize: CGFloat = 16
    }
    
    static let dotStatus: CGFloat = 6
    static let typeChip: CGFloat = 15
    static let treeIndent: CGFloat = 18
    
    enum Window {
        static let defaultSize = CGSize(width: 1440, height: 900)
        // A barra superior somada pede cerca de 1380 pontos e as tres colunas
        // pedem 980. Em 1100 a janela abria com os controles das pontas
        // cortados pela borda, que era o estado em que dava para redimensionar.
        static let minSize = CGSize(width: 1320, height: 720)
    }
    
    enum DeviceMirror {
        static let normalSize = CGSize(width: 258, height: 540)
        static let compactSize = CGSize(width: 186, height: 390)
        static let bezelPadding: CGFloat = 7
        static let notchSize = CGSize(width: 76, height: 20)
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
