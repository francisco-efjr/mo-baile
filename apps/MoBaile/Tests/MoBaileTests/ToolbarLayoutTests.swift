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
}
