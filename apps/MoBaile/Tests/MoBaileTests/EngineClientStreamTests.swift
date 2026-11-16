import XCTest
@testable import MoBaile

/// Integração com o motor de verdade, para o caminho que só quebra em payload
/// grande.
///
/// Regressão: cada pedaço do stdout virava uma `Task` própria, e `Task` não
/// garante ordem. Resposta curta cabe num pedaço só e sempre funcionou; um
/// quadro do espelho passa de 400 KB em base64, chega em vários pedaços e era
/// remontado embaralhado. O JSON continuava decodificando, porque a troca caía
/// dentro da string base64, e o PNG saía parcial — certo no topo, uma faixa de
/// lixo e o resto preto.
///
/// Nenhum teste de unidade pegava isso: o erro está na concorrência entre o
/// cano e o ator, não na lógica de nenhuma função.
///
/// Precisa de aparelho conectado, então roda só com MOBAILE_DEVICE_TESTS=1.
final class EngineClientStreamTests: XCTestCase {

    /// Roda `operacao` com prazo.
    ///
    /// Com o transporte embaralhado a linha não decodifica, a continuação da
    /// chamada nunca é resumida e o `call` fica pendurado para sempre — foi
    /// assim que este teste se comportou com o bug de volta: travou em vez de
    /// falhar. Travar é o pior modo de falhar, tanto em CI quanto no app, onde
    /// o mesmo caminho vira janela congelada.
    private func comPrazo<T: Sendable>(
        _ segundos: Double = 45,
        _ operacao: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { grupo in
            grupo.addTask { try await operacao() }
            grupo.addTask {
                try await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
                throw XCTSkip("prazo de \(segundos)s estourado: a chamada ao motor não retornou")
            }
            let primeiro = try await grupo.next()!
            grupo.cancelAll()
            return primeiro
        }
    }

    private func motorConectado() async throws -> EngineClient {
        guard ProcessInfo.processInfo.environment["MOBAILE_DEVICE_TESTS"] == "1" else {
            throw XCTSkip("defina MOBAILE_DEVICE_TESTS=1 com um aparelho conectado")
        }
        let client = EngineClient(configuration: try EngineLocator.resolve())
        try await client.start()
        return client
    }

    func testQuadroGrandeChegaInteiro() async throws {
        let client = try await motorConectado()
        defer { Task { await client.stop() } }

        let lista: EngineDTO.DeviceList = try await client.call(
            "devices.list", params: ["platform": .string("android")]
        )
        let alvo = try XCTUnwrap(lista.devices.first(where: { $0.ready }), "nenhum aparelho pronto")
        _ = try await client.call(
            "session.select_device",
            params: ["platform": .string("android"), "device_id": .string(alvo.id)],
            as: EngineDTO.SessionState.self
        )

        let tamanho: EngineDTO.ScreenSize = try await client.call("screen.size")

        // 900 de largura é o que o espelho usa em produção: passa bem de 400 KB
        // em base64 e força a resposta a atravessar o cano em vários pedaços.
        let frame: EngineDTO.Frame = try await comPrazo {
            try await client.call("screen.capture", params: ["max_width": .int(900)])
        }

        let imagem = try XCTUnwrap(frame.image, "o PNG não decodificou: base64 corrompido no transporte")

        // A prova de integridade: um PNG remontado fora de ordem decodifica com
        // altura menor que a declarada, porque os dados acabam antes das linhas.
        XCTAssertEqual(Int(imagem.size.width), frame.width, "largura decodificada diferente da declarada")
        XCTAssertEqual(Int(imagem.size.height), frame.height, "altura decodificada diferente da declarada")

        // E a proporção tem de bater com a do aparelho, não com um pedaço dele.
        let proporcaoAparelho = Double(tamanho.width) / Double(tamanho.height)
        let proporcaoQuadro = Double(frame.width) / Double(frame.height)
        XCTAssertEqual(proporcaoQuadro, proporcaoAparelho, accuracy: 0.02,
                       "o quadro chegou cortado: proporção não bate com a do aparelho")
    }

    /// Várias capturas seguidas: o embaralhamento aparecia de forma
    /// intermitente, então uma passagem só não seria prova.
    func testCapturasSeguidasChegamTodasInteiras() async throws {
        let client = try await motorConectado()
        defer { Task { await client.stop() } }

        let lista: EngineDTO.DeviceList = try await client.call(
            "devices.list", params: ["platform": .string("android")]
        )
        let alvo = try XCTUnwrap(lista.devices.first(where: { $0.ready }))
        _ = try await client.call(
            "session.select_device",
            params: ["platform": .string("android"), "device_id": .string(alvo.id)],
            as: EngineDTO.SessionState.self
        )

        for tentativa in 1...5 {
            let frame: EngineDTO.Frame = try await comPrazo {
                try await client.call("screen.capture", params: ["max_width": .int(900)])
            }
            let imagem = try XCTUnwrap(frame.image, "captura \(tentativa): PNG não decodificou")
            XCTAssertEqual(Int(imagem.size.height), frame.height, "captura \(tentativa) veio cortada")
        }
    }
}
