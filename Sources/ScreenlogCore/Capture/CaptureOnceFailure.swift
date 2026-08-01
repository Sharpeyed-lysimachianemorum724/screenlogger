public enum CaptureOnceFailure: Equatable, Sendable {
    case permissionRequired
    case lowDiskSpace
    case excludedContent
    case privateBrowsing
    case browserAddressUnavailable
    case displayUnavailable
    case encodingFailed
    case captureFailed

    /// Reduces operational errors to a payload-free state before they can be
    /// published to the UI. The underlying error remains available to the
    /// caller for local diagnostics.
    public static func classify(
        _ error: Error,
        pauseReason: CapturePauseReason?
    ) -> CaptureOnceFailure {
        guard let captureError = error as? CaptureError else {
            return .captureFailed
        }

        switch captureError {
        case .notAuthorized:
            return .permissionRequired
        case .diskFull:
            return .lowDiskSpace
        case .excluded:
            switch pauseReason {
            case .privateBrowsing:
                return .privateBrowsing
            case .browserAddressUnavailable:
                return .browserAddressUnavailable
            default:
                return .excludedContent
            }
        case .noDisplay:
            return .displayUnavailable
        case .encodeFailed:
            return .encodingFailed
        }
    }

    public var userTitle: String {
        switch self {
        case .permissionRequired: return "Permissions setup required"
        case .lowDiskSpace: return "Not enough free storage"
        case .excludedContent: return "This activity is excluded"
        case .privateBrowsing: return "Private Browsing is excluded"
        case .browserAddressUnavailable: return "The active website couldn't be identified"
        case .displayUnavailable: return "No display is available"
        case .encodingFailed: return "Capture couldn't be processed"
        case .captureFailed: return "Capture couldn't be saved"
        }
    }

    public var userMessage: String {
        switch self {
        case .permissionRequired:
            return "Allow Screen Recording and Accessibility in Permissions & Privacy, then try again."
        case .lowDiskSpace:
            return "Free up storage on this Mac, then retry the capture."
        case .excludedContent:
            return "Switch to an app or website that is not excluded, then try again."
        case .privateBrowsing:
            return "Leave the private window or tab, then try again."
        case .browserAddressUnavailable:
            return "Allow Accessibility access, switch away from the browser, or review strict website protection."
        case .displayUnavailable:
            return "Screenlogger couldn't find a display to capture. Reconnect or wake the display, then try again."
        case .encodingFailed:
            return "Screenlogger couldn't process this image. Your existing Library remains available. Try again."
        case .captureFailed:
            return "Screenlogger couldn't save this capture. Your existing Library remains available. Try again."
        }
    }
}
