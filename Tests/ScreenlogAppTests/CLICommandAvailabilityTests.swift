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
