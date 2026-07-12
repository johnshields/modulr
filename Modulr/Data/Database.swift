import Foundation
import SQLite3

/**
 * Database
 * Thin wrapper around libsqlite3 prepared statements: exec / fetchOne / fetchAll
 * over bound parameters. Values bind as String, Int or NULL; rows return as
 * [column: value] dictionaries.
 */
final class Database {
    enum Value {
        case text(String)
        case int(Int)
        case null
    }

    private var handle: OpaquePointer?
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: URL) {
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        sqlite3_open(path.path, &handle)
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA foreign_keys = ON;")
    }

    deinit { sqlite3_close(handle) }

    /// Run one or more statements with no result set.
    @discardableResult
    func exec(_ sql: String, _ params: [Value] = []) -> Bool {
        guard let stmt = prepare(sql, params) else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    /// Run a script of statements separated by ; (schema migration).
    func execScript(_ sql: String) {
        sqlite3_exec(handle, sql, nil, nil, nil)
    }

    func fetchAll(_ sql: String, _ params: [Value] = []) -> [[String: Any]] {
        guard let stmt = prepare(sql, params) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(rowDict(stmt))
        }
        return rows
    }

    func fetchOne(_ sql: String, _ params: [Value] = []) -> [String: Any]? {
        fetchAll(sql, params).first
    }

    func transaction(_ body: () -> Void) {
        execScript("BEGIN;")
        body()
        execScript("COMMIT;")
    }

    private func prepare(_ sql: String, _ params: [Value]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, Self.transient)
            case .int(let n):  sqlite3_bind_int64(stmt, idx, Int64(n))
            case .null:        sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    private func rowDict(_ stmt: OpaquePointer?) -> [String: Any] {
        var out: [String: Any] = [:]
        for c in 0..<sqlite3_column_count(stmt) {
            let name = String(cString: sqlite3_column_name(stmt, c))
            switch sqlite3_column_type(stmt, c) {
            case SQLITE_INTEGER: out[name] = Int(sqlite3_column_int64(stmt, c))
            case SQLITE_NULL:    break
            default:
                if let cs = sqlite3_column_text(stmt, c) { out[name] = String(cString: cs) }
            }
        }
        return out
    }
}
