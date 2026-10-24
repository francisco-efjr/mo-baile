import AppKit
import Foundation

/// Roda um alvo de `instalar-mac.sh` no Terminal, à vista da pessoa.
///
/// O app não instala nada por baixo dos panos: escreve um `.command` de uma
/// linha e pede ao macOS para abri-lo, o que abre o Terminal com o comando. A
/// pessoa vê cada passo, digita a senha quando o Homebrew pedir e pode
/// interromper com ⌃C. Abrir um `.command` não pede permissão de automação,
/// ao contrário de mandar comandos ao Terminal por AppleScript.
///
/// O como-instalar mora só no script; o motor diz qual alvo resolve cada item.
enum SetupInstaller {
    static let scriptName = "instalar-mac.sh"

    /// O script: dentro do app em `Contents/Resources/setup`, ou no
    /// repositório em `tools/setup` (rodando pelo `swift run`).
    static func scriptURL(
        resources: URL? = Bundle.main.resourceURL,
        repositoryRoot: URL? = EngineLocator.repositoryRoot(),
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL? {
        var candidatos: [URL] = []
        if let resources { candidatos.append(resources.appendingPathComponent("setup/\(scriptName)")) }
        if let repositoryRoot { candidatos.append(repositoryRoot.appendingPathComponent("tools/setup/\(scriptName)")) }
        return candidatos.first { exists($0.path) }
    }

    /// Aspas simples de shell: o caminho do app tem espaço e parênteses.
    static func shellQuote(_ texto: String) -> String {
        "'" + texto.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Alvos são palavras curtas do motor (`android`, `ios-device`); qualquer
    /// outra coisa não vira comando.
    static func isValidTarget(_ alvo: String) -> Bool {
        !alvo.isEmpty && alvo.allSatisfy { $0.isLowercase || $0 == "-" }
    }

    /// A linha que roda o alvo. Com `python`, os pacotes vão para o Python que
    /// o motor usa agora (`MOBAILE_PYTHON`), e não para outro qualquer.
    static func command(target: String, script: URL, python: String?) -> String {
        var partes: [String] = []
        if let python, !python.isEmpty { partes.append("MOBAILE_PYTHON=\(shellQuote(python))") }
        partes += ["bash", shellQuote(script.path), target]
        return partes.joined(separator: " ")
    }

    /// Conteúdo do `.command`: limpa a tela e roda a linha.
    static func commandFile(_ comando: String) -> String {
        "#!/bin/bash\nclear\n\(comando)\n"
    }

    enum Failure: LocalizedError, Equatable {
        case scriptMissing
        case invalidTarget(String)

        var errorDescription: String? {
            switch self {
            case .scriptMissing:
                return "O script de instalação não está no app. Reinstale o Mo baile ou rode tools/setup/\(SetupInstaller.scriptName) do código-fonte."
            case .invalidTarget(let alvo):
                return "Alvo de instalação desconhecido: \(alvo)."
            }
        }
    }

    /// Escreve o `.command` numa pasta temporária e o abre no Terminal.
    @discardableResult
    static func openInTerminal(target: String, python: String?) throws -> URL {
        guard isValidTarget(target) else { throw Failure.invalidTarget(target) }
        guard let script = scriptURL() else { throw Failure.scriptMissing }
        let arquivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoBaile-instalar-\(target).command")
        try commandFile(command(target: target, script: script, python: python))
            .write(to: arquivo, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: arquivo.path)
        NSWorkspace.shared.open(arquivo)
        return arquivo
    }

    /// O comando para colar no Terminal, o mesmo do botão.
    static func copyableCommand(target: String, python: String?) -> String? {
        guard isValidTarget(target), let script = scriptURL() else { return nil }
        return command(target: target, script: script, python: python)
    }
}
