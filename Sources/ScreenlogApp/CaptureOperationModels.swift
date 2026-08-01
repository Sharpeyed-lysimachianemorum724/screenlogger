import ScreenlogCore

/// Failures owned by automatic capture controls. Expected pauses such as low
/// disk space, permissions, exclusions, and inactivity remain `CapturePauseReason`.
enum CaptureIssue: Equatable, Sendable {
    case startFailed
    case stopFailed
    case pauseFailed
    case resumeFailed
    case automaticCaptureFailed

    var title: String {
        switch self {
        case .startFailed: return "Capture Couldn't Start"
        case .stopFailed: return "Capture Couldn't Stop"
        case .pauseFailed: return "Capture Couldn't Pause"
        case .resumeFailed: return "Capture Couldn't Resume"
        case .automaticCaptureFailed: return "A Moment Couldn't Be Saved"
        }
    }

    var message: String {
        switch self {
        case .startFailed:
            return "Screenlogger couldn't start automatic capture. Your existing Library is unchanged."
        case .stopFailed:
            return "Screenlogger couldn't confirm that automatic capture stopped. Try again before working with private content."
        case .pauseFailed:
            return "Screenlogger couldn't pause automatic capture. No timed pause was scheduled."
        case .resumeFailed:
            return "The pause ended, but Screenlogger couldn't resume automatic capture."
        case .automaticCaptureFailed:
            return "Screenlogger skipped the latest moment and will retry automatically. Your existing Library remains available."
        }
    }

    var canRetry: Bool { self != .automaticCaptureFailed }
}

enum CaptureOnceState: Equatable, Sendable {
    case idle
    case inProgress
    case success(frameID: Int64)
    case failure(CaptureOnceFailure)
}
