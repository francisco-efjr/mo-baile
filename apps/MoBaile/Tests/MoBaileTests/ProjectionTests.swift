import XCTest
@testable import MoBaile

/// Projecao entre o ponto clicado na janela e a coordenada no aparelho.
///
/// Esta era a origem de um erro silencioso: a conversao usava 1080x1920 fixo.
/// Em qualquer aparelho fora dessa proporcao, a caixa de selecao aparecia
/// deslocada e o toque repassado caia no lugar errado. Como nada quebrava, o
/// sintoma parecia "o espelho esta impreciso".
final class ProjectionTests: XCTestCase {

    func testCentroDaTelaMapeiaParaCentroDoAparelho() {
        let projection = Projection(
            viewport: CGSize(width: 400, height: 800),
            device: CGSize(width: 1080, height: 2160)
        )
        let center = projection.toDevice(CGPoint(x: 200, y: 400))
        XCTAssertEqual(center.x, 540, accuracy: 1)
        XCTAssertEqual(center.y, 1080, accuracy: 1)
    }

    func testLetterboxHorizontalEDescontado() {
        // Janela mais larga que a proporcao do aparelho: sobra faixa dos dois lados.
        let projection = Projection(
            viewport: CGSize(width: 800, height: 800),
            device: CGSize(width: 1080, height: 2160)
        )
        XCTAssertEqual(projection.scale, 800.0 / 2160.0, accuracy: 0.0001)
        XCTAssertGreaterThan(projection.offset.x, 0, "deve haver faixa lateral")
        XCTAssertEqual(projection.offset.y, 0, accuracy: 0.001)

        // O centro visual continua sendo o centro do aparelho.
        let center = projection.toDevice(CGPoint(x: 400, y: 400))
        XCTAssertEqual(center.x, 540, accuracy: 1)
        XCTAssertEqual(center.y, 1080, accuracy: 1)
    }

    func testProporcoesDiferentesNaoDeslocamOverlay() {
        // Aparelhos reais: 18:9, 19.5:9 e um simulador iPhone.
        for device in [CGSize(width: 1080, height: 2160),
                       CGSize(width: 1080, height: 2400),
                       CGSize(width: 1170, height: 2532)] {
            let projection = Projection(viewport: CGSize(width: 360, height: 760), device: device)
            let elementRect = CGRect(x: 0, y: 0, width: device.width, height: device.height)
            let viewRect = projection.toView(elementRect)

            // Um elemento do tamanho da tela tem que cobrir exatamente a area
            // util, sem sobrar nem estourar.
            XCTAssertEqual(viewRect.minX, projection.offset.x, accuracy: 0.5)
            XCTAssertEqual(viewRect.minY, projection.offset.y, accuracy: 0.5)
            XCTAssertLessThanOrEqual(viewRect.width, 360.5)
            XCTAssertLessThanOrEqual(viewRect.height, 760.5)
        }
    }

    func testIdaEVoltaDeCoordenada() {
        let projection = Projection(viewport: CGSize(width: 384, height: 800), device: CGSize(width: 1080, height: 2400))
        let deviceRect = CGRect(x: 100, y: 400, width: 300, height: 120)
        let viewRect = projection.toView(deviceRect)
        let backToDevice = projection.toDevice(CGPoint(x: viewRect.midX, y: viewRect.midY))
        XCTAssertEqual(backToDevice.x, deviceRect.midX, accuracy: 2)
        XCTAssertEqual(backToDevice.y, deviceRect.midY, accuracy: 2)
    }

    func testCliqueForaDaAreaUtilEGrampeadoNaTela() {
        let projection = Projection(viewport: CGSize(width: 800, height: 800), device: CGSize(width: 1080, height: 2160))
        // Clique na faixa preta a esquerda nao pode virar coordenada negativa.
        let point = projection.toDevice(CGPoint(x: 0, y: 400))
        XCTAssertGreaterThanOrEqual(point.x, 0)
        XCTAssertLessThanOrEqual(point.x, 1080)
    }

    func testDimensaoZeroNaoDivideePorZero() {
        let projection = Projection(viewport: CGSize(width: 300, height: 600), device: .zero)
        XCTAssertTrue(projection.scale.isFinite)
        XCTAssertTrue(projection.toDevice(CGPoint(x: 10, y: 10)).x.isFinite)
    }
}
