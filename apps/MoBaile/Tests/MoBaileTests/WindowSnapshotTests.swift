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
            package: "com.example.demoapp", platform: .ios, depth: 0, parentIndex: pai
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
            texto("Novo pedido", 140, 70, 16, tinta, bold: true)
            texto("‹", 24, 62, 26, azul)
            NSColor(hex: "#E3EEF3").setFill()
            NSBezierPath(ovalIn: NSRect(x: 136, y: 150, width: 120, height: 120)).fill()
            texto("Simule seu pedido", 32, 350, 26, tinta, bold: true)
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
            inputText: texto, package: "com.example.demoapp", platform: .ios
        )
    }

    private static func requisicao(_ id: Int, _ metodo: String, _ status: Int?, _ host: String, _ path: String, ms: Int?, body: String = "", tunel: Bool = false) -> NetworkEvent {
        NetworkEvent(
            id: id, timestamp: Date(), timeStr: "13:02:1\(id)", method: metodo, url: "https://\(host)\(path)",
            host: host, path: path, statusCode: status, statusText: "", requestHeaders: [
                "Accept-Language": "pt-BR", "Authorization": "Bearer eyJhbGciOi…", "Content-Type": "application/json",
                "User-Agent": "DemoApp/5.42.0 (iPhone; iOS 18.6; Scale/3.00)",
            ],
            requestBody: metodo == "POST" ? "{\"valor\": 5000, \"parcelas\": 12}" : "", responseHeaders: ["Content-Type": "application/json"],
            responseBody: body, durationMs: ms, protocol: "HTTP/1.1", isTunnel: tunel
        )
    }

    private func ambiente(conectado: Bool = true, area: WorkspaceTab = .pageObjects) -> (AppState, EngineSession, ThemeManager) {
        let estado = AppState()
        estado.platform = .ios
        estado.availableDevices = [(id: "SERIAL0001", name: "iPhone 16")]
        estado.selectedDevice = conectado ? "SERIAL0001" : nil
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
                Self.elemento("XCUIElementTypeApplication", texto: "DemoApp", 0, 0, 393, 852),
                Self.elemento("XCUIElementTypeWindow", pai: 0, 0, 0, 393, 852),
                Self.elemento("XCUIElementTypeNavigationBar", id: "Novo pedido", pai: 1, 0, 47, 393, 59),
                Self.elemento("XCUIElementTypeButton", id: "Voltar", texto: "Voltar", pai: 2, 8, 57, 44, 40),
                Self.elemento("XCUIElementTypeStaticText", texto: "Novo pedido", pai: 2, 140, 67, 113, 20),
                Self.elemento("XCUIElementTypeOther", id: "conteudo", pai: 1, 0, 106, 393, 746),
                Self.elemento("XCUIElementTypeStaticText", texto: "Simule seu pedido em minutos", pai: 5, 32, 345, 300, 70),
                Self.elemento("XCUIElementTypeTextField", id: "campo_cpf", texto: "CPF", pai: 5, 32, 498, 329, 44),
                Self.elemento("XCUIElementTypeTextField", id: "campo_valor", texto: "Valor desejado", pai: 5, 32, 578, 329, 44),
                Self.elemento("XCUIElementTypeButton", id: "Continuar", texto: "Continuar", pai: 5, 32, 700, 329, 50),
                Self.elemento("XCUIElementTypeButton", id: "Agora não", texto: "Agora não", pai: 5, 150, 764, 93, 28),
            ]
            estado.selectedElement = estado.hierarchyElements[9]
            estado.steps = [
                Self.passo(1, "click", "Simular pedido", "BOTAO_SIMULAR_PEDIDO", .id),
                Self.passo(2, "send_keys", "campo_cpf", "CAMPO_CPF", .id, texto: "12345678901"),
                Self.passo(3, "send_keys", "campo_valor", "CAMPO_VALOR", .id, texto: "5000"),
                Self.passo(4, "click", "Continuar", "BOTAO_CONTINUAR", .id),
                Self.passo(5, "click", "Confirmar contratação", "BOTAO_CONFIRMAR_CONTRATACAO", .xpath),
                Self.passo(6, "click", "position", "TOQUE_FECHAR", .coords),
            ]
            estado.actionsCode = estado.steps.map { s in
                let ref = "self.locators['cadastro_demo_objs'].\(s.varName)"
                let arg = s.actionType == "send_keys" ? "self, texto" : "self"
                let acao = s.actionType == "send_keys" ? "    self.send_keys(\(ref), texto)" : "    self.click(\(ref), 2)"
                return "def \(s.actionType == "send_keys" ? "preencher" : "click")_\(s.varName.lowercased())(\(arg)):\n    self.wait_to_be_visible(\(ref), 15)\n\(acao)\n"
            }.joined(separator: "\n")
            estado.locatorsCode = "from appium.webdriver.common.appiumby import AppiumBy\n\n" + estado.steps.map {
                $0.strategy == .coords ? "\($0.varName) = (1095, 210)  # coords" : "\($0.varName) = (AppiumBy.ACCESSIBILITY_ID, \"\($0.locatorValue)\")"
            }.joined(separator: "\n")
            estado.proxyRunning = true
            estado.httpRequests = [
                Self.requisicao(1, "DELETE", nil, "api.demoapp.test", "/v2/pedido/simulacao/sim_8f2c", ms: nil),
                Self.requisicao(2, "GET", 500, "api.demoapp.test", "/v2/clientes/me/preferencias", ms: 1800),
                Self.requisicao(3, "POST", 422, "api.demoapp.test", "/v2/pedido/contratacao", ms: 266,
                                body: "{\"erro\": \"limite_excedido\", \"mensagem\": \"Valor acima do limite permitido.\"}"),
                Self.requisicao(4, "GET", 304, "cdn.demoapp.test", "/img/onboarding/pedido@3x.png", ms: 41),
                Self.requisicao(5, "CONNECT", 200, "app-measurement.com", ":443", ms: 58, tunel: true),
                Self.requisicao(6, "POST", 201, "api.demoapp.test", "/v2/pedido/simulacao", ms: 812,
                                body: "{\"cet_anual\": 28.4, \"parcelas\": 12, \"simulacao_id\": \"sim_8f2c\", \"valor_parcela\": 487.32}"),
            ]
            estado.selectedRequest = estado.httpRequests[5]
            estado.analyticsListenerActive = true
            estado.analyticsEvents = [
                AnalyticsEvent(id: 1, timestamp: Date(), timeStr: "13:02:10.880", tag: "iOS (Firebase)", eventName: "session_start", params: [:], rawLog: "Logging event: session_start", platform: .ios),
                AnalyticsEvent(id: 2, timestamp: Date(), timeStr: "13:02:11.102", tag: "iOS (Firebase)", eventName: "screen_view",
                               params: ["firebase_screen": "cadastro_demo", "firebase_previous_screen": "home"], rawLog: "Logging event: screen_view", platform: .ios),
                AnalyticsEvent(id: 3, timestamp: Date(), timeStr: "13:02:14.920", tag: "iOS (Firebase)", eventName: "simulacao_pedido_iniciada",
                               params: ["canal": "app_ios", "parcelas": "12", "produto": "avulso", "valor": "5000"],
                               rawLog: "2026-10-08 13:02:14.920 DemoApp[4821:91234] 11.3.0 - [FirebaseAnalytics][I-ACS023051] Logging event: origin, name, params: app, simulacao_pedido_iniciada, {\n    canal: app_ios, parcelas: 12, produto: avulso, valor: 5000\n}", platform: .ios),
            ]
            estado.selectedAnalyticsEvent = estado.analyticsEvents[2]
        }
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        let tema = ThemeManager(defaults: UserDefaults(suiteName: "mobaile.snapshots.\(UUID().uuidString)")!)
        return (estado, sessao, tema)
    }

    // MARK: - Captura

    /// `partindoDe`: abre a janela nesse tamanho e só depois encolhe, como quem
    /// arrasta a borda; sem ele a janela já nasce no tamanho pedido.
    ///
    /// Devolve se o app estava ativo na captura. Inativo, o macOS tira o tom de
    /// tudo (vidro tingido do Rodar, botões em destaque), e o macOS só ativa o
    /// processo de teste se o app da frente ceder o foco.
    ///
    /// `preparar`: roda com a janela já na tela, antes da foto, para chegar a
    /// estado local das Views (aba escolhida, card em edição) que o AppState
    /// não alcança.
    @discardableResult
    private func fotografar<V: View>(_ view: V, tamanho: CGSize, nome: String, escuro: Bool = false, tema: ThemeManager? = nil,
                                     partindoDe inicial: CGSize? = nil,
                                     preparar: ((NSWindow) -> Void)? = nil) throws -> Bool {
        let pasta = try destino()
        tema?.setMode(escuro ? .dark : .light)
        let controller = NSHostingController(rootView: view.preferredColorScheme(escuro ? .dark : .light))
        controller.sceneBridgingOptions = [.toolbars, .title]
        // Sem isto a janela cresce até o tamanho ideal do conteúdo e a captura
        // não mostra a largura pedida.
        controller.sizingOptions = [.minSize]
        let janela = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: inicial ?? tamanho),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        janela.appearance = NSAppearance(named: escuro ? .darkAqua : .aqua)
        janela.toolbarStyle = .unified
        janela.contentViewController = controller
        janela.setContentSize(inicial ?? tamanho)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        janela.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        // O SwiftUI ajusta a janela ao tamanho mínimo do conteúdo depois do
        // primeiro layout; reaplicar o tamanho deixa as capturas comparáveis.
        // Abaixo do mínimo, a janela para no mínimo, como no arraste da borda.
        janela.setContentSize(inicial == nil ? tamanho : CGSize(width: max(tamanho.width, janela.contentMinSize.width),
                                                                height: max(tamanho.height, janela.contentMinSize.height)))
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        if let preparar {
            preparar(janela)
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        }
        let ativo = NSApp.isActive
        if !ativo { print("AVISO \(nome): app inativo na captura, sem o tom do destaque") }
        if ProcessInfo.processInfo.environment["MOBAILE_MEDIR"] != nil {
            print("MEDIDA \(nome): pedido=\(tamanho) janela=\(janela.frame.size) minimo=\(janela.contentMinSize) "
                  + "fitting=\(controller.view.fittingSize) tela=\(janela.screen?.frame.size ?? .zero) escala=\(janela.backingScaleFactor)")
        }

        // Só o servidor de janelas compõe o Liquid Glass. O `cacheDisplay`, que
        // era o plano B, desenha a janela sem o vidro e sem avisar: a foto
        // sairia errada. Sem a captura do servidor, o teste falha.
        let imagem = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(janela.windowNumber),
                                             [.boundsIgnoreFraming, .bestResolution])
        janela.orderOut(nil)
        let cg = try XCTUnwrap(imagem, "sem captura do servidor de janelas (tela bloqueada ou sem permissão de Gravação de Tela)")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
        try png.write(to: pasta.appendingPathComponent("\(nome).png"))
        return ativo
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

    /// PO-5: faixa de tool windows, painel Projeto com a árvore das fixtures
    /// do motor e o editor no esquema PyCharm. Espelho e inspector fechados
    /// para a árvore caber, como quem trabalha só no código.
    func testJanelaPageObjectsProjetoEscuro() throws {
        _ = try destino()
        let (e, _, t) = ambiente()
        e.mirrorVisible = false
        e.inspectorVisible = false
        let s = EngineSession(state: e, client: FakeEngine(respostas: try resultadosDasFixtures()))
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "16-page-objects-projeto-escuro",
                       escuro: true, tema: t)
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
            LogLine(timestamp: agora.addingTimeInterval(1), prefix: "RUN", message: "passo 1 · click BOTAO_SIMULAR_PEDIDO"),
            LogLine(timestamp: agora.addingTimeInterval(2), prefix: "PASS", message: "passo 1 ok"),
            LogLine(timestamp: agora.addingTimeInterval(3), prefix: "HTTP", message: "POST /v2/pedido/simulacao → 201 (812 ms)"),
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
                $0.status == .error && $0.flow == "empresa" && $0.variation == "click:parcelas"
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

    // MARK: - Fluidez 3.5 (docs/design/telas/3.5)

    func testPaletaDeComandos() throws {
        let (e, s, t) = ambiente()
        e.commandPalettePresented = true
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "3.5-paleta-de-comandos-claro", tema: t)
        let (e2, s2, t2) = ambiente(conectado: false)
        e2.commandPalettePresented = true
        try fotografar(janela(e2, s2, t2), tamanho: CGSize(width: 1280, height: 800), nome: "3.5-paleta-sem-aparelho-escuro", escuro: true, tema: t2)
    }

    func testFaixaMotorParado() async throws {
        let (e, _, t) = ambiente(conectado: false)
        let parado = EngineSession(state: e) {
            try EngineLocator.selectPython(
                from: ["/usr/bin/python3"], isExecutable: { _ in true },
                probe: { _ in PythonProbe.Result(kind: .tooOld, version: "3.9.6") }
            )
            throw EngineError.notRunning
        }
        await parado.connect()
        try fotografar(janela(e, parado, t), tamanho: CGSize(width: 1280, height: 800), nome: "3.5-motor-parado-claro", tema: t)
        try fotografar(janela(e, parado, t), tamanho: CGSize(width: 1280, height: 800), nome: "3.5-motor-parado-escuro", escuro: true, tema: t)
    }

    func testSemAparelhoComProximoPasso() async throws {
        _ = try destino()
        let (e, _, t) = ambiente(conectado: false)
        // Diagnóstico das fixtures do motor: WDA sem resposta no iOS e AVDs
        // parados no Android. Só o iOS, plataforma em uso, ganha o destaque.
        let s = EngineSession(state: e, client: FakeEngine(respostas: try resultadosDasFixtures()))
        await s.refreshEnvironment()
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "3.5-sem-aparelho-claro", tema: t)
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "3.5-sem-aparelho-escuro", escuro: true, tema: t)
    }

    func testJanelaPaletaSalvia() throws {
        let (e, s, t) = ambiente()
        e.selectedStepID = e.steps[1].id
        t.setPalette("salvia")
        try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "11-janela-salvia")
    }

    // MARK: - Telas pequenas

    /// Todas as áreas no tamanho mínimo e num notebook de 13" (1280×720 úteis),
    /// com o inspector aberto. Com MOBAILE_MEDIR, imprime o mínimo da janela.
    func testTelasPequenas() throws {
        let tamanhos = [CGSize(width: 980, height: 600), CGSize(width: 1280, height: 720)]
        let areas: [(String, () throws -> (AppState, EngineSession, ThemeManager))] = [
            ("page-objects", { self.ambiente() }),
            ("rede", { self.ambiente(area: .network) }),
            ("analytics", { self.ambiente(area: .analytics) }),
            ("sem-dispositivo", { self.ambiente(conectado: false) }),
            ("relatorio-vazio", { self.ambiente(conectado: false, area: .report) }),
            ("relatorio-spec", { try self.ambienteDoRelatorio(comRelatorio: false) }),
            ("relatorio", { try self.ambienteDoRelatorio() }),
            ("relatorio-fora-da-spec", {
                let (e, s, t) = try self.ambienteDoRelatorio()
                e.reportFilter = .outOfSpec
                e.selectedReportExtraID = e.report?.extras.first?.id
                return (e, s, t)
            }),
            ("execucao-vazia", { self.ambiente(conectado: false, area: .execution) }),
            ("execucao", {
                let (e, s, t) = self.ambiente(conectado: false, area: .execution)
                try self.preencherExecucao(e)
                return (e, s, t)
            }),
        ]
        for tamanho in tamanhos {
            for (nome, montar) in areas {
                let (e, s, t) = try montar()
                try fotografar(janela(e, s, t), tamanho: tamanho,
                               nome: "pequena-\(Int(tamanho.width))x\(Int(tamanho.height))-\(nome)", tema: t,
                               partindoDe: CGSize(width: 1440, height: 900))
            }
        }
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
        /// Aparência da janela na cena única: a da paleta, senão a toolbar sai
        /// clara sobre uma paleta escura.
        var escura = false
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

    private func specDasFixtures() throws -> ReportSpecDraft {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.cards"])
        return try JSONDecoder().decode(EngineDTO.ReportCardsPayload.self, from: dados).toModel()
    }

    private func linhasDeExecucao() -> [LogLine] {
        let agora = Date()
        return [
            LogLine(timestamp: agora, prefix: "INFO", message: "Sessão Appium aberta · XCUITest · iPhone 16 (iOS 18.6)"),
            LogLine(timestamp: agora.addingTimeInterval(1), prefix: "RUN", message: "passo 1 · click BOTAO_SIMULAR_PEDIDO"),
            LogLine(timestamp: agora.addingTimeInterval(2), prefix: "PASS", message: "passo 1 ok"),
            LogLine(timestamp: agora.addingTimeInterval(3), prefix: "HTTP", message: "POST /v2/pedido/simulacao → 201 (812 ms)"),
            LogLine(timestamp: agora.addingTimeInterval(4), prefix: "FA", message: "simulacao_pedido_iniciada"),
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
                 conferir: "Mascote, título, trilho de vidro transparente com a barra no destaque, texto de boot",
                 tamanho: CGSize(width: 640, height: 380),
                 montar: { _ in
                     (AnyView(SplashView(progress: SplashProgress(message: "Procurando aparelhos e simuladores…",
                                                                  fraction: 0.7))), ThemeManager())
                 }),
            Cena(id: "02-sem-dispositivo-procurando", titulo: "Sem dispositivo, procurando",
                 conferir: "Estado vazio enquanto o motor ainda não respondeu ao diagnóstico",
                 montar: janelaPronta({ _, _ in }, conectado: false)),
            Cena(id: "02b-sem-dispositivo-diagnostico", titulo: "Sem dispositivo, diagnóstico medido",
                 conferir: "Cartões iOS e Android com checagens reais, um só próximo passo em destaque, rodapé da última verificação",
                 montar: { _ in
                     let (e, _, t) = self.ambiente(conectado: false)
                     let s = EngineSession(state: e, client: FakeEngine(respostas: try self.resultadosDasFixtures()))
                     self.esperar { await s.refreshEnvironment() }
                     return (AnyView(self.janela(e, s, t)), t)
                 }),
            Cena(id: "02c-inicio-falta-instalar", titulo: "Início no dia a dia, sem aparelho",
                 conferir: "Saudação, cápsula do ambiente com a pendência, alvos com Iniciar e o aviso Só espelho com Resolver, "
                    + "atalho do Relatório, áreas com ⌘1–⌘4, recentes e novidades; Ambiente com contagem no rodapé da barra lateral",
                 tamanho: CGSize(width: 1280, height: 1100),
                 montar: { _ in
                     let (e, _, t) = self.ambiente(conectado: false, area: .home)
                     let s = EngineSession(state: e, client: FakeEngine(respostas: try self.resultadosDasFixtures()))
                     self.esperar { await s.refreshEnvironment() }
                     return (AnyView(self.janela(e, s, t)), t)
                 }),
            Cena(id: "02d-inicio-sem-python", titulo: "Início, Mac sem Python que sirva",
                 conferir: "O motor não sobe: o Início ainda diz o que falta e oferece instalar e reiniciar",
                 montar: { _ in
                     let (e, _, t) = self.ambiente(conectado: false, area: .home)
                     let mensagem = EngineLocator.unsuitableMessage(found: ["/usr/bin/python3 (Python 3.9.6, antigo demais)"])
                     let s = EngineSession(state: e, restartPolicy: .init(delays: [0], maxAttempts: 0)) {
                         throw EngineError.pythonUnsuitable(mensagem)
                     }
                     self.esperar { await s.connect() }
                     return (AnyView(self.janela(e, s, t)), t)
                 }),
            Cena(id: "02e-inicio-aparelho-conectado", titulo: "Início no dia a dia, aparelho conectado",
                 conferir: "Miniatura do último quadro, chip da plataforma, ações em cápsula, status vivos à direita",
                 tamanho: CGSize(width: 1280, height: 1000),
                 montar: { _ in
                     let (e, _, t) = self.ambiente(conectado: true, area: .home)
                     let s = EngineSession(state: e, client: FakeEngine(respostas: try self.resultadosDasFixtures()))
                     self.esperar { await s.refreshEnvironment() }
                     return (AnyView(self.janela(e, s, t)), t)
                 }),
            Cena(id: "02f-inicio-primeira-vez", titulo: "Início, primeira vez nesta máquina",
                 conferir: "Três passos: motor pronto, Android e iOS com o que foi achado e o sugerido em destaque, conectar desabilitado",
                 tamanho: CGSize(width: 1280, height: 1000),
                 montar: { _ in
                     let (e, _, t) = self.ambiente(conectado: false, area: .home)
                     var respostas = try self.resultadosDasFixtures()
                     var resumo = try XCTUnwrap(
                         JSONSerialization.jsonObject(with: try XCTUnwrap(respostas["home.summary"])) as? [String: Any]
                     )
                     resumo["state"] = "first_run"
                     respostas["home.summary"] = try JSONSerialization.data(withJSONObject: resumo)
                     let s = EngineSession(state: e, client: FakeEngine(respostas: respostas))
                     self.esperar { await s.refreshEnvironment() }
                     return (AnyView(self.janela(e, s, t)), t)
                 }),
            Cena(id: "02g-ambiente", titulo: "Ambiente",
                 conferir: "Resumo por grupo, pendência com comando e Instalar no Terminal, tabela Área × iOS × Android, "
                    + "componentes por grupo com o pendente antes",
                 tamanho: CGSize(width: 1280, height: 1400),
                 montar: { _ in
                     let (e, _, t) = self.ambiente(conectado: false, area: .environment)
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
            Cena(id: "06f-relatorio-editar-card", titulo: "Relatório, editar card (inspector)",
                 conferir: "Seção, título, evento, parâmetros, variações, observação; Salvar em destaque",
                 tamanho: CGSize(width: 320, height: 640),
                 montar: avulsa { _, _ in
                     let dados = try XCTUnwrap(try self.resultadosDasFixtures()["report.card"])
                     let card = try JSONDecoder().decode(EngineDTO.ReportCardPayload.self, from: dados).toModel()
                     return ReportCardEditor(draft: .constant(card), onCancel: {}, onSave: {})
                 }),
            Cena(id: "06g-relatorio-dados-da-exportacao", titulo: "Relatório, dados da exportação (sheet)",
                 conferir: "Quatro campos opcionais, Limpar, Cancelar, Pular e Exportar",
                 tamanho: CGSize(width: 440, height: 300),
                 montar: avulsa { _, _ in ReportExportSheet(request: ReportExportRequest(directory: nil)) }),
            Cena(id: "06h-relatorio-editor-spec-quadro", titulo: "Relatório, editor de spec em quadro",
                 conferir: "Um quadro por card agrupado por seção, compartimentos, Quadro | Tabela, Fechar e Salvar",
                 montar: janelaPronta({ e, _ in
                     let r = try self.relatorioDasFixtures()
                     e.reportSpec = r.spec
                     e.reportSpecEditor = try self.specDasFixtures()
                 }, area: .report, conectado: false)),
            Cena(id: "06i-relatorio-editor-spec-tabela", titulo: "Relatório, editor de spec em tabela",
                 conferir: "Uma linha por parâmetro, nome e valor editáveis na célula",
                 montar: janelaPronta({ e, _ in
                     let r = try self.relatorioDasFixtures()
                     e.reportSpec = r.spec
                     e.reportSpecEditor = try self.specDasFixtures()
                     e.reportSpecEditorMode = .table
                 }, area: .report, conectado: false)),
            Cena(id: "06j-relatorio-editor-spec-problemas", titulo: "Relatório, editor de spec com card alterado e inválido",
                 conferir: "Selo Alterado, borda e lista de problemas no card, Salvar desabilitado, contagem no cabeçalho",
                 montar: janelaPronta({ e, _ in
                     let r = try self.relatorioDasFixtures()
                     var spec = try self.specDasFixtures()
                     spec.cards[0].titulo = "Home revisada"
                     spec.cards[1].evento = ""
                     spec.cards[1].params.append(.init(key: spec.cards[1].params[0].key, value: "duplicado"))
                     e.reportSpec = r.spec
                     e.reportSpecEditor = spec
                 }, area: .report, conectado: false)),
            Cena(id: "06k-execucao-vazia", titulo: "Execução sem projeto",
                 conferir: "Estado vazio com Abrir Projeto…, funciona sem aparelho",
                 montar: janelaPronta({ _, _ in }, area: .execution, conectado: false)),
            Cena(id: "06l-execucao-sem-interpretador", titulo: "Execução, projeto sem interpretador",
                 conferir: "Cabeçalho do projeto, banner Falhou com contagens e Abrir Pasta/Abrir Vídeo, Rodar bloqueado "
                    + "com explicação, candidatos com versão e behave, configs com selos, suítes, doctor, console",
                 montar: janelaPronta({ e, _ in try self.preencherExecucao(e) }, area: .execution, conectado: false)),
            Cena(id: "06m-execucao-rodando", titulo: "Execução rodando",
                 conferir: "Parar no lugar do Rodar, tempo decorrido, console ao vivo, \"rodando\" na barra lateral",
                 montar: janelaPronta({ e, _ in try self.preencherExecucao(e, semInterpretador: false, resultado: false,
                                                                          rodando: true) },
                                      area: .execution, conectado: true)),
            Cena(id: "06n-execucao-confiar", titulo: "Execução, Confiar neste projeto? (sheet)",
                 conferir: "Interpretador, arquivo de entrada e pasta de trabalho; Confiar e Rodar como padrão",
                 tamanho: CGSize(width: 480, height: 300),
                 montar: avulsa { e, _ in
                     try self.preencherExecucao(e, semInterpretador: false)
                     let leitura = try XCTUnwrap(e.execution.inspection)
                     return ExecutionConfirmationSheet(confirmation: .trust(ExecutionTrustRequest(leitura, then: .run)))
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
                 escura: true,
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
            Cena(id: "11c-paleta-costes", titulo: "Janela com a paleta Costes (escura), Rodar disponível",
                 conferir: "Rodar em vidro tingido de dourado com rótulo escuro (onAccent), legível (com o app ativo)",
                 doisTemas: false,
                 escura: true,
                 montar: { _ in
                     let (e, s, t) = self.ambiente()
                     t.setPalette("garcia")
                     return (AnyView(self.janela(e, s, t).preferredColorScheme(.dark)), t)
                 }),
            Cena(id: "11d-vidro-nas-paletas", titulo: "Vidro nas 12 aparências (macOS 26)",
                 conferir: "Rodar tingido com o destaque e rótulo legível (com o app ativo; inativo, neutro), cápsula visível, painel de vidro, em toda paleta",
                 tamanho: CGSize(width: 800, height: 520), doisTemas: false,
                 montar: { _ in (AnyView(AmostraDeVidro.todas()), ThemeManager(preview: PraiaLightTheme())) }),
            Cena(id: "11e-vidro-recuo-macos14", titulo: "Recuo do vidro no macOS 14 e 15 (MOBAILE_SEM_VIDRO)",
                 conferir: "Mesmas amostras com o caminho antigo: botão preenchido, cápsula de preenchimento, material com borda e sombra",
                 tamanho: CGSize(width: 800, height: 520), doisTemas: false,
                 montar: { _ in
                     setenv("MOBAILE_SEM_VIDRO", "1", 1)
                     return (AnyView(AmostraDeVidro.todas(forcarTom: true)), ThemeManager(preview: PraiaLightTheme()))
                 }),
            Cena(id: "12-paleta-de-comandos", titulo: "Paleta de comandos (Liquid Glass)",
                 conferir: "Painel de vidro do sistema sobre a janela, sem borda nem sombra próprias; lista legível",
                 montar: { _ in
                     let (e, s, t) = self.ambiente()
                     e.commandPalettePresented = true
                     return (AnyView(self.janela(e, s, t)), t)
                 }),
            Cena(id: "13-reduzir-transparencia", titulo: "Início e paleta com Reduzir transparência",
                 conferir: "Cápsula do Ambiente e paleta em superfície opaca do tema, com borda; nada translúcido do app",
                 tamanho: CGSize(width: 1280, height: 1000),
                 montar: { _ in
                     let (e, _, t) = self.ambiente(conectado: true, area: .home)
                     let s = EngineSession(state: e, client: FakeEngine(respostas: try self.resultadosDasFixtures()))
                     self.esperar { await s.refreshEnvironment() }
                     e.commandPalettePresented = true
                     return (AnyView(self.janela(e, s, t).environment(\._accessibilityReduceTransparency, true)), t)
                 }),
        ]
    }

    func testCatalogoDeTelas() throws {
        let pasta = try destino()
        // O catálogo é público: sem o nome de quem captura na saudação e sem a
        // pasta real do repositório no comando de instalação.
        HomeCopy.userFullName = { "" }
        SetupInstaller.displayedScriptOverride = URL(fileURLWithPath: "/Users/voce/mo-baile/tools/setup/instalar-mac.sh")
        defer {
            HomeCopy.userFullName = { NSFullUserName() }
            SetupInstaller.displayedScriptOverride = nil
        }
        var manifesto: [[String: Any]] = []
        var inativas: [String] = []
        // MOBAILE_CENA=11c refaz só as cenas com esse prefixo, sem tocar no
        // catalogo.json.
        let filtro = ProcessInfo.processInfo.environment["MOBAILE_CENA"]
        for cena in cenas where filtro.map({ cena.id.hasPrefix($0) }) ?? true {
            var entrada: [String: Any] = ["id": cena.id, "titulo": cena.titulo, "conferir": cena.conferir]
            for escuro in cena.doisTemas ? [false, true] : [cena.escura] {
                let (view, tema) = try cena.montar(escuro)
                let nome = cena.doisTemas ? "\(cena.id)-\(escuro ? "escuro" : "claro")" : cena.id
                defer { unsetenv("MOBAILE_SEM_VIDRO") }
                let ativo = try fotografar(view, tamanho: cena.tamanho, nome: nome, escuro: escuro,
                                           tema: cena.doisTemas ? tema : nil)
                if !ativo { inativas.append("\(nome).png") }
                entrada[cena.doisTemas ? (escuro ? "escuro" : "claro") : "unica"] = "\(nome).png"
            }
            manifesto.append(entrada)
        }
        guard filtro == nil else { return }
        let dados = try JSONSerialization.data(withJSONObject: ["telas": manifesto, "capturadasComAppInativo": inativas], options: [.prettyPrinted, .sortedKeys])
        try dados.write(to: pasta.appendingPathComponent("catalogo.json"))
    }
}

// MARK: - Textos grandes no Relatório (docs/design/telas/textos-grandes)

/// A aba Relatório com textos grandes: muitos itens, valores longos sem espaço,
/// URL, títulos e observações compridas. Serve para avaliar a tela antes e
/// depois de mexer nela, gravando direto na pasta de MOBAILE_SNAPSHOT_DIR:
///
///     cd apps/MoBaile
///     MOBAILE_SNAPSHOT_DIR="$(cd ../.. && pwd)/docs/design/telas/textos-grandes/antes" \
///         swift test --filter 'WindowSnapshotTests/testTextosGrandes'
///
/// Cada cena sai em claro e escuro, em 1280×800 e numa janela pequena
/// (1024×680, encolhida a partir de 1440×900 como quem arrasta a borda; abaixo
/// do mínimo do conteúdo, a janela para no mínimo). Os dados passam pelos DTOs
/// do motor, como no app.
extension WindowSnapshotTests {

    private enum TextoLongo {
        static let projeto = "Pedido Empresa — contratação com seguro prestamista, parcelamento estendido e confirmação final (Android)"
        static let pasta = "/Users/qa/Documents/Mo baile/Demanda 4821 - Pedido Empresa com Seguro Prestamista"
        static let specPath = pasta + "/spec_pedido_empresa_seguro_prestamista_parcelamento_v3_revisada_final.json"
        static let logPath = pasta + "/log_obtido_moto_g55_android15_2026-11-19_14h32_sessao_completa_com_seguro.json"
        static let printsDir = pasta + "/prints"
        static let secaoSimulacao = "Simulação de parcelamento com seguro prestamista e carência"
        static let secaoCheckout = "Checkout e confirmação do pedido"
        /// ~150 caracteres.
        static let titulo = "Simulação de parcelamento do pedido empresa com seguro prestamista opcional, carência de 90 dias "
            + "e confirmação do valor final das parcelas antes do envio"
        static let evento = "interaction_pedido_empresa_simulacao_parcelamento_seguro_prestamista"
        static let fluxoLongo = (key: "empresa_seguro",
                                 label: "PDES · pedido-empresa-com-seguro-prestamista-e-parcelamento-estendido-em-ate-48-vezes-sem-juros-carencia-90-dias")
        /// ~120 caracteres sem espaço.
        static let screenName = "app:pedido:empresa:simulacao:parcelamento:seguro-prestamista:carencia-90-dias:"
            + "confirmacao-do-valor-final-das-parcelas:revisao"
        static let flowName = "pedido-empresa-com-seguro-prestamista-e-parcelamento-estendido-em-ate-48-vezes-sem-juros-"
            + "carencia-90-dias-canal-app-android"
        static let detail = "click:confirmar-simulacao-de-parcelamento-com-seguro-prestamista-opcional-e-carencia-de-noventa-"
            + "dias-antes-do-envio-final"
        static let detailObtido = "click:confirmar-simulacao-de-parcelamento-com-seguro-prestamista-opcional-e-carencia-de-noventa-"
            + "dias-antes-do-envio"
        static let detailParcelas = "click:[numero]-parcelas-com-seguro-prestamista-e-carencia-de-noventa-dias-selecionadas-no-"
            + "seletor-de-quantidade-de-parcelas"
        static let gaScreen = screenName + "-v2"
        static let url = "https://www.exemplo-loja.com.br/checkout/pedido-empresa/simulacao/parcelamento?utm_source=app_android"
            + "&utm_medium=push_notification&utm_campaign=black_friday_2026_parcelamento_sem_juros&utm_content=banner_topo_home"
            + "&gclid=EAIaIQobChMI8sKj5r2_-wIVUBOtBh3x9w0LEAAYASAAEgJ4fPD_BwE"
        static let urlRegra = #"re:^https://www\.exemplo-loja\.com\.br/checkout/pedido-empresa/simulacao/parcelamento\?utm_source=app_android&.+$"#
        /// ~250 caracteres.
        static let itemName = "Camiseta Básica Masculina Manga Curta 100% Algodão Orgânico Pré-Encolhido, Gola Careca Reforçada, "
            + "Modelagem Regular Fit, Cor Azul Marinho Mesclado, Tamanho GG, Coleção Primavera-Verão 2026, Edição Limitada "
            + "Comemorativa de 25 Anos da Marca — Kit com 3 Unidades"
        static let itemNameObtido = itemName.replacingOccurrences(of: "Tamanho GG", with: "Tamanho G")
        /// O GA4 corta `item_name` em 100 caracteres.
        static let itemNameCortado = String(itemName.prefix(100))
        static let obs = "Conferido com produto em 12/11: o detail muda quando o cliente marca o seguro prestamista depois de "
            + "escolher as parcelas; nesse caso o app envia o detail antigo e só atualiza no próximo toque. O time de mobile "
            + "abriu a história MOB-4821 para corrigir; até lá, considerar as duas variações válidas no relatório de homologação."
        static let detailForaDaSpec = "click:banner-black-friday-2026-parcelamento-em-ate-48-vezes-sem-juros-com-seguro-prestamista-"
            + "gratis-nos-tres-primeiros-meses"
        static let excecao = "java.lang.IllegalStateException:Fragment_SimulacaoParcelamentoSeguroPrestamistaFragment{8f2c1a7}"
            + "_not_attached_to_a_context_at_androidx.fragment.app.Fragment.requireContext(Fragment.java:972)"
    }

    /// Uma conferência: campo, esperado, obtido (`nil` = não veio) e se confere.
    private struct Conferencia {
        let campo: String
        let esperado: String
        let obtido: String?
        let ok: Bool

        init(_ campo: String, _ esperado: String, _ obtido: String?, _ ok: Bool) {
            self.campo = campo
            self.esperado = esperado
            self.obtido = obtido
            self.ok = ok
        }

        var payload: [String: Any] {
            ["field": campo, "expected": esperado, "obtained": obtido.map { $0 as Any } ?? NSNull(), "ok": ok]
        }
    }

    private static func nulo(_ texto: String?) -> Any {
        if let texto { return texto }
        return NSNull()
    }

    /// Comentário longo do bloco quebrado em 78 colunas, como o `textwrap` do
    /// motor (`board.variant_block_text`).
    private static func quebrarComentario(_ linha: String, largura: Int = 78, recuo: String = "//   ") -> [String] {
        guard linha.hasPrefix("//"), linha.count > largura else { return [linha] }
        var linhas: [String] = []
        var atual = ""
        for palavra in linha.split(separator: " ").map(String.init) {
            let base = atual.isEmpty ? (linhas.isEmpty ? "" : recuo) : atual + " "
            if (base + palavra).count <= largura {
                atual = base + palavra
                continue
            }
            if !atual.isEmpty { linhas.append(atual) }
            atual = ""
            var resto = palavra
            while true {
                let inicio = linhas.isEmpty ? "" : recuo
                let espaco = largura - inicio.count
                if resto.count <= espaco {
                    atual = inicio + resto
                    break
                }
                linhas.append(inicio + String(resto.prefix(espaco)))
                resto = String(resto.dropFirst(espaco))
            }
        }
        if !atual.isEmpty { linhas.append(atual) }
        return linhas
    }

    /// O bloco com ✓/✗ no formato do motor.
    private static func bloco(cabeca: String, evento: String, status: String, conferencias: [Conferencia],
                              esperado: [(String, String)], hora: String?, disparos: Int, gaScreen: String?,
                              anteriores: [String], nota: String?) -> String {
        func json(_ texto: String) -> String {
            Double(texto) != nil ? texto : "\"\(texto.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        var linhas: [String]
        if status == "missing" {
            linhas = ["// \(cabeca)\(evento) [ERRO]", "// NÃO DISPARADO no log", "{"]
            for (i, par) in esperado.enumerated() {
                linhas.append("  \"\(par.0)\": \(json(par.1))" + (i < esperado.count - 1 ? "," : ""))
            }
            linhas.append("}  // esperado (spec)")
        } else {
            linhas = ["// \(cabeca)\(evento) [\(status == "ok" ? "OK" : "ERRO")]", "// log \(hora ?? "") · \(disparos) disparo(s)", "{"]
            for (i, c) in conferencias.enumerated() {
                let virgula = i < conferencias.count - 1 ? "," : ""
                linhas.append("  \"\(c.campo)\": \(c.obtido.map(json) ?? "AUSENTE")\(virgula)  \(c.ok ? "✓" : "✗")")
                if !c.ok { linhas.append("    // ↳ esperado: \(c.esperado)") }
            }
            linhas.append("}")
            if let gaScreen { linhas.append("// ga_screen: \(gaScreen)") }
            if !anteriores.isEmpty {
                linhas.append("// ⚠ \(anteriores.count) disparo(s) anterior(es) divergente(s):")
                linhas += anteriores.prefix(4).map { "//   \($0)" }
            }
        }
        if let nota { linhas.append("// obs: \(nota)") }
        return linhas.flatMap { quebrarComentario($0) }.joined(separator: "\n")
    }

    /// Uma linha de `report.audit`, com divergências e bloco montados como o
    /// motor monta.
    private static func resultado(
        _ id: Int, card: Int, secao: String, titulo: String, fluxo: (key: String, label: String)?, evento: String,
        variacao: String, status: String, conferencias: [Conferencia] = [], esperado: [(String, String)] = [],
        hora: String? = nil, disparos: Int = 0, params: [String: Any] = [:], gaScreen: String? = nil,
        anteriores: [String] = [], nota: String? = nil
    ) -> [String: Any] {
        let divergencias = status == "missing" ? "Não disparado no log" : conferencias.filter { !$0.ok }
            .map { "\($0.campo): obtido \($0.obtido ?? "AUSENTE"), esperado \($0.esperado)" }.joined(separator: "; ")
        let cabeca = fluxo.map { "\($0.label.components(separatedBy: " · ")[0]) · " } ?? ""
        let esperadoDaLinha = esperado.isEmpty ? conferencias.map { ($0.campo, $0.esperado) } : esperado
        var disparo: Any = NSNull()
        if status != "missing" {
            disparo = ["id": 0, "time": nulo(hora), "event_name": evento, "params": params] as [String: Any]
        }
        return [
            "id": id, "card_index": card, "section": secao, "card_title": titulo, "print_path": NSNull(),
            "flow": nulo(fluxo?.key), "flow_label": nulo(fluxo?.label), "event": evento, "variation": variacao,
            "status": status, "checks": conferencias.map(\.payload), "matched": disparo,
            "occurrences": status == "missing" ? 0 : disparos, "older_divergent": anteriores.count,
            "older_divergences": anteriores, "ga_screen": nulo(gaScreen), "note": nulo(nota),
            "divergences": divergencias,
            "block": bloco(cabeca: cabeca, evento: evento, status: status, conferencias: conferencias,
                           esperado: esperadoDaLinha, hora: hora, disparos: disparos, gaScreen: gaScreen,
                           anteriores: anteriores, nota: nota),
            "expected": esperadoDaLinha.map { ["key": $0.0, "value": $0.1] },
        ]
    }

    private static let fluxosLongos: [(key: String, label: String)] = [
        ("avulso", "PDA · pedido-avulso"), ("empresa", "PDE · pedido-empresa"), TextoLongo.fluxoLongo,
    ]

    /// `purchase` com 12 itens: `value` contra a soma dos itens (72.05) e a
    /// regra "item_id ou item_name" no item 3, que veio sem os dois.
    private static func compraComDozeItens(_ id: Int) -> [String: Any] {
        let precos = [5.00, 6.50, 4.25, 7.80, 3.90, 8.10, 5.55, 6.00, 7.25, 4.70, 6.35, 6.65]
        let skuErrado: Set<Int> = [2, 5, 7, 9, 11]
        var itens: [[String: Any]] = []
        var conferencias = [
            Conferencia("screen_name", "app:pedido:empresa:checkout:confirmacao", "app:pedido:empresa:checkout:confirmacao", true),
            Conferencia("flow_name", "pedido-empresa", "pedido-empresa", true),
            Conferencia("transaction_id", "[preenchido]", "T-2026-11-19-000482", true),
            Conferencia("currency", "BRL", "BRL", true),
            Conferencia("value", "soma dos itens: 72.05", "999.99", false),
        ]
        for (i, preco) in precos.enumerated() {
            let sku: String? = i == 3 ? nil : skuErrado.contains(i) ? "sku_\(10001 + i)" : "SKU-\(10001 + i)"
            var item: [String: Any] = ["price": preco, "quantity": 1]
            if let sku {
                item["item_id"] = sku
                item["item_name"] = i == 0 ? "Camiseta Básica Masculina Azul Marinho GG" : "Produto \(i + 1) do kit"
            }
            itens.append(item)
            conferencias.append(Conferencia("items[\(i)].item_id", "SKU-[numero]", sku, sku?.hasPrefix("SKU-") == true))
            if i == 0 {
                conferencias.append(Conferencia("items[0].item_name", "[preenchido]", "Camiseta Básica Masculina Azul Marinho GG", true))
            }
            if i == 3 {
                conferencias.append(Conferencia("items[3].item_id|item_name", "[preenchido]", nil, false))
            }
        }
        return resultado(
            id, card: 1, secao: TextoLongo.secaoCheckout,
            titulo: "Compra confirmada com 12 itens no carrinho, value igual à soma dos itens e regra item_id ou item_name",
            fluxo: fluxosLongos[1], evento: "purchase", variacao: "app:pedido:empresa:checkout:confirmacao", status: "error",
            conferencias: conferencias, hora: "14:41:22.907", disparos: 2,
            params: ["screen_name": "app:pedido:empresa:checkout:confirmacao", "flow_name": "pedido-empresa",
                     "transaction_id": "T-2026-11-19-000482", "currency": "BRL", "value": 999.99, "items": itens,
                     "ga_screen": "app:pedido:empresa:checkout:confirmacao"]
        )
    }

    /// Variação com tudo comprido: evento, título, fluxo, tela, detail, URL,
    /// item_name, ga_screen, disparos anteriores e a observação da spec.
    private static func variacaoComValoresLongos(_ id: Int) -> [String: Any] {
        resultado(
            id, card: 0, secao: TextoLongo.secaoSimulacao, titulo: TextoLongo.titulo, fluxo: TextoLongo.fluxoLongo,
            evento: TextoLongo.evento, variacao: TextoLongo.detail, status: "error",
            conferencias: [
                Conferencia("screen_name", TextoLongo.screenName, TextoLongo.screenName, true),
                Conferencia("flow_name", TextoLongo.flowName, TextoLongo.flowName, true),
                Conferencia("component", "button", "checkbox", false),
                Conferencia("detail", TextoLongo.detail, TextoLongo.detailObtido, false),
                Conferencia("link_url", TextoLongo.urlRegra, TextoLongo.url, true),
                Conferencia("items[0].item_name", TextoLongo.itemName, TextoLongo.itemNameObtido, false),
            ],
            hora: "14:36:05.412", disparos: 4,
            params: ["screen_name": TextoLongo.screenName, "flow_name": TextoLongo.flowName, "component": "checkbox",
                     "detail": TextoLongo.detailObtido, "link_url": TextoLongo.url, "ga_screen": TextoLongo.gaScreen,
                     "items": [["item_id": "SKU-48210", "item_name": TextoLongo.itemNameObtido, "price": 1299.9, "quantity": 1]]],
            gaScreen: TextoLongo.gaScreen,
            anteriores: ["detail=\(TextoLongo.detailObtido)", "flow_name=\(TextoLongo.flowName.replacingOccurrences(of: "android", with: "ios"))"],
            nota: TextoLongo.obs
        )
    }

    /// Auditoria com as duas linhas acima e outras para encher a tabela: `id` 1
    /// é a compra com 12 itens, `id` 2 a de valores longos.
    private func relatorioComTextosGrandes() throws -> AuditReport {
        typealias T = TextoLongo
        let fluxos = Self.fluxosLongos
        let resultados: [[String: Any]] = [
            Self.resultado(0, card: 4, secao: "Home", titulo: "screen_view", fluxo: nil, evento: "screen_view",
                           variacao: "app:pedido:home", status: "ok",
                           conferencias: [Conferencia("screen_name", "app:pedido:home", "app:pedido:home", true),
                                          Conferencia("flow_name", "pedido", "pedido", true)],
                           hora: "14:32:01.118", disparos: 3,
                           params: ["screen_name": "app:pedido:home", "flow_name": "pedido", "ga_screen": "app:pedido:home"]),
            Self.compraComDozeItens(1),
            Self.variacaoComValoresLongos(2),
            Self.resultado(3, card: 0, secao: T.secaoSimulacao, titulo: T.titulo, fluxo: T.fluxoLongo, evento: T.evento,
                           variacao: T.detailParcelas, status: "missing",
                           esperado: [("screen_name", T.screenName), ("flow_name", T.flowName), ("component", "button"),
                                      ("detail", T.detailParcelas), ("link_url", T.urlRegra)],
                           nota: T.obs),
            Self.resultado(4, card: 3, secao: T.secaoSimulacao, titulo: "Parcelas", fluxo: fluxos[1],
                           evento: "interaction_pedido_empresa", variacao: "click:parcelas", status: "ok",
                           conferencias: [Conferencia("screen_name", "app:pedido:empresa:simulacao", "app:pedido:empresa:simulacao", true),
                                          Conferencia("flow_name", "pedido-empresa", "pedido-empresa", true),
                                          Conferencia("component", "button", "button", true),
                                          Conferencia("detail", "click:parcelas", "click:parcelas", true)],
                           hora: "14:34:40.020", disparos: 1,
                           params: ["screen_name": "app:pedido:empresa:simulacao", "flow_name": "pedido-empresa",
                                    "component": "button", "detail": "click:parcelas"]),
            Self.resultado(5, card: 2, secao: T.secaoSimulacao, titulo: "add_to_cart", fluxo: fluxos[0], evento: "add_to_cart",
                           variacao: "click:adicionar-ao-carrinho", status: "error",
                           conferencias: [Conferencia("screen_name", "app:pedido:avulso:simulacao", "app:pedido:avulso:simulacao", true),
                                          Conferencia("flow_name", "pedido-avulso", "pedido-avulso", true),
                                          Conferencia("value", "soma dos itens: 1299.90", "129.99", false),
                                          Conferencia("items[0].item_id", "SKU-[numero]", "SKU-48210", true),
                                          Conferencia("items[0].item_name", T.itemName, T.itemNameCortado, false),
                                          Conferencia("detail", "click:adicionar-ao-carrinho", "click:adicionar-ao-carrinho", true)],
                           hora: "14:38:12.733", disparos: 1,
                           params: ["screen_name": "app:pedido:avulso:simulacao", "flow_name": "pedido-avulso", "value": 129.99,
                                    "detail": "click:adicionar-ao-carrinho",
                                    "items": [["item_id": "SKU-48210", "item_name": T.itemNameCortado, "price": 1299.9, "quantity": 1]]]),
            Self.resultado(6, card: 1, secao: T.secaoCheckout,
                           titulo: "Compra confirmada com 12 itens no carrinho, value igual à soma dos itens e regra item_id ou item_name",
                           fluxo: fluxos[0], evento: "purchase", variacao: "app:pedido:avulso:checkout:confirmacao", status: "ok",
                           conferencias: [Conferencia("value", "soma dos itens: 11.50", "11.5", true),
                                          Conferencia("items[0].item_id", "SKU-[numero]", "SKU-10001", true),
                                          Conferencia("items[1].item_id", "SKU-[numero]", "SKU-10002", true)],
                           hora: "14:40:02.551", disparos: 1,
                           params: ["value": 11.5, "items": [["item_id": "SKU-10001", "price": 5.0, "quantity": 1],
                                                             ["item_id": "SKU-10002", "price": 6.5, "quantity": 1]]]),
            Self.resultado(7, card: 2, secao: T.secaoSimulacao, titulo: "add_to_cart", fluxo: fluxos[1], evento: "add_to_cart",
                           variacao: "click:comprar-agora", status: "missing",
                           esperado: [("screen_name", "app:pedido:empresa:simulacao"), ("flow_name", "pedido-empresa"),
                                      ("value", "[soma_itens]"), ("detail", "click:comprar-agora")]),
            Self.resultado(8, card: 4, secao: "Home", titulo: "screen_view", fluxo: T.fluxoLongo, evento: "screen_view",
                           variacao: T.screenName, status: "ok",
                           conferencias: [Conferencia("screen_name", T.screenName, T.screenName, true),
                                          Conferencia("flow_name", T.flowName, T.flowName, true)],
                           hora: "14:35:58.004", disparos: 2,
                           params: ["screen_name": T.screenName, "flow_name": T.flowName]),
        ]
        let foraDaSpec: [[String: Any]] = [
            ["event": "select_promotion_banner_carrossel_home_black_friday_parcelamento_sem_juros", "screen": T.screenName,
             "flow_name": T.flowName, "component": "banner-carrossel-topo-home", "detail": T.detailForaDaSpec, "count": 3],
            ["event": "view_promotion", "screen": "app:pedido:home", "flow_name": "pedido", "component": "carrossel",
             "detail": "impression:banner-topo", "count": 12],
        ]
        let alertas: [[String: Any]] = [
            ["event": "app_exception", "screen": T.screenName, "flow_name": T.flowName, "component": NSNull(),
             "detail": T.excecao, "count": 1],
        ]
        let payload: [String: Any] = [
            "spec": [
                "path": T.specPath, "projeto": T.projeto, "versao_especificacao": "v3.2 revisada em 18/11/2026 após homologação com produto",
                "plataforma": "android", "prints_dir": T.printsDir, "prints_dir_exists": true,
                "fluxos": fluxos.map { ["key": $0.key, "label": $0.label] }, "cards": 5, "variants": 9,
                "sections": [T.secaoSimulacao, T.secaoCheckout, "Home"],
            ] as [String: Any],
            "platform": "android", "source": "file", "log_path": T.logPath,
            "log_stats": ["total_lidos": 1482, "da_plataforma": 1311, "duplicados": 207, "uteis": 1104],
            "summary": ["total": 9, "ok": 4, "divergent": 3, "missing": 2, "compliance_rate": 44.4, "extras": 2, "alerts": 1]
                as [String: Any],
            "results": resultados, "extras": foraDaSpec, "alerts": alertas,
            "observations": "", "markdown": "", "tsv": "",
        ]
        let dados = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
    }

    /// Card no formato de `report.card` / `report.cards`.
    private static func cartao(_ indice: Int, secao: String, titulo: String?, evento: String, print: String? = nil,
                               params: [(String, Any)], variacoes: [[(String, Any)]] = [], obs: String? = nil) -> [String: Any] {
        [
            "card_index": indice, "cards": 5, "secao": secao, "titulo": nulo(titulo), "evento": evento, "print": nulo(print),
            "params": params.map { ["key": $0.0, "value": $0.1] as [String: Any] },
            "variacoes": variacoes.map { $0.map { ["key": $0.0, "value": $0.1] as [String: Any] } },
            "obs": nulo(obs), "obs_por_fluxo": false, "params_por_fluxo": [String](),
        ]
    }

    /// Os cinco cards da spec: 0 com textos longos, 1 a compra com `items` de
    /// vários campos, 2 o add_to_cart com item_name de ~250 caracteres, 3 e 4
    /// curtos, para comparar.
    private static var cartoesLongos: [[String: Any]] {
        typealias T = TextoLongo
        let itensDaCompra: [[String: Any]] = [
            ["item_id|item_name": "[preenchido]", "item_name": T.itemName,
             "item_category": "vestuario/masculino/camisetas/basicas/manga-curta", "item_variant": "azul-marinho-mesclado/GG",
             "price": "[numero]", "quantity": "[numero]"],
            ["item_id": "SKU-[numero]", "item_name": "[preenchido]", "price": "[numero]", "quantity": "[numero]"],
            ["item_id|item_name": "[preenchido]", "price": "[numero]", "quantity": "[numero]", "coupon": "[preenchido]",
             "discount": "[numero]"],
        ]
        return [
            cartao(0, secao: T.secaoSimulacao, titulo: T.titulo, evento: T.evento,
                   print: "simulacao_parcelamento_seguro_prestamista_carencia_90_dias_confirmacao_valor_final_v3.png",
                   params: [("screen_name", "app:pedido:{fluxo}:simulacao:parcelamento:seguro-prestamista:carencia-90-dias:"
                             + "confirmacao-do-valor-final-das-parcelas:revisao"),
                            ("flow_name", "pedido-{fluxo}-com-seguro-prestamista-e-parcelamento-estendido-em-ate-48-vezes-sem-"
                             + "juros-carencia-90-dias-canal-app-android"),
                            ("component", "button"), ("link_url", T.urlRegra)],
                   variacoes: [[("detail", T.detail)], [("detail", T.detailParcelas)],
                               [("detail", "click:seguro-prestamista"), ("component", "checkbox")]],
                   obs: T.obs),
            cartao(1, secao: T.secaoCheckout,
                   titulo: "Compra confirmada com 12 itens no carrinho, value igual à soma dos itens e regra item_id ou item_name",
                   evento: "purchase",
                   params: [("screen_name", "app:pedido:{fluxo}:checkout:confirmacao"), ("flow_name", "pedido-{fluxo}"),
                            ("transaction_id", "[preenchido]"), ("currency", "BRL"), ("value", "[soma_itens]"),
                            ("items", itensDaCompra)]),
            cartao(2, secao: T.secaoSimulacao, titulo: nil, evento: "add_to_cart",
                   params: [("screen_name", "app:pedido:{fluxo}:simulacao"), ("flow_name", "pedido-{fluxo}"),
                            ("value", "[soma_itens]"),
                            ("items", [["item_id": "SKU-[numero]", "item_name": T.itemName, "price": "[numero]", "quantity": "1"]])],
                   variacoes: [[("detail", "click:adicionar-ao-carrinho")], [("detail", "click:comprar-agora")]]),
            cartao(3, secao: T.secaoSimulacao, titulo: "Parcelas", evento: "interaction_pedido_{fluxo}",
                   params: [("screen_name", "app:pedido:{fluxo}:simulacao"), ("flow_name", "pedido-{fluxo}"), ("component", "button")],
                   variacoes: [[("detail", "click:parcelas")]], obs: "Conferido com produto"),
            cartao(4, secao: "Home", titulo: nil, evento: "screen_view", print: "home.png",
                   params: [("screen_name", "app:pedido:home"), ("flow_name", "pedido")]),
        ]
    }

    private func specComTextosGrandes() throws -> ReportSpecDraft {
        let payload: [String: Any] = [
            "path": TextoLongo.specPath, "projeto": TextoLongo.projeto, "spec_error": NSNull(), "prints_dir": TextoLongo.printsDir,
            "fluxos": Self.fluxosLongos.map { ["key": $0.key, "label": $0.label] }, "cards": Self.cartoesLongos,
        ]
        let dados = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(EngineDTO.ReportCardsPayload.self, from: dados).toModel()
    }

    /// Janela do Relatório com a auditoria de textos grandes. `cardDoMotor` é o
    /// que `report.card` devolve ao tocar em Editar no inspector.
    private func ambienteComTextosGrandes(selecionado: Int?, cardDoMotor: Int? = nil) throws -> (AppState, EngineSession, ThemeManager) {
        let (e, _, t) = ambiente(conectado: false, area: .report)
        let relatorio = try relatorioComTextosGrandes()
        e.reportSpec = relatorio.spec
        e.reportLogSource = .file(URL(fileURLWithPath: TextoLongo.logPath))
        e.report = relatorio
        e.selectedReportResultID = selecionado
        var respostas: [String: Data] = [:]
        if let cardDoMotor {
            respostas["report.card"] = try JSONSerialization.data(withJSONObject: Self.cartoesLongos[cardDoMotor])
        }
        return (e, EngineSession(state: e, client: FakeEngine(respostas: respostas)), t)
    }

    /// Aciona um controle da janela pelo rótulo, como um clique: segmento de
    /// Picker, botão do AppKit ou, por último, o elemento de acessibilidade.
    @discardableResult
    private func acionar(_ rotulo: String, na janela: NSWindow) -> Bool {
        func visitar(_ view: NSView) -> Bool {
            if let segmentos = view as? NSSegmentedControl {
                for i in 0..<segmentos.segmentCount where segmentos.label(forSegment: i) == rotulo {
                    segmentos.selectedSegment = i
                    if let acao = segmentos.action { NSApp.sendAction(acao, to: segmentos.target, from: segmentos) }
                    return true
                }
            }
            if let botao = view as? NSButton, botao.title == rotulo {
                botao.performClick(nil)
                return true
            }
            return view.subviews.contains(where: visitar)
        }
        if let raiz = janela.contentView, visitar(raiz) { return true }

        // Botão do SwiftUI sem NSButton por baixo: pela árvore de acessibilidade.
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        func valor(_ objeto: NSObject, _ seletor: String) -> Any? {
            let sel = Selector(seletor)
            guard objeto.responds(to: sel) else { return nil }
            return objeto.perform(sel)?.takeUnretainedValue()
        }
        var fila: [NSObject] = janela.contentView.map { [$0] } ?? []
        var visitados = 0
        while !fila.isEmpty && visitados < 50_000 {
            let objeto = fila.removeFirst()
            visitados += 1
            let papel = (valor(objeto, "accessibilityRole") as? String) ?? ""
            let rotuloAX = (valor(objeto, "accessibilityLabel") as? String) ?? ""
            let nome = rotuloAX.isEmpty ? ((valor(objeto, "accessibilityTitle") as? String) ?? "") : rotuloAX
            if ["AXButton", "AXRadioButton"].contains(papel), nome == rotulo,
               objeto.responds(to: Selector("accessibilityPerformPress")) {
                _ = objeto.perform(Selector("accessibilityPerformPress"))
                return true
            }
            if let filhos = valor(objeto, "accessibilityChildren") as? [Any] {
                fila += filhos.compactMap { $0 as? NSObject }
            }
        }
        return false
    }

    /// Aciona os controles em ordem. Os anteriores ao último são opcionais:
    /// "Bloco e Disparo" só existe com o detalhe empilhado (janela estreita).
    private func acionarEmOrdem(_ rotulos: [String], na janela: NSWindow) -> Bool {
        for rotulo in rotulos.dropLast() where acionar(rotulo, na: janela) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        }
        return rotulos.last.map { acionar($0, na: janela) } ?? true
    }

    /// Rola a área com rolagem mais interna sob cada ponto, dado em fração da
    /// janela a partir do canto superior esquerdo, até `fracao` do conteúdo.
    private func rolar(_ pontos: [CGPoint], fracao: CGFloat, na janela: NSWindow) -> Bool {
        guard let raiz = janela.contentView else { return false }
        var rolagens: [NSScrollView] = []
        func coletar(_ view: NSView) {
            if let rolagem = view as? NSScrollView { rolagens.append(rolagem) }
            view.subviews.forEach(coletar)
        }
        coletar(raiz)
        let quadro = janela.frame.size
        var rolou = false
        for ponto in pontos {
            let alvo = NSPoint(x: ponto.x * quadro.width, y: quadro.height - ponto.y * quadro.height)
            let candidatas = rolagens.filter { !$0.isHidden && $0.convert($0.bounds, to: nil).contains(alvo) }
            guard let rolagem = candidatas.min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }),
                  let documento = rolagem.documentView else { continue }
            let clip = rolagem.contentView
            let maximo = max(0, documento.frame.height - clip.bounds.height)
            guard maximo > 0 else { continue }
            let y = documento.isFlipped ? maximo * fracao : maximo * (1 - fracao)
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            rolagem.reflectScrolledClipView(clip)
            rolou = true
        }
        return rolou
    }

    /// Pontos do painel de validação e do bloco, abaixo da tabela. Na janela
    /// estreita os dois caem na validação, que ocupa a largura toda.
    private static let pontosDoDetalhe = [CGPoint(x: 0.34, y: 0.86), CGPoint(x: 0.63, y: 0.86)]
    /// Ponto do inspector (card do Figma ou o formulário de edição).
    private static let pontoDoInspector = [CGPoint(x: 0.9, y: 0.6)]

    /// Fotografa a cena em claro e escuro, em 1280×800 e na janela pequena,
    /// numerando a partir de `numero`: `01-nome-claro`, `02-nome-escuro`,
    /// `03-nome-pequena-claro`, `04-nome-pequena-escuro`. `preparar` roda com
    /// a janela na tela e diz se achou o que precisava.
    private func fotografarTextosGrandes(_ numero: Int, _ nome: String, preparar: ((NSWindow) -> Bool)? = nil,
                                         montar: () throws -> (AppState, EngineSession, ThemeManager)) throws {
        let tamanhos: [(sufixo: String, tamanho: CGSize, inicial: CGSize?)] = [
            ("", CGSize(width: 1280, height: 800), nil),
            ("-pequena", CGSize(width: 1024, height: 680), CGSize(width: 1440, height: 900)),
        ]
        var n = numero
        for (sufixo, tamanho, inicial) in tamanhos {
            for escuro in [false, true] {
                let (e, s, t) = try montar()
                let arquivo = String(format: "%02d", n) + "-\(nome)\(sufixo)-\(escuro ? "escuro" : "claro")"
                var preparou = true
                var antes: ((NSWindow) -> Void)? = nil
                if let preparar {
                    antes = { janela in preparou = preparar(janela) }
                }
                try fotografar(janela(e, s, t), tamanho: tamanho, nome: arquivo, escuro: escuro, tema: t, partindoDe: inicial,
                               preparar: antes)
                XCTAssertTrue(preparou, "\(arquivo): a preparação não achou o controle ou a rolagem na janela")
                n += 1
            }
        }
    }

    /// Cenário 1: `purchase` com 12 itens, `value` contra a soma dos itens e
    /// `items[3].item_id|item_name`. Como abre (01–04), validação e bloco
    /// rolados até os itens (05–08) e a aba Disparo (09–12).
    func testTextosGrandesResultadoItens() throws {
        _ = try destino()
        let montar = { try self.ambienteComTextosGrandes(selecionado: 1) }
        try fotografarTextosGrandes(1, "resultado-itens", montar: montar)
        try fotografarTextosGrandes(5, "resultado-itens-rolado", preparar: {
            self.rolar(Self.pontosDoDetalhe, fracao: 0.5, na: $0)
        }, montar: montar)
        try fotografarTextosGrandes(9, "resultado-itens-disparo", preparar: {
            self.acionarEmOrdem(["Bloco e Disparo", "Disparo"], na: $0)
        }, montar: montar)
    }

    /// Cenário 2: valores longos (título, evento, fluxo, tela, detail, URL,
    /// item_name, observação). Como abre (13–16), validação e bloco rolados
    /// até a grade (17–20) e até o fim (21–24), aba Disparo (25–28) e o evento
    /// fora da spec com flow_name e detail longos (29–32).
    func testTextosGrandesValoresLongos() throws {
        _ = try destino()
        let montar = { try self.ambienteComTextosGrandes(selecionado: 2) }
        try fotografarTextosGrandes(13, "valores-longos", montar: montar)
        try fotografarTextosGrandes(17, "valores-longos-rolado", preparar: {
            self.rolar(Self.pontosDoDetalhe, fracao: 0.4, na: $0)
        }, montar: montar)
        try fotografarTextosGrandes(21, "valores-longos-rolado-fim", preparar: {
            self.rolar(Self.pontosDoDetalhe, fracao: 1, na: $0)
        }, montar: montar)
        try fotografarTextosGrandes(25, "valores-longos-disparo", preparar: {
            self.acionarEmOrdem(["Bloco e Disparo", "Disparo"], na: $0)
        }, montar: montar)
        try fotografarTextosGrandes(29, "valores-longos-fora-da-spec") {
            let (e, s, t) = try self.ambienteComTextosGrandes(selecionado: nil)
            e.reportFilter = .outOfSpec
            e.selectedReportExtraID = 0
            return (e, s, t)
        }
    }

    /// Cenário 3: editor de spec. Quadro (33–36), Quadro filtrado na compra com
    /// `items` de vários campos (37–40) e Tabela (41–44).
    func testTextosGrandesEditorDeSpec() throws {
        _ = try destino()
        func editor(_ modo: ReportSpecEditorMode, busca: String = "") throws -> (AppState, EngineSession, ThemeManager) {
            let (e, s, t) = try ambienteComTextosGrandes(selecionado: nil)
            e.report = nil
            e.reportSpecEditor = try specComTextosGrandes()
            e.reportSpecEditorMode = modo
            e.reportFilterText = busca
            return (e, s, t)
        }
        try fotografarTextosGrandes(33, "editor-quadro") { try editor(.board) }
        try fotografarTextosGrandes(37, "editor-quadro-itens") { try editor(.board, busca: "purchase") }
        try fotografarTextosGrandes(41, "editor-tabela") { try editor(.table) }
    }

    /// Cenário 5 (3.28.0): erros e avisos no campo (RE-02, RE-08) e a folha de
    /// JSON (RE-03). O card 2 (`purchase`) ganha evento vazio, parâmetro sem
    /// nome, regra digitada errada e `items` quebrado; o "3 para corrigir" do
    /// cabeçalho é clicado como quem clica, e mostra os erros (57–64). Depois,
    /// a folha de JSON do `items` aberta pelo resumo (65–68).
    func testTextosGrandesEditorComProblemas() throws {
        _ = try destino()
        func editor(_ modo: ReportSpecEditorMode, quebrado: Bool) throws -> (AppState, EngineSession, ThemeManager) {
            let (e, s, t) = try ambienteComTextosGrandes(selecionado: nil)
            e.report = nil
            var spec = try specComTextosGrandes()
            let compra = try XCTUnwrap(spec.cards.firstIndex { $0.evento == "purchase" })
            if quebrado {
                spec.cards[compra].evento = ""
                if let i = spec.cards[compra].params.firstIndex(where: { $0.key == "value" }) {
                    spec.cards[compra].params[i].value = "[soma_item]"
                }
                if let i = spec.cards[compra].params.firstIndex(where: \.isJSON) {
                    spec.cards[compra].params[i].value = #"[{"item_id|item_name":"[preenchido]","price":"[numero]""#
                }
                spec.cards[compra].params.append(.init(key: "", value: "BRL"))
            }
            e.reportSpecEditor = spec
            e.reportSpecEditorMode = modo
            e.reportFilterText = "12 itens"
            return (e, s, t)
        }
        try fotografarTextosGrandes(57, "editor-quadro-problemas", preparar: { self.acionar("3 para corrigir", na: $0) }) {
            try editor(.board, quebrado: true)
        }
        try fotografarTextosGrandes(61, "editor-tabela-problemas", preparar: { self.acionar("3 para corrigir", na: $0) }) {
            try editor(.table, quebrado: true)
        }
        // A folha é outra janela: a captura da janela principal só pegaria o
        // fundo escurecido. A folha é aberta pelo resumo do `items`, como quem
        // clica, e fotografada sozinha; o fundo vai para um arquivo apagado depois.
        let pasta = try destino()
        let valido = #"[{"item_id|item_name":"[preenchido]","item_category":"vestuario/masculino/camisetas","#
            + #""price":"[numero]","quantity":"[numero]"},{"item_id":"SKU-[numero]","price":"[numero]"}]"#
        let quebrado = #"[{"item_id|item_name":"[preenchido]","price":"[numero]""#
        for (n, json, nome) in [(65, valido, "valido"), (67, quebrado, "erro")] {
            for escuro in [false, true] {
                let (e, s, t) = try editor(.board, quebrado: false)
                if let c = e.reportSpecEditor?.cards.firstIndex(where: { $0.evento == "purchase" }),
                   let i = e.reportSpecEditor?.cards[c].params.firstIndex(where: \.isJSON) {
                    e.reportSpecEditor?.cards[c].params[i].value = json
                }
                let arquivo = String(format: "%02d", n + (escuro ? 1 : 0)) + "-editor-json-\(nome)-\(escuro ? "escuro" : "claro")"
                var capturou = false
                _ = try fotografar(janela(e, s, t), tamanho: CGSize(width: 1280, height: 800), nome: "_fundo-\(arquivo)",
                                   escuro: escuro, tema: t, preparar: { janela in
                    let rotulo = json == valido ? "Valor JSON de items, card 2 · purchase" : "Valor JSON de items, card 2 · purchase"
                    guard self.acionar(rotulo, na: janela) else { return }
                    RunLoop.main.run(until: Date().addingTimeInterval(1.2))
                    // A folha não tem vidro: o desenho da própria view basta, e o
                    // servidor de janelas devolve a folha em branco.
                    guard let folha = janela.attachedSheet, let conteudo = folha.contentView,
                          let rep = conteudo.bitmapImageRepForCachingDisplay(in: conteudo.bounds) else { return }
                    conteudo.cacheDisplay(in: conteudo.bounds, to: rep)
                    print("FOLHA \(arquivo): \(folha.frame.size) subviews=\(conteudo.subviews.count)")
                    guard let png = rep.representation(using: .png, properties: [:]) else { return }
                    capturou = (try? png.write(to: pasta.appendingPathComponent("\(arquivo).png"))) != nil
                    janela.endSheet(folha)
                })
                try? FileManager.default.removeItem(at: pasta.appendingPathComponent("_fundo-\(arquivo).png"))
                XCTAssertTrue(capturou, "\(arquivo): a folha de JSON não abriu ou não foi fotografada")
            }
        }
    }

    /// Cenário 4: Editar card no inspector, aberto pelo botão Editar como quem
    /// clica. Card de valores longos (45–48), o mesmo rolado até a observação
    /// (49–52) e a compra com `items` (53–56).
    func testTextosGrandesEditarCard() throws {
        _ = try destino()
        let longo = { try self.ambienteComTextosGrandes(selecionado: 2, cardDoMotor: 0) }
        try fotografarTextosGrandes(45, "editar-card-valores-longos", preparar: { self.acionar("Editar", na: $0) },
                                    montar: longo)
        try fotografarTextosGrandes(49, "editar-card-valores-longos-rolado", preparar: { janela in
            guard self.acionar("Editar", na: janela) else { return false }
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            return self.rolar(Self.pontoDoInspector, fracao: 1, na: janela)
        }, montar: longo)
        try fotografarTextosGrandes(53, "editar-card-itens", preparar: { self.acionar("Editar", na: $0) }) {
            try self.ambienteComTextosGrandes(selecionado: 1, cardDoMotor: 1)
        }
    }
}

/// Amostra do vidro num tema: Rodar (vidro tingido com o destaque), a cápsula
/// do Ambiente e um painel flutuante, sobre o fundo da janela do tema. Usa os
/// modificadores de verdade (`Glass.swift`), fora da toolbar, para ver as doze
/// aparências numa imagem. O tom só aparece com o app ativo na captura.
private struct AmostraDeVidro: View {
    let nome: String
    let tema: any ThemeTokens
    var forcarTom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(nome).font(DSFont.subheadlineSemibold).foregroundStyle(tema.labelSecondary)
            // Como o Rodar de verdade: com o app inativo o tom sai (D2), e no
            // vidro do macOS 26 o próprio sistema tira o tom de app inativo. O
            // recuo é desenhado pelo app e pode mostrar o tom para conferir o
            // rótulo `onAccent`.
            Button {} label: { Label("Rodar Automação", systemImage: "play.fill") }
                .mbProminentGlassButton(forcarTom || NSApp.isActive)
            HStack(spacing: 6) {
                Circle().fill(tema.warningFill).frame(width: 7, height: 7)
                Text("Ambiente: 3 de 4").font(DSFont.mono(11)).foregroundStyle(tema.labelPrimary)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .mbGlass(.capsula, in: Capsule(), interactive: true)
            Text("Painel flutuante").font(DSFont.callout).foregroundStyle(tema.labelPrimary)
                .padding(10)
                .mbGlass(.flutuante, in: RoundedRectangle(cornerRadius: DesignMetrics.Radius.card, style: .continuous))
        }
        .padding(14)
        .frame(width: 200, height: 170, alignment: .topLeading)
        .background(tema.bgWindow)
        .environment(ThemeManager(preview: tema))
        .environment(\.colorScheme, tema.isDark ? .dark : .light)
    }

    static func todas(forcarTom: Bool = false) -> some View {
        let temas: [(String, any ThemeTokens)] = [("Praia clara", PraiaLightTheme()), ("Praia escura", PraiaDarkTheme()),
                                                  ("Praia escura · contraste", PraiaDarkTheme(highContrast: true))]
            + PaletteSpec.all.map { ($0.name, PaletteTheme(spec: $0, highContrast: false) as any ThemeTokens) }
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(200), spacing: 0), count: 4), spacing: 0) {
            ForEach(Array(temas.enumerated()), id: \.offset) { _, par in AmostraDeVidro(nome: par.0, tema: par.1, forcarTom: forcarTom) }
        }
        .fixedSize()
    }
}
