import Foundation

/// Falhas da fronteira com o motor, na granularidade que a interface precisa
/// para decidir entre exibir dialogo, apenas registrar ou tentar de novo.
enum EngineError: LocalizedError, Equatable {
    /// Nao ha Python ou o motor nao foi encontrado no disco.
    case engineNotFound(String)
    /// O processo do motor nao esta no ar.
    case notRunning
    /// O processo encerrou sozinho.
    case processTerminated(Int32)
    /// O motor respondeu com um erro de dominio (`data.code` do JSON-RPC).
    case engine(code: String, message: String)
    /// Erro de protocolo: resposta que nao casa com o contrato.
    case protocolViolation(String)
    /// A chamada passou do `timeout_s` que o motor declarou no handshake.
    ///
    /// Antes nao havia prazo: uma chamada que o motor nunca respondia deixava
    /// a interface com spinner eterno. Agora ela falha com nome e prazo, e o
    /// cliente ja avisou o motor com `$/cancelRequest`.
    case timeout(method: String, seconds: Double)
    /// A chamada foi cancelada (pelo prazo, pela tarefa que esperava ou pelo
    /// encerramento pedido). Nao e falha a mostrar: quem cancelou ja sabe.
    case cancelled
    /// O motor fala outra versao do protocolo. A mensagem cita as duas.
    case incompatibleProtocol(String)

    var errorDescription: String? {
        switch self {
        case .engineNotFound(let detail):
            return "Motor do Mo baile nao encontrado. \(detail)"
        case .notRunning:
            return "O motor nao esta em execucao."
        case .processTerminated(let status):
            return "O motor encerrou inesperadamente (codigo \(status))."
        case .engine(_, let message):
            return message
        case .protocolViolation(let detail):
            return "Resposta fora do contrato: \(detail)"
        case .timeout(let method, let seconds):
            let prazo = seconds.rounded() == seconds ? String(Int(seconds)) : String(format: "%.1f", seconds)
            return "O motor não respondeu a \(method) em \(prazo) s. A chamada foi cancelada."
        case .cancelled:
            return "Chamada cancelada."
        case .incompatibleProtocol(let message):
            return message
        }
    }

    /// `true` quando a falha e do ambiente e vale sugerir um conserto ao usuario.
    var isRecoverableBySetup: Bool {
        switch self {
        case .engineNotFound, .notRunning, .processTerminated, .incompatibleProtocol: return true
        case .engine, .protocolViolation, .timeout, .cancelled: return false
        }
    }
}
