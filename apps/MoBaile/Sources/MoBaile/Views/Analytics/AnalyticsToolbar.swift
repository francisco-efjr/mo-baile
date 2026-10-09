import SwiftUI

/// Barra acessória de Analytics: estado da escuta, origem do tagueamento no
/// iOS e as ações. Segue a estrutura de Rede de propósito.
struct AnalyticsToolbar: View {
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
        .task(id: appState.platform) {
            if appState.platform == .ios {
                await session.refreshAnalyticsIOSDevices()
            }
        }
    }

    private func conteudo(compacto: Bool) -> some View {
        let theme = themeManager.current
        let ouvindo = appState.analyticsListenerActive
        return HStack(spacing: 8) {
            if !compacto {
                StatusIndicator(status: ouvindo ? .ok : .off, label: ouvindo ? "FA Listener ativo" : "FA Listener inativo")
            }
            if appState.platform == .ios {
                iosSourceMenu(compacto: compacto)
            }
            Spacer(minLength: 8)

            Button {
                Task { await session.toggleAnalytics() }
            } label: {
                rotulo(ouvindo ? "Parar Escuta" : "Iniciar Escuta",
                       icone: ouvindo ? "stop.circle" : "antenna.radiowaves.left.and.right", compacto: compacto)
            }
            .disabled(!ouvindo && !appState.canStartAnalytics)
            .help(ouvindo ? "Encerra a captura de eventos de Analytics" : "Inicia a captura de eventos de Firebase Analytics no aparelho")
            .accessibilityLabel(ouvindo ? "Parar Escuta" : "Iniciar Escuta")

            Button {
                Exporters.copyAnalyticsTSV(appState)
            } label: {
                rotulo("Copiar TSV", icone: "doc.on.clipboard", compacto: compacto)
            }
            .disabled(appState.analyticsEvents.isEmpty)
            .help("Copia a tabela em TSV para colar no Google Planilhas")
            .accessibilityLabel("Copiar TSV")

            Button {
                Exporters.exportAnalyticsJSON(appState)
            } label: {
                rotulo("Exportar JSON…", icone: "square.and.arrow.up", compacto: compacto)
            }
            .disabled(appState.analyticsEvents.isEmpty)
            .help("Exporta os eventos em log_obtido.json")
            .accessibilityLabel("Exportar JSON…")

            Button("Limpar") {
                appState.pendingClear = .analytics
            }
            .buttonStyle(PlainTextButtonStyle(theme: theme, destructive: true))
            .disabled(appState.analyticsEvents.isEmpty)
            .accessibilityLabel("Limpar eventos")
        }
    }

    @ViewBuilder
    private func rotulo(_ texto: String, icone: String, compacto: Bool) -> some View {
        if compacto {
            Image(systemName: icone)
        } else {
            Label(texto, systemImage: icone)
        }
    }

    /// Origem do tagueamento no iOS: o simulador ou um iPhone por cabo. O
    /// espelho só funciona com simulador, mas o log do Firebase vem dos dois.
    private func iosSourceMenu(compacto: Bool) -> some View {
        Menu {
            Toggle("Automático", isOn: origem(.auto))
            Toggle("Simulador", isOn: origem(.simulator))
            Divider()
            if let hint = appState.analyticsIOSDeviceHint {
                Text("iPhone por cabo indisponível")
                Text(hint)
            } else if appState.analyticsIOSDevices.isEmpty {
                Text("Nenhum iPhone conectado por cabo")
            } else {
                ForEach(appState.analyticsIOSDevices) { device in
                    Toggle(deviceLabel(device), isOn: origem(.device(udid: device.udid)))
                        .disabled(device.problem != nil)
                }
            }
            Divider()
            Button("Atualizar Lista") {
                Task { await session.refreshAnalyticsIOSDevices() }
            }
        } label: {
            Label(sourceLabel, systemImage: sourceIcon)
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .tint(themeManager.current.labelPrimary)
        .fixedSize()
        .disabled(appState.analyticsListenerActive)
        .help(appState.analyticsListenerActive
              ? "Para trocar a origem, pare a escuta"
              : "De onde ler o tagueamento")
        .accessibilityLabel("Origem do tagueamento")
        .accessibilityValue(sourceLabel)
    }

    private func origem(_ alvo: AnalyticsIOSSource) -> Binding<Bool> {
        Binding(
            get: { appState.analyticsIOSSource == alvo },
            set: { if $0 { appState.analyticsIOSSource = alvo } }
        )
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
}
