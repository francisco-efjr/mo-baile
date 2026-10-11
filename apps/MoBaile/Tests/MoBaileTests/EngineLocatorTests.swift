import XCTest
@testable import MoBaile

/// PY-1: o `EngineLocator` só aceita um Python que sobe o motor.
///
/// Defeito que cobre (PB7): o `/usr/bin/python3` 3.9 sem Pillow era aceito
/// por ser executável, o motor morria ao importar e o app entrava no laço de
/// reinício.
final class EngineLocatorTests: XCTestCase {

    private typealias R = PythonProbe.Result

    private let candidatos = ["/repo/.venv/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]

    func testOrdemDosCandidatosNaoMudou() {
        let raiz = URL(fileURLWithPath: "/repo")
        XCTAssertEqual(EngineLocator.pythonCandidates(repositoryRoot: raiz), candidatos)
        XCTAssertEqual(EngineLocator.pythonCandidates(repositoryRoot: nil), Array(candidatos.dropFirst()))
    }

    func testPulaOAntigoEOSemDependenciaEPegaOPrimeiroQueServe() throws {
        var sondados: [String] = []
        let escolhido = try EngineLocator.selectPython(
            from: candidatos,
            isExecutable: { $0 != "/repo/.venv/bin/python3" },
            probe: { caminho in
                sondados.append(caminho)
                switch caminho {
                case "/opt/homebrew/bin/python3": return R(kind: .missingModules(["Pillow"]), version: "3.12.1")
                case "/usr/local/bin/python3": return R(kind: .usable, version: "3.11.4")
                default: return R(kind: .tooOld, version: "3.9.6")
                }
            }
        )
        XCTAssertEqual(escolhido.path, "/usr/local/bin/python3")
        XCTAssertEqual(sondados, ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"], "na ordem, e para no primeiro bom")
    }

    func testNenhumServeDaErroQueDizOQueInstalar() {
        XCTAssertThrowsError(try EngineLocator.selectPython(
            from: candidatos,
            isExecutable: { $0 == "/usr/bin/python3" },
            probe: { _ in R(kind: .tooOld, version: "3.9.6") }
        )) { erro in
            guard case EngineError.pythonUnsuitable(let mensagem) = erro else {
                return XCTFail("erro inesperado: \(erro)")
            }
            XCTAssertTrue(mensagem.contains("/usr/bin/python3 (Python 3.9.6, antigo demais)"), mensagem)
            XCTAssertTrue(mensagem.contains("3.10"), mensagem)
            XCTAssertTrue(mensagem.contains("pip install Pillow requests"), mensagem)
            XCTAssertTrue(mensagem.contains("MOBAILE_PYTHON"), mensagem)
            XCTAssertTrue((erro as? EngineError)?.isRecoverableBySetup == true)
        }
    }

    func testSemPythonNenhum() {
        XCTAssertThrowsError(try EngineLocator.selectPython(from: candidatos, isExecutable: { _ in false }, probe: { _ in
            XCTFail("não sonda o que não executa")
            return R(kind: .usable, version: nil)
        })) { erro in
            XCTAssertTrue(erro.localizedDescription.contains("Nenhum Python 3 foi encontrado"), erro.localizedDescription)
        }
    }

    func testLeituraDaSonda() {
        XCTAssertEqual(PythonProbe.parse("OK 3.12.1\n"), R(kind: .usable, version: "3.12.1"))
        XCTAssertEqual(PythonProbe.parse("OLD 3.9.6"), R(kind: .tooOld, version: "3.9.6"))
        XCTAssertEqual(PythonProbe.parse("MISSING 3.11.4 Pillow requests"), R(kind: .missingModules(["Pillow", "requests"]), version: "3.11.4"))
        XCTAssertFalse(PythonProbe.parse("").isUsable)
        XCTAssertEqual(R(kind: .missingModules(["Pillow", "requests"]), version: "3.11.4").reason, "Python 3.11.4, sem Pillow e requests")
    }

    /// A sonda de verdade com um interpretador falso: responde, demora e
    /// falha. O prazo curto prova que um Python travado não segura o app.
    func testSondaDeVerdadeComPrazo() throws {
        let pasta = FileManager.default.temporaryDirectory.appendingPathComponent("sonda-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pasta) }

        func falso(_ nome: String, _ corpo: String) throws -> String {
            let url = pasta.appendingPathComponent(nome)
            try "#!/bin/sh\n\(corpo)\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url.path
        }

        let bom = try falso("bom", "echo OK 3.12.1")
        XCTAssertEqual(PythonProbe.run(bom), R(kind: .usable, version: "3.12.1"))

        let lento = try falso("lento", "sleep 5")
        let inicio = Date()
        let resultado = PythonProbe.run(lento, timeout: 0.3)
        XCTAssertLessThan(Date().timeIntervalSince(inicio), 2, "o prazo não foi respeitado")
        XCTAssertFalse(resultado.isUsable)
        XCTAssertTrue(resultado.reason.contains("não respondeu"), resultado.reason)

        let quebrado = try falso("quebrado", "exit 3")
        XCTAssertEqual(PythonProbe.run(quebrado).kind, .failed("saiu com erro 3"))
    }

    /// R-02: falha não fica em cache. Quem instala o Pillow e usa Reiniciar
    /// Motor precisa que a sonda rode de novo, e uma partida a frio lenta não
    /// pode marcar o Python como inútil até o app ser reaberto.
    func testCacheNaoGuardaFalha() {
        let caminho = "/teste/cache-\(UUID().uuidString)/python3"
        var respostas: [R] = [
            R(kind: .missingModules(["Pillow"]), version: "3.12.1"),
            R(kind: .failed("não respondeu em 3 s"), version: nil),
            R(kind: .usable, version: "3.12.1"),
        ]
        var rodadas = 0
        let sonda: (String) -> R = { _ in rodadas += 1; return respostas.removeFirst() }

        XCTAssertFalse(PythonProbe.cached(caminho, runner: sonda).isUsable)
        XCTAssertFalse(PythonProbe.cached(caminho, runner: sonda).isUsable)
        XCTAssertTrue(PythonProbe.cached(caminho, runner: sonda).isUsable, "depois de instalar, a sonda vê o Python bom")
        XCTAssertEqual(rodadas, 3, "falha não vem do cache")

        // O que serve fica em cache: o reinício não paga a sonda de novo.
        XCTAssertTrue(PythonProbe.cached(caminho, runner: sonda).isUsable)
        XCTAssertEqual(rodadas, 3)
    }

    /// R-02: `clearCache()` esquece até o Python bom. O `restartEngine()` usa
    /// isto para o caso de alguém desinstalar uma dependência com o app aberto.
    func testLimparCacheFazSondarDeNovo() {
        let caminho = "/teste/limpar-\(UUID().uuidString)/python3"
        var rodadas = 0
        let sonda: (String) -> R = { _ in rodadas += 1; return R(kind: .usable, version: "3.12.1") }
        _ = PythonProbe.cached(caminho, runner: sonda)
        _ = PythonProbe.cached(caminho, runner: sonda)
        XCTAssertEqual(rodadas, 1)
        PythonProbe.clearCache()
        _ = PythonProbe.cached(caminho, runner: sonda)
        XCTAssertEqual(rodadas, 2)
    }

    /// O script de verdade, no Python desta máquina, quando houver um.
    func testScriptRodaNumPythonReal() throws {
        guard let python = EngineLocator.pythonCandidates().first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("sem Python nesta máquina")
        }
        let resultado = PythonProbe.run(python, timeout: 10)
        XCTAssertNotNil(resultado.version, "o script não respondeu em \(python): \(resultado.reason)")
    }
}
