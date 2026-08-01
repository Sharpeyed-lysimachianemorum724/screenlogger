import Foundation
import SQLite3

extension Store {
    // Shared SELECT for TimelineFrame rows (includes FG + BG OCR for Replay panel).
    private static let timelineSelectSQL = """
        f.id,
        f.timestamp,
        f.image_path,
        f.title,
        f.foreground,
        f.background,
        a.bundle_id,
        a.display_name,
        d.normalized_domain,
        s.url,
        CASE WHEN v.status = 0 THEN f.video ELSE NULL END,
        f.video_index,
        f.segment,
        f.width,
        f.height
        """

    private static let timelineJoinSQL = """
        FROM frame f
        LEFT JOIN segment s ON s.id = f.segment
        LEFT JOIN application a ON a.id = s.application
        LEFT JOIN domain d ON d.id = s.domain
        LEFT JOIN video v ON v.id = f.video
        """

    private static func timelineFrame(from stmt: OpaquePointer) -> TimelineFrame {
        TimelineFrame(
            id: SQLiteColumn.int64(stmt, 0),
            timestampMs: SQLiteColumn.int64(stmt, 1),
            imagePath: SQLiteColumn.text(stmt, 2),
            width: SQLiteColumn.intOptional(stmt, 13),
            height: SQLiteColumn.intOptional(stmt, 14),
            title: SQLiteColumn.text(stmt, 3),
            foreground: SQLiteColumn.text(stmt, 4),
            background: SQLiteColumn.text(stmt, 5),
            bundleID: SQLiteColumn.text(stmt, 6),
            displayName: SQLiteColumn.text(stmt, 7),
            domain: SQLiteColumn.text(stmt, 8),
            url: SQLiteColumn.text(stmt, 9),
            segmentID: SQLiteColumn.int64Optional(stmt, 12),
            videoID: SQLiteColumn.int64Optional(stmt, 10),
            videoIndex: SQLiteColumn.intOptional(stmt, 11)
        )
    }

    /// Recent frames joined with app / domain / url for Timeline UI.
    public func recentTimeline(limit: Int = 80) throws -> [TimelineFrame] {
        let sql = """
            SELECT \(Self.timelineSelectSQL)
            \(Self.timelineJoinSQL)
            ORDER BY f.id DESC
            LIMIT ?
            """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        SQLiteBind.int(stmt, 1, limit)
        var rows: [TimelineFrame] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(Self.timelineFrame(from: stmt))
        }
        return rows
    }

    /// Chronological window of frames around a center id (for search to replay).
    public func timelineAround(frameID: Int64, before: Int = 40, after: Int = 40) throws -> [TimelineFrame] {
        let sql = """
            SELECT \(Self.timelineSelectSQL)
            \(Self.timelineJoinSQL)
            WHERE f.id BETWEEN ? AND ?
            ORDER BY f.id ASC
            """
        let lo = max(1, frameID - Int64(before))
        let hi = frameID + Int64(after)
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        SQLiteBind.int64(stmt, 1, lo)
        SQLiteBind.int64(stmt, 2, hi)
        var rows: [TimelineFrame] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(Self.timelineFrame(from: stmt))
        }
        // Fallback: if id gaps (exclusions), load nearest by timestamp from frame row.
        if rows.isEmpty, let center = try frame(id: frameID) {
            return try timelineNear(timestampMs: center.timestampMs, limit: before + after)
        }
        return rows
    }

    public func timelineNear(timestampMs: Int64, limit: Int = 80) throws -> [TimelineFrame] {
        let sql = """
            SELECT \(Self.timelineSelectSQL)
            \(Self.timelineJoinSQL)
            ORDER BY ABS(f.timestamp - ?) ASC
            LIMIT ?
            """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        SQLiteBind.int64(stmt, 1, timestampMs)
        SQLiteBind.int(stmt, 2, limit)
        var rows: [TimelineFrame] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(Self.timelineFrame(from: stmt))
        }
        return rows.sorted { $0.id < $1.id }
    }

    /// Inclusive time-range timeline (`idx_frame_timestamp`) for session browse / scrub windows.
    public func timeline(
        fromTimestampMs startMs: Int64,
        toTimestampMs endMs: Int64,
        limit: Int = 500
    ) throws -> [TimelineFrame] {
        let sql = """
            SELECT \(Self.timelineSelectSQL)
            \(Self.timelineJoinSQL)
            WHERE f.timestamp >= ? AND f.timestamp <= ?
            ORDER BY f.timestamp ASC, f.id ASC
            LIMIT ?
            """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        SQLiteBind.int64(stmt, 1, startMs)
        SQLiteBind.int64(stmt, 2, endMs)
        SQLiteBind.int(stmt, 3, limit)
        var rows: [TimelineFrame] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(Self.timelineFrame(from: stmt))
        }
        return rows
    }

    /// Timeline frames for a contiguous recording block from `sessions(gapMs:)`.
    public func timeline(session: SessionRow, limit: Int = 500) throws -> [TimelineFrame] {
        try timeline(fromTimestampMs: session.startMs, toTimestampMs: session.endMs, limit: limit)
    }

    /// Expand a time window around `centerMs` by `radiusMs` on each side (more context than id-window).
    /// Useful when jumping from Search to Replay and needing surrounding minutes of activity.
    public func timelineExpand(
        aroundTimestampMs centerMs: Int64,
        radiusMs: Int64 = 60_000,
        limit: Int = 200
    ) throws -> [TimelineFrame] {
        let radius = max(0, radiusMs)
        let start = centerMs &- radius  // wrapping subtract avoids crash on underflow
        let end = centerMs &+ radius
        // If center is near 0, clamp start to 0.
        let lo = start > centerMs ? 0 : start
        return try timeline(fromTimestampMs: lo, toTimestampMs: end, limit: limit)
    }

}
