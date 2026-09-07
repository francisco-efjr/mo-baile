import XCTest
import SwiftUI
@testable import MoBaile

final class ThemeTests: XCTestCase {
    
    func testPraiaDarkThemeTokens() {
        let theme = PraiaDarkTheme()
        XCTAssertEqual(theme.name, "dark")
        XCTAssertEqual(theme.id, "praia_dark")
        
        // bgWindow #1E1E2E
        let expectedBg = Color(hex: "#1E1E2E")
        XCTAssertEqual(theme.bgWindow, expectedBg)
    }
    
    func testPraiaLightThemeTokens() {
        let dark = PraiaDarkTheme()
        let light = PraiaLightTheme()
        
        XCTAssertNotEqual(dark.bgWindow, light.bgWindow)
        XCTAssertEqual(light.id, "praia_light")
    }
    
    func testPlatformIdentity() {
        // iOS #0A84FF
        XCTAssertEqual(PlatformIdentity.ios, Color(hex: "#0A84FF"))
        XCTAssertEqual(PlatformIdentity.android, Color(hex: "#34C759"))
    }
    
    @MainActor
    func testThemeManagerDefaults() {
        let manager = ThemeManager()
        XCTAssertEqual(manager.mode, .system)
    }
}
