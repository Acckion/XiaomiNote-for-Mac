import AppKit
import Foundation
import SQLite3

/// SQLite数据库服务
///
/// 负责所有数据库操作，包括：
/// - 笔记的CRUD操作
/// - 文件夹的CRUD操作
/// - 离线操作队列管理
/// - 同步状态管理
/// - 待删除笔记管理
///
/// **线程安全**：使用并发队列（DispatchQueue）确保线程安全
/// **数据库位置**：存储在应用程序支持目录中
final class DatabaseService: @unchecked Sendable {
    static let shared = DatabaseService()

    // MARK: - 数据库字段常量

    /// Notes 表字段名称常量
    private enum NotesTableColumns {
        static let id = "id"
        static let title = "title"
        static let content = "content"
        static let folderId = "folder_id"
        static let isStarred = "is_starred"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let tags = "tags"
        static let rawData = "raw_data"
        static let snippet = "snippet"
        static let colorId = "color_id"
        static let subject = "subject"
        static let alertDate = "alert_date"
        static let type = "type"
        static let tag = "tag"
        static let status = "status"
        static let settingJson = "setting_json"
        static let extraInfoJson = "extra_info_json"
    }

    /// Notes 表创建 SQL 语句
    private static let createNotesTableSQL = """
    CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        folder_id TEXT NOT NULL DEFAULT '0',
        is_starred INTEGER NOT NULL DEFAULT 0,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL,
        tags TEXT,
        raw_data TEXT,
        snippet TEXT,
        color_id INTEGER DEFAULT 0,
        subject TEXT,
        alert_date INTEGER,
        type TEXT DEFAULT 'note',
        tag TEXT,
        status TEXT DEFAULT 'normal',
        setting_json TEXT,
        extra_info_json TEXT
    );
    """

    /// Notes 表索引创建 SQL 语句
    private static let createNotesIndexesSQL = [
        "CREATE INDEX IF NOT EXISTS idx_notes_folder_id ON notes(folder_id);",
        "CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_notes_snippet ON notes(snippet);",
        "CREATE INDEX IF NOT EXISTS idx_notes_status ON notes(status);",
        "CREATE INDEX IF NOT EXISTS idx_notes_type ON notes(type);",
        "CREATE INDEX IF NOT EXISTS idx_notes_folder_status ON notes(folder_id, status);",
    ]

    // MARK: - 内部属性（供 extension 访问）

    var db: OpaquePointer?
    let dbQueue = DispatchQueue(label: "DatabaseQueue", attributes: .concurrent)
    let dbPath: URL

    private init() {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access application support directory")
        }
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.mi.note.mac"
        let appDirectory = appSupportURL.appendingPathComponent(appBundleID)

        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)

        self.dbPath = appDirectory.appendingPathComponent("minote.db")

        initializeDatabase()
    }

    deinit {
        closeDatabase()
    }

    // MARK: - 数据库初始化

    private func initializeDatabase() {
        dbQueue.sync(flags: .barrier) {
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2(dbPath.path, &db, flags, nil) == SQLITE_OK else {
                let errorMsg = db != nil ? String(cString: sqlite3_errmsg(db)) : "无法打开数据库"
                print("[[调试]] 无法打开数据库: \(errorMsg)")
                if db != nil {
                    sqlite3_close(db)
                    db = nil
                }
                return
            }

            sqlite3_busy_timeout(db, 5000)
            sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)

            print("[[调试]] 数据库已打开: \(dbPath.path)")

            createTables()
        }
    }

    /// 创建 notes 表
    private func createNotesTable() throws {
        executeSQL(Self.createNotesTableSQL)

        for indexSQL in Self.createNotesIndexesSQL {
            executeSQL(indexSQL)
        }

        print("[[调试]] notes 表创建成功，包含所有优化字段")
    }

    /// 创建数据库表
    private func createTables() {
        do {
            try createNotesTable()
        } catch {
            print("[[调试]] 创建 notes 表失败: \(error)")
        }

        let createFoldersTable = """
        CREATE TABLE IF NOT EXISTS folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 0,
            is_system INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            raw_data TEXT
        );
        """
        executeSQL(createFoldersTable)

        do {
            try DatabaseMigrationManager.runPendingMigrations(db: db)
        } catch {
            print("[[调试]] 数据库迁移失败: \(error)")
        }

        let createSyncStatusTable = """
        CREATE TABLE IF NOT EXISTS sync_status (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            last_sync_time REAL,
            sync_tag TEXT
        );
        """
        executeSQL(createSyncStatusTable)

        let createUnifiedOperationsTable = """
        CREATE TABLE IF NOT EXISTS unified_operations (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            note_id TEXT NOT NULL,
            data BLOB NOT NULL,
            created_at INTEGER NOT NULL,
            local_save_timestamp INTEGER,
            status TEXT NOT NULL DEFAULT 'pending',
            priority INTEGER NOT NULL DEFAULT 0,
            retry_count INTEGER NOT NULL DEFAULT 0,
            next_retry_at INTEGER,
            last_error TEXT,
            error_type TEXT,
            is_local_id INTEGER NOT NULL DEFAULT 0
        );
        """
        executeSQL(createUnifiedOperationsTable)

        let createIdMappingsTable = """
        CREATE TABLE IF NOT EXISTS id_mappings (
            local_id TEXT PRIMARY KEY,
            server_id TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            completed INTEGER NOT NULL DEFAULT 0
        );
        """
        executeSQL(createIdMappingsTable)

        let createOperationHistoryTable = """
        CREATE TABLE IF NOT EXISTS operation_history (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            note_id TEXT NOT NULL,
            data BLOB NOT NULL,
            created_at INTEGER NOT NULL,
            completed_at INTEGER NOT NULL,
            status TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            error_type TEXT
        );
        """
        executeSQL(createOperationHistoryTable)

        let createFolderSortInfoTable = """
        CREATE TABLE IF NOT EXISTS folder_sort_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            etag TEXT NOT NULL,
            orders TEXT NOT NULL
        );
        """
        executeSQL(createFolderSortInfoTable)

        createIndexes()
    }

    private func createIndexes() {
        for indexSQL in Self.createNotesIndexesSQL {
            executeSQL(indexSQL)
        }

        executeSQL("CREATE INDEX IF NOT EXISTS idx_unified_operations_note_id ON unified_operations(note_id);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_unified_operations_status ON unified_operations(status) WHERE status IN ('pending', 'failed');")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_unified_operations_retry ON unified_operations(next_retry_at) WHERE next_retry_at IS NOT NULL;")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_unified_operations_priority ON unified_operations(priority DESC, created_at ASC);")

        executeSQL("CREATE INDEX IF NOT EXISTS idx_id_mappings_server_id ON id_mappings(server_id);")

        executeSQL("CREATE INDEX IF NOT EXISTS idx_operation_history_completed_at ON operation_history(completed_at DESC);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_operation_history_note_id ON operation_history(note_id);")
    }

    func executeSQL(_ sql: String, ignoreError: Bool = false) {
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            if !ignoreError {
                print("[[调试]] SQL 准备失败: \(String(cString: sqlite3_errmsg(db)))")
            }
            return
        }

        let result = sqlite3_step(statement)
        if result != SQLITE_DONE, !ignoreError {
            print("[[调试]] SQL 执行失败: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private func closeDatabase() {
        dbQueue.sync(flags: .barrier) {
            if db != nil {
                sqlite3_close(db)
                db = nil
                print("[[调试]] 数据库已关闭")
            }
        }
    }
}
