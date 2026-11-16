import XCTest
@testable import MoBaile

/// F11: o quadro do espelho pode vir em JPEG (`image_base64` + `format`) ou,
/// de um motor anterior, em `png_base64`. Os dois decodificam.
final class FrameFormatTests: XCTestCase {
    private let jpeg1x1 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDzqiiivjj+kT//2Q=="
    private let png1x1 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    private func decode(_ json: String) throws -> EngineDTO.Frame {
        try JSONDecoder().decode(EngineDTO.Frame.self, from: Data(json.utf8))
    }

    func testQuadroJPEGDecodifica() throws {
        let frame = try decode(#"{"format":"jpeg","image_base64":"\#(jpeg1x1)","width":1,"height":1,"source_width":1,"source_height":1}"#)
        XCTAssertEqual(frame.format, "jpeg")
        XCTAssertNil(frame.pngBase64)
        XCTAssertNotNil(frame.image)
        XCTAssertEqual(frame.image?.size, NSSize(width: 1, height: 1))
    }

    func testQuadroPNGAntigoContinuaDecodificando() throws {
        let frame = try decode(#"{"png_base64":"\#(png1x1)","width":1,"height":1,"source_width":1,"source_height":1}"#)
        XCTAssertNil(frame.format)
        XCTAssertNotNil(frame.image)
    }

    func testQuadroPNGNovoPrefereImageBase64() throws {
        let frame = try decode(#"{"format":"png","image_base64":"\#(png1x1)","png_base64":"\#(png1x1)","width":1,"height":1,"source_width":1,"source_height":1}"#)
        XCTAssertNotNil(frame.image)
    }

    func testSemImagemNenhumaNaoDecodifica() throws {
        let frame = try decode(#"{"width":1,"height":1,"source_width":1,"source_height":1}"#)
        XCTAssertNil(frame.image)
    }

    func testFixtureDoMotorDecodifica() throws {
        let url = Bundle.module.url(forResource: "engine_payloads", withExtension: "json")!
        let todas = try JSONDecoder().decode([String: JSONValue].self, from: Data(contentsOf: url))
        guard case let .object(envelope)? = todas["notif_stream.frame"],
              case let .object(params)? = envelope["params"] else {
            return XCTFail("fixture notif_stream.frame ausente")
        }
        let data = try JSONEncoder().encode(JSONValue.object(params))
        let frame = try JSONDecoder().decode(EngineDTO.Frame.self, from: data)
        XCTAssertNotNil(frame.image)
    }
}
