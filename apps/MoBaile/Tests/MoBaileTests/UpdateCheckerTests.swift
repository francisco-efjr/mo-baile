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

        relogio = agora.addingTimeInterval(UpdateState.interval - 60)
        d.removeObject(forKey: UpdateState.Keys.lastCheck)
        await estado.checkOnLaunch()
        XCTAssertNil(estado.available, "ainda adiado")

        relogio = agora.addingTimeInterval(UpdateState.interval + 60)
        d.removeObject(forKey: UpdateState.Keys.lastCheck)
        await estado.checkOnLaunch()
        XCTAssertEqual(estado.available?.tagName, "v3.24.0")
    }

    func testFaixaVoltaAoReabrirDentroDoDiaSemRede() async {
        let d = defaults()
        let contador = Contador(release("v3.24.0"))
        await UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0")).checkOnLaunch()
        let reaberto = UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0"))
        await reaberto.checkOnLaunch()
        XCTAssertEqual(contador.chamadas, 1, "dentro das 24 h, decide pelo release guardado")
        XCTAssertEqual(reaberto.available?.tagName, "v3.24.0", "a faixa não some sozinha ao reabrir")
    }

    func testLembrarAmanhaValeUmDiaSemNovaConsulta() async {
        let d = defaults()
        var relogio = agora
        let contador = Contador(release("v3.24.0"))
        let estado = UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0"), now: { relogio })
        await estado.checkOnLaunch()
        relogio = agora.addingTimeInterval(3_600)
        estado.snooze()
        relogio = agora.addingTimeInterval(UpdateState.interval - 60)
        await estado.checkOnLaunch()
        XCTAssertNil(estado.available)
        relogio = agora.addingTimeInterval(UpdateState.interval + 3_600 + 60)
        await estado.checkOnLaunch()
        XCTAssertEqual(estado.available?.tagName, "v3.24.0", "passado um dia do clique, volta")
    }

    func testConfereNoMaximoUmaVezPorDiaENadaQuandoDesligado() async {
        let d = defaults()
        let contador = Contador(release("v3.24.0"))
        let estado = UpdateState(fetcher: contador, defaults: d, current: AppVersion("3.23.0"))
        await estado.checkOnLaunch()
        await estado.checkOnLaunch()
        XCTAssertEqual(contador.chamadas, 1)

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
}
