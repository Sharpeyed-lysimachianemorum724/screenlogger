import XCTest

final class SettingsWindowLayoutTests: XCTestCase {
    func testSettingsContentSizeClampsWideAndUndersizedRestoredFrames() {
        XCTAssertEqual(
            SettingsWindowLayout.constrainedContentSize(
                CGSize(width: 1_920, height: 900)
            ),
            CGSize(width: 980, height: 900)
        )
        XCTAssertEqual(
            SettingsWindowLayout.constrainedContentSize(
                CGSize(width: 620, height: 420)
            ),
            CGSize(width: 820, height: 540)
        )
    }

    func testSettingsContentSizePreservesSupportedUserSize() {
        let proposed = CGSize(width: 900, height: 680)

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
                constrainedFrameWidth: 980
            ),
            570
        )
    }
}
