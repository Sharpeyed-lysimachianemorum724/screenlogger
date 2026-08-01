import Foundation

/// Relative time windows for search filter chips (today / yesterday / last week).
public enum SearchTimeWindow: String, Sendable, CaseIterable, Codable, Identifiable {
    case all
    case today
    case yesterday
    case lastWeek

    public var id: String { rawValue }

    public var chipLabel: String {
        switch self {
        case .all: return "Any time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .lastWeek: return "Last week"
        }
    }

    /// Whether `timestampMs` falls inside this window relative to `now`.
    public func matches(
        timestampMs: Int64,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            let d = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
            return calendar.isDate(d, inSameDayAs: now)
        case .yesterday:
            let d = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
            guard let y = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
            return calendar.isDate(d, inSameDayAs: y)
        case .lastWeek:
            let d = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
            guard let start = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) else {
                return false
            }
            return d >= start && d <= now
        }
    }
}

/// Pure client-side filters applied to FTS hits (app, domain, session range, time window).
public enum SearchResultFiltering {
    /// Apply optional app / domain / session / time filters to an FTS hit list.
    public static func apply(
        results: [FTSResult],
        appBundleID: String? = nil,
        domain: String? = nil,
        sessionStartMs: Int64? = nil,
        sessionEndMs: Int64? = nil,
        timeWindow: SearchTimeWindow = .all,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [FTSResult] {
        let normalizedDomain: String? = {
            guard let domain, !domain.isEmpty else { return nil }
            let n = FaviconCache.normalizeDomain(domain)
            return n.isEmpty ? nil : n
        }()

        return results.filter { r in
            if let s = sessionStartMs, let e = sessionEndMs {
                if r.timestampMs < s || r.timestampMs > e { return false }
            }
            if !timeWindow.matches(timestampMs: r.timestampMs, now: now, calendar: calendar) {
                return false
            }
            if let app = appBundleID, !app.isEmpty, (r.bundleID ?? "") != app {
                return false
            }
            if let want = normalizedDomain {
                let got = FaviconCache.normalizeDomain(r.domain ?? "")
                if got != want { return false }
            }
            return true
        }
    }

    /// Distinct domains present in `results`, sorted by frequency then name.
    public static func domainChips(from results: [FTSResult]) -> [(domain: String, count: Int)] {
        var counts: [String: Int] = [:]
        for r in results {
            let d = FaviconCache.normalizeDomain(r.domain ?? "")
            guard !d.isEmpty else { continue }
            counts[d, default: 0] += 1
        }
        return
            counts
            .map { (domain: $0.key, count: $0.value) }
            .sorted {
                $0.count > $1.count || ($0.count == $1.count && $0.domain < $1.domain)
            }
    }

    /// Distinct apps present in `results`, sorted by frequency then label.
    public static func appChips(from results: [FTSResult]) -> [(bundleID: String, label: String, count: Int)] {
        var counts: [String: Int] = [:]
        var labels: [String: String] = [:]
        for r in results {
            guard let bid = r.bundleID, !bid.isEmpty else { continue }
            counts[bid, default: 0] += 1
            if labels[bid] == nil, let dn = r.displayName, !dn.isEmpty {
                labels[bid] = dn
            }
        }
        return
            counts
            .map { bid, n in
                let label =
                    labels[bid]
                    ?? bid.split(separator: ".").last.map(String.init)
                    ?? bid
                return (bid, label, n)
            }
            .sorted {
                $0.count > $1.count || ($0.count == $1.count && $0.label < $1.label)
            }
    }
}
