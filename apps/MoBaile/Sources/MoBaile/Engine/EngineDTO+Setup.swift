import Foundation

/// `setup.check`: o que está instalado nesta máquina e o que cada área precisa.
/// Alimenta a tela Início. A decisão (o que é obrigatório, o próximo passo, o
/// estado de cada área) é do motor, em `engine/src/mobaile/services/setup.py`;
/// aqui só se desenha.
extension EngineDTO {

    struct Setup: Decodable, Equatable {
        struct PythonInfo: Decodable, Equatable {
            let version: String
            let path: String
        }

        let system: String
        let python: PythonInfo
        let groups: [SetupGroup]
        let features: [SetupFeature]
        /// Obrigatórios que faltam (a contagem do Início na barra lateral).
        let pending: Int
        let nextStep: SetupNextStep?

        enum CodingKeys: String, CodingKey {
            case system, python, groups, features, pending
            case nextStep = "next_step"
        }

        func component(_ id: String) -> SetupComponent? {
            groups.lazy.flatMap(\.components).first { $0.id == id }
        }

        func feature(_ id: String) -> SetupFeature? {
            features.first { $0.id == id }
        }
    }

    struct SetupGroup: Decodable, Equatable, Identifiable {
        let id: String
        let title: String
        let components: [SetupComponent]
    }

    struct SetupComponent: Decodable, Equatable, Identifiable {
        let id: String
        let label: String
        let state: String
        let detail: String
        let required: Bool
        /// Alvo de `tools/setup/instalar-mac.sh` que resolve, quando há.
        let install: String?
        /// Página a abrir quando não há script (Xcode, Android Studio).
        let link: String?
        let neededFor: String

        enum CodingKeys: String, CodingKey {
            case id, label, state, detail, required, install, link
            case neededFor = "needed_for"
        }

        var daemonState: DaemonState { DaemonState(engineState: state) }
    }

    struct SetupFeature: Decodable, Equatable, Identifiable {
        struct PlatformState: Decodable, Equatable {
            /// `ios`, `android` ou `any` (o Relatório não depende de aparelho).
            let platform: String
            let state: String
            let detail: String

            var daemonState: DaemonState { DaemonState(engineState: state) }
        }

        /// `page_objects`, `network`, `analytics` ou `report`.
        let id: String
        let platforms: [PlatformState]

        /// A aba do app que corresponde a esta área.
        var tab: WorkspaceTab? {
            switch id {
            case "page_objects": return .pageObjects
            case "network": return .network
            case "analytics": return .analytics
            case "report": return .report
            default: return nil
            }
        }
    }

    struct SetupNextStep: Decodable, Equatable {
        let component: String
        let label: String
        let detail: String
        let install: String?
        let link: String?
    }
}

extension DaemonState {
    /// Estado como o motor escreve (`ok`, `warn`, `error`, `busy`, `off`).
    init(engineState: String) {
        self = DaemonState(rawValue: engineState) ?? .off
    }
}
