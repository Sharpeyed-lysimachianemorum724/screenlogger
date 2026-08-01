import Foundation
import ScreenlogCore

extension ScreenlogCLIMain {
    // MARK: - status / stats

    static func status(_ args: [String], client: ScreenlogXPCClient) throws {
        guard args.isEmpty || args == ["--json"] else {
            throw CLIError.usage("status [--json]")
        }
        let s = try client.status()
        if args == ["--json"] {
            try printJSON(CLIStatusDocument(status: s))
            return
        }
        guard let dataRoot = s.dataRoot,
            let totalFrames = s.totalFrames,
            let unfinalizedFrames = s.unfinalizedFrames,
            let screenRecording = s.screenRecording,
            let accessibility = s.accessibility
        else {
            throw CLIError.message("app returned an incomplete status response")
        }
        print("version: \(s.version)")
        print("recording: \(s.recording)")
        if let reason = s.pauseReason {
            print("capture_pause_reason: \(reason.rawValue)")
            print("capture_pause_detail: \(reason.userDescription)")
        }
        print("xpc_connections: \(s.connections)")
        print("data_root: \(dataRoot)")
        print("total_frames: \(totalFrames)")
        print("unfinalized: \(unfinalizedFrames)")
        if let n = s.minTimestampMs { print("min_ts: \(n)") }
        if let n = s.maxTimestampMs { print("max_ts: \(n)") }
        print("screen_recording: \(screenRecording)")
        print("accessibility: \(accessibility)")
        if !accessibility {
            print("capability_error: Accessibility is required before capture can start")
        }
        print("health: \(screenRecording && accessibility ? "ok" : "degraded")")
    }

    static func stats(client: ScreenlogXPCClient) throws {
        let s = try client.stats()
        print(
            "total_frames=\(s.totalFrames) unfinalized=\(s.unfinalizedFrames) min_ts=\(s.minTimestampMs ?? -1) max_ts=\(s.maxTimestampMs ?? -1)"
        )
    }

    static func doctor(_ args: [String], root: URL, client: ScreenlogXPCClient) async throws {
        guard args.isEmpty || args == ["--json"] else {
            throw CLIError.usage("doctor [--json]")
        }
        let socketPresent = FileManager.default.fileExists(
            atPath: ScreenlogSocketPaths.socketURL(root: root).path
        )
        if args == ["--json"] {
            let report: CLIDoctorDocument
            do {
                let ping = try client.ping()
                let status = try client.status()
                report = CLIDoctorDocument(
                    root: root,
                    socketPresent: socketPresent,
                    ping: ping,
                    status: status,
                    cliVersion: ScreenlogCore.version
                )
            } catch let error as XPCClientError {
                report = CLIDoctorDocument(
                    connectionFailure: error,
                    socketPresent: socketPresent,
                    cliVersion: ScreenlogCore.version
                )
            } catch {
                // The common "app is closed" path still has a complete JSON
                // contract. Raw transport errors and private paths stay out of
                // the document; the process remains nonzero for automation.
                report = CLIDoctorDocument(
                    connectionUnavailableWithSocketPresent: socketPresent,
                    cliVersion: ScreenlogCore.version
                )
            }
            try printJSON(report)
            if report.health == .degraded {
                throw CLIError.message("doctor found \(report.issues.count) issue(s)")
            }
            return
        }

        let ping = try client.ping()
        let st = try client.status()
        let report = CLIDoctorDocument(
            root: root,
            socketPresent: socketPresent,
            ping: ping,
            status: st,
            cliVersion: ScreenlogCore.version
        )
        print("cli_version: \(ScreenlogCore.version)")
        print("data: \(root.path)")
        let sock = ScreenlogSocketPaths.socketURL(root: root).path
        print("cli_socket: \(sock)")
        print("cli_socket_exists: \(socketPresent)")
        print("xpc_ping: \(ping)")
        print("app_version: \(st.version)")
        print("recording: \(st.recording)")
        print("capture_pause_reason: \(st.pauseReason?.rawValue ?? "none")")
        print("screen_recording: \(st.screenRecording.map(String.init) ?? "unknown")")
        print("accessibility: \(st.accessibility.map(String.init) ?? "unknown")")
        print("frames: \(st.totalFrames.map(String.init) ?? "unknown")")

        for warning in report.warnings { print("warning: \(doctorWarningDescription(warning))") }
        if report.issues.isEmpty {
            print("health: ok")
        } else {
            print("health: degraded")
            for issue in report.issues { print("issue: \(doctorIssueDescription(issue))") }
            throw CLIError.message("doctor found \(report.issues.count) issue(s)")
        }
    }

    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    static func doctorIssueDescription(_ issue: CLIDoctorDocument.Issue) -> String {
        switch issue {
        case .bridgeUnavailable: return "Screenlogger.app is not reachable"
        case .incompatibleProtocol:
            return "Screenlogger.app and the screenlog command use incompatible local protocols"
        case .socketUnavailable: return "the local command-line socket is unavailable"
        case .unexpectedPing: return "the app returned an unexpected ping response"
        case .dataRootMismatch: return "the app is serving a different data root"
        case .dataRootUnavailable: return "the app data root is unavailable"
        case .screenRecordingUnavailable: return "Screen Recording permission is unavailable"
        case .accessibilityUnavailable: return "Accessibility permission is unavailable"
        case .lowDiskSpace: return "capture is paused until more disk space is available"
        case .frameStatisticsUnavailable: return "frame statistics are unavailable"
        }
    }

    static func doctorWarningDescription(_ warning: CLIDoctorDocument.Warning) -> String {
        switch warning {
        case .accessibilityUnavailable:
            return "Accessibility permission is unavailable"
        case .productVersionDifference:
            return
                "Screenlogger.app and the screenlog command have different product versions, but their local protocol is compatible"
        }
    }
}
