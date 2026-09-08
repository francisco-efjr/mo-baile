import XCTest
@testable import MoBaile

/// Motor falso que responde com as fixtures reais e anota o que foi chamado.
///
/// Existe porque a sessão guardava um `EngineClient` concreto criado dentro do
/// próprio `connect()`: não havia como observar quais chamadas ela faz sem
/// subir um processo Python. Foi por isso que o espelho em branco passou por 45
/// testes verdes.
actor FakeEngine: EngineCalling {
    private let respostas: [String: Data]
    private(set) var chamadas: [String] = []

    init(respostas: [String: Data]) {
        self.respostas = respostas
    }

    func call<Response: Decodable>(
        _ method: String,
        params: [String: JSONValue],
        as type: Response.Type
    ) async throws -> Response {
        chamadas.append(method)
        guard let data = respostas[method] else {
            throw EngineError.notRunning
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    func callIgnoringResult(_ method: String, params: [String: JSONValue]) async throws {
        chamadas.append(method)
    }

    func stop() {}
}

@MainActor
final class EngineSessionTests: XCTestCase {

    /// Carrega o campo `result` de cada fixture, que é o que o cliente entrega
    /// aos chamadores depois de descascar o envelope JSON-RPC.
    private func resultadosDasFixtures() throws -> [String: Data] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine_payloads", withExtension: "json"))
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        )
        var saida: [String: Data] = [:]
        for (metodo, envelope) in root {
            guard let envelope = envelope as? [String: Any],
                  let resultado = envelope["result"] else { continue }
            saida[metodo] = try JSONSerialization.data(withJSONObject: resultado)
        }
        return saida
    }

    /// Regressão: selecionar um dispositivo enchia a hierarquia e deixava o
    /// espelho vazio.
    ///
    /// `select(deviceID:)` chamava `screen.size` e `hierarchy.dump`, mas nenhuma
    /// captura. Na tela, o resultado era conectar com a árvore de acessibilidade
    /// completa e uma moldura preta ao lado, até alguém ligar o streaming ou
    /// clicar em "Forçar Captura". Quem abre a ferramenta com aparelho conectado
    /// espera ver a tela.
    func testSelecionarDispositivoPedeUmQuadroInicial() async throws {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.select(deviceID: "emulator-5554")

        let chamadas = await motor.chamadas
        XCTAssertTrue(
            chamadas.contains("screen.capture"),
            "selecionar dispositivo tem de pedir um quadro; chamadas: \(chamadas)"
        )
        XCTAssertNotNil(
            estado.currentFrame,
            "o espelho ficou sem quadro depois de selecionar o dispositivo"
        )
    }

    /// A hierarquia continua sendo carregada: a correção do espelho não pode ter
    /// custado o que já funcionava.
    func testSelecionarDispositivoTambemCarregaHierarquiaETamanho() async throws {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.select(deviceID: "emulator-5554")

        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.first, "session.select_device")
        XCTAssertTrue(chamadas.contains("screen.size"))
        XCTAssertTrue(chamadas.contains("hierarchy.dump"))
        XCTAssertFalse(estado.hierarchyElements.isEmpty)
        XCTAssertEqual(estado.deviceSize, CGSize(width: 1080, height: 2400))
    }

    /// Regressão: quadro do aparelho anterior ficava na tela ao trocar de alvo.
    ///
    /// `select` limpava hierarquia e seleção, mas não o quadro. Trocar de
    /// dispositivo deixava a moldura mostrando a tela do aparelho antigo, o que
    /// é pior que moldura vazia: parece dado atual e não é.
    ///
    /// Aqui o motor falso não sabe responder `screen.capture`, simulando a
    /// captura que falha; mesmo assim o quadro velho não pode sobreviver.
    func testTrocarDeDispositivoNaoDeixaOQuadroAnteriorNaTela() async throws {
        var respostas = try resultadosDasFixtures()
        respostas.removeValue(forKey: "screen.capture")

        let estado = AppState()
        estado.currentFrame = NSImage(size: NSSize(width: 10, height: 10))

        let motor = FakeEngine(respostas: respostas)
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.select(deviceID: "emulator-5554")

        XCTAssertNil(
            estado.currentFrame,
            "o quadro do aparelho anterior continuou na moldura"
        )
    }

    /// Regressão: toque repassado com o espelho ao vivo desligado deixava tela
    /// e hierarquia paradas no estado anterior.
    ///
    /// `tap(at:)` só chamava `input.tap`. Com streaming ligado o
    /// `stream.settled` mandava reler; desligado, ninguém mandava. O efeito
    /// ruim não é o visual: o passo gravado em seguida é resolvido contra a
    /// árvore velha, então o toque navega e a gravação aponta para o elemento
    /// que não está mais na tela.
    func testToqueSemStreamingRelêTelaEHierarquia() async throws {
        let estado = AppState()
        estado.streamActive = false
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.tap(at: CGPoint(x: 60, y: 45))

        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.first, "input.tap")
        XCTAssertTrue(chamadas.contains("screen.capture"), "chamadas: \(chamadas)")
        XCTAssertTrue(chamadas.contains("hierarchy.dump"), "chamadas: \(chamadas)")
    }

    /// Com o espelho ao vivo ligado quem avisa é o `stream.settled`; reler aqui
    /// seria captura e dump repetidos a cada toque.
    func testToqueComStreamingNaoDuplicaLeitura() async throws {
        let estado = AppState()
        estado.streamActive = true
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.tap(at: CGPoint(x: 60, y: 45))

        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas, ["input.tap"])
    }

    /// Regressão: gravar um passo não aparecia em lugar nenhum da tela.
    ///
    /// `codegen.record` já devolvia `object_code` e `action_code`, mas
    /// `actionsCode` e `locatorsCode` do `AppState` nunca eram escritos por
    /// ninguém: nasciam vazios e só eram limpos. Os dois editores da coluna de
    /// workspace ficavam permanentemente em branco, e o ciclo do produto —
    /// clicar no elemento e receber o Page Object — falhava em silêncio.
    func testGravarPassoEscreveNosDoisEditores() async throws {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        XCTAssertTrue(estado.actionsCode.isEmpty)
        XCTAssertTrue(estado.locatorsCode.isEmpty)

        await sessao.record(at: CGPoint(x: 60, y: 45))

        XCTAssertFalse(estado.locatorsCode.isEmpty, "o editor de locators continuou vazio")
        XCTAssertFalse(estado.actionsCode.isEmpty, "o editor de ações continuou vazio")
        // O que o motor gera de verdade, vindo da fixture: um par
        // (locator, ação) por elemento gravado.
        XCTAssertTrue(estado.locatorsCode.contains("AppiumBy"), estado.locatorsCode)
        XCTAssertTrue(estado.actionsCode.contains("def "), estado.actionsCode)
        XCTAssertFalse(estado.steps.isEmpty, "os passos não foram relidos")
    }

    /// Gravar dois passos acumula, e não substitui: o arquivo cresce.
    func testGravacoesSeAcumulamNosEditores() async throws {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.record(at: CGPoint(x: 60, y: 45))
        let depoisDoPrimeiro = estado.locatorsCode.count
        await sessao.record(at: CGPoint(x: 60, y: 45))

        XCTAssertGreaterThan(estado.locatorsCode.count, depoisDoPrimeiro)
    }

    /// Gravar um passo também toca no aparelho.
    ///
    /// Os três modos eram exclusivos, então gravar um fluxo obrigava a alternar
    /// entre "Gravar passo" e "Repassar toque" a cada clique: vinte passos
    /// viravam quarenta trocas de modo. Um fluxo só avança navegando por ele.
    func testGravarPassoTambemTocaNoAparelho() async throws {
        let estado = AppState()
        estado.streamActive = true   // evita a releitura extra do modo sem streaming
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.record(at: CGPoint(x: 60, y: 45))

        let chamadas = await motor.chamadas
        XCTAssertTrue(chamadas.contains("codegen.record"), "chamadas: \(chamadas)")
        XCTAssertTrue(chamadas.contains("input.tap"), "gravou sem tocar: \(chamadas)")
        // A ordem importa: o elemento é resolvido contra a tela atual, e só
        // depois o toque leva para a próxima.
        let posRecord = chamadas.firstIndex(of: "codegen.record")!
        let posTap = chamadas.firstIndex(of: "input.tap")!
        XCTAssertLessThan(posRecord, posTap, "o toque veio antes da gravação")
    }

    /// Selecionar um aparelho já liga o espelho ao vivo: o interruptor saiu da
    /// barra, então isso não pode depender de o usuário descobrir uma opção.
    func testSelecionarDispositivoLigaOEspelhoAoVivo() async throws {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        await sessao.select(deviceID: "emulator-5554")

        let chamadas = await motor.chamadas
        XCTAssertTrue(chamadas.contains("stream.start"), "chamadas: \(chamadas)")
        XCTAssertTrue(estado.streamActive)
    }

    /// Regressão: aparelho que chega pelo detector recebia um quadro só e o
    /// espelho congelava nele.
    ///
    /// Havia dois caminhos até um alvo ficar pronto — escolher no menu e o
    /// aparelho aparecer sozinho — e só o primeiro ligava o espelho ao vivo.
    /// Pelo segundo, que é o caminho comum de quem pluga o aparelho, a moldura
    /// mostrava a tela de minutos atrás e só saía disso no botão "Atualizar".
    ///
    /// Medido no aparelho: o motor não fazia nenhuma captura, zero processos de
    /// `screencap` em 6 s, porque `stream.start` nunca tinha sido pedido.
    func testAparelhoQueChegaPeloDetectorLigaOEspelhoAoVivo() async throws {
        let estado = AppState()
        let motor = FakeEngine(respostas: try resultadosDasFixtures())
        let sessao = EngineSession(state: estado, client: motor)

        let aviso = EngineNotification(
            method: "device.changed",
            payload: Data(#"{"params":{"platform":"android","device_id":"emulator-5554"}}"#.utf8)
        )
        await sessao.handle(aviso)

        let chamadas = await motor.chamadas
        XCTAssertTrue(chamadas.contains("stream.start"), "o espelho não foi ligado: \(chamadas)")
        XCTAssertTrue(estado.streamActive)
    }

    /// Os dois caminhos têm de fazer a mesma coisa. Foi a divergência entre eles
    /// que deixou o espelho parado por um caminho e vivo pelo outro.
    func testOsDoisCaminhosDeixamOAlvoNoMesmoEstado() async throws {
        let porMenu = AppState()
        let motorMenu = FakeEngine(respostas: try resultadosDasFixtures())
        await EngineSession(state: porMenu, client: motorMenu).select(deviceID: "emulator-5554")

        let porDetector = AppState()
        let motorDetector = FakeEngine(respostas: try resultadosDasFixtures())
        await EngineSession(state: porDetector, client: motorDetector).handle(
            EngineNotification(
                method: "device.changed",
                payload: Data(#"{"params":{"platform":"android","device_id":"emulator-5554"}}"#.utf8)
            )
        )

        let esperadas = ["screen.size", "screen.capture", "hierarchy.dump", "stream.start"]
        let doMenu = await motorMenu.chamadas
        let doDetector = await motorDetector.chamadas
        for metodo in esperadas {
            XCTAssertTrue(doMenu.contains(metodo), "menu não chamou \(metodo)")
            XCTAssertTrue(doDetector.contains(metodo), "detector não chamou \(metodo)")
        }
        XCTAssertEqual(porMenu.streamActive, porDetector.streamActive)
    }
}
