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

    private static func locatePython() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment[pythonOverrideKey], isExecutable(override) {
            return URL(fileURLWithPath: override)
        }

        var candidates: [String] = []
        // Ambiente virtual do proprio repositorio vem primeiro: e onde as
        // dependencias do motor estao instaladas em desenvolvimento.
        if let root = repositoryRoot() {
            candidates.append(root.appendingPathComponent(".venv/bin/python3").path)
        }
        candidates += [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        for path in candidates where isExecutable(path) {
            return URL(fileURLWithPath: path)
        }
        throw EngineError.engineNotFound(
            "Nenhum Python 3 encontrado. Defina \(pythonOverrideKey) apontando para o interpretador."
        )
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
    private static func repositoryRoot() -> URL? {
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
