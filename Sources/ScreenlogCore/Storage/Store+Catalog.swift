import Foundation
import SQLite3

extension Store {
    // MARK: - Apps / domains

    public func upsertApplication(bundleID: String?, version: String = "", displayName: String?) throws -> Int64? {
        try withSerializedMutation {
            guard let bundleID, !bundleID.isEmpty else { return nil }
            let ver = version
            let select = try db.prepare(
                "SELECT id FROM application WHERE bundle_id = ? AND version = ? LIMIT 1"
            )
            defer { sqlite3_finalize(select) }
            SQLiteBind.text(select, 1, bundleID)
            SQLiteBind.text(select, 2, ver)
            if sqlite3_step(select) == SQLITE_ROW {
                let id = SQLiteColumn.int64(select, 0)
                if let displayName, !displayName.isEmpty {
                    let upd = try db.prepare(
                        "UPDATE application SET display_name = COALESCE(display_name, ?) WHERE id = ?"
                    )
                    defer { sqlite3_finalize(upd) }
                    SQLiteBind.text(upd, 1, displayName)
                    SQLiteBind.int64(upd, 2, id)
                    _ = sqlite3_step(upd)
                }
                return id
            }
            let ins = try db.prepare(
                "INSERT INTO application(bundle_id, version, display_name) VALUES(?, ?, ?)"
            )
            defer { sqlite3_finalize(ins) }
            SQLiteBind.text(ins, 1, bundleID)
            SQLiteBind.text(ins, 2, ver)
            SQLiteBind.text(ins, 3, displayName)
            if sqlite3_step(ins) != SQLITE_DONE {
                throw SQLiteError.step("insert application failed")
            }
            return db.lastInsertRowID()
        }
    }

    public func upsertDomain(normalized: String?) throws -> Int64? {
        try withSerializedMutation {
            guard let normalized, !normalized.isEmpty else { return nil }
            let lower = normalized.lowercased()
            let select = try db.prepare("SELECT id FROM domain WHERE normalized_domain = ? LIMIT 1")
            defer { sqlite3_finalize(select) }
            SQLiteBind.text(select, 1, lower)
            if sqlite3_step(select) == SQLITE_ROW {
                return SQLiteColumn.int64(select, 0)
            }
            let ins = try db.prepare("INSERT INTO domain(normalized_domain) VALUES(?)")
            defer { sqlite3_finalize(ins) }
            SQLiteBind.text(ins, 1, lower)
            if sqlite3_step(ins) != SQLITE_DONE {
                throw SQLiteError.step("insert domain failed")
            }
            return db.lastInsertRowID()
        }
    }

    public func listApplications() throws -> [ApplicationRow] {
        let stmt = try db.prepare(
            """
            SELECT id, bundle_id, version, display_name, icon_path, is_user_app, dominant_color
            FROM application
            ORDER BY COALESCE(display_name, bundle_id)
            """
        )
        defer { sqlite3_finalize(stmt) }
        var rows: [ApplicationRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let isUser: Bool? = {
                if sqlite3_column_type(stmt, 5) == SQLITE_NULL { return nil }
                return SQLiteColumn.bool(stmt, 5)
            }()
            rows.append(
                ApplicationRow(
                    id: SQLiteColumn.int64(stmt, 0),
                    bundleID: SQLiteColumn.text(stmt, 1) ?? "",
                    version: SQLiteColumn.text(stmt, 2) ?? "",
                    displayName: SQLiteColumn.text(stmt, 3),
                    iconPath: SQLiteColumn.text(stmt, 4),
                    isUserApp: isUser,
                    dominantColor: SQLiteColumn.intOptional(stmt, 6)
                )
            )
        }
        return rows
    }

    public func listDomains() throws -> [DomainRow] {
        let stmt = try db.prepare(
            """
            SELECT id, normalized_domain, common_name, icon_path, dominant_color
            FROM domain
            ORDER BY COALESCE(common_name, normalized_domain)
            """
        )
        defer { sqlite3_finalize(stmt) }
        var rows: [DomainRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(
                DomainRow(
                    id: SQLiteColumn.int64(stmt, 0),
                    normalizedDomain: SQLiteColumn.text(stmt, 1) ?? "",
                    commonName: SQLiteColumn.text(stmt, 2),
                    iconPath: SQLiteColumn.text(stmt, 3),
                    dominantColor: SQLiteColumn.intOptional(stmt, 4)
                )
            )
        }
        return rows
    }

}
