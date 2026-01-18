import Foundation
import SQLite3
import AppKit

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
        // 现有字段
        static let id = "id"
        static let title = "title"
        static let content = "content"
        static let folderId = "folder_id"
        static let isStarred = "is_starred"
        static let createdAt = "created_at"
        static let updatedAt = "updated_at"
        static let tags = "tags"
        static let rawData = "raw_data"
        
        // 新增字段
        static let snippet = "snippet"
        static let colorId = "color_id"
        static let subject = "subject"
        static let alertDate = "alert_date"
        static let type = "type"
        static let tag = "tag"
        static let status = "status"
        static let settingJson = "setting_json"
        static let extraInfoJson = "extra_info_json"
        static let modifyDate = "modify_date"
        static let createDate = "create_date"
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
        extra_info_json TEXT,
        modify_date INTEGER,
        create_date INTEGER
    );
    """
    
    /// Notes 表索引创建 SQL 语句
    private static let createNotesIndexesSQL = [
        "CREATE INDEX IF NOT EXISTS idx_notes_folder_id ON notes(folder_id);",
        "CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);",
        "CREATE INDEX IF NOT EXISTS idx_notes_snippet ON notes(snippet);",
        "CREATE INDEX IF NOT EXISTS idx_notes_modify_date ON notes(modify_date DESC);",
        "CREATE INDEX IF NOT EXISTS idx_notes_status ON notes(status);",
        "CREATE INDEX IF NOT EXISTS idx_notes_type ON notes(type);",
        "CREATE INDEX IF NOT EXISTS idx_notes_folder_status ON notes(folder_id, status);"
    ]
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "DatabaseQueue", attributes: .concurrent)
    private let dbPath: URL
    
    private init() {
        // 获取应用程序支持目录
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBundleID = Bundle.main.bundleIdentifier ?? "com.mi.note.mac"
        let appDirectory = appSupportURL.appendingPathComponent(appBundleID)
        
        // 创建目录（如果不存在）
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        
        // 数据库文件路径
        dbPath = appDirectory.appendingPathComponent("minote.db")
        
        // 初始化数据库
        initializeDatabase()
    }
    
    deinit {
        closeDatabase()
    }
    
    // MARK: - 数据库初始化
    
    private func initializeDatabase() {
        dbQueue.sync(flags: .barrier) {
            // 使用 SQLITE_OPEN_FULLMUTEX 标志启用多线程模式
            // 这确保数据库连接可以在多个线程间安全共享
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2(dbPath.path, &db, flags, nil) == SQLITE_OK else {
                let errorMsg = db != nil ? String(cString: sqlite3_errmsg(db)) : "无法打开数据库"
                print("[Database] 无法打开数据库: \(errorMsg)")
                if db != nil {
                    sqlite3_close(db)
                    db = nil
                }
                return
            }
            
            // 设置忙等待超时为5秒
            sqlite3_busy_timeout(db, 5000)
            
            // 启用外键约束
            sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
            
            print("[Database] 数据库已打开: \(dbPath.path)")
            
            // 创建表
            createTables()
        }
    }
    
    /// 创建 notes 表
    /// 
    /// 创建包含所有优化字段的 notes 表，包括：
    /// - 基本字段：id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data
    /// - 新增字段：snippet, color_id, subject, alert_date, type, tag, status, setting_json, extra_info_json, modify_date, create_date
    /// 
    /// 使用事务确保创建操作的原子性
    /// 
    /// - Throws: DatabaseError（数据库操作失败）
    func createNotesTable() throws {
        try dbQueue.sync(flags: .barrier) {
            // 开始事务
            executeSQL("BEGIN TRANSACTION;")
            
            do {
                // 创建 notes 表（使用常量定义）
                executeSQL(Self.createNotesTableSQL)
                
                // 创建索引
                for indexSQL in Self.createNotesIndexesSQL {
                    executeSQL(indexSQL)
                }
                
                // 提交事务
                executeSQL("COMMIT;")
                
                print("[Database] ✅ notes 表创建成功，包含所有优化字段")
            } catch {
                // 回滚事务
                executeSQL("ROLLBACK;")
                print("[Database] ❌ notes 表创建失败，事务已回滚")
                throw error
            }
        }
    }
    
    /// 创建数据库表
    /// 
    /// 创建以下表：
    /// - notes: 笔记表（包含所有优化后的字段）
    /// - folders: 文件夹表
    /// - sync_status: 同步状态表（单行表）
    /// - unified_operations: 统一操作队列表
    /// - id_mappings: ID 映射表
    /// - operation_history: 操作历史表
    /// - folder_sort_info: 文件夹排序信息表
    private func createTables() {
        // 创建 notes 表（使用新的 createNotesTable 方法）
        do {
            try createNotesTable()
        } catch {
            print("[Database] ❌ 创建 notes 表失败: \(error)")
        }
        
        // 创建 folders 表
        let createFoldersTable = """
        CREATE TABLE IF NOT EXISTS folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 0,
            is_system INTEGER NOT NULL DEFAULT 0,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            raw_data TEXT -- JSON 对象
        );
        """
        executeSQL(createFoldersTable)
        
        // 如果表已存在但没有 is_pinned 字段，添加该字段
        let addPinnedColumn = """
        ALTER TABLE folders ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;
        """
        executeSQL(addPinnedColumn, ignoreError: true)  // 忽略错误（如果字段已存在）
        
        // 注意：由于应用未正式投入使用，不需要实现数据迁移逻辑
        // notes 表已通过 createNotesTable() 方法创建，包含所有必需字段
        
        // 创建 sync_status 表（单行表）
        let createSyncStatusTable = """
        CREATE TABLE IF NOT EXISTS sync_status (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            last_sync_time REAL,
            sync_tag TEXT
        );
        """
        executeSQL(createSyncStatusTable)
        
        // 创建 unified_operations 表（统一操作队列）
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
        
        // 创建 id_mappings 表（临时 ID -> 正式 ID 映射）
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
        
        // 创建 operation_history 表（历史操作记录）
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
        
        // 创建 folder_sort_info 表（文件夹排序信息）
        let createFolderSortInfoTable = """
        CREATE TABLE IF NOT EXISTS folder_sort_info (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            etag TEXT NOT NULL,
            orders TEXT NOT NULL
        );
        """
        executeSQL(createFolderSortInfoTable)
        
        // 创建索引
        createIndexes()
    }
    
    private func createIndexes() {
        // notes 表索引（使用常量定义）
        for indexSQL in Self.createNotesIndexesSQL {
            executeSQL(indexSQL)
        }
        
        // unified_operations 表索引
        executeSQL("CREATE INDEX IF NOT EXISTS idx_unified_operations_note_id ON unified_operations(note_id);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_unified_operations_status ON unified_operations(status) WHERE status IN ('pending', 'failed');")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_unified_operations_retry ON unified_operations(next_retry_at) WHERE next_retry_at IS NOT NULL;")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_unified_operations_priority ON unified_operations(priority DESC, created_at ASC);")
        
        // id_mappings 表索引
        executeSQL("CREATE INDEX IF NOT EXISTS idx_id_mappings_server_id ON id_mappings(server_id);")
        
        // operation_history 表索引
        executeSQL("CREATE INDEX IF NOT EXISTS idx_operation_history_completed_at ON operation_history(completed_at DESC);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_operation_history_note_id ON operation_history(note_id);")
    }
    
    /// 迁移 notes 表，确保所有新增字段存在
    /// 
    /// 检查并添加缺失的字段到现有表
    /// 使用事务确保迁移的原子性
    private func migrateNotesTable() {
        print("[Database] 开始迁移 notes 表，检查字段兼容性")
        
        // 开始事务
        executeSQL("BEGIN TRANSACTION;")
        
        // 定义需要添加的字段及其默认值
        let newColumns: [(name: String, definition: String)] = [
            ("snippet", "TEXT"),
            ("color_id", "INTEGER DEFAULT 0"),
            ("subject", "TEXT"),
            ("alert_date", "INTEGER"),
            ("type", "TEXT DEFAULT 'note'"),
            ("tag", "TEXT"),
            ("status", "TEXT DEFAULT 'normal'"),
            ("setting_json", "TEXT"),
            ("extra_info_json", "TEXT"),
            ("modify_date", "INTEGER"),
            ("create_date", "INTEGER")
        ]
        
        // 检查每个字段是否存在，如果不存在则添加
        for column in newColumns {
            let checkColumnSQL = "PRAGMA table_info(notes);"
            var columnExists = false
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            if sqlite3_prepare_v2(db, checkColumnSQL, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let nameText = sqlite3_column_text(statement, 1) {
                        let columnName = String(cString: nameText)
                        if columnName == column.name {
                            columnExists = true
                            break
                        }
                    }
                }
            }
            
            // 如果字段不存在，添加该字段
            if !columnExists {
                let alterSQL = "ALTER TABLE notes ADD COLUMN \(column.name) \(column.definition);"
                executeSQL(alterSQL, ignoreError: false)
                print("[Database] 添加字段: \(column.name)")
            } else {
                print("[Database] 字段已存在: \(column.name)")
            }
        }
        
        // 提交事务
        executeSQL("COMMIT;")
        
        print("[Database] notes 表迁移完成")
    }
    
    private func executeSQL(_ sql: String, ignoreError: Bool = false) {
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            if !ignoreError {
            print("[Database] SQL 准备失败: \(String(cString: sqlite3_errmsg(db)))")
            }
            return
        }
        
        let result = sqlite3_step(statement)
        if result != SQLITE_DONE && !ignoreError {
            print("[Database] SQL 执行失败: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    private func closeDatabase() {
        dbQueue.sync(flags: .barrier) {
            if db != nil {
                sqlite3_close(db)
                db = nil
                print("[Database] 数据库已关闭")
            }
        }
    }
    
    // MARK: - 笔记操作
    
    /// 保存笔记（插入或更新）
    /// 
    /// 如果笔记已存在，则更新；否则插入新记录
    /// 包含数据验证，确保字段类型和约束正确
    /// 
    /// - Parameter note: 要保存的笔记对象
    /// - Throws: DatabaseError（数据库操作失败或数据验证失败）
    func saveNote(_ note: Note) throws {
        print("![[debug]] [Database] 保存笔记，ID: \(note.id), 标题: \(note.title), content长度: \(note.content.count)")
        
        // 数据验证
        try validateNote(note)
        
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO notes (
                id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                snippet, color_id, subject, alert_date, type, tag, status, 
                setting_json, extra_info_json, modify_date, create_date
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("![[debug]] [Database] ❌ SQL准备失败: \(errorMsg)")
                throw DatabaseError.prepareFailed(errorMsg)
            }
            
            print("![[debug]] ========== 数据流程节点DB2: 绑定参数 ==========")
            // 绑定基本字段（索引 1-9）
            sqlite3_bind_text(statement, 1, (note.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (note.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (note.content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 4, (note.folderId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 5, note.isStarred ? 1 : 0)
            sqlite3_bind_double(statement, 6, note.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, note.updatedAt.timeIntervalSince1970)
            
            // tags 作为 JSON
            let tagsJSON = try JSONEncoder().encode(note.tags)
            sqlite3_bind_text(statement, 8, String(data: tagsJSON, encoding: .utf8), -1, nil)
            
            // raw_data 作为 JSON
            var rawDataJSON: String? = nil
            if let rawData = note.rawData {
                let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [])
                rawDataJSON = String(data: jsonData, encoding: .utf8)
            }
            sqlite3_bind_text(statement, 9, rawDataJSON, -1, nil)
            
            // 绑定新增字段（索引 10-20）
            // snippet（索引 10）
            sqlite3_bind_text(statement, 10, note.snippet, -1, nil)
            
            // color_id（索引 11）
            sqlite3_bind_int(statement, 11, Int32(note.colorId))
            
            // subject（索引 12）
            sqlite3_bind_text(statement, 12, note.subject, -1, nil)
            
            // alert_date（索引 13）- Date 转毫秒时间戳
            if let alertDate = note.alertDate {
                sqlite3_bind_int64(statement, 13, Int64(alertDate.timeIntervalSince1970 * 1000))
            } else {
                sqlite3_bind_null(statement, 13)
            }
            
            // type（索引 14）
            sqlite3_bind_text(statement, 14, (note.type as NSString).utf8String, -1, nil)
            
            // tag（索引 15）- 服务器标签
            sqlite3_bind_text(statement, 15, note.serverTag, -1, nil)
            
            // status（索引 16）
            sqlite3_bind_text(statement, 16, (note.status as NSString).utf8String, -1, nil)
            
            // setting_json（索引 17）
            sqlite3_bind_text(statement, 17, note.settingJson, -1, nil)
            
            // extra_info_json（索引 18）
            sqlite3_bind_text(statement, 18, note.extraInfoJson, -1, nil)
            
            // modify_date（索引 19）- Date 转毫秒时间戳
            if let modifyDate = note.modifyDate {
                sqlite3_bind_int64(statement, 19, Int64(modifyDate.timeIntervalSince1970 * 1000))
            } else {
                sqlite3_bind_null(statement, 19)
            }
            
            // create_date（索引 20）- Date 转毫秒时间戳
            if let createDate = note.createDate {
                sqlite3_bind_int64(statement, 20, Int64(createDate.timeIntervalSince1970 * 1000))
            } else {
                sqlite3_bind_null(statement, 20)
            }
            
            print("![[debug]] ========== 数据流程节点DB4: 执行 SQL ==========")
            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("![[debug]] [Database] ❌ SQL执行失败: \(errorMsg)")
                throw DatabaseError.executionFailed(errorMsg)
            }
            
            print("![[debug]] ========== 数据流程节点DB5: 数据库保存成功 ==========")
            print("![[debug]] [Database] ✅ 保存笔记到数据库成功，ID: \(note.id), 标题: \(note.title), content长度: \(note.content.count)")
        }
    }
    
    /// 验证笔记数据
    /// 
    /// 检查笔记字段是否符合约束条件
    /// 
    /// - Parameter note: 要验证的笔记对象
    /// - Throws: DatabaseError.validationFailed（数据验证失败）
    private func validateNote(_ note: Note) throws {
        // 验证 ID 不为空
        guard !note.id.isEmpty else {
            throw DatabaseError.validationFailed("笔记 ID 不能为空")
        }
        
        // 验证 folderId 不为空
        guard !note.folderId.isEmpty else {
            throw DatabaseError.validationFailed("文件夹 ID 不能为空")
        }
        
        // 验证 colorId 在合理范围内（0-10）
        guard note.colorId >= 0 && note.colorId <= 10 else {
            throw DatabaseError.validationFailed("颜色 ID 必须在 0-10 之间，当前值: \(note.colorId)")
        }
        
        // 验证 type 不为空
        guard !note.type.isEmpty else {
            throw DatabaseError.validationFailed("笔记类型不能为空")
        }
        
        // 验证 status 不为空
        guard !note.status.isEmpty else {
            throw DatabaseError.validationFailed("笔记状态不能为空")
        }
        
        // 验证 JSON 字段格式（如果存在）
        if let settingJson = note.settingJson, !settingJson.isEmpty {
            guard let jsonData = settingJson.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: jsonData, options: [])) != nil else {
                throw DatabaseError.validationFailed("setting_json 格式无效")
            }
        }
        
        if let extraInfoJson = note.extraInfoJson, !extraInfoJson.isEmpty {
            guard let jsonData = extraInfoJson.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: jsonData, options: [])) != nil else {
                throw DatabaseError.validationFailed("extra_info_json 格式无效")
            }
        }
        
        // 验证时间戳合理性
        let now = Date()
        let minDate = Date(timeIntervalSince1970: 0) // 1970-01-01
        
        guard note.createdAt >= minDate && note.createdAt <= now.addingTimeInterval(86400) else {
            throw DatabaseError.validationFailed("创建时间不合理: \(note.createdAt)")
        }
        
        guard note.updatedAt >= minDate && note.updatedAt <= now.addingTimeInterval(86400) else {
            throw DatabaseError.validationFailed("更新时间不合理: \(note.updatedAt)")
        }
        
        // 验证 updatedAt >= createdAt
        guard note.updatedAt >= note.createdAt else {
            throw DatabaseError.validationFailed("更新时间不能早于创建时间")
        }
    }
    
    /// 异步保存笔记（插入或更新）
    /// 
    /// 使用异步队列执行，不阻塞调用线程
    /// 
    /// - Parameters:
    ///   - note: 要保存的笔记对象
    ///   - completion: 完成回调，参数为错误（如果有）
    func saveNoteAsync(_ note: Note, completion: @escaping (Error?) -> Void) {
        dbQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else {
                completion(DatabaseError.connectionFailed("数据库连接已关闭"))
                return
            }
            
            do {
                let sql = """
                INSERT OR REPLACE INTO notes (
                    id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                    snippet, color_id, subject, alert_date, type, tag, status, 
                    setting_json, extra_info_json, modify_date, create_date
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
                
                var statement: OpaquePointer?
                defer {
                    if statement != nil {
                        sqlite3_finalize(statement)
                    }
                }
                
                guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else {
                    let errorMsg = String(cString: sqlite3_errmsg(self.db))
                    throw DatabaseError.prepareFailed(errorMsg)
                }
                
                // 绑定基本字段（索引 1-9）
                sqlite3_bind_text(statement, 1, (note.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (note.title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (note.content as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 4, (note.folderId as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 5, note.isStarred ? 1 : 0)
                sqlite3_bind_double(statement, 6, note.createdAt.timeIntervalSince1970)
                sqlite3_bind_double(statement, 7, note.updatedAt.timeIntervalSince1970)
                
                // tags 作为 JSON
                let tagsJSON = try JSONEncoder().encode(note.tags)
                sqlite3_bind_text(statement, 8, String(data: tagsJSON, encoding: .utf8), -1, nil)
                
                // raw_data 作为 JSON
                var rawDataJSON: String? = nil
                if let rawData = note.rawData {
                    let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [])
                    rawDataJSON = String(data: jsonData, encoding: .utf8)
                }
                sqlite3_bind_text(statement, 9, rawDataJSON, -1, nil)
                
                // 绑定新增字段（索引 10-20）
                // snippet（索引 10）
                sqlite3_bind_text(statement, 10, note.snippet, -1, nil)
                
                // color_id（索引 11）
                sqlite3_bind_int(statement, 11, Int32(note.colorId))
                
                // subject（索引 12）
                sqlite3_bind_text(statement, 12, note.subject, -1, nil)
                
                // alert_date（索引 13）- Date 转毫秒时间戳
                if let alertDate = note.alertDate {
                    sqlite3_bind_int64(statement, 13, Int64(alertDate.timeIntervalSince1970 * 1000))
                } else {
                    sqlite3_bind_null(statement, 13)
                }
                
                // type（索引 14）
                sqlite3_bind_text(statement, 14, (note.type as NSString).utf8String, -1, nil)
                
                // tag（索引 15）- 服务器标签
                sqlite3_bind_text(statement, 15, note.serverTag, -1, nil)
                
                // status（索引 16）
                sqlite3_bind_text(statement, 16, (note.status as NSString).utf8String, -1, nil)
                
                // setting_json（索引 17）
                sqlite3_bind_text(statement, 17, note.settingJson, -1, nil)
                
                // extra_info_json（索引 18）
                sqlite3_bind_text(statement, 18, note.extraInfoJson, -1, nil)
                
                // modify_date（索引 19）- Date 转毫秒时间戳
                if let modifyDate = note.modifyDate {
                    sqlite3_bind_int64(statement, 19, Int64(modifyDate.timeIntervalSince1970 * 1000))
                } else {
                    sqlite3_bind_null(statement, 19)
                }
                
                // create_date（索引 20）- Date 转毫秒时间戳
                if let createDate = note.createDate {
                    sqlite3_bind_int64(statement, 20, Int64(createDate.timeIntervalSince1970 * 1000))
                } else {
                    sqlite3_bind_null(statement, 20)
                }
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    let errorMsg = String(cString: sqlite3_errmsg(self.db))
                    throw DatabaseError.executionFailed(errorMsg)
                }
                
                Swift.print("[保存流程] ✅ Tier 1 异步保存笔记到数据库成功，ID: \(note.id.prefix(8))..., 标题: \(note.title)")
                completion(nil)
            } catch {
                Swift.print("[保存流程] ❌ Tier 1 异步保存笔记失败: \(error)")
                completion(error)
            }
        }
    }
    
    /// 更新笔记 ID
    ///
    /// 将临时 ID 更新为云端下发的正式 ID。
    /// 这是一个原子操作，会更新 notes 表中的主键。
    ///
    /// - Parameters:
    ///   - oldId: 旧的笔记 ID（临时 ID）
    ///   - newId: 新的笔记 ID（正式 ID）
    /// - Throws: DatabaseError（数据库操作失败）
    func updateNoteId(oldId: String, newId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            // SQLite 不支持直接更新主键，需要使用 INSERT + DELETE 的方式
            // 1. 先读取旧记录（包含所有字段）
            let selectSQL = """
            SELECT id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                   snippet, color_id, subject, alert_date, type, tag, status, 
                   setting_json, extra_info_json, modify_date, create_date
            FROM notes WHERE id = ?;
            """
            
            var selectStatement: OpaquePointer?
            defer {
                if selectStatement != nil {
                    sqlite3_finalize(selectStatement)
                }
            }
            
            guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStatement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(selectStatement, 1, (oldId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(selectStatement) == SQLITE_ROW else {
                print("[Database] ⚠️ 更新笔记 ID 失败：找不到笔记 \(oldId)")
                return
            }
            
            // 使用 parseNote 方法解析完整的笔记对象
            guard var note = try parseNote(from: selectStatement) else {
                print("[Database] ⚠️ 更新笔记 ID 失败：无法解析笔记 \(oldId)")
                return
            }
            
            // 更新笔记 ID
            note = Note(
                id: newId,
                title: note.title,
                content: note.content,
                folderId: note.folderId,
                isStarred: note.isStarred,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                tags: note.tags,
                rawData: note.rawData,
                snippet: note.snippet,
                colorId: note.colorId,
                subject: note.subject,
                alertDate: note.alertDate,
                type: note.type,
                serverTag: note.serverTag,
                status: note.status,
                settingJson: note.settingJson,
                extraInfoJson: note.extraInfoJson,
                modifyDate: note.modifyDate,
                createDate: note.createDate
            )
            
            // 2. 插入新记录（使用新 ID）
            let insertSQL = """
            INSERT INTO notes (
                id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                snippet, color_id, subject, alert_date, type, tag, status, 
                setting_json, extra_info_json, modify_date, create_date
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var insertStatement: OpaquePointer?
            defer {
                if insertStatement != nil {
                    sqlite3_finalize(insertStatement)
                }
            }
            
            guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStatement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            // 绑定基本字段
            sqlite3_bind_text(insertStatement, 1, (note.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (note.title as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, (note.content as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 4, (note.folderId as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStatement, 5, note.isStarred ? 1 : 0)
            sqlite3_bind_double(insertStatement, 6, note.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(insertStatement, 7, note.updatedAt.timeIntervalSince1970)
            
            // tags 作为 JSON
            let tagsJSON = try JSONEncoder().encode(note.tags)
            sqlite3_bind_text(insertStatement, 8, String(data: tagsJSON, encoding: .utf8), -1, nil)
            
            // raw_data 作为 JSON
            var rawDataJSON: String? = nil
            if let rawData = note.rawData {
                let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [])
                rawDataJSON = String(data: jsonData, encoding: .utf8)
            }
            sqlite3_bind_text(insertStatement, 9, rawDataJSON, -1, nil)
            
            // 绑定新增字段
            sqlite3_bind_text(insertStatement, 10, note.snippet, -1, nil)
            sqlite3_bind_int(insertStatement, 11, Int32(note.colorId))
            sqlite3_bind_text(insertStatement, 12, note.subject, -1, nil)
            
            if let alertDate = note.alertDate {
                sqlite3_bind_int64(insertStatement, 13, Int64(alertDate.timeIntervalSince1970 * 1000))
            } else {
                sqlite3_bind_null(insertStatement, 13)
            }
            
            sqlite3_bind_text(insertStatement, 14, (note.type as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 15, note.serverTag, -1, nil)
            sqlite3_bind_text(insertStatement, 16, (note.status as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 17, note.settingJson, -1, nil)
            sqlite3_bind_text(insertStatement, 18, note.extraInfoJson, -1, nil)
            
            if let modifyDate = note.modifyDate {
                sqlite3_bind_int64(insertStatement, 19, Int64(modifyDate.timeIntervalSince1970 * 1000))
            } else {
                sqlite3_bind_null(insertStatement, 19)
            }
            
            if let createDate = note.createDate {
                sqlite3_bind_int64(insertStatement, 20, Int64(createDate.timeIntervalSince1970 * 1000))
            } else {
                sqlite3_bind_null(insertStatement, 20)
            }
            
            guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            // 3. 删除旧记录
            let deleteSQL = "DELETE FROM notes WHERE id = ?;"
            
            var deleteStatement: OpaquePointer?
            defer {
                if deleteStatement != nil {
                    sqlite3_finalize(deleteStatement)
                }
            }
            
            guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(deleteStatement, 1, (oldId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] ✅ 更新笔记 ID: \(oldId) -> \(newId)")
        }
    }
    
    // 注意：已移除与html_content相关的所有方法，包括：
    // - getHTMLContent
    // - batchUpdateHTMLContent
    // - updateHTMLContentOnly
    
    /// 加载笔记
    /// 
    /// - Parameter noteId: 笔记ID
    /// - Returns: 笔记对象，如果不存在则返回nil
    /// - Throws: DatabaseError（数据库操作失败）
    func loadNote(noteId: String) throws -> Note? {
        return try dbQueue.sync {
            let sql = """
            SELECT id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                   snippet, color_id, subject, alert_date, type, tag, status, 
                   setting_json, extra_info_json, modify_date, create_date
            FROM notes WHERE id = ?;
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (noteId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            
            guard var note = try parseNote(from: statement) else {
                return nil
            }
            
            return note
        }
    }
    
    /// 获取所有笔记
    /// 
    /// 按更新时间倒序排列（最新的在前）
    /// 
    /// - Returns: 笔记数组
    /// - Throws: DatabaseError（数据库操作失败）
    func getAllNotes() throws -> [Note] {
        return try dbQueue.sync {
            let sql = """
            SELECT id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                   snippet, color_id, subject, alert_date, type, tag, status, 
                   setting_json, extra_info_json, modify_date, create_date
            FROM notes ORDER BY updated_at DESC;
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            var notes: [Note] = []
            var rowCount = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                rowCount += 1
                do {
                    if var note = try parseNote(from: statement) {
                        notes.append(note)
                    }
                } catch {
                    // 静默处理解析错误，继续处理下一行
                }
            }
            
            print("[Database] getAllNotes: 处理了 \(rowCount) 行，成功解析 \(notes.count) 条笔记")
            return notes
        }
    }
    
    /// 删除笔记
    /// 
    /// - Parameter noteId: 要删除的笔记ID
    /// - Throws: DatabaseError（数据库操作失败）
    func deleteNote(noteId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM notes WHERE id = ?;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (noteId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 删除笔记: \(noteId)")
        }
    }
    
    /// 检查笔记是否存在
    /// 
    /// - Parameter noteId: 笔记ID
    /// - Returns: 如果存在返回true，否则返回false
    func noteExists(noteId: String) -> Bool {
        return dbQueue.sync {
            let sql = "SELECT COUNT(*) FROM notes WHERE id = ?;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return false
            }
            
            sqlite3_bind_text(statement, 1, (noteId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return false
            }
            
            return sqlite3_column_int(statement, 0) > 0
        }
    }
    
    /// 批量保存笔记（插入或更新）
    /// 
    /// 使用事务批量保存多个笔记，提高性能
    /// 
    /// - Parameter notes: 要保存的笔记数组
    /// - Throws: DatabaseError（数据库操作失败）
    func saveNotes(_ notes: [Note]) throws {
        guard !notes.isEmpty else { return }
        
        try dbQueue.sync(flags: .barrier) {
            // 开始事务
            executeSQL("BEGIN TRANSACTION;")
            
            do {
                for note in notes {
                    let sql = """
                    INSERT OR REPLACE INTO notes (
                        id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                        snippet, color_id, subject, alert_date, type, tag, status, 
                        setting_json, extra_info_json, modify_date, create_date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """
                    
                    var statement: OpaquePointer?
                    defer {
                        if statement != nil {
                            sqlite3_finalize(statement)
                        }
                    }
                    
                    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                        let errorMsg = String(cString: sqlite3_errmsg(db))
                        throw DatabaseError.prepareFailed(errorMsg)
                    }
                    
                    // 绑定基本字段（索引 1-9）
                    sqlite3_bind_text(statement, 1, (note.id as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (note.title as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 3, (note.content as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 4, (note.folderId as NSString).utf8String, -1, nil)
                    sqlite3_bind_int(statement, 5, note.isStarred ? 1 : 0)
                    sqlite3_bind_double(statement, 6, note.createdAt.timeIntervalSince1970)
                    sqlite3_bind_double(statement, 7, note.updatedAt.timeIntervalSince1970)
                    
                    // tags 作为 JSON
                    let tagsJSON = try JSONEncoder().encode(note.tags)
                    sqlite3_bind_text(statement, 8, String(data: tagsJSON, encoding: .utf8), -1, nil)
                    
                    // raw_data 作为 JSON
                    var rawDataJSON: String? = nil
                    if let rawData = note.rawData {
                        let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [])
                        rawDataJSON = String(data: jsonData, encoding: .utf8)
                    }
                    sqlite3_bind_text(statement, 9, rawDataJSON, -1, nil)
                    
                    // 绑定新增字段（索引 10-20）
                    sqlite3_bind_text(statement, 10, note.snippet, -1, nil)
                    sqlite3_bind_int(statement, 11, Int32(note.colorId))
                    sqlite3_bind_text(statement, 12, note.subject, -1, nil)
                    
                    if let alertDate = note.alertDate {
                        sqlite3_bind_int64(statement, 13, Int64(alertDate.timeIntervalSince1970 * 1000))
                    } else {
                        sqlite3_bind_null(statement, 13)
                    }
                    
                    sqlite3_bind_text(statement, 14, (note.type as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 15, note.serverTag, -1, nil)
                    sqlite3_bind_text(statement, 16, (note.status as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 17, note.settingJson, -1, nil)
                    sqlite3_bind_text(statement, 18, note.extraInfoJson, -1, nil)
                    
                    if let modifyDate = note.modifyDate {
                        sqlite3_bind_int64(statement, 19, Int64(modifyDate.timeIntervalSince1970 * 1000))
                    } else {
                        sqlite3_bind_null(statement, 19)
                    }
                    
                    if let createDate = note.createDate {
                        sqlite3_bind_int64(statement, 20, Int64(createDate.timeIntervalSince1970 * 1000))
                    } else {
                        sqlite3_bind_null(statement, 20)
                    }
                    
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        let errorMsg = String(cString: sqlite3_errmsg(db))
                        throw DatabaseError.executionFailed(errorMsg)
                    }
                }
                
                // 提交事务
                executeSQL("COMMIT;")
                
                print("[Database] ✅ 批量保存 \(notes.count) 条笔记成功")
            } catch {
                // 回滚事务
                executeSQL("ROLLBACK;")
                print("[Database] ❌ 批量保存笔记失败，事务已回滚: \(error)")
                throw error
            }
        }
    }
    
    /// 从数据库行解析 Note 对象
    /// 
    /// 解析数据库查询结果中的所有字段，包括新增的优化字段。
    /// 处理 NULL 值并使用合适的默认值。
    /// 对 JSON 字段进行错误处理，解析失败时记录错误并使用空值。
    /// 
    /// - Parameter statement: SQLite 查询语句指针
    /// - Returns: Note 对象，如果解析失败则返回 nil
    /// - Throws: DatabaseError（数据库操作失败）
    private func parseNote(from statement: OpaquePointer?) throws -> Note? {
        guard let statement = statement else {
            return nil
        }
        
        // 解析基本字段（索引 0-8）
        let id = String(cString: sqlite3_column_text(statement, 0))
        let title = String(cString: sqlite3_column_text(statement, 1))
        let content = String(cString: sqlite3_column_text(statement, 2))
        let folderId = String(cString: sqlite3_column_text(statement, 3))
        let isStarred = sqlite3_column_int(statement, 4) != 0
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        
        // 解析 tags（索引 7）- 带 JSON 错误处理
        var tags: [String] = []
        if let tagsText = sqlite3_column_text(statement, 7) {
            let tagsString = String(cString: tagsText)
            if !tagsString.isEmpty, let tagsData = tagsString.data(using: .utf8) {
                do {
                    tags = try JSONDecoder().decode([String].self, from: tagsData)
                } catch {
                    print("[Database] ⚠️ 解析 tags JSON 失败 (id=\(id)): \(error)")
                    // 使用空数组作为默认值
                    tags = []
                }
            }
        }
        
        // 解析 raw_data（索引 8）- 带 JSON 错误处理
        var rawData: [String: Any]? = nil
        if let rawDataText = sqlite3_column_text(statement, 8) {
            let rawDataString = String(cString: rawDataText)
            if !rawDataString.isEmpty, let rawDataData = rawDataString.data(using: .utf8) {
                do {
                    rawData = try JSONSerialization.jsonObject(with: rawDataData, options: []) as? [String: Any]
                } catch {
                    print("[Database] ⚠️ 解析 raw_data JSON 失败 (id=\(id)): \(error)")
                    // 使用 nil 作为默认值
                    rawData = nil
                }
            }
        }
        
        // 解析新增字段（索引 9-19）
        // snippet（索引 9）- 可选字段
        var snippet: String? = nil
        if sqlite3_column_type(statement, 9) != SQLITE_NULL,
           let snippetText = sqlite3_column_text(statement, 9) {
            snippet = String(cString: snippetText)
        }
        
        // color_id（索引 10）- 默认值 0
        let colorId: Int
        if sqlite3_column_type(statement, 10) != SQLITE_NULL {
            colorId = Int(sqlite3_column_int(statement, 10))
        } else {
            colorId = 0
        }
        
        // subject（索引 11）- 可选字段
        var subject: String? = nil
        if sqlite3_column_type(statement, 11) != SQLITE_NULL,
           let subjectText = sqlite3_column_text(statement, 11) {
            subject = String(cString: subjectText)
        }
        
        // alert_date（索引 12）- 可选字段，毫秒时间戳转 Date
        var alertDate: Date? = nil
        if sqlite3_column_type(statement, 12) != SQLITE_NULL {
            let alertDateMs = sqlite3_column_int64(statement, 12)
            if alertDateMs > 0 {
                alertDate = Date(timeIntervalSince1970: TimeInterval(alertDateMs) / 1000.0)
            }
        }
        
        // type（索引 13）- 默认值 "note"
        let type: String
        if sqlite3_column_type(statement, 13) != SQLITE_NULL,
           let typeText = sqlite3_column_text(statement, 13) {
            type = String(cString: typeText)
        } else {
            type = "note"
        }
        
        // tag（索引 14）- 可选字段（服务器标签）
        var serverTag: String? = nil
        if sqlite3_column_type(statement, 14) != SQLITE_NULL,
           let tagText = sqlite3_column_text(statement, 14) {
            serverTag = String(cString: tagText)
        }
        
        // status（索引 15）- 默认值 "normal"
        let status: String
        if sqlite3_column_type(statement, 15) != SQLITE_NULL,
           let statusText = sqlite3_column_text(statement, 15) {
            status = String(cString: statusText)
        } else {
            status = "normal"
        }
        
        // setting_json（索引 16）- 可选字段，不需要解析，直接存储字符串
        var settingJson: String? = nil
        if sqlite3_column_type(statement, 16) != SQLITE_NULL,
           let settingText = sqlite3_column_text(statement, 16) {
            settingJson = String(cString: settingText)
            // 验证 JSON 格式（可选）
            if let jsonData = settingJson?.data(using: .utf8) {
                do {
                    _ = try JSONSerialization.jsonObject(with: jsonData, options: [])
                } catch {
                    print("[Database] ⚠️ setting_json 格式无效 (id=\(id)): \(error)")
                    // 保留原始字符串，不清空
                }
            }
        }
        
        // extra_info_json（索引 17）- 可选字段，不需要解析，直接存储字符串
        var extraInfoJson: String? = nil
        if sqlite3_column_type(statement, 17) != SQLITE_NULL,
           let extraInfoText = sqlite3_column_text(statement, 17) {
            extraInfoJson = String(cString: extraInfoText)
            // 验证 JSON 格式（可选）
            if let jsonData = extraInfoJson?.data(using: .utf8) {
                do {
                    _ = try JSONSerialization.jsonObject(with: jsonData, options: [])
                } catch {
                    print("[Database] ⚠️ extra_info_json 格式无效 (id=\(id)): \(error)")
                    // 保留原始字符串，不清空
                }
            }
        }
        
        // modify_date（索引 18）- 可选字段，毫秒时间戳转 Date
        var modifyDate: Date? = nil
        if sqlite3_column_type(statement, 18) != SQLITE_NULL {
            let modifyDateMs = sqlite3_column_int64(statement, 18)
            if modifyDateMs > 0 {
                modifyDate = Date(timeIntervalSince1970: TimeInterval(modifyDateMs) / 1000.0)
            }
        }
        
        // create_date（索引 19）- 可选字段，毫秒时间戳转 Date
        var createDate: Date? = nil
        if sqlite3_column_type(statement, 19) != SQLITE_NULL {
            let createDateMs = sqlite3_column_int64(statement, 19)
            if createDateMs > 0 {
                createDate = Date(timeIntervalSince1970: TimeInterval(createDateMs) / 1000.0)
            }
        }
        
        return Note(
            id: id,
            title: title,
            content: content,
            folderId: folderId,
            isStarred: isStarred,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: tags,
            rawData: rawData,
            snippet: snippet,
            colorId: colorId,
            subject: subject,
            alertDate: alertDate,
            type: type,
            serverTag: serverTag,
            status: status,
            settingJson: settingJson,
            extraInfoJson: extraInfoJson,
            modifyDate: modifyDate,
            createDate: createDate
        )
    }
    
    // MARK: - 文件夹操作
    
    /// 保存文件夹（插入或更新）
    /// 
    /// - Parameter folder: 要保存的文件夹对象
    /// - Throws: DatabaseError（数据库操作失败）
    func saveFolder(_ folder: Folder) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO folders (id, name, count, is_system, is_pinned, created_at, raw_data)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (folder.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (folder.name as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 3, Int32(folder.count))
            sqlite3_bind_int(statement, 4, folder.isSystem ? 1 : 0)
            sqlite3_bind_int(statement, 5, folder.isPinned ? 1 : 0)
            sqlite3_bind_double(statement, 6, folder.createdAt.timeIntervalSince1970)
            
            // raw_data 作为 JSON
            var rawDataJSON: String? = nil
            if let rawData = folder.rawData {
                let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [])
                rawDataJSON = String(data: jsonData, encoding: .utf8)
            }
            sqlite3_bind_text(statement, 7, rawDataJSON, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 保存文件夹: \(folder.id)")
        }
    }
    
    /// 保存多个文件夹
    /// 
    /// - Parameter folders: 文件夹数组
    /// - Throws: DatabaseError（数据库操作失败）
    func saveFolders(_ folders: [Folder]) throws {
        for folder in folders {
            try saveFolder(folder)
        }
    }
    
    /// 加载所有文件夹
    /// 
    /// 按以下顺序排列：
    /// 1. 置顶文件夹（is_pinned = 1）
    /// 2. 系统文件夹（is_system = 1）
    /// 3. 普通文件夹（按名称升序）
    /// 
    /// - Returns: 文件夹数组
    /// - Throws: DatabaseError（数据库操作失败）
    func loadFolders() throws -> [Folder] {
        return try dbQueue.sync {
            let sql = "SELECT id, name, count, is_system, is_pinned, created_at, raw_data FROM folders ORDER BY is_pinned DESC, is_system DESC, name ASC;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            var folders: [Folder] = []
            var rowCount = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                rowCount += 1
                if let folder = try parseFolder(from: statement) {
                    folders.append(folder)
                }
            }
            
            print("[Database] loadFolders: 处理了 \(rowCount) 行，成功解析 \(folders.count) 个文件夹")
            return folders
        }
    }
    
    /// 删除文件夹
    func deleteFolder(folderId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM folders WHERE id = ?;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (folderId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 删除文件夹: \(folderId)")
        }
    }
    
    /// 更新笔记的文件夹ID（用于文件夹ID从临时ID更新为服务器ID时，或删除文件夹时移动笔记到未分类）
    /// 
    /// - Parameters:
    ///   - oldFolderId: 旧的文件夹ID
    ///   - newFolderId: 新的文件夹ID
    /// - Throws: DatabaseError（数据库操作失败）
    func updateNotesFolderId(oldFolderId: String, newFolderId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "UPDATE notes SET folder_id = ? WHERE folder_id = ?;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (newFolderId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (oldFolderId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            let changes = sqlite3_changes(db)
            print("[Database] 更新笔记文件夹ID: \(oldFolderId) -> \(newFolderId), 影响了 \(changes) 条笔记")
            
            // 只有在更新ID时（而不是移动到未分类时）才重命名图片目录
            // 移动到未分类时，图片应该保留在原目录或移动到未分类目录（根据业务需求）
            // 这里我们选择保留在原目录，因为图片目录名是 folderId，移动到未分类时folderId变为"0"
            // 但原文件夹的图片应该保留在原来的目录中（如果之后文件夹被恢复，图片还在）
            // 或者可以根据需要移动到未分类的图片目录
            // 当前实现：如果是从临时ID更新为服务器ID，重命名目录；如果是删除文件夹（移动到未分类），不重命名目录
            if newFolderId != "0" && oldFolderId != "0" {
                // 这是ID更新操作，不是删除操作，需要重命名图片目录
                try LocalStorageService.shared.renameFolderImageDirectory(oldFolderId: oldFolderId, newFolderId: newFolderId)
            }
            // 如果移动到未分类（newFolderId == "0"），图片目录保留在原处，或者可以根据需要移动到未分类目录
        }
    }
    
    private func parseFolder(from statement: OpaquePointer?) throws -> Folder? {
        guard let statement = statement else { return nil }
        
        let id = String(cString: sqlite3_column_text(statement, 0))
        let name = String(cString: sqlite3_column_text(statement, 1))
        let count = Int(sqlite3_column_int(statement, 2))
        let isSystem = sqlite3_column_int(statement, 3) != 0
        
        // 检查 is_pinned 列是否存在（兼容旧数据库）
        // 新数据库：id, name, count, is_system, is_pinned, created_at, raw_data (7列)
        // 旧数据库：id, name, count, is_system, created_at, raw_data (6列)
        // 通过检查第4列（索引4）的类型来判断是否有 is_pinned 字段
        let isPinned: Bool
        let createdAtIndex: Int32
        let rawDataIndex: Int32
        
        // 检查第4列是否存在且不是 NULL（如果是 INTEGER 类型，说明有 is_pinned 字段）
        if sqlite3_column_type(statement, 4) == SQLITE_INTEGER {
            // 新数据库结构，包含 is_pinned
            isPinned = sqlite3_column_int(statement, 4) != 0
            createdAtIndex = 5
            rawDataIndex = 6
        } else {
            // 旧数据库结构，没有 is_pinned（第4列是 created_at）
            isPinned = false
            createdAtIndex = 4
            rawDataIndex = 5
        }
        
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, createdAtIndex))
        
        // 解析 raw_data（可能为 NULL 或空字符串）
        var rawData: [String: Any]? = nil
        if sqlite3_column_type(statement, rawDataIndex) != SQLITE_NULL {
            if let rawDataText = sqlite3_column_text(statement, rawDataIndex) {
            let rawDataString = String(cString: rawDataText)
                if !rawDataString.isEmpty, let rawDataData = rawDataString.data(using: .utf8), !rawDataData.isEmpty {
                    do {
                rawData = try JSONSerialization.jsonObject(with: rawDataData, options: []) as? [String: Any]
                    } catch {
                        // 如果 JSON 解析失败，记录错误但不阻止文件夹加载
                        print("[Database] parseFolder: 解析 raw_data 失败 (id=\(id)): \(error)")
                    }
                }
            }
        }
        
        return Folder(
            id: id,
            name: name,
            count: count,
            isSystem: isSystem,
            isPinned: isPinned,
            createdAt: createdAt,
            rawData: rawData
        )
    }
    
    // MARK: - 离线操作队列
    
    /// 添加离线操作到队列
    // MARK: - 同步状态
    
    /// 保存同步状态
    /// 
    /// 同步状态是单行表（id = 1），每次保存都会替换现有记录
    /// 
    /// - Parameter status: 同步状态对象
    /// - Throws: DatabaseError（数据库操作失败）
    func saveSyncStatus(_ status: SyncStatus) throws {
        try dbQueue.sync(flags: .barrier) {
            print("[Database] 🔄 开始保存同步状态: syncTag=\(status.syncTag ?? "nil")")
            
            let sql = """
            INSERT OR REPLACE INTO sync_status (id, last_sync_time, sync_tag)
            VALUES (1, ?, ?);
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("[Database] ❌ SQL准备失败: \(errorMsg)")
                throw DatabaseError.prepareFailed(errorMsg)
            }
            
            if let lastSyncTime = status.lastSyncTime {
                sqlite3_bind_double(statement, 1, lastSyncTime.timeIntervalSince1970)
                print("[Database] 绑定 lastSyncTime: \(lastSyncTime)")
            } else {
                sqlite3_bind_null(statement, 1)
                print("[Database] 绑定 lastSyncTime: NULL")
            }
            
            if let syncTag = status.syncTag {
                sqlite3_bind_text(statement, 2, (syncTag as NSString).utf8String, -1, nil)
                print("[Database] 绑定 syncTag: \(syncTag)")
            } else {
                sqlite3_bind_null(statement, 2)
                print("[Database] 绑定 syncTag: NULL")
            }
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("[Database] ❌ SQL执行失败: \(errorMsg)")
                throw DatabaseError.executionFailed(errorMsg)
            }
            
            print("[Database] ✅ 保存同步状态成功: syncTag=\(status.syncTag ?? "nil")")
        }
    }
    
    /// 加载同步状态
    /// 
    /// - Returns: 同步状态对象，如果不存在则返回nil
    /// - Throws: DatabaseError（数据库操作失败）
    func loadSyncStatus() throws -> SyncStatus? {
        return try dbQueue.sync { () -> SyncStatus? in
            let sql = "SELECT last_sync_time, sync_tag FROM sync_status WHERE id = 1;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            
            var lastSyncTime: Date? = nil
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                lastSyncTime = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            }
            
            var syncTag: String? = nil
            if sqlite3_column_type(statement, 1) != SQLITE_NULL {
                if let textPointer = sqlite3_column_text(statement, 1) {
                    syncTag = String(cString: textPointer)
                }
            }
            
            return SyncStatus(
                lastSyncTime: lastSyncTime,
                syncTag: syncTag
            )
        }
    }
    
    /// 清除同步状态
    func clearSyncStatus() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM sync_status WHERE id = 1;"
            executeSQL(sql)
            print("[Database] 清除同步状态")
        }
    }
    
    // MARK: - 文件夹排序信息
    
    /// 保存文件夹排序信息
    /// 
    /// - Parameters:
    ///   - eTag: 排序信息的ETag（用于增量同步）
    ///   - orders: 文件夹ID的顺序数组
    /// - Throws: DatabaseError（数据库操作失败）
    func saveFolderSortInfo(eTag: String, orders: [String]) throws {
        try dbQueue.sync(flags: .barrier) {
            // 创建文件夹排序信息表（如果不存在）
            let createTableSQL = """
            CREATE TABLE IF NOT EXISTS folder_sort_info (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                e_tag TEXT NOT NULL,
                orders TEXT NOT NULL, -- JSON 数组
                updated_at REAL NOT NULL
            );
            """
            executeSQL(createTableSQL)
            
            // 插入或更新排序信息
            let sql = """
            INSERT OR REPLACE INTO folder_sort_info (id, e_tag, orders, updated_at)
            VALUES (1, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (eTag as NSString).utf8String, -1, nil)
            
            // orders 作为 JSON
            let ordersJSON = try JSONEncoder().encode(orders)
            sqlite3_bind_text(statement, 2, String(data: ordersJSON, encoding: .utf8), -1, nil)
            
            sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 保存文件夹排序信息: eTag=\(eTag), orders数量=\(orders.count)")
        }
    }
    
    /// 加载文件夹排序信息
    /// 
    /// - Returns: 包含eTag和orders的元组，如果不存在则返回nil
    /// - Throws: DatabaseError（数据库操作失败）
    func loadFolderSortInfo() throws -> (eTag: String, orders: [String])? {
        return try dbQueue.sync {
            // 检查表是否存在
            let tableExistsSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='folder_sort_info';"
            var tableExists = false
            
            var checkStatement: OpaquePointer?
            defer {
                if checkStatement != nil {
                    sqlite3_finalize(checkStatement)
                }
            }
            
            if sqlite3_prepare_v2(db, tableExistsSQL, -1, &checkStatement, nil) == SQLITE_OK {
                if sqlite3_step(checkStatement) == SQLITE_ROW {
                    tableExists = true
                }
            }
            
            if !tableExists {
                return nil
            }
            
            let sql = "SELECT e_tag, orders FROM folder_sort_info WHERE id = 1;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            
            guard let eTagText = sqlite3_column_text(statement, 0) else {
                return nil
            }
            let eTag = String(cString: eTagText)
            
            guard let ordersText = sqlite3_column_text(statement, 1) else {
                return nil
            }
            let ordersString = String(cString: ordersText)
            
            guard let ordersData = ordersString.data(using: .utf8) else {
                return nil
            }
            
            let orders = try JSONDecoder().decode([String].self, from: ordersData)
            
            print("[Database] 加载文件夹排序信息: eTag=\(eTag), orders数量=\(orders.count)")
            return (eTag: eTag, orders: orders)
        }
    }
    
    /// 清除文件夹排序信息
    /// 
    /// - Throws: DatabaseError（数据库操作失败）
    func clearFolderSortInfo() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM folder_sort_info WHERE id = 1;"
            executeSQL(sql)
            print("[Database] 清除文件夹排序信息")
        }
    }
    
    // MARK: - 统一操作队列（UnifiedOperations）
    
    /// 保存统一操作
    ///
    /// - Parameter operation: 笔记操作
    /// - Throws: DatabaseError（数据库操作失败）
    func saveUnifiedOperation(_ operation: NoteOperation) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO unified_operations (
                id, type, note_id, data, created_at, local_save_timestamp,
                status, priority, retry_count, next_retry_at, last_error, error_type, is_local_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (operation.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (operation.type.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (operation.noteId as NSString).utf8String, -1, nil)
            sqlite3_bind_blob(statement, 4, (operation.data as NSData).bytes, Int32(operation.data.count), nil)
            sqlite3_bind_int64(statement, 5, Int64(operation.createdAt.timeIntervalSince1970))
            
            if let localSaveTimestamp = operation.localSaveTimestamp {
                sqlite3_bind_int64(statement, 6, Int64(localSaveTimestamp.timeIntervalSince1970))
            } else {
                sqlite3_bind_null(statement, 6)
            }
            
            sqlite3_bind_text(statement, 7, (operation.status.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 8, Int32(operation.priority))
            sqlite3_bind_int(statement, 9, Int32(operation.retryCount))
            
            if let nextRetryAt = operation.nextRetryAt {
                sqlite3_bind_int64(statement, 10, Int64(nextRetryAt.timeIntervalSince1970))
            } else {
                sqlite3_bind_null(statement, 10)
            }
            
            if let lastError = operation.lastError {
                sqlite3_bind_text(statement, 11, (lastError as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 11)
            }
            
            if let errorType = operation.errorType {
                sqlite3_bind_text(statement, 12, (errorType.rawValue as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 12)
            }
            
            sqlite3_bind_int(statement, 13, operation.isLocalId ? 1 : 0)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 保存统一操作: \(operation.id), type: \(operation.type.rawValue), noteId: \(operation.noteId)")
        }
    }
    
    /// 获取所有统一操作
    ///
    /// 按优先级降序、创建时间升序排列
    ///
    /// - Returns: 操作数组
    /// - Throws: DatabaseError（数据库操作失败）
    func getAllUnifiedOperations() throws -> [NoteOperation] {
        return try dbQueue.sync {
            let sql = """
            SELECT id, type, note_id, data, created_at, local_save_timestamp,
                   status, priority, retry_count, next_retry_at, last_error, error_type, is_local_id
            FROM unified_operations
            ORDER BY priority DESC, created_at ASC;
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            var operations: [NoteOperation] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let operation = parseUnifiedOperation(from: statement) {
                    operations.append(operation)
                }
            }
            
            return operations
        }
    }
    
    /// 获取待处理的统一操作
    ///
    /// 返回状态为 pending 或 failed 的操作
    ///
    /// - Returns: 待处理操作数组
    /// - Throws: DatabaseError（数据库操作失败）
    func getPendingUnifiedOperations() throws -> [NoteOperation] {
        return try dbQueue.sync {
            let sql = """
            SELECT id, type, note_id, data, created_at, local_save_timestamp,
                   status, priority, retry_count, next_retry_at, last_error, error_type, is_local_id
            FROM unified_operations
            WHERE status IN ('pending', 'failed')
            ORDER BY priority DESC, created_at ASC;
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            var operations: [NoteOperation] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let operation = parseUnifiedOperation(from: statement) {
                    operations.append(operation)
                }
            }
            
            return operations
        }
    }
    
    /// 获取指定笔记的待处理操作
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 该笔记的待处理操作数组
    /// - Throws: DatabaseError（数据库操作失败）
    func getUnifiedOperations(for noteId: String) throws -> [NoteOperation] {
        return try dbQueue.sync {
            let sql = """
            SELECT id, type, note_id, data, created_at, local_save_timestamp,
                   status, priority, retry_count, next_retry_at, last_error, error_type, is_local_id
            FROM unified_operations
            WHERE note_id = ? AND status IN ('pending', 'failed')
            ORDER BY priority DESC, created_at ASC;
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (noteId as NSString).utf8String, -1, nil)
            
            var operations: [NoteOperation] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let operation = parseUnifiedOperation(from: statement) {
                    operations.append(operation)
                }
            }
            
            return operations
        }
    }
    
    /// 删除统一操作
    ///
    /// - Parameter operationId: 操作 ID
    /// - Throws: DatabaseError（数据库操作失败）
    func deleteUnifiedOperation(operationId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM unified_operations WHERE id = ?;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (operationId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 删除统一操作: \(operationId)")
        }
    }
    
    /// 更新操作中的笔记 ID
    ///
    /// 用于将临时 ID 更新为正式 ID
    ///
    /// - Parameters:
    ///   - oldNoteId: 旧的笔记 ID（临时 ID）
    ///   - newNoteId: 新的笔记 ID（正式 ID）
    /// - Throws: DatabaseError（数据库操作失败）
    func updateNoteIdInUnifiedOperations(oldNoteId: String, newNoteId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "UPDATE unified_operations SET note_id = ?, is_local_id = 0 WHERE note_id = ?;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (newNoteId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (oldNoteId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            let changes = sqlite3_changes(db)
            print("[Database] 更新操作中的笔记 ID: \(oldNoteId) -> \(newNoteId), 影响了 \(changes) 条操作")
        }
    }
    
    /// 清空所有统一操作
    ///
    /// - Throws: DatabaseError（数据库操作失败）
    func clearAllUnifiedOperations() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM unified_operations;"
            executeSQL(sql)
            print("[Database] 清空所有统一操作")
        }
    }
    
    /// 解析统一操作
    private func parseUnifiedOperation(from statement: OpaquePointer?) -> NoteOperation? {
        guard let statement = statement else { return nil }
        
        let id = String(cString: sqlite3_column_text(statement, 0))
        let typeString = String(cString: sqlite3_column_text(statement, 1))
        guard let type = OperationType(rawValue: typeString) else { return nil }
        
        let noteId = String(cString: sqlite3_column_text(statement, 2))
        
        // 获取 BLOB 数据
        let dataLength = sqlite3_column_bytes(statement, 3)
        guard let dataPointer = sqlite3_column_blob(statement, 3) else { return nil }
        let data = Data(bytes: dataPointer, count: Int(dataLength))
        
        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4)))
        
        var localSaveTimestamp: Date? = nil
        if sqlite3_column_type(statement, 5) != SQLITE_NULL {
            localSaveTimestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5)))
        }
        
        let statusString = String(cString: sqlite3_column_text(statement, 6))
        let status = OperationStatus(rawValue: statusString) ?? .pending
        
        let priority = Int(sqlite3_column_int(statement, 7))
        let retryCount = Int(sqlite3_column_int(statement, 8))
        
        var nextRetryAt: Date? = nil
        if sqlite3_column_type(statement, 9) != SQLITE_NULL {
            nextRetryAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9)))
        }
        
        var lastError: String? = nil
        if sqlite3_column_type(statement, 10) != SQLITE_NULL {
            if let errorText = sqlite3_column_text(statement, 10) {
                lastError = String(cString: errorText)
            }
        }
        
        var errorType: OperationErrorType? = nil
        if sqlite3_column_type(statement, 11) != SQLITE_NULL {
            if let errorTypeText = sqlite3_column_text(statement, 11) {
                errorType = OperationErrorType(rawValue: String(cString: errorTypeText))
            }
        }
        
        let isLocalId = sqlite3_column_int(statement, 12) != 0
        
        return NoteOperation(
            id: id,
            type: type,
            noteId: noteId,
            data: data,
            createdAt: createdAt,
            localSaveTimestamp: localSaveTimestamp,
            status: status,
            priority: priority,
            retryCount: retryCount,
            nextRetryAt: nextRetryAt,
            lastError: lastError,
            errorType: errorType,
            isLocalId: isLocalId
        )
    }
    
    // MARK: - 操作历史（OperationHistory）
    
    /// 保存操作到历史记录
    ///
    /// - Parameters:
    ///   - operation: 笔记操作
    ///   - completedAt: 完成时间
    /// - Throws: DatabaseError（数据库操作失败）
    func saveOperationHistory(_ operation: NoteOperation, completedAt: Date) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO operation_history (
                id, type, note_id, data, created_at, completed_at,
                status, retry_count, last_error, error_type
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (operation.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (operation.type.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (operation.noteId as NSString).utf8String, -1, nil)
            sqlite3_bind_blob(statement, 4, (operation.data as NSData).bytes, Int32(operation.data.count), nil)
            sqlite3_bind_int64(statement, 5, Int64(operation.createdAt.timeIntervalSince1970))
            sqlite3_bind_int64(statement, 6, Int64(completedAt.timeIntervalSince1970))
            sqlite3_bind_text(statement, 7, (operation.status.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 8, Int32(operation.retryCount))
            
            if let lastError = operation.lastError {
                sqlite3_bind_text(statement, 9, (lastError as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 9)
            }
            
            if let errorType = operation.errorType {
                sqlite3_bind_text(statement, 10, (errorType.rawValue as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 10)
            }
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    
    /// 获取历史操作记录
    ///
    /// - Parameter limit: 最大返回数量
    /// - Returns: 历史操作数组（按完成时间降序）
    /// - Throws: DatabaseError（数据库操作失败）
    func getOperationHistory(limit: Int = 100) throws -> [OperationHistoryEntry] {
        return try dbQueue.sync {
            let sql = """
            SELECT id, type, note_id, data, created_at, completed_at,
                   status, retry_count, last_error, error_type
            FROM operation_history
            ORDER BY completed_at DESC
            LIMIT ?;
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_int(statement, 1, Int32(limit))
            
            var entries: [OperationHistoryEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let entry = parseOperationHistory(from: statement) {
                    entries.append(entry)
                }
            }
            
            return entries
        }
    }
    
    /// 清空历史操作记录
    ///
    /// - Throws: DatabaseError（数据库操作失败）
    func clearOperationHistory() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM operation_history;"
            executeSQL(sql)
            print("[Database] 清空操作历史记录")
        }
    }
    
    /// 清理旧的历史记录（保留最近 N 条）
    ///
    /// - Parameter keepCount: 保留的记录数量
    /// - Throws: DatabaseError（数据库操作失败）
    func cleanupOldHistory(keepCount: Int = 100) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            DELETE FROM operation_history
            WHERE id NOT IN (
                SELECT id FROM operation_history
                ORDER BY completed_at DESC
                LIMIT ?
            );
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_int(statement, 1, Int32(keepCount))
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            let changes = sqlite3_changes(db)
            if changes > 0 {
                print("[Database] 清理了 \(changes) 条旧的历史记录")
            }
        }
    }
    
    /// 解析历史操作记录
    private func parseOperationHistory(from statement: OpaquePointer?) -> OperationHistoryEntry? {
        guard let statement = statement else { return nil }
        
        let id = String(cString: sqlite3_column_text(statement, 0))
        let typeString = String(cString: sqlite3_column_text(statement, 1))
        guard let type = OperationType(rawValue: typeString) else { return nil }
        
        let noteId = String(cString: sqlite3_column_text(statement, 2))
        
        // 获取 BLOB 数据
        let dataLength = sqlite3_column_bytes(statement, 3)
        guard let dataPointer = sqlite3_column_blob(statement, 3) else { return nil }
        let data = Data(bytes: dataPointer, count: Int(dataLength))
        
        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4)))
        let completedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5)))
        
        let statusString = String(cString: sqlite3_column_text(statement, 6))
        let status = OperationStatus(rawValue: statusString) ?? .completed
        
        let retryCount = Int(sqlite3_column_int(statement, 7))
        
        var lastError: String? = nil
        if sqlite3_column_type(statement, 8) != SQLITE_NULL {
            if let errorText = sqlite3_column_text(statement, 8) {
                lastError = String(cString: errorText)
            }
        }
        
        var errorType: OperationErrorType? = nil
        if sqlite3_column_type(statement, 9) != SQLITE_NULL {
            if let errorTypeText = sqlite3_column_text(statement, 9) {
                errorType = OperationErrorType(rawValue: String(cString: errorTypeText))
            }
        }
        
        return OperationHistoryEntry(
            id: id,
            type: type,
            noteId: noteId,
            data: data,
            createdAt: createdAt,
            completedAt: completedAt,
            status: status,
            retryCount: retryCount,
            lastError: lastError,
            errorType: errorType
        )
    }
    
    // MARK: - ID 映射表（IdMappings）
    
    // 注意：IdMapping 结构体已移至 IdMappingRegistry.swift 中定义为公共类型
    
    /// 保存 ID 映射
    ///
    /// - Parameter mapping: ID 映射记录
    /// - Throws: DatabaseError（数据库操作失败）
    func saveIdMapping(_ mapping: IdMapping) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO id_mappings (local_id, server_id, entity_type, created_at, completed)
            VALUES (?, ?, ?, ?, ?);
            """
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (mapping.localId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (mapping.serverId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (mapping.entityType as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(statement, 4, Int64(mapping.createdAt.timeIntervalSince1970))
            sqlite3_bind_int(statement, 5, mapping.completed ? 1 : 0)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 保存 ID 映射: \(mapping.localId) -> \(mapping.serverId)")
        }
    }
    
    /// 获取 ID 映射
    ///
    /// - Parameter localId: 临时 ID
    /// - Returns: ID 映射记录，如果不存在则返回 nil
    /// - Throws: DatabaseError（数据库操作失败）
    func getIdMapping(for localId: String) throws -> IdMapping? {
        return try dbQueue.sync {
            let sql = "SELECT local_id, server_id, entity_type, created_at, completed FROM id_mappings WHERE local_id = ?;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (localId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return nil
            }
            
            return parseIdMapping(from: statement)
        }
    }
    
    /// 获取所有未完成的 ID 映射
    ///
    /// - Returns: 未完成的 ID 映射数组
    /// - Throws: DatabaseError（数据库操作失败）
    func getIncompleteIdMappings() throws -> [IdMapping] {
        return try dbQueue.sync {
            let sql = "SELECT local_id, server_id, entity_type, created_at, completed FROM id_mappings WHERE completed = 0;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            var mappings: [IdMapping] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let mapping = parseIdMapping(from: statement) {
                    mappings.append(mapping)
                }
            }
            
            return mappings
        }
    }
    
    /// 标记 ID 映射为已完成
    ///
    /// - Parameter localId: 临时 ID
    /// - Throws: DatabaseError（数据库操作失败）
    func markIdMappingCompleted(localId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "UPDATE id_mappings SET completed = 1 WHERE local_id = ?;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            sqlite3_bind_text(statement, 1, (localId as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 标记 ID 映射完成: \(localId)")
        }
    }
    
    /// 删除已完成的 ID 映射
    ///
    /// - Throws: DatabaseError（数据库操作失败）
    func deleteCompletedIdMappings() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM id_mappings WHERE completed = 1;"
            executeSQL(sql)
            print("[Database] 删除已完成的 ID 映射")
        }
    }
    
    /// 解析 ID 映射
    private func parseIdMapping(from statement: OpaquePointer?) -> IdMapping? {
        guard let statement = statement else { return nil }
        
        let localId = String(cString: sqlite3_column_text(statement, 0))
        let serverId = String(cString: sqlite3_column_text(statement, 1))
        let entityType = String(cString: sqlite3_column_text(statement, 2))
        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 3)))
        let completed = sqlite3_column_int(statement, 4) != 0
        
        return IdMapping(
            localId: localId,
            serverId: serverId,
            entityType: entityType,
            createdAt: createdAt,
            completed: completed
        )
    }
}

// MARK: - 数据库错误

/// 数据库操作错误类型
/// 
/// 定义了所有可能的数据库操作错误，包括：
/// - 连接错误
/// - SQL 准备和执行错误
/// - 数据验证错误
/// - JSON 解析错误
/// - 事务错误
enum DatabaseError: Error {
    /// SQL 语句准备失败
    case prepareFailed(String)
    
    /// SQL 语句执行失败
    case executionFailed(String)
    
    /// 数据验证失败（字段类型或约束违反）
    case validationFailed(String)
    
    /// 数据库连接失败或已关闭
    case connectionFailed(String)
    
    /// JSON 解析失败
    case jsonParseFailed(String)
    
    /// 事务操作失败
    case transactionFailed(String)
    
    /// 数据格式无效
    case invalidData(String)
    
    /// 表或字段不存在
    case schemaError(String)
}

extension DatabaseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .prepareFailed(let message):
            return "SQL 准备失败: \(message)"
        case .executionFailed(let message):
            return "SQL 执行失败: \(message)"
        case .validationFailed(let message):
            return "数据验证失败: \(message)"
        case .connectionFailed(let message):
            return "数据库连接失败: \(message)"
        case .jsonParseFailed(let message):
            return "JSON 解析失败: \(message)"
        case .transactionFailed(let message):
            return "事务操作失败: \(message)"
        case .invalidData(let message):
            return "数据格式无效: \(message)"
        case .schemaError(let message):
            return "表结构错误: \(message)"
        }
    }
}
