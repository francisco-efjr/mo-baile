import AppKit
import Foundation
import Observation

/// Aviso de versão nova (LIB-4). O app pergunta ao GitHub qual é o release
/// mais recente e, se for maior que o instalado, mostra uma faixa discreta com
/// Ver Novidades, Baixar, Lembrar Depois e Ignorar Esta Versão. Não baixa nem
/// troca nada sozinho: a atualização no lugar só vale a pena com Developer ID
/// (`docs/melhorias/2026-11-16-liberacao/revisao/distribuicao.md`, PROP-1).
///
/// É a única chamada de rede do app. Fica desligável em Ajustes › Geral, e
/// erro de rede é silencioso: o Mo baile continua funcionando offline.

/// Versão `X.Y.Z` comparável por número: 3.9.0 < 3.10.0. Aceita o `v` da tag.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    init?(_ texto: String) {
        var limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpo.hasPrefix("v") || limpo.hasPrefix("V") { limpo.removeFirst() }
        let pedacos = limpo.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pedacos.count) else { return nil }
        var numeros: [Int] = []
        for pedaco in pedacos {
            guard !pedaco.isEmpty, pedaco.allSatisfy(\.isASCII), let n = Int(pedaco), n >= 0 else { return nil }
            numeros.append(n)
        }
        parts = numeros
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let n = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<n {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    /// A versão deste app (`CFBundleShortVersionString`). `nil` rodando pelo
    /// `swift run`, sem Info.plist: build de desenvolvimento não confere.
    static var installed: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }
}

/// O que interessa de `GET /repos/{owner}/{repo}/releases/latest`.
struct ReleaseInfo: Codable, Equatable, Sendable {
    struct Asset: Codable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body, draft, prerelease, assets
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try c.decode(String.self, forKey: .tagName)
        htmlURL = try c.decode(URL.self, forKey: .htmlURL)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try c.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try c.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    init(tagName: String, htmlURL: URL, body: String? = nil, draft: Bool = false, prerelease: Bool = false, assets: [Asset] = []) {
        self.tagName = tagName
        self.htmlURL = htmlURL
        self.body = body
        self.draft = draft
        self.prerelease = prerelease
        self.assets = assets
    }

    var version: AppVersion? { AppVersion(tagName) }

    /// O zip do app no release (`MoBaile-X.Y.Z-macOS.zip`); sem ele, a página.
    var downloadURL: URL {
        assets.first { $0.name.hasSuffix("-macOS.zip") }?.browserDownloadURL ?? htmlURL
    }
}

/// Decisão pura, testável sem rede nem relógio de verdade.
enum UpdateDecision: Equatable {
    case none
    case available(ReleaseInfo)

    static func decide(
        current: AppVersion?,
        remote: ReleaseInfo,
        ignoredTag: String?,
        snoozeUntil: Date?,
        now: Date,
        manual: Bool = false
    ) -> UpdateDecision {
        guard let current, let nova = remote.version, !remote.draft, !remote.prerelease, current < nova else {
            return .none
        }
        if !manual {
            if let ignoredTag, AppVersion(ignoredTag) == nova { return .none }
            if let snoozeUntil, now < snoozeUntil { return .none }
        }
        return .available(remote)
    }
}

protocol ReleaseFetching: Sendable {
    func latest() async throws -> ReleaseInfo
}

/// Busca o release mais recente sem token: o repositório é público.
struct GitHubReleaseFetcher: ReleaseFetching {
    static let defaultURL = URL(string: "https://api.github.com/repos/francisco-efjr/mo-baile/releases/latest")!

    /// `MOBAILE_UPDATE_URL` (para testar com um JSON em 127.0.0.1), depois o
    /// `UserDefaults` `mobaile.update.feedURL`, depois o GitHub.
    static func configuredURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> URL {
        if let texto = environment["MOBAILE_UPDATE_URL"], let url = URL(string: texto), url.scheme != nil { return url }
        if let texto = defaults.string(forKey: UpdateState.Keys.feedURL), let url = URL(string: texto), url.scheme != nil { return url }
        return defaultURL
    }

    var url: URL = GitHubReleaseFetcher.configuredURL()
    var session: URLSession = .shared

    func latest() async throws -> ReleaseInfo {
        var pedido = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        pedido.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        pedido.setValue(EngineSession.clientName, forHTTPHeaderField: "User-Agent")
        let (dados, resposta) = try await session.data(for: pedido)
        if let http = resposta as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ReleaseInfo.self, from: dados)
    }
}

/// Estado do aviso de versão, injetado pelo ambiente como o `AppState`.
@MainActor
@Observable
final class UpdateState {
    enum Keys {
        static let autoCheck = "mobaile.update.autoCheck"
        static let ignoredTag = "mobaile.update.ignoredTag"
        static let snoozeUntil = "mobaile.update.snoozeUntil"
        static let lastCheck = "mobaile.update.lastCheck"
        static let feedURL = "mobaile.update.feedURL"
        /// Último release lido do GitHub, para decidir sem rede dentro das 24 h.
        static let lastRelease = "mobaile.update.lastRelease"
    }

    /// Resultado de "Buscar Atualizações…" pelo menu, para o alerta.
    enum ManualResult: Equatable {
        case available
        case upToDate(String)
        case failed
    }

    /// Release maior que o instalado, ainda não ignorado nem adiado.
    private(set) var available: ReleaseInfo?
    private(set) var checking = false

    var autoCheck: Bool {
        didSet { defaults.set(autoCheck, forKey: Keys.autoCheck) }
    }

    /// Intervalo mínimo entre conferências automáticas.
    static let interval: TimeInterval = 24 * 60 * 60

    private let fetcher: ReleaseFetching
    private let defaults: UserDefaults
    private let current: AppVersion?
    private let now: () -> Date

    init(
        fetcher: ReleaseFetching = GitHubReleaseFetcher(),
        defaults: UserDefaults = .standard,
        current: AppVersion? = AppVersion.installed,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetcher = fetcher
        self.defaults = defaults
        self.current = current
        self.now = now
        autoCheck = defaults.object(forKey: Keys.autoCheck) as? Bool ?? true
    }

    var currentVersion: String { current?.description ?? "dev" }

    /// Ao abrir o app: no máximo uma vez a cada 24 h, se estiver ligado.
    func checkOnLaunch() async {
        guard autoCheck, current != nil else { return }
        if let ultima = defaults.object(forKey: Keys.lastCheck) as? Date, now().timeIntervalSince(ultima) < Self.interval {
            // Dentro das 24 h: decide pelo último release guardado, sem rede.
            // Assim a faixa não some sozinha ao reabrir o app, e o "Lembrar
            // Amanhã" vale um dia, e não até a próxima consulta.
            if let dados = defaults.data(forKey: Keys.lastRelease),
               let guardado = try? JSONDecoder().decode(ReleaseInfo.self, from: dados) {
                apply(UpdateDecision.decide(
                    current: current, remote: guardado,
                    ignoredTag: defaults.string(forKey: Keys.ignoredTag),
                    snoozeUntil: defaults.object(forKey: Keys.snoozeUntil) as? Date,
                    now: now()
                ))
            }
            return
        }
        await check(manual: false)
    }

    private func apply(_ decisao: UpdateDecision) {
        if case .available(let release) = decisao { available = release } else { available = nil }
    }

    /// "Buscar Atualizações…": ignora o adiamento e a versão ignorada.
    @discardableResult
    func checkNow() async -> ManualResult {
        await check(manual: true)
    }

    func ignoreCurrent() {
        guard let available else { return }
        defaults.set(available.tagName, forKey: Keys.ignoredTag)
        self.available = nil
    }

    func snooze() {
        defaults.set(now().addingTimeInterval(Self.interval), forKey: Keys.snoozeUntil)
        available = nil
    }

    @discardableResult
    private func check(manual: Bool) async -> ManualResult {
        guard !checking else { return available == nil ? .upToDate(currentVersion) : .available }
        checking = true
        defer { checking = false }
        do {
            let remoto = try await fetcher.latest()
            defaults.set(now(), forKey: Keys.lastCheck)
            defaults.set(try? JSONEncoder().encode(remoto), forKey: Keys.lastRelease)
            let decisao = UpdateDecision.decide(
                current: current,
                remote: remoto,
                ignoredTag: defaults.string(forKey: Keys.ignoredTag),
                snoozeUntil: defaults.object(forKey: Keys.snoozeUntil) as? Date,
                now: now(),
                manual: manual
            )
            switch decisao {
            case .available(let release):
                available = release
                return .available
            case .none:
                available = nil
                return .upToDate(currentVersion)
            }
        } catch {
            // Offline ou GitHub fora do ar: silêncio na conferência automática;
            // só o pedido pelo menu mostra a falha.
            return .failed
        }
    }
}

/// Alerta do "Buscar Atualizações…" quando não há faixa a mostrar.
@MainActor
enum UpdateAlert {
    static func message(_ resultado: UpdateState.ManualResult, installed: String) -> (String, String)? {
        switch resultado {
        case .available:
            return nil
        case .upToDate:
            return ("Você está na versão mais recente", "O Mo baile \(installed) é a versão mais nova publicada.")
        case .failed:
            return ("Não deu para buscar atualizações",
                    "Sem conexão com o GitHub agora. O Mo baile continua funcionando; tente de novo mais tarde.")
        }
    }

    static func show(_ resultado: UpdateState.ManualResult, installed: String) {
        guard let (titulo, texto) = message(resultado, installed: installed) else { return }
        let alerta = NSAlert()
        alerta.messageText = titulo
        alerta.informativeText = texto
        alerta.alertStyle = resultado == .failed ? .warning : .informational
        alerta.runModal()
    }
}
