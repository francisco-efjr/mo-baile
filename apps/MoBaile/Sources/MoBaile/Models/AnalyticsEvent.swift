import Foundation

/// iPhone conectado por cabo, como origem do tagueamento no iOS.
struct IOSPhysicalDevice: Identifiable, Equatable, Sendable {
    let udid: String
    let name: String
    let iosVersion: String
    let problem: String?

    var id: String { udid }
}

/// De onde a escuta de tagueamento le no iOS.
enum AnalyticsIOSSource: Equatable, Sendable {
    /// Simulador da sessao; sem ele, o primeiro iPhone por cabo.
    case auto
    case simulator
    case device(udid: String)

    var rpcValue: String {
        switch self {
        case .auto: return "auto"
        case .simulator: return "simulator"
        case .device(let udid): return udid
        }
    }
}

struct AnalyticsEvent: Identifiable, Equatable, Sendable {
    let id: Int
    let timestamp: Date
    let timeStr: String
    let tag: String       // "FA", "FA-SVC", "iOS (Firebase)"
    let eventName: String
    let params: [String: String]
    let rawLog: String
    let platform: Platform
    
    var paramCount: Int { params.count }
    
    static func == (lhs: AnalyticsEvent, rhs: AnalyticsEvent) -> Bool {
        lhs.id == rhs.id
    }
}
