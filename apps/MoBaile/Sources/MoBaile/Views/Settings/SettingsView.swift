import SwiftUI

/// Janela de Ajustes (⌘,): abas Geral e Conexões. As mudanças valem na hora,
/// sem Salvar nem Cancelar.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Geral", systemImage: "gearshape") }
            ConnectionSettings()
                .tabItem { Label("Conexões", systemImage: "cable.connector") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @AppStorage(LocatorStrategy.defaultKey) private var seletorPadrao: LocatorStrategy = .auto

    var body: some View {
        @Bindable var state = appState
        Form {
            Picker("Aparência:", selection: Binding(
                get: { themeManager.mode },
                set: { themeManager.setMode($0) }
            )) {
                Text("Sistema").tag(ThemeMode.system)
                Text("Claro").tag(ThemeMode.light)
                Text("Escuro").tag(ThemeMode.dark)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Picker("Seletor padrão:", selection: $seletorPadrao) {
                ForEach(LocatorStrategy.allCases) { Text($0.displayName).tag($0) }
            }
            .fixedSize()
            .onChange(of: seletorPadrao) { _, novo in appState.locatorStrategy = novo }
            .help("Estratégia com que o app abre. Auto: o motor escolhe o localizador único mais robusto.")

            Divider()

            LabeledContent("Ao conectar:") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Iniciar o espelho automaticamente", isOn: $state.autoStartStream)
                    Text("O espelho começa assim que um aparelho é detectado.")
                        .font(DSFont.subheadline)
                        .foregroundStyle(themeManager.current.labelSecondary)
                }
            }
        }
        .formStyle(.columns)
        .padding(DesignMetrics.Spacing.windowMargin)
    }
}

/// Endereços que o motor usa. Vêm da configuração do motor e aparecem só para
/// leitura: o protocolo não tem como mudá-los com o motor no ar.
private struct ConnectionSettings: View {
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        Form {
            LabeledContent("WebDriverAgent:") {
                valor(session.engineInfo?.wdaUrl)
            }
            LabeledContent("Host do proxy:") {
                VStack(alignment: .leading, spacing: 4) {
                    valor(session.engineInfo?.proxy.host)
                    Text("Mantenha 127.0.0.1. Escutar em 0.0.0.0 transforma a máquina em proxy aberto para a rede.")
                        .font(DSFont.subheadline)
                        .foregroundStyle(theme.labelSecondary)
                        .frame(maxWidth: 240, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            LabeledContent("Porta do proxy:") {
                valor(session.engineInfo.map { String($0.proxy.port) })
            }
            LabeledContent("adb:") {
                valor(session.engineInfo.map { $0.adbAvailable ? $0.adbPath : "não encontrado" })
            }
            Text("Esses valores vêm da configuração do motor e valem para a sessão inteira.")
                .font(DSFont.subheadline)
                .foregroundStyle(theme.labelSecondary)
        }
        .formStyle(.columns)
        .padding(DesignMetrics.Spacing.windowMargin)
    }

    private func valor(_ texto: String?) -> some View {
        Text(texto ?? "motor não conectado")
            .font(DSFont.mono(12))
            .foregroundStyle(texto == nil ? themeManager.current.labelTertiary : themeManager.current.labelPrimary)
            .textSelection(.enabled)
    }
}
