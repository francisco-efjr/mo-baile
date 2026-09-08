import AppKit
import Foundation

/// Estruturas espelhando exatamente o JSON do motor, e a traducao para os
/// modelos que a interface usa.
///
/// Sao tipos separados dos modelos de apresentacao de proposito. O contrato do
/// motor usa `snake_case` e tipos crus (limites como lista de quatro inteiros,
/// duracao em ponto flutuante); a interface quer `CGRect` e `Date`. Misturar as
/// duas coisas num tipo so faria a menor mudanca no contrato virar alteracao em
/// dezenas de telas.
enum EngineDTO {

    // MARK: - Dispositivos

    struct DeviceList: Decodable {
        let devices: [Device]
    }

    struct Device: Decodable {
        let id: String
        let name: String
        let platform: String
        let state: String
        let ready: Bool
    }

    // MARK: - Tela

    struct Frame: Decodable {
        let pngBase64: String
        let width: Int
        let height: Int
        let sourceWidth: Int
        let sourceHeight: Int
        /// Métricas que viajam junto com o quadro do streaming.
        ///
        /// Opcionais porque `screen.capture` (captura avulsa) não as manda:
        /// elas só existem quando há um stream medindo.
        let fps: Double?
        let captureMs: Double?
        let skipped: Int?

        enum CodingKeys: String, CodingKey {
            case pngBase64 = "png_base64"
            case width, height, fps
            case sourceWidth = "source_width"
            case sourceHeight = "source_height"
            case captureMs = "capture_ms"
            case skipped
        }

        /// Converte para imagem. `nil` quando o base64 chega corrompido, o que a
        /// camada de cima trata como quadro perdido e nao como falha de sessao.
        var image: NSImage? {
            guard let data = Data(base64Encoded: pngBase64) else { return nil }
            return NSImage(data: data)
        }
    }

    struct ScreenSize: Decodable {
        let width: Int
        let height: Int
    }

    // MARK: - Hierarquia

    struct HierarchyDump: Decodable {
        let count: Int
        let elements: [Element]
    }

    struct ElementLookup: Decodable {
        let element: Element?
    }

    struct Element: Decodable {
        let tag: String
        let className: String
        let resourceId: String
        let text: String
        let contentDesc: String
        let clickable: Bool
        let bounds: [Int]
        let area: Int
        let package: String
        let platform: String
        let depth: Int
        let parentIdx: Int?

        enum CodingKeys: String, CodingKey {
            case tag
            case className = "class_name"
            case resourceId = "resource_id"
            case text
            case contentDesc = "content_desc"
            case clickable, bounds, area, package, platform, depth
            case parentIdx = "parent_idx"
        }

        var rect: CGRect {
            guard bounds.count == 4 else { return .zero }
            return CGRect(
                x: bounds[0],
                y: bounds[1],
                width: max(0, bounds[2] - bounds[0]),
                height: max(0, bounds[3] - bounds[1])
            )
        }

        func toModel() -> UIElement {
            UIElement(
                tag: tag,
                className: className,
                resourceId: resourceId,
                text: text,
                contentDesc: contentDesc,
                clickable: clickable,
                bounds: rect,
                area: area,
                package: package,
                platform: platform == "ios" ? .ios : .android,
                depth: depth,
                parentIndex: parentIdx
            )
        }
    }

    // MARK: - Rede

    struct NetworkEventList: Decodable {
        let events: [NetworkEventPayload]
        let total: Int
    }

    struct NetworkEventPayload: Decodable {
        let id: Int
        let timestamp: Double
        let time: String
        let method: String
        let url: String
        let host: String
        let path: String
        let statusCode: Int
        let statusText: String
        let requestHeaders: [String: String]
        let requestBody: String
        let responseHeaders: [String: String]
        let responseBody: String
        let durationMs: Double
        let networkProtocol: String
        let isTunnel: Bool
        let error: String?

        enum CodingKeys: String, CodingKey {
            case id, timestamp, time, method, url, host, path, error
            case statusCode = "status_code"
            case statusText = "status_text"
            case requestHeaders = "request_headers"
            case requestBody = "request_body"
            case responseHeaders = "response_headers"
            case responseBody = "response_body"
            case durationMs = "duration_ms"
            case networkProtocol = "protocol"
            case isTunnel = "is_tunnel"
        }

        func toModel() -> NetworkEvent {
            NetworkEvent(
                id: id,
                timestamp: Date(timeIntervalSince1970: timestamp),
                timeStr: time,
                method: method,
                url: url,
                host: host,
                path: path,
                statusCode: statusCode,
                statusText: statusText,
                requestHeaders: requestHeaders,
                requestBody: requestBody,
                responseHeaders: responseHeaders,
                responseBody: responseBody,
                durationMs: Int(durationMs.rounded()),
                protocol: networkProtocol,
                isTunnel: isTunnel,
                error: error
            )
        }
    }

    // MARK: - Analytics

    struct AnalyticsEventList: Decodable {
        let events: [AnalyticsEventPayload]
    }

    struct AnalyticsEventPayload: Decodable {
        let id: Int
        let time: String
        let timestamp: Double
        let platform: String
        let tag: String
        let eventName: String
        let params: [String: JSONValue]
        let rawLog: String

        enum CodingKeys: String, CodingKey {
            case id, time, timestamp, platform, tag, params
            case eventName = "event_name"
            case rawLog = "raw_log"
        }

        /// Parametro de analytics chega com tipo livre; a tabela exibe texto.
        private static func describe(_ value: JSONValue) -> String {
            switch value {
            case .string(let text): return text
            case .int(let number): return String(number)
            case .double(let number): return String(number)
            case .bool(let flag): return flag ? "true" : "false"
            case .null: return ""
            case .array, .object:
                guard let data = try? JSONEncoder().encode(value) else { return "" }
                return String(decoding: data, as: UTF8.self)
            }
        }

        func toModel() -> AnalyticsEvent {
            AnalyticsEvent(
                id: id,
                timestamp: Date(timeIntervalSince1970: timestamp),
                timeStr: time,
                tag: tag,
                eventName: eventName,
                params: params.mapValues(Self.describe),
                rawLog: rawLog,
                platform: platform == "ios" ? .ios : .android
            )
        }
    }

    // MARK: - Geracao de codigo

    struct RecordedStep: Decodable {
        let varName: String
        let objectCode: String
        let actionCode: String
        let element: Element
        let stepCount: Int

        enum CodingKeys: String, CodingKey {
            case varName = "var_name"
            case objectCode = "object_code"
            case actionCode = "action_code"
            case element
            case stepCount = "step_count"
        }
    }

    struct StepList: Decodable {
        let steps: [StepPayload]
    }

    struct StepPayload: Decodable {
        let stepNum: Int
        let actionType: String
        let varName: String
        let elementName: String
        let className: String
        let strategy: String
        let locatorValue: String
        let coords: [Int]
        let inputText: String?
        let package: String
        let platform: String

        enum CodingKeys: String, CodingKey {
            case stepNum = "step_num"
            case actionType = "action_type"
            case varName = "var_name"
            case elementName = "element_name"
            case className = "class_name"
            case strategy
            case locatorValue = "locator_value"
            case coords
            case inputText = "input_text"
            case package, platform
        }

        /// O motor chama a estrategia por coordenada de `position`; a interface,
        /// de `coords`. A traducao fica num lugar so, aqui.
        var mappedStrategy: LocatorStrategy {
            switch strategy {
            case "id": return .id
            case "xpath": return .xpath
            default: return .coords
            }
        }

        func toModel() -> AutomationStep {
            AutomationStep(
                stepNum: stepNum,
                actionType: actionType,
                varName: varName,
                elementName: elementName,
                className: className,
                strategy: mappedStrategy,
                locatorValue: locatorValue,
                coords: coords.count == 2 ? CGPoint(x: coords[0], y: coords[1]) : nil,
                inputText: inputText,
                package: package,
                platform: platform == "ios" ? .ios : .android
            )
        }
    }

    // MARK: - Diagnostico de ambiente

    struct Diagnostics: Decodable {
        let ios: PlatformDiagnostics
        let android: PlatformDiagnostics

        func forPlatform(_ platform: Platform) -> PlatformDiagnostics {
            platform == .ios ? ios : android
        }
    }

    struct PlatformDiagnostics: Decodable {
        let platform: String
        let title: String
        let ready: Bool
        let checks: [Check]
    }

    /// Uma linha do cartao de diagnostico, com o estado medido de verdade.
    struct Check: Decodable, Identifiable {
        let label: String
        let state: String
        let detail: String
        /// Identificador da acao que resolve, quando existe uma.
        let action: String?

        var id: String { label }

        var daemonState: DaemonState {
            switch state {
            case "ok": return .ok
            case "warn": return .warn
            case "error": return .error
            case "busy": return .busy
            default: return .off
            }
        }
    }

    struct PassiveState: Decodable {
        let listening: Bool
        let platform: String
        /// Espaço de coordenadas do alvo: pixels no Android, pontos no iOS.
        let screen: [Int]
    }

    struct FlowRun: Decodable {
        let running: Bool
        let steps: Int
        let script: String
    }

    struct SaveResult: Decodable {
        let saved: Bool
        let paths: [String]
        let directory: String
    }

    // MARK: - Gravacao de video da tela

    struct RecordingState: Decodable {
        let recording: Bool
        let path: String?
        let platform: String?
        /// Só o Android tem limite: `screenrecord` para sozinho ao atingi-lo.
        let limitSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case recording, path, platform
            case limitSeconds = "limit_s"
        }
    }

    struct RecordingResult: Decodable {
        let recording: Bool
        let path: String?
        let sizeBytes: Int
        let durationSeconds: Double

        enum CodingKeys: String, CodingKey {
            case recording, path
            case sizeBytes = "size_bytes"
            case durationSeconds = "duration_s"
        }
    }

    // MARK: - Ciclo de vida de simulador e emulador

    struct SimulatorList: Decodable {
        let simulators: [Simulator]
    }

    struct Simulator: Decodable, Identifiable {
        let udid: String
        let name: String
        let state: String
        let runtime: String
        let booted: Bool

        var id: String { udid }
        var displayName: String { "\(name) · \(runtime)" }
    }

    struct BootResult: Decodable {
        let udid: String
        let message: String
        let booted: Bool
    }

    struct AvdList: Decodable {
        let avds: [String]
    }

    struct AvdBootResult: Decodable {
        let name: String
        let starting: Bool
    }

    struct WDAStatus: Decodable {
        let wdaRunning: Bool
        let appiumInstalled: Bool
        let appiumRunning: Bool
        let appiumUrl: String
        let wdaUrl: String

        enum CodingKeys: String, CodingKey {
            case wdaRunning = "wda_running"
            case appiumInstalled = "appium_installed"
            case appiumRunning = "appium_running"
            case appiumUrl = "appium_url"
            case wdaUrl = "wda_url"
        }
    }

    struct WDAStartResult: Decodable {
        let udid: String
        let message: String
        let wdaRunning: Bool

        enum CodingKeys: String, CodingKey {
            case udid, message
            case wdaRunning = "wda_running"
        }
    }

    // MARK: - Diagnostico

    struct EngineInfo: Decodable {
        struct ProxyInfo: Decodable {
            let host: String
            let port: Int
            let running: Bool
        }
        let version: String
        let platform: String
        let deviceId: String?
        let adbPath: String
        let adbAvailable: Bool
        let scrcpyAvailable: Bool
        let wdaUrl: String
        /// Nome que os arquivos gravados vão receber.
        let pageObjectsKey: String
        let proxy: ProxyInfo
        let methods: [String]

        enum CodingKeys: String, CodingKey {
            case version, platform, proxy, methods
            case deviceId = "device_id"
            case adbPath = "adb_path"
            case adbAvailable = "adb_available"
            case scrcpyAvailable = "scrcpy_available"
            case wdaUrl = "wda_url"
            case pageObjectsKey = "page_objects_key"
        }
    }

    struct StreamStats: Decodable {
        let running: Bool
        let framesCaptured: Int?
        let framesEmitted: Int?
        let framesSkipped: Int?
        let skipRatio: Double?
        let effectiveFps: Double?
        let lastCaptureMs: Double?

        enum CodingKeys: String, CodingKey {
            case running
            case framesCaptured = "frames_captured"
            case framesEmitted = "frames_emitted"
            case framesSkipped = "frames_skipped"
            case skipRatio = "skip_ratio"
            case effectiveFps = "effective_fps"
            case lastCaptureMs = "last_capture_ms"
        }
    }

    struct ScrcpyStatus: Decodable, Sendable {
        let running: Bool
        let available: Bool?
        let started: Bool?
        let deviceId: String?

        enum CodingKeys: String, CodingKey {
            case running, available, started
            case deviceId = "device_id"
        }
    }

    struct ProxyState: Decodable {
        let running: Bool
        let started: Bool?
        let deviceConfigured: Bool?

        enum CodingKeys: String, CodingKey {
            case running, started
            case deviceConfigured = "device_configured"
        }
    }

    struct AnalyticsState: Decodable {
        let running: Bool
    }

    struct SessionState: Decodable {
        let platform: String
        let deviceId: String?

        enum CodingKeys: String, CodingKey {
            case platform
            case deviceId = "device_id"
        }
    }
}
