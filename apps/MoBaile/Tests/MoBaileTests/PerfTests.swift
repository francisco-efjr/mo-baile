import XCTest
@testable import MoBaile

/// Trilha de desempenho (PERF-1 a PERF-5): janela oculta, sinais do Mac,
/// perfil vindo do motor e o freio local da parte visual.
@MainActor
final class PerfTests: XCTestCase {

    private func sessao() throws -> (AppState, FakeEngine, EngineSession) {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        return (estado, motor, EngineSession(state: estado, client: motor))
    }

    // MARK: - PERF-1: janela oculta

    func testJanelaOcultaPausaOEspelhoEVoltarRetoma() async throws {
        let (_, motor, sessao) = try sessao()

        await sessao.setWindowVisible(false, pauseDelayNanoseconds: 0)
        var chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.filter { $0 == "stream.pause" }.count, 1, "\(chamadas)")

        await sessao.setWindowVisible(true)
        chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.last, "stream.resume", "\(chamadas)")
    }

    func testAlternarRapidoNaoPausa() async throws {
        let (_, motor, sessao) = try sessao()

        let oculta = Task { await sessao.setWindowVisible(false, pauseDelayNanoseconds: 2_000_000_000) }
        await Task.yield()
        await sessao.setWindowVisible(true)
        await oculta.value

        let chamadas = await motor.chamadas
        XCTAssertFalse(chamadas.contains("stream.pause"), "voltou antes do prazo: nada a pausar. \(chamadas)")
        XCTAssertFalse(chamadas.contains("stream.resume"), "\(chamadas)")
    }

    func testTelaEstavelComJanelaOcultaReleHierarquiaSoAoVoltar() async throws {
        let (_, motor, sessao) = try sessao()
        await sessao.setWindowVisible(false, pauseDelayNanoseconds: 0)

        await sessao.handle(EngineNotification(method: "stream.settled", payload: Data(#"{"params":{}}"#.utf8)))
        try await Task.sleep(nanoseconds: 300_000_000)
        var chamadas = await motor.chamadas
        XCTAssertFalse(chamadas.contains("hierarchy.dump"), "janela oculta não relê a árvore: \(chamadas)")

        await sessao.setWindowVisible(true)
        try await Task.sleep(nanoseconds: 300_000_000)
        chamadas = await motor.chamadas
        XCTAssertTrue(chamadas.contains("hierarchy.dump"), "ao voltar, relê a árvore que ficou para trás: \(chamadas)")
    }

    // MARK: - PERF-4: sinais do Mac e perfil do motor

    override func tearDown() {
        Motion.perfReduced = false
        UserDefaults.standard.removeObject(forKey: PerfPreference.storageKey)
        super.tearDown()
    }

    func testSinaisVaoAoMotorEOPerfilVoltaParaOEstado() async throws {
        let (estado, motor, sessao) = try sessao()

        await sessao.sendPerfSignals()

        let enviados = await motor.parametros(de: "perf.signals")
        let params = try XCTUnwrap(enviados)
        for chave in ["thermal", "low_power", "memory_pressure", "physical_memory_gb", "arch", "translated"] {
            XCTAssertNotNil(params[chave], "falta \(chave) em perf.signals")
        }
        // A fixture responde com o leve por Mac quente.
        XCTAssertEqual(estado.perf.profile, "leve")
        XCTAssertEqual(estado.perf.reasonText, "Mac quente")
        XCTAssertTrue(estado.perf.reducesGlass)
        XCTAssertTrue(Motion.perfReduced, "no leve as molas viram crossfade")
    }

    func testMotorSemRespostaLigaOFreioLocalVisual() async throws {
        let estado = AppState()
        let motor = FakeEngine(
            respostas: try resultadosDasFixtures(),
            erros: ["perf.signals": .timeout(method: "perf.signals", seconds: 5)]
        )
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.sendPerfSignals()

        XCTAssertTrue(estado.perf.semMotor)
        XCTAssertTrue(estado.perf.reducesGlass)
        XCTAssertEqual(estado.perf.badge, "leve")
        XCTAssertEqual(estado.perf.profile, "completo", "o Swift não decide perfil: só a parte visual")
    }

    func testNotificacaoDePerfilAtualizaOEstado() async throws {
        let (estado, _, sessao) = try sessao()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine_payloads", withExtension: "json"))
        let raiz = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let aviso = try JSONSerialization.data(withJSONObject: try XCTUnwrap(raiz["notif_perf.profile"]))

        await sessao.handle(EngineNotification(method: "perf.profile", payload: aviso))

        XCTAssertEqual(estado.perf.badge, "leve")
        XCTAssertEqual(estado.perf.summary, "modo leve: Mac quente")
    }

    func testPreferenciaVaiAoMotorEFicaGuardada() async throws {
        let (estado, motor, sessao) = try sessao()

        await sessao.setPerfPreference(.leve)

        let enviados = await motor.parametros(de: "perf.set_preference")
        XCTAssertEqual(enviados?["preference"], .string("leve"))
        XCTAssertEqual(estado.perf.preference, .leve)
        XCTAssertEqual(PerfPreference.stored, .leve)
    }

    func testEspelhoSemParametrosFixosSegueOPerfil() async throws {
        let estado = AppState()
        estado.selectedDevice = "emulator-5554"
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.startStream()

        let enviados = await motor.parametros(de: "stream.start")
        XCTAssertEqual(enviados, [:], "fps e largura saem do perfil do motor")
    }

    func testBadgeSoForaDoCompleto() {
        var perf = PerfState()
        XCTAssertNil(perf.badge)
        perf.profile = "equilibrado"
        perf.reason = "low_power"
        XCTAssertEqual(perf.summary, "modo equilibrado: Economia de Energia ligada")
        perf.reason = "manual"
        XCTAssertFalse(perf.isAutomatic)
    }

    func testSinaisDoMacTemNomesDoContrato() {
        let sinais = PerfSensors().current
        XCTAssertTrue(["nominal", "fair", "serious", "critical"].contains(sinais.thermal))
        XCTAssertGreaterThan(sinais.physicalMemoryGB, 0)
        XCTAssertEqual(PerfSignals.thermalName(.serious), "serious")
    }
}
