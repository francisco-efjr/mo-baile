import XCTest
@testable import MoBaile

/// Aviso de versão nova (LIB-4): comparação numérica, decisão pura, leitura do
/// JSON do GitHub e o estado com fetcher falso, sem rede.
@MainActor
final class UpdateCheckerTests: XCTestCase {

    // MARK: - AppVersion

    func testComparaPorNumeroENaoPorTexto() throws {
        XCTAssertLessThan(try XCTUnwrap(AppVersion("3.9.0")), try XCTUnwrap(AppVersion("3.10.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("3.23.0")), try XCTUnwrap(AppVersion("v3.24.0")))
        XCTAssertEqual(AppVersion("v3.23.0"), AppVersion("3.23.0"))
        XCTAssertEqual(AppVersion("3.23"), AppVersion("3.23.0"))
    }

    func testVersaoInvalidaViraNil() {
        for lixo in ["", "dev", "3..1", "3.x.0", "v", "-1.0.0", "1.2.3.4.5", "３.1.0"] {
            XCTAssertNil(AppVersion(lixo), lixo)
        }
    }

    // MARK: - UpdateDecision

    private let agora = Date(timeIntervalSince1970: 1_800_000_000)

    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false) -> ReleaseInfo {
        ReleaseInfo(tagName: tag, htmlURL: URL(string: "https://example.test/\(tag)")!, draft: draft, prerelease: prerelease)
    }

    func testSoAvisaVersaoMaiorPublicada() {
        let atual = AppVersion("3.23.0")
        XCTAssertEqual(UpdateDecision.decide(current: atual, remote: release("v3.24.0"), ignoredTag: nil, snoozeUntil: nil, now: agora),
                       .available(release("v3.24.0")))
        for tag in ["v3.23.0", "v3.21.0", "lixo"] {
            XCTAssertEqual(UpdateDecision.decide(current: atual, remote: release(tag), ignoredTag: nil, snoozeUntil: nil, now: agora), .none, tag)
        }
        XCTAssertEqual(UpdateDecision.decide(current: atual, remote: release("v4.0.0", draft: true), ignoredTag: nil, snoozeUntil: nil, now: agora), .none)
        XCTAssertEqual(UpdateDecision.decide(current: atual, remote: release("v4.0.0", prerelease: true), ignoredTag: nil, snoozeUntil: nil, now: agora), .none)
        XCTAssertEqual(UpdateDecision.decide(current: nil, remote: release("v4.0.0"), ignoredTag: nil, snoozeUntil: nil, now: agora), .none,
                       "build de desenvolvimento não confere")
    }

    func testIgnoradaEAdiadaSoValemNaConferenciaAutomatica() {
        let atual = AppVersion("3.23.0")
        let nova = release("v3.24.0")
        XCTAssertEqual(UpdateDecision.decide(current: atual, remote: nova, ignoredTag: "v3.24.0", snoozeUntil: nil, now: agora), .none)
        XCTAssertEqual(UpdateDecision.decide(current: atual, remote: release("v3.25.0"), ignoredTag: "v3.24.0", snoozeUntil: nil, now: agora),
                       .available(release("v3.25.0")), "uma versão mais nova que a ignorada volta a avisar")
        XCTAssertEqual(UpdateDecision.decide(current: atual, remote: nova, ignoredTag: nil, snoozeUntil: agora.addingTimeInterval(60), now: agora), .none)
        XCTAssertEqual(UpdateDecision.decide(current: atual, remote: nova, ignoredTag: nil, snoozeUntil: agora.addingTimeInterval(-1), now: agora),
                       .available(nova))
        XCTAssertEqual(UpdateDecision.decide(current: atual, remote: nova, ignoredTag: "v3.24.0", snoozeUntil: agora.addingTimeInterval(60), now: agora, manual: true),
                       .available(nova), "Buscar Atualizações… pelo menu não respeita adiamento nem ignorada")
    }

    // MARK: - JSON do GitHub

    func testLeOJSONDoReleasesLatest() throws {
        let json = """
        {"url":"https://api.github.com/x","tag_name":"v3.24.0","name":"Mo baile 3.24.0",
         "html_url":"https://github.com/francisco-efjr/mo-baile/releases/tag/v3.24.0",
         "draft":false,"prerelease":false,"body":"## [3.24.0]",
         "assets":[{"name":"MoBaile-3.24.0-macOS.zip.sha256","browser_download_url":"https://example.test/a.sha256"},
                   {"name":"MoBaile-3.24.0-macOS.zip","browser_download_url":"https://example.test/a.zip"}]}
        """
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
        XCTAssertEqual(release.version, AppVersion("3.24.0"))
        XCTAssertEqual(release.downloadURL.absoluteString, "https://example.test/a.zip")
        XCTAssertFalse(release.prerelease)

        let semZip = ReleaseInfo(tagName: "v1.0.0", htmlURL: URL(string: "https://example.test/pagina")!)
        XCTAssertEqual(semZip.downloadURL.absoluteString, "https://example.test/pagina", "sem zip, abre a página")
    }

    func testURLDeTesteVemDaVariavelDeAmbiente() {
        let defaults = UserDefaults(suiteName: "mobaile.testes.\(UUID().uuidString)")!
        XCTAssertEqual(GitHubReleaseFetcher.configuredURL(environment: [:], defaults: defaults), GitHubReleaseFetcher.defaultURL)
        defaults.set("http://127.0.0.1:8765/latest.json", forKey: UpdateState.Keys.feedURL)
        XCTAssertEqual(GitHubReleaseFetcher.configuredURL(environment: [:], defaults: defaults).absoluteString, "http://127.0.0.1:8765/latest.json")
        XCTAssertEqual(
            GitHubReleaseFetcher.configuredURL(environment: ["MOBAILE_UPDATE_URL": "http://127.0.0.1:9/x.json"], defaults: defaults).absoluteString,
            "http://127.0.0.1:9/x.json"
        )
    }

    // MARK: - UpdateState

    private struct FetcherFalso: ReleaseFetching {
        var resultado: Result<ReleaseInfo, Error>
        func latest() async throws -> ReleaseInfo { try resultado.get() }
    }

    private final class Contador: ReleaseFetching, @unchecked Sendable {
        var chamadas = 0
        let release: ReleaseInfo
        init(_ release: ReleaseInfo) { self.release = release }
        func latest() async throws -> ReleaseInfo { chamadas += 1; return release }
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "mobaile.testes.\(UUID().uuidString)")!
    }

    func testIgnorarPersisteEntreAberturas() async {
        let d = defaults()
        let estado = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.24.0"))), defaults: d, current: AppVersion("3.23.0"))
        await estado.checkOnLaunch()
        XCTAssertEqual(estado.available?.tagName, "v3.24.0")
        estado.ignoreCurrent()
        XCTAssertNil(estado.available)

        d.removeObject(forKey: UpdateState.Keys.lastCheck)
        let reaberto = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.24.0"))), defaults: d, current: AppVersion("3.23.0"))
        await reaberto.checkOnLaunch()
        XCTAssertNil(reaberto.available)
    }

    func testLembrarDepoisSomePorUmDia() async {
        let d = defaults()
        var relogio = agora
        let estado = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.24.0"))), defaults: d,
                                 current: AppVersion("3.23.0"), now: { relogio })
        await estado.checkNow()
        estado.snooze()
        XCTAssertNil(estado.available)

        relogio = agora.addingTimeInterval(UpdateState.snoozeInterval - 60)
        d.removeObject(forKey: UpdateState.Keys.lastCheck)
        await estado.checkOnLaunch()
        XCTAssertNil(estado.available, "ainda adiado")

        relogio = agora.addingTimeInterval(UpdateState.snoozeInterval + 60)
        d.removeObject(forKey: UpdateState.Keys.lastCheck)
        await estado.checkOnLaunch()
        XCTAssertEqual(estado.available?.tagName, "v3.24.0")
    }

    func testFaixaVoltaAoReabrirDentroDoIntervaloSemRede() async {
        let d = defaults()
        let contador = Contador(release("v3.24.0"))
        await UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0")).checkOnLaunch()
        let reaberto = UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0"))
        await reaberto.checkOnLaunch()
        XCTAssertEqual(contador.chamadas, 1, "dentro do intervalo, decide pelo release guardado")
        XCTAssertEqual(reaberto.available?.tagName, "v3.24.0", "a faixa não some sozinha ao reabrir")
    }

    func testLembrarAmanhaValeUmDiaMesmoComConsultasNoMeio() async {
        let d = defaults()
        var relogio = agora
        let contador = Contador(release("v3.24.0"))
        let estado = UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0"), now: { relogio })
        await estado.checkOnLaunch()
        relogio = agora.addingTimeInterval(3_600)
        estado.snooze()
        relogio = agora.addingTimeInterval(UpdateState.snoozeInterval - 60)
        await estado.checkOnLaunch()
        XCTAssertNil(estado.available)
        relogio = agora.addingTimeInterval(UpdateState.snoozeInterval + 3_600 + 60)
        await estado.checkOnLaunch()
        XCTAssertEqual(estado.available?.tagName, "v3.24.0", "passado um dia do clique, volta")
    }

    func testConfereNoMaximoUmaVezPorIntervaloENadaQuandoDesligado() async {
        let d = defaults()
        var relogio = agora
        let contador = Contador(release("v3.24.0"))
        let estado = UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0"), now: { relogio })
        await estado.checkOnLaunch()
        await estado.checkOnLaunch()
        XCTAssertEqual(contador.chamadas, 1)
        relogio = agora.addingTimeInterval(UpdateState.checkInterval - 60)
        await estado.checkIfDue()
        XCTAssertEqual(contador.chamadas, 1, "a conferência periódica respeita o intervalo")
        relogio = agora.addingTimeInterval(UpdateState.checkInterval + 60)
        await estado.checkIfDue()
        XCTAssertEqual(contador.chamadas, 2, "passado o intervalo, consulta de novo com o app aberto")

        let d2 = defaults()
        let contador2 = Contador(release("v3.24.0"))
        let desligado = UpdateState(fetcher: contador2, defaults: d2, current: AppVersion("3.23.0"))
        desligado.autoCheck = false
        await desligado.checkOnLaunch()
        XCTAssertEqual(contador2.chamadas, 0, "desligado em Ajustes, nenhuma requisição sai")
        XCTAssertEqual(d2.object(forKey: UpdateState.Keys.autoCheck) as? Bool, false)
    }

    func testFalhaDeRedeESilenciosaNaAberturaEAvisadaNoMenu() async {
        let estado = UpdateState(fetcher: FetcherFalso(resultado: .failure(URLError(.notConnectedToInternet))),
                                 defaults: defaults(), current: AppVersion("3.23.0"))
        await estado.checkOnLaunch()
        XCTAssertNil(estado.available)
        let manual = await estado.checkNow()
        XCTAssertEqual(manual, .failed)
        XCTAssertNotNil(UpdateAlert.message(.failed, installed: "3.23.0"))
        XCTAssertNil(UpdateAlert.message(.available, installed: "3.23.0"))
    }

    func testMenuDizQueEstaNaMaisRecente() async {
        let estado = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.21.0"))),
                                 defaults: defaults(), current: AppVersion("3.23.0"))
        let resultado = await estado.checkNow()
        XCTAssertEqual(resultado, .upToDate("3.23.0"))
        XCTAssertNil(estado.available)
    }

    // MARK: - Notificação e cache por endereço (3.26.0)

    private final class NotifierFalso: UpdateNotifying {
        var avisos: [String] = []
        var podiaInstalar: [Bool] = []
        func notifyAvailable(_ release: ReleaseInfo, installed: String, canInstall: Bool) {
            avisos.append(release.tagName)
            podiaInstalar.append(canInstall)
        }
    }

    func testNotificaUmaVezPorVersaoESoNaConsultaAutomatica() async {
        let d = defaults()
        let aviso = NotifierFalso()
        let estado = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.24.0"))), defaults: d,
                                 current: AppVersion("3.23.0"), installer: nil)
        estado.notifier = aviso
        await estado.checkOnLaunch()
        XCTAssertEqual(aviso.avisos, ["v3.24.0"])
        XCTAssertEqual(aviso.podiaInstalar, [false], "sem instalador, a notificação manda abrir o app")

        d.removeObject(forKey: UpdateState.Keys.lastCheck)
        let reaberto = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.24.0"))), defaults: d,
                                   current: AppVersion("3.23.0"), installer: nil)
        reaberto.notifier = aviso
        await reaberto.checkOnLaunch()
        XCTAssertEqual(aviso.avisos, ["v3.24.0"], "a mesma versão não notifica de novo")

        d.removeObject(forKey: UpdateState.Keys.lastCheck)
        let maisNova = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.25.0"))), defaults: d,
                                   current: AppVersion("3.23.0"), installer: nil)
        maisNova.notifier = aviso
        await maisNova.checkOnLaunch()
        XCTAssertEqual(aviso.avisos, ["v3.24.0", "v3.25.0"])

        let manual = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.26.0"))), defaults: defaults(),
                                 current: AppVersion("3.23.0"), installer: nil)
        manual.notifier = aviso
        await manual.checkNow()
        XCTAssertEqual(aviso.avisos.count, 2, "Buscar Atualizações… mostra a faixa, sem notificação")
    }

    func testReleaseGuardadoDeOutroEnderecoNaoVale() async {
        let d = defaults()
        let teste = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v9.0.0"))), defaults: d,
                                current: AppVersion("3.23.0"), feedID: "http://127.0.0.1:8765/latest.json")
        await teste.checkOnLaunch()
        XCTAssertEqual(teste.available?.tagName, "v9.0.0")

        let contador = Contador(release("v3.21.0"))
        let diario = UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0"),
                                 feedID: GitHubReleaseFetcher.defaultURL.absoluteString)
        await diario.checkOnLaunch()
        XCTAssertNil(diario.available, "o release falso de um teste local não aparece no app de uso diário")
    }

    func testAssetDaAssinaturaAcompanhaOZip() {
        let zip = ReleaseInfo.Asset(name: "MoBaile-3.26.0-macOS.zip", browserDownloadURL: URL(string: "https://example.test/a.zip")!)
        let sig = ReleaseInfo.Asset(name: "MoBaile-3.26.0-macOS.zip.sig", browserDownloadURL: URL(string: "https://example.test/a.sig")!)
        let outra = ReleaseInfo.Asset(name: "MoBaile-3.25.0-macOS.zip.sig", browserDownloadURL: URL(string: "https://example.test/b.sig")!)
        let pagina = URL(string: "https://example.test/r")!
        XCTAssertEqual(ReleaseInfo(tagName: "v3.26.0", htmlURL: pagina, assets: [sig, zip]).signatureAsset, sig)
        XCTAssertNil(ReleaseInfo(tagName: "v3.26.0", htmlURL: pagina, assets: [zip]).signatureAsset)
        XCTAssertNil(ReleaseInfo(tagName: "v3.26.0", htmlURL: pagina, assets: [zip, outra]).signatureAsset,
                     "a assinatura precisa ser do mesmo zip")
    }

    // MARK: - Instalação pelo estado (instalador falso)

    private final class InstaladorFalso: UpdateInstalling, @unchecked Sendable {
        var bloqueio: String?
        var preparo: Result<PreparedUpdate, Error> = .success(PreparedUpdate(
            version: AppVersion("3.24.0")!, newApp: URL(fileURLWithPath: "/tmp/novo.app"), workDir: URL(fileURLWithPath: "/tmp/mobaile-nao-existe")
        ))
        var esperarCancelamento = false
        var troca: Error?
        var instalados = 0

        func blocker(for release: ReleaseInfo) -> String? { bloqueio }

        func prepare(_ release: ReleaseInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> PreparedUpdate {
            progress(0.5)
            if esperarCancelamento {
                try await Task.sleep(for: .seconds(30))
            }
            return try preparo.get()
        }

        func install(_ prepared: PreparedUpdate) throws {
            if let troca { throw troca }
            instalados += 1
        }
    }

    private func esperar(_ condicao: () -> Bool, _ mensagem: String = "") async {
        for _ in 0..<300 where !condicao() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condicao(), mensagem)
    }

    private func estadoComVersaoNova(_ instalador: InstaladorFalso) async -> UpdateState {
        let estado = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.24.0"))), defaults: defaults(),
                                 current: AppVersion("3.23.0"), installer: instalador)
        estado.openURL = { _ in XCTFail("não devia abrir o navegador") }
        await estado.checkOnLaunch()
        return estado
    }

    func testAtualizarBaixaEReiniciarTrocaEEncerra() async {
        let instalador = InstaladorFalso()
        let estado = await estadoComVersaoNova(instalador)
        var encerrou = false
        estado.terminate = { encerrou = true }

        estado.update()
        await esperar({ estado.phase == .ready }, "baixada e conferida, fica pronta")
        XCTAssertFalse(encerrou, "baixar não fecha o app")

        estado.restartNow()
        XCTAssertEqual(instalador.instalados, 1)
        XCTAssertTrue(encerrou)
        XCTAssertEqual(estado.phase, .installing)
    }

    func testAtualizarComVersaoProntaInstala() async {
        let instalador = InstaladorFalso()
        let estado = await estadoComVersaoNova(instalador)
        var encerrou = false
        estado.terminate = { encerrou = true }
        estado.update()
        await esperar { estado.phase == .ready }
        estado.update()
        XCTAssertTrue(encerrou, "o Atualizar da notificação com a versão pronta instala")
    }

    func testFalhaNaTrocaMostraOMotivoESegueAberto() async {
        let instalador = InstaladorFalso()
        instalador.troca = UpdateInstallError.replaceFailed("sem permissão")
        let estado = await estadoComVersaoNova(instalador)
        estado.terminate = { XCTFail("não pode fechar se a troca falhou") }
        estado.update()
        await esperar { estado.phase == .ready }
        estado.restartNow()
        XCTAssertEqual(estado.phase, .failed(UpdateInstallError.replaceFailed("sem permissão").errorDescription!))
        XCTAssertEqual(estado.available?.tagName, "v3.24.0", "a faixa continua, com Baixar e Tentar de Novo")
    }

    func testAjudanteQueNaoSobePedeParaFecharEAbrir() async {
        let instalador = InstaladorFalso()
        instalador.troca = UpdateInstallError.relaunchFailed("x")
        let estado = await estadoComVersaoNova(instalador)
        estado.terminate = { XCTFail("sem ajudante, não fecha sozinho") }
        estado.update()
        await esperar { estado.phase == .ready }
        estado.restartNow()
        XCTAssertEqual(estado.phase, .installedNeedsRestart)
    }

    func testDownloadQueFalhaPermiteTentarDeNovo() async {
        let instalador = InstaladorFalso()
        instalador.preparo = .failure(UpdateInstallError.badSignature)
        let estado = await estadoComVersaoNova(instalador)
        estado.update()
        await esperar { if case .failed = estado.phase { true } else { false } }
        XCTAssertEqual(estado.phase, .failed(UpdateInstallError.badSignature.errorDescription!))

        instalador.preparo = .success(PreparedUpdate(version: AppVersion("3.24.0")!, newApp: URL(fileURLWithPath: "/tmp/n.app"),
                                                     workDir: URL(fileURLWithPath: "/tmp/mobaile-nao-existe")))
        estado.retry()
        await esperar { estado.phase == .ready }
    }

    func testCancelarVoltaAoInicio() async {
        let instalador = InstaladorFalso()
        instalador.esperarCancelamento = true
        let estado = await estadoComVersaoNova(instalador)
        estado.update()
        await esperar({ estado.phase == .downloading(0.5) }, "o progresso chega à faixa")
        estado.cancelDownload()
        XCTAssertEqual(estado.phase, .idle)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(estado.phase, .idle, "o fim da tarefa cancelada não muda a fase")
    }

    func testSemComoInstalarNoLugarAbreODownload() async {
        let instalador = InstaladorFalso()
        instalador.bloqueio = "Mova o app."
        let estado = UpdateState(fetcher: FetcherFalso(resultado: .success(release("v3.24.0"))), defaults: defaults(),
                                 current: AppVersion("3.23.0"), installer: instalador)
        var aberto: URL?
        estado.openURL = { aberto = $0 }
        await estado.checkOnLaunch()
        XCTAssertEqual(estado.inPlaceBlocker, "Mova o app.")
        estado.update()
        XCTAssertEqual(aberto?.absoluteString, "https://example.test/v3.24.0")
        XCTAssertEqual(estado.phase, .idle)
    }

    func testConsultaNovaNaoTrocaOReleaseNoMeioDoDownload() async {
        let instalador = InstaladorFalso()
        instalador.esperarCancelamento = true
        let d = defaults()
        var remoto = release("v3.24.0")
        var relogio = agora
        let estado = UpdateState(fetcher: FetcherVariavel { remoto }, defaults: d, current: AppVersion("3.23.0"),
                                 now: { relogio }, installer: instalador)
        await estado.checkOnLaunch()
        estado.update()
        await esperar { estado.phase == .downloading(0.5) }
        remoto = release("v3.25.0")
        relogio = agora.addingTimeInterval(UpdateState.checkInterval + 60)
        await estado.checkIfDue()
        XCTAssertEqual(estado.available?.tagName, "v3.24.0")
        estado.cancelDownload()
    }

    private struct FetcherVariavel: ReleaseFetching, @unchecked Sendable {
        let fonte: () -> ReleaseInfo
        func latest() async throws -> ReleaseInfo { fonte() }
    }

    func testTextosDaFaixaENotificacao() {
        let r = release("v3.26.0")
        XCTAssertEqual(UpdateBannerView.title(r), "Versão 3.26.0 disponível")
        XCTAssertEqual(UpdateBannerView.title(r, phase: .ready), "Versão 3.26.0 pronta para instalar")
        XCTAssertEqual(UpdateBannerView.detail(installed: "3.25.0", phase: .downloading(0.424), blocker: nil),
                       "42% · dá para continuar usando o app enquanto baixa.")
        XCTAssertTrue(UpdateBannerView.detail(installed: "3.25.0", phase: .idle, blocker: "Mova o app.").hasSuffix("Mova o app."))
        let (titulo, corpo) = UpdateNotifier.content(r, installed: "3.25.0", canInstall: true)
        XCTAssertEqual(titulo, "Mo baile 3.26.0 disponível")
        XCTAssertTrue(corpo.contains("Atualizar"))
    }
}
