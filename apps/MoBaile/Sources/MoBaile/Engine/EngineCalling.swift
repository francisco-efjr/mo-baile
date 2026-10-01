import Foundation

/// A superfície do motor que a sessão consome.
///
/// `EngineSession` guardava um `EngineClient` concreto, criado dentro do
/// próprio `connect()`. Isso deixava a sessão impossível de testar sem subir um
/// processo Python de verdade, e o resultado apareceu na prática: a suíte tinha
/// 45 testes verdes enquanto a tela conectava com o espelho em branco, porque
/// nenhum teste conseguia observar quais chamadas a sessão faz.
///
/// O protocolo existe para essa costura. Em produção quem conforma é o
/// `EngineClient`; no teste, um duplo que responde com as fixtures reais do
/// motor.
///
/// Os três fluxos e o ciclo de vida fazem parte da costura porque a sessão
/// supervisiona o motor: sem eles, o reinício automático só seria testável
/// matando um processo Python de verdade.
protocol EngineCalling: Actor {
    /// Notificações ordenadas e sem perda (tudo menos `stream.frame`).
    nonisolated var notifications: AsyncStream<EngineNotification> { get }
    /// `stream.frame`, guardando só o mais novo.
    nonisolated var frames: AsyncStream<EngineNotification> { get }
    /// Código de saída quando o motor morre sem ter sido parado.
    nonisolated var terminations: AsyncStream<Int32> { get }

    func start() throws

    func call<Response: Decodable>(
        _ method: String,
        params: [String: JSONValue],
        as type: Response.Type
    ) async throws -> Response

    func callIgnoringResult(_ method: String, params: [String: JSONValue]) async throws

    /// Prazos por método, vindos do `engine.hello`.
    func useMethodTable(_ table: [String: EngineDTO.MethodSpec])

    /// Encerramento ordenado: pode esperar o motor desmontar antes de voltar.
    func stop() async
}

/// Conveniências com os mesmos padrões que o cliente concreto oferece.
///
/// Requisito de protocolo não aceita valor padrão de parâmetro, e sem estas
/// sobrecargas cada chamada da sessão teria de repetir `params:` e `as:`. As
/// aridades são distintas da exigência do protocolo de propósito: é o que
/// impede a chamada de recair sobre si mesma.
extension EngineCalling {
    func call<Response: Decodable>(
        _ method: String,
        params: [String: JSONValue] = [:]
    ) async throws -> Response {
        try await call(method, params: params, as: Response.self)
    }

    func call<Response: Decodable>(
        _ method: String,
        as type: Response.Type
    ) async throws -> Response {
        try await call(method, params: [:], as: type)
    }

    func callIgnoringResult(_ method: String) async throws {
        try await callIgnoringResult(method, params: [:])
    }
}

extension EngineClient: EngineCalling {}
