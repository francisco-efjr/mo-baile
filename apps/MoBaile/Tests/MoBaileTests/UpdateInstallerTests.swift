import CryptoKit
import XCTest
@testable import MoBaile

/// Atualização no lugar (ADR 0008) com arquivos de verdade num diretório
/// temporário: zip feito pelo `ditto`, assinatura Ed25519 com chave de teste,
/// troca do bundle e o ajudante que reabre. Só a rede é falsa.
final class UpdateInstallerTests: XCTestCase {

    private var raiz: URL!
    private var pastaApps: URL!
    private var appInstalado: URL!
    private let chave = Curve25519.Signing.PrivateKey()
    private var chavePublica: String { chave.publicKey.rawRepresentation.base64EncodedString() }
    private let executavel = "Mo baile (nativo)"

    override func setUpWithError() throws {
        raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mobaile-atualizacao-\(UUID().uuidString)", isDirectory: true)
        pastaApps = raiz.appendingPathComponent("Aplicativos", isDirectory: true)
        try FileManager.default.createDirectory(at: pastaApps, withIntermediateDirectories: true)
        appInstalado = pastaApps.appendingPathComponent("\(executavel).app")
        try criarApp(em: appInstalado, versao: "3.25.0")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pastaApps.path)
        try? FileManager.default.removeItem(at: raiz)
    }

    // MARK: - Apoio

    private func criarApp(em app: URL, versao: String, id: String = "com.qa.mobaile") throws {
        let macos = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": id,
            "CFBundleShortVersionString": versao,
            "CFBundleExecutable": executavel,
            "CFBundlePackageType": "APPL",
        ]
        let dados = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try dados.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let binario = macos.appendingPathComponent(executavel)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binario)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binario.path)
    }

    /// Monta o zip de um app como o workflow de release faz e assina.
    private func publicar(versao: String, id: String = "com.qa.mobaile", assinarCom outra: Curve25519.Signing.PrivateKey? = nil)
        throws -> (zip: URL, sig: URL)
    {
        let saida = raiz.appendingPathComponent("release-\(UUID().uuidString)", isDirectory: true)
        let app = saida.appendingPathComponent("monta/\(executavel).app")
        try criarApp(em: app, versao: versao, id: id)
        let zip = saida.appendingPathComponent("MoBaile-\(versao)-macOS.zip")
        XCTAssertEqual(try UpdateInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]), 0)
        let assinatura = try (outra ?? chave).signature(for: Data(contentsOf: zip))
        let sig = zip.appendingPathExtension("sig")
        try Data((assinatura.base64EncodedString() + "\n").utf8).write(to: sig)
        return (zip, sig)
    }

    private func release(_ tag: String, zip: URL, sig: URL?) -> ReleaseInfo {
        var assets = [ReleaseInfo.Asset(name: zip.lastPathComponent, browserDownloadURL: URL(string: "https://example.test/\(zip.lastPathComponent)")!)]
        if let sig {
            assets.append(ReleaseInfo.Asset(name: sig.lastPathComponent, browserDownloadURL: URL(string: "https://example.test/\(sig.lastPathComponent)")!))
        }
        return ReleaseInfo(tagName: tag, htmlURL: URL(string: "https://example.test/r")!, assets: assets)
    }

    /// Serve os arquivos locais no lugar da rede.
    private struct DownloaderLocal: UpdateDownloading {
        let arquivos: [String: URL]

        func data(from url: URL) async throws -> Data {
            guard let local = arquivos[url.lastPathComponent] else { throw URLError(.fileDoesNotExist) }
            return try Data(contentsOf: local)
        }

        func download(from url: URL, to destino: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            guard let local = arquivos[url.lastPathComponent] else { throw URLError(.fileDoesNotExist) }
            try FileManager.default.copyItem(at: local, to: destino)
            progress(1)
        }
    }

    private final class Relancamentos: @unchecked Sendable {
        var chamadas: [(URL, URL)] = []
    }

    private func instalador(publicado: (zip: URL, sig: URL), relancamentos: Relancamentos = Relancamentos()) -> UpdateInstaller {
        var instalador = UpdateInstaller(bundleURL: appInstalado, bundleID: "com.qa.mobaile", current: AppVersion("3.25.0"))
        instalador.publicKeys = [chavePublica]
        instalador.downloader = DownloaderLocal(arquivos: [
            publicado.zip.lastPathComponent: publicado.zip,
            publicado.sig.lastPathComponent: publicado.sig,
        ])
        instalador.verifyCodeSignature = { _ in true }
        instalador.relaunch = { app, lixo in relancamentos.chamadas.append((app, lixo)) }
        return instalador
    }

    private func versao(_ app: URL) -> String? {
        (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleShortVersionString"] as? String
    }

    // MARK: - Preparar

    func testPreparaConfereEDeixaOAppNovoAoLadoSemTocarNoInstalado() async throws {
        let publicado = try publicar(versao: "3.26.0")
        let pronto = try await instalador(publicado: publicado).prepare(release("v3.26.0", zip: publicado.zip, sig: publicado.sig)) { _ in }
        XCTAssertEqual(pronto.version, AppVersion("3.26.0"))
        XCTAssertEqual(versao(pronto.newApp), "3.26.0")
        XCTAssertEqual(versao(appInstalado), "3.25.0", "preparar não troca nada")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pronto.workDir.appendingPathComponent("atualizacao.zip").path),
                       "o zip sai depois de extraído")
        try? FileManager.default.removeItem(at: pronto.workDir)
    }

    func testAssinaturaDeOutraChaveNaoInstalaNada() async throws {
        let publicado = try publicar(versao: "3.26.0", assinarCom: Curve25519.Signing.PrivateKey())
        do {
            _ = try await instalador(publicado: publicado).prepare(release("v3.26.0", zip: publicado.zip, sig: publicado.sig)) { _ in }
            XCTFail("aceitou assinatura de outra chave")
        } catch {
            XCTAssertEqual(error as? UpdateInstallError, .badSignature)
        }
        XCTAssertEqual(versao(appInstalado), "3.25.0")
    }

    func testZipAlteradoDepoisDeAssinadoEhRecusado() async throws {
        let publicado = try publicar(versao: "3.26.0")
        let handle = try FileHandle(forWritingTo: publicado.zip)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x00]))
        try handle.close()
        do {
            _ = try await instalador(publicado: publicado).prepare(release("v3.26.0", zip: publicado.zip, sig: publicado.sig)) { _ in }
            XCTFail("aceitou zip alterado")
        } catch {
            XCTAssertEqual(error as? UpdateInstallError, .badSignature)
        }
    }

    func testOutroAppOuOutraVersaoNoZipSaoRecusados() async throws {
        let outroApp = try publicar(versao: "3.26.0", id: "com.exemplo.outro")
        do {
            _ = try await instalador(publicado: outroApp).prepare(release("v3.26.0", zip: outroApp.zip, sig: outroApp.sig)) { _ in }
            XCTFail("aceitou outro bundle id")
        } catch {
            XCTAssertEqual(error as? UpdateInstallError, .invalidBundle("o app do zip não é o Mo baile"))
        }

        let outraVersao = try publicar(versao: "3.25.5")
        do {
            _ = try await instalador(publicado: outraVersao).prepare(release("v3.26.0", zip: outraVersao.zip, sig: outraVersao.sig)) { _ in }
            XCTFail("aceitou versão diferente da anunciada")
        } catch {
            XCTAssertEqual(error as? UpdateInstallError, .invalidBundle("o app do zip não é a versão 3.26.0"))
        }
    }

    func testAssinaturaDeCodigoQuebradaEhRecusada() async throws {
        let publicado = try publicar(versao: "3.26.0")
        var instalador = instalador(publicado: publicado)
        instalador.verifyCodeSignature = { _ in false }
        do {
            _ = try await instalador.prepare(release("v3.26.0", zip: publicado.zip, sig: publicado.sig)) { _ in }
            XCTFail("aceitou app com assinatura de código quebrada")
        } catch {
            XCTAssertEqual(error as? UpdateInstallError, .invalidBundle("a assinatura de código do app novo não confere"))
        }
    }

    func testCodesignDeVerdadeAceitaAdHocEPegaAlteracao() throws {
        let app = raiz.appendingPathComponent("assinado/\(executavel).app")
        try criarApp(em: app, versao: "3.26.0")
        XCTAssertEqual(try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path]), 0)
        XCTAssertTrue(UpdateInstaller.codeSignatureIsValid(app))
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: app.appendingPathComponent("Contents/MacOS/\(executavel)"))
        XCTAssertFalse(UpdateInstaller.codeSignatureIsValid(app), "binário trocado depois de assinado")
    }

    // MARK: - Trocar

    func testInstalarTrocaOAppGuardaOAnteriorEChamaOAjudante() async throws {
        let publicado = try publicar(versao: "3.26.0")
        let relancamentos = Relancamentos()
        let instalador = instalador(publicado: publicado, relancamentos: relancamentos)
        let pronto = try await instalador.prepare(release("v3.26.0", zip: publicado.zip, sig: publicado.sig)) { _ in }
        try instalador.install(pronto)

        XCTAssertEqual(versao(appInstalado), "3.26.0", "mesmo caminho, versão nova")
        XCTAssertEqual(versao(pronto.workDir.appendingPathComponent("anterior.app")), "3.25.0")
        XCTAssertEqual(relancamentos.chamadas.count, 1)
        XCTAssertEqual(relancamentos.chamadas.first?.0, appInstalado)
        XCTAssertEqual(relancamentos.chamadas.first?.1, pronto.workDir)
    }

    func testFalhaAoPorONovoDevolveOAnterior() throws {
        let trabalho = raiz.appendingPathComponent("trabalho", isDirectory: true)
        try FileManager.default.createDirectory(at: trabalho, withIntermediateDirectories: true)
        let pronto = PreparedUpdate(version: AppVersion("3.26.0")!, newApp: trabalho.appendingPathComponent("sumiu.app"), workDir: trabalho)
        let instalador = UpdateInstaller(bundleURL: appInstalado, bundleID: "com.qa.mobaile", current: AppVersion("3.25.0"))
        XCTAssertThrowsError(try instalador.install(pronto)) { erro in
            guard case .replaceFailed = erro as? UpdateInstallError else { return XCTFail("\(erro)") }
        }
        XCTAssertEqual(versao(appInstalado), "3.25.0", "o app em uso volta ao lugar")
    }

    // MARK: - Quando não dá para instalar no lugar

    func testBloqueios() throws {
        let publicado = try publicar(versao: "3.26.0")
        let ok = instalador(publicado: publicado)
        let comAssinatura = release("v3.26.0", zip: publicado.zip, sig: publicado.sig)
        XCTAssertNil(ok.blocker(for: comAssinatura))

        XCTAssertNotNil(ok.blocker(for: release("v3.26.0", zip: publicado.zip, sig: nil)), "release sem .sig (anterior à 3.26.0)")

        let http = ReleaseInfo(tagName: "v3.26.0", htmlURL: URL(string: "https://example.test/r")!, assets: [
            .init(name: "MoBaile-3.26.0-macOS.zip", browserDownloadURL: URL(string: "http://example.test/a.zip")!),
            .init(name: "MoBaile-3.26.0-macOS.zip.sig", browserDownloadURL: URL(string: "http://example.test/a.zip.sig")!),
        ])
        XCTAssertNotNil(ok.blocker(for: http), "HTTP só em loopback")
        XCTAssertTrue(UpdateInstaller.isAllowed(URL(string: "http://127.0.0.1:8765/a.zip")!))

        var transladado = ok
        transladado.bundleURL = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Mo baile (nativo).app")
        XCTAssertEqual(transladado.blocker(for: comAssinatura),
                       "Para atualizar com um clique, mova o Mo baile para a pasta Aplicativos e abra de novo.")

        var desenvolvimento = ok
        desenvolvimento.bundleURL = raiz.appendingPathComponent(".build/debug")
        XCTAssertEqual(desenvolvimento.blocker(for: comAssinatura), "Só o app empacotado se atualiza sozinho.")

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: pastaApps.path)
        XCTAssertNotNil(ok.blocker(for: comAssinatura), "pasta sem permissão de escrita")
    }

    // MARK: - Ajudante que reabre

    func testAjudanteSobeForaDoProcesso() throws {
        let marca = raiz.appendingPathComponent("marca")
        try UpdateInstaller.spawnDetached("/bin/sh", ["-c", "echo ok > \"$1\"", "teste", marca.path])
        let limite = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: marca.path), Date() < limite { usleep(20_000) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marca.path))
    }

    func testScriptEsperaOProcessoSairAntesDeApagar() throws {
        let espera = Process()
        espera.executableURL = URL(fileURLWithPath: "/bin/sleep")
        espera.arguments = ["1"]
        try espera.run()

        let lixo = raiz.appendingPathComponent("lixo", isDirectory: true)
        try FileManager.default.createDirectory(at: lixo, withIntermediateDirectories: true)
        // Caminho que não existe: o `open` falha calado e nada abre no teste.
        let inexistente = raiz.appendingPathComponent("nao-existe.app").path
        try UpdateInstaller.spawnDetached("/bin/sh", ["-c", UpdateInstaller.relaunchScript, "teste",
                                                      String(espera.processIdentifier), inexistente, lixo.path])
        usleep(400_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lixo.path), "com o processo vivo, não mexe em nada")

        espera.waitUntilExit()
        let limite = Date().addingTimeInterval(5)
        while FileManager.default.fileExists(atPath: lixo.path), Date() < limite { usleep(50_000) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: lixo.path), "depois que o app sai, apaga o anterior")
    }

    // MARK: - Assinatura

    func testAssinaturaEd25519() throws {
        let dados = Data("zip".utf8)
        let assinatura = try chave.signature(for: dados)
        XCTAssertEqual(UpdateSignature.parse(assinatura.base64EncodedString() + "\n"), assinatura)
        XCTAssertNil(UpdateSignature.parse("não é base64"))
        XCTAssertNil(UpdateSignature.parse(Data(count: 10).base64EncodedString()), "precisa de 64 bytes")
        XCTAssertTrue(UpdateSignature.isValid(signature: assinatura, for: dados, keys: ["lixo", chavePublica]))
        XCTAssertFalse(UpdateSignature.isValid(signature: assinatura, for: Data("outro".utf8), keys: [chavePublica]))
        XCTAssertFalse(UpdateSignature.isValid(signature: assinatura, for: dados), "a chave de teste não é a do app")
    }

    func testChavesEmbutidasSaoChavesValidas() {
        XCTAssertFalse(UpdateSignature.publicKeys.isEmpty)
        for texto in UpdateSignature.publicKeys {
            let bruto = Data(base64Encoded: texto)
            XCTAssertNotNil(bruto.flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }, texto)
        }
    }
}
