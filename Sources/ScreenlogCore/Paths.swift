import Foundation

/// On-disk layout for Screenlogger local data.
///
/// ```
/// ~/Library/Application Support/dev.screenlog/
///   db.sqlite3 (+ -wal / -shm)
///   frames/          # HEIC/JPEG stills while unfinalized
///   videos/          # optional HEVC after compaction
///   cli.sock         # unix domain socket for CLI bridge
/// ```
public enum ScreenlogPaths {
    public static let bundleID = "dev.screenlog"
    public static let appSupportName = "dev.screenlog"

    public static var applicationSupportRoot: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appSupportName, isDirectory: true)
    }

    public static var databaseURL: URL {
        applicationSupportRoot.appendingPathComponent("db.sqlite3", isDirectory: false)
    }

    public static var framesDirectory: URL {
        applicationSupportRoot.appendingPathComponent("frames", isDirectory: true)
    }

    public static var videosDirectory: URL {
        applicationSupportRoot.appendingPathComponent("videos", isDirectory: true)
    }

    /// XPC anonymous endpoint archive written by Screenlogger.app for the CLI.
    public static var xpcEndpointURL: URL {
        applicationSupportRoot.appendingPathComponent("xpc.endpoint", isDirectory: false)
    }

    /// Override root for tests / scratch environments via `SCREENLOG_DATA_DIR`.
    public static func resolvedRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["SCREENLOG_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return applicationSupportRoot
    }

    public static func ensureDirectories(root: URL? = nil) throws {
        let rootURL = root ?? applicationSupportRoot
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: rootURL.appendingPathComponent("frames", isDirectory: true), withIntermediateDirectories: true)
        try fm.createDirectory(at: rootURL.appendingPathComponent("videos", isDirectory: true), withIntermediateDirectories: true)
    }

    public static func databaseURL(root: URL) -> URL {
        root.appendingPathComponent("db.sqlite3")
    }

    public static func framesDirectory(root: URL) -> URL {
        root.appendingPathComponent("frames", isDirectory: true)
    }

    public static func videosDirectory(root: URL) -> URL {
        root.appendingPathComponent("videos", isDirectory: true)
    }

    public static func xpcEndpointURL(root: URL) -> URL {
        root.appendingPathComponent("xpc.endpoint")
    }
}
