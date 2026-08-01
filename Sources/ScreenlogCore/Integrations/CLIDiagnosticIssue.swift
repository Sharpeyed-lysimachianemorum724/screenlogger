/// Stable issue codes shared by Screenlogger's machine-readable CLI documents
/// and the app services that consume them.
public enum CLIDiagnosticIssue: String, Codable, CaseIterable, Sendable {
    case accessibilityUnavailable = "accessibility_unavailable"
    case bridgeUnavailable = "bridge_unavailable"
    case dataRootMismatch = "data_root_mismatch"
    case dataRootUnavailable = "data_root_unavailable"
    case frameStatisticsUnavailable = "frame_statistics_unavailable"
    case incompatibleProtocol = "incompatible_protocol"
    case lowDiskSpace = "low_disk_space"
    case screenRecordingUnavailable = "screen_recording_unavailable"
    case socketUnavailable = "socket_unavailable"
    case unexpectedPing = "unexpected_ping"
}
