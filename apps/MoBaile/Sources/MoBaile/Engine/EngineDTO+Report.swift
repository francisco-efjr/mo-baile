import Foundation

/// DTOs de `report.*` (aba Relatório). Espelham o JSON do motor campo a campo;
/// a tradução para os modelos de `ReportModels.swift` acontece em `toModel()`.
/// A verdade do formato está nas fixtures geradas pelo motor (`make fixtures`).
extension EngineDTO {

    struct ReportFlowPayload: Decodable {
        let key: String
        let label: String
    }

    /// `report.spec`, e o resumo que vai junto em `report.audit` e `report.import`.
    struct ReportSpecPayload: Decodable {
        let path: String
        let projeto: String
        let versaoEspecificacao: String?
        let plataforma: String
        let printsDir: String?
        let printsDirExists: Bool
        let fluxos: [ReportFlowPayload]
        let cards: Int
        let variants: Int
        let sections: [String]

        enum CodingKeys: String, CodingKey {
            case path, projeto, plataforma, fluxos, cards, variants, sections
            case versaoEspecificacao = "versao_especificacao"
            case printsDir = "prints_dir"
            case printsDirExists = "prints_dir_exists"
        }

        func toModel() -> ReportSpec {
            ReportSpec(
                path: path,
                projeto: projeto,
                versao: versaoEspecificacao,
                plataforma: plataforma == "ios" ? .ios : .android,
                printsDir: printsDir,
                printsDirExists: printsDirExists,
                fluxos: fluxos.map { ReportFlow(key: $0.key, label: $0.label) },
                cards: cards,
                variants: variants,
                sections: sections
            )
        }
    }

    struct ReportCheckPayload: Decodable {
        let field: String
        let expected: String
        let obtained: String?
        let ok: Bool
    }

    struct ReportMatchedPayload: Decodable {
        let id: Int?
        let time: String?
        let eventName: String
        let params: [String: JSONValue]

        enum CodingKeys: String, CodingKey {
            case id, time, params
            case eventName = "event_name"
        }
    }

    struct ReportResultPayload: Decodable {
        let id: Int
        let cardIndex: Int
        let section: String
        let cardTitle: String
        let printPath: String?
        let flow: String?
        let flowLabel: String?
        let event: String
        let variation: String
        let status: String
        let checks: [ReportCheckPayload]
        let matched: ReportMatchedPayload?
        let occurrences: Int
        let olderDivergent: Int
        let olderDivergences: [String]
        let gaScreen: String?
        let note: String?
        let divergences: String
        let block: String

        enum CodingKeys: String, CodingKey {
            case id, section, flow, event, variation, status, checks, matched, occurrences, note, divergences, block
            case cardIndex = "card_index"
            case cardTitle = "card_title"
            case printPath = "print_path"
            case flowLabel = "flow_label"
            case olderDivergent = "older_divergent"
            case olderDivergences = "older_divergences"
            case gaScreen = "ga_screen"
        }

        func toModel() -> ReportResult {
            ReportResult(
                id: id,
                cardIndex: cardIndex,
                section: section,
                cardTitle: cardTitle,
                printPath: printPath,
                flow: flow,
                flowLabel: flowLabel,
                event: event,
                variation: variation,
                // Status desconhecido conta como divergente: esconder uma linha
                // que o motor marcou seria pior que mostrá-la como problema.
                status: ReportStatus(rawValue: status) ?? .error,
                checks: checks.map { ReportCheck(field: $0.field, expected: $0.expected, obtained: $0.obtained, ok: $0.ok) },
                matched: matched.map {
                    ReportMatchedEvent(time: $0.time, eventName: $0.eventName, params: $0.params.mapValues(\.displayText))
                },
                occurrences: occurrences,
                olderDivergent: olderDivergent,
                olderDivergences: olderDivergences,
                gaScreen: gaScreen,
                note: note,
                divergences: divergences,
                block: block
            )
        }
    }

    struct ReportExtraPayload: Decodable {
        let event: String
        let screen: String?
        let flowName: String?
        let component: String?
        let detail: String?
        let count: Int

        enum CodingKeys: String, CodingKey {
            case event, screen, component, detail, count
            case flowName = "flow_name"
        }
    }

    struct ReportLogStatsPayload: Decodable {
        let totalLidos: Int
        let daPlataforma: Int
        let duplicados: Int
        let uteis: Int

        enum CodingKeys: String, CodingKey {
            case duplicados, uteis
            case totalLidos = "total_lidos"
            case daPlataforma = "da_plataforma"
        }
    }

    struct ReportSummaryPayload: Decodable {
        let total: Int
        let ok: Int
        let divergent: Int
        let missing: Int
        let complianceRate: Double
        let extras: Int
        let alerts: Int

        enum CodingKeys: String, CodingKey {
            case total, ok, divergent, missing, extras, alerts
            case complianceRate = "compliance_rate"
        }
    }

    /// `report.audit`.
    struct ReportAuditPayload: Decodable {
        let spec: ReportSpecPayload
        let platform: String
        let source: String
        let logPath: String?
        let logStats: ReportLogStatsPayload
        let summary: ReportSummaryPayload
        let results: [ReportResultPayload]
        let extras: [ReportExtraPayload]
        let alerts: [ReportExtraPayload]
        let observations: String
        let markdown: String
        let tsv: String

        enum CodingKeys: String, CodingKey {
            case spec, platform, source, summary, results, extras, alerts, observations, markdown, tsv
            case logPath = "log_path"
            case logStats = "log_stats"
        }

        func toModel() -> AuditReport {
            let fora = extras.map { ($0, false) }
            let alertas = alerts.map { ($0, true) }
            return AuditReport(
                spec: spec.toModel(),
                platform: platform == "ios" ? .ios : .android,
                source: source,
                logPath: logPath,
                logStats: ReportLogStats(
                    totalRead: logStats.totalLidos,
                    platformEvents: logStats.daPlataforma,
                    duplicates: logStats.duplicados,
                    useful: logStats.uteis
                ),
                summary: ReportSummary(
                    total: summary.total,
                    ok: summary.ok,
                    divergent: summary.divergent,
                    missing: summary.missing,
                    complianceRate: summary.complianceRate,
                    extras: summary.extras,
                    alerts: summary.alerts
                ),
                results: results.map { $0.toModel() },
                extras: (fora + alertas).enumerated().map { indice, par in
                    let (extra, alerta) = par
                    return ReportExtra(
                        id: indice, event: extra.event, screen: extra.screen, flowName: extra.flowName,
                        component: extra.component, detail: extra.detail, count: extra.count, isAlert: alerta
                    )
                },
                observations: observations,
                markdown: markdown,
                tsv: tsv
            )
        }
    }

    /// `report.export`.
    struct ReportExportPayload: Decodable {
        struct File: Decodable {
            let kind: String
            let name: String
            let path: String
            let bytes: Int
        }

        let directory: String
        let files: [File]

        func toModel() -> ReportExport {
            ReportExport(
                directory: directory,
                files: files.map { ReportExportFile(kind: $0.kind, name: $0.name, path: $0.path, bytes: $0.bytes) }
            )
        }
    }

    /// `report.import`.
    struct ReportImportPayload: Decodable {
        struct Card: Decodable {
            let print: String
            let event: String
            let doubts: [String]
        }

        let specPath: String
        let reviewPath: String
        let spec: ReportSpecPayload?
        let specError: String?
        let review: [Card]
        let doubtsTotal: Int

        enum CodingKeys: String, CodingKey {
            case spec, review
            case specPath = "spec_path"
            case reviewPath = "review_path"
            case specError = "spec_error"
            case doubtsTotal = "doubts_total"
        }

        func toModel() -> ReportImport {
            ReportImport(
                specPath: specPath,
                reviewPath: reviewPath,
                spec: spec?.toModel(),
                specError: specError,
                review: review.enumerated().map { ReportImportCard(id: $0, print: $1.print, event: $1.event, doubts: $1.doubts) },
                doubtsTotal: doubtsTotal
            )
        }
    }
}
