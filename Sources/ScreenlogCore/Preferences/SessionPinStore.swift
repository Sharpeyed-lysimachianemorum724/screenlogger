import Foundation

/// Persists pinned recording sessions. Existing values use a start/end key,
/// but matching is intentionally based on the stable start timestamp because
/// an active session's end timestamp continues to move.
/// Pure UserDefaults-backed store - unit-testable without UI.
public final class SessionPinStore: @unchecked Sendable {
    public static let shared = SessionPinStore()

    public static let defaultsKey = "screenlog.pinnedSessions"

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = SessionPinStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Stable id for a session window.
    public static func pinID(startMs: Int64, endMs: Int64) -> String {
        "\(startMs)-\(endMs)"
    }

    public static func pinID(for session: SessionRow) -> String {
        pinID(startMs: session.startMs, endMs: session.endMs)
    }

    public func isPinned(startMs: Int64, endMs: Int64) -> Bool {
        pinnedIDs().contains { id in
            SessionPinning.parsePinKey(id)?.startMs == startMs
        }
    }

    public func isPinned(_ session: SessionRow) -> Bool {
        isPinned(startMs: session.startMs, endMs: session.endMs)
    }

    public func setPinned(_ session: SessionRow, pinned: Bool) {
        setPinned(startMs: session.startMs, endMs: session.endMs, pinned: pinned)
    }

    public func setPinned(startMs: Int64, endMs: Int64, pinned: Bool) {
        lock.lock()
        defer { lock.unlock() }
        var ids = Set(defaults.stringArray(forKey: key) ?? [])
        let id = Self.pinID(startMs: startMs, endMs: endMs)
        // Replace an older range for this logical session. This both keeps the
        // preference set bounded and migrates a growing live session forward.
        ids = Set(
            ids.filter { existing in
                SessionPinning.parsePinKey(existing)?.startMs != startMs
            })
        if pinned {
            ids.insert(id)
        }
        defaults.set(Array(ids).sorted(), forKey: key)
    }

    public func toggle(_ session: SessionRow) -> Bool {
        let now = !isPinned(session)
        setPinned(session, pinned: now)
        return now
    }

    public func pinnedIDs() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Sort sessions: pinned first, then by startMs descending.
    public func sortedSessions(_ sessions: [SessionRow]) -> [SessionRow] {
        let pins = pinnedIDs()
        return sessions.sorted { a, b in
            let ap = SessionPinning.isPinned(a, in: pins)
            let bp = SessionPinning.isPinned(b, in: pins)
            if ap != bp { return ap && !bp }
            return a.startMs > b.startMs
        }
    }
}

// MARK: - Recent search queries

/// Last-N free-text search queries for empty-state chips.
public final class RecentSearchStore: @unchecked Sendable {
    public static let shared = RecentSearchStore()
    public static let defaultsKey = "screenlog.recentSearchQueries"
    public static let maxCount = 8

    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, key: String = RecentSearchStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func all() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return defaults.stringArray(forKey: key) ?? []
    }

    public func record(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        lock.lock()
        defer { lock.unlock() }
        var list = defaults.stringArray(forKey: key) ?? []
        list.removeAll { $0.caseInsensitiveCompare(q) == .orderedSame }
        list.insert(q, at: 0)
        if list.count > Self.maxCount {
            list = Array(list.prefix(Self.maxCount))
        }
        defaults.set(list, forKey: key)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}
