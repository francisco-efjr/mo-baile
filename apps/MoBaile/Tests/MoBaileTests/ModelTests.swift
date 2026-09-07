import XCTest
@testable import MoBaile

final class ModelTests: XCTestCase {
    
    // UIElement Tests
    func testUIElementChipType() {
        let btn = UIElement(tag: "", className: "XCUIElementTypeButton", resourceId: "", text: "", contentDesc: "", clickable: true, bounds: .zero, area: 0, package: "", platform: .ios, depth: 0, parentIndex: nil)
        XCTAssertEqual(btn.chipType, .button)
        
        let input = UIElement(tag: "", className: "XCUIElementTypeSecureTextField", resourceId: "", text: "", contentDesc: "", clickable: true, bounds: .zero, area: 0, package: "", platform: .ios, depth: 0, parentIndex: nil)
        XCTAssertEqual(input.chipType, .input)
        
        let text = UIElement(tag: "", className: "XCUIElementTypeStaticText", resourceId: "", text: "", contentDesc: "", clickable: false, bounds: .zero, area: 0, package: "", platform: .ios, depth: 0, parentIndex: nil)
        XCTAssertEqual(text.chipType, .text)
        
        let window = UIElement(tag: "", className: "XCUIElementTypeWindow", resourceId: "", text: "", contentDesc: "", clickable: false, bounds: .zero, area: 0, package: "", platform: .ios, depth: 0, parentIndex: nil)
        XCTAssertEqual(window.chipType, .window)
    }
    
    func testUIElementDisplayName() {
        // Priority: text > contentDesc > resourceId > className
        var element = UIElement(tag: "", className: "android.widget.Button", resourceId: "com.app:id/submit", text: "Submit", contentDesc: "Submit Button", clickable: true, bounds: .zero, area: 0, package: "", platform: .android, depth: 0, parentIndex: nil)
        XCTAssertEqual(element.displayName, "Submit")
        
        element = UIElement(tag: "", className: "android.widget.Button", resourceId: "com.app:id/submit", text: "", contentDesc: "Submit Button", clickable: true, bounds: .zero, area: 0, package: "", platform: .android, depth: 0, parentIndex: nil)
        XCTAssertEqual(element.displayName, "Submit Button")
        
        element = UIElement(tag: "", className: "android.widget.Button", resourceId: "com.app:id/submit", text: "", contentDesc: "", clickable: true, bounds: .zero, area: 0, package: "", platform: .android, depth: 0, parentIndex: nil)
        // Extract short ID
        XCTAssertEqual(element.displayName, "submit")
        
        element = UIElement(tag: "", className: "android.widget.Button", resourceId: "", text: "", contentDesc: "", clickable: true, bounds: .zero, area: 0, package: "", platform: .android, depth: 0, parentIndex: nil)
        XCTAssertEqual(element.displayName, "android.widget.Button")
    }
    
    func testUIElementCenter() {
        let element = UIElement(tag: "", className: "View", resourceId: "", text: "", contentDesc: "", clickable: true, bounds: CGRect(x: 10, y: 20, width: 40, height: 60), area: 2400, package: "", platform: .android, depth: 0, parentIndex: nil)
        XCTAssertEqual(element.center, CGPoint(x: 30, y: 50)) // midX, midY
    }
    
    // NetworkEvent Tests
    func testNetworkEventFormattedDuration() {
        var event = NetworkEvent(id: 1, timestamp: Date(), timeStr: "", method: "GET", url: "", host: "", path: "", statusText: "", requestHeaders: [:], requestBody: "", responseHeaders: [:], responseBody: "", protocol: "HTTP/1.1", isTunnel: false)
        
        event.durationMs = nil
        XCTAssertEqual(event.formattedDuration, "—")
        
        event.durationMs = 500
        XCTAssertEqual(event.formattedDuration, "500 ms")
        
        event.durationMs = 1500
        XCTAssertEqual(event.formattedDuration, "1.5 s")
    }
    
    func testNetworkEventFormattedSize() {
        var event = NetworkEvent(id: 1, timestamp: Date(), timeStr: "", method: "GET", url: "", host: "", path: "", statusText: "", requestHeaders: [:], requestBody: "", responseHeaders: [:], responseBody: "", protocol: "HTTP/1.1", isTunnel: false)
        
        // Size is computed from responseBody string length in utf8
        event.responseBody = String(repeating: "A", count: 500)
        XCTAssertEqual(event.formattedSize, "500 B")
        
        event.responseBody = String(repeating: "A", count: 1536) // 1.5 KB
        XCTAssertEqual(event.formattedSize, "1.5 KB")
        
        event.responseBody = String(repeating: "A", count: 1024 * 1024 + 512 * 1024) // 1.5 MB
        XCTAssertEqual(event.formattedSize, "1.5 MB")
    }
    
    // AppState Tests
    @MainActor
    func testAppStateFilteredHTTPRequests() {
        let state = AppState()
        
        let req1 = NetworkEvent(id: 1, timestamp: Date(), timeStr: "", method: "GET", url: "", host: "api.example.com", path: "/users", statusText: "", requestHeaders: [:], requestBody: "", responseHeaders: [:], responseBody: "", protocol: "", isTunnel: false)
        let req2 = NetworkEvent(id: 2, timestamp: Date(), timeStr: "", method: "POST", url: "", host: "auth.example.com", path: "/login", statusCode: 401, statusText: "", requestHeaders: [:], requestBody: "", responseHeaders: [:], responseBody: "", protocol: "", isTunnel: false)
        
        state.httpRequests = [req1, req2]
        
        state.httpFilterText = "auth"
        XCTAssertEqual(state.filteredHTTPRequests.count, 1)
        XCTAssertEqual(state.filteredHTTPRequests.first?.id, 2)
        
        state.httpFilterText = "401"
        XCTAssertEqual(state.filteredHTTPRequests.count, 1)
        XCTAssertEqual(state.filteredHTTPRequests.first?.id, 2)
        
        state.httpFilterText = "GET"
        XCTAssertEqual(state.filteredHTTPRequests.count, 1)
        XCTAssertEqual(state.filteredHTTPRequests.first?.id, 1)
    }
    
    @MainActor
    func testAppStateToggleZenMode() {
        let state = AppState()
        
        state.mirrorVisible = true
        state.hierarchyVisible = true
        state.zenMode = false
        
        state.toggleZenMode()
        
        XCTAssertTrue(state.zenMode)
        XCTAssertFalse(state.mirrorVisible)
        XCTAssertFalse(state.hierarchyVisible)
        
        state.toggleZenMode()
        
        XCTAssertFalse(state.zenMode)
        XCTAssertTrue(state.mirrorVisible)
        XCTAssertTrue(state.hierarchyVisible)
    }
}
