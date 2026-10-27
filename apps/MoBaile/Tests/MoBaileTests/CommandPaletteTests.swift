import XCTest
import SwiftUI
@testable import MoBaile

/// FLU-1: registro único de ações, busca aproximada, disponibilidade por
/// contexto e recentes da paleta de comandos.
final class CommandPaletteTests: XCTestCase {

    /// Aparelho conectado, motor no ar, passos e tráfego: quase tudo disponível.
    private func contextoCheio() -> CommandContext {
        var c = CommandContext()
        c.devices = [.init(id: "7303D258", name: "iPhone 16"), .init(id: "A1B2", name: "iPhone 15")]
        c.selectedDevice = "7303D258"
        c.stepCount = 6
        c.hasCode = true
        c.hasActionsCode = true
        c.hasLocatorsCode = true
        c.httpCount = 3
        c.analyticsCount = 2
        c.canStartAnalytics = true
        c.hasSimulators = true
        return c
    }

    private func primeiro(_ busca: String, _ c: CommandContext? = nil, recentes: [CommandID] = []) -> AppCommand? {
        let comandos = CommandRegistry.commands(in: c ?? contextoCheio())
        return CommandSearch.sections(comandos, query: busca, recents: recentes).first?.commands.first
    }

    // MARK: - Registro

    func testIdentificadoresETitulosUnicos() {
        let comandos = CommandRegistry.commands(in: contextoCheio())
        XCTAssertEqual(Set(comandos.map(\.id)).count, comandos.count, "id repetido no registro")
        XCTAssertEqual(Set(comandos.map(\.title)).count, comandos.count, "dois itens com o mesmo título confundem a busca")
    }

    /// Os atalhos de antes continuam onde estavam, e nenhum se repete.
    func testAtalhosDosMenusEstaoNoRegistroSemRepetir() {
        let comandos = CommandRegistry.commands(in: contextoCheio())
        let atalhos = comandos.compactMap { c in c.shortcut.map { (c.id, $0.display) } }
        XCTAssertEqual(Set(atalhos.map(\.1)).count, atalhos.count, "atalho repetido: \(atalhos.map(\.1).sorted())")

        let porID = Dictionary(uniqueKeysWithValues: atalhos)
        let esperados: [CommandID: String] = [
            .save: "⌘S", .openSpec: "⌘O", .exportHAR: "⇧⌘E", .search: "⌘F",
            .inspector: "⌥⌘I", .mirror: "⌥1", .workspace: "⌥2", .allPanels: "⌥⌘F", .zen: "⌃⌘Z",
            .area(.home): "⌘0", .area(.pageObjects): "⌘1", .area(.network): "⌘2", .area(.analytics): "⌘3", .area(.report): "⌘4",
            .refreshDevices: "⇧⌘R", .captureNow: "⌘K", .stream: "⌘E", .run: "⌘R",
            .palette: "⇧⌘P", .settings: "⌘,",
        ]
        for (id, atalho) in esperados {
            XCTAssertEqual(porID[id], atalho, id.rawValue)
        }
    }

    func testRegistroCobreAsAcoesPedidas() {
        let ids = Set(CommandRegistry.commands(in: contextoCheio()).map(\.id))
        let pedidas: [CommandID] = [
            .area(.network), .selectDevice("A1B2"), .startWDA, .proxy, .analytics, .screenRecording, .passive,
            .run, .save, .exportHAR, .search, .settings, .restartEngine, .inspector, .appearance,
        ]
        for id in pedidas { XCTAssertTrue(ids.contains(id), "falta \(id.rawValue)") }
    }

    func testPaletaNaoListaASiMesma() {
        let secoes = CommandSearch.sections(CommandRegistry.commands(in: contextoCheio()), query: "", recents: [])
        XCTAssertFalse(secoes.flatMap(\.commands).contains { $0.id == .palette })
        XCTAssertNotNil(CommandRegistry.command(.palette, in: contextoCheio()), "o menu ainda lê o item")
    }

    // MARK: - Busca aproximada

    func testBuscaIgnoraAcentoEMaiusculas() {
        XCTAssertEqual(primeiro("PROXY")?.id, .proxy)
        XCTAssertEqual(primeiro("proxi")?.id, .proxy, "um erro de digitação ainda acha")
        XCTAssertEqual(primeiro("configuracoes")?.id, .settings, "sinônimo sem acento")
        XCTAssertEqual(primeiro("preferências")?.id, .settings)
        XCTAssertEqual(primeiro("har")?.id, .exportHAR)
        XCTAssertEqual(primeiro("wda")?.id, .startWDA)
    }

    func testSinonimosDeVerbo() {
        XCTAssertEqual(primeiro("ligar proxy")?.id, .proxy)
        XCTAssertEqual(primeiro("executar")?.id, .run)
        XCTAssertEqual(primeiro("modo escuro")?.id, .appearance)
        XCTAssertEqual(primeiro("trocar aparelho iphone 15")?.id, .selectDevice("A1B2"))
        XCTAssertEqual(primeiro("procurar hierarquia")?.id, .search)
    }

    func testTodoTermoPrecisaCasar() {
        let secoes = CommandSearch.sections(CommandRegistry.commands(in: contextoCheio()), query: "proxy zzzz", recents: [])
        XCTAssertTrue(secoes.isEmpty)
    }

    func testSemBuscaAgrupaPorCategoria() {
        let secoes = CommandSearch.sections(CommandRegistry.commands(in: contextoCheio()), query: "  ", recents: [])
        XCTAssertEqual(secoes.first?.title, "Áreas")
        XCTAssertEqual(secoes.map(\.title), CommandCategory.allCases.map(\.rawValue).filter { t in secoes.contains { $0.title == t } })
    }

    // MARK: - Disponibilidade por contexto

    func testSemAparelhoAcaoSaiDesabilitadaComMotivo() {
        var c = contextoCheio()
        c.selectedDevice = nil
        let rodar = CommandRegistry.command(.run, in: c)
        XCTAssertEqual(rodar?.disabledReason, "Conecte um aparelho")
        XCTAssertEqual(CommandRegistry.command(.stream, in: c)?.disabledReason, "Conecte um aparelho")
        XCTAssertTrue(CommandRegistry.command(.area(.report), in: c)?.isEnabled == true, "o Relatório funciona sem aparelho")

        c.stepCount = 0
        XCTAssertEqual(CommandRegistry.command(.run, in: c)?.disabledReason, "Grave ao menos um passo",
                       "o motivo mais próximo da pessoa vem primeiro")
    }

    func testMotorParadoDesabilitaOQueDependeDele() {
        var c = contextoCheio()
        c.engineConnected = false
        XCTAssertEqual(CommandRegistry.command(.proxy, in: c)?.disabledReason, "O motor está parado")
        XCTAssertTrue(CommandRegistry.command(.restartEngine, in: c)?.isEnabled == true)
        XCTAssertTrue(CommandRegistry.command(.mirror, in: c)?.isEnabled == true, "mexer em painel não precisa de motor")

        c.engineRestarting = true
        XCTAssertEqual(CommandRegistry.command(.restartEngine, in: c)?.disabledReason, "O motor está reiniciando")
    }

    func testContextoMudaTituloEMotivo() {
        var c = contextoCheio()
        c.proxyRunning = true
        XCTAssertEqual(CommandRegistry.command(.proxy, in: c)?.title, "Parar Proxy")
        c.paletteActive = true
        XCTAssertNotNil(CommandRegistry.command(.appearance, in: c)?.disabledReason)
        c.platform = .android
        XCTAssertEqual(CommandRegistry.command(.startWDA, in: c)?.disabledReason, "Só no iOS")
        c.inspectorSuppressed = true
        XCTAssertEqual(CommandRegistry.command(.inspector, in: c)?.disabledReason, "O inspector volta ao conectar um aparelho")
        XCTAssertEqual(CommandRegistry.command(.selectDevice("7303D258"), in: c)?.disabledReason, "Já é o aparelho em uso")
    }

    /// Ação indisponível continua na busca: esconder faria a pessoa achar
    /// que ela não existe.
    func testIndisponivelAparecePelaBusca() {
        var c = contextoCheio()
        c.selectedDevice = nil
        let achado = primeiro("rodar automacao", c)
        XCTAssertEqual(achado?.id, .run)
        XCTAssertFalse(achado?.isEnabled ?? true)
    }

    // MARK: - Recentes

    func testRecentesSemRepeticaoComLimite() {
        let defaults = UserDefaults(suiteName: "mobaile.testes.\(UUID().uuidString)")!
        let recentes = CommandRecents(defaults: defaults)
        recentes.record(.proxy)
        recentes.record(.run)
        recentes.record(.proxy)
        XCTAssertEqual(recentes.ids, [.proxy, .run], "a mais recente primeiro, sem repetir")
        for id: CommandID in [.save, .exportHAR, .mirror, .zen, .settings] { recentes.record(id) }
        XCTAssertEqual(recentes.ids.count, CommandRecents.limit)
        XCTAssertEqual(recentes.ids.first, .settings)
        XCTAssertFalse(recentes.ids.contains(.run), "a mais antiga sai")
        XCTAssertEqual(CommandRecents(defaults: defaults).ids, recentes.ids, "sobrevive a reabrir")
    }

    func testRecentesNoTopoSemBuscaEDesempateComBusca() {
        let comandos = CommandRegistry.commands(in: contextoCheio())
        let secoes = CommandSearch.sections(comandos, query: "", recents: [.exportHAR, .run, CommandID(rawValue: "sumiu")])
        XCTAssertEqual(secoes.first?.title, "Recentes")
        XCTAssertEqual(secoes.first?.commands.map(\.id), [.exportHAR, .run], "id que não existe mais é ignorado")
        let resto = secoes.dropFirst().flatMap(\.commands).map(\.id)
        XCTAssertFalse(resto.contains(.run), "a recente não aparece duas vezes")

        // "limpar" casa igual com Limpar Tráfego, Limpar Eventos e Limpar
        // Passos; a usada por último vence o empate.
        let semRecente = CommandSearch.sections(comandos, query: "limpar", recents: [])
        let comRecente = CommandSearch.sections(comandos, query: "limpar", recents: [.clearAnalytics])
        XCTAssertNotEqual(semRecente.first?.commands.first?.id, .clearAnalytics)
        XCTAssertEqual(comRecente.first?.commands.first?.id, .clearAnalytics)
    }

    // MARK: - Execução

    @MainActor
    func testExecucaoDasAcoesDeInterface() throws {
        let estado = AppState()
        estado.selectedDevice = "7303D258"
        let sessao = EngineSession(state: estado, client: FakeEngine(respostas: try resultadosDasFixtures()))
        let executor = CommandPerformer(appState: estado, session: sessao)

        executor.perform(.area(.analytics))
        XCTAssertEqual(estado.workspaceTab, .analytics)
        executor.perform(.mirror)
        XCTAssertFalse(estado.mirrorVisible)
        executor.perform(.inspector)
        XCTAssertFalse(estado.inspectorVisible)
        executor.perform(.clearTraffic)
        XCTAssertEqual(estado.pendingClear, .network, "limpar passa pela confirmação, como o botão")
        executor.perform(.structure)
        XCTAssertTrue(estado.showingStructure)
        executor.perform(.palette)
        XCTAssertTrue(estado.commandPalettePresented)
    }

    func testAtalhoFaladoParaOVoiceOver() {
        XCTAssertEqual(CommandShortcut.cmdShift("p").spoken, "Shift Command P")
        XCTAssertEqual(CommandShortcut.cmd(",").display, "⌘,")
        let rodar = CommandRegistry.command(.run, in: CommandContext())!
        XCTAssertEqual(CommandPaletteRow.spokenLabel(rodar), "Rodar Automação, atalho Command R. Indisponível: Grave ao menos um passo")
    }
}
