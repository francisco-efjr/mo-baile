import Foundation

struct DaemonStatusMap: Sendable {
    var wda: DaemonState = .off
    var adb: DaemonState = .off
    var proxy: DaemonState = .off
    var fa: DaemonState = .off
}

struct LogLine: Identifiable, Sendable {
    let id: UUID = UUID()
    let timestamp: Date
    let prefix: String   // "INFO", "RUN", "PASS", "FAIL", "HTTP", "FA"
    let message: String
}
