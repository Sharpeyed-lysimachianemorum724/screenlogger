import ApplicationServices
import XCTest

@testable import ScreenlogCore

final class AXTreeExtractorTests: XCTestCase {
    func testAccessibilityElementRejectsUnexpectedCoreFoundationType() {
        let value = "not an accessibility element" as CFString
        XCTAssertNil(AXTreeExtractor.accessibilityElement(from: value))
    }

    func testAccessibilityElementAcceptsAXElement() {
        let element = AXUIElementCreateSystemWide()
        XCTAssertNotNil(AXTreeExtractor.accessibilityElement(from: element))
    }

    func testPointAndSizeRequireMatchingAXValueTypes() throws {
        var point = CGPoint(x: -120, y: 48)
        var size = CGSize(width: 1_440, height: 900)
        let pointValue = try XCTUnwrap(AXValueCreate(.cgPoint, &point))
        let sizeValue = try XCTUnwrap(AXValueCreate(.cgSize, &size))

        XCTAssertEqual(AXTreeExtractor.point(from: pointValue), point)
        XCTAssertEqual(AXTreeExtractor.size(from: sizeValue), size)
        XCTAssertNil(AXTreeExtractor.point(from: sizeValue))
        XCTAssertNil(AXTreeExtractor.size(from: pointValue))
        XCTAssertNil(AXTreeExtractor.point(from: "wrong" as CFString))
        XCTAssertNil(AXTreeExtractor.size(from: NSNumber(value: 42)))
    }

    func testBackgroundExtractionRejectsTheCurrentProcess() {
        XCTAssertFalse(
            AXTreeExtractor.shouldInspect(
                focusedPID: 42,
                expectedPID: 42,
                currentProcessID: 42
            )
        )
    }

    func testExtractionRejectsFocusChangesAfterTheScreenshot() {
        XCTAssertFalse(
            AXTreeExtractor.shouldInspect(
                focusedPID: 43,
                expectedPID: 42,
                currentProcessID: 99
            )
        )
        XCTAssertTrue(
            AXTreeExtractor.shouldInspect(
                focusedPID: 42,
                expectedPID: 42,
                currentProcessID: 99
            )
        )
    }
}
