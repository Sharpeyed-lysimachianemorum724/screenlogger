import Darwin
import Foundation

struct CLIPathSetup: Equatable, Sendable {
    let shellName: String
    let command: String
}

enum CLICommandAvailability: Equatable, Sendable {
    case unknown
    case notChecked(expectedPath: String, setup: CLIPathSetup?)
    case checking
    case available(path: String)
    case unavailable(expectedPath: String, setup: CLIPathSetup?)
    case shadowed(expectedPath: String, resolvedPath: String, setup: CLIPathSetup?)
    case checkFailed(expectedPath: String, setup: CLIPathSetup?)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var setup: CLIPathSetup? {
        switch self {
        case .notChecked(_, let setup), .unavailable(_, let setup),
            .shadowed(_, _, let setup),
            .checkFailed(_, let setup):
            return setup
        case .unknown, .checking, .available:
            return nil
        }
    }

    var expectedPath: String? {
        switch self {
        case .notChecked(let path, _), .unavailable(let path, _),
            .shadowed(let path, _, _), .checkFailed(let path, _),
            .available(let path):
            return path
        case .unknown, .checking:
            return nil
        }
    }

    var automaticAssistantAccessVerificationAction: CLIAssistantAccessVerificationAction {
        switch self {
        case .unknown, .notChecked:
            return .checkCommandAvailability
        case .available:
            return .verifyLiveAccess
        case .checking, .unavailable, .shadowed, .checkFailed:
            return .noAction
        }
    }

    func needsPreparation(expectedPath: String, forceReset: Bool) -> Bool {
        if forceReset { return true }
        if isChecking { return false }
        return self.expectedPath != expectedPath
    }
}

enum CLIAssistantAccessVerificationAction: Equatable, Sendable {
    case checkCommandAvailability
    case verifyLiveAccess
    case noAction
}

/// Checks the user's login-shell command lookup during automatic integration
/// verification or after an explicit Settings action. It never edits shell
/// configuration; Settings can only copy an explicit setup command for a
/// recognized shell.
enum CLICommandAvailabilityService {
    static func notChecked(expectedExecutable: URL) -> CLICommandAvailability {
        .notChecked(
            expectedPath: expectedExecutable.path,
            setup: pathSetup(forShellPath: currentUserShellPath())
        )
    }

    static func inspect(expectedExecutable: URL) -> CLICommandAvailability {
        let shellPath = currentUserShellPath()
        let setup = pathSetup(forShellPath: shellPath)
        guard FileManager.default.isExecutableFile(atPath: shellPath) else {
            return .checkFailed(expectedPath: expectedExecutable.path, setup: setup)
        }

        let process = Process()
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "screenlogger-path-check-\(UUID().uuidString)",
            isDirectory: true
        )
        let output = outputDirectory.appendingPathComponent("resolved-path.txt")
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: false
            )
        } catch {
            return .checkFailed(expectedPath: expectedExecutable.path, setup: setup)
        }
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        process.executableURL = URL(fileURLWithPath: shellPath)
        process.arguments = [
            "-lic",
            "command -v screenlog > \"$SCREENLOGGER_PATH_CHECK_OUTPUT\"",
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["SCREENLOGGER_PATH_CHECK_OUTPUT"] = output.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        do {
            try process.run()
        } catch {
            return .checkFailed(expectedPath: expectedExecutable.path, setup: setup)
        }

        var didComplete = false
        for _ in 0..<50 {
            if Task.isCancelled {
                process.terminate()
                _ = completed.wait(timeout: .now() + 1)
                return .checkFailed(expectedPath: expectedExecutable.path, setup: setup)
            }
            if completed.wait(timeout: .now() + 0.1) == .success {
                didComplete = true
                break
            }
        }
        guard didComplete else {
            process.terminate()
            _ = completed.wait(timeout: .now() + 1)
            return .checkFailed(expectedPath: expectedExecutable.path, setup: setup)
        }

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            return .unavailable(expectedPath: expectedExecutable.path, setup: setup)
        }

        guard
            let size = try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= 4_096,
            let data = try? Data(contentsOf: output)
        else {
            return .unavailable(expectedPath: expectedExecutable.path, setup: setup)
        }
        guard
            let rawOutput = String(data: data, encoding: .utf8),
            let resolvedPath = rawOutput.split(whereSeparator: \.isNewline).first.map(String.init),
            resolvedPath.hasPrefix("/")
        else {
            return .unavailable(expectedPath: expectedExecutable.path, setup: setup)
        }
        return classify(
            expectedPath: expectedExecutable.path,
            resolvedPath: resolvedPath,
            setup: setup
        )
    }

    static func classify(
        expectedPath: String,
        resolvedPath: String?,
        setup: CLIPathSetup?
    ) -> CLICommandAvailability {
        guard let resolvedPath else {
            return .unavailable(expectedPath: expectedPath, setup: setup)
        }
        let expected = URL(fileURLWithPath: expectedPath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = URL(fileURLWithPath: resolvedPath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        if expected == resolved {
            return .available(path: expected)
        }
        return .shadowed(
            expectedPath: expected,
            resolvedPath: resolved,
            setup: setup
        )
    }

    static func pathSetup(forShellPath shellPath: String) -> CLIPathSetup? {
        switch URL(fileURLWithPath: shellPath).lastPathComponent {
        case "zsh":
            return CLIPathSetup(
                shellName: "zsh",
                command:
                    "grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' \"$HOME/.zprofile\" 2>/dev/null || printf '\\n%s\\n' 'export PATH=\"$HOME/.local/bin:$PATH\"' >> \"$HOME/.zprofile\""
            )
        case "bash":
            return CLIPathSetup(
                shellName: "bash",
                command:
                    "grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' \"$HOME/.bash_profile\" 2>/dev/null || printf '\\n%s\\n' 'export PATH=\"$HOME/.local/bin:$PATH\"' >> \"$HOME/.bash_profile\""
            )
        case "fish":
            return CLIPathSetup(
                shellName: "fish",
                command: "fish_add_path \"$HOME/.local/bin\""
            )
        case "sh":
            return CLIPathSetup(
                shellName: "sh",
                command:
                    "grep -qxF 'export PATH=\"$HOME/.local/bin:$PATH\"' \"$HOME/.profile\" 2>/dev/null || printf '\\n%s\\n' 'export PATH=\"$HOME/.local/bin:$PATH\"' >> \"$HOME/.profile\""
            )
        default:
            return nil
        }
    }

    static func currentUserShellPath() -> String {
        if let record = getpwuid(getuid()), let shell = record.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
}
