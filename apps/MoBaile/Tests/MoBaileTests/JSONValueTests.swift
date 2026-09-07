import XCTest
@testable import MoBaile

/// Serializacao dos parametros enviados ao motor.
///
/// O que sai daqui vira uma linha no stdin do processo Python. Um numero
/// codificado como string, ou um `nil` que some do objeto, quebra a validacao
/// do outro lado com uma mensagem dificil de rastrear.
final class JSONValueTests: XCTestCase {

    private func encode(_ value: [String: JSONValue]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func testTiposBasicosMantemOTipoNoJSON() throws {
        let json = try encode([
            "x": .int(120),
            "fps": .double(6.5),
            "ligado": .bool(true),
            "nome": .string("emulator-5554"),
        ])
        XCTAssertTrue(json.contains("\"x\":120"), "inteiro nao pode virar string")
        XCTAssertTrue(json.contains("\"fps\":6.5"))
        XCTAssertTrue(json.contains("\"ligado\":true"))
        XCTAssertTrue(json.contains("\"nome\":\"emulator-5554\""))
    }

    func testNuloEEnviadoExplicitamente() throws {
        // `device_id: null` significa "nenhum dispositivo" no contrato. Omitir a
        // chave significaria "manter o atual", que e outra coisa.
        let json = try encode(["device_id": .null])
        XCTAssertEqual(json, "{\"device_id\":null}")
    }

    func testTextoComAspasEAcentoSobreviveAoTransporte() throws {
        let original = "campo \"nome\" com acento: ação"
        let json = try encode(["text": .string(original)])
        let voltou = try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
        XCTAssertEqual(voltou["text"], .string(original))
    }

    func testEstruturaAninhadaFazIdaEVolta() throws {
        let original: JSONValue = .object([
            "lista": .array([.int(1), .string("dois"), .bool(false), .null]),
            "interno": .object(["chave": .double(1.5)]),
        ])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), original)
    }

    func testLiteraisReduzemRuidoNaChamada() {
        // Acucar para montar parametros sem repetir `.string(...)` em toda linha.
        let params: [String: JSONValue] = ["platform": "android", "limit": 200, "configure": true]
        XCTAssertEqual(params["platform"], .string("android"))
        XCTAssertEqual(params["limit"], .int(200))
        XCTAssertEqual(params["configure"], .bool(true))
    }
}
