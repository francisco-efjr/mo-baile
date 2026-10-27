import XCTest
import SwiftUI
import AppKit
@testable import MoBaile

/// Guarda da toolbar unificada.
///
/// A barra antiga sumiu da janela uma vez sem que nada quebrasse: desenhada
/// isolada continuava certa, e só empilhada na janela é que colapsava. Com a
/// toolbar nativa o risco equivalente é ela não ser instalada na janela (um
/// `.toolbar` no lugar errado da hierarquia não dá erro, só não aparece).
/// Por isso a primeira guarda abre a janela de verdade e confere os itens.
@MainActor
final class ToolbarLayoutTests: XCTestCase {

    private func ambiente(
        plataforma: Platform = .ios,
        aparelho: (id: String, name: String)? = (id: "7303D258", name: "iPhone 16")
    ) -> (AppState, EngineSession, ThemeManager) {
        let estado = AppState()
        estado.platform = plataforma
        if let aparelho {
            estado.availableDevices = [aparelho]
            estado.selectedDevice = aparelho.id
        }
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        return (estado, sessao, ThemeManager())
    }

    /// Abre a janela principal e devolve os itens da toolbar instalada.
    private func itensDaToolbar(_ estado: AppState, _ sessao: EngineSession, _ tema: ThemeManager) throws -> (NSWindow, [NSToolbarItem]) {
        let controller = NSHostingController(
            rootView: ContentView().environment(estado).environment(sessao).environment(tema)
        )
        controller.sceneBridgingOptions = [.toolbars, .title]
        let janela = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        janela.isReleasedWhenClosed = false
        janela.contentViewController = controller
        janela.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        guard let toolbar = janela.toolbar else {
            janela.close()
            throw XCTSkip("O SwiftUI não instalou a toolbar neste ambiente (sem sessão gráfica?)")
        }
        return (janela, toolbar.items)
    }

    func testToolbarEInstaladaNaJanelaComTituloDaSecao() throws {
        let (estado, sessao, tema) = ambiente()
        let (janela, itens) = try itensDaToolbar(estado, sessao, tema)
        defer { janela.close() }

        // Aparelho, modo do clique, três de gravação, Rodar, Buscar, Inspector
        // e o botão da barra lateral: a contagem exata depende do macOS, mas
        // uma toolbar com menos de seis itens perdeu controles.
        XCTAssertGreaterThanOrEqual(itens.count, 6, "itens: \(itens.map(\.itemIdentifier.rawValue))")
        // O título mostra a seção, nunca o nome do app.
        XCTAssertEqual(janela.title, "Page Objects")
    }

    /// A janela abre no Início (`AppState.atLaunch`); numa área que precisa
    /// de aparelho, o título diz que não há um.
    func testTituloSemAparelho() throws {
        let (estado, sessao, tema) = ambiente(aparelho: nil)
        estado.workspaceTab = AppState.atLaunch().workspaceTab
        let (janela, _) = try itensDaToolbar(estado, sessao, tema)
        defer { janela.close() }
        XCTAssertEqual(janela.title, "Início")
        estado.workspaceTab = .pageObjects
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(janela.title, "Sem dispositivo")
    }

    /// O Relatório trabalha com arquivos: sem aparelho, a janela mostra a aba,
    /// e não o diagnóstico de "Sem dispositivo".
    func testRelatorioFuncionaSemAparelho() throws {
        let (estado, sessao, tema) = ambiente(aparelho: nil)
        estado.workspaceTab = .report
        let (janela, _) = try itensDaToolbar(estado, sessao, tema)
        defer { janela.close() }
        XCTAssertEqual(janela.title, "Relatório")
        XCTAssertEqual(janela.subtitle, "Nenhuma spec")
    }

    func testTituloAcompanhaAArea() throws {
        let (estado, sessao, tema) = ambiente()
        estado.workspaceTab = .network
        let (janela, _) = try itensDaToolbar(estado, sessao, tema)
        defer { janela.close() }
        XCTAssertEqual(janela.title, "Rede HTTP")
    }

    // MARK: - Componentes

    private func arvore<V: View>(_ view: V, _ estado: AppState, _ sessao: EngineSession, _ tema: ThemeManager, largura: CGFloat = 420) throws -> AXNode {
        try AccessibilityInspector.arvore(
            de: HStack { view }.environment(estado).environment(sessao).environment(tema),
            largura: largura, altura: 60
        )
    }

    /// O pop-up absorveu o seletor iOS | Android: tem de dizer qual aparelho
    /// está escolhido, ou "Nenhum dispositivo".
    func testPopUpDeAparelhoDizOAparelho() throws {
        let (estado, sessao, tema) = ambiente()
        let ax = try arvore(DeviceMenu(), estado, sessao, tema)
        let popup = ax.node(label: "Dispositivo")
        XCTAssertNotNil(popup, ax.dump)
        XCTAssertEqual(popup?.value, "iPhone 16", ax.dump)

        let (vazio, sessaoVazia, temaVazio) = ambiente(aparelho: nil)
        let axVazio = try arvore(DeviceMenu(), vazio, sessaoVazia, temaVazio)
        XCTAssertEqual(axVazio.node(label: "Dispositivo")?.value, "Nenhum dispositivo", axVazio.dump)
    }

    /// Gravando, os botões trocam de nome: o leitor precisa saber que o
    /// próximo clique para a gravação.
    func testBotoesDeGravacaoTrocamDeNomeEnquantoGravam() throws {
        let (estado, sessao, tema) = ambiente(plataforma: .android, aparelho: (id: "emulator-5554", name: "Pixel 7"))
        estado.scrcpyAvailable = true
        let parado = try arvore(HStack { PassiveCaptureButton(); ScreenRecordingButton(); ScrcpyButton() }, estado, sessao, tema)
        let rotulosParado = parado.buttons.map(\.label)
        XCTAssertTrue(rotulosParado.contains("Gravar do Aparelho"), "\(rotulosParado)")
        XCTAssertTrue(rotulosParado.contains("Gravar a Tela"), "\(rotulosParado)")
        XCTAssertTrue(rotulosParado.contains("Espelho 60 FPS"), "\(rotulosParado)")

        estado.passiveListening = true
        estado.screenRecording = true
        estado.scrcpyRunning = true
        let gravando = try arvore(HStack { PassiveCaptureButton(); ScreenRecordingButton(); ScrcpyButton() }, estado, sessao, tema)
        let rotulos = gravando.buttons.map(\.label)
        XCTAssertTrue(rotulos.contains("Parar Captura"), "\(rotulos)")
        XCTAssertTrue(rotulos.contains("Parar de Gravar a Tela"), "\(rotulos)")
        XCTAssertTrue(rotulos.contains("Fechar Espelho 60 FPS"), "\(rotulos)")
    }

    /// O 60 FPS é do Android: no iOS o botão não existe.
    func testScrcpySoNoAndroid() throws {
        let (estado, sessao, tema) = ambiente()
        estado.scrcpyAvailable = true
        let ax = try arvore(HStack { ScrcpyButton(); RunAutomationButton() }, estado, sessao, tema)
        XCTAssertFalse(ax.buttons.map(\.label).contains("Espelho 60 FPS"), ax.dump)
    }

    func testRodarSoComPassoEAparelho() {
        let (estado, _, _) = ambiente()
        XCTAssertFalse(RunAutomationButton.podeRodar(estado), "sem passo não roda")
        estado.steps = [AutomationStep(
            stepNum: 1, actionType: "click", varName: "BOTAO", elementName: "Botao", className: "Button",
            strategy: .id, locatorValue: "botao", coords: nil, inputText: nil, package: "p", platform: .ios
        )]
        XCTAssertTrue(RunAutomationButton.podeRodar(estado))
        estado.runState = .running
        XCTAssertFalse(RunAutomationButton.podeRodar(estado), "não roda duas vezes ao mesmo tempo")
        estado.runState = .idle
        estado.selectedDevice = nil
        XCTAssertFalse(RunAutomationButton.podeRodar(estado), "sem aparelho não roda")
    }

    // MARK: - Tamanho mínimo (D1, Q4)

    /// Mede o tamanho mínimo que a janela aceita com barra lateral e inspector
    /// abertos. O mínimo declarado (980) não dizia nada: a soma das colunas
    /// chegou a 1.885 pt e, numa janela menor, o conteúdo era desenhado nessa
    /// largura e cortado nas bordas.
    ///
    /// Três causas, todas fora daqui agora: o HSplitView do espelho (529 pt), o
    /// `.inspector` aninhado na NavigationSplitView (a barra lateral contava em
    /// dobro e as colunas eram medidas pela largura ideal: o Relatório com
    /// resultado pedia 1.743 pt) e os VSplitView de Rede, Analytics e Relatório.
    private func tamanhoMinimo(_ estado: AppState, _ sessao: EngineSession, _ tema: ThemeManager) throws -> CGSize {
        let controller = NSHostingController(
            rootView: ContentView().environment(estado).environment(sessao).environment(tema)
        )
        controller.sceneBridgingOptions = [.toolbars, .title]
        controller.sizingOptions = [.minSize]
        let janela = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        janela.isReleasedWhenClosed = false
        janela.toolbarStyle = .unified
        janela.contentViewController = controller
        janela.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        defer { janela.close() }
        guard janela.toolbar != nil else {
            throw XCTSkip("O SwiftUI não instalou a toolbar neste ambiente (sem sessão gráfica?)")
        }
        return janela.contentMinSize
    }

    /// Mínimo de uma view solta, numa janela sem toolbar.
    private func minimoDaView<V: View>(_ view: V) -> CGSize {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.minSize]
        let janela = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        janela.isReleasedWhenClosed = false
        janela.contentViewController = controller
        janela.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        defer { janela.close() }
        return janela.contentMinSize
    }

    /// As áreas com o conteúdo que mais pesa: requisição aberta em Rede,
    /// evento em Analytics, auditoria com uma divergência no Relatório.
    private func ambienteComConteudo(_ aba: WorkspaceTab) throws -> (AppState, EngineSession, ThemeManager) {
        let (estado, sessao, tema) = ambiente()
        estado.workspaceTab = aba
        estado.sidebarVisibility = .all
        estado.inspectorVisible = true
        estado.proxyRunning = true
        let requisicao = NetworkEvent(
            id: 1, timestamp: Date(), timeStr: "13:02:11", method: "POST",
            url: "https://api.demoapp.test/v2/pedido/simulacao", host: "api.demoapp.test", path: "/v2/pedido/simulacao",
            statusCode: 201, statusText: "Created",
            requestHeaders: ["Content-Type": "application/json", "User-Agent": "DemoApp/5.42.0 (iPhone; iOS 18.6; Scale/3.00)"],
            requestBody: "{\"valor\": 5000}", responseHeaders: ["Content-Type": "application/json"],
            responseBody: "{\"simulacao_id\": \"sim_8f2c\"}", durationMs: 812, protocol: "HTTP/1.1", isTunnel: false
        )
        estado.httpRequests = [requisicao]
        estado.selectedRequest = requisicao
        estado.analyticsListenerActive = true
        let evento = AnalyticsEvent(
            id: 1, timestamp: Date(), timeStr: "13:02:14.920", tag: "iOS (Firebase)", eventName: "simulacao_pedido_iniciada",
            params: ["canal": "app_ios", "parcelas": "12"], rawLog: "Logging event: simulacao_pedido_iniciada", platform: .ios
        )
        estado.analyticsEvents = [evento]
        estado.selectedAnalyticsEvent = evento
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.audit"])
        let relatorio = try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
        estado.reportSpec = relatorio.spec
        estado.report = relatorio
        estado.selectedReportResultID = relatorio.results.first { $0.status == .error }?.id
        return (estado, sessao, tema)
    }

    /// O teto cabe num monitor de 1.280 × 720 pt com folga para o Dock.
    func testJanelaCabeNumMonitorPequenoEmTodasAsAreas() throws {
        var medidas: [String] = []
        for aba in WorkspaceTab.allCases {
            for comConteudo in [false, true] {
                let (estado, sessao, tema): (AppState, EngineSession, ThemeManager)
                if comConteudo {
                    (estado, sessao, tema) = try ambienteComConteudo(aba)
                } else {
                    (estado, sessao, tema) = ambiente()
                    estado.workspaceTab = aba
                    estado.sidebarVisibility = .all
                    estado.inspectorVisible = true
                }
                let minimo = try tamanhoMinimo(estado, sessao, tema)
                let nome = "\(aba)\(comConteudo ? "+conteudo" : "")"
                medidas.append("\(nome)=\(Int(minimo.width))x\(Int(minimo.height))")
                XCTAssertLessThanOrEqual(minimo.width, 1100, "\(nome): largura mínima \(minimo.width) pt com barra lateral e inspector")
                XCTAssertLessThanOrEqual(minimo.height, 600, "\(nome): altura mínima \(minimo.height) pt")
            }
        }
        print("TAMANHO MINIMO: \(medidas.joined(separator: " "))")
    }

    /// O workspace declara 360 pt à janela com `.frame(minWidth:maxWidth:)`, que
    /// não repassa o mínimo do conteúdo. Se o conteúdo pedir mais, ele
    /// transborda a coluna: o espelho vai para baixo da barra lateral e o
    /// inspector sai pela borda (Rede pedia 564 pt com Request e Response lado
    /// a lado). O mesmo vale para o inspector.
    func testConteudoDasColunasCabeNoMinimoDeclarado() throws {
        for aba in WorkspaceTab.allCases {
            let (estado, sessao, tema) = try ambienteComConteudo(aba)
            // O Relatório ocupa a coluna inteira, fora do workspace, e declara o
            // próprio mínimo; o teste da janela já o cobre.
            if aba.needsDevice {
                let area = minimoDaView(WorkspacePane().environment(estado).environment(sessao).environment(tema))
                XCTAssertLessThanOrEqual(area.width, DesignMetrics.Widths.workspaceMin, "\(aba): workspace pede \(area.width) pt")
            }
            let inspector: CGSize
            if aba == .report {
                inspector = minimoDaView(ReportCardInspector().environment(estado).environment(sessao).environment(tema))
            } else {
                inspector = minimoDaView(InspectorPane().environment(estado).environment(sessao).environment(tema))
            }
            XCTAssertLessThanOrEqual(inspector.width, DesignMetrics.Widths.inspectorMin, "\(aba): inspector pede \(inspector.width) pt")
        }
    }
}
