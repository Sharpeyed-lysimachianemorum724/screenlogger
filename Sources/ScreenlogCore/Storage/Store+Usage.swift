import Foundation
import SQLite3

extension Store {
    // MARK: - Usage

    public func stats() throws -> RecordingStats {
        let stmt = try db.prepare(
            """
            SELECT
                COUNT(*),
                MIN(timestamp),
                MAX(timestamp),
                SUM(CASE WHEN image_path IS NOT NULL THEN 1 ELSE 0 END)
            FROM frame
            """
        )
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return RecordingStats(totalFrames: 0, minTimestampMs: nil, maxTimestampMs: nil, unfinalizedFrames: 0)
        }
        return RecordingStats(
            totalFrames: SQLiteColumn.int64(stmt, 0),
            minTimestampMs: SQLiteColumn.int64Optional(stmt, 1),
            maxTimestampMs: SQLiteColumn.int64Optional(stmt, 2),
            unfinalizedFrames: SQLiteColumn.int64(stmt, 3)
        )
    }

    public func topApplications(limit: Int = 20) throws -> [UsageTopItem] {
        let sql = """
            SELECT a.bundle_id, a.display_name, COUNT(f.id) AS fc
            FROM frame f
            JOIN segment s ON s.id = f.segment
            JOIN application a ON a.id = s.application
            GROUP BY a.bundle_id
            ORDER BY fc DESC
            LIMIT ?
            """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        SQLiteBind.int(stmt, 1, limit)
        var items: [UsageTopItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            items.append(
                UsageTopItem(
                    identifier: SQLiteColumn.text(stmt, 0) ?? "",
                    displayName: SQLiteColumn.text(stmt, 1),
                    frameCount: SQLiteColumn.int64(stmt, 2)
                )
            )
        }
        return items
    }

    public func topDomains(limit: Int = 20) throws -> [UsageTopItem] {
        let sql = """
            SELECT d.normalized_domain, d.common_name, COUNT(f.id) AS fc
            FROM frame f
            JOIN segment s ON s.id = f.segment
            JOIN domain d ON d.id = s.domain
            GROUP BY d.id
            ORDER BY fc DESC
            LIMIT ?
            """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        SQLiteBind.int(stmt, 1, limit)
        var items: [UsageTopItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            items.append(
                UsageTopItem(
                    identifier: SQLiteColumn.text(stmt, 0) ?? "",
                    displayName: SQLiteColumn.text(stmt, 1),
                    frameCount: SQLiteColumn.int64(stmt, 2)
                )
            )
        }
        return items
    }

    /// Sessions = contiguous recording blocks split when gap >= gapMs.
    /// Enriched with primary app (first frame join) and optional still preview path.
    public func sessions(gapMs: Int64 = 5 * 60 * 1000) throws -> [SessionRow] {
        let sql = """
            WITH ordered AS (
                SELECT
                    timestamp,
                    timestamp - LAG(timestamp) OVER (ORDER BY timestamp) AS delta_ms
                FROM frame
            ),
            breaks AS (
                SELECT
                    timestamp,
                    SUM(CASE WHEN delta_ms IS NULL OR delta_ms >= ? THEN 1 ELSE 0 END)
                        OVER (ORDER BY timestamp) AS session_id
                FROM ordered
            ),
            session_bounds AS (
                SELECT
                    MIN(timestamp) AS start_ms,
                    MAX(timestamp) AS end_ms,
                    COUNT(*) AS frame_count
                FROM breaks
                GROUP BY session_id
            )
            SELECT
                sb.start_ms,
                sb.end_ms,
                sb.frame_count,
                (
                    SELECT a.bundle_id
                    FROM frame f
                    LEFT JOIN segment s ON s.id = f.segment
                    LEFT JOIN application a ON a.id = s.application
                    WHERE f.timestamp = sb.start_ms
                    ORDER BY f.id ASC
                    LIMIT 1
                ),
                (
                    SELECT a.display_name
                    FROM frame f
                    LEFT JOIN segment s ON s.id = f.segment
                    LEFT JOIN application a ON a.id = s.application
                    WHERE f.timestamp = sb.start_ms
                    ORDER BY f.id ASC
                    LIMIT 1
                ),
                (
                    SELECT f.image_path
                    FROM frame f
                    WHERE f.timestamp BETWEEN sb.start_ms AND sb.end_ms
                      AND f.image_path IS NOT NULL
                      AND length(f.image_path) > 0
                    ORDER BY f.timestamp ASC
                    LIMIT 1
                )
            FROM session_bounds sb
            ORDER BY sb.start_ms DESC
            """
        let stmt = try db.prepare(sql)
        defer { sqlite3_finalize(stmt) }
        SQLiteBind.int64(stmt, 1, gapMs)
        var rows: [SessionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(
                SessionRow(
                    startMs: SQLiteColumn.int64(stmt, 0),
                    endMs: SQLiteColumn.int64(stmt, 1),
                    frameCount: SQLiteColumn.int64(stmt, 2),
                    primaryBundleID: SQLiteColumn.text(stmt, 3),
                    primaryDisplayName: SQLiteColumn.text(stmt, 4),
                    previewImagePath: SQLiteColumn.text(stmt, 5)
                )
            )
        }
        return rows
    }

}
