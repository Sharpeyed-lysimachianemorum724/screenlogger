import XCTest

@testable import ScreenlogCore

final class RecordedDomainLoadStateTests: XCTestCase {
    func testIssuesExposeStablePrivacySafeCopyAndRetryRecovery() {
        XCTAssertEqual(RecordedDomainLoadIssue.libraryUnavailable.title, "Library unavailable")
        XCTAssertEqual(
            RecordedDomainLoadIssue.libraryUnavailable.message,
            "The Library isn't available right now. Try loading the list again."
        )
        XCTAssertEqual(
            RecordedDomainLoadIssue.queryFailed.title,
            "Recently recorded websites unavailable"
        )
        XCTAssertEqual(
            RecordedDomainLoadIssue.queryFailed.message,
            "Screenlogger couldn't load recently recorded websites. Try again."
        )

        for issue in RecordedDomainLoadIssue.allCases {
            XCTAssertEqual(issue.recoveryAction, .retry)
            XCTAssertFalse(issue.message.contains("/Users/"))
            XCTAssertFalse(issue.message.contains("SQLite"))
        }
    }

    func testRetryRecoveryUsesStableAccessibleCopy() {
        let recovery = RecordedDomainLoadRecoveryAction.retry

        XCTAssertEqual(recovery.title, "Retry")
        XCTAssertEqual(
            recovery.accessibilityHint,
            "Try loading the recently recorded website list again"
        )
    }

    func testLoadStateExposesOnlyTypedFailureIssues() {
        XCTAssertTrue(RecordedDomainLoadState.loading.isLoading)
        XCTAssertNil(RecordedDomainLoadState.loading.issue)
        XCTAssertFalse(RecordedDomainLoadState.loaded.isLoading)
        XCTAssertNil(RecordedDomainLoadState.loaded.issue)

        let state = RecordedDomainLoadState.failed(.queryFailed)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.issue, .queryFailed)
    }
}
