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

            if !appState.proxyRunning && !appState.debugNetActive && appState.httpRequests.isEmpty {
                EmptyState(
                    icon: "network",
                    title: "O proxy está desligado",
                    text: "Inicie o proxy para registrar o tráfego HTTP do aparelho, ou leia o app em debug sem proxy com \(DebugNetCopy(appState.platform).titulo). As credenciais são redigidas.",
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
            // Tráfego do app em debug sem proxy nem certificado: CFNetwork no
            // iPhone, log do OkHttp no Android.
            let copia = DebugNetCopy(appState.platform)
            Button {
                Task { await session.toggleDebugNet() }
            } label: {
                rotulo(appState.debugNetActive ? copia.parar : copia.titulo,
                       icone: appState.debugNetActive ? "stop.circle" : copia.icone, compacto: compacto)
            }
            .disabled(appState.platform == .android && !appState.isDeviceConnected && !appState.debugNetActive)
            .help(copia.ajuda)
            .accessibilityLabel(appState.debugNetActive ? copia.pararAcessivel : copia.iniciarAcessivel)
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

    /// JSON indentado para leitura, com os valores exatamente como vieram.
    ///
    /// Antes o corpo passava por `JSONSerialization` ida e volta: `28.4` virava
    /// `28.399999999999999`, a ordem das chaves mudava e o que aparecia não era
    /// o que o servidor mandou. Agora o `JSONSerialization` só confere que é
    /// JSON; a indentação é feita sobre o texto original, sem reinterpretar
    /// número, string nem ordem.
    static func prettyBody(_ text: String) -> String {
        let corpo = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard corpo.first == "{" || corpo.first == "[",
              let data = corpo.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else {
            return text
        }
        return indentJSON(corpo)
    }

    /// Reindenta JSON já válido, dois espaços por nível, sem tocar em literal.
    static func indentJSON(_ json: String) -> String {
        var saida = ""
        var nivel = 0
        var emString = false
        var escapando = false
        let caracteres = Array(json)
        var indice = 0

        func quebra() {
            saida += "\n" + String(repeating: "  ", count: nivel)
        }
        func proximoSignificativo(_ de: Int) -> Character? {
            var i = de
            while i < caracteres.count, caracteres[i].isWhitespace { i += 1 }
            return i < caracteres.count ? caracteres[i] : nil
        }

        while indice < caracteres.count {
            let c = caracteres[indice]
            indice += 1
            if emString {
                saida.append(c)
                if escapando {
                    escapando = false
                } else if c == "\\" {
                    escapando = true
                } else if c == "\"" {
                    emString = false
                }
                continue
            }
            switch c {
            case "\"":
                emString = true
                saida.append(c)
            case "{", "[":
                saida.append(c)
                let fecha: Character = c == "{" ? "}" : "]"
                if proximoSignificativo(indice) == fecha {
                    // Vazio fica numa linha só: {} e [].
                    while caracteres[indice].isWhitespace { indice += 1 }
                    saida.append(fecha)
                    indice += 1
                } else {
                    nivel += 1
                    quebra()
                }
            case "}", "]":
                nivel = max(0, nivel - 1)
                quebra()
                saida.append(c)
            case ",":
                saida.append(c)
                quebra()
            case ":":
                saida += ": "
            default:
                if !c.isWhitespace { saida.append(c) }
            }
        }
        return saida
    }
}

/// Textos do "app em debug" por plataforma. O recurso é o mesmo (tráfego HTTPS
/// sem proxy); muda de onde o motor lê e o que o app precisa ter.
struct DebugNetCopy {
    let titulo: String
    let parar: String
    let icone: String
    let ajuda: String
    let iniciarAcessivel: String
    let pararAcessivel: String

    init(_ plataforma: Platform) {
        switch plataforma {
        case .ios:
            titulo = "iPhone em Debug"
            parar = "Parar iPhone Debug"
            icone = "cable.connector"
            ajuda = "Lê pelo cabo as requisições do app em debug, sem proxy nem certificado. No scheme do Xcode, adicione a variável de ambiente CFNETWORK_DIAGNOSTICS=3."
            iniciarAcessivel = "Ler tráfego do iPhone em debug"
            pararAcessivel = "Parar leitura de tráfego do iPhone em debug"
        case .android:
            titulo = "App em Debug"
            parar = "Parar App Debug"
            icone = "ladybug"
            ajuda = "Lê pelo logcat as requisições do app em debug, sem proxy nem certificado, e funciona com o debugger do Android Studio conectado. O build de debug precisa do HttpLoggingInterceptor do OkHttp (nível BODY para ver os corpos)."
            iniciarAcessivel = "Ler tráfego do app Android em debug"
            pararAcessivel = "Parar leitura de tráfego do app Android em debug"
        }
    }
}
