import AppKit
import Foundation

@MainActor
extension AppModel {
    /// Publish feedback on the surface where the action occurred. The injected
    /// announcement closure keeps accessibility delivery observable in focused
    /// tests without making notice presentation depend on a particular view.
    func publishTimelineNotice(
        _ event: TimelineNotice.Event,
        announce: Bool = true
    ) {
        let notice = TimelineNotice(event)
        timelineNoticeDismissTask?.cancel()
        timelineNotice = notice

        if announce {
            timelineNoticeAnnouncementHandler(notice.accessibilityAnnouncement)
        }

        timelineNoticeDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(notice.dismissalDelay * 1_000_000_000)
                )
            } catch {
                return
            }
            guard let self, self.timelineNotice?.id == notice.id else { return }
            self.timelineNotice = nil
            self.timelineNoticeDismissTask = nil
        }
    }

    func publishTimelineMomentAction(_ outcome: TimelineMomentActionOutcome) {
        publishTimelineNotice(outcome.noticeEvent)
    }

    func dismissTimelineNotice() {
        timelineNoticeDismissTask?.cancel()
        timelineNoticeDismissTask = nil
        timelineNotice = nil
    }
}
