/// Semantic presentation for the result of an assistant-integration action.
/// This is intentionally separate from readiness and filesystem inspection:
/// those remain authoritative, while a notice is transient user feedback.
public enum AssistantIntegrationActionNotice: Equatable, Sendable {
    case installed(AssistantIntegrationTarget)
    case verified(AssistantIntegrationTarget)
    case removed(AssistantIntegrationTarget)
    case alreadyRemoved(AssistantIntegrationTarget)
    case inspectionUnavailable(AssistantIntegrationTarget)
    case inspectionAvailableAgain(AssistantIntegrationTarget)
    case inspectionCurrent(AssistantIntegrationTarget)
    case inspectionUnchanged(AssistantIntegrationTarget)
    case failed(AssistantIntegrationActionFailure)

    public var severity: AssistantIntegrationActionNoticeSeverity {
        switch self {
        case .installed, .verified, .removed, .inspectionAvailableAgain, .inspectionCurrent:
            return .success
        case .alreadyRemoved, .inspectionUnchanged:
            return .information
        case .inspectionUnavailable, .failed:
            return .failure
        }
    }

    public var message: String {
        switch self {
        case .installed(let target):
            return "Installed the \(target.label) integration files. Restart \(target.label) if it was already open."
        case .verified(let target):
            return "The \(target.label) integration files are current."
        case .removed(let target):
            return "Removed the \(target.label) integration."
        case .alreadyRemoved(let target):
            return "The \(target.label) integration was already removed."
        case .inspectionUnavailable(let target):
            return
                "The \(target.label) integration is still unavailable. Reinstall Screenlogger if this persists."
        case .inspectionAvailableAgain(let target):
            return "The \(target.label) integration is available again."
        case .inspectionCurrent(let target):
            return "The \(target.label) integration files are current."
        case .inspectionUnchanged:
            return "Checked the integration again. No files were changed."
        case .failed(let failure):
            return failure.message
        }
    }
}

public enum AssistantIntegrationActionNoticeSeverity: Equatable, Sendable {
    case success
    case information
    case failure

    public var accessibilityLabel: String {
        switch self {
        case .success:
            return "Assistant integration updated"
        case .information:
            return "Assistant integration information"
        case .failure:
            return "Assistant integration action failed"
        }
    }
}

public enum AssistantIntegrationActionFailure: Equatable, Sendable {
    case resourcesUnavailable
    case configurationUnavailable
    case malformedConfiguration
    case updateRequired
    case destinationConflict
    case unsafeDestination
    case replacementFailed
    case unknown

    public init(_ issue: AssistantIntegrationError) {
        switch issue {
        case .sourceMissing:
            self = .resourcesUnavailable
        case .configMissing:
            self = .configurationUnavailable
        case .malformedConfiguration:
            self = .malformedConfiguration
        case .destinationNeedsUpgrade:
            self = .updateRequired
        case .destinationNotOwned:
            self = .destinationConflict
        case .unsafeDestination:
            self = .unsafeDestination
        case .replacementFailed:
            self = .replacementFailed
        }
    }

    public var message: String {
        switch self {
        case .resourcesUnavailable:
            return "Screenlogger's integration resources are unavailable. Reinstall the app and try again."
        case .configurationUnavailable:
            return "OpenClaw's configuration isn't available. Install or open OpenClaw, then try again."
        case .malformedConfiguration:
            return "OpenClaw's integration settings couldn't be read. Screenlogger left the file unchanged."
        case .updateRequired:
            return "This Screenlogger integration needs an update. Choose Resolve to review and update it."
        case .destinationConflict:
            return "Another item is using the integration location. Screenlogger left it unchanged."
        case .unsafeDestination:
            return "Screenlogger refused an unsafe integration location. No files were changed."
        case .replacementFailed:
            return "The integration couldn't be replaced. The previous installation was preserved."
        case .unknown:
            return "The integration couldn't be changed. No unrelated files were replaced."
        }
    }
}
