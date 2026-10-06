import AppKit
import SwiftUI

struct AnalyticsToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.analyticsListenerActive ? theme.current.success : theme.current.danger)
                    .frame(width: 6, height: 6)
                Text(appState.analyticsListenerActive ? "FA Listener ativo" : "FA Listener inativo")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.current.textSecondary)
            }
            .frame(width: 140, alignment: .leading)

            if appState.platform == .ios {
                iosSourceMenu
            }

            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(theme.current.textTertiary)
                    .accessibilityHidden(true)
                @Bindable var state = appState
                TextField("Filtrar eventos e tags", text: $state.analyticsFilterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(theme.current.textPrimary)
                    // O texto-sugestão some ao digitar; o nome fica.
                    .accessibilityLabel("Filtrar eventos por nome ou tag")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(theme.current.bgControl)
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(theme.current.borderSubtle, lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            
            HStack(spacing: 8) {
                FluidPillButton(
                    text: appState.analyticsListenerActive ? "Parar escuta" : "Iniciar escuta",
                    icon: appState.analyticsListenerActive ? "stop.fill" : "antenna.radiowaves.left.and.right",
                    style: appState.analyticsListenerActive ? .primary : .secondary
                ) {
                    Task {
                        await session.toggleAnalytics()
                    }
                }
                .disabled(!appState.analyticsListenerActive && !appState.canStartAnalytics)
                .help(appState.analyticsListenerActive ? "Encerra a captura de eventos de Analytics" : "Inicia a captura de eventos de Analytics (Firebase) no aparelho")

                FluidPillButton(
                    text: "Copiar TSV",
                    icon: "doc.on.clipboard",
                    style: .secondary
                ) {
                    copyTSV()
                }
                .disabled(appState.analyticsEvents.isEmpty)
                .help("Copia a tabela em formato TSV para colar diretamente no Google Planilhas")

                FluidPillButton(
                    text: "Exportar JSON",
                    icon: "square.and.arrow.up",
                    style: .secondary
                ) {
                    exportJSON()
                }
                .disabled(appState.analyticsEvents.isEmpty)
                .help("Exporta eventos estruturados em formato log_obtido.json")

                FluidPillButton(text: "Limpar", style: .destructiveText) {
                    Task {
                        await session.clearAnalytics()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.current.bgPanel)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(theme.current.border),
            alignment: .bottom
        )
        .task(id: appState.platform) {
            if appState.platform == .ios {
                await session.refreshAnalyticsIOSDevices()
            }
        }
    }

    /// Origem do tagueamento no iOS: o simulador ou um iPhone por cabo. O
    /// espelho so funciona com simulador, mas o log do Firebase vem dos dois.
    private var iosSourceMenu: some View {
        Menu {
            Button(checked("Automático", appState.analyticsIOSSource == .auto)) {
                appState.analyticsIOSSource = .auto
            }
            Button(checked("Simulador", appState.analyticsIOSSource == .simulator)) {
                appState.analyticsIOSSource = .simulator
            }
            Divider()
            if let hint = appState.analyticsIOSDeviceHint {
                Text("iPhone por cabo indisponível")
                Text(hint)
            } else if appState.analyticsIOSDevices.isEmpty {
                Text("Nenhum iPhone conectado por cabo")
            } else {
                ForEach(appState.analyticsIOSDevices) { device in
                    Button(checked(deviceLabel(device), appState.analyticsIOSSource == .device(udid: device.udid))) {
                        appState.analyticsIOSSource = .device(udid: device.udid)
                    }
                    .disabled(device.problem != nil)
                    .help(device.problem ?? "")
                }
            }
            Divider()
            Button("Atualizar lista") {
                Task { await session.refreshAnalyticsIOSDevices() }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 10))
                Text(sourceLabel)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundColor(theme.current.textSecondary)
            .frame(maxWidth: 170, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(appState.analyticsListenerActive)
        .help("De onde ler o tagueamento. Para trocar, pare a escuta.")
        .accessibilityLabel("Origem do tagueamento")
        .accessibilityValue(sourceLabel)
    }

    private func checked(_ label: String, _ isOn: Bool) -> String {
        isOn ? "✓ \(label)" : label
    }

    private func deviceLabel(_ device: IOSPhysicalDevice) -> String {
        let version = device.iosVersion.isEmpty ? "" : " · iOS \(device.iosVersion)"
        let problem = device.problem == nil ? "" : " (indisponível)"
        return "\(device.name)\(version)\(problem)"
    }

    private var sourceLabel: String {
        switch appState.analyticsIOSSource {
        case .auto: return "Automático"
        case .simulator: return "Simulador"
        case .device(let udid):
            return appState.analyticsIOSDevices.first { $0.udid == udid }?.name ?? "iPhone"
        }
    }

    private var sourceIcon: String {
        switch appState.analyticsIOSSource {
        case .auto: return "wand.and.stars"
        case .simulator: return "macbook.and.iphone"
        case .device: return "cable.connector"
        }
    }

    private func copyTSV() {
        guard !appState.analyticsEvents.isEmpty else {
            appState.statusMessage = "Nenhum evento de analytics para copiar"
            return
        }
        var lines: [String] = [
            "Hora\tPlataforma\tOrigem\tNome do Evento\tParâmetros Principais\tJSON dos Parâmetros"
        ]
        for ev in appState.analyticsEvents {
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
        let tsv = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tsv, forType: .string)
        appState.statusMessage = "✓ \(appState.analyticsEvents.count) eventos copiados como TSV (para Planilhas)!"
    }

    private func exportJSON() {
        guard !appState.analyticsEvents.isEmpty else {
            appState.statusMessage = "Nenhum evento de analytics para exportar"
            return
        }
        let dataArray: [[String: Any]] = appState.analyticsEvents.map { ev in
            [
                "id": ev.id,
                "time_str": ev.timeStr,
                "tag": ev.tag,
                "event_name": ev.eventName,
                "params": ev.params,
                "raw_log": ev.rawLog,
                "platform": ev.platform.rawValue
            ]
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dataArray, options: [.prettyPrinted, .sortedKeys]) else {
            appState.statusMessage = "Erro ao formatar eventos em JSON"
            return
        }
        let panel = NSSavePanel()
        panel.title = "Exportar Analytics (JSON)"
        panel.nameFieldStringValue = "log_obtido.json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try jsonData.write(to: url)
                appState.statusMessage = "✓ JSON de analytics salvo em: \(url.lastPathComponent)"
            } catch {
                appState.statusMessage = "Erro ao salvar JSON: \(error.localizedDescription)"
            }
        }
    }
}
