import XCTest

@testable import ScreenlogCore

final class CaptureOnceFailureTests: XCTestCase {
    func testOperationalFailuresCarryOnlyStablePrivacySafeCopy() {
        let rawDetail = "/Users/person/Secret Project/private-frame.heic: encoding failed"
        let error = NSError(
            domain: rawDetail,
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: rawDetail]
        )
        let failure = CaptureOnceFailure.classify(error, pauseReason: nil)

        XCTAssertEqual(failure, .captureFailed)
        XCTAssertFalse(failure.userTitle.contains(rawDetail))
        XCTAssertFalse(failure.userMessage.contains(rawDetail))
        XCTAssertFalse(String(describing: failure).contains(rawDetail))
    }

    func testCaptureErrorsMapToTypedRecoveryStates() {
        XCTAssertEqual(CaptureOnceFailure.classify(CaptureError.noDisplay, pauseReason: nil), .displayUnavailable)
        XCTAssertEqual(CaptureOnceFailure.classify(CaptureError.encodeFailed, pauseReason: nil), .encodingFailed)
        XCTAssertEqual(CaptureOnceFailure.classify(CaptureError.notAuthorized, pauseReason: nil), .permissionRequired)
        XCTAssertEqual(CaptureOnceFailure.classify(CaptureError.diskFull, pauseReason: nil), .lowDiskSpace)
        XCTAssertEqual(
            CaptureOnceFailure.classify(CaptureError.excluded, pauseReason: .privateBrowsing),
            .privateBrowsing
        )
        XCTAssertEqual(
            CaptureOnceFailure.classify(CaptureError.excluded, pauseReason: .browserAddressUnavailable),
            .browserAddressUnavailable
        )
        XCTAssertEqual(CaptureOnceFailure.classify(CaptureError.excluded, pauseReason: nil), .excludedContent)
    }

    func testExpectedRecoveryMessagesRemainSpecific() {
        XCTAssertEqual(
            CaptureOnceFailure.permissionRequired.userMessage,
            "Allow Screen Recording and Accessibility in Permissions & Privacy, then try again."
        )
        XCTAssertEqual(
            CaptureOnceFailure.lowDiskSpace.userMessage,
            "Free up storage on this Mac, then retry the capture."
        )
        XCTAssertEqual(
            CaptureOnceFailure.privateBrowsing.userMessage,
            "Leave the private window or tab, then try again."
        )
        XCTAssertTrue(
            CaptureOnceFailure.browserAddressUnavailable.userMessage.contains(
                "Accessibility"
            )
        )
    }

    func testUnexpectedFailureUsesTruthfulGenericCopy() {
        XCTAssertEqual(CaptureOnceFailure.captureFailed.userTitle, "Capture couldn't be saved")
        XCTAssertEqual(
            CaptureOnceFailure.captureFailed.userMessage,
            "Screenlogger couldn't save this capture. Your existing Library remains available. Try again."
        )
    }
}
