import SwiftUI

/// Área "Analytics": barra acessória, tabela de eventos e detalhe
/// (Parâmetros | Log Bruto).
struct AnalyticsInspectorView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    @State private var ordem = [KeyPathComparator(\AnalyticsEvent.id, order: .reverse)]

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            AnalyticsToolbar()

            if !appState.analyticsListenerActive && appState.analyticsEvents.isEmpty {
                EmptyState(
                    icon: "chart.xyaxis.line",
                    title: "Nenhum evento capturado",
                    text: "Inicie a escuta para ver os eventos de Firebase Analytics em tempo real.",
                    actionLabel: appState.canStartAnalytics ? "Iniciar Escuta" : nil,
                    action: { Task { await session.toggleAnalytics() } }
                )
            } else {
                VSplitView {
                    tabela
                        .frame(minHeight: 100, idealHeight: 260)
                    detalhe
                        .frame(minHeight: 120, idealHeight: 260)
                }
            }
        }
        .background(theme.bgContent)
    }

    private var tabela: some View {
        let theme = themeManager.current
        let linhas = appState.filteredAnalyticsEvents.sorted(using: ordem)
        return Table(linhas, selection: selecao, sortOrder: $ordem) {
            TableColumn("Hora", value: \.timeStr) { event in
                Text(event.timeStr)
                    .font(DSFont.mono(11).monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel(event.accessibilitySummary)
            }
            .width(min: 80, ideal: 100, max: 130)

            TableColumn("Evento", value: \.eventName) { event in
                Text(event.eventName)
                    .font(DSFont.mono(11, weight: .medium))
                    .foregroundStyle(theme.accentText)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 260)

            TableColumn("Parâmetros", value: \.paramCount) { event in
                Text("\(event.paramCount)")
                    .font(DSFont.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 84, max: 110)

            TableColumn("Origem", value: \.tag) { event in
                Text(event.tag).font(DSFont.callout).lineLimit(1)
            }
            .width(min: 70, ideal: 110, max: 160)
        }
        .alternatingRowBackgrounds()
        .overlay {
            if linhas.isEmpty {
                EmptyState(
                    icon: appState.analyticsFilterText.isEmpty ? "antenna.radiowaves.left.and.right" : "magnifyingglass",
                    text: appState.analyticsFilterText.isEmpty ? "Aguardando eventos…" : "Nenhum evento corresponde ao filtro.",
                    compact: true
                )
                .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Eventos de analytics")
    }

    private var selecao: Binding<AnalyticsEvent.ID?> {
        Binding(
            get: { appState.selectedAnalyticsEvent?.id },
            set: { id in
                appState.selectedAnalyticsEvent = id.flatMap { alvo in appState.analyticsEvents.first { $0.id == alvo } }
            }
        )
    }

    @ViewBuilder
    private var detalhe: some View {
        let theme = themeManager.current
        if let selected = appState.selectedAnalyticsEvent {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    DetailHeader(
                        title: "Parâmetros",
                        copyLabel: "Copiar parâmetros",
                        onCopy: {
                            Exporters.copy(selected.params.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))
                        }
                    ) {
                        CountBadge(value: selected.params.count)
                    } tabs: {
                        EmptyView()
                    }
                    ScrollView {
                        if selected.params.isEmpty {
                            EmptyState(icon: "tag", text: "Evento sem parâmetros.", compact: true)
                        } else {
                            KeyValueGrid(rows: selected.params.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(theme.separator).frame(width: 1)

                VStack(spacing: 0) {
                    DetailHeader(
                        title: "Log Bruto",
                        copyLabel: "Copiar log bruto",
                        onCopy: { Exporters.copy(selected.rawLog) }
                    ) {
                        Text(selected.tag)
                            .font(DSFont.subheadline)
                            .foregroundStyle(theme.labelSecondary)
                    } tabs: {
                        EmptyView()
                    }
                    ScrollView {
                        CodeBlock(text: selected.rawLog)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            EmptyState(icon: "info.circle", text: "Selecione um evento para ver os detalhes.", compact: true)
        }
    }
}

extension AnalyticsEvent {
    /// A frase que o leitor de tela lê no lugar das células da linha.
    var accessibilitySummary: String {
        let parametros = paramCount == 1 ? "1 parâmetro" : "\(paramCount) parâmetros"
        return "\(eventName), \(parametros), origem \(tag), \(timeStr)"
    }
}
