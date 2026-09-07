import Foundation

struct AutomationStep: Identifiable, Equatable, Sendable {
    let id: UUID = UUID()
    let stepNum: Int
    let actionType: String   // "click", "send_keys"
    let varName: String      // e.g. "BOTAO_CONTINUAR"
    let elementName: String
    let className: String
    let strategy: LocatorStrategy
    let locatorValue: String
    let coords: CGPoint?
    let inputText: String?
    let package: String
    let platform: Platform
    
    static func == (lhs: AutomationStep, rhs: AutomationStep) -> Bool {
        lhs.id == rhs.id
    }
}
