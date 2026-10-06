import XCTest
@testable import MoBaile

@MainActor
final class EngineSessionReliabilityTests: XCTestCase {
    private enum WaitError: Error { case timedOut }

    private func waitUntil(_ description: String, _ condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while clock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Prazo esgotado esperando: \(description)")
        throw WaitError.timedOut
    }

    private func dump(named name: String) throws -> Data {
        let fixtures = try resultadosDasFixtures()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(fixtures["hierarchy.dump"])) as? [String: Any])
        var elements = try XCTUnwrap(root["elements"] as? [[String: Any]])
        elements[0]["text"] = name
        root["elements"] = elements
        return try JSONSerialization.data(withJSONObject: root)
    }

    func testHierarchyOfPreviousDeviceCannotOverwriteCurrentDevice() async throws {
        let state = AppState()
        state.selectedDevice = "device-a"
        let engine = FakeEngine(respostas: try resultadosDasFixtures())
        let session = EngineSession(state: state, client: engine)
        await engine.enfileirar("hierarchy.dump", [try dump(named: "Device A"), try dump(named: "Device B")])
        await engine.responder("session.select_device", com: Data(#"{"platform":"android","device_id":"device-b"}"#.utf8))
        await engine.reter("hierarchy.dump")

        let oldDump = Task { await session.refreshHierarchy() }
        try await waitUntil("dump do aparelho A retido") { await engine.quantasRetidas("hierarchy.dump") == 1 }
        let change = Task { await session.select(deviceID: "device-b") }
        try await waitUntil("dump do aparelho B retido") { await engine.quantasRetidas("hierarchy.dump") == 2 }
        await engine.liberarUltima("hierarchy.dump")
        await change.value
        XCTAssertEqual(state.hierarchyElements.first?.text, "Device B")
        await engine.liberar("hierarchy.dump")
        await oldDump.value

        XCTAssertEqual(state.hierarchyElements.first?.text, "Device B", "árvore antiga substituiu a árvore do alvo atual")
    }

    func testOlderHierarchyResponseCannotOverwriteLatestRefreshOnSameDevice() async throws {
        let state = AppState()
        state.selectedDevice = "device-a"
        let engine = FakeEngine(respostas: try resultadosDasFixtures())
        let session = EngineSession(state: state, client: engine)
        await engine.enfileirar("hierarchy.dump", [try dump(named: "Before navigation"), try dump(named: "After navigation")])
        await engine.reter("hierarchy.dump")
        let oldDump = Task { await session.refreshHierarchy() }
        try await waitUntil("primeiro dump retido") { await engine.quantasRetidas("hierarchy.dump") == 1 }
        let newDump = Task { await session.refreshHierarchy() }
        try await waitUntil("segundo dump retido") { await engine.quantasRetidas("hierarchy.dump") == 2 }
        await engine.liberarUltima("hierarchy.dump")
        await newDump.value
        await engine.liberar("hierarchy.dump")
        await oldDump.value

        XCTAssertEqual(state.hierarchyElements.first?.text, "After navigation")
    }

    func testFailedResetPreservesRecordedStepsAndManualCode() async throws {
        let state = AppState()
        let engine = FakeEngine(respostas: try resultadosDasFixtures(), erros: ["codegen.reset": .engine(code: "reset_failed", message: "Falha ao limpar passos")])
        let session = EngineSession(state: state, client: engine)
        await session.refreshSteps()
        let stepCount = state.steps.count
        XCTAssertGreaterThan(stepCount, 0)
        state.actionsCode = "manual actions"
        state.locatorsCode = "manual locators"

        await session.clearSteps()

        XCTAssertEqual(state.steps.count, stepCount)
        XCTAssertEqual(state.actionsCode, "manual actions")
        XCTAssertEqual(state.locatorsCode, "manual locators")
        XCTAssertEqual(session.lastError, "Falha ao limpar passos")
    }

    func testSuccessfulResetClearsStepsAndBothEditors() async throws {
        let state = AppState()
        let engine = FakeEngine(respostas: try resultadosDasFixtures())
        let session = EngineSession(state: state, client: engine)
        await session.refreshSteps()
        XCTAssertFalse(state.steps.isEmpty)
        state.actionsCode = "manual actions"
        state.locatorsCode = "manual locators"

        await session.clearSteps()

        XCTAssertTrue(state.steps.isEmpty)
        XCTAssertEqual(state.actionsCode, "")
        XCTAssertEqual(state.locatorsCode, "")
        XCTAssertNil(session.lastError)
    }

    func testFailedTrafficClearPreservesCapturedEvidenceAndSelection() async throws {
        let state = AppState()
        let fixtures = try resultadosDasFixtures()
        state.httpRequests = [NetworkEvent(id: 7, timestamp: Date(timeIntervalSince1970: 1_000), timeStr: "12:00", method: "GET", url: "https://example.com/test", host: "example.com", path: "/test", statusCode: 200, statusText: "OK", requestHeaders: [:], requestBody: "", responseHeaders: [:], responseBody: "evidence", durationMs: 50, protocol: "HTTP/1.1", isTunnel: false)]
        state.selectedRequest = state.httpRequests.first
        XCTAssertFalse(state.httpRequests.isEmpty)
        let count = state.httpRequests.count
        let selectedID = state.selectedRequest?.id
        let engine = FakeEngine(respostas: fixtures, erros: ["proxy.clear": .engine(code: "clear_failed", message: "Falha ao limpar tráfego")])
        let session = EngineSession(state: state, client: engine)

        await session.clearTraffic()

        XCTAssertEqual(state.httpRequests.count, count)
        XCTAssertEqual(state.selectedRequest?.id, selectedID)
        XCTAssertEqual(session.lastError, "Falha ao limpar tráfego")
    }

    func testFailedAnalyticsClearPreservesCapturedEventsAndSelection() async throws {
        let state = AppState()
        let fixtures = try resultadosDasFixtures()
        state.analyticsEvents = [AnalyticsEvent(id: 8, timestamp: Date(timeIntervalSince1970: 1_000), timeStr: "12:00", tag: "FA", eventName: "screen_view", params: ["screen": "checkout"], rawLog: "screen_view", platform: .android)]
        state.selectedAnalyticsEvent = state.analyticsEvents.first
        XCTAssertFalse(state.analyticsEvents.isEmpty)
        let count = state.analyticsEvents.count
        let selectedID = state.selectedAnalyticsEvent?.id
        let engine = FakeEngine(respostas: fixtures, erros: ["analytics.clear": .engine(code: "clear_failed", message: "Falha ao limpar analytics")])
        let session = EngineSession(state: state, client: engine)

        await session.clearAnalytics()

        XCTAssertEqual(state.analyticsEvents.count, count)
        XCTAssertEqual(state.selectedAnalyticsEvent?.id, selectedID)
        XCTAssertEqual(session.lastError, "Falha ao limpar analytics")
    }

    func testFailedRecordingStopReconcilesWithEngineInsteadOfAssumingStopped() async throws {
        let state = AppState()
        state.screenRecording = true
        state.screenRecordingPath = "/tmp/recording.mp4"
        var fixtures = try resultadosDasFixtures()
        fixtures["recording.status"] = Data(#"{"recording":true,"path":"/tmp/recording.mp4","platform":"android"}"#.utf8)
        let engine = FakeEngine(respostas: fixtures, erros: ["recording.stop": .timeout(method: "recording.stop", seconds: 60)])
        let session = EngineSession(state: state, client: engine)

        await session.stopScreenRecording()

        XCTAssertTrue(state.screenRecording, "o vídeo ainda está gravando; o botão de parar deve continuar disponível")
        XCTAssertEqual(state.screenRecordingPath, "/tmp/recording.mp4")
        XCTAssertNotNil(session.lastError)
        let calls = await engine.chamadas
        XCTAssertTrue(calls.contains("recording.status"))
    }

    func testDoubleClickRecordingStartDoesNotIssueTwoStarts() async throws {
        let state = AppState()
        let engine = FakeEngine(respostas: try resultadosDasFixtures())
        let session = EngineSession(state: state, client: engine)
        await engine.reter("recording.start")
        let first = Task { await session.startScreenRecording() }
        try await waitUntil("início de gravação retido") { await engine.quantasRetidas("recording.start") == 1 }
        var secondCompleted = false
        let second = Task {
            await session.startScreenRecording()
            secondCompleted = true
        }
        try await waitUntil("segundo clique concluído ou enviado indevidamente ao motor") {
            if secondCompleted { return true }
            return await engine.quantasRetidas("recording.start") == 2
        }
        XCTAssertTrue(secondCompleted, "o clique repetido deve retornar sem iniciar outra gravação")
        await engine.liberar("recording.start")
        await first.value
        await second.value

        let calls = await engine.chamadas
        XCTAssertEqual(calls.filter { $0 == "recording.start" }.count, 1)
        XCTAssertTrue(state.screenRecording)
    }

    func testOldRecordingStatusCannotUndoAConfirmedStart() async throws {
        let state = AppState()
        let engine = FakeEngine(respostas: try resultadosDasFixtures())
        let session = EngineSession(state: state, client: engine)
        await engine.reter("recording.status")
        let refresh = Task { await session.refreshDaemonStatus() }
        try await waitUntil("estado antigo de gravação retido") { await engine.quantasRetidas("recording.status") == 1 }

        await session.startScreenRecording()
        XCTAssertTrue(state.screenRecording)
        await engine.liberar("recording.status")
        await refresh.value

        XCTAssertTrue(state.screenRecording, "um status anterior ao início desligou o indicador de gravação")
    }

    func testDaemonRefreshReflectsAutomaticRecordingStop() async throws {
        let state = AppState()
        state.screenRecording = true
        var fixtures = try resultadosDasFixtures()
        fixtures["recording.status"] = Data(#"{"recording":false,"path":"/tmp/finished.mp4","platform":"android"}"#.utf8)
        let session = EngineSession(state: state, client: FakeEngine(respostas: fixtures))

        await session.refreshDaemonStatus()

        XCTAssertFalse(state.screenRecording)
        XCTAssertEqual(state.screenRecordingPath, "/tmp/finished.mp4")
    }
}
