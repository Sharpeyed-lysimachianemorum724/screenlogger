import Foundation

/// Discovers installed assistant products with a supported integration shape.
///
/// Integration files and assistant configuration are intentionally not inputs:
/// installing a skill must never make an assistant appear to be installed.
/// Discovery does not prove that a host loaded the integration, authenticated,
/// or completed a Screenlogger search.
public struct AssistantHostDiscovery: Sendable {
    public struct Result: Equatable, Sendable {
        public let appURL: URL?
        public let cliURL: URL?

        public var isPresent: Bool {
            appURL != nil || cliURL != nil
        }

        public init(appURL: URL?, cliURL: URL?) {
            self.appURL = appURL
            self.cliURL = cliURL
        }
    }

    /// Injectable product probes keep discovery deterministic in tests and let
    /// every client share the same compatibility policy.
    public struct Probes: Sendable {
        private final class FileSystem: @unchecked Sendable {
            let fileManager: FileManager

            init(_ fileManager: FileManager) {
                self.fileManager = fileManager
            }
        }

        public let executableURL: @Sendable (String) -> URL?
        public let applicationURL: @Sendable (String) -> URL?

        public init(
            executableURL: @escaping @Sendable (String) -> URL?,
            applicationURL: @escaping @Sendable (String) -> URL?
        ) {
            self.executableURL = executableURL
            self.applicationURL = applicationURL
        }

        public static var live: Probes {
            fileSystem()
        }

        static func fileSystem(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
            applicationDirectories: [URL]? = nil,
            fileManager: FileManager = .default
        ) -> Probes {
            let fileSystem = FileSystem(fileManager)
            let appDirectories =
                applicationDirectories ?? [
                    URL(fileURLWithPath: "/Applications", isDirectory: true),
                    homeDirectory.appendingPathComponent("Applications", isDirectory: true),
                ]

            return Probes(
                executableURL: { name in
                    executableURL(
                        named: name,
                        environment: environment,
                        homeDirectory: homeDirectory,
                        fileManager: fileSystem.fileManager
                    )
                },
                applicationURL: { name in
                    compatibleApplicationURL(
                        named: name,
                        directories: appDirectories,
                        fileManager: fileSystem.fileManager
                    )
                }
            )
        }

        private static func executableURL(
            named name: String,
            environment: [String: String],
            homeDirectory: URL,
            fileManager: FileManager
        ) -> URL? {
            if name == "grok" {
                guard
                    let grokHome = AssistantIntegrationService.resolveGrokHomeDirectory(
                        homeDirectory: homeDirectory,
                        environment: environment
                    )
                else { return nil }
                let candidate = grokHome.appendingPathComponent(
                    "bin/grok",
                    isDirectory: false
                )
                var isDirectory: ObjCBool = false
                guard
                    fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                    !isDirectory.boolValue,
                    fileManager.isExecutableFile(atPath: candidate.path)
                else { return nil }
                return candidate.standardizedFileURL
            }

            var directories = (environment["PATH"] ?? "")
                .split(separator: ":", omittingEmptySubsequences: true)
                .map { URL(fileURLWithPath: String($0), isDirectory: true) }
            directories.append(contentsOf: [
                URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
                URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
                homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            ])

            var candidates = directories.map {
                $0.appendingPathComponent(name, isDirectory: false).standardizedFileURL
            }
            if name == "codex" {
                candidates.append(
                    homeDirectory.appendingPathComponent(
                        ".codex/packages/standalone/current/bin/codex",
                        isDirectory: false
                    )
                )
            } else if name == "claude" {
                candidates.append(
                    homeDirectory.appendingPathComponent(
                        ".claude/local/claude",
                        isDirectory: false
                    )
                )
            }

            return candidates.first { candidate in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(
                    atPath: candidate.path,
                    isDirectory: &isDirectory
                )
                    && !isDirectory.boolValue
                    && fileManager.isExecutableFile(atPath: candidate.path)
            }
        }

        private static func compatibleApplicationURL(
            named name: String,
            directories: [URL],
            fileManager: FileManager
        ) -> URL? {
            directories.lazy.compactMap { directory -> URL? in
                let candidate = directory.appendingPathComponent(
                    "\(name).app",
                    isDirectory: true
                )
                var isDirectory: ObjCBool = false
                guard
                    fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                    isDirectory.boolValue,
                    let infoData = try? Data(
                        contentsOf: candidate.appendingPathComponent("Contents/Info.plist")
                    ),
                    let info = try? PropertyListSerialization.propertyList(
                        from: infoData,
                        options: [],
                        format: nil
                    ) as? [String: Any],
                    info["CFBundlePackageType"] as? String == "APPL",
                    let bundleIdentifier = info["CFBundleIdentifier"] as? String,
                    !bundleIdentifier.isEmpty,
                    let executableName = info["CFBundleExecutable"] as? String,
                    !executableName.isEmpty
                else {
                    return nil
                }
                let executableURL = candidate.appendingPathComponent(
                    "Contents/MacOS/\(executableName)",
                    isDirectory: false
                )
                guard fileManager.isExecutableFile(atPath: executableURL.path) else {
                    return nil
                }
                return candidate.standardizedFileURL
            }.first
        }
    }

    private let probes: Probes

    public init(probes: Probes = .live) {
        self.probes = probes
    }

    public func detect(_ target: AssistantIntegrationTarget) -> Result {
        let specification = specification(for: target)
        return Result(
            appURL: specification.applicationName.flatMap(probes.applicationURL),
            cliURL: probes.executableURL(specification.executableName)
        )
    }

    public func detectedTargets() -> [AssistantIntegrationTarget] {
        AssistantIntegrationTarget.allCases.filter { detect($0).isPresent }
    }

    private func specification(
        for target: AssistantIntegrationTarget
    ) -> (executableName: String, applicationName: String?) {
        switch target {
        case .claude:
            return ("claude", "Claude Code")
        case .cursor:
            // Cursor's editor shell command opens files and folders; only the
            // Agent CLI accepts an initial assistant request.
            return ("cursor-agent", "Cursor")
        case .codex:
            return ("codex", "Codex")
        case .grok:
            return ("grok", nil)
        case .openclaw:
            return ("openclaw", nil)
        }
    }
}
