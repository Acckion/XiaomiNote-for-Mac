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
    
    /// 创建数据库表
    /// 
    /// 创建以下表：
    /// - notes: 笔记表
    /// - folders: 文件夹表
    /// - offline_operations: 离线操作队列表
    /// - sync_status: 同步状态表（单行表）
    /// - pending_deletions: 待删除笔记表
    private func createTables() {
        // 创建 notes 表
        let createNotesTable = """
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            folder_id TEXT NOT NULL DEFAULT '0',
            is_starred INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            tags TEXT, -- JSON 数组
            raw_data TEXT -- JSON 对象
        );
        """
        executeSQL(createNotesTable)
        
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
        
        // 创建 offline_operations 表
        let createOfflineOperationsTable = """
        CREATE TABLE IF NOT EXISTS offline_operations (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            note_id TEXT NOT NULL,
            data BLOB NOT NULL,
            timestamp REAL NOT NULL,
            priority INTEGER NOT NULL DEFAULT 0,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            status TEXT NOT NULL DEFAULT 'pending'
        );
        """
        executeSQL(createOfflineOperationsTable)
        
        // 迁移：为已存在的表添加新字段（如果字段不存在）
        migrateOfflineOperationsTable()
        
        // 迁移 notes 表，确保 raw_data 字段兼容性
        migrateNotesTable()
        
        // 创建 sync_status 表（单行表）
        let createSyncStatusTable = """
        CREATE TABLE IF NOT EXISTS sync_status (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            last_sync_time REAL,
            sync_tag TEXT
        );
        """
        executeSQL(createSyncStatusTable)
        
        // 创建 pending_deletions 表
        let createPendingDeletionsTable = """
        CREATE TABLE IF NOT EXISTS pending_deletions (
            note_id TEXT PRIMARY KEY,
            tag TEXT NOT NULL,
            purge INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL
        );
        """
        executeSQL(createPendingDeletionsTable)
        
        // 创建 pending_uploads 表（待上传注册表）
        let createPendingUploadsTable = """
        CREATE TABLE IF NOT EXISTS pending_uploads (
            note_id TEXT PRIMARY KEY,
            local_save_timestamp REAL NOT NULL,
            registered_at REAL NOT NULL
        );
        """
        executeSQL(createPendingUploadsTable)
        
        // 创建索引
        createIndexes()
    }
    
    private func createIndexes() {
        // notes 表索引
        executeSQL("CREATE INDEX IF NOT EXISTS idx_notes_folder_id ON notes(folder_id);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);")
        
        // offline_operations 表索引
        executeSQL("CREATE INDEX IF NOT EXISTS idx_offline_operations_timestamp ON offline_operations(timestamp);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_offline_operations_status ON offline_operations(status);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_offline_operations_priority ON offline_operations(priority DESC, timestamp ASC);")
    }
    
    /// 迁移 offline_operations 表，添加新字段
    /// 
    /// 为已存在的表添加以下字段（如果不存在）：
    /// - priority: 操作优先级
    /// - retry_count: 重试次数
    /// - last_error: 最后错误信息
    /// - status: 操作状态
    private func migrateOfflineOperationsTable() {
        // 检查并添加 priority 字段
        let addPriorityColumn = "ALTER TABLE offline_operations ADD COLUMN priority INTEGER NOT NULL DEFAULT 0;"
        executeSQL(addPriorityColumn, ignoreError: true)
        
        // 检查并添加 retry_count 字段
        let addRetryCountColumn = "ALTER TABLE offline_operations ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0;"
        executeSQL(addRetryCountColumn, ignoreError: true)
        
        // 检查并添加 last_error 字段
        let addLastErrorColumn = "ALTER TABLE offline_operations ADD COLUMN last_error TEXT;"
        executeSQL(addLastErrorColumn, ignoreError: true)
        
        // 检查并添加 status 字段
        let addStatusColumn = "ALTER TABLE offline_operations ADD COLUMN status TEXT NOT NULL DEFAULT 'pending';"
        executeSQL(addStatusColumn, ignoreError: true)
        
        // 更新所有现有记录的状态为 'pending'（如果 status 为空）
        let updateStatus = "UPDATE offline_operations SET status = 'pending' WHERE status IS NULL OR status = '';"
        executeSQL(updateStatus, ignoreError: true)
        
        print("[Database] 离线操作表迁移完成")
    }
    
    /// 迁移 notes 表，确保 raw_data 字段兼容性
    /// 
    /// 检查并修复 raw_data 字段的 JSON 格式问题
    /// 确保现有数据与新 Note 模型的编码/解码兼容
    private func migrateNotesTable() {
        print("[Database] 开始迁移 notes 表，检查字段兼容性")
        
        // 1. 检查是否有 raw_data 字段为 NULL 的记录
        let checkNullSQL = "SELECT COUNT(*) FROM notes WHERE raw_data IS NULL;"
        var nullCount = 0
        
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        if sqlite3_prepare_v2(db, checkNullSQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                nullCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        
        print("[Database] 有 \(nullCount) 条记录的 raw_data 字段为 NULL")
        
        // 2. 检查 raw_data 字段是否为有效的 JSON
        // 这里我们只是记录日志，不自动修复，因为修复可能破坏数据
        // 在实际加载时会使用更健壮的解析逻辑
        
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
    /// 
    /// - Parameter note: 要保存的笔记对象
    /// - Throws: DatabaseError（数据库操作失败）
    func saveNote(_ note: Note) throws {
        print("![[debug]] [Database] 保存笔记，ID: \(note.id), 标题: \(note.title), content长度: \(note.content.count)")
        
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO notes (id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            // 绑定参数
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
                INSERT OR REPLACE INTO notes (id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
                
                // 绑定参数
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
            let sql = "SELECT id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data FROM notes WHERE id = ?;"
            
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
            let sql = "SELECT id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data FROM notes ORDER BY updated_at DESC;"
            
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
    
    private func parseNote(from statement: OpaquePointer?) throws -> Note? {
        guard let statement = statement else {
            return nil
        }
        
        let id = String(cString: sqlite3_column_text(statement, 0))
        let title = String(cString: sqlite3_column_text(statement, 1))
        let content = String(cString: sqlite3_column_text(statement, 2))
        let folderId = String(cString: sqlite3_column_text(statement, 3))
        let isStarred = sqlite3_column_int(statement, 4) != 0
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        
        // 解析 tags
        var tags: [String] = []
        if let tagsText = sqlite3_column_text(statement, 7) {
            let tagsString = String(cString: tagsText)
            if !tagsString.isEmpty, let tagsData = tagsString.data(using: .utf8) {
                if let decodedTags = try? JSONDecoder().decode([String].self, from: tagsData) {
                    tags = decodedTags
                }
            }
        }
        
        // 解析 raw_data
        var rawData: [String: Any]? = nil
        if let rawDataText = sqlite3_column_text(statement, 8) {
            let rawDataString = String(cString: rawDataText)
            if !rawDataString.isEmpty, let rawDataData = rawDataString.data(using: .utf8) {
                rawData = try? JSONSerialization.jsonObject(with: rawDataData, options: []) as? [String: Any]
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
            rawData: rawData
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
    /// 
    /// 离线操作会在网络恢复时自动处理
    /// 
    /// - Parameter operation: 离线操作对象
    /// - Throws: DatabaseError（数据库操作失败）
    func addOfflineOperation(_ operation: OfflineOperation) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO offline_operations (id, type, note_id, data, timestamp, priority, retry_count, last_error, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
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
            sqlite3_bind_double(statement, 5, operation.timestamp.timeIntervalSince1970)
            sqlite3_bind_int(statement, 6, Int32(operation.priority))
            sqlite3_bind_int(statement, 7, Int32(operation.retryCount))
            
            if let lastError = operation.lastError {
                sqlite3_bind_text(statement, 8, (lastError as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 8)
            }
            
            sqlite3_bind_text(statement, 9, (operation.status.rawValue as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 添加离线操作: \(operation.id), type: \(operation.type.rawValue), priority: \(operation.priority), status: \(operation.status.rawValue)")
        }
    }
    
    /// 获取所有离线操作
    /// 
    /// 按优先级降序、时间戳升序排列（高优先级且早的在前面）
    /// 
    /// - Returns: 离线操作数组
    /// - Throws: DatabaseError（数据库操作失败）
    func getAllOfflineOperations() throws -> [OfflineOperation] {
        return try dbQueue.sync {
            // 确保数据库连接有效
            guard let db = db else {
                throw DatabaseError.prepareFailed("数据库连接无效")
            }
            
            let sql = "SELECT id, type, note_id, data, timestamp, priority, retry_count, last_error, status FROM offline_operations ORDER BY priority DESC, timestamp ASC;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("[Database] ❌ 准备SQL语句失败: \(errorMsg)")
                throw DatabaseError.prepareFailed(errorMsg)
            }
            
            var operations: [OfflineOperation] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let operation = try parseOfflineOperation(from: statement) {
                    operations.append(operation)
                }
            }
            
            return operations
        }
    }
    
    /// 删除离线操作
    func deleteOfflineOperation(operationId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM offline_operations WHERE id = ?;"
            
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
            
            print("[Database] 删除离线操作: \(operationId)")
        }
    }
    
    /// 清空所有离线操作
    func clearAllOfflineOperations() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM offline_operations;"
            executeSQL(sql)
            print("[Database] 清空所有离线操作")
        }
    }
    
    private func parseOfflineOperation(from statement: OpaquePointer?) throws -> OfflineOperation? {
        guard let statement = statement else { return nil }
        
        // 检查新字段是否存在（兼容旧数据和新数据）
        // 旧数据：id, type, note_id, data, timestamp (5列)
        // 新数据：id, type, note_id, data, timestamp, priority, retry_count, last_error, status (9列)
        // 通过检查第5列（索引5）的类型来判断是否有新字段
        // 如果是 INTEGER 类型，说明有 priority 字段（新数据）；如果是 NULL，说明是旧数据
        let hasNewFields = sqlite3_column_type(statement, 5) != SQLITE_NULL
        
        let id = String(cString: sqlite3_column_text(statement, 0))
        let typeString = String(cString: sqlite3_column_text(statement, 1))
        guard let type = OfflineOperationType(rawValue: typeString) else {
            return nil
        }
        let noteId = String(cString: sqlite3_column_text(statement, 2))
        
        // 获取 BLOB 数据
        let dataLength = sqlite3_column_bytes(statement, 3)
        let dataPointer = sqlite3_column_blob(statement, 3)
        guard let dataPointer = dataPointer else {
            return nil
        }
        let data = Data(bytes: dataPointer, count: Int(dataLength))
        
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        
        // 解析新字段（如果存在）
        if hasNewFields {
            let priority = Int(sqlite3_column_int(statement, 5))
            let retryCount = Int(sqlite3_column_int(statement, 6))
            
            var lastError: String? = nil
            if sqlite3_column_type(statement, 7) != SQLITE_NULL {
                if let errorText = sqlite3_column_text(statement, 7) {
                    lastError = String(cString: errorText)
                }
            }
            
            var status = OfflineOperationStatus.pending
            if sqlite3_column_type(statement, 8) != SQLITE_NULL {
                if let statusText = sqlite3_column_text(statement, 8) {
                    status = OfflineOperationStatus(rawValue: String(cString: statusText)) ?? .pending
                }
            }
            
            return OfflineOperation(
                id: id,
                type: type,
                noteId: noteId,
                data: data,
                timestamp: timestamp,
                priority: priority,
                retryCount: retryCount,
                lastError: lastError,
                status: status
            )
        } else {
            // 兼容旧数据，使用默认值
            return OfflineOperation(
                id: id,
                type: type,
                noteId: noteId,
                data: data,
                timestamp: timestamp,
                priority: OfflineOperation.calculatePriority(for: type),
                retryCount: 0,
                lastError: nil,
                status: .pending
            )
        }
    }
    
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
    
    // MARK: - 待删除笔记
    
    /// 保存待删除笔记
    func savePendingDeletion(_ deletion: PendingDeletion) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO pending_deletions (note_id, tag, purge, created_at)
            VALUES (?, ?, ?, ?);
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
            
            sqlite3_bind_text(statement, 1, (deletion.noteId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (deletion.tag as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 3, deletion.purge ? 1 : 0)
            sqlite3_bind_double(statement, 4, deletion.createdAt.timeIntervalSince1970)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 保存待删除笔记: \(deletion.noteId)")
        }
    }
    
    /// 获取所有待删除笔记
    func getAllPendingDeletions() throws -> [PendingDeletion] {
        return try dbQueue.sync {
            let sql = "SELECT note_id, tag, purge, created_at FROM pending_deletions ORDER BY created_at ASC;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            var deletions: [PendingDeletion] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let noteId = String(cString: sqlite3_column_text(statement, 0))
                let tag = String(cString: sqlite3_column_text(statement, 1))
                let purge = sqlite3_column_int(statement, 2) != 0
                let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                
                deletions.append(PendingDeletion(noteId: noteId, tag: tag, purge: purge, createdAt: createdAt))
            }
            
            return deletions
        }
    }
    
    /// 删除待删除笔记
    func deletePendingDeletion(noteId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM pending_deletions WHERE note_id = ?;"
            
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
            
            print("[Database] 删除待删除笔记: \(noteId)")
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
    
    // MARK: - 待上传注册表操作
    
    /// 保存待上传条目
    /// 
    /// - Parameter entry: 待上传条目
    /// - Throws: DatabaseError（数据库操作失败）
    func savePendingUpload(_ entry: PendingUploadEntry) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO pending_uploads (note_id, local_save_timestamp, registered_at)
            VALUES (?, ?, ?);
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
            
            sqlite3_bind_text(statement, 1, (entry.noteId as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 2, entry.localSaveTimestamp.timeIntervalSince1970)
            sqlite3_bind_double(statement, 3, entry.registeredAt.timeIntervalSince1970)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    
    /// 删除待上传条目
    /// 
    /// - Parameter noteId: 笔记 ID
    /// - Throws: DatabaseError（数据库操作失败）
    func deletePendingUpload(noteId: String) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM pending_uploads WHERE note_id = ?;"
            
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
        }
    }
    
    /// 获取所有待上传条目
    /// 
    /// - Returns: 待上传条目数组
    /// - Throws: DatabaseError（数据库操作失败）
    func getAllPendingUploads() throws -> [PendingUploadEntry] {
        return try dbQueue.sync {
            let sql = "SELECT note_id, local_save_timestamp, registered_at FROM pending_uploads;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            var entries: [PendingUploadEntry] = []
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let noteId = String(cString: sqlite3_column_text(statement, 0))
                let localSaveTimestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
                let registeredAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                
                let entry = PendingUploadEntry(
                    noteId: noteId,
                    localSaveTimestamp: localSaveTimestamp,
                    registeredAt: registeredAt
                )
                entries.append(entry)
            }
            
            return entries
        }
    }
    
    /// 清空所有待上传条目
    /// 
    /// - Throws: DatabaseError（数据库操作失败）
    func clearAllPendingUploads() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM pending_uploads;"
            executeSQL(sql)
        }
    }
}

// MARK: - 数据库错误

enum DatabaseError: Error {
    case prepareFailed(String)
    case executionFailed(String)
    case invalidData(String)
    case connectionFailed(String)
}
