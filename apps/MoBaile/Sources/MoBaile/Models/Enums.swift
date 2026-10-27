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
    case home, pageObjects, network, analytics, report, environment
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .home: return "Início"
        case .pageObjects: return "Page Objects"
        case .network: return "Rede HTTP"
        case .analytics: return "Analytics"
        case .report: return "Relatório"
        case .environment: return "Ambiente"
        }
    }

    /// Início, Relatório e Ambiente funcionam sem aparelho: o Início recebe e
    /// oferece os alvos, o Relatório trabalha com arquivos (spec e log) e o
    /// Ambiente mostra o que está instalado. As outras áreas precisam de um
    /// aparelho conectado.
    var needsDevice: Bool { ![.home, .report, .environment].contains(self) }

    /// As áreas de trabalho: a seção Workspace da barra lateral. O Início fica
    /// acima dela e o Ambiente, fixo no rodapé.
    static var workspaceAreas: [WorkspaceTab] { allCases.filter { $0 != .home && $0 != .environment } }

    /// Atalho de teclado: ⌘0 no Início, ⌘1 a ⌘4 nas áreas, na ordem da barra
    /// lateral, e ⌘5 no Ambiente (3.11.0). O ⌘, continua nos Ajustes.
    var shortcutDigit: Character {
        Character("\(WorkspaceTab.allCases.firstIndex(of: self) ?? 0)")
    }
}

/// Parada pedida pelo usuário não é caso próprio: volta a `.idle`, com a
/// linha `STOP` no log (D-A da rodada 3.12.0).
enum RunState: Equatable, Sendable {
    case idle, running, passed, failed
}

/// Quem disparou a execução. Só `flow.run` roda os passos gravados; no flow do
/// Maestro a lista de passos gravados não corresponde ao que está rodando.
enum RunSource: Equatable, Sendable {
    case recordedSteps, maestro
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
