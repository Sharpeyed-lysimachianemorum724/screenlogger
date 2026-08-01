import Foundation
import ScreenlogCore

/// Versioned, machine-readable status for assistants and shell automation.
/// The document intentionally carries typed issue codes instead of parsing
/// human prose. Human-readable `screenlog status` output remains unchanged.
struct CLIStatusDocument: Encodable, Equatable {
    enum Health: String, Codable { case ok, degraded }
    typealias Issue = CLIDiagnosticIssue
    enum Warning: String, Codable { case accessibilityUnavailable = "accessibility_unavailable" }

    let schemaVersion: Int
    let health: Health
    let issues: [Issue]
    let warnings: [Warning]
    let appVersion: String
    let recording: Bool
    let capturePauseReason: String?
    let connections: Int
    let totalFrames: Int64?
    let unfinalizedFrames: Int64?
    let minTimestampMs: Int64?
    let maxTimestampMs: Int64?
    let screenRecording: Bool?
    let accessibility: Bool?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, health, issues, warnings, appVersion, recording
        case capturePauseReason, connections, totalFrames, unfinalizedFrames
        case minTimestampMs, maxTimestampMs, screenRecording, accessibility
    }

    init(status: DaemonStatus) {
        var issues: [Issue] = []
        if status.dataRoot == nil { issues.append(.dataRootUnavailable) }
        if status.totalFrames == nil || status.unfinalizedFrames == nil {
            issues.append(.frameStatisticsUnavailable)
        }
        if status.screenRecording != true { issues.append(.screenRecordingUnavailable) }
        if status.accessibility != true { issues.append(.accessibilityUnavailable) }
        if status.pauseReason == .lowDiskSpace { issues.append(.lowDiskSpace) }
        self.schemaVersion = 1
        self.health = issues.isEmpty ? .ok : .degraded
        self.issues = issues
        self.warnings = []
        self.appVersion = status.version
        self.recording = status.recording
        self.capturePauseReason = status.pauseReason?.rawValue
        self.connections = status.connections
        self.totalFrames = status.totalFrames
        self.unfinalizedFrames = status.unfinalizedFrames
        self.minTimestampMs = status.minTimestampMs
        self.maxTimestampMs = status.maxTimestampMs
        self.screenRecording = status.screenRecording
        self.accessibility = status.accessibility
    }

    /// Keep every schema-v1 key present. Unknown optional values encode as
    /// JSON null instead of disappearing, so shell and assistant clients can
    /// distinguish "unknown" from a future schema removing a field.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(health, forKey: .health)
        try container.encode(issues, forKey: .issues)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(recording, forKey: .recording)
        try container.encode(connections, forKey: .connections)
        try container.encodeOptional(capturePauseReason, forKey: .capturePauseReason)
        try container.encodeOptional(totalFrames, forKey: .totalFrames)
        try container.encodeOptional(unfinalizedFrames, forKey: .unfinalizedFrames)
        try container.encodeOptional(minTimestampMs, forKey: .minTimestampMs)
        try container.encodeOptional(maxTimestampMs, forKey: .maxTimestampMs)
        try container.encodeOptional(screenRecording, forKey: .screenRecording)
        try container.encodeOptional(accessibility, forKey: .accessibility)
    }
}

/// Doctor output deliberately reports path comparisons rather than serializing
/// the user's Library or socket path. That keeps diagnostic JSON useful to an
/// assistant without needlessly disclosing account-specific filesystem data.
struct CLIDoctorDocument: Encodable, Equatable {
    enum Health: String, Codable { case ok, degraded }
    typealias Issue = CLIDiagnosticIssue
    enum Warning: String, Codable {
        case accessibilityUnavailable = "accessibility_unavailable"
        case productVersionDifference = "product_version_difference"
    }

    let schemaVersion: Int
    let health: Health
    let issues: [Issue]
    let warnings: [Warning]
    let cliVersion: String
    let appVersion: String?
    let bridgeConnected: Bool
    let socketPresent: Bool
    let recording: Bool?
    let capturePauseReason: String?
    let screenRecording: Bool?
    let accessibility: Bool?
    let frameCount: Int64?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, health, issues, warnings, cliVersion, appVersion
        case bridgeConnected, socketPresent, recording, capturePauseReason
        case screenRecording, accessibility, frameCount
    }

    init(
        root: URL,
        socketPresent: Bool,
        ping: String,
        status: DaemonStatus,
        cliVersion: String
    ) {
        var issues: [Issue] = []
        var warnings: [Warning] = []
        if !socketPresent { issues.append(.socketUnavailable) }
        if ping != "pong \(status.version)" { issues.append(.unexpectedPing) }
        // Every successful client call has already negotiated a compatible IPC
        // protocol version. Product versions may differ during a rolling app or
        // command upgrade without making the local bridge unhealthy.
        if status.version != cliVersion { warnings.append(.productVersionDifference) }
        if let appRoot = status.dataRoot {
            let expected = root.standardizedFileURL.path
            let actual = URL(fileURLWithPath: appRoot, isDirectory: true).standardizedFileURL.path
            if actual != expected { issues.append(.dataRootMismatch) }
        } else {
            issues.append(.dataRootUnavailable)
        }
        if status.screenRecording != true { issues.append(.screenRecordingUnavailable) }
        if status.accessibility != true { issues.append(.accessibilityUnavailable) }
        if status.pauseReason == .lowDiskSpace { issues.append(.lowDiskSpace) }
        if status.totalFrames == nil { issues.append(.frameStatisticsUnavailable) }

        self.schemaVersion = 1
        self.health = issues.isEmpty ? .ok : .degraded
        self.issues = issues
        self.warnings = warnings
        self.cliVersion = cliVersion
        self.appVersion = status.version
        self.bridgeConnected = true
        self.socketPresent = socketPresent
        self.recording = status.recording
        self.capturePauseReason = status.pauseReason?.rawValue
        self.screenRecording = status.screenRecording
        self.accessibility = status.accessibility
        self.frameCount = status.totalFrames
    }

    init(connectionUnavailableWithSocketPresent socketPresent: Bool, cliVersion: String) {
        self.init(
            connectionIssue: .bridgeUnavailable,
            socketPresent: socketPresent,
            cliVersion: cliVersion
        )
    }

    init(connectionFailure: XPCClientError, socketPresent: Bool, cliVersion: String) {
        let issue: Issue
        if case .incompatibleProtocol = connectionFailure {
            issue = .incompatibleProtocol
        } else {
            issue = .bridgeUnavailable
        }
        self.init(
            connectionIssue: issue,
            socketPresent: socketPresent,
            cliVersion: cliVersion
        )
    }

    private init(connectionIssue: Issue, socketPresent: Bool, cliVersion: String) {
        self.schemaVersion = 1
        self.health = .degraded
        self.issues =
            socketPresent
            ? [connectionIssue]
            : [.socketUnavailable, connectionIssue]
        self.warnings = []
        self.cliVersion = cliVersion
        self.appVersion = nil
        self.bridgeConnected = false
        self.socketPresent = socketPresent
        self.recording = nil
        self.capturePauseReason = nil
        self.screenRecording = nil
        self.accessibility = nil
        self.frameCount = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(health, forKey: .health)
        try container.encode(issues, forKey: .issues)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(cliVersion, forKey: .cliVersion)
        try container.encode(bridgeConnected, forKey: .bridgeConnected)
        try container.encode(socketPresent, forKey: .socketPresent)
        try container.encodeOptional(appVersion, forKey: .appVersion)
        try container.encodeOptional(recording, forKey: .recording)
        try container.encodeOptional(capturePauseReason, forKey: .capturePauseReason)
        try container.encodeOptional(screenRecording, forKey: .screenRecording)
        try container.encodeOptional(accessibility, forKey: .accessibility)
        try container.encodeOptional(frameCount, forKey: .frameCount)
    }
}

extension KeyedEncodingContainer {
    fileprivate mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
