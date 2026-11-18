import AppKit
import Foundation
import Observation
import os

/// Aviso e instalação de versão nova (LIB-4, ADR 0008). Com o app aberto, ele
/// pergunta ao GitHub a cada duas horas qual é o release mais recente. Se for
/// maior que o instalado, mostra uma faixa e uma notificação do macOS com
/// Atualizar. Atualizar baixa o zip, confere a assinatura Ed25519 e deixa a
/// versão pronta; Reiniciar e Atualizar troca o app e abre de novo
/// (`UpdateInstaller`). Nada é baixado nem trocado sem um clique.
///
/// A consulta é desligável em Ajustes › Geral, e erro de rede é silencioso: o
/// Mo baile continua funcionando offline.

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

    /// O zip do app no release (`MoBaile-X.Y.Z-macOS.zip`).
    var zipAsset: Asset? { assets.first { $0.name.hasSuffix("-macOS.zip") } }

    /// A assinatura Ed25519 do zip (`<zip>.sig`), publicada pelo workflow de
    /// release desde a 3.26.0. Sem ela, só o download manual.
    var signatureAsset: Asset? {
        guard let zip = zipAsset else { return nil }
        return assets.first { $0.name == zip.name + ".sig" }
    }

    /// O zip, para baixar pelo navegador; sem ele, a página do release.
    var downloadURL: URL { zipAsset?.browserDownloadURL ?? htmlURL }
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

/// Notificação do macOS para versão nova (`UpdateNotifier`).
@MainActor
protocol UpdateNotifying: AnyObject {
    func notifyAvailable(_ release: ReleaseInfo, installed: String, canInstall: Bool)
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
        /// Último release lido do GitHub, para decidir sem rede dentro do intervalo.
        static let lastRelease = "mobaile.update.lastRelease"
        /// De que endereço veio o `lastRelease`: um teste com `MOBAILE_UPDATE_URL`
        /// não deixa um release falso valendo para o app de uso diário.
        static let lastFeed = "mobaile.update.lastFeed"
        /// Tag que já virou notificação: uma por versão, não uma por consulta.
        static let notifiedTag = "mobaile.update.notifiedTag"
        #if DEBUG
        static let debugAutoInstall = "mobaile.update.debugAutoInstall"
        #endif
    }

    /// Resultado de "Buscar Atualizações…" pelo menu, para o alerta.
    enum ManualResult: Equatable {
        case available
        case upToDate(String)
        case failed
    }

    /// Onde está a instalação da versão nova.
    enum Phase: Equatable {
        case idle
        /// Fração de 0 a 1.
        case downloading(Double)
        /// Baixada e conferida; falta o "Reiniciar e Atualizar".
        case ready
        case installing
        /// Trocou o app, mas o ajudante que reabre não subiu.
        case installedNeedsRestart
        case failed(String)
    }

    /// Release maior que o instalado, ainda não ignorado nem adiado.
    private(set) var available: ReleaseInfo?
    private(set) var checking = false
    private(set) var phase: Phase = .idle

    var autoCheck: Bool {
        didSet { defaults.set(autoCheck, forKey: Keys.autoCheck) }
    }

    /// Intervalo mínimo entre consultas automáticas ao GitHub.
    static let checkInterval: TimeInterval = 2 * 60 * 60
    /// Quanto vale o "Lembrar Amanhã".
    static let snoozeInterval: TimeInterval = 24 * 60 * 60
    /// Com o app aberto, de quanto em quanto tempo vê se o intervalo já passou.
    static let tick: Duration = .seconds(15 * 60)

    /// Notificação do macOS. Fica nil nos testes e no `swift run`.
    var notifier: UpdateNotifying?
    /// Encerra o app depois de trocar o bundle; o ajudante abre o novo.
    ///
    /// Pelo runloop, e não direto: o `restartNow()` costuma rodar dentro de uma
    /// tarefa do MainActor (clique na notificação, fim do download). Ali, o
    /// `.terminateLater` do `AppDelegate` faz o AppKit esperar a resposta num
    /// laço que não drena a fila principal, e nem a resposta do encerramento
    /// ordenado nem a rede de segurança de 6 s chegam: o app trava (visto no
    /// teste de ponta a ponta de 18/11).
    var terminate: @MainActor () -> Void = {
        NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
    }
    /// Abre notas e download no navegador. Injetável para testes.
    var openURL: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }

    private static let log = Logger(subsystem: "com.qa.mobaile", category: "update")

    private let fetcher: ReleaseFetching
    private let defaults: UserDefaults
    private let current: AppVersion?
    private let now: () -> Date
    private let installer: UpdateInstalling?
    private let feedID: String
    private var prepared: PreparedUpdate?
    /// Tag em download ou pronta: uma consulta nova não troca o release no meio.
    private var installingTag: String?
    private var downloadTask: Task<Void, Never>?
    private var loop: Task<Void, Never>?

    init(
        fetcher: ReleaseFetching = GitHubReleaseFetcher(),
        defaults: UserDefaults = .standard,
        current: AppVersion? = AppVersion.installed,
        now: @escaping () -> Date = Date.init,
        installer: UpdateInstalling? = UpdateInstaller.forCurrentApp(),
        feedID: String = GitHubReleaseFetcher.configuredURL().absoluteString
    ) {
        self.fetcher = fetcher
        self.defaults = defaults
        self.current = current
        self.now = now
        self.installer = installer
        self.feedID = feedID
        autoCheck = defaults.object(forKey: Keys.autoCheck) as? Bool ?? true
    }

    var currentVersion: String { current?.description ?? "dev" }

    /// Por que a versão disponível não pode ser instalada com um clique; nil se pode.
    var inPlaceBlocker: String? {
        guard let available else { return nil }
        guard let installer else { return "Só o app empacotado se atualiza sozinho." }
        return installer.blocker(for: available)
    }

    private var busy: Bool {
        switch phase {
        case .downloading, .ready, .installing, .installedNeedsRestart: true
        case .idle, .failed: false
        }
    }

    // MARK: - Consulta

    /// Ao abrir o app: confere agora (se o intervalo passou) e depois a cada
    /// `tick`, enquanto o app estiver aberto. Chamar de novo não duplica.
    func startAutomaticChecks() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.checkIfDue()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard !Task.isCancelled else { return }
                await self?.checkIfDue()
            }
        }
    }

    func checkOnLaunch() async {
        await checkIfDue()
    }

    /// Consulta o GitHub se a última consulta passou do intervalo. Dentro dele,
    /// decide pelo último release guardado, sem rede: a faixa não some sozinha
    /// ao reabrir o app, e o "Lembrar Amanhã" vale um dia mesmo sem consulta.
    func checkIfDue() async {
        guard autoCheck, current != nil else { return }
        if let ultima = defaults.object(forKey: Keys.lastCheck) as? Date, now().timeIntervalSince(ultima) < Self.checkInterval {
            if available == nil, let guardado = cachedRelease() {
                apply(decide(guardado, manual: false), automatic: true)
            }
            return
        }
        await check(manual: false)
    }

    /// "Buscar Atualizações…": ignora o adiamento e a versão ignorada.
    @discardableResult
    func checkNow() async -> ManualResult {
        await check(manual: true)
    }

    private func cachedRelease() -> ReleaseInfo? {
        guard defaults.string(forKey: Keys.lastFeed) == feedID, let dados = defaults.data(forKey: Keys.lastRelease) else {
            return nil
        }
        return try? JSONDecoder().decode(ReleaseInfo.self, from: dados)
    }

    private func decide(_ remoto: ReleaseInfo, manual: Bool) -> UpdateDecision {
        UpdateDecision.decide(
            current: current, remote: remoto,
            ignoredTag: defaults.string(forKey: Keys.ignoredTag),
            snoozeUntil: defaults.object(forKey: Keys.snoozeUntil) as? Date,
            now: now(),
            manual: manual
        )
    }

    @discardableResult
    private func check(manual: Bool) async -> ManualResult {
        guard !checking else { return available == nil ? .upToDate(currentVersion) : .available }
        checking = true
        defer { checking = false }
        do {
            let remoto = try await fetcher.latest()
            Self.log.notice("consulta de versão: \(remoto.tagName, privacy: .public) publicada, \(self.currentVersion, privacy: .public) instalada")
            defaults.set(now(), forKey: Keys.lastCheck)
            defaults.set(try? JSONEncoder().encode(remoto), forKey: Keys.lastRelease)
            defaults.set(feedID, forKey: Keys.lastFeed)
            apply(decide(remoto, manual: manual), automatic: !manual)
            return available == nil ? .upToDate(currentVersion) : .available
        } catch {
            // Offline ou GitHub fora do ar: silêncio na conferência automática;
            // só o pedido pelo menu mostra a falha.
            Self.log.notice("consulta de versão falhou: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func apply(_ decisao: UpdateDecision, automatic: Bool) {
        switch decisao {
        case .available(let release):
            if busy {
                // Em download ou pronta: só volta a mostrar a mesma versão
                // (depois de um "Lembrar Amanhã"), sem trocar no meio.
                if release.tagName == installingTag { available = release }
                return
            }
            if case .failed = phase, available?.tagName != release.tagName { phase = .idle }
            available = release
            if automatic { notifyIfNew(release) }
            #if DEBUG
            if automatic, debugAutoInstall { update() }
            #endif
        case .none:
            guard !busy else { return }
            available = nil
            phase = .idle
        }
    }

    private func notifyIfNew(_ release: ReleaseInfo) {
        guard let notifier, defaults.string(forKey: Keys.notifiedTag) != release.tagName else { return }
        defaults.set(release.tagName, forKey: Keys.notifiedTag)
        notifier.notifyAvailable(release, installed: currentVersion, canInstall: inPlaceBlocker == nil)
    }

    // MARK: - Instalação

    /// "Atualizar" (faixa ou notificação): baixa e confere; se já estiver
    /// pronta, instala. Sem como instalar no lugar, abre o download.
    func update() {
        switch phase {
        case .ready:
            restartNow()
            return
        case .downloading, .installing, .installedNeedsRestart:
            return
        case .idle, .failed:
            break
        }
        guard let release = available else {
            // Clique na notificação com o app fechado: a consulta ainda não rodou.
            Task { if await checkNow() == .available { update() } }
            return
        }
        guard let installer, installer.blocker(for: release) == nil else {
            openDownloadPage()
            return
        }
        installingTag = release.tagName
        phase = .downloading(0)
        Self.log.notice("baixando \(release.tagName, privacy: .public)")
        let aviso: @Sendable (Double) -> Void = { [weak self] fracao in
            Task { @MainActor in self?.progress(fracao) }
        }
        downloadTask = Task { [weak self] in
            do {
                let pronto = try await installer.prepare(release, progress: aviso)
                self?.downloaded(pronto)
            } catch is CancellationError {
                self?.reset()
            } catch {
                self?.fail(error)
            }
        }
    }

    private func progress(_ fracao: Double) {
        if case .downloading = phase { phase = .downloading(min(max(fracao, 0), 1)) }
    }

    private func downloaded(_ pronto: PreparedUpdate) {
        guard case .downloading = phase else {
            // Cancelado enquanto terminava.
            try? FileManager.default.removeItem(at: pronto.workDir)
            return
        }
        prepared = pronto
        phase = .ready
        Self.log.notice("versão \(pronto.version.description, privacy: .public) baixada e conferida")
        #if DEBUG
        if debugAutoInstall { restartNow() }
        #endif
    }

    func cancelDownload() {
        guard case .downloading = phase else { return }
        downloadTask?.cancel()
        downloadTask = nil
        reset()
    }

    /// "Reiniciar e Atualizar": troca o app e encerra; o ajudante abre o novo.
    func restartNow() {
        guard case .ready = phase, let prepared, let installer else { return }
        phase = .installing
        do {
            try installer.install(prepared)
            Self.log.notice("app trocado pela \(prepared.version.description, privacy: .public); encerrando para reabrir")
            terminate()
        } catch UpdateInstallError.relaunchFailed {
            self.prepared = nil
            phase = .installedNeedsRestart
        } catch {
            try? FileManager.default.removeItem(at: prepared.workDir)
            self.prepared = nil
            installingTag = nil
            fail(error)
        }
    }

    func retry() {
        guard case .failed = phase else { return }
        phase = .idle
        update()
    }

    private func reset() {
        if let prepared { try? FileManager.default.removeItem(at: prepared.workDir) }
        prepared = nil
        installingTag = nil
        phase = .idle
    }

    private func fail(_ error: Error) {
        installingTag = nil
        let motivo = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        Self.log.error("atualização falhou: \(motivo, privacy: .public)")
        phase = .failed(motivo)
    }

    func openDownloadPage() {
        if let r = available, r.downloadURL.scheme == "https" { openURL(r.downloadURL) }
    }

    func openReleaseNotes() {
        if let r = available, r.htmlURL.scheme == "https" { openURL(r.htmlURL) }
    }

    func ignoreCurrent() {
        guard let available else { return }
        downloadTask?.cancel()
        downloadTask = nil
        reset()
        defaults.set(available.tagName, forKey: Keys.ignoredTag)
        self.available = nil
    }

    /// Some por um dia. Se a versão já estiver baixada, continua pronta.
    func snooze() {
        defaults.set(now().addingTimeInterval(Self.snoozeInterval), forKey: Keys.snoozeUntil)
        available = nil
    }

    #if DEBUG
    /// Teste de ponta a ponta sem clicar (docs/RELEASE.md): baixa e reinicia
    /// sozinho. Só existe em build de depuração; o app distribuído não tem isto.
    private var debugAutoInstall: Bool {
        ProcessInfo.processInfo.environment["MOBAILE_UPDATE_AUTOINSTALL"] == "1" || defaults.bool(forKey: Keys.debugAutoInstall)
    }
    #endif
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
