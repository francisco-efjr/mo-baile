import Foundation

/// Descobre onde estao o Python e o codigo do motor.
///
/// Duas situacoes precisam funcionar sem configuracao manual:
/// rodando do codigo-fonte (desenvolvimento) e dentro do bundle `.app`
/// (distribuicao). A busca abaixo cobre as duas, na ordem do mais especifico.
enum EngineLocator {
    /// Permite apontar um ambiente proprio sem recompilar.
    private static let pythonOverrideKey = "MOBAILE_PYTHON"
    private static let sourceOverrideKey = "MOBAILE_ENGINE_SRC"

    static func resolve() throws -> EngineConfiguration {
        let python = try locatePython()
        let source = try locateEngineSource()
        return EngineConfiguration(pythonURL: python, sourcePath: source)
    }

    // MARK: - Python

    /// Versão mínima e módulos que o motor importa ao subir
    /// (`engine/pyproject.toml`: `requires-python` e `dependencies`).
    static let minimumPython = (major: 3, minor: 10)
    static let requiredModules = [("PIL", "Pillow"), ("requests", "requests")]

    /// Python só do Mo baile, em `~/Library/Application Support/Mo baile/python`.
    /// O mesmo caminho de `tools/setup/instalar-mac.sh` e de
    /// `tools/verify_native_app.sh`: se mudar aqui, muda lá.
    static var appPython: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mo baile/python/bin/python3")
    }

    /// Ordem de busca, do mais específico ao mais genérico. A mesma de
    /// `tools/verify_native_app.sh`: se mudar aqui, muda lá.
    static func pythonCandidates(repositoryRoot root: URL? = repositoryRoot()) -> [String] {
        var candidates: [String] = []
        // Ambiente virtual do proprio repositorio vem primeiro: e onde as
        // dependencias do motor estao instaladas em desenvolvimento.
        if let root {
            candidates.append(root.appendingPathComponent(".venv/bin/python3").path)
        }
        // O Python do Mo baile, criado pela tela Início
        // (`tools/setup/instalar-mac.sh python`). Vem antes dos do sistema:
        // quem o criou quer que o app use ele.
        candidates.append(appPython.path)
        candidates += [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        return candidates
    }

    private static func locatePython() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        // Quem aponta MOBAILE_PYTHON escolheu de propósito: não é testado.
        if let override = environment[pythonOverrideKey], isExecutable(override) {
            return URL(fileURLWithPath: override)
        }
        return try selectPython(from: pythonCandidates(), isExecutable: isExecutable, probe: { PythonProbe.cached($0) })
    }

    /// O primeiro candidato executável que passa na sonda (PY-1).
    ///
    /// Antes valia o primeiro `python3` executável. O `/usr/bin/python3` 3.9
    /// sem Pillow era aceito, o motor morria ao importar e o app entrava no
    /// laço de reinício (PB7). Agora cada candidato é testado, na mesma ordem.
    static func selectPython(
        from candidates: [String],
        isExecutable: (String) -> Bool,
        probe: (String) -> PythonProbe.Result
    ) throws -> URL {
        var achados: [String] = []
        for path in candidates where isExecutable(path) {
            let resultado = probe(path)
            if resultado.isUsable { return URL(fileURLWithPath: path) }
            achados.append("\(path) (\(resultado.reason))")
        }
        throw EngineError.pythonUnsuitable(unsuitableMessage(found: achados))
    }

    /// Começo da mensagem de Python que não serve. A tela Início reconhece
    /// por ele que o motor está parado por falta de Python, e não por outro motivo.
    static let unsuitablePrefix = "O motor precisa do Python"

    static func isPythonProblem(_ mensagem: String?) -> Bool {
        mensagem?.hasPrefix(unsuitablePrefix) ?? false
    }

    /// Erro que diz o que houve, o que foi achado e o que fazer.
    static func unsuitableMessage(found: [String]) -> String {
        let versao = "\(minimumPython.major).\(minimumPython.minor)"
        let pacotes = requiredModules.map(\.1).joined(separator: " ")
        var texto = "\(unsuitablePrefix) \(versao) ou mais novo com \(requiredModules.map(\.1).joined(separator: " e ")). "
        if found.isEmpty {
            texto += "Nenhum Python 3 foi encontrado. "
        } else {
            texto += "Nenhum dos encontrados serve: \(found.joined(separator: "; ")). "
        }
        // `pip install` direto no Python do Homebrew é recusado (PEP 668): o
        // caminho que funciona é o Python só do Mo baile, que a tela Início cria.
        texto += "Na tela Início, use Instalar no Terminal…: ele cria um Python só do Mo baile com \(pacotes). "
            + "Ou defina \(pythonOverrideKey) com o caminho de um Python que já tenha os dois. "
            + "Depois, use Reiniciar Motor."
        return texto
    }

    // MARK: - Codigo do motor

    private static func locateEngineSource() throws -> String {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment[sourceOverrideKey], isDirectory(override) {
            return override
        }

        var candidates: [String] = []
        // Dentro do bundle: Contents/Resources/engine/src.
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("engine/src").path)
        }
        if let root = repositoryRoot() {
            candidates.append(root.appendingPathComponent("engine/src").path)
        }

        for path in candidates where isDirectory(path + "/mobaile") {
            return path
        }
        throw EngineError.engineNotFound(
            "Codigo do motor nao encontrado. Defina \(sourceOverrideKey) apontando para engine/src."
        )
    }

    /// Sobe a arvore ate achar a raiz do repositorio (a que contem `engine/`).
    static func repositoryRoot() -> URL? {
        var directory = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if isDirectory(directory.appendingPathComponent("engine/src/mobaile").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        // Fallback para `swift run`, em que o binario fica em .build/.
        var working = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            if isDirectory(working.appendingPathComponent("engine/src/mobaile").path) {
                return working
            }
            working = working.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: - Utilidades

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}

// MARK: - Sonda do Python

/// Testa um interpretador antes de o motor depender dele (PY-1).
///
/// Roda um `python3 -c` curto que informa a versão e os módulos ausentes, com
/// prazo de 3 s. O Python que serve fica em cache por caminho: a sonda roda na
/// primeira subida e a supervisão não paga de novo. Falha não fica em cache, e
/// o Reiniciar Motor limpa tudo (R-02).
enum PythonProbe {
    struct Result: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case usable
            case tooOld
            case missingModules([String])
            case failed(String)
        }

        var kind: Kind
        var version: String?

        var isUsable: Bool { kind == .usable }

        /// Por que não serve, em texto curto para a mensagem de erro.
        var reason: String {
            let v = version.map { "Python \($0)" } ?? "Python"
            switch kind {
            case .usable: return "\(v), ok"
            case .tooOld: return "\(v), antigo demais"
            case .missingModules(let faltam): return "\(v), sem \(faltam.joined(separator: " e "))"
            case .failed(let motivo): return motivo
            }
        }
    }

    static let timeout: TimeInterval = 3

    /// O script imprime uma linha: `OK 3.12.1`, `OLD 3.9.6` ou
    /// `MISSING 3.11.4 Pillow requests`.
    static var script: String {
        let minimo = "(\(EngineLocator.minimumPython.major), \(EngineLocator.minimumPython.minor))"
        let modulos = EngineLocator.requiredModules.map { "(\"\($0.0)\", \"\($0.1)\")" }.joined(separator: ", ")
        // Roda com -S (ver `run`): as pastas site-packages entram aqui, sem
        // seguir os `.pth`, como o motor faz em `mobaile._site`.
        return """
        import sys, os, site, importlib.util
        for d in site.getsitepackages():
            if d not in sys.path and os.path.isdir(d):
                sys.path.append(d)
        v = "%d.%d.%d" % sys.version_info[:3]
        if sys.version_info[:2] < \(minimo):
            print("OLD", v)
        else:
            faltam = [nome for mod, nome in [\(modulos)] if importlib.util.find_spec(mod) is None]
            print("MISSING" if faltam else "OK", v, *faltam)
        """
    }

    /// Interpreta a linha do script.
    static func parse(_ saida: String) -> Result {
        let partes = saida.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let tipo = partes.first, partes.count >= 2 else {
            return Result(kind: .failed("resposta inesperada da sonda"), version: nil)
        }
        let versao = partes[1]
        switch tipo {
        case "OK": return Result(kind: .usable, version: versao)
        case "OLD": return Result(kind: .tooOld, version: versao)
        case "MISSING": return Result(kind: .missingModules(Array(partes.dropFirst(2))), version: versao)
        default: return Result(kind: .failed("resposta inesperada da sonda"), version: nil)
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Result] = [:]

    /// Sonda com cache por caminho (R-02).
    ///
    /// Só o resultado que serve fica guardado. Falha (sem Pillow, antigo, sem
    /// resposta no prazo) roda de novo na próxima subida: é o que deixa
    /// "instale o Pillow e use Reiniciar Motor" funcionar sem reabrir o app, e
    /// impede que uma partida a frio lenta descarte um Python bom para sempre.
    /// `runner` existe para o teste trocar a sonda de verdade.
    static func cached(_ path: String, runner: (String) -> Result = { run($0) }) -> Result {
        lock.lock()
        if let pronto = cache[path] {
            lock.unlock()
            return pronto
        }
        lock.unlock()
        let resultado = runner(path)
        if resultado.isUsable {
            lock.lock()
            cache[path] = resultado
            lock.unlock()
        }
        return resultado
    }

    /// Esquece tudo o que a sonda guardou. O `restartEngine()` chama: quem
    /// desinstalou uma dependência com o app aberto também é atendido.
    static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// Roda a sonda de verdade, sem cache.
    static func run(_ path: String, timeout: TimeInterval = timeout) -> Result {
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: path)
        // -I: não lê PYTHONPATH nem o diretório atual, só o que o interpretador
        // tem instalado. -S: não segue os `.pth` (um deles apontava para
        // ~/Documents e fazia o macOS pedir acesso); o script põe o
        // site-packages no caminho por conta própria.
        processo.arguments = ["-I", "-S", "-c", script]
        let saida = Pipe()
        processo.standardOutput = saida
        processo.standardError = FileHandle.nullDevice
        processo.standardInput = FileHandle.nullDevice

        let terminou = DispatchSemaphore(value: 0)
        processo.terminationHandler = { _ in terminou.signal() }
        do {
            try processo.run()
        } catch {
            return Result(kind: .failed("não executou"), version: nil)
        }
        if terminou.wait(timeout: .now() + timeout) == .timedOut {
            encerrar(processo, terminou: terminou)
            return Result(kind: .failed("não respondeu em \(Int(timeout)) s"), version: nil)
        }
        let dados = saida.fileHandleForReading.readDataToEndOfFile()
        guard processo.terminationStatus == 0, let texto = String(data: dados, encoding: .utf8) else {
            return Result(kind: .failed("saiu com erro \(processo.terminationStatus)"), version: nil)
        }
        return parse(texto)
    }

    /// Quanto o processo tem para sair depois do SIGTERM antes do SIGKILL.
    static let killGrace: TimeInterval = 0.5

    /// SIGTERM, uma espera curta e SIGKILL se ainda estiver vivo (R-05).
    /// Um interpretador travado que ignora o SIGTERM não fica pendurado no app.
    private static func encerrar(_ processo: Process, terminou: DispatchSemaphore) {
        processo.terminate()
        guard terminou.wait(timeout: .now() + killGrace) == .timedOut else { return }
        if processo.isRunning {
            kill(processo.processIdentifier, SIGKILL)
        }
        // O SIGKILL não pode ser ignorado; a espera só cobre a colheita.
        _ = terminou.wait(timeout: .now() + killGrace)
    }
}
