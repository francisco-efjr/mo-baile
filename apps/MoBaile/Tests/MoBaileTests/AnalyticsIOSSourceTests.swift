import XCTest
@testable import MoBaile

/// Origem do tagueamento no iOS: simulador da sessão ou iPhone por cabo.
@MainActor
final class AnalyticsIOSSourceTests: XCTestCase {

    private let iphone = Data(#"""
    {"available": true, "devices": [
        {"udid": "00008020-001549180128402E", "name": "iPhone XR", "ios_version": "18.7", "connection": "USB"},
        {"udid": "00008030-AAAA", "name": "iPhone bloqueado", "ios_version": "17.0", "connection": "USB",
         "problem": "Desbloqueie o iPhone e tente de novo."}
    ]}
    """#.utf8)

    private func sessao(_ estado: AppState) -> (EngineSession, FakeEngine) {
        let motor = FakeEngine(respostas: [
            "analytics.ios_devices": iphone,
            "analytics.start": Data(#"{"running": true, "source": "ios_device", "device_id": "x"}"#.utf8),
        ])
        return (EngineSession(state: estado, client: motor), motor)
    }

    func testListaIPhonesComMotivoDeIndisponivel() async {
        let estado = AppState()
        let (sessao, _) = sessao(estado)

        await sessao.refreshAnalyticsIOSDevices()

        XCTAssertEqual(estado.analyticsIOSDevices.map(\.name), ["iPhone XR", "iPhone bloqueado"])
        XCTAssertEqual(estado.analyticsIOSDevices[0].iosVersion, "18.7")
        XCTAssertNil(estado.analyticsIOSDevices[0].problem)
        XCTAssertNotNil(estado.analyticsIOSDevices[1].problem)
    }

    /// Sem simulador ligado o botão ficava desabilitado, mesmo com o iPhone no cabo.
    func testIPhonePorCaboHabilitaAEscutaSemSimulador() async {
        let estado = AppState()
        estado.platform = .ios
        let (sessao, _) = sessao(estado)
        XCTAssertFalse(estado.canStartAnalytics)

        await sessao.refreshAnalyticsIOSDevices()

        XCTAssertNil(estado.selectedDevice)
        XCTAssertTrue(estado.canStartAnalytics)
        estado.analyticsIOSSource = .simulator
        XCTAssertFalse(estado.canStartAnalytics, "simulador escolhido, mas nenhum ligado")
    }

    func testIniciarNoIOSMandaAOrigemEscolhida() async {
        let estado = AppState()
        estado.platform = .ios
        estado.analyticsIOSSource = .device(udid: "00008020-001549180128402E")
        let (sessao, motor) = sessao(estado)

        await sessao.toggleAnalytics()

        let params = await motor.parametros(de: "analytics.start")
        XCTAssertEqual(params?["ios_source"], .string("00008020-001549180128402E"))
        XCTAssertTrue(estado.analyticsListenerActive)
    }

    func testIniciarNoAndroidNaoMandaOrigemIOS() async {
        let estado = AppState()
        estado.platform = .android
        let (sessao, motor) = sessao(estado)

        await sessao.toggleAnalytics()

        let params = await motor.parametros(de: "analytics.start")
        XCTAssertNil(params?["ios_source"])
    }

    func testIPhoneDesconectadoVoltaParaOAutomatico() async {
        let estado = AppState()
        estado.analyticsIOSSource = .device(udid: "UDID-QUE-SAIU")
        let (sessao, _) = sessao(estado)

        await sessao.refreshAnalyticsIOSDevices()

        XCTAssertEqual(estado.analyticsIOSSource, .auto)
    }
}
