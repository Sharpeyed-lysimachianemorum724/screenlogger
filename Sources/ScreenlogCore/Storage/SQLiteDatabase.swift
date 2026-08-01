import Foundation
import SQLite3

public enum SQLiteError: Error, CustomStringConvertible, Sendable {
    case open(String)
    case exec(String)
    case prepare(String)
    case step(String)
    case bind(String)
    case notFound

    public var description: String {
        switch self {
        case .open(let m), .exec(let m), .prepare(let m), .step(let m), .bind(let m):
            return m
        case .notFound:
            return "row not found"
        }
    }
}

public struct SQLiteForeignKeyViolation: Equatable, Sendable {
    public let table: String
    public let rowID: Int64?
    public let parentTable: String
    public let constraintIndex: Int64
}

public struct SQLiteReadOnlyValidation: Equatable, Sendable {
    public let schemaVersion: Int
    public let integrityFailures: [String]
    public let foreignKeyViolationCount: Int

    public var isValid: Bool {
        integrityFailures.isEmpty && foreignKeyViolationCount == 0
    }
}

/// Thin SQLite3 wrapper used by Screenlogger (no GRDB dependency).
public final class SQLiteDatabase: @unchecked Sendable {
    public private(set) var db: OpaquePointer?
    public let path: String
    /// Recursive because transactions call `exec`, and Store mutation helpers
    /// may compose inside maintenance transactions.
    private let mutationExecutor = NSRecursiveLock()

    public init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError.open("Failed to open \(path): \(msg)")
        }
        db = handle
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA synchronous = NORMAL;")
        try exec("PRAGMA busy_timeout = 5000;")
        try exec("PRAGMA foreign_keys = ON;")
        // Performance: larger page cache + mmap for timeline/FTS scans (local SSD typical).
        try exec("PRAGMA cache_size = -20000;")  // ~20MB
        try exec("PRAGMA temp_store = MEMORY;")
        try exec("PRAGMA mmap_size = 268435456;")  // 256MB
        try exec("PRAGMA recursive_triggers = ON;")
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    /// Close the connection deterministically before a coordinated Library
    /// replacement. Callers must first stop every operation that can prepare a
    /// statement or use this connection.
    public func close() throws {
        try withExclusiveMutation {
            guard let handle = db else { return }
            let result = sqlite3_close(handle)
            guard result == SQLITE_OK else {
                throw SQLiteError.exec("Failed to close database: \(String(cString: sqlite3_errmsg(handle)))")
            }
            db = nil
        }
    }

    /// Execute a complete logical mutation while excluding every other writer
    /// using this database connection.
    public func withExclusiveMutation<T>(_ body: () throws -> T) rethrows -> T {
        mutationExecutor.lock()
        defer { mutationExecutor.unlock() }
        return try body()
    }

    public func exec(_ sql: String) throws {
        try withExclusiveMutation {
            var err: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, sql, nil, nil, &err)
            if rc != SQLITE_OK {
                let message = err.map { String(cString: $0) } ?? "sqlite error \(rc)"
                sqlite3_free(err)
                throw SQLiteError.exec(message)
            }
        }
    }

    public func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(db)))
        }
        return stmt!
    }

    public func lastInsertRowID() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    public func changes() -> Int32 {
        sqlite3_changes(db)
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try withExclusiveMutation {
            try exec("BEGIN IMMEDIATE;")
            do {
                let value = try body()
                try exec("COMMIT;")
                return value
            } catch {
                try? exec("ROLLBACK;")
                throw error
            }
        }
    }

    /// Create a consistent standalone database without copying WAL/SHM files.
    /// Callers that also snapshot managed media must hold Store's serialized
    /// mutation executor across this backup and the corresponding file copies.
    public func backup(to destination: URL) throws {
        try withExclusiveMutation {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw SQLiteError.exec("Backup destination already exists: \(destination.path)")
            }
            var destinationHandle: OpaquePointer?
            let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2(destination.path, &destinationHandle, flags, nil) == SQLITE_OK,
                let destinationHandle
            else {
                let message = destinationHandle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
                if let destinationHandle { sqlite3_close(destinationHandle) }
                throw SQLiteError.open("Failed to create backup database: \(message)")
            }
            defer {
                sqlite3_close(destinationHandle)
                // A read of a WAL-mode header can create an empty shared-memory
                // coordination pair. The online backup has already materialized
                // every committed page in the main file; these new sidecars
                // carry no database content and are never archive data.
                try? FileManager.default.removeItem(atPath: destination.path + "-shm")
                try? FileManager.default.removeItem(atPath: destination.path + "-wal")
            }
            guard let backup = sqlite3_backup_init(destinationHandle, "main", db, "main") else {
                throw SQLiteError.exec("Failed to initialize SQLite backup: \(String(cString: sqlite3_errmsg(destinationHandle)))")
            }
            let stepResult = sqlite3_backup_step(backup, -1)
            let finishResult = sqlite3_backup_finish(backup)
            guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
                throw SQLiteError.exec("SQLite backup failed (step \(stepResult), finish \(finishResult))")
            }
            func schemaVersion(_ handle: OpaquePointer?) throws -> Int {
                var statement: OpaquePointer?
                guard
                    sqlite3_prepare_v2(
                        handle,
                        "SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
                        -1,
                        &statement,
                        nil
                    ) == SQLITE_OK,
                    let statement
                else {
                    throw SQLiteError.prepare("Could not inspect backup schema version")
                }
                defer { sqlite3_finalize(statement) }
                guard sqlite3_step(statement) == SQLITE_ROW else {
                    throw SQLiteError.step("Could not read backup schema version")
                }
                return Int(sqlite3_column_int64(statement, 0))
            }
            let sourceVersion = try schemaVersion(db)
            let copiedVersion = try schemaVersion(destinationHandle)
            guard copiedVersion == sourceVersion else {
                throw SQLiteError.exec(
                    "SQLite backup schema version mismatch (source \(sourceVersion), copy \(copiedVersion))"
                )
            }
        }
    }

    /// Validate an export candidate without opening it read/write or creating
    /// journal sidecars.
    public static func validateReadOnly(at databaseURL: URL) throws -> SQLiteReadOnlyValidation {
        var handle: OpaquePointer?
        // Backup copies can retain WAL mode in the database header even though
        // the online backup API has already materialized every committed page
        // into the standalone file. Immutable URI mode prevents a read-only
        // verifier from trying to create unnecessary WAL/SHM sidecars.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI
        let immutableURI = databaseURL.absoluteString + "?mode=ro&immutable=1"
        guard sqlite3_open_v2(immutableURI, &handle, flags, nil) == SQLITE_OK,
            let handle
        else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle { sqlite3_close(handle) }
            throw SQLiteError.open("Failed to open backup database read-only: \(message)")
        }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 5_000)

        func integerScalar(_ sql: String) throws -> Int {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
                let statement
            else {
                throw SQLiteError.prepare(String(cString: sqlite3_errmsg(handle)))
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw SQLiteError.step("Read-only validation query returned no row: \(sql)")
            }
            return Int(sqlite3_column_int64(statement, 0))
        }

        var quickCheck: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA quick_check(100)", -1, &quickCheck, nil) == SQLITE_OK,
            let quickCheck
        else {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(quickCheck) }
        var integrityFailures: [String] = []
        var sawOK = false
        var step = sqlite3_step(quickCheck)
        while step == SQLITE_ROW {
            let message = sqlite3_column_text(quickCheck, 0).map { String(cString: $0) } ?? ""
            if message == "ok" { sawOK = true } else { integrityFailures.append(message.isEmpty ? "empty quick_check result" : message) }
            step = sqlite3_step(quickCheck)
        }
        guard step == SQLITE_DONE else {
            throw SQLiteError.step("Read-only quick_check failed")
        }
        if integrityFailures.isEmpty, !sawOK { integrityFailures.append("quick_check returned no result") }

        var foreignKeys: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA foreign_key_check", -1, &foreignKeys, nil) == SQLITE_OK,
            let foreignKeys
        else {
            throw SQLiteError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(foreignKeys) }
        var violationCount = 0
        step = sqlite3_step(foreignKeys)
        while step == SQLITE_ROW {
            violationCount += 1
            step = sqlite3_step(foreignKeys)
        }
        guard step == SQLITE_DONE else { throw SQLiteError.step("Read-only foreign-key check failed") }

        return SQLiteReadOnlyValidation(
            schemaVersion: try integerScalar(
                "SELECT COALESCE(MAX(version), 0) FROM schema_migrations"
            ),
            integrityFailures: integrityFailures,
            foreignKeyViolationCount: violationCount
        )
    }

    /// Returns every non-`ok` result from SQLite's bounded startup check.
    public func quickCheckFailures() throws -> [String] {
        try withExclusiveMutation {
            let stmt = try prepare("PRAGMA quick_check(100)")
            defer { sqlite3_finalize(stmt) }
            var failures: [String] = []
            var sawSuccess = false
            var result = sqlite3_step(stmt)
            while result == SQLITE_ROW {
                guard let message = SQLiteColumn.text(stmt, 0) else {
                    failures.append("quick_check returned an empty result")
                    result = sqlite3_step(stmt)
                    continue
                }
                if message == "ok" {
                    sawSuccess = true
                    result = sqlite3_step(stmt)
                    continue
                }
                failures.append(message)
                result = sqlite3_step(stmt)
            }
            guard result == SQLITE_DONE else {
                throw SQLiteError.step("quick_check failed while reading results")
            }
            if failures.isEmpty, !sawSuccess {
                failures.append("quick_check returned no result")
            }
            return failures
        }
    }

    /// Foreign-key validation is separate from `quick_check` in SQLite.
    public func foreignKeyViolations() throws -> [SQLiteForeignKeyViolation] {
        try withExclusiveMutation {
            let stmt = try prepare("PRAGMA foreign_key_check")
            defer { sqlite3_finalize(stmt) }
            var violations: [SQLiteForeignKeyViolation] = []
            var result = sqlite3_step(stmt)
            while result == SQLITE_ROW {
                violations.append(
                    SQLiteForeignKeyViolation(
                        table: SQLiteColumn.text(stmt, 0) ?? "unknown",
                        rowID: SQLiteColumn.int64Optional(stmt, 1),
                        parentTable: SQLiteColumn.text(stmt, 2) ?? "unknown",
                        constraintIndex: SQLiteColumn.int64(stmt, 3)
                    )
                )
                result = sqlite3_step(stmt)
            }
            guard result == SQLITE_DONE else {
                throw SQLiteError.step("foreign_key_check failed while reading results")
            }
            return violations
        }
    }
}

// MARK: - Statement helpers

public enum SQLiteBind {
    public static func text(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    public static func int64(_ stmt: OpaquePointer, _ index: Int32, _ value: Int64?) {
        if let value {
            sqlite3_bind_int64(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    public static func int(_ stmt: OpaquePointer, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    public static func bool(_ stmt: OpaquePointer, _ index: Int32, _ value: Bool) {
        sqlite3_bind_int(stmt, index, value ? 1 : 0)
    }

    public static func double(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    public static func blob(_ stmt: OpaquePointer, _ index: Int32, _ value: Data?) {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        value.withUnsafeBytes { raw in
            let ptr = raw.baseAddress
            // SQLITE_TRANSIENT: copy blob bytes so Data lifetime is independent of the bind.
            sqlite3_bind_blob(stmt, index, ptr, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }
}

public enum SQLiteColumn {
    public static func text(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    public static func int64(_ stmt: OpaquePointer, _ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    public static func int64Optional(_ stmt: OpaquePointer, _ index: Int32) -> Int64? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, index)
    }

    public static func intOptional(_ stmt: OpaquePointer, _ index: Int32) -> Int? {
        int64Optional(stmt, index).map { Int($0) }
    }

    public static func bool(_ stmt: OpaquePointer, _ index: Int32) -> Bool {
        sqlite3_column_int(stmt, index) != 0
    }

    public static func doubleOptional(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return sqlite3_column_double(stmt, index)
    }

    public static func data(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0, let ptr = sqlite3_column_blob(stmt, index) else {
            return Data()
        }
        return Data(bytes: ptr, count: count)
    }
}
