import Foundation
import Observation

/// Estado da aba Execução (B1, 3.23.0): o projeto de automação do dono, o
/// `main` resumido, o doctor, o console e o resultado da última execução.
///
/// Fica fora do `AppState` para não inchá-lo, mas pendurado nele
/// (`AppState.execution`): a sessão aplica as notificações aqui, e as telas
/// leem daqui, como no resto do app.
@Observable
final class ExecutionState {
    // --- Projetos ---
    /// `project.list`: o aberto mais recentemente primeiro.
    var projects: [EngineDTO.Project] = []
    var currentProjectID: String?
    /// `project.inspect` (ou `project.configure`) do projeto atual.
    var inspection: EngineDTO.ProjectInspection?
    /// A primeira leitura (`project.list` + `run.status`) já foi feita.
    var loadedOnce = false
    var operation: ExecutionOperation?
    /// Erro da aba, em linha (o motor explica: nuvem, aparelho ocupado, udid
    /// diferente da config…).
    var error: String?

    // --- Doctor ---
    var doctor: EngineDTO.ProjectDoctor?
    var doctorRunning = false
    var doctorProgress: String?
    /// Token do `$/progress` do doctor em andamento. Próprio, para não
    /// disputar com o da operação longa de outra aba.
    var doctorToken: String?

    // --- Execução ---
    /// Console: referência, e não valor, para cada linha nova não copiar as
    /// 5.000 guardadas (ver `ExecutionConsole`). `consoleRevision` é o que as
    /// telas observam.
    let console = ExecutionConsole()
    private(set) var consoleRevision = 0
    var activeRun: ActiveRun?
    var starting = false
    /// `run_id` adotado do primeiro `run.log`/`run.finished` que chega
    /// durante o `run.start`, antes da resposta (revisão FR-07).
    var adoptedRunId: String?
    var stopping = false
    var lastResult: EngineDTO.RunFinished?
    /// Aparelho escolhido na barra Rodar; `nil` deixa o motor decidir (o
    /// `udid` da config ativa, senão o aparelho da sessão).
    var targetDeviceID: String?
    var recordVideo: Bool = UserDefaults.standard.object(forKey: ExecutionState.recordVideoKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(recordVideo, forKey: ExecutionState.recordVideoKey) }
    }

    /// Diálogo aberto: "Confiar neste projeto?" ou "Rodar mesmo assim?".
    var confirmation: ExecutionConfirmation?

    static let recordVideoKey = "mobaile.execucao.gravarVideo"

    // MARK: - Derivados

    var currentProject: EngineDTO.Project? {
        if let currentProjectID, let item = projects.first(where: { $0.id == currentProjectID }) { return item }
        return inspection?.project
    }

    var isRunning: Bool { activeRun != nil }

    /// Contagem da barra lateral: as falhas do último resultado (cenários que
    /// falharam, com erro ou indefinidos; 1 quando o motor não deu resumo).
    /// A execução em andamento aparece como "rodando", fora daqui.
    var badgeCount: Int {
        guard !isRunning, let lastResult, lastResult.status == "failed" else { return 0 }
        return max(1, lastResult.counts?.scenarios.failing ?? 0)
    }

    // MARK: - Console

    func appendConsole(_ line: String) {
        console.append(line)
        consoleRevision &+= 1
    }

    func clearConsole() {
        console.clear()
        consoleRevision &+= 1
    }

    // MARK: - Projeto

    /// Põe o projeto no topo da lista (o motor faz o mesmo com `opened_at`).
    func upsert(_ project: EngineDTO.Project) {
        projects.removeAll { $0.id == project.id }
        projects.insert(project, at: 0)
    }

    /// Atualiza o item sem mudar a ordem (a análise não reabre o projeto).
    func upsertKeepingOrder(_ project: EngineDTO.Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.insert(project, at: 0)
        }
    }

    /// Troca de projeto: o que era do anterior sai da tela.
    func select(_ project: EngineDTO.Project) {
        if currentProjectID != project.id {
            inspection = nil
            doctor = nil
            error = nil
            if !isRunning {
                lastResult = nil
                clearConsole()
            }
        }
        currentProjectID = project.id
        upsert(project)
    }

    func forgetCurrent() {
        if let currentProjectID { projects.removeAll { $0.id == currentProjectID } }
        currentProjectID = nil
        inspection = nil
        doctor = nil
        error = nil
    }

    /// Marca o projeto como confiável na lista e na análise, sem reler.
    func markTrusted(_ id: String) {
        projects = projects.map { $0.id == id ? $0.trusting() : $0 }
    }

    /// Por que trocar ou esquecer o projeto está bloqueado agora, ou `nil`
    /// (revisões FR-02 e FR-03).
    var projectLockReason: String? {
        if isRunning { return "Espere a execução terminar (ou pare) para trocar de projeto." }
        if starting { return "Espere a execução começar." }
        if operation == .trusting { return "Aguarde: marcando o projeto como confiável." }
        if operation != nil { return "Aguarde: lendo o projeto." }
        return nil
    }

    /// Por que o Rodar está bloqueado, ou `nil` quando pode rodar.
    func runBlockReason(engineConnected: Bool) -> String? {
        ExecutionRules.runBlockReason(inspection: inspection, engineConnected: engineConnected,
                                      busy: operation != nil || starting)
    }
}

enum ExecutionOperation: Equatable, Sendable {
    case loading, opening, inspecting, configuring, trusting
}

/// Execução em andamento, do `run.start` ou do `run.status`.
struct ActiveRun: Equatable, Sendable {
    let runId: String
    let projectId: String?
    let startedAt: Date
    let folder: String?
    let deviceId: String?
    let videoWarning: String?
}

/// O que o diálogo de confiança mostra e o que fazer ao confirmar.
struct ExecutionTrustRequest: Equatable, Identifiable, Sendable {
    enum Then: Equatable, Sendable {
        /// Repete o `run.start` com `trusted: true`.
        case run
        /// Chama `project.trust` e refaz o doctor.
        case verify
    }

    let projectId: String
    let projectName: String
    let interpreter: String?
    let entry: String?
    let workingDir: String?
    let message: String?
    let then: Then

    var id: String { "\(projectId)-\(then)" }

    init(projectId: String, projectName: String, interpreter: String?, entry: String?, workingDir: String?,
         message: String? = nil, then: Then) {
        self.projectId = projectId
        self.projectName = projectName
        self.interpreter = interpreter
        self.entry = entry
        self.workingDir = workingDir
        self.message = message
        self.then = then
    }

    /// Do `project.inspect`: interpretador, arquivo de entrada e pasta de trabalho.
    init(_ inspection: EngineDTO.ProjectInspection, message: String? = nil, then: Then) {
        self.init(projectId: inspection.project.id, projectName: inspection.project.name,
                  interpreter: inspection.interpreter.path, entry: inspection.entry.file ?? inspection.project.entry,
                  workingDir: inspection.workingDir ?? inspection.project.root, message: message, then: then)
    }
}

/// Diálogo de confirmação da aba.
enum ExecutionConfirmation: Equatable, Identifiable, Sendable {
    case trust(ExecutionTrustRequest)
    /// `hub_unknown`: o motor não conseguiu provar que a config roda só nesta
    /// máquina; confirmar repete com `allow_unknown_hub: true`.
    case unknownHub(message: String, trusted: Bool)

    var id: String {
        switch self {
        case .trust(let pedido): return "trust-\(pedido.id)"
        case .unknownHub: return "hub"
        }
    }
}

/// Regras puras da aba, fora da view para o teste alcançar.
enum ExecutionRules {
    static func runBlockReason(inspection: EngineDTO.ProjectInspection?, engineConnected: Bool, busy: Bool) -> String? {
        guard engineConnected else { return "O motor não está no ar." }
        guard let inspection else { return busy ? "Lendo o projeto…" : "Abra um projeto para rodar." }
        if !inspection.entry.found || inspection.entry.file == nil {
            return "Não achei o arquivo de entrada do projeto (main.py, run.py ou __main__.py)."
        }
        if !inspection.interpreter.usable {
            if let caminho = inspection.interpreter.path {
                return "O interpretador \(caminho) não existe nesta máquina. Escolha outro na coluna Projeto."
            }
            return "Nenhum interpretador encontrado. Escolha um na coluna Projeto."
        }
        guard let ativa = inspection.activeConfig else {
            return "O main não tem um init(...) ativo: descomente uma config para rodar."
        }
        if inspection.runHub == .cloud {
            let host = inspection.activeConfiguration?.hub.map { " (\($0))" } ?? ""
            return "A config ativa \(ativa) roda na nuvem\(host). Nesta versão só roda local: troque o init no main."
        }
        return nil
    }
}

extension EngineDTO.Project {
    func trusting() -> EngineDTO.Project {
        EngineDTO.Project(id: id, root: root, name: name, entry: entry, trusted: true, openedAt: openedAt,
                          interpreterOverride: interpreterOverride, entryOverride: entryOverride)
    }
}

// MARK: - Console

/// As linhas do console da execução, com teto.
///
/// Classe, e não struct: o `NSTextView` do console guarda uma referência e
/// aplica só o que mudou desde a última vez (linhas novas no fim, antigas
/// descartadas no começo). Com um valor, a view do SwiftUI segurava uma cópia
/// e cada linha nova copiava o array inteiro.
final class ExecutionConsole {
    static let defaultLimit = 5000

    let limit: Int
    private(set) var lines: [String] = []
    /// Linhas descartadas pelo teto desde a última limpeza.
    private(set) var dropped = 0
    /// Linhas recebidas desde a última limpeza (guardadas + descartadas).
    private(set) var appended = 0
    /// Muda a cada limpeza: quem desenha recomeça do zero.
    private(set) var generation = 0

    init(limit: Int = ExecutionConsole.defaultLimit) {
        self.limit = max(1, limit)
    }

    func append(_ line: String) {
        // Uma linha por item: quebra dentro da linha desalinharia a contagem.
        let limpa = line.contains(where: { $0 == "\n" || $0 == "\r" })
            ? line.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            : line
        lines.append(limpa)
        appended += 1
        if lines.count > limit {
            let excesso = lines.count - limit
            lines.removeFirst(excesso)
            dropped += excesso
        }
    }

    func clear() {
        lines.removeAll(keepingCapacity: true)
        dropped = 0
        appended = 0
        generation += 1
    }

    var isEmpty: Bool { lines.isEmpty }
    var text: String { lines.joined(separator: "\n") }

    /// "N linhas antigas descartadas", ou `nil` sem descarte.
    var droppedNotice: String? {
        switch dropped {
        case 0: return nil
        case 1: return "1 linha antiga descartada"
        default: return "\(dropped.formatted(.number.locale(Locale(identifier: "pt_BR")))) linhas antigas descartadas"
        }
    }

    enum Tone: Equatable { case normal, fail, pass, dim }

    /// Cor da linha no console: resumo do behave, falha e traceback.
    static func tone(of line: String) -> Tone {
        let minusc = line.lowercased()
        if minusc.contains("traceback") || minusc.contains("error") || minusc.contains("erro")
            || minusc.contains("assertionerror") || minusc.range(of: #"\b[1-9]\d* (failed|error)"#, options: .regularExpression) != nil {
            return .fail
        }
        if minusc.range(of: #"\d+ (features?|scenarios?|steps?) passed"#, options: .regularExpression) != nil {
            return .pass
        }
        if minusc.hasPrefix("  ") && (minusc.contains("# ") || minusc.hasSuffix("...")) {
            return .dim
        }
        return .normal
    }
}

// MARK: - Resultado

/// O banner do `run.finished`: título, contagens e duração, já em texto.
struct ExecutionResultSummary: Equatable {
    enum Kind: Equatable { case passed, failed, indeterminate, cancelled }

    let kind: Kind
    let title: String
    let symbol: String
    /// "Cenários: 1 passou, 1 falhou", um por tipo do resumo do behave.
    let counts: [String]
    let duration: String?
    let message: String?
    let folder: String?
    let video: String?
    let videoWarning: String?

    init(_ resultado: EngineDTO.RunFinished) {
        switch resultado.status {
        case "passed": kind = .passed
        case "failed": kind = .failed
        case "cancelled": kind = .cancelled
        default: kind = .indeterminate
        }
        switch kind {
        case .passed: title = "Passou"; symbol = "checkmark.circle.fill"
        case .failed: title = "Falhou"; symbol = "xmark.octagon.fill"
        case .indeterminate: title = "Indeterminado"; symbol = "questionmark.circle.fill"
        case .cancelled: title = "Cancelado"; symbol = "stop.circle.fill"
        }
        if let c = resultado.counts {
            counts = [Self.countsText("Features", c.features, feminino: true),
                      Self.countsText("Cenários", c.scenarios, feminino: false),
                      Self.countsText("Steps", c.steps, feminino: false)]
        } else {
            counts = []
        }
        duration = resultado.durationS.map(Self.duration)
        let texto = resultado.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        message = (texto?.isEmpty ?? true) ? nil : texto
        folder = resultado.folder
        video = resultado.video
        videoWarning = resultado.videoWarning
    }

    /// "Cenários: 1 passou, 1 falhou". O que passou sempre aparece; o resto,
    /// só quando não é zero.
    static func countsText(_ rotulo: String, _ c: EngineDTO.RunCountSet, feminino: Bool) -> String {
        var partes = [c.passed == 1 ? "1 passou" : "\(c.passed) passaram"]
        if c.failed > 0 { partes.append(c.failed == 1 ? "1 falhou" : "\(c.failed) falharam") }
        if c.errors > 0 { partes.append("\(c.errors) com erro") }
        if c.undefined > 0 {
            partes.append("\(c.undefined) \(c.undefined == 1 ? (feminino ? "indefinida" : "indefinido") : (feminino ? "indefinidas" : "indefinidos"))")
        }
        if c.skipped > 0 {
            partes.append("\(c.skipped) \(c.skipped == 1 ? (feminino ? "pulada" : "pulado") : (feminino ? "puladas" : "pulados"))")
        }
        if c.untested > 0 {
            partes.append("\(c.untested) não \(c.untested == 1 ? (feminino ? "testada" : "testado") : (feminino ? "testadas" : "testados"))")
        }
        return "\(rotulo): \(partes.joined(separator: ", "))"
    }

    /// "1,2 s" abaixo de um minuto; "2 min 05 s" acima.
    static func duration(_ segundos: Double) -> String {
        let s = max(0, segundos)
        if s < 60 {
            return String(format: "%.1f s", s).replacingOccurrences(of: ".", with: ",")
        }
        let total = Int(s.rounded())
        if total < 3600 {
            return String(format: "%d min %02d s", total / 60, total % 60)
        }
        return String(format: "%d h %02d min", total / 3600, (total % 3600) / 60)
    }

    /// Tempo decorrido da execução em andamento: "00:42", "1:02:03".
    static func elapsed(_ segundos: TimeInterval) -> String {
        let total = max(0, Int(segundos))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Textos da aba que mais de uma tela usa.
enum ExecutionCopy {
    static func interpreterSource(_ source: String?) -> String {
        switch source {
        case "manual": return "escolhido por você"
        case "run_configuration": return "run configuration do PyCharm"
        case "pycharm_sdk": return "SDK do PyCharm"
        case "venv": return "venv do projeto"
        default: return "não encontrado"
        }
    }

    static func platform(_ id: String?) -> String? {
        switch id {
        case "android": return "Android"
        case "ios": return "iOS"
        default: return nil
        }
    }

    /// Subtítulo da janela: projeto e estado.
    static func subtitle(_ ex: ExecutionState) -> String {
        guard let projeto = ex.currentProject else { return "Nenhum projeto" }
        if ex.isRunning { return "\(projeto.name) · rodando" }
        if let resultado = ex.lastResult {
            return "\(projeto.name) · \(ExecutionResultSummary(resultado).title.lowercased())"
        }
        return projeto.name
    }

    /// `~/…` quando o caminho fica na pasta do usuário.
    static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
