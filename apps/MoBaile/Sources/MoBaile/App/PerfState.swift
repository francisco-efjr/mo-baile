import Foundation

/// Preferência de desempenho escolhida em Ajustes › Desempenho (PERF-5).
/// Fica no `UserDefaults` e vai ao motor a cada conexão; o motor decide o
/// perfil efetivo.
enum PerfPreference: String, CaseIterable, Identifiable, Sendable {
    case auto, completo, equilibrado, leve

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Automático"
        case .completo: return "Completo"
        case .equilibrado: return "Equilibrado"
        case .leve: return "Leve"
        }
    }

    static let storageKey = "mobaile.desempenho.preferencia"

    static var stored: PerfPreference {
        UserDefaults.standard.string(forKey: storageKey).flatMap(PerfPreference.init(rawValue:)) ?? .auto
    }

    func store() { UserDefaults.standard.set(rawValue, forKey: Self.storageKey) }
}

/// O perfil de desempenho como a interface o vê.
struct PerfState: Equatable {
    var profile = "completo"
    var reason = "sinais_normais"
    var preference = PerfPreference.stored
    /// Parte visual que o motor mandou (`knobs.glass` e `knobs.animations`).
    var vidro = true
    var animacoes = true
    /// Freio local: o motor não respondeu aos sinais. O Swift aplica sozinho a
    /// parte visual do leve, sem decidir perfil nenhum.
    var semMotor = false

    var reducesGlass: Bool { semMotor || !vidro }
    var reducesMotion: Bool { semMotor || !animacoes }

    /// O que o badge da barra de status mostra; nada no completo.
    var badge: String? {
        if semMotor { return "leve" }
        return profile == "completo" ? nil : profile
    }

    /// Automático: o motor escolheu por um sinal do Mac (não pela pessoa).
    var isAutomatic: Bool { semMotor || reason != "manual" }

    /// Motivo em linguagem natural, para o tooltip e o VoiceOver.
    var reasonText: String {
        if semMotor { return "o motor não respondeu" }
        switch reason {
        case "manual": return "escolhido em Ajustes"
        case "thermal_fair": return "Mac aquecendo"
        case "thermal_serious", "thermal_critical": return "Mac quente"
        case "low_power": return "Economia de Energia ligada"
        case "memory_warning", "memory_critical": return "memória do Mac apertada"
        case "hardware_modesto": return "Mac com poucos recursos"
        case "recuperando": return "voltando ao normal"
        default: return "sinais normais"
        }
    }

    /// "modo leve: Mac quente".
    var summary: String { "modo \(badge ?? profile): \(reasonText)" }
}
