import Foundation

/// The user action Screenlogger can safely retry after a login-item failure.
public enum LaunchAtLoginOperation: String, Equatable, Sendable {
    case enable
    case disable
    case refresh
}

/// Stable, privacy-safe categories for ServiceManagement failures.
///
/// The underlying system error belongs in the local bootstrap log, not in UI.
public enum LaunchAtLoginIssue: Equatable, Sendable {
    case registrationFailed
    case removalFailed
    case serviceUnavailable
}

/// Truthful presentation state for the main-app login item.
///
/// `isEnabled` always describes the last status reported by macOS. In
/// particular, approval-required and failed enable operations remain off.
public enum LaunchAtLoginState: Equatable, Sendable {
    case ready(isEnabled: Bool)
    case enabling(previouslyEnabled: Bool)
    case disabling(previouslyEnabled: Bool)
    case approvalRequired
    case failed(
        operation: LaunchAtLoginOperation,
        isEnabled: Bool,
        issue: LaunchAtLoginIssue
    )

    public var isEnabled: Bool {
        switch self {
        case .ready(let isEnabled), .failed(_, let isEnabled, _):
            return isEnabled
        case .enabling(let previouslyEnabled), .disabling(let previouslyEnabled):
            return previouslyEnabled
        case .approvalRequired:
            return false
        }
    }

    public var isBusy: Bool {
        switch self {
        case .enabling, .disabling: return true
        case .ready, .approvalRequired, .failed: return false
        }
    }

    public var retryOperation: LaunchAtLoginOperation? {
        switch self {
        case .approvalRequired:
            return .refresh
        case .failed(let operation, _, _):
            return operation
        case .ready, .enabling, .disabling:
            return nil
        }
    }
}
