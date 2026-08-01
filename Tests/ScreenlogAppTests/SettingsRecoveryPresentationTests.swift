import XCTest

final class SettingsRecoveryPresentationTests: XCTestCase {
    func testCaptureOnceRoutesMissingScreenRecordingPermissionToSetup() {
        XCTAssertEqual(
            CaptureOnceSettingsControl.resolve(
                state: .idle,
                captureReady: false
            ),
            .reviewSetup
        )
        XCTAssertEqual(
            CaptureOnceSettingsControl.resolve(
                state: .success(frameID: 42),
                captureReady: false
            ),
            .reviewSetup
        )
    }

    func testCaptureOnceOnlyOffersCaptureWhenPermissionIsAvailable() {
        XCTAssertEqual(
            CaptureOnceSettingsControl.resolve(
                state: .idle,
                captureReady: true
            ),
            .capture(title: "Capture Now")
        )
        XCTAssertEqual(
            CaptureOnceSettingsControl.resolve(
                state: .success(frameID: 42),
                captureReady: true
            ),
            .capture(title: "Capture Again")
        )
        XCTAssertEqual(
            CaptureOnceSettingsControl.resolve(
                state: .inProgress,
                captureReady: false
            ),
            .progress
        )
    }

    func testLoginItemApprovalLeadsWithRequiredSystemSettingsAction() {
        XCTAssertEqual(
            LaunchAtLoginRecoveryLayout.approvalRequired.actions,
            [
                .openLoginItems,
                .retry(title: "Check Again"),
                .keepOff,
            ]
        )
    }

    func testLoginItemOperationFailureStillLeadsWithRetry() {
        XCTAssertEqual(
            LaunchAtLoginRecoveryLayout.operationFailed(retryTitle: "Try Again").actions,
            [
                .retry(title: "Try Again"),
                .openLoginItems,
            ]
        )
    }
}
