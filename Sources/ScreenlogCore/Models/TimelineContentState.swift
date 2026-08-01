import Foundation

/// The lifecycle of the Timeline's primary content query.
///
/// This is deliberately independent from capture state: capture can be on while
/// an existing Timeline query is loading or has failed.
public enum TimelineLoadState: Equatable, Sendable {
    case awaitingInitialLoad
    case loading
    case ready
    case failed
}

/// Context for a successful Timeline query which returned no moments.
public enum TimelineEmptyState: Equatable, Sendable {
    case libraryResultUnavailable
    case selectedSessionUnavailable
    case captureState
}

/// Mutually exclusive primary Timeline surfaces.
///
/// Resolving this state outside SwiftUI prevents a transient empty Library from
/// being mistaken for first-run onboarding while its initial query is running.
public enum TimelineContentState: Equatable, Sendable {
    case loading
    case failed
    case empty(TimelineEmptyState)
    case content

    public static func resolve(
        hasFrames: Bool,
        loadState: TimelineLoadState,
        hasTimelineIssue: Bool,
        openedFromLibraryResult: Bool,
        hasSelectedSession: Bool
    ) -> Self {
        // A refresh failure should not replace moments the person can still
        // inspect. The app presents that recoverable error as a compact banner.
        if hasFrames { return .content }

        switch loadState {
        case .awaitingInitialLoad, .loading:
            return .loading
        case .failed:
            return .failed
        case .ready:
            break
        }

        if hasTimelineIssue { return .failed }
        if openedFromLibraryResult { return .empty(.libraryResultUnavailable) }
        if hasSelectedSession { return .empty(.selectedSessionUnavailable) }
        return .empty(.captureState)
    }
}
