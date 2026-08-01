import AppKit
import Foundation
import OSLog
import os

private let faviconLog = Logger(subsystem: "dev.screenlog", category: "favicon")

/// Disk + memory cache for website favicons.
/// Fetches use a public favicon endpoint; failures never throw to callers - use
/// `placeholder(for:)` instead.
public final class FaviconCache: @unchecked Sendable {
    public static let shared = FaviconCache(preferences: ScreenlogProcessPreferences.current)

    private struct State: Sendable {
        var cacheDirectory: URL
        var negativeDomains = Set<String>()
        var airgapMode: Bool
        var remoteFetchingEnabled: Bool
    }

    private let memory = NSCache<NSString, NSImage>()
    private let ioQueue = DispatchQueue(label: "dev.screenlog.favicon", qos: .utility)
    private let session: URLSession
    private let state: OSAllocatedUnfairLock<State>

    /// When true, never hit the network (Airgap Mode). Memory/disk cache still works.
    public var airgapMode: Bool {
        get { state.withLock { $0.airgapMode } }
        set { state.withLock { $0.airgapMode = newValue } }
    }

    /// Whether misses may send a domain to the public icon provider. This is
    /// deliberately opt-in because domains can disclose browsing activity.
    public var remoteFetchingEnabled: Bool {
        get { state.withLock { $0.remoteFetchingEnabled } }
        set { state.withLock { $0.remoteFetchingEnabled = newValue } }
    }

    public init(
        cacheDirectory: URL? = nil,
        session: URLSession = .shared,
        airgapMode: Bool? = nil,
        remoteFetchingEnabled: Bool? = nil,
        preferences: UserDefaults = .standard
    ) {
        let resolvedDirectory =
            cacheDirectory
            ?? ScreenlogPaths.resolvedRoot().appendingPathComponent("favicon-cache", isDirectory: true)
        let resolvedAirgap =
            airgapMode
            ?? preferences.bool(forKey: ProductPreferenceKey.airgapMode)
        let resolvedRemoteFetching =
            remoteFetchingEnabled
            ?? preferences.bool(forKey: ProductPreferenceKey.remoteFaviconsEnabled)

        self.session = session
        self.state = OSAllocatedUnfairLock(
            initialState: State(
                cacheDirectory: resolvedDirectory,
                airgapMode: resolvedAirgap,
                remoteFetchingEnabled: resolvedRemoteFetching
            )
        )
        memory.countLimit = 256
        try? FileManager.default.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
    }

    /// Point cache at a specific directory (tests / alternate data roots).
    public func reconfigure(cacheDirectory: URL) {
        state.withLock {
            $0.cacheDirectory = cacheDirectory
            $0.negativeDomains.removeAll()
        }
        memory.removeAllObjects()
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Normalize a domain or URL-ish string into a favicon host key.
    public static func normalizeDomain(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return "" }
        if s.contains("://"), let host = URL(string: s)?.host {
            s = host.lowercased()
        } else if s.hasPrefix("www.") {
            s = String(s.dropFirst(4))
        }
        // Strip path/query if user pasted a host/path.
        if let slash = s.firstIndex(of: "/") {
            s = String(s[..<slash])
        }
        if let q = s.firstIndex(of: "?") {
            s = String(s[..<q])
        }
        if s.hasPrefix("www.") {
            s = String(s.dropFirst(4))
        }
        return s
    }

    /// Synchronous memory/disk lookup (no network).
    public func cachedImage(for domain: String) -> NSImage? {
        let key = Self.normalizeDomain(domain)
        guard !key.isEmpty else { return nil }
        if let mem = memory.object(forKey: key as NSString) {
            return mem
        }
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path),
            let img = NSImage(contentsOf: url)
        else {
            return nil
        }
        memory.setObject(img, forKey: key as NSString)
        return img
    }

    /// Letter/placeholder so UI never blocks on network.
    public func placeholder(for domain: String, size: CGFloat = 16) -> NSImage {
        let key = Self.normalizeDomain(domain)
        let letter: String
        if let first = key.first {
            letter = String(first).uppercased()
        } else {
            letter = "?"
        }
        let dim = max(12, size)
        let image = NSImage(size: NSSize(width: dim, height: dim), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: dim * 0.22, yRadius: dim * 0.22)
            NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
            path.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: dim * 0.55, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            let str = NSString(string: letter)
            let textSize = str.size(withAttributes: attrs)
            let origin = NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            )
            str.draw(at: origin, withAttributes: attrs)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Resolve image: memory to disk to network (async). Never throws.
    public func image(for domain: String) async -> NSImage {
        let key = Self.normalizeDomain(domain)
        guard !key.isEmpty else { return placeholder(for: domain) }
        if let cached = cachedImage(for: key) {
            return cached
        }
        let skipNetwork = state.withLock {
            $0.airgapMode || !$0.remoteFetchingEnabled || $0.negativeDomains.contains(key)
        }
        if skipNetwork {
            return placeholder(for: key)
        }
        if let fetched = await fetch(domain: key) {
            store(image: fetched, domain: key)
            return fetched
        }
        _ = state.withLock { $0.negativeDomains.insert(key) }
        return placeholder(for: key)
    }

    /// Warm cache for many domains (search chips). Skips network in airgap mode.
    public func prefetch(domains: [String]) async {
        let unique = Array(Set(domains.map { Self.normalizeDomain($0) }.filter { !$0.isEmpty }))
        await withTaskGroup(of: Void.self) { group in
            for d in unique.prefix(40) {
                group.addTask { _ = await self.image(for: d) }
            }
        }
    }

    /// Seed cache from raw image bytes (unit tests / offline fixtures).
    @discardableResult
    public func store(data: Data, domain: String) -> NSImage? {
        let key = Self.normalizeDomain(domain)
        guard !key.isEmpty, let img = NSImage(data: data) else { return nil }
        store(image: img, domain: key)
        return img
    }

    // MARK: - Private

    private func fileURL(for normalizedDomain: String) -> URL {
        // Avoid path injection; keep host-looking characters only.
        let safe =
            normalizedDomain
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let directory = state.withLock { $0.cacheDirectory }
        return directory.appendingPathComponent("\(safe).png")
    }

    private func store(image: NSImage, domain: String) {
        memory.setObject(image, forKey: domain as NSString)
        let url = fileURL(for: domain)
        ioQueue.async {
            guard let tiff = image.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            else {
                return
            }
            let fileManager = FileManager()
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? png.write(to: url, options: .atomic)
        }
    }

    private func fetch(domain: String) async -> NSImage? {
        // Defense in depth: re-check immediately before creating the request.
        let networkAllowed = state.withLock { !$0.airgapMode && $0.remoteFetchingEnabled }
        if !networkAllowed { return nil }
        // DuckDuckGo IP3 icons provide a small, cacheable public endpoint.
        guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(domain).ico") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                faviconLog.debug("favicon HTTP \(http.statusCode) for \(domain, privacy: .private(mask: .hash))")
                return nil
            }
            guard !data.isEmpty, let img = NSImage(data: data), img.size.width > 0 else {
                return nil
            }
            return img
        } catch {
            faviconLog.debug(
                "favicon fetch failed \(domain, privacy: .private(mask: .hash)): \(error.localizedDescription, privacy: .private(mask: .hash))"
            )
            return nil
        }
    }
}
