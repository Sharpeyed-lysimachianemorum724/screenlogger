import Foundation
import ScreenlogCore

/// Why Timeline is currently being presented. Only a result handoff owns a
/// one-shot return path to the preserved Library query.
enum TimelineNavigationOrigin: Sendable, Equatable {
    case direct
    case libraryResult
}

/// A recoverable failure owned by the Timeline experience.
///
/// Keeping recovery as data (rather than retaining a UI closure) makes retries
/// predictable even if the selected session or moment changes before the user
/// acts on the banner.
enum TimelineIssue: Equatable, Sendable {
    case refreshSessions
    case refreshTimeline
    case showRecentActivity
    case reloadSession(startMs: Int64)
    case reopenMoment(frameID: Int64, timestampMs: Int64?)

    var title: String {
        switch self {
        case .refreshSessions:
            return "Recorded days couldn't refresh"
        case .refreshTimeline:
            return "Timeline couldn't refresh"
        case .showRecentActivity:
            return "Recent activity couldn't open"
        case .reloadSession:
            return "Session couldn't open"
        case .reopenMoment:
            return "Moment couldn't open"
        }
    }

    var message: String {
        switch self {
        case .refreshSessions:
            return "Screenlogger couldn't load your recorded days. Try again."
        case .refreshTimeline:
            return "Screenlogger couldn't load your recent moments. Try again."
        case .showRecentActivity:
            return "Your current session is still open. Try showing recent activity again."
        case .reloadSession:
            return "Screenlogger couldn't load this session. Try opening it again."
        case .reopenMoment:
            return "Screenlogger couldn't open this moment. Try opening it again."
        }
    }
}

/// A failure loading media for the currently selected Timeline moment.
/// This is separate from intentionally unavailable media, which is derived
/// from a frame having neither an image nor a compacted-video reference.
enum TimelinePreviewIssue: Equatable, Sendable {
    case momentMissing
    case mediaUnreadable
}

extension AppModel {
    /// One primary surface at a time: progress, full-page recovery, contextual
    /// empty guidance, or usable Timeline content.
    var timelineContentState: TimelineContentState {
        TimelineContentState.resolve(
            hasFrames: !timeline.isEmpty,
            loadState: timelineLoadState,
            hasTimelineIssue: timelineIssue != nil,
            openedFromLibraryResult: timelineNavigationOrigin == .libraryResult,
            hasSelectedSession: selectedSession != nil
        )
    }
}
