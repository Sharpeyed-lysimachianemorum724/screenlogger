import ScreenlogCore

/// The single control shown beside Capture Once. Keeping this decision pure
/// prevents Settings from offering an action that is known to fail while
/// Either required capture permission is missing.
enum CaptureOnceSettingsControl: Equatable, Sendable {
    case capture(title: String)
    case reviewSetup
    case progress
    case none

    static func resolve(
        state: CaptureOnceState,
        captureReady: Bool
    ) -> Self {
        switch state {
        case .inProgress:
            return .progress
        case .failure:
            return .none
        case .idle where !captureReady,
            .success where !captureReady:
            return .reviewSetup
        case .idle:
            return .capture(title: "Capture Now")
        case .success:
            return .capture(title: "Capture Again")
        }
    }
}

/// Stable action hierarchy for Open at Login recovery. The first action is
/// both the visual primary action and the default Return-key action.
enum LaunchAtLoginRecoveryAction: Equatable, Hashable, Sendable {
    case openLoginItems
    case retry(title: String)
    case keepOff
}

enum LaunchAtLoginRecoveryLayout: Equatable, Sendable {
    case approvalRequired
    case operationFailed(retryTitle: String)

    var actions: [LaunchAtLoginRecoveryAction] {
        switch self {
        case .approvalRequired:
            return [
                .openLoginItems,
                .retry(title: "Check Again"),
                .keepOff,
            ]
        case .operationFailed(let retryTitle):
            return [
                .retry(title: retryTitle),
                .openLoginItems,
            ]
        }
    }
}
