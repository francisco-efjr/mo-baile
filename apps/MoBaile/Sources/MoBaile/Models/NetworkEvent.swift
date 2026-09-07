import Foundation

public struct NetworkEvent: Identifiable, Equatable, Sendable {
    public let id: Int
    public let timestamp: Date
    public let timeStr: String
    public let method: String
    public let url: String
    public let host: String
    public let path: String
    public var statusCode: Int?
    public var statusText: String
    public var requestHeaders: [String: String]
    public var requestBody: String
    public var responseHeaders: [String: String]
    public var responseBody: String
    public var durationMs: Int?
    public let `protocol`: String
    public let isTunnel: Bool
    public var error: String?
    
    public var formattedDuration: String {
        guard let ms = durationMs else { return "—" }
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.1f s", Double(ms) / 1000.0)
    }
    
    public var formattedSize: String {
        let bytes = responseBody.utf8.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }
    
    public static func == (lhs: NetworkEvent, rhs: NetworkEvent) -> Bool {
        lhs.id == rhs.id
    }
}
