import Foundation
import XCTest

final class CLICommandAvailabilityTests: XCTestCase {
    func testInstalledCommandStartsUnverifiedWithoutLaunchingAShell() {
        let expected = URL(fileURLWithPath: "/Users/test/.local/bin/screenlog")
        let availability = CLICommandAvailabilityService.notChecked(
            expectedExecutable: expected
        )

        guard case .notChecked(let path, _) = availability else {
            return XCTFail("Expected an explicit not-checked state")
        }
        XCTAssertEqual(path, expected.path)
        XCTAssertFalse(availability.isAvailable)
        XCTAssertFalse(availability.isChecking)
    }

    func testFreshCommandAutomaticallyStartsCommandAvailabilityCheck() {
        let setup = CLICommandAvailabilityService.pathSetup(forShellPath: "/bin/zsh")

        XCTAssertEqual(
            CLICommandAvailability.notChecked(
                expectedPath: "/Users/test/.local/bin/screenlog",
                setup: setup
            ).automaticAssistantAccessVerificationAction,
            .checkCommandAvailability
        )
        XCTAssertEqual(
            CLICommandAvailability.unknown.automaticAssistantAccessVerificationAction,
            .checkCommandAvailability
        )
    }

    func testAvailableCommandAutomaticallyContinuesToLiveVerification() {
        XCTAssertEqual(
            CLICommandAvailability.available(
                path: "/Users/test/.local/bin/screenlog"
            ).automaticAssistantAccessVerificationAction,
            .verifyLiveAccess
        )
    }

    func testAutomaticVerificationDoesNotRetryPendingOrFailedChecks() {
        let expectedPath = "/Users/test/.local/bin/screenlog"
        let setup = CLICommandAvailabilityService.pathSetup(forShellPath: "/bin/zsh")
        let states: [CLICommandAvailability] = [
            .checking,
            .unavailable(expectedPath: expectedPath, setup: setup),
            .shadowed(
                expectedPath: expectedPath,
                resolvedPath: "/opt/homebrew/bin/screenlog",
                setup: setup
            ),
            .checkFailed(expectedPath: expectedPath, setup: setup),
        ]

        for state in states {
            XCTAssertEqual(
                state.automaticAssistantAccessVerificationAction,
                .noAction,
                "Unexpected automatic retry for \(state)"
            )
        }
    }

    func testAutomaticPreparationPreservesPendingAndCompletedChecks() {
        let expectedPath = "/Users/test/.local/bin/screenlog"
        let setup = CLICommandAvailabilityService.pathSetup(forShellPath: "/bin/zsh")

        XCTAssertFalse(
            CLICommandAvailability.checking.needsPreparation(
                expectedPath: expectedPath,
                forceReset: false
            )
        )
        XCTAssertFalse(
            CLICommandAvailability.unavailable(
                expectedPath: expectedPath,
                setup: setup
            ).needsPreparation(expectedPath: expectedPath, forceReset: false)
        )
        XCTAssertTrue(
            CLICommandAvailability.unknown.needsPreparation(
                expectedPath: expectedPath,
                forceReset: false
            )
        )
        XCTAssertTrue(
            CLICommandAvailability.checking.needsPreparation(
                expectedPath: expectedPath,
                forceReset: true
            )
        )
    }

    func testExactManagedCommandIsAvailable() {
        let setup = CLICommandAvailabilityService.pathSetup(forShellPath: "/bin/zsh")
        XCTAssertEqual(
            CLICommandAvailabilityService.classify(
                expectedPath: "/Users/test/.local/bin/screenlog",
                resolvedPath: "/Users/test/.local/bin/screenlog",
                setup: setup
            ),
            .available(path: "/Users/test/.local/bin/screenlog")
        )
    }

    func testDifferentCommandIsReportedAsShadowingManagedCommand() {
        let setup = CLICommandAvailabilityService.pathSetup(forShellPath: "/bin/zsh")
        XCTAssertEqual(
            CLICommandAvailabilityService.classify(
                expectedPath: "/Users/test/.local/bin/screenlog",
                resolvedPath: "/opt/homebrew/bin/screenlog",
                setup: setup
            ),
            .shadowed(
                expectedPath: "/Users/test/.local/bin/screenlog",
                resolvedPath: "/opt/homebrew/bin/screenlog",
                setup: setup
            )
        )
    }

    func testSymlinkToManagedCommandIsNotReportedAsShadowing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "screenlogger-path-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let managed = root.appendingPathComponent("managed-screenlog")
        let linked = root.appendingPathComponent("screenlog")
        try Data("test".utf8).write(to: managed)
        try FileManager.default.createSymbolicLink(
            at: linked,
            withDestinationURL: managed
        )

        XCTAssertEqual(
            CLICommandAvailabilityService.classify(
                expectedPath: managed.path,
                resolvedPath: linked.path,
                setup: nil
            ),
            .available(path: managed.path)
        )
    }

    func testMissingShellResolutionIsNotAvailable() {
        let setup = CLICommandAvailabilityService.pathSetup(forShellPath: "/bin/bash")
        XCTAssertEqual(
            CLICommandAvailabilityService.classify(
                expectedPath: "/Users/test/.local/bin/screenlog",
                resolvedPath: nil,
                setup: setup
            ),
            .unavailable(
                expectedPath: "/Users/test/.local/bin/screenlog",
                setup: setup
            )
        )
    }

    func testRecognizedShellsOfferIdempotentCopyableSetup() throws {
        let zsh = try XCTUnwrap(
            CLICommandAvailabilityService.pathSetup(forShellPath: "/bin/zsh")
        )
        XCTAssertEqual(zsh.shellName, "zsh")
        XCTAssertTrue(zsh.command.contains("$HOME/.zprofile"))
        XCTAssertTrue(zsh.command.contains("grep -qxF"))
        XCTAssertTrue(zsh.command.contains("$HOME/.local/bin"))

        let fish = try XCTUnwrap(
            CLICommandAvailabilityService.pathSetup(
                forShellPath: "/opt/homebrew/bin/fish"
            )
        )
        XCTAssertEqual(fish.shellName, "fish")
        XCTAssertEqual(fish.command, "fish_add_path \"$HOME/.local/bin\"")
    }

    func testUnknownShellDoesNotInventSetupInstructions() {
        XCTAssertNil(
            CLICommandAvailabilityService.pathSetup(
                forShellPath: "/usr/local/bin/custom-shell"
            )
        )
    }
}
