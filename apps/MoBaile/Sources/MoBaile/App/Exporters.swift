import AppKit
import Foundation

/// Exportações e cópias usadas pela barra acessória e pelos menus.
///
/// Ficavam dentro das barras de Rede e Analytics. Com o menu Arquivo
/// oferecendo as mesmas ações (todo comando da interface também aparece num
/// menu), o código precisou sair da View.
@MainActor
enum Exporters {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Rede

    static func exportHAR(_ state: AppState) {
        guard !state.httpRequests.isEmpty else {
            state.statusMessage = "Nenhuma requisição para exportar"
            return
        }
        guard let data = HARExporter.generateHAR(from: state.httpRequests) else {
            state.statusMessage = "Não foi possível gerar o arquivo HAR."
            return
        }
        save(data, title: "Exportar Tráfego HAR", fileName: "network_traffic.har", state: state)
    }

    /// `curl` equivalente à requisição, com os headers já redigidos pelo motor.
    static func curl(for event: NetworkEvent) -> String {
        var partes = ["curl -X \(event.method) '\(event.url)'"]
        for (nome, valor) in event.requestHeaders.sorted(by: { $0.key < $1.key }) {
            partes.append("-H '\(nome): \(valor.replacingOccurrences(of: "'", with: "'\\''"))'")
        }
        if !event.requestBody.isEmpty {
            partes.append("--data-raw '\(event.requestBody.replacingOccurrences(of: "'", with: "'\\''"))'")
        }
        return partes.joined(separator: " \\\n  ")
    }

    // MARK: - Analytics

    static func copyAnalyticsTSV(_ state: AppState) {
        guard !state.analyticsEvents.isEmpty else {
            state.statusMessage = "Nenhum evento de analytics para copiar"
            return
        }
        var lines: [String] = [
            "Hora\tPlataforma\tOrigem\tNome do Evento\tParâmetros Principais\tJSON dos Parâmetros"
        ]
        for ev in state.analyticsEvents {
            let sortedKeys = ev.params.keys.sorted()
            let mainParams = sortedKeys.prefix(4).map { "\($0): \(ev.params[$0] ?? "")" }.joined(separator: ", ")
            let jsonParams: String
            if let data = try? JSONSerialization.data(withJSONObject: ev.params, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                jsonParams = str
            } else {
                jsonParams = "{}"
            }
            lines.append("\(ev.timeStr)\t\(ev.platform.rawValue.uppercased())\t\(ev.tag)\t\(ev.eventName)\t\(mainParams)\t\(jsonParams)")
        }
        copy(lines.joined(separator: "\n"))
        state.statusMessage = "\(state.analyticsEvents.count) eventos copiados como TSV"
    }

    static func exportAnalyticsJSON(_ state: AppState) {
        guard !state.analyticsEvents.isEmpty else {
            state.statusMessage = "Nenhum evento de analytics para exportar"
            return
        }
        let dataArray: [[String: Any]] = state.analyticsEvents.map { ev in
            [
                "id": ev.id,
                "time_str": ev.timeStr,
                "tag": ev.tag,
                "event_name": ev.eventName,
                "params": ev.params,
                "raw_log": ev.rawLog,
                "platform": ev.platform.rawValue,
            ]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dataArray, options: [.prettyPrinted, .sortedKeys]) else {
            state.statusMessage = "Não foi possível montar o JSON dos eventos."
            return
        }
        save(jsonData, title: "Exportar Analytics (JSON)", fileName: "log_obtido.json", state: state)
    }

    // MARK: - Execução

    /// Grava o log da execução num arquivo temporário e abre no editor padrão.
    static func openRunLog(_ state: AppState) {
        let texto = state.runLog.map {
            "[\($0.timestamp.formatted(date: .omitted, time: .standard))] [\($0.prefix)] \($0.message)"
        }.joined(separator: "\n")
        copy(texto)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mobaile-flow-run.log")
        try? texto.write(to: tempURL, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(tempURL)
        state.statusMessage = "Log copiado e aberto no editor"
    }

    // MARK: - Apoio

    private static func save(_ data: Data, title: String, fileName: String, state: AppState) {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            state.statusMessage = "Salvo em \(url.lastPathComponent)"
        } catch {
            state.statusMessage = "Não foi possível salvar \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
