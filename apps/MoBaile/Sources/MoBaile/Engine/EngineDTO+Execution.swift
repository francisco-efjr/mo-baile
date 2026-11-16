import Foundation

/// `project.*` e `run.*`: a aba Execução (B1, 3.23.0). Contrato em
/// `docs/PROTOCOLO_RPC.md`, seções "Projeto de automação do dono" e "Rodar o
/// `main`". O motor analisa e roda; aqui só se decodifica e desenha.
///
/// Os campos que o protocolo diz opcionais (ou que só existem desde a B1-4)
/// são decodificados com valor padrão: um motor um pouco mais velho ou mais
/// novo não pode deixar a aba vazia por causa de um campo a menos.
extension EngineDTO {

    // MARK: - Registro de projetos

    struct Project: Decodable, Equatable, Identifiable, Sendable {
        let id: String
        /// Caminho real da pasta do projeto.
        let root: String
        let name: String
        /// Arquivo de entrada relativo à raiz, ou `nil` quando o motor não achou.
        let entry: String?
        let trusted: Bool
        let openedAt: Double?
        /// O que o dono escolheu em `project.configure` (B1-4).
        let interpreterOverride: String?
        let entryOverride: String?

        enum CodingKeys: String, CodingKey {
            case id, root, name, entry, trusted
            case openedAt = "opened_at"
            case interpreterOverride = "interpreter_override"
            case entryOverride = "entry_override"
        }

        init(id: String, root: String, name: String, entry: String?, trusted: Bool,
             openedAt: Double? = nil, interpreterOverride: String? = nil, entryOverride: String? = nil) {
            self.id = id
            self.root = root
            self.name = name
            self.entry = entry
            self.trusted = trusted
            self.openedAt = openedAt
            self.interpreterOverride = interpreterOverride
            self.entryOverride = entryOverride
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            root = try c.decode(String.self, forKey: .root)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? (root as NSString).lastPathComponent
            entry = try c.decodeIfPresent(String.self, forKey: .entry)
            trusted = try c.decodeIfPresent(Bool.self, forKey: .trusted) ?? false
            openedAt = try c.decodeIfPresent(Double.self, forKey: .openedAt)
            interpreterOverride = try c.decodeIfPresent(String.self, forKey: .interpreterOverride)
            entryOverride = try c.decodeIfPresent(String.self, forKey: .entryOverride)
        }
    }

    struct ProjectOpened: Decodable, Equatable {
        let project: Project
    }

    struct ProjectList: Decodable, Equatable {
        let projects: [Project]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        }

        enum CodingKeys: String, CodingKey { case projects }
    }

    struct ProjectForgotten: Decodable, Equatable {
        let removed: Bool
    }

    /// `project.trust`: o projeto já confiável. Tolerante ao formato (o item
    /// pode vir em `project` ou não vir).
    struct ProjectTrusted: Decodable, Equatable {
        let project: Project?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            project = try? c.decodeIfPresent(Project.self, forKey: .project)
        }

        enum CodingKeys: String, CodingKey { case project }
    }

    /// Onde o hub da config roda, para o selo e a trava do Rodar.
    enum HubState: String, Equatable, Sendable {
        case local, cloud, unknown

        /// `cloud` ganha de tudo. Sem `hub_state` (motor anterior à revisão),
        /// local. Um valor que este front não conhece vira "Não confirmado",
        /// nunca "Local": o selo de segurança falha fechado (revisão FR-09).
        init(rawValue: String?, cloud: Bool) {
            if cloud { self = .cloud; return }
            guard let rawValue else { self = .local; return }
            self = HubState(rawValue: rawValue) ?? .unknown
        }

        var label: String {
            switch self {
            case .local: return "Local"
            case .cloud: return "Nuvem (bloqueada)"
            case .unknown: return "Não confirmado"
            }
        }
    }

    // MARK: - Análise estática (`project.inspect` e `project.configure`)

    struct ProjectInspection: Decodable, Equatable {
        struct Entry: Decodable, Equatable {
            let file: String?
            let function: String?
            let found: Bool

            init(file: String?, function: String?, found: Bool) {
                self.file = file
                self.function = function
                self.found = found
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                file = try c.decodeIfPresent(String.self, forKey: .file)
                function = try c.decodeIfPresent(String.self, forKey: .function)
                found = try c.decodeIfPresent(Bool.self, forKey: .found) ?? (file != nil)
            }

            enum CodingKeys: String, CodingKey { case file, function, found }
        }

        struct Candidate: Decodable, Equatable, Identifiable {
            let path: String
            let version: String?
            /// Versão do behave instalada nesse Python, ou `nil`.
            let behave: String?

            var id: String { path }
        }

        struct Interpreter: Decodable, Equatable {
            let path: String?
            /// `manual`, `run_configuration`, `pycharm_sdk`, `venv` ou `nil`.
            let source: String?
            let exists: Bool
            let candidates: [Candidate]

            init(path: String?, source: String?, exists: Bool, candidates: [Candidate] = []) {
                self.path = path
                self.source = source
                self.exists = exists
                self.candidates = candidates
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                path = try c.decodeIfPresent(String.self, forKey: .path)
                source = try c.decodeIfPresent(String.self, forKey: .source)
                exists = try c.decodeIfPresent(Bool.self, forKey: .exists) ?? false
                candidates = try c.decodeIfPresent([Candidate].self, forKey: .candidates) ?? []
            }

            enum CodingKeys: String, CodingKey { case path, source, exists, candidates }

            /// Há um interpretador que o motor consegue usar.
            var usable: Bool { path != nil && exists }
            var isManual: Bool { source == "manual" }
        }

        struct RunConfiguration: Decodable, Equatable {
            let name: String?
            let file: String?
            /// Só os nomes: os valores das `envs` nunca saem do motor.
            let envNames: [String]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decodeIfPresent(String.self, forKey: .name)
                file = try c.decodeIfPresent(String.self, forKey: .file)
                envNames = try c.decodeIfPresent([String].self, forKey: .envNames) ?? []
            }

            enum CodingKeys: String, CodingKey {
                case name, file
                case envNames = "env_names"
            }
        }

        struct Config: Decodable, Equatable, Identifiable {
            let name: String
            let active: Bool
            let found: Bool
            let file: String?
            let line: Int?
            /// `android`, `ios` ou `nil`.
            let platform: String?
            /// Só as chaves permitidas, sem o prefixo `appium:`.
            let values: [String: String]
            /// `host:porta`, `"dinâmico"` ou `nil`.
            let hub: String?
            let cloud: Bool
            /// `local`, `cloud` ou `unknown` (revisão da B1). Motor anterior não
            /// manda: aí vale `cloud`.
            let hubState: String?
            /// Todos os nomes de chave, como estão no arquivo.
            let keys: [String]

            var id: String { "\(name)#\(line ?? 0)#\(active)" }

            /// O selo da config: Local, Nuvem (bloqueada) ou Não confirmado.
            var hubKind: HubState { HubState(rawValue: hubState, cloud: cloud) }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? false
                found = try c.decodeIfPresent(Bool.self, forKey: .found) ?? true
                file = try c.decodeIfPresent(String.self, forKey: .file)
                line = try c.decodeIfPresent(Int.self, forKey: .line)
                platform = try c.decodeIfPresent(String.self, forKey: .platform)
                // O motor só manda texto, mas um número literal não pode
                // derrubar a análise inteira.
                if let texto = try? c.decodeIfPresent([String: String].self, forKey: .values) {
                    values = texto
                } else if let brutos = try? c.decodeIfPresent([String: JSONValue].self, forKey: .values) {
                    values = brutos.mapValues(Self.text)
                } else {
                    values = [:]
                }
                hub = try c.decodeIfPresent(String.self, forKey: .hub)
                cloud = try c.decodeIfPresent(Bool.self, forKey: .cloud) ?? false
                hubState = try c.decodeIfPresent(String.self, forKey: .hubState)
                keys = try c.decodeIfPresent([String].self, forKey: .keys) ?? []
            }

            enum CodingKeys: String, CodingKey {
                case name, active, found, file, line, platform, values, hub, cloud, keys
                case hubState = "hub_state"
            }

            private static func text(_ valor: JSONValue) -> String {
                switch valor {
                case .string(let s): return s
                case .int(let i): return String(i)
                case .double(let d): return String(d)
                case .bool(let b): return b ? "True" : "False"
                case .null: return "None"
                case .array, .object: return "dinâmico"
                }
            }

            /// Ordem em que as chaves aparecem: a da lista de permitidas do
            /// contrato, e depois o resto em ordem alfabética.
            static let valueOrder = ["platformName", "automationName", "udid", "deviceName", "platformVersion",
                                     "app", "appPackage", "appActivity", "bundleId"]

            var orderedValues: [(key: String, value: String)] {
                values.sorted { a, b in
                    let ia = Self.valueOrder.firstIndex(of: a.key) ?? Int.max
                    let ib = Self.valueOrder.firstIndex(of: b.key) ?? Int.max
                    return ia == ib ? a.key < b.key : ia < ib
                }
                .map { (key: $0.key, value: $0.value) }
            }

            /// Chaves que aparecem só pelo nome (as sensíveis estão aqui): todas
            /// menos as que já têm valor e a URL do hub.
            var nameOnlyKeys: [String] {
                keys.filter { chave in
                    let semPrefixo = chave.hasPrefix("appium:") ? String(chave.dropFirst("appium:".count)) : chave
                    return values[semPrefixo] == nil && chave != "url" && chave.lowercased() != "command_executor"
                }
            }
        }

        struct Run: Decodable, Equatable {
            let squad: String?
            let feature: String?
            let line: Int?
            let found: Bool
            let path: String?
            let title: String?
            let scenarios: [String]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                squad = try c.decodeIfPresent(String.self, forKey: .squad)
                feature = try c.decodeIfPresent(String.self, forKey: .feature)
                line = try c.decodeIfPresent(Int.self, forKey: .line)
                found = try c.decodeIfPresent(Bool.self, forKey: .found) ?? false
                path = try c.decodeIfPresent(String.self, forKey: .path)
                title = try c.decodeIfPresent(String.self, forKey: .title)
                scenarios = try c.decodeIfPresent([String].self, forKey: .scenarios) ?? []
            }

            enum CodingKeys: String, CodingKey { case squad, feature, line, found, path, title, scenarios }
        }

        struct Suite: Decodable, Equatable, Identifiable {
            let name: String
            let defined: Bool
            let line: Int?
            let runs: [Run]

            var id: String { "\(name)#\(line ?? 0)" }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                name = try c.decode(String.self, forKey: .name)
                defined = try c.decodeIfPresent(Bool.self, forKey: .defined) ?? true
                line = try c.decodeIfPresent(Int.self, forKey: .line)
                runs = try c.decodeIfPresent([Run].self, forKey: .runs) ?? []
            }

            enum CodingKeys: String, CodingKey { case name, defined, line, runs }
        }

        struct Problem: Decodable, Equatable {
            let file: String?
            let line: Int?
            let message: String

            var location: String? {
                guard let file else { return nil }
                return line.map { "\(file):\($0)" } ?? file
            }
        }

        let project: Project
        let entry: Entry
        let interpreter: Interpreter
        let workingDir: String?
        let runConfiguration: RunConfiguration?
        let activeConfig: String?
        /// Onde a execução como um todo roda (`local`, `cloud`, `unknown`), ou
        /// `nil` num motor anterior à revisão da B1.
        let hubState: String?
        let configs: [Config]
        let suites: [Suite]
        let unusedSuites: [String]
        let problems: [Problem]

        enum CodingKeys: String, CodingKey {
            case project, entry, interpreter, configs, suites, problems
            case workingDir = "working_dir"
            case runConfiguration = "run_configuration"
            case activeConfig = "active_config"
            case unusedSuites = "unused_suites"
            case hubState = "hub_state"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            project = try c.decode(Project.self, forKey: .project)
            entry = try c.decodeIfPresent(Entry.self, forKey: .entry) ?? Entry(file: nil, function: nil, found: false)
            interpreter = try c.decodeIfPresent(Interpreter.self, forKey: .interpreter)
                ?? Interpreter(path: nil, source: nil, exists: false)
            workingDir = try c.decodeIfPresent(String.self, forKey: .workingDir)
            runConfiguration = try c.decodeIfPresent(RunConfiguration.self, forKey: .runConfiguration)
            activeConfig = try c.decodeIfPresent(String.self, forKey: .activeConfig)
            hubState = try c.decodeIfPresent(String.self, forKey: .hubState)
            configs = try c.decodeIfPresent([Config].self, forKey: .configs) ?? []
            suites = try c.decodeIfPresent([Suite].self, forKey: .suites) ?? []
            unusedSuites = try c.decodeIfPresent([String].self, forKey: .unusedSuites) ?? []
            problems = try c.decodeIfPresent([Problem].self, forKey: .problems) ?? []
        }

        /// A config do `init(...)` ativo, quando o motor achou a definição.
        var activeConfiguration: Config? {
            configs.first { $0.active } ?? activeConfig.flatMap { nome in configs.first { $0.name == nome } }
        }

        /// Onde a execução roda: o `hub_state` do inspect, senão o da config ativa.
        var runHub: HubState {
            if let hubState { return HubState(rawValue: hubState, cloud: activeConfiguration?.cloud ?? false) }
            return activeConfiguration?.hubKind ?? .local
        }

        /// Quantas execuções (`executar`) o main faz, e quantas acharam a feature.
        var runCount: Int { suites.reduce(0) { $0 + $1.runs.count } }
        var missingFeatures: Int { suites.reduce(0) { $0 + $1.runs.filter { !$0.found }.count } }
    }

    // MARK: - Doctor (`project.doctor`)

    struct ProjectDoctor: Decodable, Equatable {
        struct Check: Decodable, Equatable, Identifiable {
            let id: String
            let label: String
            /// `ok`, `warn`, `fail` ou `skip`.
            let state: String
            let message: String
            let hint: String?
            /// Pulada porque o projeto ainda não é confiável (revisão da B1):
            /// o front oferece "Confiar no projeto e verificar".
            let needsTrust: Bool

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(String.self, forKey: .id)
                needsTrust = try c.decodeIfPresent(Bool.self, forKey: .needsTrust) ?? false
                label = try c.decodeIfPresent(String.self, forKey: .label) ?? id
                state = try c.decodeIfPresent(String.self, forKey: .state) ?? "skip"
                message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
                hint = try c.decodeIfPresent(String.self, forKey: .hint)
            }

            enum CodingKeys: String, CodingKey {
                case id, label, state, message, hint
                case needsTrust = "needs_trust"
            }
        }

        struct Summary: Decodable, Equatable {
            let ok: Int
            let warn: Int
            let fail: Int
            let skip: Int

            init(ok: Int = 0, warn: Int = 0, fail: Int = 0, skip: Int = 0) {
                self.ok = ok
                self.warn = warn
                self.fail = fail
                self.skip = skip
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                ok = try c.decodeIfPresent(Int.self, forKey: .ok) ?? 0
                warn = try c.decodeIfPresent(Int.self, forKey: .warn) ?? 0
                fail = try c.decodeIfPresent(Int.self, forKey: .fail) ?? 0
                skip = try c.decodeIfPresent(Int.self, forKey: .skip) ?? 0
            }

            enum CodingKeys: String, CodingKey { case ok, warn, fail, skip }
        }

        let projectId: String?
        let checks: [Check]
        let summary: Summary
        let ready: Bool

        /// Alguma checagem esperou a confiança no projeto.
        var needsTrust: Bool { checks.contains { $0.needsTrust } }

        enum CodingKeys: String, CodingKey {
            case checks, summary, ready
            case projectId = "project_id"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
            checks = try c.decodeIfPresent([Check].self, forKey: .checks) ?? []
            summary = try c.decodeIfPresent(Summary.self, forKey: .summary) ?? Summary()
            ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        }
    }

    // MARK: - Execução (`run.*`)

    struct RunStarted: Decodable, Equatable {
        struct Command: Decodable, Equatable {
            let interpreter: String?
            let entry: String?
            let workingDir: String?

            enum CodingKeys: String, CodingKey {
                case interpreter, entry
                case workingDir = "working_dir"
            }
        }

        struct Video: Decodable, Equatable {
            /// `scrcpy`, `screenrecord`, `simctl` ou `nil` (sem vídeo).
            let mode: String?
            let warning: String?
        }

        let runId: String
        let projectId: String?
        let folder: String?
        let deviceId: String?
        let platform: String?
        let config: String?
        let command: Command?
        let video: Video?
        let startedAt: Double?

        enum CodingKeys: String, CodingKey {
            case folder, platform, config, command, video
            case runId = "run_id"
            case projectId = "project_id"
            case deviceId = "device_id"
            case startedAt = "started_at"
        }
    }

    struct RunStopped: Decodable, Equatable {
        let running: Bool
        let stopped: Bool
        let runId: String?

        enum CodingKeys: String, CodingKey {
            case running, stopped
            case runId = "run_id"
        }
    }

    struct RunStatus: Decodable, Equatable {
        struct Active: Decodable, Equatable {
            let runId: String
            let projectId: String?
            let projectName: String?
            let deviceId: String?
            let platform: String?
            let folder: String?
            let startedAt: Double?
            let elapsedS: Double?
            let lines: Int?
            /// Modo do vídeo (`scrcpy`…) ou `nil`.
            let video: String?
            let stopping: Bool

            enum CodingKeys: String, CodingKey {
                case platform, folder, lines, video, stopping
                case runId = "run_id"
                case projectId = "project_id"
                case projectName = "project_name"
                case deviceId = "device_id"
                case startedAt = "started_at"
                case elapsedS = "elapsed_s"
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                runId = try c.decode(String.self, forKey: .runId)
                projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
                projectName = try c.decodeIfPresent(String.self, forKey: .projectName)
                deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId)
                platform = try c.decodeIfPresent(String.self, forKey: .platform)
                folder = try c.decodeIfPresent(String.self, forKey: .folder)
                startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
                elapsedS = try c.decodeIfPresent(Double.self, forKey: .elapsedS)
                lines = try c.decodeIfPresent(Int.self, forKey: .lines)
                video = try? c.decodeIfPresent(String.self, forKey: .video)
                stopping = try c.decodeIfPresent(Bool.self, forKey: .stopping) ?? false
            }
        }

        let running: Bool
        let run: Active?
        /// O último `run.finished` deste motor.
        let last: RunFinished?
    }

    struct RunLogLine: Decodable, Equatable {
        let runId: String?
        let line: String

        enum CodingKeys: String, CodingKey {
            case line
            case runId = "run_id"
        }
    }

    /// Contagem de um tipo do resumo do behave (features, cenários ou steps).
    struct RunCountSet: Decodable, Equatable {
        let passed: Int
        let failed: Int
        let skipped: Int
        let undefined: Int
        let errors: Int
        let untested: Int

        init(passed: Int = 0, failed: Int = 0, skipped: Int = 0, undefined: Int = 0, errors: Int = 0, untested: Int = 0) {
            self.passed = passed
            self.failed = failed
            self.skipped = skipped
            self.undefined = undefined
            self.errors = errors
            self.untested = untested
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            passed = try c.decodeIfPresent(Int.self, forKey: .passed) ?? 0
            failed = try c.decodeIfPresent(Int.self, forKey: .failed) ?? 0
            skipped = try c.decodeIfPresent(Int.self, forKey: .skipped) ?? 0
            undefined = try c.decodeIfPresent(Int.self, forKey: .undefined) ?? 0
            errors = try c.decodeIfPresent(Int.self, forKey: .errors) ?? 0
            untested = try c.decodeIfPresent(Int.self, forKey: .untested) ?? 0
        }

        enum CodingKeys: String, CodingKey { case passed, failed, skipped, undefined, errors, untested }

        var total: Int { passed + failed + skipped + undefined + errors + untested }
        /// O que conta como falha no resultado (D-3 do motor).
        var failing: Int { failed + errors + undefined }
    }

    struct RunCounts: Decodable, Equatable {
        let features: RunCountSet
        let scenarios: RunCountSet
        let steps: RunCountSet
        /// Quantas chamadas do behave imprimiram resumo.
        let summaries: Int

        init(features: RunCountSet = RunCountSet(), scenarios: RunCountSet = RunCountSet(),
             steps: RunCountSet = RunCountSet(), summaries: Int = 0) {
            self.features = features
            self.scenarios = scenarios
            self.steps = steps
            self.summaries = summaries
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            features = try c.decodeIfPresent(RunCountSet.self, forKey: .features) ?? RunCountSet()
            scenarios = try c.decodeIfPresent(RunCountSet.self, forKey: .scenarios) ?? RunCountSet()
            steps = try c.decodeIfPresent(RunCountSet.self, forKey: .steps) ?? RunCountSet()
            summaries = try c.decodeIfPresent(Int.self, forKey: .summaries) ?? 0
        }

        enum CodingKeys: String, CodingKey { case features, scenarios, steps, summaries }
    }

    struct RunFinished: Decodable, Equatable {
        let runId: String?
        /// `passed`, `failed`, `indeterminate` ou `cancelled`.
        let status: String
        let counts: RunCounts?
        let exitCode: Int?
        let folder: String?
        let video: String?
        let videoWarning: String?
        let message: String?
        let durationS: Double?

        enum CodingKeys: String, CodingKey {
            case status, counts, folder, video, message
            case runId = "run_id"
            case exitCode = "exit_code"
            case videoWarning = "video_warning"
            case durationS = "duration_s"
        }

        init(runId: String? = nil, status: String, counts: RunCounts? = nil, exitCode: Int? = nil, folder: String? = nil,
             video: String? = nil, videoWarning: String? = nil, message: String? = nil, durationS: Double? = nil) {
            self.runId = runId
            self.status = status
            self.counts = counts
            self.exitCode = exitCode
            self.folder = folder
            self.video = video
            self.videoWarning = videoWarning
            self.message = message
            self.durationS = durationS
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            runId = try c.decodeIfPresent(String.self, forKey: .runId)
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "indeterminate"
            counts = try c.decodeIfPresent(RunCounts.self, forKey: .counts)
            exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
            folder = try c.decodeIfPresent(String.self, forKey: .folder)
            video = try c.decodeIfPresent(String.self, forKey: .video)
            videoWarning = try c.decodeIfPresent(String.self, forKey: .videoWarning)
            message = try c.decodeIfPresent(String.self, forKey: .message)
            durationS = try c.decodeIfPresent(Double.self, forKey: .durationS)
        }
    }
}
