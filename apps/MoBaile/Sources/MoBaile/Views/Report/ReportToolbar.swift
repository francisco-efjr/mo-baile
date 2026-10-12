import SwiftUI

/// Barra acessória do Relatório: a spec aberta, de onde vêm os eventos, a
/// plataforma e as ações. Segue a estrutura de Analytics: menus à esquerda,
/// ações à direita, rótulos que viram só ícone em larguras estreitas.
struct ReportToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        AccessoryBar {
            ViewThatFits(in: .horizontal) {
                conteudo(compacto: false)
                conteudo(compacto: true)
            }
        }
    }

    private func conteudo(compacto: Bool) -> some View {
        let ocupado = appState.reportOperation != nil
        return HStack(spacing: 8) {
            specMenu(compacto: compacto)
            logMenu(compacto: compacto)
            platformMenu(compacto: compacto)

            Spacer(minLength: 8)

            Button {
                Task { await session.runReport() }
            } label: {
                rotulo("Auditar", icone: "checklist", compacto: compacto)
            }
            .disabled(!appState.canRunReport)
            .help(dicaAuditar)
            .accessibilityLabel("Auditar")

            exportMenu(compacto: compacto)
                .disabled(appState.report == nil || ocupado)

            Menu {
                Button("Copiar TSV") { copiar(\.tsv, "TSV") }
                Button("Copiar Markdown") { copiar(\.markdown, "Markdown") }
            } label: {
                rotulo("Copiar", icone: "doc.on.clipboard", compacto: compacto)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(appState.report == nil)
            .help("Copia a tabela em TSV (Google Planilhas) ou em Markdown (PR, Jira)")
            .accessibilityLabel("Copiar relatório")
        }
    }

    // MARK: - Spec

    private func specMenu(compacto: Bool) -> some View {
        let spec = appState.reportSpec
        return Menu {
            Button("Abrir Spec…") { ReportActions.openSpec(session) }
            Button("Importar Prints do Figma…") { ReportActions.importPrints(appState, session) }
            if let spec {
                Divider()
                Button("Reler Spec") {
                    Task { await session.openReportSpec(at: URL(fileURLWithPath: spec.path)) }
                }
                Button("Abrir no Editor") { Exporters.openFile(spec.path) }
                Button("Mostrar no Finder") { Exporters.revealInFinder(spec.path) }
            }
        } label: {
            Label(spec.map { Self.encurtar(compacto ? $0.projeto : "\($0.projeto) · \($0.fileName)",
                                           limite: compacto ? 22 : 44) } ?? "Abrir Spec",
                  systemImage: "doc.text")
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .tint(themeManager.current.labelPrimary)
        .fixedSize()
        .disabled(appState.reportOperation != nil)
        .help(spec.map { "Spec: \($0.path)" } ?? "Abra a spec-modelo do tagueamento (JSON)")
        .accessibilityLabel("Spec de tagueamento")
        .accessibilityValue(spec?.projeto ?? "nenhuma")
    }

    // MARK: - Log

    private func logMenu(compacto: Bool) -> some View {
        Menu {
            Toggle("Eventos Capturados (\(appState.analyticsEvents.count))", isOn: Binding(
                get: { appState.reportLogSource == .session },
                set: { if $0 { appState.reportLogSource = .session } }
            ))
            if case .file(let url) = appState.reportLogSource {
                Toggle(url.lastPathComponent, isOn: .constant(true))
            }
            Divider()
            Button("Escolher Arquivo de Log…") {
                if let url = Exporters.chooseReportLog() {
                    appState.reportLogSource = .file(url)
                }
            }
        } label: {
            Label(rotuloLog(compacto: compacto), systemImage: iconeLog)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .tint(themeManager.current.labelPrimary)
        .fixedSize()
        .disabled(appState.reportOperation != nil)
        .help("De onde vêm os eventos: o que a escuta de Analytics capturou, ou um log exportado (log_obtido.json, Logcat)")
        .accessibilityLabel("Origem dos eventos")
        .accessibilityValue(rotuloLog(compacto: false))
    }

    private func rotuloLog(compacto: Bool) -> String {
        switch appState.reportLogSource {
        case .session:
            return compacto ? "Capturados" : "Eventos Capturados (\(appState.analyticsEvents.count))"
        case .file(let url):
            return Self.encurtar(url.lastPathComponent, limite: compacto ? 18 : 32)
        }
    }

    /// Rótulo de menu não trunca sozinho com `fixedSize`; nome longo de spec ou
    /// de log empurraria as ações para fora da barra.
    static func encurtar(_ texto: String, limite: Int) -> String {
        texto.count <= limite ? texto : String(texto.prefix(limite - 1)) + "…"
    }

    private var iconeLog: String {
        if case .file = appState.reportLogSource { return "doc.plaintext" }
        return "antenna.radiowaves.left.and.right"
    }

    // MARK: - Plataforma

    private func platformMenu(compacto: Bool) -> some View {
        let daSpec = appState.reportSpec?.plataforma
        return Menu {
            Toggle(daSpec.map { "Da Spec (\($0.displayName))" } ?? "Da Spec", isOn: plataforma(nil))
            Divider()
            ForEach(Platform.allCases) { alvo in
                Toggle(alvo.displayName, isOn: plataforma(alvo))
            }
        } label: {
            rotulo(appState.reportEffectivePlatform?.displayName ?? "Plataforma", icone: "iphone", compacto: compacto)
        }
        .menuStyle(.borderlessButton)
        .tint(themeManager.current.labelPrimary)
        .fixedSize()
        .disabled(appState.reportSpec == nil || appState.reportOperation != nil)
        .help("Plataforma auditada. Logs mistos são filtrados: só os eventos dela entram.")
        .accessibilityLabel("Plataforma auditada")
        .accessibilityValue(appState.reportEffectivePlatform?.displayName ?? "da spec")
    }

    private func plataforma(_ alvo: Platform?) -> Binding<Bool> {
        Binding(
            get: { appState.reportPlatform == alvo },
            set: { if $0 { appState.reportPlatform = alvo } }
        )
    }

    // MARK: - Exportar

    private func exportMenu(compacto: Bool) -> some View {
        Menu {
            Button("Exportar em Documentos › Mo baile") {
                Task { await session.exportReport(to: nil) }
            }
            Button("Exportar Para…") { ReportActions.exportTo(session) }
            if let exportado = appState.reportLastExport {
                Divider()
                if let html = exportado.file("html") {
                    Button("Abrir Relatório HTML") { Exporters.openFile(html.path) }
                }
                if let board = exportado.file("board") {
                    Button("Abrir Board (.excalidraw)") { Exporters.openFile(board.path) }
                }
                Button("Mostrar no Finder") { Exporters.revealInFinder(exportado.directory) }
            }
        } label: {
            rotulo("Exportar", icone: "square.and.arrow.up", compacto: compacto)
        } primaryAction: {
            Task { await session.exportReport(to: nil) }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Grava o board Excalidraw, o HTML, o Markdown e o TSV em Documentos › Mo baile › Relatórios")
        .accessibilityLabel("Exportar relatório")
    }

    // MARK: - Apoio

    private var dicaAuditar: String {
        if appState.reportSpec == nil { return "Abra uma spec para auditar" }
        if case .session = appState.reportLogSource, appState.analyticsEvents.isEmpty {
            return "Nenhum evento capturado: inicie a escuta em Analytics ou escolha um arquivo de log"
        }
        return "Cruza a spec com os eventos e valida cada parâmetro"
    }

    private func copiar(_ campo: KeyPath<AuditReport, String>, _ nome: String) {
        guard let report = appState.report else { return }
        Exporters.copy(report[keyPath: campo])
        appState.statusMessage = "Relatório copiado em \(nome)"
    }

    @ViewBuilder
    private func rotulo(_ texto: String, icone: String, compacto: Bool) -> some View {
        if compacto {
            Image(systemName: icone)
        } else {
            Label(texto, systemImage: icone)
        }
    }
}

/// Ações com painel do sistema, usadas pela barra, pelo estado vazio e pelo
/// menu Arquivo.
@MainActor
enum ReportActions {
    static func openSpec(_ session: EngineSession) {
        guard let url = Exporters.chooseReportSpec() else { return }
        Task { await session.openReportSpec(at: url) }
    }

    /// A plataforma do rascunho é a da aba (ou a do app); dá para trocar no JSON.
    static func importPrints(_ appState: AppState, _ session: EngineSession) {
        guard let pasta = Exporters.chooseReportPrintsFolder() else { return }
        let plataforma = appState.reportEffectivePlatform ?? appState.platform
        Task { await session.importReportPrints(from: pasta, projeto: nil, platform: plataforma) }
    }

    static func exportTo(_ session: EngineSession) {
        guard let pasta = Exporters.chooseReportExportFolder() else { return }
        Task { await session.exportReport(to: pasta) }
    }
}
