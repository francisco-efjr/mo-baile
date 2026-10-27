import Foundation

/// `home.summary`: o que a tela Início mostra. Quem decide o estado (primeira
/// vez ou dia a dia), a contagem do ambiente, o que cada pendência bloqueia e
/// os alvos é o motor (`engine/src/mobaile/services/home.py`); aqui só se
/// desenha.
extension EngineDTO {

    struct HomeSummary: Decodable, Equatable {
        /// `first_run` ou `daily`.
        let state: String
        let python: Setup.PythonInfo
        let environment: HomeEnvironment
        let platforms: [HomePlatform]
        let suggestedPlatform: String?
        let targets: [HomeTarget]
        let recent: [HomeRecent]
        let whatsNew: HomeWhatsNew?

        enum CodingKeys: String, CodingKey {
            case state, python, environment, platforms, targets, recent
            case suggestedPlatform = "suggested_platform"
            case whatsNew = "whats_new"
        }

        var isFirstRun: Bool { state == "first_run" }

        /// A pendência pelo id, para a linha de aviso de um alvo.
        func pending(_ id: String) -> HomePending? {
            environment.pending.first { $0.id == id }
        }
    }

    struct HomeEnvironment: Decodable, Equatable {
        let ready: Int
        let total: Int
        let pending: [HomePending]

        var isReady: Bool { pending.isEmpty }
    }

    struct HomePending: Decodable, Equatable, Identifiable {
        struct Block: Decodable, Equatable {
            /// Área do contrato (`page_objects`…) ou `*` para a plataforma toda.
            let area: String
            let platform: String
            let effect: String
        }

        let id: String
        let title: String
        let install: String?
        let link: String?
        let blocks: [Block]
    }

    struct HomePlatform: Decodable, Equatable, Identifiable {
        let platform: String
        let ready: Bool
        let found: [String]
        let missing: [String]
        let install: String
        let link: String?

        var id: String { platform }
    }

    struct HomeTarget: Decodable, Equatable, Identifiable {
        struct Capabilities: Decodable, Equatable {
            let mirror: Bool
            let tap: Bool
            let record: Bool
        }

        let id: String
        let name: String
        let platform: String
        /// `simulator`, `emulator` ou `physical`.
        let kind: String
        let running: Bool
        let connected: Bool
        let capabilities: Capabilities
        let blockedBy: [String]

        enum CodingKeys: String, CodingKey {
            case id, name, platform, kind, running, connected, capabilities
            case blockedBy = "blocked_by"
        }

        var appPlatform: Platform { platform == "ios" ? .ios : .android }
    }

    struct HomeRecent: Decodable, Equatable, Identifiable {
        /// `flow`, `maestro`, `report` ou `page_object`.
        let kind: String
        let title: String
        let subtitle: String
        let path: String
        /// Epoch, em segundos.
        let at: Double

        var id: String { path }
        var date: Date { Date(timeIntervalSince1970: at) }
    }

    struct HomeWhatsNew: Decodable, Equatable {
        let version: String
        let items: [String]
    }
}
