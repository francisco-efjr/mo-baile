import Foundation

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
