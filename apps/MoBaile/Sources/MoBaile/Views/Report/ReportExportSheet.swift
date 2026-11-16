import SwiftUI

/// Folha opcional antes de exportar o relatório: versão do app, número da
/// conta, cooperativa e código do usuário. O que for preenchido aparece no
/// topo do HTML, junto à plataforma e à data; nada é obrigatório. Os valores
/// ficam lembrados para a próxima exportação.
struct ReportExportSheet: View {
    let request: ReportExportRequest

    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("report.export.versao") private var versao = ""
    @AppStorage("report.export.conta") private var conta = ""
    @AppStorage("report.export.cooperativa") private var cooperativa = ""
    @AppStorage("report.export.codigoUsuario") private var codigoUsuario = ""

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dados do relatório")
                    .font(DSFont.title3)
                    .foregroundStyle(theme.labelPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Opcional. O que você preencher aparece no topo do relatório, junto à plataforma e à data.")
                    .font(DSFont.callout)
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                TextField("Versão", text: $versao, prompt: Text("ex.: 4.2.0"))
                TextField("Número da conta", text: $conta)
                TextField("Cooperativa", text: $cooperativa)
                TextField("Código do usuário", text: $codigoUsuario)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Button("Limpar") { versao = ""; conta = ""; cooperativa = ""; codigoUsuario = "" }
                    .disabled(info.params.isEmpty)
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Pular") { exportar(ReportExportInfo()) }
                    .help("Exporta sem esses dados")
                Button("Exportar") { exportar(info) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var info: ReportExportInfo {
        ReportExportInfo(versao: versao, conta: conta, cooperativa: cooperativa, codigoUsuario: codigoUsuario)
    }

    private func exportar(_ dados: ReportExportInfo) {
        let pasta = request.directory
        dismiss()
        Task { await session.exportReport(to: pasta, info: dados) }
    }
}
