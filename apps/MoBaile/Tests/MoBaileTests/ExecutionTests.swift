import XCTest
import AppKit
@testable import MoBaile

/// Aba Execução (B1, 3.23.0): DTOs das fixtures reais do motor, console com
/// teto, banner do resultado, trava do Rodar, fluxo de confiança e atalhos.
@MainActor
final class ExecutionTests: XCTestCase {

    // MARK: - Apoio

    private func fixtures() throws -> [String: Data] { try resultadosDasFixtures() }

    private func decode<T: Decodable>(_ nome: String, as tipo: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: try XCTUnwrap(try fixtures()[nome], "fixture ausente: \(nome)"))
    }

    /// Envelope inteiro de uma fixture (notificações e erros não têm `result`).
    private func envelope(_ nome: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine_payloads", withExtension: "json"))
        let raiz = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(raiz[nome] as? [String: Any], "fixture ausente: \(nome)")
    }

    private func notificacao(_ nome: String) throws -> EngineNotification {
        let env = try envelope(nome)
        return EngineNotification(method: try XCTUnwrap(env["method"] as? String),
                                  payload: try JSONSerialization.data(withJSONObject: env))
    }

    private func notificacao(_ metodo: String, _ params: String) -> EngineNotification {
        EngineNotification(method: metodo, payload: Data(#"{"jsonrpc":"2.0","method":"\#(metodo)","params":\#(params)}"#.utf8))
    }

    private func novaSessao() throws -> (AppState, EngineSession, FakeEngine) {
        let estado = AppState()
        let motor = FakeEngine(respostas: try fixtures())
        return (estado, EngineSession(state: estado, client: motor), motor)
    }

    /// Sessão com o projeto já lido e um interpretador que existe (a fixture de
    /// `project.configure`), pronta para rodar.
    private func sessaoProntaParaRodar() throws -> (AppState, EngineSession, FakeEngine) {
        let (estado, sessao, motor) = try novaSessao()
        let leitura = try decode("project.configure", as: EngineDTO.ProjectInspection.self)
        estado.execution.select(leitura.project)
        estado.execution.inspection = leitura
        estado.execution.loadedOnce = true
        return (estado, sessao, motor)
    }

    // MARK: - Decodificação das fixtures

    func testProjectOpenEList() throws {
        let aberto = try decode("project.open", as: EngineDTO.ProjectOpened.self).project
        XCTAssertEqual(aberto.id, "0a1b2c3d4e5f")
        XCTAssertEqual(aberto.name, "projeto_exemplo_behave")
        XCTAssertEqual(aberto.entry, "main.py")
        XCTAssertFalse(aberto.trusted)
        XCTAssertNil(aberto.interpreterOverride)
        let lista = try decode("project.list", as: EngineDTO.ProjectList.self)
        XCTAssertEqual(lista.projects.map(\.id), ["0a1b2c3d4e5f"])
        XCTAssertTrue(try decode("project.forget", as: EngineDTO.ProjectForgotten.self).removed)
    }

    func testProjectInspectComOMainResumido() throws {
        let leitura = try decode("project.inspect", as: EngineDTO.ProjectInspection.self)
        XCTAssertEqual(leitura.entry.file, "main.py")
        XCTAssertEqual(leitura.entry.function, "main_sem_args")
        XCTAssertEqual(leitura.interpreter.source, "run_configuration")
        XCTAssertEqual(leitura.interpreter.path, "/Users/qa/Projetos/projeto_exemplo_behave/.venv/bin/python")
        XCTAssertEqual(leitura.runHub, .local)
        XCTAssertEqual(leitura.runConfiguration?.envNames, ["PYTHONUNBUFFERED", "AMBIENTE", "TOKEN_MASSA"])
        XCTAssertEqual(leitura.activeConfig, "config_android_local_HLG")
        XCTAssertEqual(leitura.configs.count, 4)

        let ativa = try XCTUnwrap(leitura.activeConfiguration)
        XCTAssertEqual(ativa.name, "config_android_local_HLG")
        XCTAssertEqual(ativa.hubKind, .local)
        XCTAssertEqual(ativa.orderedValues.first?.key, "platformName")
        XCTAssertEqual(ativa.values["udid"], "emulator-5554")
        // A chave sensível aparece só pelo nome; as de valor e a URL do hub, não.
        XCTAssertTrue(ativa.nameOnlyKeys.contains("senha_usuario_teste"))
        XCTAssertTrue(ativa.nameOnlyKeys.contains("appium:noReset"))
        XCTAssertFalse(ativa.nameOnlyKeys.contains("appium:udid"))
        XCTAssertFalse(ativa.nameOnlyKeys.contains("url"))

        let kobiton = try XCTUnwrap(leitura.configs.first { $0.name == "config_kobiton_android_HLG" })
        XCTAssertFalse(kobiton.active)
        XCTAssertEqual(kobiton.hubKind, .cloud)
        XCTAssertEqual(kobiton.hubKind.label, "Nuvem (bloqueada)")
        XCTAssertTrue(kobiton.nameOnlyKeys.contains("kobiton:accessKey"))

        XCTAssertEqual(leitura.suites.map(\.name), ["test_suite_time_01", "test_suite_time_02", "test_suite_time_03"])
        XCTAssertEqual(leitura.runCount, 3)
        XCTAssertEqual(leitura.missingFeatures, 0)
        let run = try XCTUnwrap(leitura.suites.first?.runs.first)
        XCTAssertEqual(run.squad, "time_01")
        XCTAssertTrue(run.found)
        XCTAssertEqual(run.title, "Navegação básica do app de exemplo")
        XCTAssertEqual(run.scenarios, ["Abrir a home", "Abrir o extrato"])
        XCTAssertEqual(leitura.unusedSuites, ["test_suite_canais"])
        XCTAssertTrue(leitura.problems.isEmpty)
    }

    func testInspectSemInterpretadorTrazCandidatos() throws {
        let leitura = try decode("project.inspect_sem_interpretador", as: EngineDTO.ProjectInspection.self)
        XCTAssertNil(leitura.interpreter.path)
        XCTAssertNil(leitura.interpreter.source)
        XCTAssertNil(leitura.runConfiguration)
        let candidato = try XCTUnwrap(leitura.interpreter.candidates.first)
        XCTAssertEqual(candidato.path, "/usr/local/bin/python3")
        XCTAssertEqual(candidato.version, "3.14.0")
        XCTAssertEqual(candidato.behave, "1.2.6")
    }

    func testConfigureDevolveAEscolhaManual() throws {
        let leitura = try decode("project.configure", as: EngineDTO.ProjectInspection.self)
        XCTAssertEqual(leitura.interpreter.source, "manual")
        XCTAssertTrue(leitura.interpreter.isManual)
        XCTAssertTrue(leitura.interpreter.usable)
        XCTAssertEqual(leitura.project.interpreterOverride, "/Users/qa/.virtualenvs/exemplo/bin/python")
        XCTAssertEqual(ExecutionCopy.interpreterSource(leitura.interpreter.source), "escolhido por você")
    }

    func testDoctor() throws {
        let doctor = try decode("project.doctor", as: EngineDTO.ProjectDoctor.self)
        XCTAssertEqual(doctor.checks.map(\.id), ["interpreter", "packages", "requirements", "pip_check", "appium",
                                                 "appium_port", "device", "app", "uiautomation", "cloud", "features"])
        let s = doctor.summary
        XCTAssertEqual(s.ok + s.warn + s.fail + s.skip, doctor.checks.count, "o resumo conta cada checagem")
        XCTAssertEqual(doctor.ready, s.fail == 0)
        XCTAssertTrue(doctor.checks.allSatisfy { !$0.label.isEmpty && ["ok", "warn", "fail", "skip"].contains($0.state) })
        XCTAssertEqual(ExecutionDoctorCopy.summary(.init(ok: 6, warn: 1, fail: 1, skip: 3)), "6 ok · 1 atenção · 1 falha · 3 puladas")
        XCTAssertEqual(ExecutionDoctorCopy.summary(.init(ok: 2, fail: 2)), "2 ok · 2 falhas")
        XCTAssertEqual(ExecutionDoctorCopy.daemonState("fail"), .error)
        XCTAssertEqual(ExecutionDoctorCopy.daemonState("skip"), .off)
    }

    /// Revisão da B1 (B1-5): projeto ainda não confiável → as checagens que
    /// rodam o Python dele vêm `skip` com `needs_trust`; depois de confiar, não.
    func testDoctorEsperaAConfiancaEProjectTrust() throws {
        let antes = try decode("project.doctor_sem_confianca", as: EngineDTO.ProjectDoctor.self)
        XCTAssertTrue(antes.needsTrust)
        XCTAssertTrue(antes.checks.filter(\.needsTrust).allSatisfy { $0.state == "skip" })
        XCTAssertEqual(antes.checks.first { $0.id == "interpreter" }?.needsTrust, true)
        let depois = try decode("project.doctor_confiavel", as: EngineDTO.ProjectDoctor.self)
        XCTAssertFalse(depois.needsTrust)
        XCTAssertTrue(depois.ready)
        XCTAssertEqual(depois.summary.fail, 0)
        let confiado = try decode("project.trust", as: EngineDTO.ProjectTrusted.self)
        XCTAssertEqual(confiado.project?.trusted, true)
        XCTAssertEqual(confiado.project?.id, "0a1b2c3d4e5f")
        let erro = try XCTUnwrap(try envelope("erro_hub_unknown")["error"] as? [String: Any])
        XCTAssertEqual((erro["data"] as? [String: Any])?["code"] as? String, "hub_unknown")
        XCTAssertNotNil((erro["data"] as? [String: Any])?["message"] as? String)

        let leitura = try decode("project.inspect", as: EngineDTO.ProjectInspection.self)
        XCTAssertEqual(leitura.hubState, "local")
        XCTAssertEqual(leitura.configs.map(\.hubKind), [.local, .local, .cloud, .cloud])
    }

    /// Revisão FR-09: valor de `hub_state` que este front não conhece falha
    /// fechado ("Não confirmado"), nunca "Local".
    func testHubStateDesconhecidoNaoViraLocal() {
        XCTAssertEqual(EngineDTO.HubState(rawValue: "blocked", cloud: false), .unknown)
        XCTAssertEqual(EngineDTO.HubState(rawValue: nil, cloud: false), .local)
        XCTAssertEqual(EngineDTO.HubState(rawValue: "local", cloud: true), .cloud)
        XCTAssertEqual(EngineDTO.HubState(rawValue: "unknown", cloud: false).label, "Não confirmado")
    }

    func testRunStartStopStatus() throws {
        let inicio = try decode("run.start", as: EngineDTO.RunStarted.self)
        XCTAssertEqual(inicio.runId, "20250905-000000-0a1b2c")
        XCTAssertEqual(inicio.deviceId, "emulator-5554")
        XCTAssertEqual(inicio.command?.entry, "main.py")
        XCTAssertEqual(inicio.command?.workingDir, "/Users/qa/Projetos/projeto_exemplo_behave")
        XCTAssertNil(inicio.video?.mode)
        XCTAssertEqual(inicio.startedAt, 1757030000.0)

        let parada = try decode("run.stop", as: EngineDTO.RunStopped.self)
        XCTAssertFalse(parada.running)
        XCTAssertNil(parada.runId)

        let status = try decode("run.status", as: EngineDTO.RunStatus.self)
        XCTAssertFalse(status.running)
        XCTAssertNil(status.run)
        XCTAssertNil(status.last)
    }

    func testNotificacoesDoRun() throws {
        let log = try JSONSerialization.data(withJSONObject: try XCTUnwrap(try envelope("notif_run.log")["params"]))
        let linha = try JSONDecoder().decode(EngineDTO.RunLogLine.self, from: log)
        XCTAssertEqual(linha.line, "  Cenário: Abrir a home")

        let fimDados = try JSONSerialization.data(withJSONObject: try XCTUnwrap(try envelope("notif_run.finished")["params"]))
        let fim = try JSONDecoder().decode(EngineDTO.RunFinished.self, from: fimDados)
        XCTAssertEqual(fim.status, "failed")
        XCTAssertEqual(fim.counts?.scenarios, EngineDTO.RunCountSet(passed: 1, failed: 1))
        XCTAssertEqual(fim.counts?.steps.passed, 5)
        XCTAssertEqual(fim.counts?.summaries, 1)
        XCTAssertEqual(fim.exitCode, 0)
        XCTAssertNil(fim.video)
        XCTAssertEqual(fim.videoWarning, "Sem aparelho alvo: a execução segue sem vídeo.")
        XCTAssertEqual(fim.durationS, 1.2)
    }

    func testErroProjetoNaoConfiavelTemCodigoProprio() throws {
        let erro = try XCTUnwrap(try envelope("erro_project_not_trusted")["error"] as? [String: Any])
        let dados = try XCTUnwrap(erro["data"] as? [String: Any])
        XCTAssertEqual(dados["code"] as? String, "project_not_trusted")
    }

    /// Campos que o protocolo diz opcionais (ou que vieram depois) não podem
    /// derrubar a decodificação; os novos da revisão (`hub_state`,
    /// `needs_trust`) são lidos quando vêm.
    func testToleranteACampoAusenteELeOsCamposDaRevisao() throws {
        let minimo = Data(#"{"project":{"id":"a","root":"/tmp/p"}}"#.utf8)
        let leitura = try JSONDecoder().decode(EngineDTO.ProjectInspection.self, from: minimo)
        XCTAssertEqual(leitura.project.name, "p")
        XCTAssertFalse(leitura.project.trusted)
        XCTAssertFalse(leitura.entry.found)
        XCTAssertFalse(leitura.interpreter.usable)
        XCTAssertTrue(leitura.configs.isEmpty)
        XCTAssertEqual(leitura.runHub, .local)

        let revisao = Data(#"""
        {"project":{"id":"a","root":"/tmp/p"},"hub_state":"unknown","active_config":"c",
         "configs":[{"name":"c","active":true,"hub_state":"unknown","hub":"dinâmico","values":{"udid":7}}]}
        """#.utf8)
        let lida = try JSONDecoder().decode(EngineDTO.ProjectInspection.self, from: revisao)
        XCTAssertEqual(lida.runHub, .unknown)
        XCTAssertEqual(lida.configs.first?.hubKind.label, "Não confirmado")
        XCTAssertEqual(lida.configs.first?.values["udid"], "7", "número literal vira texto")

        let doctor = try JSONDecoder().decode(EngineDTO.ProjectDoctor.self, from: Data(#"""
        {"checks":[{"id":"packages","state":"skip","needs_trust":true},{"id":"appium","state":"ok"}]}
        """#.utf8))
        XCTAssertTrue(doctor.needsTrust)
        XCTAssertEqual(doctor.checks.first?.label, "packages")
        XCTAssertEqual(doctor.summary, EngineDTO.ProjectDoctor.Summary())

        let fim = try JSONDecoder().decode(EngineDTO.RunFinished.self, from: Data(#"{"status":"cancelled"}"#.utf8))
        XCTAssertNil(fim.counts)
        XCTAssertEqual(ExecutionResultSummary(fim).kind, .cancelled)
    }

    // MARK: - Console

    func testConsoleGuardaAsUltimasEContaODescarte() {
        let console = ExecutionConsole(limit: 3)
        XCTAssertNil(console.droppedNotice)
        for i in 1...5 { console.append("linha \(i)") }
        XCTAssertEqual(console.lines, ["linha 3", "linha 4", "linha 5"])
        XCTAssertEqual(console.dropped, 2)
        XCTAssertEqual(console.appended, 5)
        XCTAssertEqual(console.droppedNotice, "2 linhas antigas descartadas")
        console.append("a\nb\r\nc")
        XCTAssertEqual(console.lines.last, "a b c", "uma linha por item")
        XCTAssertEqual(console.droppedNotice, "3 linhas antigas descartadas")

        let geracao = console.generation
        console.clear()
        XCTAssertTrue(console.isEmpty)
        XCTAssertEqual(console.dropped, 0)
        XCTAssertNil(console.droppedNotice)
        XCTAssertEqual(console.generation, geracao + 1)
    }

    func testTetoPadraoDoConsoleE5000() {
        let console = ExecutionConsole()
        XCTAssertEqual(console.limit, 5000)
        for i in 0..<5003 { console.append("\(i)") }
        XCTAssertEqual(console.lines.count, 5000)
        XCTAssertEqual(console.lines.first, "3")
        XCTAssertEqual(console.droppedNotice, "3 linhas antigas descartadas")
    }

    func testCorDasLinhas() {
        XCTAssertEqual(ExecutionConsole.tone(of: "1 feature passed, 0 failed, 0 skipped"), .pass)
        XCTAssertEqual(ExecutionConsole.tone(of: "0 features passed, 1 failed, 0 skipped"), .fail)
        XCTAssertEqual(ExecutionConsole.tone(of: "Traceback (most recent call last):"), .fail)
        XCTAssertEqual(ExecutionConsole.tone(of: "Feature: Navegação"), .normal)
    }

    /// O texto do console acompanha o buffer: só as linhas novas entram no
    /// fim, e as descartadas saem do começo.
    func testTextoDoConsoleSegueOBufferSemReconstruir() throws {
        let console = ExecutionConsole(limit: 4)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let pronto = NSTextView.scrollableTextView()
        scroll.documentView = pronto.documentView
        let coordenador = ExecutionConsoleTextView.Coordinator(following: .constant(true))
        coordenador.scroll = scroll
        let texto = try XCTUnwrap(scroll.documentView as? NSTextView)

        for i in 1...3 { console.append("l\(i)") }
        coordenador.sync(console, following: true)
        XCTAssertEqual(texto.string, "l1\nl2\nl3")

        for i in 4...6 { console.append("l\(i)") }
        coordenador.sync(console, following: true)
        XCTAssertEqual(texto.string, "l3\nl4\nl5\nl6")

        console.clear()
        console.append("nova")
        coordenador.sync(console, following: true)
        XCTAssertEqual(texto.string, "nova")

        XCTAssertEqual(ExecutionConsoleTextView.Coordinator.offset(afterLines: 2, in: "a\nbb\nc" as NSString), 5)
        XCTAssertEqual(ExecutionConsoleTextView.Coordinator.offset(afterLines: 9, in: "a\nb" as NSString), 3)
    }

    // MARK: - Resultado

    func testBannerDoResultado() throws {
        let fimDados = try JSONSerialization.data(withJSONObject: try XCTUnwrap(try envelope("notif_run.finished")["params"]))
        let falhou = ExecutionResultSummary(try JSONDecoder().decode(EngineDTO.RunFinished.self, from: fimDados))
        XCTAssertEqual(falhou.kind, .failed)
        XCTAssertEqual(falhou.title, "Falhou")
        XCTAssertEqual(falhou.counts, ["Features: 0 passaram, 1 falhou", "Cenários: 1 passou, 1 falhou",
                                       "Steps: 5 passaram, 1 falhou"])
        XCTAssertEqual(falhou.duration, "1,2 s")
        XCTAssertEqual(falhou.message, "Falhou: 1 de 2 cenários.")
        XCTAssertNil(falhou.video)

        XCTAssertEqual(ExecutionResultSummary(.init(status: "passed")).title, "Passou")
        XCTAssertEqual(ExecutionResultSummary(.init(status: "indeterminate", message: "RuntimeError: x")).title, "Indeterminado")
        XCTAssertEqual(ExecutionResultSummary(.init(status: "cancelled")).title, "Cancelado")
        XCTAssertEqual(ExecutionResultSummary(.init(status: "algo-novo")).kind, .indeterminate)

        let contagem = EngineDTO.RunCountSet(passed: 2, skipped: 1, undefined: 2, errors: 1)
        XCTAssertEqual(ExecutionResultSummary.countsText("Cenários", contagem, feminino: false),
                       "Cenários: 2 passaram, 1 com erro, 2 indefinidos, 1 pulado")
        XCTAssertEqual(ExecutionResultSummary.duration(125), "2 min 05 s")
        XCTAssertEqual(ExecutionResultSummary.elapsed(42), "00:42")
        XCTAssertEqual(ExecutionResultSummary.elapsed(3723), "1:02:03")
    }

    func testBadgeDaBarraLateral() {
        let ex = ExecutionState()
        XCTAssertEqual(ex.badgeCount, 0)
        ex.lastResult = .init(status: "failed", counts: .init(scenarios: .init(passed: 1, failed: 2, errors: 1)))
        XCTAssertEqual(ex.badgeCount, 3)
        ex.lastResult = .init(status: "failed")
        XCTAssertEqual(ex.badgeCount, 1, "falhou sem resumo ainda conta")
        ex.lastResult = .init(status: "passed")
        XCTAssertEqual(ex.badgeCount, 0)
        ex.lastResult = .init(status: "failed")
        ex.activeRun = ActiveRun(runId: "r", projectId: nil, startedAt: Date(), folder: nil, deviceId: nil, videoWarning: nil)
        XCTAssertEqual(ex.badgeCount, 0, "rodando, a barra mostra \"rodando\", não a contagem")
    }

    // MARK: - Trava do Rodar

    func testRodarBloqueadoComExplicacao() throws {
        XCTAssertEqual(ExecutionRules.runBlockReason(inspection: nil, engineConnected: false, busy: false),
                       "O motor não está no ar.")
        let semInterpretador = try decode("project.inspect_sem_interpretador", as: EngineDTO.ProjectInspection.self)
        XCTAssertTrue(try XCTUnwrap(ExecutionRules.runBlockReason(inspection: semInterpretador, engineConnected: true,
                                                                  busy: false)).contains("Nenhum interpretador"))
        let inexistente = try JSONDecoder().decode(EngineDTO.ProjectInspection.self, from: Data(#"""
        {"project":{"id":"a","root":"/p"},"entry":{"file":"main.py","found":true},"active_config":"c",
         "interpreter":{"path":"/p/.venv/bin/python","source":"venv","exists":false},"configs":[{"name":"c","active":true}]}
        """#.utf8))
        XCTAssertTrue(try XCTUnwrap(ExecutionRules.runBlockReason(inspection: inexistente, engineConnected: true,
                                                                  busy: false)).contains("não existe nesta máquina"))
        let pronto = try decode("project.configure", as: EngineDTO.ProjectInspection.self)
        XCTAssertNil(ExecutionRules.runBlockReason(inspection: pronto, engineConnected: true, busy: false))

        let nuvem = try JSONDecoder().decode(EngineDTO.ProjectInspection.self, from: Data(#"""
        {"project":{"id":"a","root":"/p"},"entry":{"file":"main.py","found":true},
         "interpreter":{"path":"/usr/bin/python3","exists":true},"active_config":"config_kobiton",
         "configs":[{"name":"config_kobiton","active":true,"cloud":true,"hub":"api.kobiton.com:443"}]}
        """#.utf8))
        let motivo = try XCTUnwrap(ExecutionRules.runBlockReason(inspection: nuvem, engineConnected: true, busy: false))
        XCTAssertTrue(motivo.contains("nuvem") && motivo.contains("api.kobiton.com:443"), motivo)

        let semInit = try JSONDecoder().decode(EngineDTO.ProjectInspection.self, from: Data(#"""
        {"project":{"id":"a","root":"/p"},"entry":{"file":"main.py","found":true},
         "interpreter":{"path":"/usr/bin/python3","exists":true}}
        """#.utf8))
        XCTAssertTrue(try XCTUnwrap(ExecutionRules.runBlockReason(inspection: semInit, engineConnected: true,
                                                                  busy: false)).contains("init(...)"))

        // Hub não confirmado não bloqueia: o motor pede confirmação.
        let incerto = try JSONDecoder().decode(EngineDTO.ProjectInspection.self, from: Data(#"""
        {"project":{"id":"a","root":"/p"},"entry":{"file":"main.py","found":true},"hub_state":"unknown",
         "interpreter":{"path":"/usr/bin/python3","exists":true},"active_config":"c",
         "configs":[{"name":"c","active":true,"hub_state":"unknown"}]}
        """#.utf8))
        XCTAssertNil(ExecutionRules.runBlockReason(inspection: incerto, engineConnected: true, busy: false))
    }

    // MARK: - Sessão

    func testAbrirProjetoLeOMainERodaODoctor() async throws {
        let (estado, sessao, motor) = try novaSessao()
        await sessao.openProject(path: "/Users/qa/Projetos/projeto_exemplo_behave")
        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas, ["project.open", "project.inspect", "project.doctor"])
        XCTAssertEqual(estado.execution.currentProject?.name, "projeto_exemplo_behave")
        XCTAssertEqual(estado.execution.inspection?.activeConfig, "config_android_local_HLG")
        XCTAssertEqual(estado.execution.doctor?.checks.count, 11)
        XCTAssertFalse(estado.execution.doctorRunning)
        let doctor = await motor.parametros(de: "project.doctor")
        XCTAssertEqual(doctor?["project_id"], .string("0a1b2c3d4e5f"))
        XCTAssertNotNil(doctor?["progress_token"])
    }

    func testPrimeiraLeituraAbreOMaisRecente() async throws {
        let (estado, sessao, motor) = try novaSessao()
        await sessao.loadExecution()
        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas, ["project.list", "run.status", "project.inspect", "project.doctor"])
        XCTAssertEqual(estado.execution.currentProjectID, "0a1b2c3d4e5f")
        XCTAssertTrue(estado.execution.loadedOnce)
    }

    func testProgressoDoDoctorTemTokenProprio() async throws {
        let (estado, sessao, _) = try novaSessao()
        estado.execution.doctorToken = "project.doctor-9"
        await sessao.handle(notificacao("$/progress", #"{"token":"project.doctor-9","message":"Conferindo o Appium","percent":null}"#))
        XCTAssertEqual(estado.execution.doctorProgress, "Conferindo o Appium")
        await sessao.handle(notificacao("$/progress", #"{"token":"outro-1","message":"x","percent":null}"#))
        XCTAssertEqual(estado.execution.doctorProgress, "Conferindo o Appium")
    }

    /// `project_not_trusted` → diálogo "Confiar neste projeto?" com
    /// interpretador, entrada e pasta → confirmar repete com `trusted: true`.
    func testFluxoDeConfiancaAoRodar() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await motor.enfileirarErro("run.start", .engine(code: "project_not_trusted", message: "ainda não é confiável"))

        await sessao.startRun()
        let primeira = await motor.parametros(de: "run.start")
        XCTAssertNil(primeira?["trusted"])
        XCTAssertNil(estado.execution.activeRun)
        guard case .trust(let pedido) = try XCTUnwrap(estado.execution.confirmation) else {
            return XCTFail("esperava o diálogo de confiança")
        }
        XCTAssertEqual(pedido.then, .run)
        // Relido na hora (FR-05): o da fixture de `project.inspect`.
        XCTAssertEqual(pedido.interpreter, "/Users/qa/Projetos/projeto_exemplo_behave/.venv/bin/python")
        XCTAssertEqual(pedido.entry, "main.py")
        XCTAssertEqual(pedido.workingDir, "/Users/qa/Projetos/projeto_exemplo_behave")
        XCTAssertNil(estado.execution.error, "não é erro: é pergunta")

        await sessao.confirmExecutionDialog(.trust(pedido))
        let segunda = await motor.parametros(de: "run.start")
        XCTAssertEqual(segunda?["trusted"], .bool(true))
        XCTAssertEqual(segunda?["record_video"], .bool(estado.execution.recordVideo))
        XCTAssertNil(estado.execution.confirmation)
        XCTAssertEqual(estado.execution.activeRun?.runId, "20250905-000000-0a1b2c")
        XCTAssertEqual(estado.execution.currentProject?.trusted, true)
    }

    func testHubNaoConfirmadoPedeConfirmacaoERepete() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await motor.enfileirarErro("run.start", .engine(code: "hub_unknown", message: "hub montado por os.environ"))
        await sessao.startRun()
        guard case .unknownHub(let mensagem, let confiou) = try XCTUnwrap(estado.execution.confirmation) else {
            return XCTFail("esperava a confirmação do hub")
        }
        XCTAssertEqual(mensagem, "hub montado por os.environ")
        await sessao.confirmExecutionDialog(.unknownHub(message: mensagem, trusted: confiou))
        let parametros = await motor.parametros(de: "run.start")
        XCTAssertEqual(parametros?["allow_unknown_hub"], .bool(true))
        XCTAssertNotNil(estado.execution.activeRun)
    }

    func testAparelhoOcupadoEEntradaInvalidaMostramAMensagemDoMotor() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await motor.enfileirarErro("run.start", .engine(code: "device_busy", message: "O aparelho está rodando o projeto X"))
        await sessao.startRun()
        XCTAssertEqual(estado.execution.error, "O aparelho está rodando o projeto X")
        XCTAssertNil(estado.execution.confirmation)

        await motor.enfileirarErro("run.start", .engine(code: "invalid_input",
                                                        message: "O aparelho escolhido difere do udid da config"))
        estado.execution.targetDeviceID = "SERIAL0002"
        await sessao.startRun()
        XCTAssertEqual(estado.execution.error, "O aparelho escolhido difere do udid da config")
        let parametros = await motor.parametros(de: "run.start")
        XCTAssertEqual(parametros?["device_id"], .string("SERIAL0002"))
    }

    func testConsoleEFimPelasNotificacoes() async throws {
        let (estado, sessao, _) = try sessaoProntaParaRodar()
        await sessao.startRun()
        XCTAssertTrue(estado.execution.isRunning)
        let revisao = estado.execution.consoleRevision
        await sessao.handle(try notificacao("notif_run.log"))
        XCTAssertEqual(estado.execution.console.lines, ["  Cenário: Abrir a home"])
        XCTAssertEqual(estado.execution.consoleRevision, revisao + 1, "cada linha avisa a tela")

        await sessao.handle(try notificacao("notif_run.finished"))
        XCTAssertFalse(estado.execution.isRunning)
        XCTAssertEqual(estado.execution.lastResult?.status, "failed")
        XCTAssertEqual(estado.execution.badgeCount, 1)
        XCTAssertTrue(estado.statusMessage.hasPrefix("Falhou"))
    }

    /// `run.finished` que chega antes da resposta do `run.start` não deixa a
    /// aba presa em "rodando".
    func testFimAntesDaRespostaNaoFicaRodando() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await motor.reter("run.start")
        let tarefa = Task { await sessao.startRun() }
        while await motor.quantasRetidas("run.start") == 0 { await Task.yield() }
        await sessao.handle(notificacao("run.finished", #"{"run_id":"20250905-000000-0a1b2c","status":"indeterminate"}"#))
        await motor.liberar("run.start")
        await tarefa.value
        XCTAssertFalse(estado.execution.isRunning)
        XCTAssertEqual(estado.execution.lastResult?.status, "indeterminate")
    }

    func testConfiarPeloDoctorChamaProjectTrustERefazODoctor() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await sessao.requestTrustForDoctor()
        guard case .trust(let pedido) = try XCTUnwrap(estado.execution.confirmation) else {
            return XCTFail("esperava o mesmo diálogo de confiança")
        }
        XCTAssertEqual(pedido.then, .verify)
        await sessao.confirmExecutionDialog(.trust(pedido))
        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.suffix(2), ["project.trust", "project.doctor"])
        XCTAssertEqual(estado.execution.currentProject?.trusted, true)
    }

    func testEscolherInterpretadorChamaConfigure() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await sessao.configureInterpreter(.string("/Users/qa/.virtualenvs/exemplo/bin/python"))
        let parametros = await motor.parametros(de: "project.configure")
        XCTAssertEqual(parametros?["interpreter"], .string("/Users/qa/.virtualenvs/exemplo/bin/python"))
        XCTAssertEqual(estado.execution.inspection?.interpreter.source, "manual")
        await sessao.configureInterpreter(.null)
        let volta = await motor.parametros(de: "project.configure")
        XCTAssertEqual(volta?["interpreter"], .null)
    }

    func testEsquecerTiraDaListaEVoltaAoEstadoVazio() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await sessao.forgetCurrentProject()
        let parametros = await motor.parametros(de: "project.forget")
        XCTAssertEqual(parametros?["project_id"], .string("0a1b2c3d4e5f"))
        XCTAssertNil(estado.execution.currentProject)
        XCTAssertNil(estado.execution.inspection)
        XCTAssertTrue(estado.execution.projects.isEmpty)
    }

    func testPararChamaRunStop() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await sessao.startRun()
        await sessao.stopRun()
        let chamadas = await motor.chamadas
        XCTAssertTrue(chamadas.contains("run.stop"))
        // A fixture diz que não havia execução: a aba não fica presa.
        XCTAssertFalse(estado.execution.isRunning)
        XCTAssertFalse(estado.execution.stopping)
    }

    // MARK: - Revisão do front (FR-01 a FR-08)

    /// FR-01: a primeira leitura cancelada (sair da aba no meio do inspect)
    /// não deixa o projeto sem análise para sempre: a volta relê.
    func testPrimeiraLeituraCanceladaRecuperaNaVolta() async throws {
        let (estado, sessao, motor) = try novaSessao()
        await motor.enfileirarErro("project.inspect", .cancelled)
        await sessao.loadExecution()
        XCTAssertTrue(estado.execution.loadedOnce)
        XCTAssertNotNil(estado.execution.currentProjectID)
        XCTAssertNil(estado.execution.inspection, "o cancelamento interrompeu o inspect")
        XCTAssertNil(estado.execution.error, "cancelar não é erro")

        await sessao.loadExecution()
        XCTAssertNotNil(estado.execution.inspection, "a volta à aba relê o main")
        XCTAssertNotNil(estado.execution.doctor, "e roda o doctor que faltou")
    }

    /// Resposta do doctor com marca própria, para saber qual foi aplicada.
    private func doctorMarcado(_ ok: Int) -> Data {
        Data(#"{"project_id":"0a1b2c3d4e5f","checks":[],"summary":{"ok":\#(ok),"warn":0,"fail":0,"skip":0},"ready":true}"#.utf8)
    }

    private func esperarRetida(_ motor: FakeEngine, _ metodo: String) async {
        while await motor.quantasRetidas(metodo) == 0 { await Task.yield() }
    }

    /// FR-02: trocar de projeto com o doctor em andamento cancela o antigo
    /// (o resultado dele é descartado) e roda o doctor do projeto novo.
    func testTrocarDeProjetoDuranteODoctorRefazODoctor() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await motor.enfileirar("project.doctor", [doctorMarcado(99), doctorMarcado(7)])
        await motor.reter("project.doctor")
        let antigo = Task { await sessao.runDoctor() }
        await esperarRetida(motor, "project.doctor")
        XCTAssertTrue(estado.execution.doctorRunning)

        let troca = Task { await sessao.openProject(path: "/Users/qa/Projetos/projeto_exemplo_behave") }
        await Task.yield()
        await motor.liberar("project.doctor")
        await troca.value
        await antigo.value

        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas.filter { $0 == "project.doctor" }.count, 2)
        XCTAssertEqual(estado.execution.doctor?.summary.ok, 7, "o doctor antigo, cancelado, não pode valer")
        XCTAssertFalse(estado.execution.doctorRunning)
    }

    /// FR-02: escolher outro interpretador durante o doctor refaz o doctor
    /// com o interpretador novo.
    func testTrocarInterpretadorDuranteODoctorRefazODoctor() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await motor.enfileirar("project.doctor", [doctorMarcado(99), doctorMarcado(5)])
        await motor.reter("project.doctor")
        let antigo = Task { await sessao.runDoctor() }
        await esperarRetida(motor, "project.doctor")

        let troca = Task { await sessao.configureInterpreter(.string("/Users/qa/.virtualenvs/exemplo/bin/python")) }
        await Task.yield()
        await motor.liberar("project.doctor")
        await troca.value
        await antigo.value

        let chamadas = await motor.chamadas
        XCTAssertEqual(Array(chamadas.suffix(2)), ["project.configure", "project.doctor"])
        XCTAssertEqual(estado.execution.doctor?.summary.ok, 5)
    }

    /// FR-03: com o `run.start` em voo, Abrir, Recentes e Esquecer não
    /// mexem no projeto.
    func testProjetoTravadoDuranteORunStart() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await motor.reter("run.start")
        let rodar = Task { await sessao.startRun() }
        await esperarRetida(motor, "run.start")
        XCTAssertTrue(estado.execution.starting)
        XCTAssertNotNil(estado.execution.projectLockReason)

        await sessao.forgetCurrentProject()
        await sessao.openProject(path: "/outro")
        await sessao.configureInterpreter(.null)
        let chamadas = await motor.chamadas
        XCTAssertFalse(chamadas.contains("project.forget"))
        XCTAssertFalse(chamadas.contains("project.open"))
        XCTAssertFalse(chamadas.contains("project.configure"))
        XCTAssertNotNil(estado.execution.currentProject)

        await motor.liberar("run.start")
        await rodar.value
        XCTAssertTrue(estado.execution.isRunning)
        XCTAssertNotNil(estado.execution.projectLockReason, "rodando, continua travado")
        await sessao.forgetCurrentProject()
        let depois = await motor.chamadas
        XCTAssertFalse(depois.contains("project.forget"))
    }

    /// FR-05: o diálogo de confiança mostra a análise relida na hora, e não
    /// a de quando o projeto foi aberto.
    func testDialogoDeConfiancaReleOProjetoAntes() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        // A análise guardada é a de `project.configure` (interpretador manual);
        // a de agora (`project.inspect`) é a do .venv do projeto.
        await motor.enfileirarErro("run.start", .engine(code: "project_not_trusted", message: "não confiável"))
        await sessao.startRun()
        let chamadas = await motor.chamadas
        XCTAssertEqual(Array(chamadas.suffix(2)), ["run.start", "project.inspect"])
        guard case .trust(let pedido) = try XCTUnwrap(estado.execution.confirmation) else {
            return XCTFail("esperava o diálogo de confiança")
        }
        XCTAssertEqual(pedido.interpreter, "/Users/qa/Projetos/projeto_exemplo_behave/.venv/bin/python")

        estado.execution.confirmation = nil
        await sessao.requestTrustForDoctor()
        let depois = await motor.chamadas
        XCTAssertEqual(depois.last, "project.inspect")
        guard case .trust(let verificar) = try XCTUnwrap(estado.execution.confirmation) else {
            return XCTFail("esperava o diálogo de confiança do doctor")
        }
        XCTAssertEqual(verificar.then, .verify)
    }

    /// FR-07: linha e fim de outra execução (atrasados) não entram na desta.
    func testNotificacoesDeOutraExecucaoSaoIgnoradas() async throws {
        let (estado, sessao, _) = try sessaoProntaParaRodar()
        await sessao.startRun()
        let id = try XCTUnwrap(estado.execution.activeRun?.runId)
        await sessao.handle(notificacao("run.log", #"{"run_id":"velha","line":"linha atrasada"}"#))
        await sessao.handle(notificacao("run.finished", #"{"run_id":"velha","status":"passed"}"#))
        XCTAssertTrue(estado.execution.console.isEmpty)
        XCTAssertTrue(estado.execution.isRunning, "o fim da execução antiga não encerra a nova")
        await sessao.handle(notificacao("run.log", #"{"run_id":"\#(id)","line":"minha linha"}"#))
        XCTAssertEqual(estado.execution.console.lines, ["minha linha"])

        // Sem execução nem início em voo, nada entra.
        await sessao.handle(notificacao("run.finished", #"{"run_id":"\#(id)","status":"failed"}"#))
        await sessao.handle(notificacao("run.log", #"{"run_id":"\#(id)","line":"depois do fim"}"#))
        XCTAssertEqual(estado.execution.console.lines, ["minha linha"])
    }

    /// FR-07 + D-F8: durante o `run.start`, adota o `run_id` da primeira
    /// linha e recusa outro.
    func testDuranteORunStartAdotaOPrimeiroRunId() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await motor.reter("run.start")
        let rodar = Task { await sessao.startRun() }
        await esperarRetida(motor, "run.start")
        await sessao.handle(notificacao("run.log", #"{"run_id":"20250905-000000-0a1b2c","line":"primeira"}"#))
        await sessao.handle(notificacao("run.log", #"{"run_id":"outra","line":"intrusa"}"#))
        await motor.liberar("run.start")
        await rodar.value
        XCTAssertEqual(estado.execution.console.lines, ["primeira"])
        XCTAssertEqual(estado.execution.activeRun?.runId, "20250905-000000-0a1b2c")
    }

    /// FR-08: a mensagem de parada sai antes da chamada; um fim que chega
    /// antes da resposta não é sobrescrito por "Parando…".
    func testParadaNaoSobrescreveOFim() async throws {
        let (estado, sessao, motor) = try sessaoProntaParaRodar()
        await sessao.startRun()
        let id = try XCTUnwrap(estado.execution.activeRun?.runId)
        await motor.responder("run.stop", com: Data(#"{"running":true,"stopped":true,"run_id":"\#(id)"}"#.utf8))
        await motor.reter("run.stop")
        let parar = Task { await sessao.stopRun() }
        await esperarRetida(motor, "run.stop")
        XCTAssertEqual(estado.statusMessage, "Parando a execução…")
        await sessao.handle(notificacao("run.finished", #"{"run_id":"\#(id)","status":"cancelled"}"#))
        await motor.liberar("run.stop")
        await parar.value
        XCTAssertTrue(estado.statusMessage.hasPrefix("Execução: cancelado"), estado.statusMessage)
        XCTAssertFalse(estado.execution.isRunning)
    }

    /// Reabrir a aba com a execução viva no motor reconcilia o "rodando".
    func testRunStatusComExecucaoAtiva() async throws {
        let (estado, sessao, motor) = try novaSessao()
        await motor.responder("run.status", com: Data(#"""
        {"running":true,"run":{"run_id":"r9","project_id":"0a1b2c3d4e5f","project_name":"p","device_id":"emulator-5554",
         "folder":"/tmp/r9","started_at":1757030000.0,"elapsed_s":3.0,"lines":10,"video":"scrcpy","stopping":false},"last":null}
        """#.utf8))
        await sessao.refreshRunStatus()
        XCTAssertEqual(estado.execution.activeRun?.runId, "r9")
        XCTAssertEqual(estado.execution.activeRun?.deviceId, "emulator-5554")
        await sessao.handle(notificacao("run.log", #"{"run_id":"r9","line":"ao vivo"}"#))
        XCTAssertEqual(estado.execution.console.lines, ["ao vivo"])

        await motor.responder("run.status", com: Data(#"{"running":false,"run":null,"last":{"run_id":"r9","status":"passed"}}"#.utf8))
        await sessao.refreshRunStatus()
        XCTAssertFalse(estado.execution.isRunning)
        XCTAssertEqual(estado.execution.lastResult?.status, "passed")
    }

    /// FR-06: o aparelho alvo aparece na barra Rodar, parado (menu) e
    /// rodando (texto), numa coluna estreita.
    func testBarraRodarSempreDizOAparelho() throws {
        let (estado, sessao, _) = try sessaoProntaParaRodar()
        estado.availableDevices = [(id: "emulator-5554", name: "Pixel 7")]
        let tema = ThemeManager(preview: PraiaLightTheme())
        let parado = try AccessibilityInspector.arvore(
            de: ExecutionRunBar().environment(estado).environment(sessao).environment(tema), largura: 520, altura: 80
        )
        let menu = try XCTUnwrap(parado.node(label: "Aparelho alvo"), parado.dump)
        XCTAssertEqual(menu.value, "Automático (emulator-5554)", parado.dump)

        estado.execution.activeRun = ActiveRun(runId: "r", projectId: nil, startedAt: Date(), folder: nil,
                                               deviceId: "emulator-5554", videoWarning: nil)
        let rodando = try AccessibilityInspector.arvore(
            de: ExecutionRunBar().environment(estado).environment(sessao).environment(tema), largura: 520, altura: 80
        )
        XCTAssertEqual(rodando.node(label: "Aparelho alvo")?.value, "Pixel 7", rodando.dump)
        XCTAssertNotNil(rodando.node(label: "Tempo decorrido")?.value, rodando.dump)
    }

    /// FR-11: ⌘F na Execução busca no console.
    func testBuscaNaExecucaoVaiParaOConsole() {
        let estado = AppState()
        estado.workspaceTab = .execution
        XCTAssertTrue(estado.canSearch)
        estado.search()
        XCTAssertEqual(estado.consoleFindRequest, 1)
        var contexto = CommandContext()
        contexto.workspaceTab = .execution
        contexto.inspectorSuppressed = true
        let busca = CommandRegistry.command(.search, in: contexto)
        XCTAssertEqual(busca?.title, "Buscar no Console")
        XCTAssertNil(busca?.disabledReason)
    }

    // MARK: - Área e atalhos

    func testExecucaoEhOUltimoCasoComAtalhoSeisEAmbienteContinuaNoCinco() {
        XCTAssertEqual(WorkspaceTab.allCases.last, .execution)
        XCTAssertEqual(WorkspaceTab.execution.shortcutDigit, "6")
        XCTAssertEqual(WorkspaceTab.environment.shortcutDigit, "5")
        XCTAssertEqual(WorkspaceTab.report.shortcutDigit, "4")
        XCTAssertEqual(WorkspaceTab.execution.displayName, "Execução")
        XCTAssertFalse(WorkspaceTab.execution.needsDevice)
        XCTAssertEqual(WorkspaceTab.workspaceAreas.last, .execution, "na barra lateral, depois do Relatório")
        XCTAssertFalse(HomeCopy.areaSummary(.execution).isEmpty)

        let comandos = CommandRegistry.commands(in: CommandContext())
        let comSeis = comandos.filter { $0.shortcut?.key == "6" && $0.shortcut?.modifiers == .command }
        XCTAssertEqual(comSeis.map(\.id), [.area(.execution)])
        let comCinco = comandos.filter { $0.shortcut?.key == "5" && $0.shortcut?.modifiers == .command }
        XCTAssertEqual(comCinco.map(\.id), [.area(.environment)])
    }

    func testExecucaoSemInspectorESemBuscaDaToolbar() {
        let estado = AppState()
        estado.selectedDevice = "emulator-5554"
        estado.workspaceTab = .execution
        XCTAssertTrue(estado.inspectorSuppressed)
        XCTAssertFalse(estado.usesToolbarSearch, "a toolbar não tem campo de busca na Execução")
        XCTAssertFalse(estado.canToggleMirror)
        var contexto = CommandContext()
        contexto.workspaceTab = .execution
        contexto.inspectorSuppressed = true
        XCTAssertEqual(CommandRegistry.command(.inspector, in: contexto)?.disabledReason, "A Execução não tem inspector")
    }

    func testSubtituloDaJanela() throws {
        let ex = ExecutionState()
        XCTAssertEqual(ExecutionCopy.subtitle(ex), "Nenhum projeto")
        ex.select(try decode("project.open", as: EngineDTO.ProjectOpened.self).project)
        XCTAssertEqual(ExecutionCopy.subtitle(ex), "projeto_exemplo_behave")
        ex.lastResult = .init(status: "passed")
        XCTAssertEqual(ExecutionCopy.subtitle(ex), "projeto_exemplo_behave · passou")
    }
}

extension XCTestCase {
    /// A aba Execução com o conteúdo que mais pesa: projeto lido (com ou sem
    /// interpretador), doctor, banner de resultado e console com linhas.
    /// Usado nas guardas de tamanho mínimo e nas capturas.
    @MainActor
    func preencherExecucao(_ estado: AppState, semInterpretador: Bool = true, resultado: Bool = true,
                           rodando: Bool = false) throws {
        let fixtures = try resultadosDasFixtures()
        let decoder = JSONDecoder()
        let nome = semInterpretador ? "project.inspect_sem_interpretador" : "project.configure"
        let leitura = try decoder.decode(EngineDTO.ProjectInspection.self, from: try XCTUnwrap(fixtures[nome]))
        let ex = estado.execution
        ex.loadedOnce = true
        ex.select(leitura.project)
        ex.inspection = leitura
        ex.doctor = try decoder.decode(EngineDTO.ProjectDoctor.self, from: try XCTUnwrap(fixtures["project.doctor"]))
        let linhas = [
            "Feature: Navegação básica do app de exemplo # features/teste/teste.feature:1",
            "  Cenário: Abrir a home                     # features/teste/teste.feature:3",
            "    Dado que o app está aberto ... passed in 0.001s",
            "    Então vejo a home ... passed in 0.000s",
            "  Cenário: Abrir o extrato                  # features/teste/teste.feature:7",
            "    Dado que o app está aberto ... passed in 0.001s",
            "    Então vejo o extrato ... failed in 0.002s",
            "Traceback (most recent call last):",
            "AssertionError: extrato não apareceu",
            "0 features passed, 1 failed, 0 skipped",
            "1 scenario passed, 1 failed, 0 skipped",
            "5 steps passed, 1 failed, 0 skipped, 0 undefined",
        ]
        for linha in linhas { ex.appendConsole(linha) }
        if resultado {
            ex.lastResult = EngineDTO.RunFinished(
                runId: "20250905-000000-0a1b2c", status: "failed",
                counts: .init(features: .init(failed: 1), scenarios: .init(passed: 1, failed: 1),
                              steps: .init(passed: 5, failed: 1), summaries: 1),
                exitCode: 0, folder: "/Users/qa/Documents/Mo baile/Execuções/projeto-exemplo-behave/20250905-000000",
                video: nil, videoWarning: "Sem aparelho alvo: a execução segue sem vídeo.",
                message: "Falhou: 1 de 2 cenários.", durationS: 1.2
            )
        }
        if rodando {
            ex.activeRun = ActiveRun(runId: "r1", projectId: leitura.project.id, startedAt: Date().addingTimeInterval(-42),
                                     folder: nil, deviceId: "emulator-5554", videoWarning: nil)
        }
    }
}
