import XCTest
@testable import MoBaile

/// Tráfego HTTPS do app em debug sem proxy, nas duas plataformas.
///
/// Antes só o iPhone tinha o recurso ("iPhone em Debug"). No Android, a pessoa
/// que depura no Android Studio via as URLs no App Inspection e não no Mo baile.
@MainActor
final class DebugNetTests: XCTestCase {

    private func sessao(fonte: String) -> (AppState, EngineSession, FakeEngine) {
        let estado = AppState()
        let resposta = #"{"running": true, "device_id": "emulator-5554", "raw_log": null, "source": "\#(fonte)"}"#
        let motor = FakeEngine(respostas: [
            "netlog.start": Data(resposta.utf8),
            "netlog.stop": Data(#"{"running": false}"#.utf8),
        ])
        return (estado, EngineSession(state: estado, client: motor), motor)
    }

    func testAndroidLigaPeloLogcatEExplicaORequisito() async {
        let (estado, sessao, motor) = sessao(fonte: "okhttp_logcat")
        await sessao.toggleDebugNet()
        XCTAssertTrue(estado.debugNetActive)
        XCTAssertTrue(estado.statusMessage.contains("HttpLoggingInterceptor"), estado.statusMessage)
        let chamadas = await motor.chamadas
        XCTAssertEqual(chamadas, ["netlog.start"])

        await sessao.toggleDebugNet()
        XCTAssertFalse(estado.debugNetActive)
        let depois = await motor.chamadas
        XCTAssertEqual(depois, ["netlog.start", "netlog.stop"])
    }

    func testIPhoneContinuaPedindoOCFNetwork() async {
        let (estado, sessao, _) = sessao(fonte: "cfnetwork")
        await sessao.toggleDebugNet()
        XCTAssertTrue(estado.statusMessage.contains("CFNETWORK_DIAGNOSTICS"), estado.statusMessage)
    }

    func testFalhaDeixaDesligado() async {
        let estado = AppState()
        let motor = FakeEngine(respostas: [:], erros: [
            "netlog.start": .engine(code: "device_not_found", message: "Selecione um aparelho Android para ler o tráfego do app em debug."),
        ])
        let sessao = EngineSession(state: estado, client: motor)
        await sessao.toggleDebugNet()
        XCTAssertFalse(estado.debugNetActive)
        XCTAssertTrue(estado.statusMessage.contains("aparelho Android"), estado.statusMessage)
    }

    func testTextosPorPlataforma() {
        XCTAssertEqual(DebugNetCopy(.ios).titulo, "iPhone em Debug")
        XCTAssertEqual(DebugNetCopy(.android).titulo, "App em Debug")
        XCTAssertTrue(DebugNetCopy(.android).ajuda.contains("Android Studio"))
        XCTAssertNotEqual(DebugNetCopy(.ios).iniciarAcessivel, DebugNetCopy(.android).iniciarAcessivel)
    }

    func testMotorAntigoSemFonteAindaDecodifica() throws {
        let antigo = try JSONDecoder().decode(EngineDTO.NetlogState.self,
                                              from: Data(#"{"running": true, "device_id": "X", "raw_log": "/tmp/a.log"}"#.utf8))
        XCTAssertNil(antigo.source)
    }
}
