import Foundation

enum Platform: String, CaseIterable, Identifiable, Codable, Sendable {
    case ios, android
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }
}

enum LocatorStrategy: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Deixa o motor escolher o localizador mais robusto que seja único na tela
    /// atual. Uma estratégia fixa para a sessão inteira produz passo instável:
    /// o mesmo `resource-id` pode casar com vários elementos, e aí o teste
    /// depende de qual deles o Appium encontre primeiro.
    case auto
    case id, xpath, coords

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .id: return "ID"
        case .xpath: return "XPath"
        case .coords: return "Coords"
        }
    }

    /// Nome do lado do motor. A interface chama de `coords` o que o contrato
    /// chama de `position`.
    var engineName: String {
        self == .coords ? "position" : rawValue
    }
}

enum WorkspaceTab: String, CaseIterable, Identifiable, Sendable {
    case pageObjects, network, analytics
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .pageObjects: return "Page Objects"
        case .network: return "Rede HTTP"
        case .analytics: return "Analytics"
        }
    }
}

enum RunState: Equatable, Sendable {
    case idle, running, passed, failed
}

enum DaemonState: String, Sendable {
    case ok, busy, warn, error, off
}

enum ChipType: String, Sendable {
    case window = "W"
    case view = "V"
    case text = "T"
    case input = "I"
    case button = "B"
}

enum ThemeMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, light, dark
    var id: String { rawValue }
}


/// O que um clique no espelho significa.
///
/// Eram tres modos. "Inspecionar" saiu: o painel de atributos ja e preenchido
/// em qualquer modo, entao ele nao fazia nada que os outros dois nao fizessem,
/// e ocupava espaco na barra obrigando a trocar de modo a toa.
enum InteractionMode: String, CaseIterable, Identifiable, Sendable {
    case forward
    case record

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forward: return "Repassar toque"
        case .record: return "Gravar passo"
        }
    }

    var symbolName: String {
        switch self {
        case .forward: return "hand.tap"
        case .record: return "record.circle"
        }
    }
}
