import XCTest
import SwiftUI
@testable import MoBaile

/// Renderiza as telas fora da janela, para poder olhar o layout.
///
/// Não é suíte de asserção: é ferramenta de inspeção. `ImageRenderer` desenha
/// a View sem precisar de janela nem de permissão de tela, o que é a única
/// forma de ver o resultado quando o ambiente não dá acesso ao display.
///
/// Roda só quando MOBAILE_SNAPSHOT_DIR está definido, para não gerar PNG em CI.
@MainActor
final class LayoutSnapshotTests: XCTestCase {

    private func ambiente() -> (AppState, EngineSession, ThemeManager) {
        let estado = AppState()
        estado.statusMessage = "Dispositivo conectado"
        estado.selectedDevice = "7303D258"
        estado.availableDevices = [(id: "7303D258", name: "iPhone 16")]
        estado.platform = .ios
        estado.deviceSize = CGSize(width: 1179, height: 2556)
        estado.hierarchyElements = []
        let motor = FakeEngine(respostas: [:])
        return (estado, EngineSession(state: estado, client: motor), ThemeManager())
    }

    private func desenhar<V: View>(_ view: V, largura: CGFloat, altura: CGFloat, nome: String) throws {
        guard let destino = ProcessInfo.processInfo.environment["MOBAILE_SNAPSHOT_DIR"] else {
            throw XCTSkip("defina MOBAILE_SNAPSHOT_DIR para gerar os PNGs")
        }
        let renderer = ImageRenderer(content: view.frame(width: largura, height: altura))
        renderer.scale = 2
        let imagem = try XCTUnwrap(renderer.nsImage, "ImageRenderer nao produziu imagem")
        let tiff = try XCTUnwrap(imagem.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: destino).appendingPathComponent("\(nome).png"))
    }

    /// Barra, resumo e inspector do Relatório (a tabela é do AppKit e não sai
    /// no `ImageRenderer`; a janela inteira fica em `WindowSnapshotTests`).
    func testDesenhaPartesDoRelatorio() throws {
        let (estado, sessao, tema) = ambiente()
        let dados = try XCTUnwrap(try resultadosDasFixtures()["report.audit"])
        let relatorio = try JSONDecoder().decode(EngineDTO.ReportAuditPayload.self, from: dados).toModel()
        estado.workspaceTab = .report
        estado.reportSpec = relatorio.spec
        estado.report = relatorio
        estado.reportLogSource = .file(URL(fileURLWithPath: "/Users/qa/Documents/log_obtido_android_investimentos.json"))
        estado.selectedReportResultID = relatorio.results.first { $0.cardIndex == 0 }?.id
        try desenhar(
            VStack(spacing: 0) {
                ReportToolbar()
                ReportSummaryBar(report: relatorio)
            }
            .environment(estado).environment(sessao).environment(tema),
            largura: 1040, altura: 150, nome: "relatorio-barra"
        )
        try desenhar(
            ReportCardInspector().environment(estado).environment(sessao).environment(tema),
            largura: 280, altura: 420, nome: "relatorio-inspector"
        )
    }

    func testDesenhaJanelaInteira() throws {
        let (estado, sessao, tema) = ambiente()
        try desenhar(
            ContentView().environment(estado).environment(sessao).environment(tema),
            largura: 1440, altura: 900, nome: "janela-1440"
        )
    }

    func testDesenhaJanelaNoMinimo() throws {
        let (estado, sessao, tema) = ambiente()
        try desenhar(
            ContentView().environment(estado).environment(sessao).environment(tema),
            largura: 980, altura: 600, nome: "janela-980-minimo"
        )
    }



    /// A coluna do espelho, para conferir a moldura responsiva e o botão que
    /// substituiu o dock de quatro botões inertes. A janela inteira, com
    /// toolbar e inspector, está em `WindowSnapshotTests`.
    func testDesenhaColunaDoEspelho() throws {
        let (estado, sessao, tema) = ambiente()
        try desenhar(
            MirrorColumn().environment(estado).environment(sessao).environment(tema),
            largura: 400, altura: 780, nome: "coluna-espelho"
        )
    }

    func testDesenhaWorkspace() throws {
        let (estado, sessao, tema) = ambiente()
        estado.actionsCode = """
        # Page Object gerado
        def click_botao_continuar(self):
            self.click(self.locators['onboarding'].BOTAO_CONTINUAR)

        def preencher_campo_cpf(self, texto):
            self.send_keys(self.locators['onboarding'].CAMPO_CPF, texto)
        """
        estado.locatorsCode = """
        BOTAO_CONTINUAR = (AppiumBy.ID, "br.app:id/btn_ok")
        CAMPO_CPF = (AppiumBy.ACCESSIBILITY_ID, "cpf-field")
        """
        try desenhar(
            WorkspaceColumn().environment(estado).environment(sessao).environment(tema),
            largura: 440, altura: 950, nome: "workspace"
        )
    }


}
