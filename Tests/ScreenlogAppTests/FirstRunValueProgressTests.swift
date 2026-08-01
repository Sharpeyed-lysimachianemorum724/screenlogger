import XCTest

final class FirstRunValueProgressTests: XCTestCase {
    func testExistingFrameCannotCompleteJourney() {
        var progress = FirstRunValueProgress()
        progress.begin(after: 42)

        XCTAssertFalse(progress.observeDurableFrame(42))
        XCTAssertFalse(progress.observeDurableFrame(41))
        XCTAssertEqual(progress.phase, .waiting)
    }

    func testNewDurableFrameCompletesJourneyOnlyOnce() {
        var progress = FirstRunValueProgress()
        progress.begin(after: 42)

        XCTAssertTrue(progress.observeDurableFrame(43))
        XCTAssertEqual(progress.phase, .ready(frameID: 43))
        XCTAssertFalse(progress.observeDurableFrame(44))
        XCTAssertEqual(progress.phase, .ready(frameID: 43))
    }

    func testFirstFrameCompletesJourneyWithoutBaseline() {
        var progress = FirstRunValueProgress()
        progress.begin(after: nil)

        XCTAssertTrue(progress.observeDurableFrame(1))
        XCTAssertTrue(progress.isReady)
    }

    func testResetReturnsToIdle() {
        var progress = FirstRunValueProgress()
        progress.begin(after: 8)
        progress.reset()

        XCTAssertEqual(progress.phase, .idle)
        XCTAssertFalse(progress.isWaiting)
        XCTAssertFalse(progress.observeDurableFrame(9))
    }
}
