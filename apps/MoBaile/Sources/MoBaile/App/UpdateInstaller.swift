import Darwin
import Foundation

/// Atualização no lugar (ADR 0008): baixa o zip do release, confere a
/// assinatura Ed25519, descompacta no mesmo volume do app, valida o bundle novo
/// e, no "Reiniciar e Atualizar", troca o app e abre de novo.
///
/// Nada aqui roda sozinho: o `UpdateState` chama `prepare` quando a pessoa
/// clica em Atualizar e `install` quando ela clica em Reiniciar e Atualizar.

/// Uma atualização baixada, conferida e pronta para trocar o app.
struct PreparedUpdate: Equatable, Sendable {
    let version: AppVersion
    /// O `.app` extraído, no mesmo volume do app instalado (troca por rename).
    let newApp: URL
    /// Pasta temporária da atualização; o ajudante apaga depois de reabrir.
    let workDir: URL
}

enum UpdateInstallError: Error, Equatable, LocalizedError {
    /// Não dá para instalar no lugar; o texto diz por quê.
    case blocked(String)
    case download(String)
    case badSignature
    case invalidBundle(String)
    case replaceFailed(String)
    /// O app já foi trocado, mas o ajudante que reabre não subiu.
    case relaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let motivo): motivo
        case .download(let motivo): "O download falhou (\(motivo)). Confira a conexão e tente de novo."
        case .badSignature: "A assinatura do arquivo baixado não confere. Por segurança, nada foi instalado."
        case .invalidBundle(let motivo): "O arquivo baixado não é uma versão válida do Mo baile: \(motivo)."
        case .replaceFailed(let motivo): "Não deu para trocar o app: \(motivo)"
        case .relaunchFailed(let motivo): "O app foi atualizado, mas não abriu sozinho (\(motivo))."
        }
    }
}

protocol UpdateInstalling: Sendable {
    /// Por que esta atualização não pode ser instalada no lugar; nil se pode.
    func blocker(for release: ReleaseInfo) -> String?
    func prepare(_ release: ReleaseInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> PreparedUpdate
    func install(_ prepared: PreparedUpdate) throws
}

protocol UpdateDownloading: Sendable {
    func data(from url: URL) async throws -> Data
    func download(from url: URL, to destino: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

struct UpdateInstaller: UpdateInstalling {
    var bundleURL: URL
    var bundleID: String?
    var current: AppVersion?
    var publicKeys: [String] = UpdateSignature.publicKeys
    var downloader: UpdateDownloading = URLSessionDownloader()
    var verifyCodeSignature: @Sendable (URL) -> Bool = { UpdateInstaller.codeSignatureIsValid($0) }
    var relaunch: @Sendable (_ app: URL, _ cleanup: URL) throws -> Void = { try UpdateInstaller.spawnRelauncher(app: $0, cleanup: $1) }

    static func forCurrentApp() -> UpdateInstaller {
        UpdateInstaller(bundleURL: Bundle.main.bundleURL, bundleID: Bundle.main.bundleIdentifier, current: .installed)
    }

    /// Endereço aceito para baixar: HTTPS, ou HTTP só em loopback (teste local
    /// com `MOBAILE_UPDATE_URL`). A assinatura vale nos dois casos.
    static func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": return true
        case "http": return ["127.0.0.1", "localhost", "::1"].contains(url.host?.lowercased() ?? "")
        default: return false
        }
    }

    func blocker(for release: ReleaseInfo) -> String? {
        guard bundleURL.pathExtension == "app", current != nil, bundleID != nil else {
            return "Só o app empacotado se atualiza sozinho."
        }
        if bundleURL.path.contains("/AppTranslocation/") {
            return "Para atualizar com um clique, mova o Mo baile para a pasta Aplicativos e abra de novo."
        }
        let pasta = bundleURL.deletingLastPathComponent()
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: pasta.path), fm.isWritableFile(atPath: bundleURL.path) else {
            return "Sem permissão para trocar o app em \(pasta.path). Baixe o zip e troque à mão."
        }
        guard let zip = release.zipAsset, let sig = release.signatureAsset,
              Self.isAllowed(zip.browserDownloadURL), Self.isAllowed(sig.browserDownloadURL) else {
            return "Esta versão saiu sem a assinatura de atualização. Baixe o zip e troque à mão."
        }
        return nil
    }

    func prepare(_ release: ReleaseInfo, progress: @escaping @Sendable (Double) -> Void) async throws -> PreparedUpdate {
        if let motivo = blocker(for: release) { throw UpdateInstallError.blocked(motivo) }
        guard let nova = release.version, let zip = release.zipAsset, let sig = release.signatureAsset else {
            throw UpdateInstallError.blocked("Esta versão saiu sem a assinatura de atualização.")
        }
        let fm = FileManager.default
        // Mesmo volume do app: a troca final é um rename, sem cópia pela metade.
        let trabalho = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundleURL, create: true)
        do {
            let textoAssinatura = try await Self.semCancelamentoDeRede { try await downloader.data(from: sig.browserDownloadURL) }
            guard let assinatura = UpdateSignature.parse(String(decoding: textoAssinatura, as: UTF8.self)) else {
                throw UpdateInstallError.badSignature
            }
            // Nome fixo: o nome do asset vem da rede e não entra em caminho.
            let arquivo = trabalho.appendingPathComponent("atualizacao.zip")
            try await Self.semCancelamentoDeRede {
                try await downloader.download(from: zip.browserDownloadURL, to: arquivo, progress: progress)
            }
            try Task.checkCancellation()

            let dados = try Data(contentsOf: arquivo, options: .mappedIfSafe)
            guard UpdateSignature.isValid(signature: assinatura, for: dados, keys: publicKeys) else {
                throw UpdateInstallError.badSignature
            }

            let pasta = trabalho.appendingPathComponent("novo", isDirectory: true)
            guard (try? Self.run("/usr/bin/ditto", ["-x", "-k", arquivo.path, pasta.path])) == 0 else {
                throw UpdateInstallError.invalidBundle("não consegui descompactar o zip")
            }
            try? fm.removeItem(at: arquivo)
            let app = try validate(extractedIn: pasta, expected: nova)
            // A origem já foi conferida pela assinatura própria; sem isto, um zip
            // com quarentena faria o Gatekeeper barrar a abertura (ADR 0008).
            _ = try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
            try Task.checkCancellation()
            return PreparedUpdate(version: nova, newApp: app, workDir: trabalho)
        } catch {
            try? fm.removeItem(at: trabalho)
            throw error
        }
    }

    /// Confere o app extraído: um só `.app`, mesmo bundle id, a versão
    /// anunciada (e maior que a instalada), executável presente e assinatura
    /// de código íntegra.
    func validate(extractedIn pasta: URL, expected: AppVersion) throws -> URL {
        let itens = (try? FileManager.default.contentsOfDirectory(at: pasta, includingPropertiesForKeys: nil)) ?? []
        let apps = itens.filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else {
            throw UpdateInstallError.invalidBundle("o zip não tem exatamente um app")
        }
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            throw UpdateInstallError.invalidBundle("o app novo não tem Info.plist")
        }
        guard let id = info["CFBundleIdentifier"] as? String, id == bundleID else {
            throw UpdateInstallError.invalidBundle("o app do zip não é o Mo baile")
        }
        guard let texto = info["CFBundleShortVersionString"] as? String, let versao = AppVersion(texto), versao == expected else {
            throw UpdateInstallError.invalidBundle("o app do zip não é a versão \(expected)")
        }
        if let current, !(current < versao) {
            throw UpdateInstallError.invalidBundle("a versão do zip não é mais nova que a instalada")
        }
        guard let executavel = info["CFBundleExecutable"] as? String, !executavel.isEmpty, !executavel.contains("/"),
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/\(executavel)").path) else {
            throw UpdateInstallError.invalidBundle("o app novo não tem executável")
        }
        guard verifyCodeSignature(app) else {
            throw UpdateInstallError.invalidBundle("a assinatura de código do app novo não confere")
        }
        return app
    }

    func install(_ prepared: PreparedUpdate) throws {
        let fm = FileManager.default
        let anterior = prepared.workDir.appendingPathComponent("anterior.app")
        do {
            try fm.moveItem(at: bundleURL, to: anterior)
        } catch {
            throw UpdateInstallError.replaceFailed(Self.reason(error))
        }
        do {
            try fm.moveItem(at: prepared.newApp, to: bundleURL)
        } catch {
            // Devolve o app em uso ao lugar antes de avisar.
            try? fm.moveItem(at: anterior, to: bundleURL)
            throw UpdateInstallError.replaceFailed(Self.reason(error))
        }
        do {
            try relaunch(bundleURL, prepared.workDir)
        } catch {
            throw UpdateInstallError.relaunchFailed(Self.reason(error))
        }
    }

    // MARK: - Apoio

    private static func reason(_ error: Error) -> String {
        let ns = error as NSError
        let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? $0.code : nil }
        let semPermissao = ns.code == NSFileWriteNoPermissionError
            || (ns.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(ns.code))
            || posix.map { [Int(EPERM), Int(EACCES)].contains($0) } == true
        if semPermissao {
            return "o macOS não deixou. Libere o Mo baile em Ajustes do Sistema › Privacidade e Segurança › Gerenciamento de Apps, ou baixe o zip e troque à mão."
        }
        if let erro = error as? UpdateInstallError, let texto = erro.errorDescription { return texto }
        return ns.localizedDescription
    }

    /// O `URLSession` avisa cancelamento como `URLError(.cancelled)`; aqui ele
    /// vira `CancellationError`, e as demais falhas de rede, `.download`.
    private static func semCancelamentoDeRede<T>(_ corpo: () async throws -> T) async throws -> T {
        do {
            return try await corpo()
        } catch let erro as URLError {
            if erro.code == .cancelled || Task.isCancelled { throw CancellationError() }
            throw UpdateInstallError.download(erro.localizedDescription)
        }
    }

    @discardableResult
    static func run(_ executavel: String, _ argumentos: [String]) throws -> Int32 {
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: executavel)
        processo.arguments = argumentos
        processo.standardInput = FileHandle.nullDevice
        processo.standardOutput = FileHandle.nullDevice
        processo.standardError = FileHandle.nullDevice
        try processo.run()
        processo.waitUntilExit()
        return processo.terminationStatus
    }

    static func codeSignatureIsValid(_ app: URL) -> Bool {
        (try? run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])) == 0
    }

    /// Espera este processo sair (o encerramento ordenado desfaz o proxy do
    /// aparelho e pode levar alguns segundos), abre o app no mesmo caminho e
    /// apaga a pasta temporária com o app anterior.
    static let relaunchScript = """
    pid="$1"; app="$2"; lixo="$3"; n=0
    while /bin/kill -0 "$pid" 2>/dev/null; do
      case "$(/bin/ps -o stat= -p "$pid" 2>/dev/null)" in Z*) break ;; esac
      n=$((n + 1)); [ "$n" -ge 600 ] && break
      /bin/sleep 0.1
    done
    /usr/bin/open "$app"
    /bin/rm -rf "$lixo"
    """

    static func spawnRelauncher(app: URL, cleanup: URL) throws {
        try spawnDetached("/bin/sh", ["-c", relaunchScript, "mobaile-relaunch", String(getpid()), app.path, cleanup.path])
    }

    /// Sobe um processo que sobrevive ao app: grupo de processos próprio (o
    /// launchd encerra o grupo do app quando ele sai) e nenhum descritor herdado
    /// além de /dev/null (um pipe do motor herdado seguraria o motor vivo).
    static func spawnDetached(_ executavel: String, _ argumentos: [String]) throws {
        var atributos: posix_spawnattr_t?
        posix_spawnattr_init(&atributos)
        defer { posix_spawnattr_destroy(&atributos) }
        posix_spawnattr_setflags(&atributos, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&atributos, 0)

        var acoes: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&acoes)
        defer { posix_spawn_file_actions_destroy(&acoes) }
        posix_spawn_file_actions_addopen(&acoes, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&acoes, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&acoes, 2, "/dev/null", O_WRONLY, 0)

        let argv: [UnsafeMutablePointer<CChar>?] = ([executavel] + argumentos).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executavel, &acoes, &atributos, argv, environ)
        guard rc == 0 else { throw UpdateInstallError.relaunchFailed(String(cString: strerror(rc))) }
    }
}

/// Download pelo `URLSession`, com progresso lido do `Progress` da tarefa.
struct URLSessionDownloader: UpdateDownloading {
    func data(from url: URL) async throws -> Data {
        let (dados, resposta) = try await URLSession.shared.data(for: Self.request(url))
        try Self.check(resposta)
        return dados
    }

    func download(from url: URL, to destino: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let (temporario, resposta) = try await URLSession.shared.download(for: Self.request(url), delegate: ProgressObserver(progress))
        try Self.check(resposta)
        try? FileManager.default.removeItem(at: destino)
        try FileManager.default.moveItem(at: temporario, to: destino)
    }

    private static func request(_ url: URL) -> URLRequest {
        var pedido = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        pedido.setValue(EngineSession.clientName, forHTTPHeaderField: "User-Agent")
        return pedido
    }

    private static func check(_ resposta: URLResponse) throws {
        if let http = resposta as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateInstallError.download("o servidor respondeu \(http.statusCode)")
        }
    }
}

/// Lê o progresso da tarefa criada pelo `URLSession.download(for:delegate:)`.
private final class ProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observacao: NSKeyValueObservation?

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let aviso = onProgress
        observacao = task.progress.observe(\.fractionCompleted, options: [.new]) { progresso, _ in
            aviso(progresso.fractionCompleted)
        }
    }
}
