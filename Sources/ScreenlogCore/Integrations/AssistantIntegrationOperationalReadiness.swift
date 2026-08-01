import Foundation

/// Whether Screenlogger has found a compatible assistant host for the
/// integration's shell-based skill.
///
/// This is product discovery, not a host-specific search result. A consumer
/// application from the same vendor is not necessarily a usable host.
public enum AssistantIntegrationHostState: Equatable, Sendable {
    case notDetected
    case notUsable
    case usable
}

/// The result of resolving `screenlog` from the user's login shell. Assistant
/// hosts may load a different environment, so this is only a local prerequisite.
public enum AssistantIntegrationShellCommandResolution: Equatable, Sendable {
    /// Resolution has not run yet. This is intentionally different from a
    /// completed lookup that did not find the command.
    case notChecked
    case missing
    case checkFailed
    case resolved(path: String)
}

/// A stable, privacy-safe reason that a live command verification failed.
///
/// Probes should discard command output and implementation-specific errors
/// before constructing this value.
public enum AssistantIntegrationLiveVerificationFailure: Equatable, Sendable {
    case commandFailed
    case appUnavailable
    case invalidResponse
    case versionMismatch
    case protocolMismatch
}

/// Result of invoking the managed command against the running app.
public enum AssistantIntegrationLiveVerificationState: Equatable, Sendable {
    case notRun
    case succeeded
    case failed(AssistantIntegrationLiveVerificationFailure)
}

/// Typed observations consumed by the pure operational-readiness evaluator.
///
/// Collection of these observations deliberately lives outside this model so
/// app and CLI callers can inject deterministic probes rather than reading the
/// current process's home directory, applications, or `PATH` in the evaluator.
public struct AssistantIntegrationOperationalInputs: Equatable, Sendable {
    public let host: AssistantIntegrationHostState
    public let integrationFiles: AssistantIntegrationReadiness
    public let managedCLI: CLIInstallState
    public let shellCommand: AssistantIntegrationShellCommandResolution
    public let bridge: CLIConnectionState
    public let liveVerification: AssistantIntegrationLiveVerificationState

    public init(
        host: AssistantIntegrationHostState,
        integrationFiles: AssistantIntegrationReadiness,
        managedCLI: CLIInstallState,
        shellCommand: AssistantIntegrationShellCommandResolution,
        bridge: CLIConnectionState,
        liveVerification: AssistantIntegrationLiveVerificationState
    ) {
        self.host = host
        self.integrationFiles = integrationFiles
        self.managedCLI = managedCLI
        self.shellCommand = shellCommand
        self.bridge = bridge
        self.liveVerification = liveVerification
    }
}

public enum AssistantIntegrationHostIssue: Equatable, Sendable {
    case notDetected
    case notUsable
}

public enum AssistantIntegrationFilesIssue: Equatable, Sendable {
    case notInstalled
    case updateAvailable
    case setupIncomplete
    case blocked(AssistantIntegrationState)
}

public enum AssistantIntegrationManagedCLIIssue: Equatable, Sendable {
    case notInstalled
    case installing
    case removing
    case updateAvailable
    case verificationUnavailable
    case conflict(CLIArtifactConflict)
    case failed(CLIInstallFailure)
}

public enum AssistantIntegrationShellCommandIssue: Equatable, Sendable {
    case notChecked
    case missing(expectedPath: String)
    case checkFailed(expectedPath: String)
    case shadowed(expectedPath: String, resolvedPath: String)
}

public enum AssistantIntegrationBridgeIssue: Equatable, Sendable {
    case disabled
    case starting
    case unavailable(CLIConnectionFailure)
}

public enum AssistantIntegrationLiveVerificationIssue: Equatable, Sendable {
    case notRun
    case failed(AssistantIntegrationLiveVerificationFailure)
}

/// The first unmet requirement in the supported setup order.
public enum AssistantIntegrationOperationalBlocker: Equatable, Sendable {
    case assistantHost(AssistantIntegrationHostIssue)
    case integrationFiles(AssistantIntegrationFilesIssue)
    case managedCLI(AssistantIntegrationManagedCLIIssue)
    case shellCommand(AssistantIntegrationShellCommandIssue)
    case bridge(AssistantIntegrationBridgeIssue)
    case liveVerification(AssistantIntegrationLiveVerificationIssue)
}

/// Aggregate truth for Screenlogger's side of an assistant connection.
///
/// A verified local connection does not claim that the assistant has loaded
/// the integration files, authenticated with its provider, or completed a
/// host-specific search. Callers may offer a reviewed handoff in this state,
/// but must not present the assistant itself as ready or tested.
public enum AssistantIntegrationOperationalReadiness: Equatable, Sendable {
    case blocked(AssistantIntegrationOperationalBlocker)
    case localConnectionVerified

    public var blocker: AssistantIntegrationOperationalBlocker? {
        guard case .blocked(let blocker) = self else { return nil }
        return blocker
    }

    public var canOfferReviewedHandoff: Bool {
        self == .localConnectionVerified
    }
}

/// Pure policy for turning independently collected setup observations into a
/// single truthful state. The first failing check is the recovery action a UI
/// or CLI should offer.
public struct AssistantIntegrationOperationalReadinessEvaluator: Sendable {
    public init() {}

    public func evaluate(
        _ inputs: AssistantIntegrationOperationalInputs
    ) -> AssistantIntegrationOperationalReadiness {
        if let issue = urgentIntegrationFilesIssue(for: inputs.integrationFiles) {
            return .blocked(.integrationFiles(issue))
        }

        if let issue = hostIssue(for: inputs.host) {
            return .blocked(.assistantHost(issue))
        }

        if let issue = integrationFilesIssue(for: inputs.integrationFiles) {
            return .blocked(.integrationFiles(issue))
        }

        let expectedCommandPath: String
        switch inputs.managedCLI {
        case .ready(let path):
            expectedCommandPath = path
        case .notInstalled:
            return .blocked(.managedCLI(.notInstalled))
        case .installing:
            return .blocked(.managedCLI(.installing))
        case .removing:
            return .blocked(.managedCLI(.removing))
        case .updateAvailable:
            return .blocked(.managedCLI(.updateAvailable))
        case .verificationUnavailable:
            return .blocked(.managedCLI(.verificationUnavailable))
        case .conflict(let conflict):
            return .blocked(.managedCLI(.conflict(conflict)))
        case .failed(let failure):
            return .blocked(.managedCLI(.failed(failure)))
        }

        if let issue = shellCommandIssue(
            for: inputs.shellCommand,
            expectedPath: expectedCommandPath
        ) {
            return .blocked(.shellCommand(issue))
        }

        if let issue = bridgeIssue(for: inputs.bridge) {
            return .blocked(.bridge(issue))
        }

        if let issue = liveVerificationIssue(for: inputs.liveVerification) {
            return .blocked(.liveVerification(issue))
        }

        return .localConnectionVerified
    }

    private func hostIssue(
        for state: AssistantIntegrationHostState
    ) -> AssistantIntegrationHostIssue? {
        switch state {
        case .notDetected: return .notDetected
        case .notUsable: return .notUsable
        case .usable: return nil
        }
    }

    private func integrationFilesIssue(
        for readiness: AssistantIntegrationReadiness
    ) -> AssistantIntegrationFilesIssue? {
        switch readiness {
        case .ready: return nil
        case .notInstalled: return .notInstalled
        case .updateAvailable: return .updateAvailable
        case .setupIncomplete: return .setupIncomplete
        case .blocked(let state): return .blocked(state)
        }
    }

    /// Conflicts remain recoverable even when the related host is no longer
    /// installed. Missing ordinary files still defer to host discovery so an
    /// absent assistant does not look actionable.
    private func urgentIntegrationFilesIssue(
        for readiness: AssistantIntegrationReadiness
    ) -> AssistantIntegrationFilesIssue? {
        switch readiness {
        case .blocked(let state): return .blocked(state)
        case .ready, .notInstalled, .updateAvailable, .setupIncomplete: return nil
        }
    }

    private func shellCommandIssue(
        for resolution: AssistantIntegrationShellCommandResolution,
        expectedPath: String
    ) -> AssistantIntegrationShellCommandIssue? {
        switch resolution {
        case .notChecked:
            return .notChecked
        case .missing:
            return .missing(expectedPath: expectedPath)
        case .checkFailed:
            return .checkFailed(expectedPath: expectedPath)
        case .resolved(let resolvedPath):
            guard normalized(path: resolvedPath) != normalized(path: expectedPath) else {
                return nil
            }
            return .shadowed(
                expectedPath: expectedPath,
                resolvedPath: resolvedPath
            )
        }
    }

    private func bridgeIssue(
        for state: CLIConnectionState
    ) -> AssistantIntegrationBridgeIssue? {
        switch state {
        case .disabled: return .disabled
        case .starting: return .starting
        case .available: return nil
        case .unavailable(let failure): return .unavailable(failure)
        }
    }

    private func liveVerificationIssue(
        for state: AssistantIntegrationLiveVerificationState
    ) -> AssistantIntegrationLiveVerificationIssue? {
        switch state {
        case .notRun: return .notRun
        case .succeeded: return nil
        case .failed(let failure): return .failed(failure)
        }
    }

    private func normalized(path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
