import XCTest
import SwiftUI
@testable import MoBaile

/// Guarda de layout da barra superior.
///
/// Diferente de `LayoutSnapshotTests`, que só grava PNG para inspeção, esta
/// suíte afirma e falha sozinha. Ela existe porque a barra sumiu da janela sem
/// que nada quebrasse: desenhada isolada continuava correta, e só empilhada no
/// `VStack` da janela é que colapsava.
@MainActor
final class ToolbarLayoutTests: XCTestCase {

    private func barraEmpilhada() -> some View {
        let estado = AppState()
        estado.selectedDevice = "7303D258"
        estado.availableDevices = [(id: "7303D258", name: "iPhone 16")]
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        return VStack(spacing: 0) {
            UnifiedToolbar()
            Rectangle().fill(Color.gray)
        }
        .environment(estado)
        .environment(sessao)
        .environment(ThemeManager())
    }

    /// Lê os pixels de uma faixa horizontal do desenho.
    private func coresDaFaixa<V: View>(_ view: V, largura: CGFloat, altura: CGFloat, y: Int) throws -> Set<String> {
        let renderer = ImageRenderer(content: view.frame(width: largura, height: altura))
        renderer.scale = 1
        let imagem = try XCTUnwrap(renderer.nsImage)
        let tiff = try XCTUnwrap(imagem.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        var cores: Set<String> = []
        for x in stride(from: 0, to: Int(largura), by: 4) {
            guard let cor = bitmap.colorAt(x: x, y: y) else { continue }
            cores.insert(String(format: "%.2f,%.2f,%.2f", cor.redComponent, cor.greenComponent, cor.blueComponent))
        }
        return cores
    }

    /// Regressão: envolver a barra num `GeometryReader` a deixou sem altura
    /// intrínseca, e no `VStack` da janela ela colapsou — o preenchimento de
    /// baixo subiu e ocupou a faixa dela.
    ///
    /// A faixa de 26 pontos (meio da barra de 52) tem de conter os controles,
    /// ou seja, várias cores. Colapsada, ela vira uma cor só, a do que estiver
    /// atrás.
    func testBarraOcupaAFaixaDoTopoQuandoEmpilhada() throws {
        let cores = try coresDaFaixa(barraEmpilhada(), largura: 1440, altura: 200, y: 26)
        XCTAssertGreaterThan(
            cores.count, 3,
            "a faixa da barra saiu com \(cores.count) cor(es): a barra colapsou no VStack"
        )
    }

    /// E o que está abaixo dela continua sendo o conteúdo, não a barra
    /// esticada: o outro modo de errar é a barra tomar a janela inteira, que é
    /// o comportamento natural de um `GeometryReader` solto.
    func testBarraNaoInvadeOConteudoAbaixo() throws {
        let cores = try coresDaFaixa(barraEmpilhada(), largura: 1440, altura: 200, y: 150)
        XCTAssertEqual(
            cores.count, 1,
            "abaixo da barra deveria haver só o preenchimento; vieram \(cores.count) cores"
        )
    }

    /// Valida que a barra renderiza perfeitamente no estado desconectado
    func testBarraRenderizaDesconectadaSemErros() throws {
        let estado = AppState()
        estado.selectedDevice = nil
        estado.availableDevices = []
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        let toolbar = UnifiedToolbar()
            .environment(estado)
            .environment(sessao)
            .environment(ThemeManager())

        let renderer = ImageRenderer(content: toolbar.frame(width: 1440, height: 52))
        XCTAssertNotNil(renderer.nsImage, "Falha ao renderizar toolbar desconectada")
    }

    /// Valida renderização no Android com scrcpy ativo e inativo
    func testBarraRenderizaAndroidComScrcpy() throws {
        let estado = AppState()
        estado.platform = .android
        estado.selectedDevice = "emulator-5554"
        estado.availableDevices = [(id: "emulator-5554", name: "Pixel 7 Pro")]
        estado.scrcpyAvailable = true
        estado.scrcpyRunning = true
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        let toolbar = UnifiedToolbar()
            .environment(estado)
            .environment(sessao)
            .environment(ThemeManager())

        let renderer = ImageRenderer(content: toolbar.frame(width: 1440, height: 52))
        XCTAssertNotNil(renderer.nsImage, "Falha ao renderizar toolbar Android com scrcpy ativo")
    }

    /// Valida renderização no iOS físico vs iOS simulador
    func testBarraRenderizaIOSFisicoESimulador() throws {
        let estado = AppState()
        estado.platform = .ios
        estado.selectedDevice = "00008110-0012345678" // Dispositivo físico
        estado.availableDevices = [(id: "00008110-0012345678", name: "iPhone 15 Pro Max")]
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        let toolbarFisico = UnifiedToolbar()
            .environment(estado)
            .environment(sessao)
            .environment(ThemeManager())

        let rendererFisico = ImageRenderer(content: toolbarFisico.frame(width: 1440, height: 52))
        XCTAssertNotNil(rendererFisico.nsImage, "Falha ao renderizar toolbar no iOS físico")

        // Agora simulador (deve ter escuta passiva habilitada se UDID estiver em simulators)
        estado.selectedDevice = "7303D258"
        estado.availableDevices = [(id: "7303D258", name: "iPhone 16")]
        let toolbarSim = UnifiedToolbar()
            .environment(estado)
            .environment(sessao)
            .environment(ThemeManager())

        let rendererSim = ImageRenderer(content: toolbarSim.frame(width: 1440, height: 52))
        XCTAssertNotNil(rendererSim.nsImage, "Falha ao renderizar toolbar no iOS simulador")
    }

    /// Valida renderização nos estados de gravação de tela e escuta passiva simultâneos
    func testBarraRenderizaEstadosDeGravacao() throws {
        let estado = AppState()
        estado.platform = .android
        estado.selectedDevice = "emulator-5554"
        estado.availableDevices = [(id: "emulator-5554", name: "Pixel 7")]
        estado.screenRecording = true
        estado.passiveListening = true
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        let toolbar = UnifiedToolbar()
            .environment(estado)
            .environment(sessao)
            .environment(ThemeManager())

        let renderer = ImageRenderer(content: toolbar.frame(width: 1440, height: 52))
        XCTAssertNotNil(renderer.nsImage, "Falha ao renderizar toolbar gravando tela e escuta passiva")
    }

    /// Valida que a barra alterna para o modo compacto sem cortar elementos nem crashar em larguras menores
    func testBarraModoCompactoRenderizaSemErros() throws {
        let estado = AppState()
        estado.platform = .android
        estado.selectedDevice = "emulator-5554"
        estado.availableDevices = [(id: "emulator-5554", name: "Pixel 7 Pro Extra Long Name")]
        estado.screenRecording = true
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: [:]))
        let toolbar = UnifiedToolbar()
            .environment(estado)
            .environment(sessao)
            .environment(ThemeManager())

        for largura in [CGFloat(1100), CGFloat(1280), CGFloat(1320), CGFloat(1399)] {
            let renderer = ImageRenderer(content: toolbar.frame(width: largura, height: 52))
            XCTAssertNotNil(renderer.nsImage, "Falha ao renderizar toolbar compacta na largura \(largura)")
        }
    }
}
