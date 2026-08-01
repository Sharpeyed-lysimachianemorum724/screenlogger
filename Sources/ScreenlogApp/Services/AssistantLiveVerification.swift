import Foundation
import ScreenlogCore

/// Executes Screenlogger's authenticated managed command and reduces its
/// bounded, privacy-safe doctor document to local-connection readiness.
///
/// This deliberately does not launch, authenticate, or test an assistant host.
/// A successful result only proves that the managed command can reach the
/// running Screenlogger Library through a compatible local protocol.
enum AssistantLiveVerificationService {
    struct ProcessResult: Equatable, Sendable {
        let terminationStatus: Int32
        let standardOutput: Data
    }

    typealias Runner = (URL) -> ProcessResult?

    static func verify(
        executable: URL,
        expectedCLIVersion: String = ScreenlogCore.version,
        runner: Runner = runDoctor
    ) -> AssistantIntegrationLiveVerificationState {
        guard let result = runner(executable) else {
            return .failed(.commandFailed)
        }
        return classify(
            result,
            expectedCLIVersion: expectedCLIVersion
        )
    }

    static func classify(
        _ result: ProcessResult,
        expectedCLIVersion: String
    ) -> AssistantIntegrationLiveVerificationState {
        guard result.standardOutput.count <= 64 * 1_024,
            let document = try? JSONDecoder().decode(
                DoctorDocument.self,
                from: result.standardOutput
            ),
            document.schemaVersion == 1
        else {
            return .failed(.invalidResponse)
        }
        guard document.cliVersion == expectedCLIVersion else {
            return .failed(.versionMismatch)
        }

        let issues = Set(document.issues)
        if issues.contains(.incompatibleProtocol) {
            return .failed(.protocolMismatch)
        }
        if issues.contains(.bridgeUnavailable) || issues.contains(.socketUnavailable) {
            return .failed(.appUnavailable)
        }
        if issues.contains(.unexpectedPing) {
            return .failed(.invalidResponse)
        }

        let nonBlockingIssues: Set<DoctorIssue> = [
            .screenRecordingUnavailable,
            .lowDiskSpace,
        ]
        guard document.bridgeConnected, issues.subtracting(nonBlockingIssues).isEmpty else {
            return .failed(.commandFailed)
        }
        if result.terminationStatus != 0 {
            guard !issues.isEmpty, issues.isSubset(of: nonBlockingIssues) else {
                return .failed(.commandFailed)
            }
        }
        return .succeeded
    }

    private static func runDoctor(executable: URL) -> ProcessResult? {
        switch BoundedLocalCommandRunner.run(
            executable: executable,
            arguments: ["doctor", "--json"],
            outputByteLimit: 64 * 1_024
        ) {
        case .success(let result):
            return ProcessResult(
                terminationStatus: result.terminationStatus,
                standardOutput: result.standardOutput
            )
        case .failure(.outputLimitExceeded):
            return ProcessResult(
                terminationStatus: -1,
                standardOutput: Data(count: 64 * 1_024 + 1)
            )
        case .failure:
            return nil
        }
    }
}

private struct DoctorDocument: Decodable {
    let schemaVersion: Int
    let issues: [DoctorIssue]
    let cliVersion: String
    let bridgeConnected: Bool
}

private enum DoctorIssue: String, Decodable {
    case bridgeUnavailable = "bridge_unavailable"
    case incompatibleProtocol = "incompatible_protocol"
    case socketUnavailable = "socket_unavailable"
    case unexpectedPing = "unexpected_ping"
    case dataRootMismatch = "data_root_mismatch"
    case dataRootUnavailable = "data_root_unavailable"
    case screenRecordingUnavailable = "screen_recording_unavailable"
    case lowDiskSpace = "low_disk_space"
    case frameStatisticsUnavailable = "frame_statistics_unavailable"
}
