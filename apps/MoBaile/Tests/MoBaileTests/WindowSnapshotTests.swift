import XCTest
import SwiftUI
import AppKit
@testable import MoBaile

/// Fotografa a janela inteira, com toolbar, sidebar e inspector, para comparar
/// com o design system (`docs/design/design-system/ui_kits/macos-app`).
///
/// `ImageRenderer` não desenha `NavigationSplitView` nem a toolbar da janela:
/// os dois só existem dentro de uma `NSWindow` de verdade. Aqui a View vai
/// para uma janela com `NSHostingController`, que leva título e toolbar do
/// SwiftUI para a janela, e a captura sai do servidor de janelas.
///
/// Ferramenta de inspeção, não asserção: roda só com MOBAILE_SNAPSHOT_DIR, e a
/// janela aparece na tela por um instante enquanto é fotografada.
@MainActor
final class WindowSnapshotTests: XCTestCase {

    private func destino() throws -> URL {
        guard let dir = ProcessInfo.processInfo.environment["MOBAILE_SNAPSHOT_DIR"] else {
            throw XCTSkip("defina MOBAILE_SNAPSHOT_DIR para gerar os PNGs")
        }
        return URL(fileURLWithPath: dir)
    }

    // MARK: - Dados de exemplo (o catálogo de telas do design system)

    private static func elemento(
        _ classe: String, id: String = "", texto: String = "", pai: Int? = nil, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat
    ) -> UIElement {
        UIElement(
            tag: classe, className: classe, resourceId: id, text: texto, contentDesc: "",
            clickable: true, bounds: CGRect(x: x, y: y, width: w, height: h), area: Int(w * h),
            package: "br.com.bancopraia", platform: .ios, depth: 0, parentIndex: pai
        )
    }

    private static func quadroDoApp() -> NSImage {
        let tamanho = NSSize(width: 393, height: 852)
        return NSImage(size: tamanho, flipped: true) { _ in
            NSColor.white.setFill()
            NSRect(origin: .zero, size: tamanho).fill()
            let azul = NSColor(hex: "#0F6E99")
            let tinta = NSColor(hex: "#17323F")
            func texto(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ cor: NSColor, bold: Bool = false) {
                (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular), .foregroundColor: cor,
                ])
            }
            texto("9:41", 40, 18, 15, tinta, bold: true)
            texto("Crédito pessoal", 140, 70, 16, tinta, bold: true)
            texto("‹", 24, 62, 26, azul)
            NSColor(hex: "#E3EEF3").setFill()
            NSBezierPath(ovalIn: NSRect(x: 136, y: 150, width: 120, height: 120)).fill()
            texto("Simule seu crédito", 32, 350, 26, tinta, bold: true)
            texto("em minutos", 32, 382, 26, tinta, bold: true)
            texto("Sem compromisso. A taxa aparece antes de você contratar.", 32, 430, 12, NSColor(hex: "#5A7C8B"))
            for (rotulo, dica, y) in [("CPF", "000.000.000-00", 480.0), ("Valor desejado", "R$ 5.000,00", 560.0)] {
                texto(rotulo, 32, CGFloat(y), 11, NSColor(hex: "#5A7C8B"))
                let caixa = NSBezierPath(roundedRect: NSRect(x: 32, y: CGFloat(y) + 18, width: 329, height: 44), xRadius: 8, yRadius: 8)
                NSColor(hex: "#CBDCE3").setStroke(); caixa.stroke()
                texto(dica, 44, CGFloat(y) + 30, 14, NSColor(hex: "#9AB0BA"))
            }
            azul.setFill()
            NSBezierPath(roundedRect: NSRect(x: 32, y: 700, width: 329, height: 50), xRadius: 12, yRadius: 12).fill()
            texto("Continuar", 160, 714, 16, .white, bold: true)
            texto("Agora não", 162, 770, 14, azul)
            return true
        }
    }

    private static func passo(_ n: Int, _ acao: String, _ elemento: String, _ varName: String, _ estrategia: LocatorStrategy, texto: String? = nil) -> AutomationStep {
        AutomationStep(
            stepNum: n, actionType: acao, varName: varName, elementName: elemento, className: "XCUIElementTypeButton",
            strategy: estrategia, locatorValue: elemento, coords: estrategia == .coords ? CGPoint(x: 1095, y: 210) : nil,
            inputText: texto, package: "br.com.bancopraia", platform: .ios
        )
    }

    private static func requisicao(_ id: Int, _ metodo: String, _ status: Int?, _ host: String, _ path: String, ms: Int?, body: String = "", tunel: Bool = false) -> NetworkEvent {
        NetworkEvent(
            id: id, timestamp: Date(), timeStr: "13:02:1\(id)", method: metodo, url: "https://\(host)\(path)",
            host: host, path: path, statusCode: status, statusText: "", requestHeaders: [
                "Accept-Language": "pt-BR", "Authorization": "Bearer eyJhbGciOi…", "Content-Type": "application/json",
                "User-Agent": "BancoPraia/5.42.0 (iPhone; iOS 18.6; Scale/3.00)",
            ],
            requestBody: metodo == "POST" ? "{\"valor\": 5000, \"parcelas\": 12}" : "", responseHeaders: ["Content-Type": "application/json"],
            responseBody: body, durationMs: ms, protocol: "HTTP/1.1", isTunnel: tunel
        )
    }

    private func ambiente(conectado: Bool = true, area: WorkspaceTab = .pageObjects) -> (AppState, EngineSession, ThemeManager) {
        let estado = AppState()
        estado.platform = .ios
        estado.availableDevices = [(id: "7303D258", name: "iPhone 16")]
        estado.selectedDevice = conectado ? "7303D258" : nil
        estado.deviceSize = CGSize(width: 393, height: 852)
        estado.workspaceTab = area
        estado.statusMessage = conectado ? "Passo 6 gravado · click TOQUE_FECHAR" : "Motor 3.0.0 conectado"
        estado.fps = 24
        estado.settleMs = 180
        estado.latencyMs = 42
        estado.cursorPosition = CGPoint(x: 196, y: 725)
        estado.daemonStatus = DaemonStatusMap(wda: conectado ? .ok : .off, adb: .busy, proxy: .ok, fa: .ok)
        if conectado {
            estado.currentFrame = Self.quadroDoApp()
            estado.hierarchyElements = [
                Self.elemento("XCUIElementTypeApplication", texto: "Banco Praia", 0, 0, 393, 852),
                Self.elemento("XCUIElementTypeWindow", pai: 0, 0, 0, 393, 852),
                Self.elemento("XCUIElementTypeNavigationBar", id: "Crédito pessoal", pai: 1, 0, 47, 393, 59),
                Self.elemento("XCUIElementTypeButton", id: "Voltar", texto: "Voltar", pai: 2, 8, 57, 44, 40),
                Self.elemento("XCUIElementTypeStaticText", texto: "Crédito pessoal", pai: 2, 140, 67, 113, 20),
                Self.elemento("XCUIElementTypeOther", id: "conteudo", pai: 1, 0, 106, 393, 746),
                Self.elemento("XCUIElementTypeStaticText", texto: "Simule seu crédito em minutos", pai: 5, 32, 345, 300, 70),
                Self.elemento("XCUIElementTypeTextField", id: "campo_cpf", texto: "CPF", pai: 5, 32, 498, 329, 44),
                Self.elemento("XCUIElementTypeTextField", id: "campo_valor", texto: "Valor desejado", pai: 5, 32, 578, 329, 44),
                Self.elemento("XCUIElementTypeButton", id: "Continuar", texto: "Continuar", pai: 5, 32, 700, 329, 50),
                Self.elemento("XCUIElementTypeButton", id: "Agora não", texto: "Agora não", pai: 5, 150, 764, 93, 28),
            ]
            estado.selectedElement = estado.hierarchyElements[9]
            estado.steps = [
                Self.passo(1, "click", "Simular crédito", "BOTAO_SIMULAR_CREDITO", .id),
                Self.passo(2, "send_keys", "campo_cpf", "CAMPO_CPF", .id, texto: "12345678901"),
                Self.passo(3, "send_keys", "campo_valor", "CAMPO_VALOR", .id, texto: "5000"),
                Self.passo(4, "click", "Continuar", "BOTAO_CONTINUAR", .id),
                Self.passo(5, "click", "Confirmar contratação", "BOTAO_CONFIRMAR_CONTRATACAO", .xpath),
                Self.passo(6, "click", "position", "TOQUE_FECHAR", .coords),
            ]
            estado.actionsCode = estado.steps.map { s in
                let ref = "self.locators['onboarding_credito_objs'].\(s.varName)"
                let arg = s.actionType == "send_keys" ? "self, texto" : "self"
                let acao = s.actionType == "send_keys" ? "    self.send_keys(\(ref), texto)" : "    self.click(\(ref), 2)"
                return "def \(s.actionType == "send_keys" ? "preencher" : "click")_\(s.varName.lowercased())(\(arg)):\n    self.wait_to_be_visible(\(ref), 15)\n\(acao)\n"
            }.joined(separator: "\n")
            estado.locatorsCode = "from appium.webdriver.common.appiumby import AppiumBy\n\n" + estado.steps.map {
                $0.strategy == .coords ? "\($0.varName) = (1095, 210)  # coords" : "\($0.varName) = (AppiumBy.ACCESSIBILITY_ID, \"\($0.locatorValue)\")"
            }.joined(separator: "\n")
            estado.proxyRunning = true
            estado.httpRequests = [
                Self.requisicao(1, "DELETE", nil, "api.bancopraia.com.br", "/v2/credito/simulacao/sim_8f2c", ms: nil),
                Self.requisicao(2, "GET", 500, "api.bancopraia.com.br", "/v2/clientes/me/preferencias", ms: 1800),
                Self.requisicao(3, "POST", 422, "api.bancopraia.com.br", "/v2/credito/contratacao", ms: 266,
                                body: "{\"erro\": \"limite_excedido\", \"mensagem\": \"Valor acima do limite pré-aprovado.\"}"),
                Self.requisicao(4, "GET", 304, "cdn.bancopraia.com.br", "/img/onboarding/credito@3x.png", ms: 41),
                Self.requisicao(5, "CONNECT", 200, "app-measurement.com", ":443", ms: 58, tunel: true),
                Self.requisicao(6, "POST", 201, "api.bancopraia.com.br", "/v2/credito/simulacao", ms: 812,
                                body: "{\"cet_anual\": 28.4, \"parcelas\": 12, \"simulacao_id\": \"sim_8f2c\", \"valor_parcela\": 487.32}"),
            ]
            estado.selectedRequest = estado.httpRequests[5]
            estado.analyticsListenerActive = true
            estado.analyticsEvents = [
                AnalyticsEvent(id: 1, timestamp: Date(), timeStr: "13:02:10.880", tag: "iOS (Firebase)", eventName: "session_start", params: [:], rawLog: "Logging event: session_start", platform: .ios),
                AnalyticsEvent(id: 2, timestamp: Date(), timeStr: "13:02:11.102", tag: "iOS (Firebase)", eventName: "screen_view",
                               params: ["firebase_screen": "onboarding_credito", "firebase_previous_screen": "home"], rawLog: "Logging event: screen_view", platform: .ios),
                AnalyticsEvent(id: 3, timestamp: Date(), timeStr: "13:02:14.920", tag: "iOS (Firebase)", eventName: "simulacao_credito_iniciada",
                               params: ["canal": "app_ios", "parcelas": "12", "produto": "pessoal", "valor": "5000"],
                               rawLog: "2026-10-08 13:02:14.920 BancoPraia[4821:91234] 11.3.0 - [FirebaseAnalytics][I-ACS023051] Logging event: origin, name, params: app, simulacao_credito_iniciada, {\n    canal: app_ios, parcelas: 12, produto: pessoal, valor: 5000\n}", platform: .ios),
            ]
            estado.selectedAnalyticsEvent = estado.analyticsEvents[2]
        }
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        let tema = ThemeManager(defaults: UserDefaults(suiteName: "mobaile.snapshots.\(UUID().uuidString)")!)
        return (estado, sessao, tema)
    }

    // MARK: - Captura

    private func fotografar<V: View>(_ view: V, tamanho: CGSize, nome: String, escuro: Bool = false, tema: ThemeManager? = nil) throws {
        let pasta = try destino()
        tema?.setMode(escuro ? .dark : .light)
        let controller = NSHostingController(rootView: view.preferredColorScheme(escuro ? .dark : .light))
        controller.sceneBridgingOptions = [.toolbars, .title]
        // Sem isto a janela cresce até o tamanho ideal do conteúdo e a captura
        // não mostra a largura pedida.
        controller.sizingOptions = [.minSize]
        let janela = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: tamanho),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        janela.appearance = NSAppearance(named: escuro ? .darkAqua : .aqua)
        janela.toolbarStyle = .unified
        janela.contentViewController = controller
        janela.setContentSize(tamanho)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        janela.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        // O SwiftUI ajusta a janela ao tamanho mínimo do conteúdo depois do
        // primeiro layout; reaplicar o tamanho deixa as capturas comparáveis.
        janela.setContentSize(tamanho)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        if ProcessInfo.processInfo.environment["MOBAILE_MEDIR"] != nil {
            print("MEDIDA \(nome): pedido=\(tamanho) janela=\(janela.frame.size) minimo=\(janela.contentMinSize) "
                  + "fitting=\(controller.view.fittingSize) tela=\(janela.screen?.frame.size ?? .zero) escala=\(janela.backingScaleFactor)")
        }

        var imagem: CGImage?
        imagem = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(janela.windowNumber), [.boundsIgnoreFraming, .bestResolution])
        if imagem == nil, let quadro = janela.contentView?.superview {
            let rep = quadro.bitmapImageRepForCachingDisplay(in: quadro.bounds)!
            quadro.cacheDisplay(in: quadro.bounds, to: rep)
            imagem = rep.cgImage
        }
        janela.orderOut(nil)
        let cg = try XCTUnwrap(imagem, "sem imagem da janela")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: pasta.appendingPathComponent("\(nome).png"))
    }

    private func janela(_ estado: AppState, _ sessao: EngineSession, _ tema: ThemeManager) -> some View {
        ContentView().environment(estado).environment(sessao).environment(tema)
    }

    func testJanelaPageObjects() throws {
        let (e, s, t) = ambiente()
        e.selectedStepID = e.steps[3].id
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "01-page-objects-claro", tema: t)
    }

    func testJanelaPageObjectsEscuro() throws {
        let (e, s, t) = ambiente()
        e.splitEditors = true
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "02-page-objects-escuro", escuro: true, tema: t)
    }

    func testJanelaRede() throws {
        let (e, s, t) = ambiente(area: .network)
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "03-rede-claro", tema: t)
    }

    func testJanelaAnalyticsEscuro() throws {
        let (e, s, t) = ambiente(area: .analytics)
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "04-analytics-escuro", escuro: true, tema: t)
    }

    func testJanelaSemDispositivo() throws {
        let (e, s, t) = ambiente(conectado: false)
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "05-sem-dispositivo-claro", tema: t)
    }

    func testJanelaEstreita() throws {
        let (e, s, t) = ambiente()
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 980, height: 640), nome: "06-janela-minima-claro", tema: t)
    }

    func testSheetExecucao() throws {
        let (e, s, t) = ambiente()
        e.runState = .failed
        e.currentRunStep = 5
        let agora = Date()
        e.runLog = [
            LogLine(timestamp: agora, prefix: "INFO", message: "Sessão Appium aberta · XCUITest · iPhone 16 (iOS 18.6)"),
            LogLine(timestamp: agora.addingTimeInterval(1), prefix: "RUN", message: "passo 1 · click BOTAO_SIMULAR_CREDITO"),
            LogLine(timestamp: agora.addingTimeInterval(2), prefix: "PASS", message: "passo 1 ok"),
            LogLine(timestamp: agora.addingTimeInterval(3), prefix: "HTTP", message: "POST /v2/credito/simulacao → 201 (812 ms)"),
            LogLine(timestamp: agora.addingTimeInterval(9), prefix: "FAIL", message: "NoSuchElementError: BOTAO_CONFIRMAR_CONTRATACAO não ficou visível em 15 s"),
        ]
        try fotografar(
            FlowRunnerSheet().environment(e).environment(s).environment(t),
            tamanho: CGSize(width: 860, height: 480), nome: "07-sheet-execucao-claro", tema: t
        )
    }

    func testAjustes() throws {
        let (e, s, t) = ambiente()
        try fotografar(
            SettingsView().environment(e).environment(s).environment(t),
            tamanho: CGSize(width: 520, height: 260), nome: "08-ajustes-claro", tema: t
        )
    }

    func testGaleriaDePaletas() throws {
        let (e, s, t) = ambiente()
        t.setPalette("salvia")
        try fotografar(
            PaletteGallery().environment(e).environment(s).environment(t),
            tamanho: CGSize(width: 680, height: 1400), nome: "09-galeria-paletas"
        )
    }

    func testJanelaPaletaTerracota() throws {
        let (e, s, t) = ambiente(area: .network)
        t.setPalette("wearstler")
        try fotografar(janela(e, s, t).preferredColorScheme(.dark), tamanho: CGSize(width: 1280, height: 800), nome: "10-janela-terracota", escuro: true)
    }

    // MARK: - Relatório

    /// Relatório com o cenário das fixtures do motor, sem aparelho conectado.
    private func ambienteDoRelatorio(comRelatorio: Bool = true) throws -> (AppState, EngineSession, ThemeManager) {
        let (e, s, t) = ambiente(conectado: false, area: .report)
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.audit"])
        let relatorio = try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
        e.reportSpec = relatorio.spec
        e.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/Documents/log_obtido.json"))
        if comRelatorio {
            e.report = relatorio
            e.selectedReportResultID = relatorio.results.first {
                $0.status == .error && $0.flow == "investimentos" && $0.variation == "click:parcelas"
            }?.id
        }
        return (e, s, t)
    }

    func testJanelaRelatorio() throws {
        let (e, s, t) = try ambienteDoRelatorio()
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "12-relatorio-claro", tema: t)
    }

    func testJanelaRelatorioEscuro() throws {
        let (e, s, t) = try ambienteDoRelatorio()
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "13-relatorio-escuro", escuro: true, tema: t)
    }

    func testJanelaRelatorioSpecAberta() throws {
        let (e, s, t) = try ambienteDoRelatorio(comRelatorio: false)
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "14-relatorio-spec-claro", tema: t)
    }

    func testJanelaRelatorioVazio() throws {
        let (e, s, t) = ambiente(conectado: false, area: .report)
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 980, height: 640), nome: "15-relatorio-vazio-claro", tema: t)
    }

    func testJanelaPaletaSalvia() throws {
        let (e, s, t) = ambiente()
        e.selectedStepID = e.steps[1].id
        t.setPalette("salvia")
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "11-janela-salvia")
    }
}

// MARK: - Catálogo de telas (docs/design/telas)

/// Gera o catálogo completo de telas e estados do app, em claro e escuro, e o
/// `catalogo.json` que `tools/catalogo_telas.py` usa para montar o PDF.
///
///     cd apps/MoBaile
///     MOBAILE_SNAPSHOT_DIR="$(cd ../.. && pwd)/docs/design/telas" swift test --filter WindowSnapshotTests/testCatalogoDeTelas
///     python3 ../../tools/catalogo_telas.py ../../docs/design/telas
///
/// As janelas aparecem na tela por um instante: com a tela bloqueada, a
/// captura sai preta.
extension WindowSnapshotTests {

    private struct Cena {
        let id: String
        let titulo: String
        let conferir: String
        var tamanho = CGSize(width: 1280, height: 800)
        /// `false`: a cena impõe a aparência (paleta alternativa) e sai uma vez só.
        var doisTemas = true
        let montar: (_ escuro: Bool) throws -> (AnyView, ThemeManager)
    }

    /// Espera um trabalho assíncrono girando o run loop, sem sair do teste síncrono.
    private func esperar(_ trabalho: @escaping @MainActor () async -> Void) {
        var pronto = false
        Task { @MainActor in
            await trabalho()
            pronto = true
        }
        let limite = Date().addingTimeInterval(5)
        while !pronto && Date() < limite {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func relatorioDasFixtures() throws -> AuditReport {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.audit"])
        return try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
    }

    private func linhasDeExecucao() -> [LogLine] {
        let agora = Date()
        return [
            LogLine(timestamp: agora, prefix: "INFO", message: "Sessão Appium aberta · XCUITest · iPhone 16 (iOS 18.6)"),
            LogLine(timestamp: agora.addingTimeInterval(1), prefix: "RUN", message: "passo 1 · click BOTAO_SIMULAR_CREDITO"),
            LogLine(timestamp: agora.addingTimeInterval(2), prefix: "PASS", message: "passo 1 ok"),
            LogLine(timestamp: agora.addingTimeInterval(3), prefix: "HTTP", message: "POST /v2/credito/simulacao → 201 (812 ms)"),
            LogLine(timestamp: agora.addingTimeInterval(4), prefix: "FA", message: "simulacao_credito_iniciada"),
            LogLine(timestamp: agora.addingTimeInterval(5), prefix: "RUN", message: "passo 2 · send_keys CAMPO_CPF"),
        ]
    }

    private var cenas: [Cena] {
        func janelaPronta(_ ajuste: @escaping (AppState, EngineSession) throws -> Void, area: WorkspaceTab = .pageObjects,
                          conectado: Bool = true) -> (Bool) throws -> (AnyView, ThemeManager) {
            { _ in
                let (e, s, t) = self.ambiente(conectado: conectado, area: area)
                try ajuste(e, s)
                return (AnyView(self.janela(e, s, t)), t)
            }
        }
        func avulsa<V: View>(_ conteudo: @escaping (AppState, EngineSession) throws -> V) -> (Bool) throws -> (AnyView, ThemeManager) {
            { _ in
                let (e, s, t) = self.ambiente()
                let view = try conteudo(e, s)
                return (AnyView(view.environment(e).environment(s).environment(t)), t)
            }
        }
        return [
            Cena(id: "01-splash", titulo: "Splash de abertura",
                 conferir: "Mascote, título, barra de progresso no destaque, texto de boot",
                 tamanho: CGSize(width: 640, height: 380),
                 montar: { _ in
                     (AnyView(SplashView(progress: SplashProgress(message: "Procurando aparelhos e simuladores…",
                                                                  fraction: 0.7))), ThemeManager())
                 }),
            Cena(id: "02-sem-dispositivo-procurando", titulo: "Sem dispositivo, procurando",
                 conferir: "Estado vazio enquanto o motor ainda não respondeu ao diagnóstico",
                 montar: janelaPronta({ _, _ in }, conectado: false)),
            Cena(id: "02b-sem-dispositivo-diagnostico", titulo: "Sem dispositivo, diagnóstico medido",
                 conferir: "Cartões iOS e Android com checagens reais, ações sugeridas, rodapé do último scan",
                 montar: { _ in
                     let (e, _, t) = self.ambiente(conectado: false)
                     let s = EngineSession(state: e, client: FakeEngine(respostas: try self.resultadosDasFixtures()))
                     self.esperar { await s.refreshEnvironment() }
                     return (AnyView(self.janela(e, s, t)), t)
                 }),
            Cena(id: "03-page-objects-inicial", titulo: "Page Objects, aparelho conectado sem passos",
                 conferir: "Espelho, editores vazios, inspector com a hierarquia, toolbar completa",
                 montar: janelaPronta({ e, _ in
                     e.steps = []
                     e.actionsCode = ""
                     e.locatorsCode = ""
                 })),
            Cena(id: "03b-page-objects-passo-selecionado", titulo: "Page Objects com passos, um selecionado",
                 conferir: "Passos na barra lateral, código do passo destacado, subtítulo \"Passo N de M\"",
                 montar: janelaPronta({ e, _ in e.selectedStepID = e.steps[3].id })),
            Cena(id: "03c-page-objects-lado-a-lado", titulo: "Page Objects, editores lado a lado",
                 conferir: "Ações e locators divididos, numeração, realce Python",
                 montar: janelaPronta({ e, _ in e.splitEditors = true })),
            Cena(id: "03d-modo-zen", titulo: "Modo Zen",
                 conferir: "Sem barra lateral e sem inspector: só espelho e workspace",
                 montar: janelaPronta({ e, _ in e.toggleZenMode() })),
            Cena(id: "04-rede-vazia", titulo: "Rede HTTP sem tráfego",
                 conferir: "Barra acessória, estado vazio com a ação de iniciar",
                 montar: janelaPronta({ e, _ in
                     e.httpRequests = []
                     e.selectedRequest = nil
                     e.proxyRunning = false
                 }, area: .network)),
            Cena(id: "04b-rede-detalhe-post", titulo: "Rede HTTP, requisição POST 201",
                 conferir: "Cores de método e status, Request e Response lado a lado, JSON formatado",
                 montar: janelaPronta({ _, _ in }, area: .network)),
            Cena(id: "04c-rede-tunel-https", titulo: "Rede HTTP, túnel CONNECT",
                 conferir: "Estado de túnel HTTPS no lugar do corpo",
                 montar: janelaPronta({ e, _ in e.selectedRequest = e.httpRequests[4] }, area: .network)),
            Cena(id: "04d-rede-erro-422", titulo: "Rede HTTP, erro 422",
                 conferir: "Cor 4xx igual na tabela e no detalhe, corpo do erro",
                 montar: janelaPronta({ e, _ in e.selectedRequest = e.httpRequests[2] }, area: .network)),
            Cena(id: "05-analytics-vazio", titulo: "Analytics sem eventos",
                 conferir: "Origem do tagueamento no iOS, estado vazio com Iniciar Escuta",
                 montar: janelaPronta({ e, _ in
                     e.analyticsEvents = []
                     e.selectedAnalyticsEvent = nil
                     e.analyticsListenerActive = false
                 }, area: .analytics)),
            Cena(id: "05b-analytics-evento", titulo: "Analytics, evento selecionado",
                 conferir: "Tabela, Parâmetros e Log Bruto",
                 montar: janelaPronta({ _, _ in }, area: .analytics)),
            Cena(id: "06-relatorio-vazio", titulo: "Relatório sem spec",
                 conferir: "Funciona sem aparelho; duas ações (importar prints, abrir spec)",
                 montar: janelaPronta({ _, _ in }, area: .report, conectado: false)),
            Cena(id: "06b-relatorio-spec-aberta", titulo: "Relatório, spec aberta",
                 conferir: "Cartão com o resumo da spec e o botão Auditar",
                 montar: janelaPronta({ e, _ in
                     let r = try self.relatorioDasFixtures()
                     e.reportSpec = r.spec
                     e.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/Documents/log_obtido.json"))
                 }, area: .report, conectado: false)),
            Cena(id: "06c-relatorio-divergencia", titulo: "Relatório, variação divergente",
                 conferir: "Conformidade, filtros, tabela, validação parâmetro a parâmetro, bloco, card no inspector",
                 montar: janelaPronta({ e, _ in
                     let r = try self.relatorioDasFixtures()
                     e.reportSpec = r.spec
                     e.report = r
                     e.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/Documents/log_obtido.json"))
                     e.selectedReportResultID = r.results.first { $0.status == .error && $0.variation == "click:parcelas" }?.id
                 }, area: .report, conectado: false)),
            Cena(id: "06d-relatorio-fora-da-spec", titulo: "Relatório, fora da spec e alertas",
                 conferir: "Tabela de eventos sem card e alertas, detalhe explicando o que conferir",
                 montar: janelaPronta({ e, _ in
                     let r = try self.relatorioDasFixtures()
                     e.reportSpec = r.spec
                     e.report = r
                     e.reportFilter = .outOfSpec
                     e.selectedReportExtraID = r.extras.first?.id
                 }, area: .report, conectado: false)),
            Cena(id: "06e-relatorio-revisao-importacao", titulo: "Relatório, revisão da importação (sheet)",
                 conferir: "Dúvidas do OCR por card, Usar Esta Spec como botão padrão",
                 tamanho: CGSize(width: 560, height: 520),
                 montar: avulsa { e, _ in
                     let dados = try XCTUnwrap(try self.resultadosDasFixtures()["report.import"])
                     e.reportImport = try JSONDecoder().decode(EngineDTO.ReportImportPayload.self, from: dados).toModel()
                     return ReportImportSheet()
                 }),
            Cena(id: "07-janela-minima", titulo: "Janela no tamanho mínimo (980×640)",
                 conferir: "Toolbar manda o excedente para o menu », colunas no mínimo, nada cortado",
                 tamanho: CGSize(width: 980, height: 640),
                 montar: janelaPronta({ _, _ in })),
            Cena(id: "08-estrutura-do-fluxo", titulo: "Estrutura do fluxo (sheet)",
                 conferir: "Tabela ordenável dos passos, Copiar resumo, Fechar",
                 tamanho: CGSize(width: 720, height: 440),
                 montar: avulsa { _, _ in StructureSheet() }),
            Cena(id: "08b-execucao-rodando", titulo: "Executar fluxo, em andamento (sheet)",
                 conferir: "Selo, progresso, passo ativo, terminal, Interromper destrutivo e nunca padrão",
                 tamanho: CGSize(width: 860, height: 480),
                 montar: avulsa { e, _ in
                     e.runState = .running
                     e.currentRunStep = 2
                     e.runLog = self.linhasDeExecucao()
                     return FlowRunnerSheet()
                 }),
            Cena(id: "08c-execucao-sucesso", titulo: "Executar fluxo, concluído (sheet)",
                 conferir: "Todos os passos OK, Concluir habilitado",
                 tamanho: CGSize(width: 860, height: 480),
                 montar: avulsa { e, _ in
                     e.runState = .passed
                     e.currentRunStep = 7
                     e.runLog = self.linhasDeExecucao() + [LogLine(timestamp: Date(), prefix: "PASS", message: "6 passos ok")]
                     return FlowRunnerSheet()
                 }),
            Cena(id: "08d-execucao-falha", titulo: "Executar fluxo, falha no passo 5 (sheet)",
                 conferir: "Passo que falhou marcado, linha FAIL no terminal",
                 tamanho: CGSize(width: 860, height: 480),
                 montar: avulsa { e, _ in
                     e.runState = .failed
                     e.currentRunStep = 5
                     e.runLog = self.linhasDeExecucao() + [LogLine(timestamp: Date(), prefix: "FAIL",
                         message: "NoSuchElementError: BOTAO_CONFIRMAR_CONTRATACAO não ficou visível em 15 s")]
                     return FlowRunnerSheet()
                 }),
            Cena(id: "09-correlacao", titulo: "Correlação (popover)",
                 conferir: "Último passo, requisições e eventos na janela do toque, gerar asserção",
                 tamanho: CGSize(width: 380, height: 300),
                 montar: avulsa { _, _ in CorrelationPopover(onClose: {}).padding(14) }),
            Cena(id: "10-ajustes-geral", titulo: "Ajustes › Geral",
                 conferir: "Formulário nativo, aparência, seletor padrão, espelho automático",
                 tamanho: CGSize(width: 520, height: 300),
                 montar: avulsa { _, _ in GeneralSettings().frame(width: 520) }),
            Cena(id: "10b-ajustes-conexoes", titulo: "Ajustes › Conexões",
                 conferir: "Endereços do motor só para leitura",
                 tamanho: CGSize(width: 520, height: 300),
                 montar: avulsa { _, _ in ConnectionSettings().frame(width: 520) }),
            Cena(id: "10c-ajustes-paletas", titulo: "Ajustes › Paletas",
                 conferir: "Galeria das nove paletas com prévia e checagens de contraste",
                 tamanho: CGSize(width: 700, height: 900),
                 montar: avulsa { _, _ in PaletteGallery() }),
            Cena(id: "11-paleta-terracota", titulo: "Janela com a paleta Terracota (escura)",
                 conferir: "Paleta impõe a aparência; barra lateral na cor da paleta",
                 doisTemas: false,
                 montar: { _ in
                     let (e, s, t) = self.ambiente(area: .network)
                     t.setPalette("wearstler")
                     return (AnyView(self.janela(e, s, t).preferredColorScheme(.dark)), t)
                 }),
            Cena(id: "11b-paleta-salvia", titulo: "Janela com a paleta Sálvia & Palha (clara)",
                 conferir: "Mesma estrutura com outra identidade",
                 doisTemas: false,
                 montar: { _ in
                     let (e, s, t) = self.ambiente()
                     e.selectedStepID = e.steps[1].id
                     t.setPalette("salvia")
                     return (AnyView(self.janela(e, s, t)), t)
                 }),
        ]
    }

    func testCatalogoDeTelas() throws {
        let pasta = try destino()
        var manifesto: [[String: Any]] = []
        for cena in cenas {
            var entrada: [String: Any] = ["id": cena.id, "titulo": cena.titulo, "conferir": cena.conferir]
            for escuro in cena.doisTemas ? [false, true] : [false] {
                let (view, tema) = try cena.montar(escuro)
                let nome = cena.doisTemas ? "\(cena.id)-\(escuro ? "escuro" : "claro")" : cena.id
                try fotografar(view, tamanho: cena.tamanho, nome: nome, escuro: escuro,
                               tema: cena.doisTemas ? tema : nil)
                entrada[cena.doisTemas ? (escuro ? "escuro" : "claro") : "unica"] = "\(nome).png"
            }
            manifesto.append(entrada)
        }
        let dados = try JSONSerialization.data(withJSONObject: ["telas": manifesto], options: [.prettyPrinted, .sortedKeys])
        try dados.write(to: pasta.appendingPathComponent("catalogo.json"))
    }
}
