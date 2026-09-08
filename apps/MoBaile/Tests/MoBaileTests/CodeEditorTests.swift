import XCTest
import AppKit
@testable import MoBaile

final class CodeEditorTests: XCTestCase {

    @MainActor
    func testContainerInitializationAndLayout() {
        let container = IDEEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.layoutSubtreeIfNeeded()

        XCTAssertNotNil(container.gutterView)
        XCTAssertNotNil(container.scrollView)
        XCTAssertNotNil(container.textView)
        XCTAssertEqual(container.gutterView.superview, container)
        XCTAssertEqual(container.scrollView.superview, container)
        XCTAssertGreaterThan(container.gutterView.frame.width, 30)
    }

    @MainActor
    func testGutterDynamicWidthScaling() {
        let container = IDEEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.layoutSubtreeIfNeeded()

        let initialWidth = container.gutterView.frame.width

        // Test with 4 digits line count (e.g. 1500 lines)
        container.updateGutterWidth(forLineCount: 1500)
        container.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(container.gutterView.frame.width, initialWidth)
    }

    @MainActor
    func testGutterDrawingWithContent() {
        let container = IDEEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.textView.string = "def test_example():\n    x = 10\n    assert x == 10\n"
        container.layoutSubtreeIfNeeded()

        let img = NSImage(size: NSSize(width: 400, height: 300))
        img.lockFocus()
        container.gutterView.draw(container.gutterView.bounds)
        img.unlockFocus()

        // Gutter should draw without throwing or crashing
        XCTAssertTrue(true)
    }

    @MainActor
    func testGutterDrawingWithEmptyContent() {
        let container = IDEEditorContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.textView.string = ""
        container.layoutSubtreeIfNeeded()

        let img = NSImage(size: NSSize(width: 400, height: 300))
        img.lockFocus()
        container.gutterView.draw(container.gutterView.bounds)
        img.unlockFocus()

        XCTAssertTrue(true)
    }
}
