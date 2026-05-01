import Foundation
import SQLite3

actor Database {
    private var db: OpaquePointer?

    static let shared = Database()

    private init() {}

    func open() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("ScreenPilot", isDirectory: true)

        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        let dbPath = dbDir.appendingPathComponent("screenpilot.db").path

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw DatabaseError.openFailed(String(cString: sqlite3_errmsg(db)))
        }

        try createTables()
    }

    func close() {
        if let db {
            sqlite3_close(db)
        }
        db = nil
    }

    // MARK: - Schema

    private func createTables() throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS activity_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                app_name TEXT NOT NULL,
                bundle_id TEXT,
                window_title TEXT,
                activity_summary TEXT NOT NULL,
                created_at TEXT DEFAULT (datetime('now'))
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_activity_timestamp ON activity_log(timestamp)",
            "CREATE INDEX IF NOT EXISTS idx_activity_app ON activity_log(app_name)",
            """
            CREATE TABLE IF NOT EXISTS nudges (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                type TEXT NOT NULL,
                title TEXT NOT NULL,
                body TEXT NOT NULL,
                activity_summary TEXT,
                feedback TEXT,
                is_read INTEGER DEFAULT 0,
                created_at TEXT DEFAULT (datetime('now'))
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_nudges_timestamp ON nudges(timestamp)",
            """
            CREATE TABLE IF NOT EXISTS capture_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                decision TEXT NOT NULL,
                app_name TEXT,
                diff_score REAL,
                created_at TEXT DEFAULT (datetime('now'))
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """,
        ]

        for sql in statements {
            try execute(sql)
        }

        try createMemoryTable()
    }

    private func createMemoryTable() throws {
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
                type,
                app,
                title,
                content,
                timestamp UNINDEXED,
                feedback UNINDEXED
            )
        """)
    }

    // MARK: - Execute

    func execute(_ sql: String) throws {
        guard let db else { throw DatabaseError.notOpen }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw DatabaseError.executionFailed(message)
        }
    }

    // MARK: - Activity Log

    func insertActivity(_ entry: ActivityEntry) throws {
        guard let db else { throw DatabaseError.notOpen }

        let sql = "INSERT INTO activity_log (timestamp, app_name, bundle_id, window_title, activity_summary) VALUES (?, ?, ?, ?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
        sqlite3_bind_text(stmt, 1, (timestamp as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (entry.app as NSString).utf8String, -1, nil)
        if let bundleId = entry.bundleId {
            sqlite3_bind_text(stmt, 3, (bundleId as NSString).utf8String, -1, nil)
        }
        if let windowTitle = entry.windowTitle {
            sqlite3_bind_text(stmt, 4, (windowTitle as NSString).utf8String, -1, nil)
        }
        sqlite3_bind_text(stmt, 5, (entry.summary as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Nudges

    func insertNudge(_ nudge: Nudge) throws -> Int64 {
        guard let db else { throw DatabaseError.notOpen }

        let sql = "INSERT INTO nudges (timestamp, type, title, body, activity_summary) VALUES (?, ?, ?, ?, ?)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let timestamp = ISO8601DateFormatter().string(from: nudge.timestamp)
        sqlite3_bind_text(stmt, 1, (timestamp as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (nudge.type.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (nudge.title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (nudge.body as NSString).utf8String, -1, nil)
        if let summary = nudge.activitySummary {
            sqlite3_bind_text(stmt, 5, (summary as NSString).utf8String, -1, nil)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }

        return sqlite3_last_insert_rowid(db)
    }

    func updateFeedback(nudgeId: Int64, feedback: Nudge.Feedback) throws {
        try execute("UPDATE nudges SET feedback = '\(feedback.rawValue)' WHERE id = \(nudgeId)")
    }

    func markNudgeRead(nudgeId: Int64) throws {
        try execute("UPDATE nudges SET is_read = 1 WHERE id = \(nudgeId)")
    }

    // MARK: - Retention

    func deleteOldRecords() throws {
        try execute("DELETE FROM activity_log WHERE created_at < datetime('now', '-30 days')")
        try execute("DELETE FROM capture_log WHERE created_at < datetime('now', '-30 days')")
        try execute("DELETE FROM nudges WHERE created_at < datetime('now', '-90 days')")
    }

    // MARK: - Memory FTS

    struct MemoryRecord {
        let type: String
        let app: String
        let title: String
        let content: String
        let timestamp: String
        let feedback: String?
        let rank: Double
    }

    func insertMemory(type: String, app: String, title: String, content: String, timestamp: Date, feedback: String? = nil) throws {
        guard let db else { throw DatabaseError.notOpen }

        let sql = "INSERT INTO memory_fts (type, app, title, content, timestamp, feedback) VALUES (?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let ts = ISO8601DateFormatter().string(from: timestamp)
        sqlite3_bind_text(stmt, 1, (type as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (app as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (ts as NSString).utf8String, -1, nil)
        if let feedback {
            sqlite3_bind_text(stmt, 6, (feedback as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func searchMemory(query: String, limit: Int = 5) throws -> [MemoryRecord] {
        guard let db else { throw DatabaseError.notOpen }

        let sql = """
            SELECT type, app, title, content, timestamp, feedback, rank
            FROM memory_fts
            WHERE memory_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let ftsQuery = sanitizeFTSQuery(query)
        sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [MemoryRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let record = MemoryRecord(
                type: String(cString: sqlite3_column_text(stmt, 0)),
                app: String(cString: sqlite3_column_text(stmt, 1)),
                title: String(cString: sqlite3_column_text(stmt, 2)),
                content: String(cString: sqlite3_column_text(stmt, 3)),
                timestamp: String(cString: sqlite3_column_text(stmt, 4)),
                feedback: sqlite3_column_type(stmt, 5) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 5)) : nil,
                rank: sqlite3_column_double(stmt, 6)
            )
            results.append(record)
        }

        return results
    }

    func updateMemoryFeedback(title: String, feedback: String) throws {
        guard let db else { throw DatabaseError.notOpen }

        let sql = "UPDATE memory_fts SET feedback = ? WHERE title = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (feedback as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (title as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func deleteOldMemory(retentionDays: Int = 90) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now)!
        let cutoffStr = ISO8601DateFormatter().string(from: cutoff)
        try execute("DELETE FROM memory_fts WHERE timestamp < '\(cutoffStr)'")
    }

    private func sanitizeFTSQuery(_ query: String) -> String {
        // Extract words, drop short ones and FTS5 special chars, join with OR for broad matching
        let words = query.components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 3 }
            .map { "\"\($0)\"" }

        guard !words.isEmpty else { return "\"\(query)\"" }
        return words.joined(separator: " OR ")
    }

    // MARK: - Settings

    func getSetting(key: String) throws -> String? {
        guard let db else { throw DatabaseError.notOpen }

        let sql = "SELECT value FROM settings WHERE key = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        return nil
    }

    func setSetting(key: String, value: String) throws {
        guard let db else { throw DatabaseError.notOpen }

        let sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case notOpen
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): "Failed to open database: \(msg)"
        case .notOpen: "Database is not open."
        case .executionFailed(let msg): "Database error: \(msg)"
        }
    }
}
