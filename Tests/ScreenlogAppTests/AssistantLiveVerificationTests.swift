import Foundation
import ScreenlogCore
import XCTest

final class AssistantLiveVerificationTests: XCTestCase {
    func testHealthyDoctorDocumentPassesLocalConnectionCheck() {
        XCTAssertEqual(
            classify(
                status: 0,
                issues: [],
                bridgeConnected: true
            ),
            .succeeded
        )
    }

    func testNonzeroExitWithoutReportedIssuesIsNotAccepted() {
        XCTAssertEqual(
            classify(
                status: 1,
                issues: [],
                bridgeConnected: true
            ),
            .failed(.commandFailed)
        )
    }

    func testDisconnectedBridgeCannotPassWithEmptyIssues() {
        XCTAssertEqual(
            classify(
                status: 0,
                issues: [],
                bridgeConnected: false
            ),
            .failed(.commandFailed)
        )
    }

    func testCompatibleAppVersionDifferenceDoesNotBlockLocalConnectionCheck() {
        XCTAssertEqual(
            classify(
                status: 0,
                issues: [],
                bridgeConnected: true,
                appVersion: "9.9.9"
            ),
            .succeeded
        )
    }

    func testCaptureHealthDoesNotBlockSearchingExistingHistory() {
        XCTAssertEqual(
            classify(
                status: 1,
                issues: [
                    "accessibility_unavailable",
                    "screen_recording_unavailable",
                    "low_disk_space",
                ],
                bridgeConnected: true
            ),
            .succeeded
        )
    }

    func testMissingBridgeAndProtocolMismatchRemainDistinct() {
        XCTAssertEqual(
            classify(
                status: 1,
                issues: ["socket_unavailable", "bridge_unavailable"],
                bridgeConnected: false
            ),
            .failed(.appUnavailable)
        )
        XCTAssertEqual(
            classify(
                status: 1,
                issues: ["incompatible_protocol"],
                bridgeConnected: false
            ),
            .failed(.protocolMismatch)
        )
    }

    func testUnexpectedPingAndMalformedDocumentsAreInvalid() {
        XCTAssertEqual(
            classify(
                status: 1,
                issues: ["unexpected_ping"],
                bridgeConnected: true
            ),
            .failed(.invalidResponse)
        )
        XCTAssertEqual(
            AssistantLiveVerificationService.classify(
                .init(
                    terminationStatus: 0,
                    standardOutput: Data("not json".utf8)
                ),
                expectedCLIVersion: "1.2.3"
            ),
            .failed(.invalidResponse)
        )
    }

    func testOversizedAndUnsupportedDocumentsAreInvalid() {
        XCTAssertEqual(
            AssistantLiveVerificationService.classify(
                .init(
                    terminationStatus: 0,
                    standardOutput: Data(count: 64 * 1_024 + 1)
                ),
                expectedCLIVersion: "1.2.3"
            ),
            .failed(.invalidResponse)
        )

        let unsupportedSchema = doctorData(
            issues: [],
            bridgeConnected: true,
            cliVersion: "1.2.3",
            schemaVersion: 2
        )
        XCTAssertEqual(
            AssistantLiveVerificationService.classify(
                .init(terminationStatus: 0, standardOutput: unsupportedSchema),
                expectedCLIVersion: "1.2.3"
            ),
            .failed(.invalidResponse)
        )
    }

    func testWrongCLIAndUnhealthyLibraryRemainDistinct() {
        XCTAssertEqual(
            classify(
                status: 0,
                issues: [],
                bridgeConnected: true,
                cliVersion: "0.0.1"
            ),
            .failed(.versionMismatch)
        )
        XCTAssertEqual(
            classify(
                status: 1,
                issues: ["data_root_mismatch"],
                bridgeConnected: true
            ),
            .failed(.commandFailed)
        )
    }

    func testInjectedRunnerNeverReadsTheRealFilesystem() {
        let executable = URL(fileURLWithPath: "/does/not/exist/screenlog")
        let state = AssistantLiveVerificationService.verify(
            executable: executable,
            expectedCLIVersion: "1.2.3"
        ) { receivedExecutable in
            XCTAssertEqual(receivedExecutable, executable)
            return .init(
                terminationStatus: 0,
                standardOutput: doctorData(
                    issues: [],
                    bridgeConnected: true,
                    cliVersion: "1.2.3"
                )
            )
        }
        XCTAssertEqual(state, .succeeded)
    }

    private func classify(
        status: Int32,
        issues: [String],
        bridgeConnected: Bool,
        cliVersion: String = "1.2.3",
        appVersion: String = "1.2.3"
    ) -> AssistantIntegrationLiveVerificationState {
        AssistantLiveVerificationService.classify(
            .init(
                terminationStatus: status,
                standardOutput: doctorData(
                    issues: issues,
                    bridgeConnected: bridgeConnected,
                    cliVersion: cliVersion,
                    appVersion: appVersion
                )
            ),
            expectedCLIVersion: "1.2.3"
        )
    }

    private func doctorData(
        issues: [String],
        bridgeConnected: Bool,
        cliVersion: String,
        appVersion: String = "1.2.3",
        schemaVersion: Int = 1
    ) -> Data {
        let document: [String: Any] = [
            "schemaVersion": schemaVersion,
            "health": issues.isEmpty ? "ok" : "degraded",
            "issues": issues,
            "warnings": [],
            "cliVersion": cliVersion,
            "appVersion": appVersion,
            "bridgeConnected": bridgeConnected,
            "socketPresent": bridgeConnected,
        ]
        return (try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]))
            ?? Data()
    }
}
