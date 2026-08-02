import Foundation

/// Pure helpers for session day grouping and summary labels.
/// Persistence of pin keys lives in `SessionPinStore` (`"startMs-endMs"` under
/// `SessionPinStore.defaultsKey` / `"screenlog.pinnedSessions"`).
public enum SessionPinning: Sendable {
    /// Stable pin / identity key for a session range (`"startMs-endMs"`).
    public static func pinKey(startMs: Int64, endMs: Int64) -> String {
        SessionPinStore.pinID(startMs: startMs, endMs: endMs)
    }

    public static func pinKey(for session: SessionRow) -> String {
        SessionPinStore.pinID(for: session)
    }

    /// Parse `"startMs-endMs"`.
    public static func parsePinKey(_ key: String) -> (startMs: Int64, endMs: Int64)? {
        guard let dash = key.firstIndex(of: "-") else { return nil }
        let startPart = key[..<dash]
        let endPart = key[key.index(after: dash)...]
        guard let startMs = Int64(startPart), let endMs = Int64(endPart) else { return nil }
        return (startMs, endMs)
    }

    /// Whether a persisted key identifies this logical session.
    ///
    /// A live session's end timestamp grows after every capture. Treating the
    /// complete range as its identity made pins disappear while recording was
    /// still in progress. The start timestamp is stable for the lifetime of a
    /// session, while accepting the historic `start-end` format keeps existing
    /// preferences compatible.
    public static func isPinned(_ session: SessionRow, in pinnedKeys: Set<String>) -> Bool {
        pinnedKeys.contains { key in
            parsePinKey(key)?.startMs == session.startMs
        }
    }

    public struct DayGroup: Sendable, Equatable, Identifiable {
        public var label: String
        public var dayStartMs: Int64
        public var sessions: [SessionRow]

        public var id: String { "\(label)-\(dayStartMs)" }

        public init(label: String, dayStartMs: Int64, sessions: [SessionRow]) {
            self.label = label
            self.dayStartMs = dayStartMs
            self.sessions = sessions
        }
    }

    /// Group already-ordered sessions by calendar day of `startMs`.
    public static func groupByDay(
        _ sessions: [SessionRow],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayGroup] {
        var groups: [DayGroup] = []
        var currentLabel: String?
        var currentDayStart: Int64 = 0
        var bucket: [SessionRow] = []

        for session in sessions {
            let label = dayLabel(session.startMs, now: now, calendar: calendar)
            if label != currentLabel {
                if let currentLabel, !bucket.isEmpty {
                    groups.append(DayGroup(label: currentLabel, dayStartMs: currentDayStart, sessions: bucket))
                }
                currentLabel = label
                currentDayStart = session.startMs
                bucket = [session]
            } else {
                bucket.append(session)
            }
        }
        if let currentLabel, !bucket.isEmpty {
            groups.append(DayGroup(label: currentLabel, dayStartMs: currentDayStart, sessions: bucket))
        }
        return groups
    }

    /// Pinned sessions first (global), then day-grouped unpinned remainder.
    public static func sections(
        _ sessions: [SessionRow],
        pinnedKeys: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (pinned: [SessionRow], dayGroups: [DayGroup]) {
        let pinned = sessions.filter { isPinned($0, in: pinnedKeys) }
        let unpinned = sessions.filter { !isPinned($0, in: pinnedKeys) }
        return (pinned, groupByDay(unpinned, now: now, calendar: calendar))
    }

    public static func dayLabel(
        _ timestampMs: Int64,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        if calendar.isDate(d, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(d, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    /// Human duration and frame count for session rows.
    public static func summaryLabel(startMs: Int64, endMs: Int64, frameCount: Int64) -> String {
        let durationSec = max(0, (endMs - startMs) / 1000)
        let frames = "\(frameCount) moment\(frameCount == 1 ? "" : "s")"
        if durationSec <= 0 {
            return frames
        }
        if durationSec < 60 {
            return "\(durationSec)s, \(frames)"
        }
        let minutes = durationSec / 60
        if minutes < 60 {
            let rem = durationSec % 60
            if rem == 0 { return "\(minutes)m, \(frames)" }
            return "\(minutes)m \(rem)s, \(frames)"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if remMin == 0 { return "\(hours)h, \(frames)" }
        return "\(hours)h \(remMin)m, \(frames)"
    }

    public static func summaryLabel(for session: SessionRow) -> String {
        summaryLabel(startMs: session.startMs, endMs: session.endMs, frameCount: session.frameCount)
    }
}
