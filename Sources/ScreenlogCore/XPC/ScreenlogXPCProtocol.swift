import Foundation

/// Mach service name (LaunchAgent / production). Dev uses anonymous endpoint file.
public let ScreenlogXPCServiceName = "dev.screenlog.xpc"

/// CLI to app protocol. The app owns SQLite and capture.
@objc public protocol ScreenlogDaemonProtocol {
    func xpcPing(with reply: @escaping (String) -> Void)
    /// JSON-encoded `DaemonStatus`.
    func xpcGetStatus(with reply: @escaping (Data?, String?) -> Void)

    func xpcStartRecording(with reply: @escaping (Bool, String?) -> Void)
    func xpcStopRecording(with reply: @escaping (Bool, String?) -> Void)
    func xpcCaptureOnce(with reply: @escaping (Int64, String?) -> Void)

    func xpcFTS(query: String, limit: Int, with reply: @escaping (Data?, String?) -> Void)
    func xpcStats(with reply: @escaping (Data?, String?) -> Void)
    func xpcTopApplications(limit: Int, with reply: @escaping (Data?, String?) -> Void)
    func xpcTopDomains(limit: Int, with reply: @escaping (Data?, String?) -> Void)
    func xpcSessions(gapMinutes: Int, with reply: @escaping (Data?, String?) -> Void)
    func xpcSample(limit: Int, minSegLen: Int, with reply: @escaping (Data?, String?) -> Void)
    func xpcFrame(id: Int64, with reply: @escaping (Data?, String?) -> Void)
    /// Nearest frame to `timestampMs` (JSON `FrameRow`).
    func xpcFrameAt(timestampMs: Int64, with reply: @escaping (Data?, String?) -> Void)
    func xpcOCRBoxes(frameID: Int64, with reply: @escaping (Data?, String?) -> Void)
    func xpcListApplications(with reply: @escaping (Data?, String?) -> Void)
    func xpcListDomains(with reply: @escaping (Data?, String?) -> Void)
    func xpcAXTree(frameID: Int64, with reply: @escaping (String?, String?) -> Void)

    /// Extract still (from `image_path` or compacted video via `FrameExtractor`).
    /// - Parameters:
    ///   - frameID: >0 selects by id; otherwise nearest to `timestampMs` is used.
    ///   - timestampMs: used when `frameID` is 0 or negative.
    ///   - outPath: empty string means host default export path; otherwise absolute file/dir.
    ///   - preferBase64: include base64 payload in JSON result (may be large).
    /// - Returns: JSON `ExtractImageResult` or error string.
    func xpcExtractImage(
        frameID: Int64,
        timestampMs: Int64,
        outPath: String,
        preferBase64: Bool,
        with reply: @escaping (Data?, String?) -> Void
    )

    func xpcCompact(with reply: @escaping (Int, String?) -> Void)
    func xpcRunRetention(with reply: @escaping (String?, String?) -> Void)
    func xpcPermissions(with reply: @escaping ([String: Bool]) -> Void)
}

/// App to CLI events for the optional reverse channel.
@objc public protocol ScreenlogClientProtocol {
    func xpcSurfaceEvent(jsonEvent: String)
}
