import XCTest

@testable import ScreenlogCore

final class AssistantIntegrationActionNoticeTests: XCTestCase {
    func testNoticeSeverityIsExplicitForEveryActionOutcome() {
        XCTAssertEqual(AssistantIntegrationActionNotice.installed(.claude).severity, .success)
        XCTAssertEqual(AssistantIntegrationActionNotice.verified(.cursor).severity, .success)
        XCTAssertEqual(AssistantIntegrationActionNotice.removed(.codex).severity, .success)
        XCTAssertEqual(AssistantIntegrationActionNotice.alreadyRemoved(.claude).severity, .information)
        XCTAssertEqual(AssistantIntegrationActionNotice.inspectionUnchanged(.cursor).severity, .information)
        XCTAssertEqual(AssistantIntegrationActionNotice.inspectionUnavailable(.codex).severity, .failure)
        XCTAssertEqual(
            AssistantIntegrationActionNotice.failed(.replacementFailed).severity,
            .failure
        )
    }

    func testSuccessfulNoticesUseStablePrivacySafeCopy() {
        XCTAssertEqual(
            AssistantIntegrationActionNotice.installed(.claude).message,
            "Installed the Claude Code integration files. Restart Claude Code if it was already open."
        )
        XCTAssertEqual(
            AssistantIntegrationActionNotice.verified(.cursor).message,
            "The Cursor integration files are current."
        )
        XCTAssertEqual(
            AssistantIntegrationActionNotice.removed(.codex).message,
            "Removed the Codex integration."
        )

        let notices: [AssistantIntegrationActionNotice] = [
            .installed(.claude),
            .verified(.cursor),
            .removed(.codex),
            .alreadyRemoved(.claude),
            .inspectionAvailableAgain(.cursor),
            .inspectionCurrent(.codex),
            .inspectionUnchanged(.openclaw),
        ]
        for notice in notices {
            XCTAssertFalse(notice.message.contains("/Users/"))
            XCTAssertFalse(notice.message.contains(" to "))
        }
    }

    func testTypedIntegrationErrorsMapToStableFailureCopy() {
        XCTAssertEqual(
            AssistantIntegrationActionFailure(.sourceMissing("private path")),
            .resourcesUnavailable
        )
        XCTAssertEqual(
            AssistantIntegrationActionFailure(.destinationNotOwned("private path")),
            .destinationConflict
        )
        XCTAssertEqual(
            AssistantIntegrationActionFailure(.replacementFailed(path: "private", reason: "details")),
            .replacementFailed
        )
        XCTAssertEqual(
            AssistantIntegrationActionFailure.destinationConflict.message,
            "Another item is using the integration location. Screenlogger left it unchanged."
        )

        for failure in [
            AssistantIntegrationActionFailure.resourcesUnavailable,
            .configurationUnavailable,
            .malformedConfiguration,
            .updateRequired,
            .destinationConflict,
            .unsafeDestination,
            .replacementFailed,
            .unknown,
        ] {
            XCTAssertFalse(failure.message.contains("private"))
        }
    }

    func testSemanticSeverityHasStableAccessibilityLabels() {
        XCTAssertEqual(
            AssistantIntegrationActionNoticeSeverity.success.accessibilityLabel,
            "Assistant integration updated"
        )
        XCTAssertEqual(
            AssistantIntegrationActionNoticeSeverity.information.accessibilityLabel,
            "Assistant integration information"
        )
        XCTAssertEqual(
            AssistantIntegrationActionNoticeSeverity.failure.accessibilityLabel,
            "Assistant integration action failed"
        )
    }
}
