import Foundation

/// Canonical filesystem lifecycle for Screenlogger assistant integrations.
///
/// UI and CLI layers choose user intent and locate the bundled source. This
/// service alone owns path layout, ownership checks, atomic replacement, stale
/// upgrades, conflict behavior, and OpenClaw registration.
public struct AssistantIntegrationService: Sendable {
    public static let skillFolderName = "screenlog-cli-skill"

    public let homeDirectory: URL
    let grokHomeDirectory: URL?

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.grokHomeDirectory = Self.resolveGrokHomeDirectory(
            homeDirectory: homeDirectory,
            environment: environment
        )
    }

    /// Grok Build uses `GROK_HOME` for both its executable and user skills.
    /// Reject malformed or relative overrides instead of guessing a location.
    static func resolveGrokHomeDirectory(
        homeDirectory: URL,
        environment: [String: String]
    ) -> URL? {
        let homeDirectory = homeDirectory.standardizedFileURL
        guard let configured = environment["GROK_HOME"] else {
            return homeDirectory.appendingPathComponent(".grok", isDirectory: true)
        }
        guard !configured.isEmpty, !configured.contains("\0") else { return nil }

        let expanded: URL
        if configured == "~" {
            expanded = homeDirectory
        } else if configured.hasPrefix("~/") {
            expanded = homeDirectory.appendingPathComponent(
                String(configured.dropFirst(2)),
                isDirectory: true
            )
        } else {
            guard configured.hasPrefix("/") else { return nil }
            expanded = URL(fileURLWithPath: configured, isDirectory: true)
        }

        let result = expanded.standardizedFileURL
        guard result.path != "/", !result.path.isEmpty else { return nil }
        return result
    }
}
