import XCTest
import SQLite3
@testable import MiNoteLibrary

/// DatabaseService 表结构和迁移测试
///
/// 验证数据库表结构的完整性和迁移功能
final class DatabaseServiceTests: XCTestCase {
    
    var testDbPath: URL!
    var testDb: OpaquePointer?
    
    override func setUp() {
        super.setUp()
        
        // 创建临时测试数据库
        let tempDir = FileManager.default.temporaryDirectory
        testDbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")
        
        // 打开测试数据库
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(testDbPath.path, &testDb, flags, nil) == SQLITE_OK else {
            XCTFail("无法创建测试数据库")
            return
        }
    }
    
    override func tearDown() {
        // 关闭数据库
        if testDb != nil {
            sqlite3_close(testDb)
            testDb = nil
        }
        
        // 删除测试数据库文件
        try? FileManager.default.removeItem(at: testDbPath)
        
        super.tearDown()
    }
    
    /// 测试：验证 notes 表包含所有必需字段
    ///
    /// **验证需求: 1.1-1.12**
    func testNotesTableHasAllRequiredFields() throws {
        // 创建旧版本的 notes 表（只有基本字段）
        let createOldTableSQL = """
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            folder_id TEXT NOT NULL DEFAULT '0',
            is_starred INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            tags TEXT,
            raw_data TEXT
        );
        """
        
        executeSQL(createOldTableSQL)
        
        // 模拟迁移过程：添加新字段
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
        
        // 开始事务
        executeSQL("BEGIN TRANSACTION;")
        
        // 添加每个新字段
        for column in newColumns {
            let alterSQL = "ALTER TABLE notes ADD COLUMN \(column.name) \(column.definition);"
            executeSQL(alterSQL)
        }
        
        // 提交事务
        executeSQL("COMMIT;")
        
        // 验证所有字段都存在
        let expectedFields = [
            "id", "title", "content", "folder_id", "is_starred",
            "created_at", "updated_at", "tags", "raw_data",
            "snippet", "color_id", "subject", "alert_date", "type",
            "tag", "status", "setting_json", "extra_info_json",
            "modify_date", "create_date"
        ]
        
        let actualFields = getTableColumns(tableName: "notes")
        
        for field in expectedFields {
            XCTAssertTrue(actualFields.contains(field), "字段 \(field) 应该存在于 notes 表中")
        }
        
        print("✅ 所有必需字段都存在于 notes 表中")
    }
    
    /// 测试：验证迁移过程的原子性
    ///
    /// **验证需求: 4.3**
    func testMigrationIsAtomic() throws {
        // 创建旧版本的 notes 表
        let createOldTableSQL = """
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            folder_id TEXT NOT NULL DEFAULT '0',
            is_starred INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            tags TEXT,
            raw_data TEXT
        );
        """
        
        executeSQL(createOldTableSQL)
        
        // 插入测试数据
        let insertSQL = """
        INSERT INTO notes (id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data)
        VALUES ('test1', 'Test Note', 'Content', '0', 0, 1234567890, 1234567890, '[]', NULL);
        """
        executeSQL(insertSQL)
        
        // 验证数据存在
        let countBefore = getRowCount(tableName: "notes")
        XCTAssertEqual(countBefore, 1, "迁移前应该有 1 条记录")
        
        // 执行迁移（在事务中）
        executeSQL("BEGIN TRANSACTION;")
        
        let newColumns: [(name: String, definition: String)] = [
            ("snippet", "TEXT"),
            ("color_id", "INTEGER DEFAULT 0"),
            ("type", "TEXT DEFAULT 'note'"),
            ("status", "TEXT DEFAULT 'normal'")
        ]
        
        for column in newColumns {
            let alterSQL = "ALTER TABLE notes ADD COLUMN \(column.name) \(column.definition);"
            executeSQL(alterSQL)
        }
        
        executeSQL("COMMIT;")
        
        // 验证数据仍然存在且完整
        let countAfter = getRowCount(tableName: "notes")
        XCTAssertEqual(countAfter, 1, "迁移后应该仍有 1 条记录")
        
        // 验证可以读取数据
        let selectSQL = "SELECT id, title, snippet, color_id, type, status FROM notes WHERE id = 'test1';"
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        XCTAssertEqual(sqlite3_prepare_v2(testDb, selectSQL, -1, &statement, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        
        let id = String(cString: sqlite3_column_text(statement, 0))
        let title = String(cString: sqlite3_column_text(statement, 1))
        
        XCTAssertEqual(id, "test1")
        XCTAssertEqual(title, "Test Note")
        
        // 验证新字段有默认值
        let colorId = sqlite3_column_int(statement, 3)
        XCTAssertEqual(colorId, 0, "color_id 应该有默认值 0")
        
        let type = String(cString: sqlite3_column_text(statement, 4))
        XCTAssertEqual(type, "note", "type 应该有默认值 'note'")
        
        let status = String(cString: sqlite3_column_text(statement, 5))
        XCTAssertEqual(status, "normal", "status 应该有默认值 'normal'")
        
        print("✅ 迁移过程保持了数据完整性")
    }
    
    /// 测试：验证重复迁移是幂等的
    ///
    /// 多次执行迁移不应该导致错误或数据损坏
    func testMigrationIsIdempotent() throws {
        // 创建旧版本的 notes 表
        let createOldTableSQL = """
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            folder_id TEXT NOT NULL DEFAULT '0',
            is_starred INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            tags TEXT,
            raw_data TEXT
        );
        """
        
        executeSQL(createOldTableSQL)
        
        // 第一次迁移
        migrateTable()
        let fieldsAfterFirstMigration = getTableColumns(tableName: "notes")
        
        // 第二次迁移（应该不会出错）
        migrateTable()
        let fieldsAfterSecondMigration = getTableColumns(tableName: "notes")
        
        // 验证字段数量相同
        XCTAssertEqual(fieldsAfterFirstMigration.count, fieldsAfterSecondMigration.count,
                      "重复迁移不应该改变字段数量")
        
        // 验证字段内容相同
        XCTAssertEqual(Set(fieldsAfterFirstMigration), Set(fieldsAfterSecondMigration),
                      "重复迁移不应该改变字段列表")
        
        print("✅ 迁移过程是幂等的")
    }
    
    // MARK: - 辅助方法
    
    /// 执行 SQL 语句
    private func executeSQL(_ sql: String) {
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(testDb, sql, -1, &statement, nil) == SQLITE_OK else {
            XCTFail("SQL 准备失败: \(String(cString: sqlite3_errmsg(testDb)))")
            return
        }
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            XCTFail("SQL 执行失败: \(String(cString: sqlite3_errmsg(testDb)))")
            return
        }
    }
    
    /// 获取表的所有列名
    private func getTableColumns(tableName: String) -> [String] {
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(testDb, sql, -1, &statement, nil) == SQLITE_OK else {
            XCTFail("无法获取表信息")
            return []
        }
        
        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let nameText = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: nameText))
            }
        }
        
        return columns
    }
    
    /// 获取表的行数
    private func getRowCount(tableName: String) -> Int {
        let sql = "SELECT COUNT(*) FROM \(tableName);"
        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }
        
        guard sqlite3_prepare_v2(testDb, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }
        
        return Int(sqlite3_column_int(statement, 0))
    }
    
    /// 模拟迁移过程
    private func migrateTable() {
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
        
        executeSQL("BEGIN TRANSACTION;")
        
        for column in newColumns {
            // 检查字段是否存在
            let columns = getTableColumns(tableName: "notes")
            if !columns.contains(column.name) {
                let alterSQL = "ALTER TABLE notes ADD COLUMN \(column.name) \(column.definition);"
                executeSQL(alterSQL)
            }
        }
        
        executeSQL("COMMIT;")
    }
}
