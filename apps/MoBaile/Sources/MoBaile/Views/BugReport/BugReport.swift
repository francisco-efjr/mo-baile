import AppKit
import Foundation
import UniformTypeIdentifiers

/// Relatar um Problema (LIB-3). O relato vira uma issue no GitHub: o app abre
/// `issues/new` com o formulário `bug-app.yml` pré-preenchido e guarda o texto
/// e os anexos numa pasta, revelada no Finder, para a pessoa arrastar os
/// arquivos para o GitHub. O app nunca guarda token nem envia nada sozinho.
/// Especificação: `docs/melhorias/2026-11-16-liberacao/revisao/ux-ajuda-beta-bugs.md` §4.
enum BugReport {
    static let repository = URL(string: "https://github.com/francisco-efjr/mo-baile")!
    static let template = "bug-app.yml"
    /// URL acima disso arrisca recusa do GitHub (Suposição: ~8 KB).
    static let maxURLLength = 7_500
    static let maxTitle = 120

    enum Limits {
        static let files = 5
        static let bytesPerFile: Int64 = 10 * 1024 * 1024
        static let bytesTotal: Int64 = 25 * 1024 * 1024
        static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "mp4", "mov", "txt", "log", "json", "pdf", "zip"]
        static let blocked: Set<String> = ["app", "sh", "command", "pkg", "dmg", "exe", "bat", "ps1", "py", "jar", "scpt"]
    }

    /// Onde aconteceu. "Ajuda" e "Outra" não são áreas do app.
    enum Area: String, CaseIterable, Identifiable, Sendable {
        case home, pageObjects, network, analytics, report, environment, execution, help, other

        var id: String { rawValue }

        init(_ tab: WorkspaceTab) {
            self = Area(rawValue: tab.rawValue) ?? .other
        }

        var displayName: String {
            switch self {
            case .help: return "Ajuda"
            case .other: return "Outra ou não sei"
            default: return WorkspaceTab(rawValue: rawValue)?.displayName ?? "Outra ou não sei"
            }
        }
    }

    struct Attachment: Identifiable, Equatable, Sendable {
        let url: URL
        let size: Int64
        var id: URL { url }
        var name: String { url.lastPathComponent }
    }

    /// Recusa de anexo, com o texto da tela.
    enum AttachmentError: Error, Equatable {
        case tooLarge(String, Int64)
        case total
        case type(String)
        case executable(String)
        case count
        case duplicate(String)
        case unreadable(String)

        var message: String {
            switch self {
            case .tooLarge(let nome, let tamanho):
                let texto = ByteCountFormatter.string(fromByteCount: tamanho, countStyle: .file)
                return "“\(nome)” tem \(texto). O limite é 10 MB por arquivo. Corte o vídeo ou use uma captura de tela."
            case .total: return "Os anexos passam de 25 MB juntos. Remova algum ou envie menos arquivos."
            case .type(let nome): return "“\(nome)” não é um tipo aceito. Use png, jpg, gif, mp4, mov, txt, log, json, pdf ou zip."
            case .executable(let nome): return "“\(nome)” é um programa ou instalador, e não pode ser anexado. Anexe uma captura ou um log."
            case .count: return "O máximo é 5 anexos. Remova um para adicionar outro."
            case .duplicate(let nome): return "“\(nome)” já está na lista."
            case .unreadable(let nome): return "Não consegui ler “\(nome)”. Confira se o arquivo ainda existe e tente de novo."
            }
        }
    }

    /// Confere um arquivo antes de entrar na lista. Só lê nome, tamanho e tipo.
    static func validate(_ url: URL, against atuais: [Attachment], fileManager: FileManager = .default) -> Result<Attachment, AttachmentError> {
        let nome = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if Limits.blocked.contains(ext) { return .failure(.executable(nome)) }
        guard Limits.extensions.contains(ext) else { return .failure(.type(nome)) }
        // Mesmo nome, mesmo sem diferenciar maiúsculas: a pasta do relato
        // guarda as cópias pelo nome, e o APFS padrão não distingue "a" de "A".
        if atuais.contains(where: { $0.name.lowercased() == nome.lowercased() }) { return .failure(.duplicate(nome)) }
        guard atuais.count < Limits.files else { return .failure(.count) }
        guard let valores = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .isExecutableKey]),
              valores.isRegularFile == true, valores.isSymbolicLink != true, let bytes = valores.fileSize else {
            return .failure(.unreadable(nome))
        }
        // Arrastar não passa pelo filtro do painel: confere o tipo real.
        if valores.isExecutable == true { return .failure(.executable(nome)) }
        guard signatureMatches(url, ext: ext) else { return .failure(.type(nome)) }
        let tamanho = Int64(bytes)
        if tamanho > Limits.bytesPerFile { return .failure(.tooLarge(nome, tamanho)) }
        if atuais.reduce(0, { $0 + $1.size }) + tamanho > Limits.bytesTotal { return .failure(.total) }
        return .success(Attachment(url: url, size: tamanho))
    }

    /// Assinatura dos formatos binários aceitos (os de texto e vídeo passam).
    static func signatureMatches(_ url: URL, ext: String) -> Bool {
        let assinaturas: [String: [[UInt8]]] = [
            "png": [[0x89, 0x50, 0x4E, 0x47]],
            "jpg": [[0xFF, 0xD8, 0xFF]], "jpeg": [[0xFF, 0xD8, 0xFF]],
            "gif": [Array("GIF8".utf8)],
            "pdf": [Array("%PDF".utf8)],
            "zip": [[0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06]],
        ]
        guard let esperadas = assinaturas[ext] else { return true }
        guard let arquivo = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? arquivo.close() }
        let inicio = [UInt8]((try? arquivo.read(upToCount: 8)) ?? Data())
        return esperadas.contains { inicio.starts(with: $0) }
    }

    /// Dados que só entram se a pessoa marcar.
    struct Environment: Equatable, Sendable {
        var appVersion: String
        var commit: String?
        var macOS: String
        var macModel: String
        var device: String?

        static func current(device: String?) -> Environment {
            let info = Bundle.main.infoDictionary ?? [:]
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return Environment(
                appVersion: (info["CFBundleShortVersionString"] as? String) ?? "dev",
                commit: (info["MoBaileGitCommit"] as? String).map { String($0.prefix(7)) },
                macOS: "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
                macModel: Self.hardwareModel(),
                device: device
            )
        }

        static func hardwareModel() -> String {
            var tamanho = 0
            sysctlbyname("hw.model", nil, &tamanho, nil, 0)
            guard tamanho > 0 else { return "Mac" }
            var bytes = [CChar](repeating: 0, count: tamanho)
            sysctlbyname("hw.model", &bytes, &tamanho, nil, 0)
            #if arch(arm64)
            let chip = "Apple Silicon"
            #else
            let chip = "Intel"
            #endif
            return "\(String(cString: bytes)), \(chip)"
        }
    }

    struct Draft: Equatable {
        var title = ""
        var area: Area = .other
        var didWhat = ""
        var expected = ""
        var happened = ""
        var attachments: [Attachment] = []
        var includeVersion = false
        var includeMac = false
        var includeDevice = false

        var isEmpty: Bool {
            [title, didWhat, expected, happened].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                && attachments.isEmpty
        }

        enum Field: Hashable { case title, happened }

        /// Campo inválido e a mensagem, na ordem da tela.
        func validationErrors() -> [(Field, String)] {
            var erros: [(Field, String)] = []
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty {
                erros.append((.title, "Informe um título. Uma frase curta já ajuda."))
            } else if t.count > BugReport.maxTitle {
                erros.append((.title, "O título tem \(t.count) caracteres. O limite é 120. Encurte e deixe os detalhes na descrição."))
            }
            if happened.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                erros.append((.happened, "Conte o que aconteceu. Uma ou duas frases bastam."))
            }
            return erros
        }

        func environmentLines(_ env: Environment) -> [String] {
            var linhas: [String] = []
            if includeVersion {
                linhas.append("Mo baile \(env.appVersion)" + (env.commit.map { " (commit \($0))" } ?? ""))
                linhas.append(env.macOS)
            }
            if includeMac { linhas.append(env.macModel) }
            if includeDevice, let device = env.device { linhas.append("Aparelho: \(device)") }
            return linhas
        }

        /// O Markdown do relato: o que vai ao GitHub e o que Copiar Relato copia.
        func markdown(_ env: Environment) -> String {
            func ou(_ s: String) -> String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? "Não informado" : t
            }
            var partes = [
                "### O que aconteceu\n\(ou(happened))",
                "### O que eu fiz\n\(ou(didWhat))",
                "### O que eu esperava\n\(ou(expected))",
                "### Área\n\(area.displayName)",
            ]
            let ambiente = environmentLines(env)
            if !ambiente.isEmpty { partes.append("### Informações do ambiente\n" + ambiente.map { "- \($0)" }.joined(separator: "\n")) }
            if !attachments.isEmpty {
                partes.append("### Anexos\n" + attachments.map { "- \($0.name)" }.joined(separator: "\n"))
            }
            partes.append("_Enviado pelo Mo baile (relato pelo app)._")
            return partes.joined(separator: "\n\n")
        }

        /// `issues/new` com os campos do `bug-app.yml` pelo `id`. Se não couber,
        /// corta os textos e avisa (`truncated`): o app copia o relato inteiro.
        func issueURL(_ env: Environment) -> (url: URL, truncated: Bool) {
            let titulo = "[bug] " + title.trimmingCharacters(in: .whitespacesAndNewlines)
            let campos: [(String, String)] = [
                ("aconteceu", happened), ("fez", didWhat), ("esperava", expected),
                ("area", area.displayName),
                ("ambiente", environmentLines(env).map { "- \($0)" }.joined(separator: "\n")),
                ("anexos", attachments.map { "- \($0.name)" }.joined(separator: "\n")),
            ]
            func montar(_ campos: [(String, String)]) -> URL {
                let pares = [("template", BugReport.template), ("title", titulo)] + campos.filter { !$0.1.isEmpty }
                let query = pares.map { "\($0.0)=\(BugReport.encode($0.1))" }.joined(separator: "&")
                return URL(string: BugReport.repository.absoluteString + "/issues/new?" + query)!
            }
            let completa = montar(campos)
            if completa.absoluteString.count <= BugReport.maxURLLength { return (completa, false) }
            // Corta cada campo pelo tamanho já codificado (acento e emoji
            // viram 6 a 12 caracteres na URL), do maior orçamento ao menor.
            let nota = "… (texto completo no relato copiado)"
            var orcamento = 3_000
            while orcamento >= 150 {
                let cortados = campos.map { nome, valor -> (String, String) in
                    guard BugReport.encode(valor).count > orcamento else { return (nome, valor) }
                    var parte = Substring(valor)
                    while !parte.isEmpty && BugReport.encode(String(parte) + nota).count > orcamento { parte = parte.dropLast(max(1, parte.count / 8)) }
                    return (nome, String(parte) + nota)
                }
                let url = montar(cortados)
                if url.absoluteString.count <= BugReport.maxURLLength { return (url, true) }
                orcamento /= 2
            }
            // Último recurso: só o título e a nota; o relato inteiro foi copiado.
            return (montar([("aconteceu", "Relato longo: o texto completo foi copiado. Cole aqui.")]), true)
        }
    }

    /// Codificação estrita para valor de query: só os não reservados passam.
    /// `URLComponents` deixa `+`, `&` e `=` crus, e o GitHub leria `+` como espaço.
    static func encode(_ texto: String) -> String {
        var permitidos = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        permitidos.insert(charactersIn: "-._~")
        return texto.addingPercentEncoding(withAllowedCharacters: permitidos) ?? ""
    }

    /// `Documentos/Mo baile/Relatos/<aaaa-mm-dd hh-mm-ss>/` com `relato.md` e
    /// cópias dos anexos, para arrastar ao GitHub.
    static func saveFolder(
        _ draft: Draft, env: Environment, base: URL? = nil, now: Date = Date(), fileManager: FileManager = .default
    ) throws -> URL {
        let raiz = base ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mo baile/Relatos", isDirectory: true)
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "en_US_POSIX")
        formato.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let pasta = raiz.appendingPathComponent(formato.string(from: now), isDirectory: true)
        try fileManager.createDirectory(at: pasta, withIntermediateDirectories: true)
        let titulo = "# " + draft.title.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        try (titulo + draft.markdown(env) + "\n").write(to: pasta.appendingPathComponent("relato.md"), atomically: true, encoding: .utf8)
        for anexo in draft.attachments {
            let destino = pasta.appendingPathComponent(anexo.name)
            if !fileManager.fileExists(atPath: destino.path) {
                try fileManager.copyItem(at: anexo.url, to: destino)
            }
        }
        return pasta
    }
}

/// Aviso de produto em desenvolvimento: uma vez por versão maior.
enum BetaNotice {
    static let key = "mobaile.avisoBetaMajor"

    /// "3" para 3.23.0; "dev" sem versão (rodando do código).
    static func major(_ versao: String?) -> String {
        guard let versao, let v = AppVersion(versao), let primeiro = v.parts.first else { return "dev" }
        return String(primeiro)
    }

    static func shouldShow(version: String?, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: key) != major(version)
    }

    static func markSeen(version: String?, defaults: UserDefaults = .standard) {
        defaults.set(major(version), forKey: key)
    }

    static var installedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static let tooltip = "Versão beta, em desenvolvimento. Pode ter bugs. Clique para relatar um problema."
    static let alertTitle = "O Mo baile está em desenvolvimento"
    static let alertMessage = "Esta é uma versão beta. Ela já faz bastante coisa, mas ainda tem bugs e algumas telas vão mudar. "
        + "Se algo falhar, relate o problema: leva um minuto e ajuda a corrigir mais rápido."
}
