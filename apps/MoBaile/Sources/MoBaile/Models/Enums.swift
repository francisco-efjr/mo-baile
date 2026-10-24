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

    static let defaultKey = "mobaile.seletorPadrao"

    /// Estratégia escolhida em Ajustes › Geral › Seletor padrão.
    static var storedDefault: LocatorStrategy {
        UserDefaults.standard.string(forKey: defaultKey).flatMap(LocatorStrategy.init(rawValue:)) ?? .auto
    }

    /// Nome do lado do motor. A interface chama de `coords` o que o contrato
    /// chama de `position`.
    var engineName: String {
        self == .coords ? "position" : rawValue
    }
}

enum WorkspaceTab: String, CaseIterable, Identifiable, Sendable {
    case home, pageObjects, network, analytics, report
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .home: return "Início"
        case .pageObjects: return "Page Objects"
        case .network: return "Rede HTTP"
        case .analytics: return "Analytics"
        case .report: return "Relatório"
        }
    }

    /// Início e Relatório funcionam sem aparelho: um mostra o ambiente, o
    /// outro trabalha com arquivos (spec e log). As outras áreas precisam de
    /// um conectado.
    var needsDevice: Bool { self != .report && self != .home }

    /// As áreas de trabalho, sem o Início: a seção Workspace da barra lateral.
    static var workspaceAreas: [WorkspaceTab] { allCases.filter { $0 != .home } }

    /// Atalho de teclado: ⌘0 no Início e ⌘1 a ⌘4 nas áreas, na ordem da
    /// barra lateral. O Início entrou depois e ficou com o 0 para as áreas
    /// manterem os atalhos que as pessoas já usam.
    var shortcutDigit: Character {
        Character("\(WorkspaceTab.allCases.firstIndex(of: self) ?? 0)")
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


/// O que uma confirmação de limpeza apaga.
enum ClearKind: String, Identifiable, Sendable {
    case network, analytics, steps
    var id: String { rawValue }
}
