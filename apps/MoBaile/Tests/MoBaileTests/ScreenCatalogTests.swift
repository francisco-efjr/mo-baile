import XCTest
import SwiftUI
import AppKit
@testable import MoBaile

/// Catálogo visual de todas as telas e estados do app, em tema claro e escuro.
///
/// Não é suíte de asserção: é ferramenta para revisar identidade visual. Gera
/// os PNGs de `docs/design/telas/` (ver o `CHECKLIST.md` de lá). Roda só quando
/// `MOBAILE_SNAPSHOT_DIR` está definido; sem a variável, todos os testes pulam.
///
/// Por que não `ImageRenderer`, como em `LayoutSnapshotTests`: ele não desenha
/// view com AppKit por baixo (`NSViewRepresentable`, `HSplitView`, `List`,
/// `Table`, `Menu`, `TextField`) e põe um "proibido" amarelo no lugar. O
/// editor de código e os painéis divididos somem. Aqui a view vai para um
/// `NSHostingView` dentro de uma janela que nunca é mostrada, e o
/// `cacheDisplay` desenha num bitmap 2x. Também não precisa de permissão de
/// tela, porque nada é capturado do display.
///
/// O estado é montado como em `LayoutSnapshotTests`: `AppState` +
/// `EngineSession(state:client:)` com `FakeEngine` + `ThemeManager`. O motor
/// falso responde com as fixtures reais, com `engine.info` e a lista de
/// simuladores trocados por um cenário de iOS (iPhone 16, 1179x2556).
@MainActor
final class ScreenCatalogTests: XCTestCase {

    // MARK: - Temas

    enum Tema: String, CaseIterable {
        case claro, escuro

        var modo: ThemeMode { self == .claro ? .light : .dark }
        var aparencia: NSAppearance? { NSAppearance(named: self == .claro ? .aqua : .darkAqua) }
        var esquema: ColorScheme { self == .claro ? .light : .dark }
    }

    struct Cena {
        let estado: AppState
        let sessao: EngineSession
        let tema: ThemeManager
    }

    // MARK: - Dados de exemplo (iOS)

    static let udid = "5F3C1E2A-7B9D-4C61-8E0F-2A6B9C4D1E73"
    static let chave = "onboarding_credito_objs"

    private static let engineInfo = #"""
    {"version": "2.1.2", "platform": "ios", "device_id": "5F3C1E2A-7B9D-4C61-8E0F-2A6B9C4D1E73",
     "adb_path": "adb", "adb_available": false, "scrcpy_available": false,
     "wda_url": "http://localhost:8100", "page_objects_key": "onboarding_credito_objs",
     "proxy": {"host": "127.0.0.1", "port": 8082, "running": false}, "methods": []}
    """#

    private static let simuladores = #"""
    {"simulators": [
      {"udid": "5F3C1E2A-7B9D-4C61-8E0F-2A6B9C4D1E73", "name": "iPhone 16", "state": "Booted",
       "runtime": "iOS 18.6", "booted": true},
      {"udid": "1A2B3C4D-0000-4000-8000-0000000000BB", "name": "iPad Air 11-inch (M3)", "state": "Shutdown",
       "runtime": "iOS 18.6", "booted": false}
    ]}
    """#

    private static let diagnosticoPronto = #"""
    {"ios": {"platform": "ios", "title": "iOS · WebDriverAgent", "ready": true, "checks": [
        {"label": "Ferramentas do Xcode", "state": "ok", "detail": "xcrun disponivel", "action": null},
        {"label": "Simulador instalado", "state": "ok", "detail": "2 disponiveis", "action": null},
        {"label": "Simulador ligado", "state": "ok", "detail": "iPhone 16", "action": null},
        {"label": "WebDriverAgent", "state": "ok", "detail": "Respondendo em http://localhost:8100", "action": null}]},
     "android": {"platform": "android", "title": "Android · ADB", "ready": false, "checks": [
        {"label": "ADB instalado", "state": "error", "detail": "adb nao encontrado no PATH. Instale com brew install android-platform-tools.", "action": null},
        {"label": "Dispositivo autorizado", "state": "off", "detail": "", "action": null},
        {"label": "Emulador disponivel", "state": "warn", "detail": "Nenhum AVD criado.", "action": null}]}}
    """#

    static let codigoPages = """
    def click_botao_simular_credito(self):
        self.wait_to_be_visible(self.locators['onboarding_credito_objs'].BOTAO_SIMULAR_CREDITO, 15)
        self.click(self.locators['onboarding_credito_objs'].BOTAO_SIMULAR_CREDITO, 2)

    def preencher_campo_cpf(self, texto):
        self.wait_to_be_visible(self.locators['onboarding_credito_objs'].CAMPO_CPF, 15)
        self.send_keys(self.locators['onboarding_credito_objs'].CAMPO_CPF, texto)

    def preencher_campo_valor(self, texto):
        self.wait_to_be_visible(self.locators['onboarding_credito_objs'].CAMPO_VALOR, 15)
        self.send_keys(self.locators['onboarding_credito_objs'].CAMPO_VALOR, texto)

    def click_botao_continuar(self):
        self.wait_to_be_visible(self.locators['onboarding_credito_objs'].BOTAO_CONTINUAR, 15)
        self.click(self.locators['onboarding_credito_objs'].BOTAO_CONTINUAR, 2)

    def click_botao_confirmar_contratacao(self):
        self.wait_to_be_visible(self.locators['onboarding_credito_objs'].BOTAO_CONFIRMAR_CONTRATACAO, 15)
        self.click(self.locators['onboarding_credito_objs'].BOTAO_CONFIRMAR_CONTRATACAO, 2)

    """

    static let codigoLocators = """
    from appium.webdriver.common.appiumby import AppiumBy

    BOTAO_SIMULAR_CREDITO = (AppiumBy.ACCESSIBILITY_ID, "Simular crédito")
    CAMPO_CPF = (AppiumBy.ACCESSIBILITY_ID, "campo_cpf")
    CAMPO_VALOR = (AppiumBy.ACCESSIBILITY_ID, "campo_valor")
    BOTAO_CONTINUAR = (AppiumBy.ACCESSIBILITY_ID, "Continuar")
    BOTAO_CONFIRMAR_CONTRATACAO = (AppiumBy.XPATH, '//XCUIElementTypeButton[@name="Confirmar contratação"]')

    """

    static func passos() -> [AutomationStep] {
        func passo(_ n: Int, _ acao: String, _ variavel: String, _ nome: String, _ classe: String,
                   _ estrategia: LocatorStrategy, _ valor: String, coords: CGPoint? = nil, texto: String? = nil) -> AutomationStep {
            AutomationStep(stepNum: n, actionType: acao, varName: variavel, elementName: nome, className: classe,
                           strategy: estrategia, locatorValue: valor, coords: coords, inputText: texto,
                           package: "br.com.bancopraia.app", platform: .ios)
        }
        return [
            passo(1, "click", "BOTAO_SIMULAR_CREDITO", "Simular crédito", "XCUIElementTypeButton", .id, "Simular crédito"),
            passo(2, "send_keys", "CAMPO_CPF", "campo_cpf", "XCUIElementTypeTextField", .id, "campo_cpf", texto: "•••••••••••"),
            passo(3, "send_keys", "CAMPO_VALOR", "campo_valor", "XCUIElementTypeTextField", .id, "campo_valor", texto: "5000"),
            passo(4, "click", "BOTAO_CONTINUAR", "Continuar", "XCUIElementTypeButton", .id, "Continuar"),
            passo(5, "click", "BOTAO_CONFIRMAR_CONTRATACAO", "Confirmar contratação", "XCUIElementTypeButton", .xpath,
                  "//XCUIElementTypeButton[@name=\"Confirmar contratação\"]"),
            passo(6, "click", "TOQUE_FECHAR", "", "XCUIElementTypeOther", .coords, "position", coords: CGPoint(x: 1095, y: 210)),
        ]
    }

    /// Árvore XCUITest do mock de tela, em pixels do aparelho (1179x2556, @3x).
    static func elementos(achatada: Bool = false) -> [UIElement] {
        func el(_ classe: String, _ nome: String, _ texto: String, _ r: CGRect, pai: Int?, prof: Int, clicavel: Bool = false) -> UIElement {
            let px = CGRect(x: r.minX * 3, y: r.minY * 3, width: r.width * 3, height: r.height * 3)
            return UIElement(tag: classe, className: classe, resourceId: nome, text: texto, contentDesc: "",
                             clickable: clicavel, bounds: px, area: Int(px.width * px.height),
                             package: "br.com.bancopraia.app", platform: .ios, depth: prof,
                             parentIndex: achatada ? nil : pai)
        }
        return [
            el("XCUIElementTypeApplication", "Banco Praia", "", CGRect(x: 0, y: 0, width: 393, height: 852), pai: nil, prof: 0),
            el("XCUIElementTypeWindow", "", "", CGRect(x: 0, y: 0, width: 393, height: 852), pai: 0, prof: 1),
            el("XCUIElementTypeNavigationBar", "Crédito pessoal", "", CGRect(x: 0, y: 54, width: 393, height: 52), pai: 1, prof: 2),
            el("XCUIElementTypeButton", "Voltar", "Voltar", CGRect(x: 8, y: 60, width: 44, height: 40), pai: 2, prof: 3, clicavel: true),
            el("XCUIElementTypeStaticText", "Crédito pessoal", "Crédito pessoal", CGRect(x: 120, y: 68, width: 153, height: 24), pai: 2, prof: 3),
            el("XCUIElementTypeOther", "conteudo", "", CGRect(x: 0, y: 106, width: 393, height: 746), pai: 1, prof: 2),
            el("XCUIElementTypeStaticText", "titulo_simulacao", "Simule seu crédito em minutos", CGRect(x: 24, y: 330, width: 345, height: 64), pai: 5, prof: 3),
            el("XCUIElementTypeStaticText", "subtitulo_simulacao", "Sem compromisso. A taxa aparece antes de você contratar.", CGRect(x: 24, y: 400, width: 345, height: 40), pai: 5, prof: 3),
            el("XCUIElementTypeTextField", "campo_cpf", "CPF", CGRect(x: 24, y: 480, width: 345, height: 52), pai: 5, prof: 3, clicavel: true),
            el("XCUIElementTypeTextField", "campo_valor", "Valor desejado", CGRect(x: 24, y: 566, width: 345, height: 52), pai: 5, prof: 3, clicavel: true),
            el("XCUIElementTypeButton", "Continuar", "Continuar", CGRect(x: 24, y: 716, width: 345, height: 54), pai: 5, prof: 3, clicavel: true),
            el("XCUIElementTypeButton", "Agora não", "Agora não", CGRect(x: 140, y: 784, width: 113, height: 32), pai: 5, prof: 3, clicavel: true),
        ]
    }

    static func requisicoes() -> [NetworkEvent] {
        let agora = Date(timeIntervalSince1970: 1_791_558_131)
        func req(_ id: Int, _ hora: String, _ metodo: String, _ host: String, _ path: String, _ status: Int?,
                 _ texto: String, reqH: [String: String] = [:], reqB: String = "", resH: [String: String] = [:],
                 resB: String = "", ms: Int?, tunel: Bool = false, erro: String? = nil) -> NetworkEvent {
            NetworkEvent(id: id, timestamp: agora.addingTimeInterval(Double(id)), timeStr: hora, method: metodo,
                         url: "https://\(host)\(path)", host: host, path: path, statusCode: status, statusText: texto,
                         requestHeaders: reqH, requestBody: reqB, responseHeaders: resH, responseBody: resB,
                         durationMs: ms, protocol: "HTTP/2", isTunnel: tunel, error: erro)
        }
        let cabecalhos = [
            "Authorization": "Bearer eyJhbGciOi…",
            "Content-Type": "application/json",
            "User-Agent": "BancoPraia/5.42.0 (iPhone; iOS 18.6; Scale/3.00)",
            "X-Correlation-Id": "7c1e9f4a-2b3d-4e5f-9a8b-0c1d2e3f4a5b",
            "Accept-Language": "pt-BR",
        ]
        let resposta = ["Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store",
                        "X-Request-Id": "req_01HZX9K2", "Server": "envoy"]
        return [
            req(1, "13:02:11.204", "GET", "api.bancopraia.com.br", "/v2/credito/ofertas", 200, "OK",
                reqH: cabecalhos, resH: resposta,
                resB: #"{"ofertas":[{"id":"pessoal","taxa_mensal":1.89,"limite":15000}],"atualizado_em":"2026-10-08T13:02:11Z"}"#, ms: 342),
            req(2, "13:02:14.918", "POST", "api.bancopraia.com.br", "/v2/credito/simulacao", 201, "Created",
                reqH: cabecalhos, reqB: #"{"cpf":"***.***.***-**","valor":5000,"parcelas":12}"#, resH: resposta,
                resB: #"{"simulacao_id":"sim_8f2c","valor_parcela":487.32,"cet_anual":28.4,"parcelas":12,"primeiro_vencimento":"2026-11-10"}"#,
                ms: 812),
            req(3, "13:02:15.002", "POST", "firebaselogging-pa.googleapis.com", "/v1/firelog/legacy/batchlog", 200, "OK",
                reqH: ["Content-Type": "application/x-protobuf"], resB: "{}", ms: 128),
            req(4, "13:02:15.310", "CONNECT", "app-measurement.com", ":443", 200, "Connection Established", ms: 58, tunel: true),
            req(5, "13:02:16.477", "GET", "cdn.bancopraia.com.br", "/img/onboarding/credito@3x.png", 304, "Not Modified",
                resH: ["Cache-Control": "max-age=86400", "ETag": "\"a1b2c3\""], ms: 41),
            req(6, "13:02:19.733", "POST", "api.bancopraia.com.br", "/v2/credito/contratacao", 422, "Unprocessable Entity",
                reqH: cabecalhos, reqB: #"{"simulacao_id":"sim_8f2c","aceite":true}"#, resH: resposta,
                resB: #"{"erro":"limite_excedido","mensagem":"Valor acima do limite pré-aprovado."}"#, ms: 266),
            req(7, "13:02:20.105", "GET", "api.bancopraia.com.br", "/v2/clientes/me/preferencias", 500, "Internal Server Error",
                reqH: cabecalhos, resH: resposta, resB: #"{"erro":"interno"}"#, ms: 1840),
            req(8, "13:02:21.990", "DELETE", "api.bancopraia.com.br", "/v2/credito/simulacao/sim_8f2c", nil, "",
                reqH: cabecalhos, ms: nil),
        ]
    }

    static func eventos() -> [AnalyticsEvent] {
        let agora = Date(timeIntervalSince1970: 1_791_558_131)
        func ev(_ id: Int, _ hora: String, _ nome: String, _ params: [String: String]) -> AnalyticsEvent {
            let json = params.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            return AnalyticsEvent(
                id: id, timestamp: agora.addingTimeInterval(Double(id)), timeStr: hora, tag: "iOS (Firebase)",
                eventName: nome, params: params,
                rawLog: "2026-10-08 \(hora) BancoPraia[4821:91234] 11.3.0 - [FirebaseAnalytics][I-ACS023051] Logging event: origin, name, params: app, \(nome), {\n    \(json)\n}",
                platform: .ios)
        }
        return [
            ev(1, "13:02:10.880", "session_start", [:]),
            ev(2, "13:02:11.102", "screen_view", ["firebase_screen": "onboarding_credito",
                                                  "firebase_screen_class": "OnboardingCreditoViewController",
                                                  "firebase_previous_screen": "home"]),
            ev(3, "13:02:12.340", "select_content", ["content_type": "botao", "item_id": "simular_credito"]),
            ev(4, "13:02:14.920", "simulacao_credito_iniciada", ["valor": "5000", "parcelas": "12", "produto": "pessoal",
                                                                 "canal": "app_ios"]),
            ev(5, "13:02:18.051", "clique_continuar", ["tela": "simulacao", "etapa": "2"]),
            ev(6, "13:02:19.740", "erro_contratacao", ["codigo": "limite_excedido", "tela": "confirmacao"]),
        ]
    }

    // MARK: - Montagem

    private func fixtures() throws -> [String: Data] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine_payloads", withExtension: "json"))
        let raiz = try XCTUnwrap(JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any])
        var saida: [String: Data] = [:]
        for (metodo, envelope) in raiz {
            guard let envelope = envelope as? [String: Any], let resultado = envelope["result"] else { continue }
            saida[metodo] = try JSONSerialization.data(withJSONObject: resultado)
        }
        return saida
    }

    private func pasta() throws -> URL {
        guard let destino = ProcessInfo.processInfo.environment["MOBAILE_SNAPSHOT_DIR"] else {
            throw XCTSkip("defina MOBAILE_SNAPSHOT_DIR para gerar o catálogo de telas")
        }
        let url = URL(fileURLWithPath: destino)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Estado de partida: iOS, iPhone 16 conectado, motor respondendo.
    private func novaCena(_ t: Tema, conectado: Bool = true, extras: [String: Data] = [:],
                          semDiagnostico: Bool = false) async throws -> Cena {
        var respostas = try fixtures()
        respostas["engine.info"] = Data(Self.engineInfo.utf8)
        respostas["simulators.list"] = Data(Self.simuladores.utf8)
        // As fixtures não trazem resultado para esta chamada; sem ela a barra
        // de analytics deixa "O motor nao esta em execucao." na barra de status.
        respostas["analytics.ios_devices"] = Data(#"""
        {"available": true, "hint": null, "devices": [{"udid": "00008140-001A2B3C4D5E6F7A",
         "name": "iPhone 15 (QA)", "ios_version": "18.6", "connection": "USB"}]}
        """#.utf8)
        if semDiagnostico { respostas["diagnostics.check"] = nil }
        respostas.merge(extras) { $1 }

        let estado = AppState()
        estado.platform = .ios
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: respostas))
        await sessao.refreshDaemonStatus()   // preenche engineInfo (portas, chave do Page Object)
        await sessao.refreshEnvironment()    // diagnóstico e simuladores

        estado.availableDevices = [(id: Self.udid, name: "iPhone 16"),
                                   (id: "00008140-001A2B3C4D5E6F7A", name: "iPhone 15 (QA)")]
        estado.selectedDevice = conectado ? Self.udid : nil
        estado.deviceSize = CGSize(width: 1179, height: 2556)
        estado.daemonStatus = DaemonStatusMap(wda: conectado ? .ok : .warn, adb: .off, proxy: .off, fa: .off)
        estado.statusMessage = conectado ? "Dispositivo conectado" : ""
        estado.hierarchyElements = conectado ? Self.elementos() : []
        if conectado {
            estado.currentFrame = Self.telaDoAparelho()
            estado.fps = 24
            estado.settleMs = 180
            estado.latencyMs = 42
            estado.cursorPosition = CGPoint(x: 588, y: 2229)
            estado.streamActive = true
        }

        let tema = ThemeManager()
        tema.setMode(t.modo)
        return Cena(estado: estado, sessao: sessao, tema: tema)
    }

    private func comPassos(_ c: Cena) {
        c.estado.steps = Self.passos()
        c.estado.actionsCode = Self.codigoPages
        c.estado.locatorsCode = Self.codigoLocators
    }

    private func comRede(_ c: Cena, selecionada: Int? = 2) {
        let lista = Self.requisicoes()
        c.estado.httpRequests = lista
        c.estado.selectedRequest = selecionada.flatMap { id in lista.first { $0.id == id } }
        c.estado.proxyRunning = true
        c.estado.daemonStatus.proxy = .ok
        c.estado.workspaceTab = .network
    }

    private func comAnalytics(_ c: Cena, selecionado: Int? = 4) {
        let lista = Self.eventos()
        c.estado.analyticsEvents = lista
        c.estado.selectedAnalyticsEvent = selecionado.flatMap { id in lista.first { $0.id == id } }
        c.estado.analyticsListenerActive = true
        c.estado.daemonStatus.fa = .ok
        c.estado.workspaceTab = .analytics
    }

    private func logDeExecucao(ate passo: Int, falha: Bool = false) -> [LogLine] {
        let base = Date(timeIntervalSince1970: 1_791_558_200)
        var linhas = [LogLine(timestamp: base, prefix: "INFO", message: "Sessão Appium aberta · XCUITest · iPhone 16 (iOS 18.6)"),
                      LogLine(timestamp: base.addingTimeInterval(1), prefix: "INFO", message: "Page Object onboarding_credito_objs carregado (5 locators)")]
        for (i, p) in Self.passos().prefix(passo).enumerated() {
            let t = base.addingTimeInterval(Double(2 + i * 2))
            linhas.append(LogLine(timestamp: t, prefix: "RUN", message: "passo \(i + 1) · \(p.actionType) \(p.varName)"))
            if falha && i + 1 == passo {
                linhas.append(LogLine(timestamp: t.addingTimeInterval(15), prefix: "FAIL",
                                      message: "NoSuchElementError: \(p.varName) não ficou visível em 15 s"))
            } else {
                if i == 1 {
                    linhas.append(LogLine(timestamp: t.addingTimeInterval(0.4), prefix: "HTTP", message: "POST /v2/credito/simulacao → 201 (812 ms)"))
                }
                if i == 3 {
                    linhas.append(LogLine(timestamp: t.addingTimeInterval(0.2), prefix: "FA", message: "clique_continuar {tela: simulacao, etapa: 2}"))
                }
                linhas.append(LogLine(timestamp: t.addingTimeInterval(1), prefix: "PASS", message: "passo \(i + 1) ok"))
            }
        }
        return linhas
    }

    // MARK: - Desenho

    /// Fotografa a view nos dois temas. `montar` prepara o estado e devolve a view.
    private func catalogar<V: View>(
        _ nome: String, largura: CGFloat, altura: CGFloat, espera: Double = 0.5,
        fundo: Bool = true,
        montar: (Cena, Tema) async throws -> V,
        cena: ((Tema) async throws -> Cena)? = nil
    ) async throws {
        let destino = try pasta()
        for t in Tema.allCases {
            let c: Cena
            if let cena { c = try await cena(t) } else { c = try await novaCena(t) }
            let view = try await montar(c, t)
            let raiz = view
                .frame(width: largura, height: altura)
                .background(fundo ? c.tema.current.bgWindow : Color.clear)
                .environment(c.estado)
                .environment(c.sessao)
                .environment(c.tema)
                .environment(\.colorScheme, t.esquema)
            try await fotografar(raiz, largura: largura, altura: altura, aparencia: t.aparencia, espera: espera,
                                 url: destino.appendingPathComponent("\(nome)-\(t.rawValue).png"))
        }
    }

    private func fotografar<V: View>(_ view: V, largura: CGFloat, altura: CGFloat, aparencia: NSAppearance?,
                                     espera: Double, url: URL) async throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: largura, height: altura)
        let janela = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        janela.isReleasedWhenClosed = false
        janela.appearance = aparencia
        host.appearance = aparencia
        janela.contentView = host
        host.layoutSubtreeIfNeeded()
        // Deixa rodar `onAppear`, `.task` e a medição de largura das barras.
        // O teste assíncrono no ator principal deixa o run loop girar enquanto
        // espera, então `Task.sleep` basta.
        try await Task.sleep(nanoseconds: UInt64(espera * 1_000_000_000))
        host.layoutSubtreeIfNeeded()
        host.display()

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(largura * 2), pixelsHigh: Int(altura * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: largura, height: altura)
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
        janela.contentView = nil
        janela.close()
    }

    // MARK: - 01 Splash

    func test01Splash() async throws {
        // O SplashView busca `NSImage(named: "mascot")`; no teste o bundle
        // principal é o do xctest, então a imagem do repositório é registrada.
        let mascote = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("assets/mascot.png")
        if NSImage(named: "mascot") == nil, let img = NSImage(contentsOf: mascote) {
            img.setName("mascot")
        }
        // A splash não depende de tema: as cores são fixas. Os dois arquivos
        // saem para manter o par claro/escuro do catálogo.
        try await catalogar("01-splash", largura: 1280, altura: 720, espera: 2.0, fundo: false) { _, _ in
            SplashView(onClose: {})
        }
    }

    // MARK: - 02 Sem dispositivo

    func test02SemDispositivo() async throws {
        try await catalogar("02-sem-dispositivo", largura: 1440, altura: 900, espera: 0.8,
                            montar: { _, _ in ContentView() },
                            cena: { try await self.novaCena($0, conectado: false) })
    }

    func test02bSemDispositivoVerificando() async throws {
        try await catalogar("02b-sem-dispositivo-verificando", largura: 1440, altura: 900, espera: 0.8,
                            montar: { _, _ in ContentView() },
                            cena: { try await self.novaCena($0, conectado: false, semDiagnostico: true) })
    }

    func test02cSemDispositivoIOSPronto() async throws {
        try await catalogar("02c-sem-dispositivo-ios-pronto", largura: 1440, altura: 900, espera: 0.8,
                            montar: { _, _ in ContentView() },
                            cena: { try await self.novaCena($0, conectado: false,
                                                            extras: ["diagnostics.check": Data(Self.diagnosticoPronto.utf8)]) })
    }

    // MARK: - 03 Janela conectada

    func test03JanelaConectadaIOS() async throws {
        try await catalogar("03-janela-ios-conectada", largura: 1440, altura: 900) { _, _ in ContentView() }
    }

    func test03bJanelaLarguraMinima() async throws {
        try await catalogar("03b-janela-ios-largura-minima", largura: 1320, altura: 720) { c, _ in
            self.comPassos(c)
            return ContentView()
        }
    }

    // MARK: - 04 Barra superior

    func test04BarraSuperiorCheia() async throws {
        try await catalogar("04-barra-superior-1440", largura: 1440, altura: 52) { _, _ in UnifiedToolbar() }
    }

    func test04bBarraSuperiorMinima() async throws {
        try await catalogar("04b-barra-superior-1320-minima", largura: 1320, altura: 52) { _, _ in UnifiedToolbar() }
    }

    func test04cBarraSuperiorGravando() async throws {
        try await catalogar("04c-barra-superior-gravando", largura: 1440, altura: 52) { c, _ in
            c.estado.interactionMode = .record
            c.estado.passiveListening = true
            c.estado.screenRecording = true
            return UnifiedToolbar()
        }
    }

    func test04dBarraSuperiorSemDispositivo() async throws {
        try await catalogar("04d-barra-superior-sem-dispositivo", largura: 1440, altura: 52,
                            montar: { _, _ in UnifiedToolbar() },
                            cena: { try await self.novaCena($0, conectado: false) })
    }

    // MARK: - 05 Espelho

    func test05ColunaEspelho() async throws {
        try await catalogar("05-coluna-espelho", largura: 384, altura: 780) { _, _ in MirrorColumn() }
    }

    func test05bEspelhoSemImagem() async throws {
        try await catalogar("05b-coluna-espelho-sem-imagem", largura: 384, altura: 780) { c, _ in
            c.estado.currentFrame = nil
            c.estado.fps = 0
            return MirrorColumn()
        }
    }

    func test05cEspelhoComCorrelacao() async throws {
        try await catalogar("05c-coluna-espelho-correlacao", largura: 384, altura: 900) { c, _ in
            self.comPassos(c)
            self.comRede(c)
            return MirrorColumn()
        }
    }

    // MARK: - 06 Hierarquia

    func test06HierarquiaArvore() async throws {
        try await catalogar("06-hierarquia-arvore", largura: 296, altura: 780) { c, _ in
            c.estado.selectedElement = c.estado.hierarchyElements[10]
            return HierarchyColumn()
        }
    }

    func test06bHierarquiaSelecionado() async throws {
        // Mesmos elementos sem pai: a lista mostra todas as linhas, sem
        // depender de expandir a árvore (que o snapshot não consegue clicar).
        try await catalogar("06b-hierarquia-lista-selecionado", largura: 296, altura: 780) { c, _ in
            c.estado.hierarchyElements = Self.elementos(achatada: true)
            c.estado.selectedElement = c.estado.hierarchyElements[10]
            return HierarchyColumn()
        }
    }

    func test06cHierarquiaVazia() async throws {
        try await catalogar("06c-hierarquia-vazia", largura: 296, altura: 600) { c, _ in
            c.estado.hierarchyElements = []
            return HierarchyColumn()
        }
    }

    func test06dHierarquiaBuscaSemResultado() async throws {
        try await catalogar("06d-hierarquia-busca-sem-resultado", largura: 296, altura: 600) { c, _ in
            c.estado.hierarchySearchText = "campo_rg"
            return HierarchyColumn()
        }
    }

    func test06eAtributos() async throws {
        try await catalogar("06e-painel-atributos", largura: 296, altura: 200) { c, _ in
            c.estado.selectedElement = c.estado.hierarchyElements[10]
            return AttributesPanel()
        }
    }

    // MARK: - 07 Workspace (Page Objects)

    func test07WorkspaceVazio() async throws {
        try await catalogar("07-workspace-vazio", largura: 1056, altura: 780) { _, _ in WorkspaceColumn() }
    }

    func test07bWorkspacePagesELocators() async throws {
        try await catalogar("07b-workspace-pages-e-locators", largura: 1056, altura: 780) { c, _ in
            self.comPassos(c)
            return WorkspaceColumn()
        }
    }

    func test07cWorkspaceSoPages() async throws {
        try await catalogar("07c-workspace-so-pages", largura: 1056, altura: 780) { c, _ in
            self.comPassos(c)
            c.estado.splitEditors = false
            return WorkspaceColumn()
        }
    }

    func test07dWorkspaceEstreito() async throws {
        try await catalogar("07d-workspace-estreito-460", largura: 460, altura: 780) { c, _ in
            self.comPassos(c)
            c.estado.splitEditors = false
            return WorkspaceColumn()
        }
    }

    func test07eJanelaComCodigo() async throws {
        try await catalogar("07e-janela-ios-com-codigo", largura: 1440, altura: 900) { c, _ in
            self.comPassos(c)
            c.estado.interactionMode = .record
            c.estado.selectedElement = c.estado.hierarchyElements[10]
            return ContentView()
        }
    }

    // MARK: - 08 Estratégia de seletor

    func test08Estrategias() async throws {
        for (i, e) in LocatorStrategy.allCases.enumerated() {
            let letra = ["", "b", "c", "d"][i]
            try await catalogar("08\(letra)-estrategia-\(e.rawValue)", largura: 1100, altura: 40) { c, _ in
                self.comPassos(c)
                c.estado.locatorStrategy = e
                return WorkspaceTabBar()
            }
        }
    }

    func test08eEstrategiaMenuEstreito() async throws {
        try await catalogar("08e-estrategia-barra-estreita-460", largura: 460, altura: 72) { c, _ in
            self.comPassos(c)
            c.estado.locatorStrategy = .xpath
            return WorkspaceTabBar()
        }
    }

    // MARK: - 09 Passos e estrutura

    func test09ListaDePassos() async throws {
        try await catalogar("09-lista-de-passos", largura: 334, altura: 300) { c, t in
            self.comPassos(c)
            return StepsList().background(c.tema.current.bgContent)
        }
    }

    func test10EstruturaDoFluxo() async throws {
        try await catalogar("10-estrutura-do-fluxo", largura: 640, altura: 420) { c, _ in
            self.comPassos(c)
            return StructureDialog(onClose: {})
        }
    }

    // MARK: - 11 Execução do fluxo

    private func execucao(_ c: Cena, estado run: RunState) {
        comPassos(c)
        c.estado.showingFlowRunner = true
        c.estado.runState = run
        c.estado.daemonStatus.proxy = .ok
        switch run {
        case .running:
            c.estado.currentRunStep = 3
            c.estado.runLog = logDeExecucao(ate: 3)
        case .passed:
            c.estado.currentRunStep = 6
            c.estado.runLog = logDeExecucao(ate: 6)
        case .failed:
            c.estado.currentRunStep = 5
            c.estado.runLog = logDeExecucao(ate: 5, falha: true)
        case .idle:
            c.estado.currentRunStep = 0
        }
    }

    func test11ExecucaoRodando() async throws {
        try await catalogar("11-execucao-rodando", largura: 1440, altura: 900) { c, _ in
            self.execucao(c, estado: .running); return ContentView()
        }
    }

    func test11bExecucaoSucesso() async throws {
        try await catalogar("11b-execucao-sucesso", largura: 1440, altura: 900) { c, _ in
            self.execucao(c, estado: .passed); return ContentView()
        }
    }

    func test11cExecucaoFalha() async throws {
        try await catalogar("11c-execucao-falha", largura: 1440, altura: 900) { c, _ in
            self.execucao(c, estado: .failed); return ContentView()
        }
    }

    func test11dTerminal() async throws {
        try await catalogar("11d-terminal", largura: 480, altura: 360) { c, _ in
            self.execucao(c, estado: .failed); return TerminalView()
        }
    }

    // MARK: - 12 Rede

    func test12RedeVazia() async throws {
        try await catalogar("12-rede-vazia", largura: 1056, altura: 780) { c, _ in
            c.estado.workspaceTab = .network
            return WorkspaceColumn()
        }
    }

    func test12bRedeTabela() async throws {
        try await catalogar("12b-rede-tabela", largura: 1056, altura: 780) { c, _ in
            self.comRede(c, selecionada: nil)
            c.estado.iosDebugNetActive = true
            return WorkspaceColumn()
        }
    }

    func test12cRedeDetalhe() async throws {
        try await catalogar("12c-rede-detalhe-request-response", largura: 1056, altura: 780) { c, _ in
            self.comRede(c, selecionada: 2); return WorkspaceColumn()
        }
    }

    func test12dRedeTunel() async throws {
        try await catalogar("12d-rede-detalhe-tunel-https", largura: 1056, altura: 780) { c, _ in
            self.comRede(c, selecionada: 4); return WorkspaceColumn()
        }
    }

    func test12eRedeErro() async throws {
        try await catalogar("12e-rede-detalhe-erro-422", largura: 1056, altura: 780) { c, _ in
            self.comRede(c, selecionada: 6); return WorkspaceColumn()
        }
    }

    func test12fJanelaRede() async throws {
        try await catalogar("12f-janela-ios-rede", largura: 1440, altura: 900) { c, _ in
            self.comPassos(c); self.comRede(c, selecionada: 2); return ContentView()
        }
    }

    // MARK: - 13 Analytics

    func test13AnalyticsVazio() async throws {
        try await catalogar("13-analytics-vazio", largura: 1056, altura: 780) { c, _ in
            c.estado.workspaceTab = .analytics
            return WorkspaceColumn()
        }
    }

    func test13bAnalyticsLista() async throws {
        try await catalogar("13b-analytics-lista", largura: 1056, altura: 780) { c, _ in
            self.comAnalytics(c, selecionado: nil); return WorkspaceColumn()
        }
    }

    func test13cAnalyticsDetalhe() async throws {
        try await catalogar("13c-analytics-detalhe", largura: 1056, altura: 780) { c, _ in
            self.comAnalytics(c, selecionado: 4); return WorkspaceColumn()
        }
    }

    func test13dJanelaAnalytics() async throws {
        try await catalogar("13d-janela-ios-analytics", largura: 1440, altura: 900) { c, _ in
            self.comPassos(c); self.comRede(c, selecionada: nil); self.comAnalytics(c, selecionado: 2)
            return ContentView()
        }
    }

    // MARK: - 14 Barra de status

    func test14BarraDeStatus() async throws {
        try await catalogar("14-barra-de-status", largura: 1440, altura: 26) { c, _ in
            c.estado.daemonStatus = DaemonStatusMap(wda: .ok, adb: .off, proxy: .busy, fa: .error)
            c.estado.statusMessage = "Motor 2.1.2 conectado"
            return StatusBar()
        }
    }

    func test14bBarraDeStatusMinima() async throws {
        try await catalogar("14b-barra-de-status-1320", largura: 1320, altura: 26) { c, _ in
            c.estado.daemonStatus = DaemonStatusMap(wda: .warn, adb: .off, proxy: .ok, fa: .ok)
            c.estado.statusMessage = "Asserção de contrato gerada e inserida no código!"
            return StatusBar()
        }
    }

    // MARK: - 15 Painéis recolhidos

    func test15EspelhoRecolhido() async throws {
        try await catalogar("15-painel-espelho-recolhido", largura: 1440, altura: 900) { c, _ in
            self.comPassos(c)
            c.estado.mirrorVisible = false
            return ContentView()
        }
    }

    func test15bWorkspaceRecolhido() async throws {
        try await catalogar("15b-painel-workspace-recolhido", largura: 1440, altura: 900) { c, _ in
            c.estado.workspaceVisible = false
            return ContentView()
        }
    }

    // MARK: - 16 Componentes

    func test16Componentes() async throws {
        try await catalogar("16-componentes", largura: 980, altura: 760) { _, _ in VitrineDeComponentes() }
    }

    // MARK: - Tela falsa do aparelho

    /// Uma tela de app iOS desenhada em SwiftUI e rasterizada a @3x, para o
    /// espelho não aparecer vazio. As caixas batem com `elementos()`.
    static func telaDoAparelho() -> NSImage? {
        let renderer = ImageRenderer(content: TelaOnboardingCredito().frame(width: 393, height: 852))
        renderer.scale = 3
        return renderer.nsImage
    }
}

// MARK: - Views de apoio

private struct TelaOnboardingCredito: View {
    private let marca = Color(red: 0.05, green: 0.45, blue: 0.62)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            // status bar
            HStack {
                Text("9:41").font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "cellularbars"); Image(systemName: "wifi"); Image(systemName: "battery.100")
            }
            .foregroundColor(.black)
            .padding(.horizontal, 32).frame(height: 54)
            // nav
            HStack {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundColor(marca)
                Spacer()
                Text("Crédito pessoal").font(.system(size: 17, weight: .semibold)).foregroundColor(.black)
                Spacer()
                Color.clear.frame(width: 20)
            }
            .padding(.horizontal, 20).frame(height: 52).offset(y: 54)
            // ilustracao
            Circle().fill(marca.opacity(0.12)).frame(width: 170, height: 170).offset(x: 111, y: 136)
            Image(systemName: "creditcard.fill").font(.system(size: 64)).foregroundColor(marca).offset(x: 160, y: 186)
            VStack(alignment: .leading, spacing: 8) {
                Text("Simule seu crédito em minutos").font(.system(size: 28, weight: .bold)).foregroundColor(.black)
                Text("Sem compromisso. A taxa aparece antes de você contratar.")
                    .font(.system(size: 15)).foregroundColor(.gray)
            }
            .frame(width: 345, alignment: .leading).offset(x: 24, y: 330)
            campo("CPF", "000.000.000-00").offset(x: 24, y: 458)
            campo("Valor desejado", "R$ 5.000,00").offset(x: 24, y: 544)
            Text("Continuar").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                .frame(width: 345, height: 54).background(RoundedRectangle(cornerRadius: 14).fill(marca))
                .offset(x: 24, y: 716)
            Text("Agora não").font(.system(size: 15, weight: .medium)).foregroundColor(marca)
                .frame(width: 113, height: 32).offset(x: 140, y: 784)
            Capsule().fill(Color.black).frame(width: 134, height: 5).offset(x: 129, y: 838)
        }
    }

    private func campo(_ rotulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rotulo).font(.system(size: 13, weight: .medium)).foregroundColor(.gray)
            Text(valor).font(.system(size: 17)).foregroundColor(.black.opacity(0.35))
                .padding(.horizontal, 14).frame(width: 345, height: 52, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.35), lineWidth: 1))
        }
    }
}

/// Todos os componentes reutilizáveis, em todos os estilos e estados.
private struct VitrineDeComponentes: View {
    @Environment(ThemeManager.self) private var themeManager
    private var theme: any ThemeTokens { themeManager.current }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            secao("FluidPillButton · estilos") {
                HStack(spacing: 10) {
                    FluidPillButton(text: "Primário", icon: "checkmark", style: .primary) {}
                    FluidPillButton(text: "Secundário", icon: "network", style: .secondary) {}
                    FluidPillButton(text: "Rodar", style: .run) {}
                    FluidPillButton(text: "Limpar tráfego", style: .destructiveText) {}
                    FluidPillButton(text: "Parar de gravar", icon: "stop.circle", style: .recording) {}
                    FluidPillButton(text: "Desabilitado", icon: "hand.tap", style: .disabled) {}
                    FluidPillButton(text: "", icon: "play.fill", style: .disabled) {}
                }
            }
            secao("SegmentedControl · simples, com contagens e desabilitado") {
                HStack(spacing: 16) {
                    SegmentedControl(items: ["iOS", "Android"], selectedIndex: .constant(0))
                    SegmentedControl(items: ["Page Objects", "Rede HTTP", "Analytics"], selectedIndex: .constant(1),
                                     badges: [6, 8, nil])
                    SegmentedControl(items: ["Repassar toque", "Gravar passo"], selectedIndex: .constant(0))
                        .disabled(true).opacity(0.5)
                }
            }
            secao("ActivityBadge · CanvasSwitch · PanelToggles") {
                HStack(spacing: 18) {
                    ActivityBadge(count: 8, style: .network)
                    ActivityBadge(count: 6, style: .analytics)
                    ActivityBadge(count: 12, style: .default)
                    CanvasSwitch(label: "Streaming", isOn: .constant(true))
                    CanvasSwitch(label: "Streaming", isOn: .constant(false))
                    PanelToggles(mirrorVisible: .constant(true), workspaceVisible: .constant(false))
                }
            }
            secao("UnderlineTabBar") {
                UnderlineTabBar(tabs: ["HEADERS", "BODY", "TIMING"], selectedIndex: .constant(1))
                    .frame(width: 420)
            }
            secao("TypeChip · DaemonIndicator") {
                HStack(spacing: 14) {
                    ForEach([ChipType.window, .view, .text, .input, .button], id: \.rawValue) { TypeChip(type: $0) }
                    Divider().frame(height: 16)
                    DaemonIndicator(title: "ok", status: .ok)
                    DaemonIndicator(title: "busy", status: .busy)
                    DaemonIndicator(title: "warn", status: .warn)
                    DaemonIndicator(title: "error", status: .error)
                    DaemonIndicator(title: "off", status: .off)
                }
            }
            secao("IDEActionButton · MirrorRefreshButton · SearchField") {
                HStack(spacing: 12) {
                    IDEActionButton(title: "Copiar", icon: "doc.on.doc", disabled: false) {}
                    IDEActionButton(title: "Limpar", icon: "trash", disabled: true) {}
                    MirrorRefreshButton()
                    SearchField().frame(width: 260)
                }
            }
            secao("CollapsedRail · DiagnosticCard (carregando)") {
                HStack(alignment: .top, spacing: 18) {
                    CollapsedRail(label: "Espelho", shortcut: "⌥1", isExpanded: .constant(false), dotColor: theme.success)
                        .frame(height: 180)
                    DiagnosticCard(platform: .ios, diagnostics: nil, isBusy: true, action: {},
                                   actionTitle: "Abrir simulador", actionEnabled: true)
                        .scaleEffect(0.68, anchor: .topLeading).frame(width: 190, height: 180, alignment: .topLeading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bgWindow)
    }

    @ViewBuilder
    private func secao<C: View>(_ titulo: String, @ViewBuilder _ conteudo: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titulo.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(theme.textLabel)
            conteudo()
        }
    }
}
