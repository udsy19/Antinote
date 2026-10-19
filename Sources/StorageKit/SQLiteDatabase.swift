import Foundation
import SQLite3

public struct StorageError: LocalizedError {
    public enum Kind {
        /// The file isn't a readable SQLite database any more (`SQLITE_CORRUPT`, `SQLITE_NOTADB`, a failed
        /// `quick_check`): the store moves it aside and recovers from a backup.
        case damaged
        /// `user_version` is ahead of this build's schema (the app was downgraded after an update).
        case newerVersion
        /// Anything else: permissions, a full disk, a locked file. The file is left exactly as it is.
        case other
    }
    public let message: String
    public var kind: Kind = .other
    public var errorDescription: String? { message }
}

/// A bindable SQLite value.
enum SQLValue {
    case null, int(Int64), double(Double), text(String)
}

/// Minimal wrapper over one SQLite connection (system SQLite3 C API).
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL, readOnly: Bool = false) throws {
        var db: OpaquePointer?
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw StorageError(message: "Could not open \(url.lastPathComponent): \(msg)")
        }
        handle = db
        sqlite3_busy_timeout(db, 3000)
    }

    deinit { close() }

    func close() {
        guard let handle else { return }
        sqlite3_close_v2(handle)
        self.handle = nil
    }

    private var lastError: String { handle.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed" }

    /// The last error as a `StorageError`, flagged `.damaged` when SQLite found the file itself unreadable.
    private func error(_ sql: String) -> StorageError {
        let code = handle.map { sqlite3_errcode($0) & 0xFF } ?? SQLITE_ERROR
        let damaged = code == SQLITE_CORRUPT || code == SQLITE_NOTADB
        return StorageError(message: "\(lastError) — \(sql.prefix(80))", kind: damaged ? .damaged : .other)
    }

    /// Runs one or more statements without results.
    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw error(sql) }
    }

    /// Runs one statement with bound parameters.
    func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw error(sql) }
    }

    /// Runs a query and maps each row.
    func query<T>(_ sql: String, _ params: [SQLValue] = [], _ map: (Row) throws -> T) throws -> [T] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw error(sql) }
            out.append(try map(Row(stmt: stmt!)))
        }
        return out
    }

    func scalarInt(_ sql: String) throws -> Int {
        try query(sql) { $0.int(0) }.first ?? 0
    }

    var userVersion: Int { (try? scalarInt("PRAGMA user_version")) ?? 0 }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") } catch { try? execute("ROLLBACK"); throw error }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw error(sql) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            // The byte count, not -1: a pasted NUL would otherwise end the text early (silent truncation).
            case .text(let v): sqlite3_bind_text(stmt, idx, v, Int32(v.utf8.count), transient)
            }
        }
        return stmt
    }

    struct Row {
        let stmt: OpaquePointer
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        /// Read by length so an embedded NUL comes back too.
        func text(_ i: Int32) -> String {
            guard let bytes = sqlite3_column_text(stmt, i) else { return "" }
            let count = Int(sqlite3_column_bytes(stmt, i))
            return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
        }
    }
}

extension SQLValue {
    static func date(_ d: Date?) -> SQLValue { d.map { .double($0.timeIntervalSinceReferenceDate) } ?? .null }
    static func bool(_ b: Bool) -> SQLValue { .int(b ? 1 : 0) }
    static func optInt(_ i: Int?) -> SQLValue { i.map { .int(Int64($0)) } ?? .null }
}
