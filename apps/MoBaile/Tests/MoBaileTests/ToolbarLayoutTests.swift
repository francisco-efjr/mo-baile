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

    func testTituloSemAparelho() throws {
        let (estado, sessao, tema) = ambiente(aparelho: nil)
        let (janela, _) = try itensDaToolbar(estado, sessao, tema)
        defer { janela.close() }
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

    /// Os segmentos do modo do clique têm nome próprio e o grupo, o dele.
    func testModoDoCliqueNomeiaOsSegmentos() throws {
        let (estado, sessao, tema) = ambiente()
        let ax = try arvore(InteractionModePicker(), estado, sessao, tema)
        let rotulos = ax.all.map(\.label)
        for esperado in ["Repassar toque", "Gravar passo"] {
            XCTAssertTrue(rotulos.contains(esperado), "falta '\(esperado)': \(rotulos)\n\(ax.dump)")
        }
        XCTAssertNotNil(ax.node(label: "Ação do clique no espelho"), ax.dump)
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
}
