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
    case id, xpath, coords
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .id: return "ID"
        case .xpath: return "XPath"
        case .coords: return "Coords"
        }
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
/// Antes o clique so selecionava o elemento na arvore; repassar o toque e
/// gravar o passo, que sao as duas razoes de existir da ferramenta, nao tinham
/// caminho na interface nativa.
enum InteractionMode: String, CaseIterable, Identifiable, Sendable {
    case inspect
    case forward
    case record

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inspect: return "Inspecionar"
        case .forward: return "Repassar toque"
        case .record: return "Gravar passo"
        }
    }

    var symbolName: String {
        switch self {
        case .inspect: return "cursorarrow.rays"
        case .forward: return "hand.tap"
        case .record: return "record.circle"
        }
    }
}
