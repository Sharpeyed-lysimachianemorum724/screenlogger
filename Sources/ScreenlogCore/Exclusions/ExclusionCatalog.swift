import AppKit
import Foundation

public struct DiscoveredApplication: Equatable, Sendable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// A stable boundary between app-catalog failures and a successful empty scan.
/// Filesystem details stay out of the UI and diagnostic callers can log the
/// underlying error before this value crosses the presentation boundary.
public enum ApplicationDiscoveryError: Error, Equatable, Sendable {
    case catalogUnavailable
}

/// Finds applications that can be selected in privacy exclusions.
///
/// Missing optional application folders are a valid empty result. A read
/// failure is only surfaced when no installed or running applications could be
/// recovered, so a single inaccessible folder does not discard useful results.
public struct ApplicationDiscoveryService: Sendable {
    typealias DirectoryCatalog = @Sendable (URL) throws -> [DiscoveredApplication]
    typealias RunningCatalog = @Sendable () throws -> [DiscoveredApplication]

    private let searchRoots: [URL]
    private let directoryCatalog: DirectoryCatalog
    private let runningCatalog: RunningCatalog

    public init() {
        searchRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
        directoryCatalog = { root in try Self.applications(in: root) }
        runningCatalog = { Self.runningApplications() }
    }

    init(
        searchRoots: [URL],
        directoryCatalog: @escaping DirectoryCatalog,
        runningCatalog: @escaping RunningCatalog
    ) {
        self.searchRoots = searchRoots
        self.directoryCatalog = directoryCatalog
        self.runningCatalog = runningCatalog
    }

    public func discover() throws -> [DiscoveredApplication] {
        var applications: [DiscoveredApplication] = []
        var encounteredCatalogFailure = false

        for root in searchRoots {
            do {
                applications.append(contentsOf: try directoryCatalog(root))
            } catch {
                encounteredCatalogFailure = true
            }
        }

        do {
            applications.append(contentsOf: try runningCatalog())
        } catch {
            encounteredCatalogFailure = true
        }

        let uniqueApplications = Self.deduplicated(applications)
        if uniqueApplications.isEmpty, encounteredCatalogFailure {
            throw ApplicationDiscoveryError.catalogUnavailable
        }
        return uniqueApplications
    }

    private static func applications(in root: URL) throws -> [DiscoveredApplication] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw ApplicationDiscoveryError.catalogUnavailable
        }

        var enumerationError: Error?
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            )
        else {
            throw ApplicationDiscoveryError.catalogUnavailable
        }

        var applications: [DiscoveredApplication] = []
        for case let appURL as URL in enumerator where appURL.pathExtension.lowercased() == "app" {
            guard let bundleID = Bundle(url: appURL)?.bundleIdentifier, !bundleID.isEmpty else {
                continue
            }
            applications.append(
                DiscoveredApplication(
                    bundleID: bundleID,
                    name: fileManager.displayName(atPath: appURL.path)
                )
            )
        }
        if enumerationError != nil {
            throw ApplicationDiscoveryError.catalogUnavailable
        }
        return applications
    }

    private static func runningApplications() -> [DiscoveredApplication] {
        NSWorkspace.shared.runningApplications.compactMap { application in
            guard let bundleID = application.bundleIdentifier, !bundleID.isEmpty else {
                return nil
            }
            return DiscoveredApplication(
                bundleID: bundleID,
                name: application.localizedName ?? bundleID
            )
        }
    }

    private static func deduplicated(
        _ applications: [DiscoveredApplication]
    ) -> [DiscoveredApplication] {
        var seen = Set<String>()

        return
            applications
            .filter { seen.insert($0.bundleID.lowercased()).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Loads password-manager bundle IDs and bank domain packs from bundled data
/// Curated local exclusion catalog shipped as package data.
public enum ExclusionCatalog {
    private static let lock = NSLock()
    private static var _passwordManagers: [String]?
    private static var _bankDomains: [String]?

    /// Password manager bundle IDs (lowercase).
    public static var passwordManagerBundleIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        if let c = _passwordManagers { return c }
        let loaded = loadLines(resource: "password-managers", subdirectory: "Data")
        let fallback = [
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.bitwarden.desktop",
            "org.keepassxc.keepassxc",
            "com.apple.passwords",
            "com.apple.keychainaccess",
            "in.sinew.enpass-desktop",
        ]
        let list = loaded.isEmpty ? fallback : loaded
        _passwordManagers = list.map { $0.lowercased() }
        return _passwordManagers!
    }

    /// Bank / neobank / fintech domains (lowercase, no scheme).
    public static var bankDomains: [String] {
        lock.lock()
        defer { lock.unlock() }
        if let c = _bankDomains { return c }
        let loaded = loadLines(resource: "bank-domains", subdirectory: "Data")
        let fallback = [
            "chase.com", "bankofamerica.com", "wellsfargo.com", "citi.com",
            "capitalone.com", "usbank.com", "americanexpress.com",
            "paypal.com", "venmo.com", "wise.com", "revolut.com",
            "monzo.com", "starlingbank.com", "ally.com", "schwab.com",
            "fidelity.com", "vanguard.com", "barclaysus.com", "hsbc.com",
        ]
        let list = loaded.isEmpty ? fallback : loaded
        _bankDomains = list.map { FaviconCache.normalizeDomain($0) }.filter { !$0.isEmpty }
        return _bankDomains!
    }

    /// Password-manager apps that are installed and/or currently running (for seamless UI).
    public static func installedOrRunningPasswordManagers() -> [(bundleID: String, name: String, running: Bool)] {
        let wanted = Set(passwordManagerBundleIDs)
        var byID: [String: (name: String, running: Bool)] = [:]

        // Running first - highest confidence.
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier?.lowercased(), wanted.contains(bid) else { continue }
            let name =
                app.localizedName
                ?? FileManager.default.displayName(atPath: app.bundleURL?.path ?? bid)
            byID[bid] = (name, true)
        }

        // Installed under /Applications and ~/Applications.
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
        let fm = FileManager.default
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in items where name.hasSuffix(".app") {
                let path = (root as NSString).appendingPathComponent(name)
                guard let bid = Bundle(path: path)?.bundleIdentifier?.lowercased(),
                    wanted.contains(bid)
                else { continue }
                if byID[bid] == nil {
                    byID[bid] = (fm.displayName(atPath: path), false)
                }
            }
        }

        // Launch Services lookup for any remaining known IDs.
        for bid in wanted where byID[bid] == nil {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                byID[bid] = (fm.displayName(atPath: url.path), false)
            }
        }

        return
            byID
            .map { (bundleID: $0.key, name: $0.value.name, running: $0.value.running) }
            .sorted { a, b in
                if a.running != b.running { return a.running && !b.running }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    // MARK: - Load

    private static func loadLines(resource: String, subdirectory: String?) -> [String] {
        // Prefer module bundle (SPM / framework), then main bundle.
        let bundles: [Bundle] = [Bundle(for: BundleToken.self), .main]
        for b in bundles {
            if let url = b.url(forResource: resource, withExtension: "txt", subdirectory: subdirectory)
                ?? b.url(forResource: resource, withExtension: "txt", subdirectory: "Exclusions/\(subdirectory ?? "")")
                ?? b.url(forResource: resource, withExtension: "txt")
            {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    return
                        text
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                }
            }
        }
        // Dev fallback: path relative to source tree when running tests from package root.
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Data/\(resource).txt")
        if let text = try? String(contentsOf: dev, encoding: .utf8) {
            return
                text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
        return []
    }
}

/// Anchor type for `Bundle(for:)` resource lookup.
private final class BundleToken: NSObject {}
