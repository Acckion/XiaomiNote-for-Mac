import Foundation
import SQLite3

/// SQLite 数据库服务
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
            guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
                print("[Database] 无法打开数据库: \(String(cString: sqlite3_errmsg(db)))")
                return
            }
            
            print("[Database] 数据库已打开: \(dbPath.path)")
            
            // 创建表
            createTables()
        }
    }
    
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
            timestamp REAL NOT NULL
        );
        """
        executeSQL(createOfflineOperationsTable)
        
        // 创建 sync_status 表（单行表）
        let createSyncStatusTable = """
        CREATE TABLE IF NOT EXISTS sync_status (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            last_sync_time REAL,
            sync_tag TEXT,
            synced_note_ids TEXT, -- JSON 数组
            last_page_sync_time REAL
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
        
        // 创建索引
        createIndexes()
    }
    
    private func createIndexes() {
        // notes 表索引
        executeSQL("CREATE INDEX IF NOT EXISTS idx_notes_folder_id ON notes(folder_id);")
        executeSQL("CREATE INDEX IF NOT EXISTS idx_notes_updated_at ON notes(updated_at);")
        
        // offline_operations 表索引
        executeSQL("CREATE INDEX IF NOT EXISTS idx_offline_operations_timestamp ON offline_operations(timestamp);")
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
    
    /// 保存笔记
    func saveNote(_ note: Note) throws {
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
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
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
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 保存笔记: \(note.id)")
        }
    }
    
    /// 加载笔记
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
            
            return try parseNote(from: statement)
        }
    }
    
    /// 获取所有笔记
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
                print("[Database] getAllNotes: 处理第 \(rowCount) 行")
                do {
                    if let note = try parseNote(from: statement) {
                        notes.append(note)
                        print("[Database] getAllNotes: 成功解析并添加笔记 id=\(note.id)")
                    } else {
                        print("[Database] getAllNotes: ⚠️ parseNote 返回 nil，跳过该行")
                    }
                } catch {
                    print("[Database] getAllNotes: ⚠️ 解析笔记时出错: \(error)")
                    print("[Database] getAllNotes: 错误详情: \(error.localizedDescription)")
                }
            }
            
            print("[Database] getAllNotes: 总共处理 \(rowCount) 行，成功解析 \(notes.count) 条笔记")
            return notes
        }
    }
    
    /// 删除笔记
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
            print("[Database] parseNote: statement 为 nil")
            return nil
        }
        
        let id = String(cString: sqlite3_column_text(statement, 0))
        print("[Database] parseNote: 开始解析笔记 id=\(id)")
        
        let title = String(cString: sqlite3_column_text(statement, 1))
        let content = String(cString: sqlite3_column_text(statement, 2))
        let folderId = String(cString: sqlite3_column_text(statement, 3))
        let isStarred = sqlite3_column_int(statement, 4) != 0
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        
        print("[Database] parseNote: 基础字段解析完成 - title=\(title), content长度=\(content.count), folderId=\(folderId)")
        
        // 解析 tags
        var tags: [String] = []
        if let tagsText = sqlite3_column_text(statement, 7) {
            let tagsString = String(cString: tagsText)
            print("[Database] parseNote: tags 字段存在，长度=\(tagsString.count), 内容=\(tagsString.prefix(100))")
            if !tagsString.isEmpty, let tagsData = tagsString.data(using: .utf8) {
                if let decodedTags = try? JSONDecoder().decode([String].self, from: tagsData) {
                    tags = decodedTags
                    print("[Database] parseNote: tags 解析成功，数量=\(tags.count)")
                } else {
                    print("[Database] parseNote: ⚠️ tags JSON 解析失败，tagsString=\(tagsString)")
                }
            } else {
                print("[Database] parseNote: tags 字段为空或无法转换为 Data")
            }
        } else {
            print("[Database] parseNote: tags 字段为 NULL")
        }
        
        // 解析 raw_data
        var rawData: [String: Any]? = nil
        if let rawDataText = sqlite3_column_text(statement, 8) {
            let rawDataString = String(cString: rawDataText)
            let rawDataLength = rawDataString.count
            print("[Database] parseNote: raw_data 字段存在，长度=\(rawDataLength)")
            
            if !rawDataString.isEmpty, let rawDataData = rawDataString.data(using: .utf8) {
                if let parsedRawData = try? JSONSerialization.jsonObject(with: rawDataData, options: []) as? [String: Any] {
                    rawData = parsedRawData
                    print("[Database] parseNote: raw_data JSON 解析成功，包含 \(parsedRawData.count) 个键")
                } else {
                    print("[Database] parseNote: ⚠️ raw_data JSON 解析失败")
                    print("[Database] parseNote: raw_data 前200字符: \(rawDataString.prefix(200))")
                    if rawDataLength > 200 {
                        print("[Database] parseNote: raw_data 后200字符: \(rawDataString.suffix(200))")
                    }
                }
            } else {
                print("[Database] parseNote: raw_data 字段为空或无法转换为 Data")
            }
        } else {
            print("[Database] parseNote: raw_data 字段为 NULL")
        }
        
        let note = Note(
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
        
        print("[Database] parseNote: 笔记解析完成 id=\(id), title=\(title)")
        return note
    }
    
    // MARK: - 文件夹操作
    
    /// 保存文件夹
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
    func saveFolders(_ folders: [Folder]) throws {
        for folder in folders {
            try saveFolder(folder)
        }
    }
    
    /// 加载所有文件夹
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
                do {
                    if let folder = try parseFolder(from: statement) {
                        folders.append(folder)
                        print("[Database] loadFolders: 成功解析文件夹 id=\(folder.id), name=\(folder.name), isSystem=\(folder.isSystem)")
                    } else {
                        print("[Database] loadFolders: ⚠️ parseFolder 返回 nil，跳过该行")
                    }
                } catch {
                    print("[Database] loadFolders: ⚠️ 解析文件夹时出错: \(error)")
                    // 继续处理下一行，不中断整个加载过程
                }
            }
            
            print("[Database] loadFolders: 总共处理 \(rowCount) 行，成功解析 \(folders.count) 个文件夹")
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
    
    private func parseFolder(from statement: OpaquePointer?) throws -> Folder? {
        guard let statement = statement else { return nil }
        
        let columnCount = sqlite3_column_count(statement)
        let id = String(cString: sqlite3_column_text(statement, 0))
        let name = String(cString: sqlite3_column_text(statement, 1))
        let count = Int(sqlite3_column_int(statement, 2))
        let isSystem = sqlite3_column_int(statement, 3) != 0
        
        // 检查 is_pinned 列是否存在（兼容旧数据库）
        // 新数据库：id, name, count, is_system, is_pinned, created_at, raw_data (7列)
        // 旧数据库：id, name, count, is_system, created_at, raw_data (6列)
        let isPinned: Bool
        let createdAtIndex: Int32
        let rawDataIndex: Int32
        
        if columnCount >= 7 {
            // 新数据库结构，包含 is_pinned
            isPinned = sqlite3_column_int(statement, 4) != 0
            createdAtIndex = 5
            rawDataIndex = 6
        } else {
            // 旧数据库结构，没有 is_pinned
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
    
    /// 添加离线操作
    func addOfflineOperation(_ operation: OfflineOperation) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO offline_operations (id, type, note_id, data, timestamp)
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
            
            sqlite3_bind_text(statement, 1, (operation.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (operation.type.rawValue as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 3, (operation.noteId as NSString).utf8String, -1, nil)
            sqlite3_bind_blob(statement, 4, (operation.data as NSData).bytes, Int32(operation.data.count), nil)
            sqlite3_bind_double(statement, 5, operation.timestamp.timeIntervalSince1970)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 添加离线操作: \(operation.id)")
        }
    }
    
    /// 获取所有离线操作
    func getAllOfflineOperations() throws -> [OfflineOperation] {
        return try dbQueue.sync {
            let sql = "SELECT id, type, note_id, data, timestamp FROM offline_operations ORDER BY timestamp ASC;"
            
            var statement: OpaquePointer?
            defer {
                if statement != nil {
                    sqlite3_finalize(statement)
                }
            }
            
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
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
        
        return OfflineOperation(
            id: id,
            type: type,
            noteId: noteId,
            data: data,
            timestamp: timestamp
        )
    }
    
    // MARK: - 同步状态
    
    /// 保存同步状态
    func saveSyncStatus(_ status: SyncStatus) throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO sync_status (id, last_sync_time, sync_tag, synced_note_ids, last_page_sync_time)
            VALUES (1, ?, ?, ?, ?);
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
            
            if let lastSyncTime = status.lastSyncTime {
                sqlite3_bind_double(statement, 1, lastSyncTime.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 1)
            }
            
            if let syncTag = status.syncTag {
                sqlite3_bind_text(statement, 2, (syncTag as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, 2)
            }
            
            // synced_note_ids 作为 JSON
            let syncedNoteIdsJSON = try JSONEncoder().encode(status.syncedNoteIds)
            sqlite3_bind_text(statement, 3, String(data: syncedNoteIdsJSON, encoding: .utf8), -1, nil)
            
            if let lastPageSyncTime = status.lastPageSyncTime {
                sqlite3_bind_double(statement, 4, lastPageSyncTime.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(statement, 4)
            }
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
            
            print("[Database] 保存同步状态")
        }
    }
    
    /// 加载同步状态
    func loadSyncStatus() throws -> SyncStatus? {
        return try dbQueue.sync {
            let sql = "SELECT last_sync_time, sync_tag, synced_note_ids, last_page_sync_time FROM sync_status WHERE id = 1;"
            
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
                syncTag = String(cString: sqlite3_column_text(statement, 1))
            }
            
            var syncedNoteIds: [String] = []
            if sqlite3_column_type(statement, 2) != SQLITE_NULL {
                let syncedNoteIdsString = String(cString: sqlite3_column_text(statement, 2))
                if let syncedNoteIdsData = syncedNoteIdsString.data(using: .utf8) {
                    syncedNoteIds = try JSONDecoder().decode([String].self, from: syncedNoteIdsData)
                }
            }
            
            var lastPageSyncTime: Date? = nil
            if sqlite3_column_type(statement, 3) != SQLITE_NULL {
                lastPageSyncTime = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            }
            
            return SyncStatus(
                lastSyncTime: lastSyncTime,
                syncTag: syncTag,
                syncedNoteIds: syncedNoteIds,
                lastPageSyncTime: lastPageSyncTime
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
}

// MARK: - 数据库错误

enum DatabaseError: Error {
    case prepareFailed(String)
    case executionFailed(String)
    case invalidData(String)
}


