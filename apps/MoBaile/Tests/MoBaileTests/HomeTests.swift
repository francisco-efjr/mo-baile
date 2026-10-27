import XCTest
@testable import MoBaile

/// Tela Início: contrato de `setup.check`, escolha do próximo passo, onde o
/// app abre e o comando que o botão "Instalar no Terminal…" roda.
@MainActor
final class HomeTests: XCTestCase {

    private func setupDaFixture() throws -> EngineDTO.Setup {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "engine_payloads", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "engine_payloads", withExtension: "json"))
        let todos = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let resultado = try XCTUnwrap((todos["setup.check"] as? [String: Any])?["result"])
        let dados = try JSONSerialization.data(withJSONObject: resultado)
        return try JSONDecoder().decode(EngineDTO.Setup.self, from: dados)
    }

    // MARK: - Contrato

    func testSetupDecodificaGruposAreasEProximoPasso() throws {
        let setup = try setupDaFixture()
        XCTAssertEqual(setup.system, "macos")
        XCTAssertEqual(setup.groups.map(\.id), ["motor", "android", "ios", "extras"])
        XCTAssertEqual(setup.pending, 1)
        XCTAssertEqual(setup.nextStep?.component, "appium")
        XCTAssertEqual(setup.nextStep?.install, "appium")

        let appium = try XCTUnwrap(setup.component("appium"))
        XCTAssertEqual(appium.daemonState, .error)
        XCTAssertTrue(appium.required)
        let xcode = try XCTUnwrap(setup.component("xcode"))
        XCTAssertNil(xcode.install, "o Xcode vem da App Store, não do script")
        XCTAssertNotNil(xcode.link)
        XCTAssertFalse(try XCTUnwrap(setup.component("scrcpy")).required)

        // Cada área do motor vira uma aba do app, na ordem da barra lateral.
        XCTAssertEqual(setup.features.compactMap(\.tab), WorkspaceTab.workspaceAreas)
        let pageObjects = try XCTUnwrap(setup.feature("page_objects"))
        XCTAssertEqual(pageObjects.platforms.first { $0.platform == "ios" }?.daemonState, .warn)
        XCTAssertEqual(pageObjects.platforms.first { $0.platform == "android" }?.daemonState, .ok)
    }

    func testTodoItemQueFaltaDizComoResolver() throws {
        for item in try setupDaFixture().groups.flatMap(\.components) where item.daemonState != .ok && item.required {
            XCTAssertTrue(item.install != nil || item.link != nil, item.id)
        }
    }

    // MARK: - Próximo passo

    func testSemPythonOProximoPassoEInstalarOPython() {
        let mensagem = EngineLocator.unsuitableMessage(found: ["/usr/bin/python3 (Python 3.9.6, antigo demais)"])
        let passo = HomeNextStep.pick(engineStatus: .stopped(mensagem), lastError: mensagem, setup: nil, deviceName: nil)
        XCTAssertEqual(passo, .installPython(detail: mensagem))
    }

    func testMotorParadoPorOutroMotivoPedeReinicio() {
        let passo = HomeNextStep.pick(engineStatus: .stopped("O motor encerrou."), lastError: "O motor encerrou.",
                                      setup: nil, deviceName: nil)
        XCTAssertEqual(passo, .engineStopped(detail: "O motor encerrou."))
    }

    func testSubindoOuSemChecagemFicaConferindo() throws {
        XCTAssertEqual(HomeNextStep.pick(engineStatus: .starting, lastError: nil, setup: nil, deviceName: nil), .checking)
        XCTAssertEqual(HomeNextStep.pick(engineStatus: .running, lastError: nil, setup: nil, deviceName: nil), .checking)
    }

    func testOQueFaltaInstalarVemAntesDoAparelho() throws {
        let setup = try setupDaFixture()
        let passo = HomeNextStep.pick(engineStatus: .running, lastError: nil, setup: setup, deviceName: "iPhone 16")
        XCTAssertEqual(passo, .install(try XCTUnwrap(setup.nextStep)))
    }

    func testTudoInstaladoMostraOAparelhoOuPedeUm() throws {
        let completo = try semPendencias(setupDaFixture())
        XCTAssertEqual(HomeNextStep.pick(engineStatus: .running, lastError: nil, setup: completo, deviceName: "iPhone 16"),
                       .connected(name: "iPhone 16"))
        XCTAssertEqual(HomeNextStep.pick(engineStatus: .running, lastError: nil, setup: completo, deviceName: nil),
                       .connectDevice)
    }

    private func semPendencias(_ s: EngineDTO.Setup) -> EngineDTO.Setup {
        EngineDTO.Setup(system: s.system, python: s.python, groups: s.groups, features: s.features,
                        pending: 0, nextStep: nil)
    }

    // MARK: - Textos

    func testResumoESubtitulo() throws {
        let setup = try setupDaFixture()
        XCTAssertEqual(HomeCopy.subtitle(setup: setup, engineRunning: true), "Falta instalar 1 item")
        XCTAssertEqual(HomeCopy.subtitle(setup: semPendencias(setup), engineRunning: true), "Tudo pronto")
        XCTAssertEqual(HomeCopy.subtitle(setup: nil, engineRunning: false), "Motor parado")
        XCTAssertEqual(HomeCopy.pendingText(3), "Faltam 3 itens para instalar")
        XCTAssertNil(HomeCopy.pendingText(0))

        let proximo = try XCTUnwrap(setup.nextStep)
        XCTAssertEqual(HomeCopy.summary(.install(proximo), pending: 1),
                       "Falta instalar 1 item: Appium com o driver XCUITest.")
        XCTAssertTrue(HomeCopy.summary(.install(proximo), pending: 2).hasPrefix("Faltam 2 itens"))
        XCTAssertEqual(HomeCopy.linkTitle("macappstore://apps.apple.com/app/id497799835"), "Abrir na App Store…")
        XCTAssertEqual(HomeCopy.linkTitle("https://developer.android.com/studio"), "Abrir Página…")
        for area in WorkspaceTab.workspaceAreas {
            XCTAssertFalse(HomeCopy.areaSummary(area).isEmpty, area.rawValue)
        }
    }

    // MARK: - Onde o app abre

    /// O app sempre abre no Início, com aparelho ou sem, e com a hierarquia
    /// fechada: ela só aparece quando a pessoa pede.
    @MainActor
    func testAbreSempreNoInicioComAHierarquiaFechada() {
        let estado = AppState.atLaunch()
        XCTAssertEqual(estado.workspaceTab, .home)
        XCTAssertFalse(estado.inspectorVisible)
        estado.selectedDevice = "7303D258"
        estado.workspaceTab = .pageObjects
        XCTAssertFalse(estado.inspectorShown, "conectar e ir para Page Objects não abre a hierarquia")
        estado.toggleInspector()
        XCTAssertTrue(estado.inspectorShown)
    }

    /// Ninguém mais leva a janela para outra área ao terminar a abertura.
    func testAberturaNaoTrocaDeArea() throws {
        var raiz = URL(fileURLWithPath: #filePath)
        while raiz.lastPathComponent != "MoBaile"
            || !FileManager.default.fileExists(atPath: raiz.appendingPathComponent("Package.swift").path) {
            guard raiz.path != "/" else { throw XCTSkip("Package.swift do app não encontrado") }
            raiz.deleteLastPathComponent()
        }
        let fonte = try String(contentsOf: raiz.appendingPathComponent("Sources/MoBaile/Views/MainWindow/ContentView.swift"),
                               encoding: .utf8)
        XCTAssertFalse(fonte.contains("onChange(of: session.launchPhase)"))
        let app = try String(contentsOf: raiz.appendingPathComponent("Sources/MoBaile/App/MoBaileApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("AppState.atLaunch()"))
    }

    // MARK: - Área Início

    func testInicioTemAtalhoZeroESemInspector() {
        XCTAssertEqual(WorkspaceTab.allCases.first, .home)
        XCTAssertEqual(WorkspaceTab.workspaceAreas, [.pageObjects, .network, .analytics, .report])
        XCTAssertEqual(WorkspaceTab.home.shortcutDigit, "0")
        XCTAssertEqual(WorkspaceTab.pageObjects.shortcutDigit, "1")
        XCTAssertEqual(WorkspaceTab.report.shortcutDigit, "4")
        XCTAssertFalse(WorkspaceTab.home.needsDevice)

        let estado = AppState()
        estado.availableDevices = [(id: "A1", name: "Pixel 7")]
        estado.selectedDevice = "A1"
        estado.workspaceTab = .home
        XCTAssertTrue(estado.inspectorSuppressed, "o Início não tem o que inspecionar")
        XCTAssertFalse(estado.inspectorShown)
        estado.workspaceTab = .pageObjects
        XCTAssertFalse(estado.inspectorSuppressed)
    }

    // MARK: - Instalador

    func testComandoComAspasEPythonDoMotor() {
        let script = URL(fileURLWithPath: "/Applications/Mo baile (nativo).app/Contents/Resources/setup/instalar-mac.sh")
        XCTAssertEqual(
            SetupInstaller.command(target: "ios-device", script: script, python: "/usr/local/bin/python3"),
            "MOBAILE_PYTHON='/usr/local/bin/python3' bash '/Applications/Mo baile (nativo).app/Contents/Resources/setup/instalar-mac.sh' ios-device"
        )
        XCTAssertEqual(SetupInstaller.command(target: "python", script: script, python: nil),
                       "bash '/Applications/Mo baile (nativo).app/Contents/Resources/setup/instalar-mac.sh' python")
        XCTAssertEqual(SetupInstaller.shellQuote("a'b"), #"'a'\''b'"#)
        XCTAssertEqual(SetupInstaller.commandFile("bash x"), "#!/bin/bash\nclear\nbash x\n")
    }

    func testSoAlvoConhecidoViraComando() {
        XCTAssertTrue(SetupInstaller.isValidTarget("appium-android"))
        XCTAssertFalse(SetupInstaller.isValidTarget("android; rm -rf ~"))
        XCTAssertFalse(SetupInstaller.isValidTarget(""))
        XCTAssertThrowsError(try SetupInstaller.openInTerminal(target: "x y", python: nil)) {
            XCTAssertEqual($0 as? SetupInstaller.Failure, .invalidTarget("x y"))
        }
    }

    func testScriptVemDoAppOuDoRepositorio() {
        let recursos = URL(fileURLWithPath: "/App.app/Contents/Resources")
        let raiz = URL(fileURLWithPath: "/repo")
        XCTAssertEqual(SetupInstaller.scriptURL(resources: recursos, repositoryRoot: raiz, exists: { _ in true })?.path,
                       "/App.app/Contents/Resources/setup/instalar-mac.sh")
        XCTAssertEqual(SetupInstaller.scriptURL(resources: recursos, repositoryRoot: raiz, exists: { $0.hasPrefix("/repo") })?.path,
                       "/repo/tools/setup/instalar-mac.sh")
        XCTAssertNil(SetupInstaller.scriptURL(resources: recursos, repositoryRoot: raiz, exists: { _ in false }))
    }

    /// Os alvos que o motor manda existem no script: um alvo novo de um lado
    /// só daria "alvo desconhecido" no Terminal.
    func testAlvosDoMotorExistemNoScript() throws {
        let raiz = try XCTUnwrap(EngineLocator.repositoryRoot(), "rodando fora do repositório")
        let script = try String(contentsOf: raiz.appendingPathComponent("tools/setup/instalar-mac.sh"), encoding: .utf8)
        let alvos = Set(try setupDaFixture().groups.flatMap(\.components).compactMap(\.install))
        XCTAssertFalse(alvos.isEmpty)
        for alvo in alvos {
            XCTAssertTrue(script.contains("\n        \(alvo)) "), "alvo '\(alvo)' não está no case do script")
        }
    }
}
