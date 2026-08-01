import XCTest

final class SettingsWindowLayoutTests: XCTestCase {
    func testSettingsContentSizeClampsWideAndUndersizedRestoredFrames() {
        XCTAssertEqual(
            SettingsWindowLayout.constrainedContentSize(
                CGSize(width: 1_920, height: 900)
            ),
            CGSize(width: 1_240, height: 900)
        )
        XCTAssertEqual(
            SettingsWindowLayout.constrainedContentSize(
                CGSize(width: 620, height: 420)
            ),
            CGSize(width: 760, height: 500)
        )
    }

    func testSettingsContentSizePreservesSupportedUserSize() {
        let proposed = CGSize(width: 1_000, height: 680)

        XCTAssertEqual(
            SettingsWindowLayout.constrainedContentSize(proposed),
            proposed
        )
    }

    func testWidthConstraintKeepsTheWindowCentered() {
        let original = CGRect(x: 100, y: 80, width: 1_920, height: 900)

        XCTAssertEqual(
            SettingsWindowLayout.centeredOriginX(
                originalFrame: original,
                constrainedFrameWidth: 1_240
            ),
            440
        )
    }
}
