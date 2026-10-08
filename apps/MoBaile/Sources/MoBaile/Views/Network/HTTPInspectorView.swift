import AppKit
import SwiftUI

/// Área "Rede HTTP": barra acessória, tabela e detalhe da requisição.
///
/// O filtro foi para a busca da toolbar. A tabela é a do sistema: ordena pelo
/// cabeçalho e redimensiona as colunas.
struct HTTPInspectorView: View {
    @Environment(AppState.self) private var appState
    @Environment(EngineSession.self) private var session
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let theme = themeManager.current
        VStack(spacing: 0) {
            NetworkAccessoryBar()

            if appState.daemonStatus.proxy == .error {
                InlineError(
                    title: "Não foi possível iniciar o proxy.",
                    text: session.lastError,
                    actionLabel: "Tentar de Novo",
                    action: { Task { await session.toggleProxy() } }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if !appState.proxyRunning && !appState.iosDebugNetActive && appState.httpRequests.isEmpty {
                EmptyState(
                    icon: "network",
                    title: "O proxy está desligado",
                    text: "Inicie o proxy para registrar o tráfego HTTP do aparelho. As credenciais são redigidas.",
                    actionLabel: "Configurar Proxy",
                    action: { Task { await session.toggleProxy() } }
                )
            } else {
                VSplitView {
                    HTTPTableView()
                        .frame(minHeight: 100, idealHeight: 260)
                    detalhe
                        .frame(minHeight: 120, idealHeight: 260)
                }
            }
        }
        .background(theme.bgContent)
    }

    @ViewBuilder
    private var detalhe: some View {
        let theme = themeManager.current
        if let selected = appState.selectedRequest {
            HStack(spacing: 0) {
                RequestDetailView(event: selected)
                    .frame(maxWidth: .infinity)
                Rectangle().fill(theme.separator).frame(width: 1)
                ResponseDetailView(event: selected)
                    .frame(maxWidth: .infinity)
            }
        } else {
            EmptyState(icon: "info.circle", text: "Selecione uma requisição para ver os detalhes.", compact: true)
        }
    }
}

/// Estado do proxy à esquerda e as ações à direita. Em larguras estreitas os
/// botões ficam só com o ícone (o tooltip continua dizendo o que fazem).
private struct NetworkAccessoryBar: View {
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
        let theme = themeManager.current
        let porta = session.engineInfo?.proxy.port ?? 8082
        return HStack(spacing: 8) {
            if !compacto {
                StatusIndicator(
                    status: appState.proxyRunning ? .ok : .off,
                    label: appState.proxyRunning ? "Proxy \(porta) ativo" : "Proxy \(porta) inativo"
                )
            }
            Spacer(minLength: 8)
            if appState.platform == .ios {
                // Tráfego do app em debug lido pelo cabo, sem proxy nem
                // certificado (CFNETWORK_DIAGNOSTICS=3 no scheme do Xcode).
                Button {
                    Task { await session.toggleIOSDebugNet() }
                } label: {
                    rotulo(appState.iosDebugNetActive ? "Parar iPhone Debug" : "iPhone em Debug",
                           icone: appState.iosDebugNetActive ? "stop.circle" : "cable.connector", compacto: compacto)
                }
                .help("Lê pelo cabo as requisições do app em debug, sem proxy nem certificado. No scheme do Xcode, adicione a variável de ambiente CFNETWORK_DIAGNOSTICS=3.")
                .accessibilityLabel(appState.iosDebugNetActive
                                    ? "Parar leitura de tráfego do iPhone em debug"
                                    : "Ler tráfego do iPhone em debug")
            }
            Button {
                Task { await session.toggleProxy() }
            } label: {
                rotulo(appState.proxyRunning ? "Parar Proxy" : "Configurar Proxy", icone: "network", compacto: compacto)
            }
            .help(appState.proxyRunning
                  ? "Encerra o proxy e desfaz a rota reversa no aparelho"
                  : "Inicia o proxy MITM e configura a rota reversa no aparelho")
            .accessibilityLabel(appState.proxyRunning ? "Parar Proxy" : "Configurar Proxy")

            Button {
                Exporters.exportHAR(appState)
            } label: {
                rotulo("Exportar HAR…", icone: "square.and.arrow.up", compacto: compacto)
            }
            .disabled(appState.httpRequests.isEmpty)
            .help("Exporta o tráfego capturado no formato HAR 1.2")
            .accessibilityLabel("Exportar HAR…")

            Button("Limpar Tráfego") {
                appState.pendingClear = .network
            }
            .buttonStyle(PlainTextButtonStyle(theme: theme, destructive: true))
            .disabled(appState.httpRequests.isEmpty)
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
}

/// Tabela de requisições: método e status coloridos, mono onde é dado técnico.
struct HTTPTableView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager

    /// Mais nova primeiro: com a mais nova embaixo, cada requisição que chegava
    /// saía da área visível.
    @State private var ordem = [KeyPathComparator(\NetworkEvent.id, order: .reverse)]

    var body: some View {
        let theme = themeManager.current
        let linhas = appState.filteredHTTPRequests.sorted(using: ordem)

        Table(linhas, selection: selecao, sortOrder: $ordem) {
            TableColumn("Método", value: \.method) { event in
                Text(event.method)
                    .font(DSFont.mono(11, weight: .medium))
                    .foregroundStyle(theme.methodColor(event.method))
                    .accessibilityLabel(event.accessibilitySummary)
            }
            .width(min: 56, ideal: 72, max: 110)

            TableColumn("Status", value: \.statusSortKey) { event in
                Text(event.statusCode.map(String.init) ?? "—")
                    .font(DSFont.mono(11))
                    .foregroundStyle(theme.statusColor(event.statusCode))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 44, ideal: 56, max: 80)

            TableColumn("Host", value: \.host) { event in
                Text(event.host).font(DSFont.mono(11)).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 100, ideal: 180)

            TableColumn("Caminho", value: \.path) { event in
                Text(event.path).font(DSFont.mono(11)).lineLimit(1).truncationMode(.middle)
            }
            .width(min: 100, ideal: 240)

            TableColumn("Tamanho", value: \.sizeBytes) { event in
                Text(event.formattedSize)
                    .font(DSFont.callout.monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 68, max: 100)

            TableColumn("Tempo", value: \.durationSortKey) { event in
                Text(event.formattedDuration)
                    .font(DSFont.callout.monospacedDigit())
                    .foregroundStyle(event.durationMs == nil ? theme.labelTertiary : theme.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 64, max: 100)
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: NetworkEvent.ID.self) { ids in
            if let id = ids.first, let event = appState.httpRequests.first(where: { $0.id == id }) {
                Button("Copiar URL") {
                    Exporters.copy(event.url)
                    appState.statusMessage = "URL copiada"
                }
                Button("Copiar como cURL") {
                    Exporters.copy(Exporters.curl(for: event))
                    appState.statusMessage = "cURL copiado"
                }
                Divider()
                Button("Exportar HAR…") { Exporters.exportHAR(appState) }
            }
        }
        .overlay {
            if linhas.isEmpty {
                EmptyState(
                    icon: appState.httpFilterText.isEmpty ? "antenna.radiowaves.left.and.right" : "magnifyingglass",
                    text: appState.httpFilterText.isEmpty
                        ? "Aguardando tráfego do aparelho…"
                        : "Nenhuma requisição corresponde ao filtro.",
                    compact: true
                )
                .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Requisições HTTP")
    }

    private var selecao: Binding<NetworkEvent.ID?> {
        Binding(
            get: { appState.selectedRequest?.id },
            set: { id in
                appState.selectedRequest = id.flatMap { alvo in appState.httpRequests.first { $0.id == alvo } }
            }
        )
    }
}

extension NetworkEvent {
    /// A frase que o leitor de tela lê no lugar das células da linha.
    var accessibilitySummary: String {
        var partes = ["\(method) \(host)\(path)", statusCode.map { "status \($0)" } ?? "sem status", formattedSize]
        if durationMs != nil { partes.append(formattedDuration) }
        return partes.joined(separator: ", ")
    }

    var statusSortKey: Int { statusCode ?? -1 }
    var sizeBytes: Int { responseBody.utf8.count }
    var durationSortKey: Int { durationMs ?? -1 }

    /// Túnel HTTPS: o `CONNECT` sem corpo de resposta.
    var isHTTPSTunnel: Bool {
        isTunnel || (method.uppercased() == "CONNECT" && responseBody.isEmpty)
    }

    static func prettyBody(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return text
        }
        return prettyString
    }
}
