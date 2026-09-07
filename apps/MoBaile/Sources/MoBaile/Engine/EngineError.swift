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
        }
    }

    /// `true` quando a falha e do ambiente e vale sugerir um conserto ao usuario.
    var isRecoverableBySetup: Bool {
        switch self {
        case .engineNotFound, .notRunning, .processTerminated: return true
        case .engine, .protocolViolation: return false
        }
    }
}
