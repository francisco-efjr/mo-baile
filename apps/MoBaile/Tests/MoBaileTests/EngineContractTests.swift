import XCTest
@testable import MoBaile

/// Verifica que o front decodifica exatamente o que o motor Python produz.
///
/// As fixtures em `Fixtures/engine_payloads.json` nao foram escritas a mao:
/// sao a saida real do motor, gerada pelo mesmo codigo que roda em producao.
/// Isso transforma o par de linguagens num contrato verificavel: se alguem
/// renomear um campo do lado Python, a suite Swift quebra na hora, em vez de a
/// tela aparecer vazia em tempo de execucao.
///
/// Para regerar apos mudar o contrato:
///   make fixtures
final class EngineContractTests: XCTestCase {

    // MARK: - Carregamento das fixtures

    private static var payloads: [String: Data] = [:]

    override class func setUp() {
        super.setUp()
        guard let url = Bundle.module.url(forResource: "engine_payloads", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("fixture engine_payloads.json nao encontrada no bundle de teste")
            return
        }
        for (key, value) in root {
            payloads[key] = try? JSONSerialization.data(withJSONObject: value)
        }
    }

    private func payload(_ name: String) throws -> Data {
        try XCTUnwrap(Self.payloads[name], "fixture ausente: \(name)")
    }

    /// Decodifica o campo `result` da resposta JSON-RPC.
    private func decodeResult<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(EngineTestResultEnvelope<T>.self, from: payload(name)).result
    }
}

private struct EngineTestResultEnvelope<R: Decodable>: Decodable {
    let result: R
}

extension EngineContractTests {

    // MARK: - Diagnostico

    func testEngineInfo() throws {
        let info = try decodeResult("engine.info", as: EngineDTO.EngineInfo.self)
        XCTAssertFalse(info.version.isEmpty)
        XCTAssertEqual(info.platform, "android")
        XCTAssertFalse(info.wdaUrl.isEmpty)
        XCTAssertGreaterThan(info.proxy.port, 0)
        XCTAssertTrue(info.methods.contains("hierarchy.dump"))
    }

    func testSessionState() throws {
        let session = try decodeResult("session.select_device", as: EngineDTO.SessionState.self)
        XCTAssertEqual(session.platform, "android")
        XCTAssertEqual(session.deviceId, "emulator-5554")
    }

    func testDeviceList() throws {
        let list = try decodeResult("devices.list", as: EngineDTO.DeviceList.self)
        XCTAssertNotNil(list.devices)
    }

    // MARK: - Hierarquia

    func testHierarchyDumpMapeiaParaModeloDaInterface() throws {
        let dump = try decodeResult("hierarchy.dump", as: EngineDTO.HierarchyDump.self)
        XCTAssertEqual(dump.count, 1)

        let element = try XCTUnwrap(dump.elements.first).toModel()
        XCTAssertEqual(element.className, "android.widget.Button")
        XCTAssertEqual(element.resourceId, "br.app:id/btn_ok")
        XCTAssertEqual(element.text, "Continuar")
        XCTAssertTrue(element.clickable)
        XCTAssertEqual(element.platform, .android)
        // bounds [10,20][110,70] -> origem (10,20), tamanho 100x50
        XCTAssertEqual(element.bounds, CGRect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertEqual(element.center, CGPoint(x: 60, y: 45))
        XCTAssertEqual(element.chipType, .button)
    }

    func testElementAt() throws {
        let lookup = try decodeResult("hierarchy.element_at", as: EngineDTO.ElementLookup.self)
        let element = try XCTUnwrap(lookup.element)
        XCTAssertEqual(element.resourceId, "br.app:id/btn_ok")
    }

    // MARK: - Tela

    func testScreenCapture() throws {
        let frame = try decodeResult("screen.capture", as: EngineDTO.Frame.self)
        XCTAssertEqual(frame.width, 30)
        XCTAssertEqual(frame.sourceWidth, 60)
        XCTAssertNotNil(frame.image, "base64 do motor precisa virar NSImage")
    }

    func testScreenSize() throws {
        let size = try decodeResult("screen.size", as: EngineDTO.ScreenSize.self)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 2400)
    }

    func testStreamStatsComStreamParado() throws {
        let stats = try decodeResult("stream.stats", as: EngineDTO.StreamStats.self)
        XCTAssertFalse(stats.running)
        XCTAssertNil(stats.framesCaptured, "campos opcionais nao podem exigir presenca")
    }

    // MARK: - Geracao de codigo

    func testRecordedStep() throws {
        let recorded = try decodeResult("codegen.record", as: EngineDTO.RecordedStep.self)
        XCTAssertEqual(recorded.varName, "BOTAO_CONTINUAR")
        XCTAssertFalse(recorded.objectCode.isEmpty)
        XCTAssertFalse(recorded.actionCode.isEmpty)
        XCTAssertEqual(recorded.stepCount, 1)
    }

    func testStepsMapeiamEstrategia() throws {
        let list = try decodeResult("codegen.steps", as: EngineDTO.StepList.self)
        let step = try XCTUnwrap(list.steps.first)
        // O motor chama de "position"; a interface, de "coords".
        XCTAssertEqual(step.strategy, "position")
        XCTAssertEqual(step.mappedStrategy, .coords)

        let model = step.toModel()
        XCTAssertEqual(model.stepNum, 1)
        XCTAssertEqual(model.varName, "BOTAO_CONTINUAR")
        XCTAssertEqual(model.coords, CGPoint(x: 60, y: 45))
        XCTAssertEqual(model.platform, .android)
    }

    // MARK: - Erros

    func testErroDeDominioTrazCodigoEstavel() throws {
        struct ErrorEnvelope: Decodable {
            struct Body: Decodable {
                struct Detail: Decodable { let code: String; let message: String }
                let code: Int
                let message: String
                let data: Detail?
            }
            let error: Body
        }
        let envelope = try JSONDecoder().decode(ErrorEnvelope.self, from: payload("erro_dominio"))
        XCTAssertEqual(envelope.error.code, -32000)
        XCTAssertEqual(envelope.error.data?.code, "invalid_input")
    }

    // MARK: - Notificacoes

    func testNotificacaoDeTrafegoMapeiaParaNetworkEvent() throws {
        struct Envelope: Decodable { let params: EngineDTO.NetworkEventPayload }
        let event = try JSONDecoder()
            .decode(Envelope.self, from: payload("notif_proxy.event")).params.toModel()

        XCTAssertEqual(event.id, 7)
        XCTAssertEqual(event.method, "POST")
        XCTAssertEqual(event.statusCode, 200)
        XCTAssertEqual(event.host, "api.exemplo.com.br")
        XCTAssertEqual(event.durationMs, 183, "duracao em ponto flutuante vira inteiro arredondado")
        XCTAssertEqual(event.protocol, "HTTP/1.1")
        XCTAssertFalse(event.isTunnel)
        // A credencial ja chega redigida do motor: a interface nunca recebe o token.
        let auth = try XCTUnwrap(event.requestHeaders["Authorization"])
        XCTAssertTrue(auth.contains("redigido"))
    }

    func testNotificacaoDeAnalyticsAchataParametrosDeTipoLivre() throws {
        struct Envelope: Decodable { let params: EngineDTO.AnalyticsEventPayload }
        let event = try JSONDecoder()
            .decode(Envelope.self, from: payload("notif_analytics.event")).params.toModel()

        XCTAssertEqual(event.eventName, "screen_view")
        XCTAssertEqual(event.tag, "FA")
        XCTAssertEqual(event.platform, .android)
        // Parametro chega com string, numero e booleano no mesmo dicionario.
        XCTAssertEqual(event.params["screen_name"], "onboarding_credito")
        XCTAssertEqual(event.params["step"], "2")
        XCTAssertEqual(event.params["first_open"], "true")
    }
}

// MARK: - Ambiente e inicializacao

/// Os DTOs de ambiente (`Diagnostics`, `Simulator`, `WDAStatus` e companhia)
/// foram escritos e compilados sem que nenhuma fixture os cobrisse: o gerador
/// nao chamava `diagnostics.check`, `simulators.*`, `emulators.*` nem `wda.*`.
/// Compilar so provava que o Swift era valido, nao que ele casava com o motor.
/// Um campo renomeado do lado Python passaria pelo CI e apareceria como cartao
/// de diagnostico vazio em execucao, que e exatamente o que as fixtures
/// existem para impedir.
extension EngineContractTests {

    func testDiagnosticsCheckTrazAsDuasPlataformas() throws {
        let diag = try decodeResult("diagnostics.check", as: EngineDTO.Diagnostics.self)

        XCTAssertEqual(diag.ios.platform, "ios")
        XCTAssertEqual(diag.android.platform, "android")
        XCTAssertFalse(diag.ios.title.isEmpty)
        XCTAssertFalse(diag.ios.checks.isEmpty)
        XCTAssertFalse(diag.android.checks.isEmpty)

        XCTAssertEqual(diag.forPlatform(.ios).platform, "ios")
        XCTAssertEqual(diag.forPlatform(.android).platform, "android")
    }

    func testChecagemCarregaDetalheEAcaoQueResolve() throws {
        let diag = try decodeResult("diagnostics.check", as: EngineDTO.Diagnostics.self)

        // Cada linha diz o que fazer: um X vermelho sozinho manda a pessoa
        // procurar o problema no lugar errado.
        for check in diag.ios.checks + diag.android.checks {
            XCTAssertFalse(check.label.isEmpty)
            XCTAssertFalse(check.detail.isEmpty, "checagem '\(check.label)' sem detalhe")
        }

        // O motor marca com um identificador de acao a checagem que tem
        // conserto, e o front obedece a isso em vez de reimplementar a decisao.
        let wda = try XCTUnwrap(diag.ios.checks.first { $0.label == "WebDriverAgent" })
        XCTAssertEqual(wda.state, "warn")
        XCTAssertEqual(wda.action, "start_wda")
        XCTAssertEqual(wda.daemonState, .warn)
    }

    /// Regressao: antes, a tela de estado vazio desenhava
    /// `("Dispositivo conectado", .ok)` escrito no codigo, ou seja, mostrava um
    /// visto verde justamente quando nao havia dispositivo nenhum.
    ///
    /// O motor tem cinco estados (`ok`, `busy`, `warn`, `error`, `off`) e o
    /// `switch` do Swift trata quatro: `off` cai no `default`. Esta suite
    /// existe para impedir que alguem "simplifique" esse default para `.ok` e
    /// traga o visto verde falso de volta por baixo.
    func testEstadoDesconhecidoNuncaViraVistoVerde() throws {
        func check(_ state: String) throws -> EngineDTO.Check {
            let json = #"{"label":"L","state":"\#(state)","detail":"d","action":null}"#
            return try JSONDecoder().decode(EngineDTO.Check.self, from: Data(json.utf8))
        }

        XCTAssertEqual(try check("ok").daemonState, .ok)
        XCTAssertEqual(try check("busy").daemonState, .busy)
        XCTAssertEqual(try check("warn").daemonState, .warn)
        XCTAssertEqual(try check("error").daemonState, .error)
        // `off` e emitido pelo motor e nao aparece no switch: cai no default.
        XCTAssertEqual(try check("off").daemonState, .off)
        // Estado que o motor ainda nao emite tem de degradar para o lado
        // seguro, nunca para .ok.
        XCTAssertEqual(try check("estado_que_ainda_nao_existe").daemonState, .off)
    }

    func testSimulatorListSeparaLigadoDeParado() throws {
        let list = try decodeResult("simulators.list", as: EngineDTO.SimulatorList.self)

        XCTAssertEqual(list.simulators.count, 2)
        let ligado = try XCTUnwrap(list.simulators.first { $0.booted })
        XCTAssertEqual(ligado.name, "iPhone 16 Pro")
        XCTAssertEqual(ligado.state, "Booted")
        XCTAssertFalse(ligado.runtime.isEmpty)
        // `id` vem do udid: a lista e usada em ForEach para escolher qual abrir.
        XCTAssertEqual(ligado.id, ligado.udid)
        XCTAssertEqual(list.simulators.filter { !$0.booted }.count, 1)
    }

    func testSimulatorBoot() throws {
        let boot = try decodeResult("simulators.boot", as: EngineDTO.BootResult.self)
        XCTAssertTrue(boot.booted)
        XCTAssertFalse(boot.udid.isEmpty)
        XCTAssertFalse(boot.message.isEmpty)
    }

    func testEmulatorList() throws {
        let list = try decodeResult("emulators.list", as: EngineDTO.AvdList.self)
        XCTAssertEqual(list.avds, ["Pixel_9", "Pixel_9_Pro"])
    }

    func testEmulatorBoot() throws {
        let boot = try decodeResult("emulators.boot", as: EngineDTO.AvdBootResult.self)
        XCTAssertEqual(boot.name, "Pixel_9")
        // O AVD sobe em segundo plano: `starting`, e nao `booted`.
        XCTAssertTrue(boot.starting)
    }

    func testWDAStatusMapeiaSnakeCase() throws {
        let status = try decodeResult("wda.status", as: EngineDTO.WDAStatus.self)
        XCTAssertFalse(status.wdaRunning)
        XCTAssertTrue(status.appiumInstalled)
        XCTAssertFalse(status.appiumRunning)
        XCTAssertFalse(status.appiumUrl.isEmpty)
        XCTAssertFalse(status.wdaUrl.isEmpty)
    }

    func testWDAStart() throws {
        let start = try decodeResult("wda.start", as: EngineDTO.WDAStartResult.self)
        XCTAssertTrue(start.wdaRunning)
        XCTAssertFalse(start.udid.isEmpty)
        XCTAssertFalse(start.message.isEmpty)
    }
}
