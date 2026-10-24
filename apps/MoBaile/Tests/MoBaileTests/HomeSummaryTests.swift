import XCTest
@testable import MoBaile

/// Início 2.0 e Ambiente (3.11.0): contrato de `home.summary`, textos da tela
/// e a seção Ambiente na navegação. A decisão (estado, pendências, alvos) é
/// do motor; aqui se confere que o front lê e diz certo.
@MainActor
final class HomeSummaryTests: XCTestCase {

    private func resumoDaFixture() throws -> EngineDTO.HomeSummary {
        let dados = try XCTUnwrap(try resultadosDasFixtures()["home.summary"])
        return try JSONDecoder().decode(EngineDTO.HomeSummary.self, from: dados)
    }

    // MARK: - Contrato

    func testResumoDecodificaEstadoAmbienteAlvosRecentesENovidades() throws {
        let resumo = try resumoDaFixture()
        XCTAssertFalse(resumo.isFirstRun)
        XCTAssertEqual(resumo.environment.ready, 3)
        XCTAssertEqual(resumo.environment.total, 4)
        let appium = try XCTUnwrap(resumo.pending("appium"))
        XCTAssertEqual(appium.install, "appium")
        XCTAssertEqual(appium.blocks.first?.area, "page_objects")
        XCTAssertEqual(appium.blocks.first?.platform, "ios")
        XCTAssertEqual(resumo.suggestedPlatform, "android")
        XCTAssertEqual(Set(resumo.targets.map(\.kind)), ["simulator", "emulator"])
        let iphone = try XCTUnwrap(resumo.targets.first { $0.platform == "ios" })
        XCTAssertEqual(iphone.blockedBy, ["appium"])
        XCTAssertTrue(iphone.capabilities.mirror)
        XCTAssertFalse(iphone.capabilities.tap)
        XCTAssertEqual(resumo.recent.first?.kind, "report")
        XCTAssertEqual(resumo.whatsNew?.items, ["Tela Início nova", "Tela Ambiente"])
    }

    // MARK: - Textos

    func testCapsulaESubtituloDoAmbiente() throws {
        let resumo = try resumoDaFixture()
        XCTAssertEqual(HomeCopy.environmentPill(resumo.environment), "Ambiente: 3 de 4 prontos")
        XCTAssertEqual(HomeCopy.environmentPill(.init(ready: 4, total: 4, pending: [])), "Ambiente pronto")
        XCTAssertEqual(HomeCopy.homeSubtitle(resumo, engineRunning: true), "Ambiente: 3 de 4 prontos")
        XCTAssertEqual(HomeCopy.homeSubtitle(nil, engineRunning: false), "Motor parado")
        XCTAssertEqual(HomeCopy.homeSubtitle(nil, engineRunning: true), "Conferindo…")
    }

    func testSaudacaoPelaHoraEPrimeiroNome() {
        func as_(_ hora: Int) -> Date {
            Calendar.current.date(bySettingHour: hora, minute: 0, second: 0, of: Date())!
        }
        XCTAssertEqual(HomeCopy.greeting(at: as_(9), fullName: "Francisco Junior"), "Bom dia, Francisco")
        XCTAssertEqual(HomeCopy.greeting(at: as_(14), fullName: "Ana"), "Boa tarde, Ana")
        XCTAssertEqual(HomeCopy.greeting(at: as_(20), fullName: "Ana"), "Boa noite, Ana")
        XCTAssertEqual(HomeCopy.greeting(at: as_(11), fullName: ""), "Bom dia")
    }

    func testDataRelativaDosRecentes() {
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let agora = calendario.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))!
        let hoje = calendario.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9, minute: 40))!
        let ontem = calendario.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 18))!
        let semana = calendario.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 10))!
        let antigo = calendario.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 10))!
        XCTAssertTrue(HomeCopy.relativeDate(hoje, now: agora, calendar: calendario).hasPrefix("hoje "))
        XCTAssertEqual(HomeCopy.relativeDate(ontem, now: agora, calendar: calendario), "ontem")
        XCTAssertFalse(HomeCopy.relativeDate(semana, now: agora, calendar: calendario).contains("/"))
        XCTAssertTrue(HomeCopy.relativeDate(antigo, now: agora, calendar: calendario).contains("/"))
    }

    func testAlvoDizOQueEEOQueLimita() throws {
        let resumo = try resumoDaFixture()
        let iphone = try XCTUnwrap(resumo.targets.first { $0.platform == "ios" })
        XCTAssertTrue(HomeCopy.targetDetail(iphone).hasPrefix("Simulador iOS · "))
        XCTAssertFalse(HomeCopy.targetDetail(iphone).contains("tudo pronto"))
        let limite = HomeCopy.limitation(iphone, pending: try XCTUnwrap(resumo.pending("appium")))
        XCTAssertTrue(limite.hasPrefix("Só espelho: falta Appium com o driver XCUITest"), limite)

        let pixel = try XCTUnwrap(resumo.targets.first { $0.platform == "android" })
        XCTAssertTrue(HomeCopy.targetDetail(pixel).hasSuffix("tudo pronto"))
        XCTAssertEqual(HomeCopy.targetAction(pixel), pixel.running ? "Usar Este" : "Iniciar Emulador")
    }

    // MARK: - Navegação

    func testAmbienteNoRodapeComAtalhoCincoESemInspector() {
        XCTAssertEqual(WorkspaceTab.environment.displayName, "Ambiente")
        XCTAssertEqual(WorkspaceTab.environment.shortcutDigit, "5")
        XCTAssertFalse(WorkspaceTab.workspaceAreas.contains(.environment))
        XCTAssertFalse(WorkspaceTab.environment.needsDevice)
        let estado = AppState()
        estado.workspaceTab = .environment
        XCTAssertTrue(estado.inspectorSuppressed)
    }

    func testAtalhoDoAmbienteNaoBateComOsDosAjustes() {
        let comandos = CommandRegistry.commands(in: CommandContext())
        let ambiente = comandos.first { $0.id == .area(.environment) }?.shortcut
        let ajustes = comandos.first { $0.id == .settings }?.shortcut
        XCTAssertEqual(ambiente?.key, "5")
        XCTAssertEqual(ajustes?.key, ",", "⌘, continua nos Ajustes")
        let comCinco = comandos.filter { $0.shortcut?.key == "5" && $0.shortcut?.modifiers == .command }
        XCTAssertEqual(comCinco.map(\.id), [.area(.environment)])
    }

    // MARK: - Sessão

    func testConferirOAmbienteTambemRelêOInicio() async throws {
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: AppState(), client: motor)
        await sessao.refreshSetup()
        let chamadas = await motor.chamadas
        XCTAssertTrue(chamadas.contains("home.summary"))
        XCTAssertEqual(sessao.home?.environment.total, 4)
    }
}
