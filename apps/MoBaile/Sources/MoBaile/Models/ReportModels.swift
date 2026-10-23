import Foundation

/// Modelos da aba Relatório: a auditoria de tagueamento contra a spec do
/// Figma, feita pelo motor (`report.*`). A interface não recalcula nada: o
/// status, o texto das divergências e o bloco de cada variação chegam prontos.

/// Resultado de uma variação (card × fluxo × variação).
enum ReportStatus: String, CaseIterable, Sendable {
    case ok, error, missing

    var displayName: String {
        switch self {
        case .ok: return "OK"
        case .error: return "Divergente"
        case .missing: return "Não disparado"
        }
    }

    /// Mesmo vocabulário visual dos serviços: ícone, cor e texto, nunca só cor.
    var daemonState: DaemonState {
        switch self {
        case .ok: return .ok
        case .error: return .error
        case .missing: return .warn
        }
    }

    /// Ordem da coluna Status: o que precisa de ação primeiro.
    var sortRank: Int {
        switch self {
        case .error: return 0
        case .missing: return 1
        case .ok: return 2
        }
    }
}

struct ReportFlow: Identifiable, Equatable, Sendable {
    let key: String
    let label: String
    var id: String { key }
}

/// Resumo da spec-modelo aberta.
struct ReportSpec: Equatable, Sendable {
    let path: String
    let projeto: String
    let versao: String?
    let plataforma: Platform
    let printsDir: String?
    let printsDirExists: Bool
    let fluxos: [ReportFlow]
    let cards: Int
    let variants: Int
    let sections: [String]

    var fileName: String { (path as NSString).lastPathComponent }
}

struct ReportCheck: Identifiable, Equatable, Sendable {
    let field: String
    let expected: String
    /// `nil` quando o parâmetro não veio no disparo.
    let obtained: String?
    let ok: Bool
    var id: String { field }
}

/// Par chave e valor na ordem em que o card da spec lista.
struct ReportParam: Equatable, Sendable {
    let key: String
    let value: String
}

/// O disparo do log que foi avaliado (o mais recente entre os candidatos).
struct ReportMatchedEvent: Equatable, Sendable {
    let time: String?
    let eventName: String
    let params: [String: String]
}

struct ReportResult: Identifiable, Equatable, Sendable {
    let id: Int
    let cardIndex: Int
    let section: String
    let cardTitle: String
    let printPath: String?
    let flow: String?
    let flowLabel: String?
    let event: String
    let variation: String
    let status: ReportStatus
    let checks: [ReportCheck]
    let matched: ReportMatchedEvent?
    let occurrences: Int
    let olderDivergent: Int
    let olderDivergences: [String]
    let gaScreen: String?
    let note: String?
    let divergences: String
    /// Bloco JSON com ✓/✗, o mesmo do board Excalidraw e do HTML.
    let block: String
    /// O que a variação espera, já com o fluxo aplicado e na ordem do card. Na
    /// não disparada é a única fonte dos valores (não há `checks`).
    var expected: [ReportParam] = []

    // Chaves de ordenação da tabela (precisam ser `Comparable`).
    var statusRank: Int { status.sortRank }
    var flowText: String { flowLabel ?? "—" }
    var timeText: String { matched?.time ?? "" }
    var failedChecks: Int { checks.filter { !$0.ok }.count }

    /// O que a busca da toolbar olha: a linha, cada parâmetro (obtido e
    /// esperado) e os parâmetros do disparo avaliado.
    var searchableFields: [String] {
        var campos = [event, variation, cardTitle, section, divergences, flowLabel ?? "", status.displayName]
        campos += checks.map { "\($0.field): \($0.obtained ?? "") \($0.expected)" }
        campos += (matched?.params ?? [:]).map { "\($0.key): \($0.value)" }
        return campos
    }

    /// O que o leitor de tela lê no lugar das células da linha.
    var accessibilitySummary: String {
        var partes = ["\(status.displayName): \(event)"]
        if !variation.isEmpty { partes.append(variation) }
        if let flowLabel { partes.append("fluxo \(flowLabel)") }
        if !divergences.isEmpty && status != .ok { partes.append(divergences) }
        return partes.joined(separator: ", ")
    }
}

/// Evento fora da spec, ou alerta (`app_exception`, `error_view`).
struct ReportExtra: Identifiable, Equatable, Sendable {
    let id: Int
    let event: String
    let screen: String?
    let flowName: String?
    let component: String?
    let detail: String?
    let count: Int
    let isAlert: Bool

    var screenText: String { screen ?? "—" }
    var detailText: String { detail ?? "" }
    var componentText: String { component ?? "" }
}

struct ReportSummary: Equatable, Sendable {
    let total: Int
    let ok: Int
    let divergent: Int
    let missing: Int
    let complianceRate: Double
    let extras: Int
    let alerts: Int

    /// O que pede ação: divergente ou não disparado.
    var needsAction: Int { divergent + missing }
}

struct ReportLogStats: Equatable, Sendable {
    let totalRead: Int
    let platformEvents: Int
    let duplicates: Int
    let useful: Int
}

/// De onde vêm os eventos auditados.
enum ReportLogSource: Equatable, Sendable {
    /// O que a escuta de Analytics capturou nesta sessão.
    case session
    /// Um log exportado (`log_obtido.json`, Logcat em texto).
    case file(URL)

    var rpcValue: String {
        switch self {
        case .session: return "session"
        case .file: return "file"
        }
    }
}

struct AuditReport: Equatable, Sendable {
    let spec: ReportSpec
    let platform: Platform
    let source: String
    let logPath: String?
    let logStats: ReportLogStats
    let summary: ReportSummary
    let results: [ReportResult]
    let extras: [ReportExtra]
    let observations: String
    let markdown: String
    let tsv: String

    var alerts: [ReportExtra] { extras.filter(\.isAlert) }
    var outOfSpec: [ReportExtra] { extras.filter { !$0.isAlert } }
}

struct ReportExportFile: Identifiable, Equatable, Sendable {
    let kind: String
    let name: String
    let path: String
    let bytes: Int
    var id: String { path }
}

struct ReportExport: Equatable, Sendable {
    let directory: String
    let files: [ReportExportFile]

    func file(_ kind: String) -> ReportExportFile? { files.first { $0.kind == kind } }
}

struct ReportImportCard: Identifiable, Equatable, Sendable {
    let id: Int
    let print: String
    let event: String
    let doubts: [String]
}

/// Resultado da importação dos prints: o rascunho gravado e o que conferir.
struct ReportImport: Equatable, Sendable {
    let specPath: String
    let reviewPath: String
    let spec: ReportSpec?
    let specError: String?
    let review: [ReportImportCard]
    let doubtsTotal: Int
}

/// Recorte da tabela de resultados.
enum ReportFilter: String, CaseIterable, Identifiable, Sendable {
    case all, needsAction, divergent, missing, ok, outOfSpec

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Todas"
        case .needsAction: return "Pedem Ação"
        case .divergent: return "Divergentes"
        case .missing: return "Não Disparadas"
        case .ok: return "OK"
        case .outOfSpec: return "Fora da Spec"
        }
    }

    func includes(_ result: ReportResult) -> Bool {
        switch self {
        case .all: return true
        case .needsAction: return result.status != .ok
        case .divergent: return result.status == .error
        case .missing: return result.status == .missing
        case .ok: return result.status == .ok
        case .outOfSpec: return false
        }
    }
}

/// Operação longa da aba em andamento. Uma de cada vez: o motor roda todas na
/// mesma fila (`report`), em ordem.
enum ReportOperation: Equatable, Sendable {
    case loadingSpec, auditing, exporting, importing, savingCard

    var message: String {
        switch self {
        case .loadingSpec: return "Lendo a spec…"
        case .auditing: return "Auditando o tagueamento…"
        case .exporting: return "Gerando o board e os relatórios…"
        case .importing: return "Lendo os prints com o OCR do macOS…"
        case .savingCard: return "Gravando o card na spec…"
        }
    }
}

// MARK: - Edição do card

/// Card da spec aberto no formulário do inspector (`report.card`).
///
/// Os valores viram texto para editar. O que era texto no JSON volta como
/// texto; o que era lista, objeto ou número (`items`, por exemplo) volta como
/// JSON, e um JSON inválido é recusado antes de ir ao motor.
struct ReportCardDraft: Equatable, Sendable {
    struct Field: Identifiable, Equatable, Sendable {
        let id: UUID
        var key: String
        var value: String
        var isJSON: Bool

        init(key: String, value: String, isJSON: Bool = false) {
            self.id = UUID()
            self.key = key
            self.value = value
            self.isJSON = isJSON
        }

        init(key: String, json: JSONValue) {
            if case .string(let texto) = json {
                self.init(key: key, value: texto)
            } else {
                self.init(key: key, value: json.jsonText, isJSON: true)
            }
        }
    }

    struct Variation: Identifiable, Equatable, Sendable {
        let id = UUID()
        var fields: [Field]
    }

    let cardIndex: Int
    let totalCards: Int
    var secao: String
    var titulo: String
    var evento: String
    let printName: String?
    var params: [Field]
    var variacoes: [Variation]
    var obs: String
    /// A `obs` do JSON é um objeto por fluxo: não vai para o formulário.
    let obsPerFlow: Bool
    /// Fluxos com parâmetros próprios (`params_por_fluxo`), que ficam no JSON.
    let paramsPerFlow: [String]

    enum Problem: LocalizedError, Equatable {
        case emptyEvent
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .emptyEvent: return "O evento não pode ficar vazio."
            case .invalidJSON(let campo): return "O valor de \(campo) precisa ser um JSON válido (lista ou objeto)."
            }
        }
    }

    /// O `card` de `report.card_update`.
    func rpcCard() throws -> JSONValue {
        guard !evento.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Problem.emptyEvent }
        var card: [String: JSONValue] = [
            "secao": .string(secao),
            "titulo": .string(titulo),
            "evento": .string(evento),
            "params": .array(try params.map(Self.pair)),
            "variacoes": .array(try variacoes.map { .array(try $0.fields.map(Self.pair)) }),
        ]
        if !obsPerFlow { card["obs"] = .string(obs) }
        return .object(card)
    }

    private static func pair(_ field: Field) throws -> JSONValue {
        let chave = field.key.trimmingCharacters(in: .whitespaces)
        guard field.isJSON else { return .object(["key": .string(chave), "value": .string(field.value)]) }
        guard let valor = try? JSONDecoder().decode(JSONValue.self, from: Data(field.value.utf8)) else {
            throw Problem.invalidJSON(chave.isEmpty ? "um parâmetro" : chave)
        }
        return .object(["key": .string(chave), "value": valor])
    }
}
