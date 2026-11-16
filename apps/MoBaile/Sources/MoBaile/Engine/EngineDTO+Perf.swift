import Foundation

/// `perf.status`, `perf.signals`, `perf.set_preference` e a notificação
/// `perf.profile` (PERF-3). Quem decide o perfil é o motor
/// (`engine/src/mobaile/services/perf.py`); aqui só se lê o que vale para a
/// interface: perfil, motivo, preferência e a parte visual dos knobs.
extension EngineDTO {

    struct PerfStatus: Decodable, Equatable {
        /// `completo`, `equilibrado` ou `leve`.
        let profile: String
        /// `manual`, `thermal_serious`, `low_power`… (ver PROTOCOLO_RPC.md).
        let reason: String
        /// `auto`, `completo`, `equilibrado` ou `leve`.
        let preference: String
        let knobs: PerfKnobs
    }

    struct PerfKnobs: Decodable, Equatable {
        /// Vidro próprio do design system (ADR 0006). Falso no leve.
        let vidro: Bool
        /// Molas do `Motion`. Falso no leve.
        let animacoes: Bool
        let streamFps: Double

        enum CodingKeys: String, CodingKey {
            case vidro = "glass"
            case animacoes = "animations"
            case streamFps = "stream_fps"
        }
    }
}
