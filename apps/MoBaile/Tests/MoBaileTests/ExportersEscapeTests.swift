import XCTest
@testable import MoBaile

/// M12: o cURL copiado e o código gerado usam dados do tráfego do app sob
/// teste, que não é confiável. Aspas e quebras de linha não podem escapar do
/// literal nem virar comando no terminal de quem cola.
@MainActor
final class ExportersEscapeTests: XCTestCase {
    private func evento(
        metodo: String = "GET",
        url: String,
        headers: [String: String] = [:],
        corpo: String = ""
    ) -> NetworkEvent {
        NetworkEvent(
            id: 1, timestamp: Date(), timeStr: "", method: metodo, url: url, host: "", path: "",
            statusText: "", requestHeaders: headers, requestBody: corpo, responseHeaders: [:],
            responseBody: "", protocol: "HTTP/1.1", isTunnel: false
        )
    }

    /// Roda o comando num `sh` com `curl` trocado por `printf`: o que o shell
    /// interpretar como comando executa de verdade, e o que for argumento sai
    /// impresso. Devolve a saída e o status.
    private func executaTrocandoCurl(_ comando: String) throws -> (saida: String, status: Int32) {
        XCTAssertTrue(comando.hasPrefix("curl "))
        let seguro = "printf '%s\\n' " + comando.dropFirst("curl ".count)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", seguro]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let dados = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(decoding: dados, as: UTF8.self), p.terminationStatus)
    }

    func testCurlComAspaNaURLNaoExecutaNada() throws {
        let marca = "/tmp/mobaile-pwn-\(UUID().uuidString)"
        let url = "https://x.test/a'$(touch \(marca))'/b"
        let (saida, status) = try executaTrocandoCurl(Exporters.curl(for: evento(url: url)))
        XCTAssertEqual(status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marca), "o comando da URL foi executado")
        XCTAssertTrue(saida.contains(url), "a URL tem de chegar inteira ao curl como um argumento")
    }

    func testMetodoEstranhoVaiEntreAspas() throws {
        let marca = "/tmp/mobaile-pwn-\(UUID().uuidString)"
        let (saida, status) = try executaTrocandoCurl(
            Exporters.curl(for: evento(metodo: "GET;touch \(marca)", url: "https://x.test/"))
        )
        XCTAssertEqual(status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marca))
        XCTAssertTrue(saida.contains("GET;touch \(marca)"))
    }

    func testMetodoHTTPComumFicaSemAspas() {
        XCTAssertTrue(Exporters.curl(for: evento(url: "https://x.test/")).hasPrefix("curl -X GET 'https://x.test/'"))
    }

    func testNomeDeHeaderComAspaNaoQuebraAspas() throws {
        let marca = "/tmp/mobaile-pwn-\(UUID().uuidString)"
        let nome = "X-A'; touch \(marca); echo '"
        let (_, status) = try executaTrocandoCurl(
            Exporters.curl(for: evento(url: "https://x.test/", headers: [nome: "1"]))
        )
        XCTAssertEqual(status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marca))
    }

    func testCorpoComAspaContinuaIntacto() throws {
        let (saida, status) = try executaTrocandoCurl(
            Exporters.curl(for: evento(metodo: "POST", url: "https://x.test/", corpo: "{\"a\":\"it's\"}"))
        )
        XCTAssertEqual(status, 0)
        XCTAssertTrue(saida.contains("{\"a\":\"it's\"}"))
    }

    func testLiteralPythonEscapaAspaBarraEQuebra() {
        XCTAssertEqual(Exporters.pythonStringLiteral("/a'),__import__('os')#"), "'/a\\'),__import__(\\'os\\')#'")
        XCTAssertEqual(Exporters.pythonStringLiteral("a\nb\\c\r"), "'a\\nb\\\\c\\r'")
        XCTAssertEqual(Exporters.pythonStringLiteral("/ok/caminho"), "'/ok/caminho'")
        XCTAssertEqual(Exporters.pythonStringLiteral("a\u{01}b"), "'a\\x01b'")
    }
}
