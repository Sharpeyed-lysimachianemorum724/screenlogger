import Foundation
import ScreenlogCore
import XCTest

final class TimelineNoticeTests: XCTestCase {
    func testSubstitutedNavigationNeverClaimsRequestedMomentOpened() {
        let nearest = TimelineMomentNavigationResolution.nearestAvailableMoment.noticeEvent
        let recent = TimelineMomentNavigationResolution.recentActivity.noticeEvent
        let unavailable = TimelineMomentNavigationResolution.unavailable.noticeEvent

        XCTAssertEqual(nearest, .nearestMomentShown)
        XCTAssertEqual(recent, .recentActivityShownInstead)
        XCTAssertEqual(unavailable, .momentUnavailable)

        XCTAssertTrue(TimelineNotice(nearest).message.contains("nearest saved moment"))
        XCTAssertTrue(TimelineNotice(recent).message.contains("recent activity"))
        XCTAssertFalse(TimelineNotice(nearest).message.contains("Moment opened"))
        XCTAssertFalse(TimelineNotice(recent).message.contains("Moment opened"))
    }

    func testMomentActionOutcomesPreserveSuccessAndFailure() {
        let cases: [(TimelineMomentActionOutcome, TimelineNotice.Event, TimelineNoticeSeverity)] = [
            (.imageCopied, .imageCopied, .success),
            (.imageUnavailable, .imageUnavailable, .information),
            (.imageCopyFailed, .imageCopyFailed, .warning),
            (.textCopied, .textCopied, .success),
            (.textUnavailable, .textUnavailable, .information),
            (.textCopyFailed, .textCopyFailed, .warning),
            (.sourceOpened(label: "Safari"), .sourceOpened(label: "Safari"), .success),
            (.sourceOpenFailed(label: "Safari"), .sourceOpenFailed(label: "Safari"), .warning),
            (.sourceUnavailable, .sourceUnavailable, .information),
            (.noMomentSelected, .noMomentSelected, .information),
        ]

        for (outcome, expectedEvent, expectedSeverity) in cases {
            let event = outcome.noticeEvent
            XCTAssertEqual(event, expectedEvent)
            XCTAssertEqual(TimelineNotice(event).severity, expectedSeverity)
        }
    }

    func testSemanticSeverityControlsBoundedLifetimeAndAnnouncementPriority() {
        let success = TimelineNotice(.textCopied)
        let information = TimelineNotice(.textUnavailable)
        let warning = TimelineNotice(.textCopyFailed)

        XCTAssertEqual(success.dismissalDelay, 3)
        XCTAssertEqual(information.dismissalDelay, 5)
        XCTAssertEqual(warning.dismissalDelay, 7)
        XCTAssertGreaterThanOrEqual(success.dismissalDelay, 3)
        XCTAssertLessThanOrEqual(warning.dismissalDelay, 7)

        XCTAssertEqual(success.accessibilityAnnouncement.priority, .low)
        XCTAssertEqual(information.accessibilityAnnouncement.priority, .medium)
        XCTAssertEqual(warning.accessibilityAnnouncement.priority, .high)
        XCTAssertEqual(warning.accessibilityAnnouncement.message, warning.message)
    }

    func testTimelineCountMessagesUseCorrectNouns() {
        XCTAssertEqual(
            TimelineNotice(.timelineLoaded(scope: .recent, momentCount: 0)).message,
            "No captured moments yet"
        )
        XCTAssertEqual(
            TimelineNotice(.timelineLoaded(scope: .recent, momentCount: 1)).message,
            "Showing 1 recent moment"
        )
        XCTAssertEqual(
            TimelineNotice(.timelineLoaded(scope: .session, momentCount: 2)).message,
            "Showing 2 moments in this session"
        )
        XCTAssertEqual(
            TimelineNotice(.momentsDeleted(count: 1, cleanupPending: false)).message,
            "Deleted 1 moment"
        )
        XCTAssertEqual(
            TimelineNotice(.momentsDeleted(count: 3, cleanupPending: true)).message,
            "Deleted 3 moments - finishing file cleanup"
        )
    }

    func testTimelineDisplayLabelsStayDistinctForMainAndMirroredGeometry() {
        let main = TimelineFrame(
            id: 1,
            timestampMs: 1,
            captureDisplay: CaptureDisplayRect(x: 0, y: 0, width: 1_728, height: 1_117)
        )
        let external = TimelineFrame(
            id: 2,
            timestampMs: 1,
            captureDisplay: CaptureDisplayRect(x: 1_728, y: 0, width: 1_920, height: 1_080)
        )

        XCTAssertEqual(TimelineDisplayPresentation.label(for: 0, in: [main, external]), "Main Display")
        XCTAssertEqual(TimelineDisplayPresentation.label(for: 1, in: [main, external]), "Display 2")

        let mirrored = [main, TimelineFrame(id: 3, timestampMs: 1, captureDisplay: main.captureDisplay)]
        XCTAssertEqual(TimelineDisplayPresentation.label(for: 0, in: mirrored), "Display 1")
        XCTAssertEqual(TimelineDisplayPresentation.label(for: 1, in: mirrored), "Display 2")
    }

    func testTimelineDeletionCopyExplainsMultiDisplayScope() {
        let frame = TimelineFrame(id: 1, timestampMs: 1)
        XCTAssertTrue(
            TimelineDisplayPresentation.deletionDetail(frame: frame, displayCount: 2)
                .contains("removes all 2 display captures")
        )
    }
}
