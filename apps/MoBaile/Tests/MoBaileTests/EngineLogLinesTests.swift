import XCTest
@testable import MoBaile

/// stderr do motor lido por linha (MEL-5).
///
/// O cano entrega pedaços de tamanho arbitrário. Decodificar cada pedaço
/// sozinho descartava o pedaço inteiro quando ele cortava um caractere UTF-8
/// no meio, e o prefixo `[motor]` caía no meio das linhas. Agora os bytes se
/// acumulam até o `\n` e só a linha completa vira texto.
final class EngineLogLinesTests: XCTestCase {

    func testCaractereMultibytePartidoEntreDoisPedacosVoltaInteiro() {
        var linhas = EngineLogLines()
        // "á" é C3 A1 em UTF-8; o primeiro pedaço termina no meio dele.
        XCTAssertEqual(linhas.append(Data([0xC3])), [])
        XCTAssertEqual(linhas.append(Data([0xA1, 0x0A])), ["á"])
    }

    func testVariasLinhasNumPedacoERestoParaOProximo() {
        var linhas = EngineLogLines()
        XCTAssertEqual(linhas.append(Data("um\r\ndois\ntr".utf8)), ["um", "dois"])
        XCTAssertEqual(linhas.append(Data("ês\n".utf8)), ["três"])
        XCTAssertNil(linhas.finish())
    }

    func testFimDeArquivoEntregaALinhaSemQuebra() {
        var linhas = EngineLogLines()
        XCTAssertEqual(linhas.append(Data("Traceback sem fim".utf8)), [])
        XCTAssertEqual(linhas.finish(), "Traceback sem fim")
        XCTAssertNil(linhas.finish(), "o resto sai uma vez só")
    }

    func testByteInvalidoNaoApagaALinha() {
        var linhas = EngineLogLines()
        XCTAssertEqual(linhas.append(Data([0x6F, 0x6B, 0xFF, 0x0A])), ["ok\u{FFFD}"])
    }

    /// Revisão da MEL-5 (R-01): um motor que despeja ~70 KB sem `\n` sai numa
    /// linha só, e o buffer volta a zero em vez de crescer sem fim.
    func testLinhaSemQuebraAcimaDoTetoSaiEOBufferZera() {
        var linhas = EngineLogLines()
        let pedaco = Data(repeating: 0x61, count: 10 * 1024)  // "a" × 10 KB
        var emitidas: [String] = []
        for _ in 0..<7 {
            emitidas += linhas.append(pedaco)
        }

        XCTAssertEqual(emitidas.count, 1)
        XCTAssertEqual(emitidas.first?.utf8.count, 70 * 1024)
        XCTAssertNil(linhas.finish(), "o buffer devia ter voltado a zero")
        XCTAssertEqual(linhas.append(Data("depois\n".utf8)), ["depois"])
    }

    // MARK: - Mensagem de queda

    func testQuedaCitaOLogDoMotorQuandoConhecido() {
        let erro = EngineError.processTerminated(3, logPath: "/Users/qa/Library/Logs/Mo baile/engine.log")
        let texto = erro.errorDescription ?? ""
        XCTAssertTrue(texto.contains("codigo 3"), texto)
        XCTAssertTrue(texto.contains("/Users/qa/Library/Logs/Mo baile/engine.log"), texto)
    }

    func testQuedaSemLogConhecidoTemTextoGenerico() {
        let texto = EngineError.processTerminated(9).errorDescription ?? ""
        XCTAssertTrue(texto.contains("codigo 9"), texto)
        XCTAssertFalse(texto.contains("nil"), texto)
        XCTAssertFalse(texto.contains("/"), "sem caminho inventado: \(texto)")
    }

    // MARK: - Contrato

    func testHelloEInfoDecodificamLogPath() throws {
        let fixtures = try resultadosDasFixtures()
        let hello = try JSONDecoder().decode(EngineDTO.Hello.self, from: XCTUnwrap(fixtures["engine.hello"]))
        XCTAssertEqual(hello.logPath, "/Users/qa/Library/Logs/Mo baile/engine.log")
        let info = try JSONDecoder().decode(EngineDTO.EngineInfo.self, from: XCTUnwrap(fixtures["engine.info"]))
        XCTAssertEqual(info.logPath, "/Users/qa/Library/Logs/Mo baile/engine.log")
    }

    func testMotorAntigoSemLogPathAindaDecodifica() throws {
        let semCampo = Data(#"{"protocol_version":2,"engine_version":"3.11.0","capabilities":[],"methods":{},"notifications":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(EngineDTO.Hello.self, from: semCampo).logPath)
    }
}
