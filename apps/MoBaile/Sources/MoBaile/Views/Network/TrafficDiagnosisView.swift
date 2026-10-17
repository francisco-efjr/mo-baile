import SwiftUI

/// Resposta de `proxy.diagnose`: cada causa com o que foi visto e o que fazer.
///
/// É o que o usuário lia em issue e fórum ("não vejo nada na aba Rede") e
/// resolvia na tentativa e erro. O motor olha o proxy, o aparelho e o
/// histórico e diz a causa provável; aqui só se apresenta.
struct TrafficDiagnosisView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(alignment: .leading, spacing: 12) {
            if let d = appState.trafficDiagnosis {
                HStack(spacing: 8) {
                    Image(systemName: "stethoscope")
                        .foregroundStyle(theme.accentText)
                    Text("Por que não vejo tráfego?")
                        .font(DSFont.headline)
                }
                Text(resumo(d))
                    .font(DSFont.callout.monospacedDigit())
                    .foregroundStyle(theme.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if d.causes.isEmpty {
                    Label("Nada aponta problema. Se o app não gera tráfego agora, use-o e observe.", systemImage: "checkmark.circle")
                        .font(DSFont.callout)
                        .foregroundStyle(theme.labelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(d.causes) { causa in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(causa.title, systemImage: Self.icone(causa.code))
                                .font(DSFont.body.weight(.semibold))
                            Text(causa.detail)
                                .font(DSFont.callout)
                                .foregroundStyle(theme.labelSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(causa.fix)
                                .font(DSFont.callout)
                                .foregroundStyle(theme.labelPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(causa.title). \(causa.detail) \(causa.fix)")
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private func resumo(_ d: EngineDTO.TrafficDiagnosis) -> String {
        var partes = ["proxy \(d.proxyRunning ? "ligado" : "desligado")"]
        if let configurado = d.deviceConfigured {
            partes.append(configurado ? "aparelho configurado" : "aparelho sem proxy")
        }
        if d.netlogRunning { partes.append("App em Debug ligado") }
        partes.append("\(d.requestsTotal) requisições")
        partes.append("\(d.tunnelsTotal) túneis" + (d.tunnelsFailed > 0 ? " (\(d.tunnelsFailed) com erro)" : ""))
        if let idade = d.lastEventAgeS { partes.append("último há \(Int(idade)) s") }
        return partes.joined(separator: " · ")
    }

    static func icone(_ code: String) -> String {
        switch code {
        case "proxy_stopped": return "power"
        case "proxy_not_on_device": return "iphone.slash"
        case "no_connections": return "antenna.radiowaves.left.and.right.slash"
        case "tls_pinning_suspected": return "lock.shield"
        case "only_tunnels": return "lock"
        case "ios_no_proxy_support": return "applelogo"
        case "netlog_running_no_events": return "doc.text.magnifyingglass"
        default: return "questionmark.circle"
        }
    }
}
