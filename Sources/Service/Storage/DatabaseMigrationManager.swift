import Foundation
import SQLite3

/// 数据库迁移错误
enum MigrationError: Error {
    case tableCreationFailed(String)
    case versionQueryFailed(String)
    case migrationFailed(version: Int, reason: String)
    case transactionFailed(String)
}

/// 单个迁移版本
struct Migration: Sendable {
    let version: Int
    let description: String
    let sql: String
}

/// 数据库迁移管理器
///
/// 负责版本化迁移的核心组件，管理有序 Migration 列表，执行版本化迁移。
/// 独立于 DatabaseService，便于单独测试。
enum DatabaseMigrationManager {
    /// 所有迁移，按版本号升序排列
    static let migrations: [Migration] = [
        Migration(
            version: 1,
            description: "添加 folders.is_pinned 字段",
            sql: "ALTER TABLE folders ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;"
        ),
    ]

    /// 执行所有未执行的迁移
    ///
    /// - Parameter db: SQLite 数据库连接指针
    /// - Throws: MigrationError
    static func runPendingMigrations(db: OpaquePointer?) throws {
        guard let db else {
            throw MigrationError.migrationFailed(version: 0, reason: "数据库连接为空")
        }

        // 确保迁移表存在
        try ensureMigrationsTable(db: db)

        // 获取当前版本
        let currentVer = try currentVersion(db: db)
        print("[[调试]] 当前数据库版本: \(currentVer)")

        // 筛选待执行的迁移
        let pendingMigrations = migrations.filter { $0.version > currentVer }

        if pendingMigrations.isEmpty {
            print("[[调试]] 数据库已是最新版本，无需迁移")
            return
        }

        print("[[调试]] 待执行迁移数量: \(pendingMigrations.count)")

        // 按版本号升序执行迁移
        for migration in pendingMigrations.sorted(by: { $0.version < $1.version }) {
            try execute(migration, db: db)
        }

        print("[[调试]] 所有迁移执行完成")
    }

    /// 确保 schema_migrations 表存在
    private static func ensureMigrationsTable(db: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            executed_at REAL NOT NULL
        );
        """

        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw MigrationError.tableCreationFailed(errorMsg)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw MigrationError.tableCreationFailed(errorMsg)
        }
    }

    /// 获取已执行的最大版本号
    ///
    /// - Parameter db: SQLite 数据库连接指针
    /// - Returns: 当前版本号，表为空时返回 0
    private static func currentVersion(db: OpaquePointer) throws -> Int {
        let sql = "SELECT MAX(version) FROM schema_migrations;"

        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw MigrationError.versionQueryFailed(errorMsg)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        // MAX 返回 NULL 时表示表为空
        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    /// 在事务中执行单个迁移
    private static func execute(_ migration: Migration, db: OpaquePointer) throws {
        print("[[调试]] 执行迁移 v\(migration.version): \(migration.description)")

        // 开始事务
        guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw MigrationError.transactionFailed("BEGIN 失败: \(errorMsg)")
        }

        do {
            // 执行迁移 SQL
            // 迁移 SQL 可能包含多条语句，需要逐条执行
            let statements = migration.sql.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            for stmt in statements where !stmt.isEmpty {
                let result = sqlite3_exec(db, stmt + ";", nil, nil, nil)
                if result != SQLITE_OK {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    throw MigrationError.migrationFailed(version: migration.version, reason: errorMsg)
                }
            }

            // 记录迁移版本
            try recordMigration(version: migration.version, db: db)

            // 提交事务
            guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                throw MigrationError.transactionFailed("COMMIT 失败: \(errorMsg)")
            }

            print("[[调试]] 迁移 v\(migration.version) 执行成功")
        } catch {
            // 回滚事务
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            print("[[调试]] 迁移 v\(migration.version) 执行失败，已回滚: \(error)")
            throw error
        }
    }

    /// 记录迁移版本到 schema_migrations 表
    private static func recordMigration(version: Int, db: OpaquePointer) throws {
        let sql = "INSERT INTO schema_migrations (version, executed_at) VALUES (?, ?);"

        var statement: OpaquePointer?
        defer {
            if statement != nil {
                sqlite3_finalize(statement)
            }
        }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw MigrationError.migrationFailed(version: version, reason: "记录版本失败: \(errorMsg)")
        }

        sqlite3_bind_int(statement, 1, Int32(version))
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw MigrationError.migrationFailed(version: version, reason: "记录版本失败: \(errorMsg)")
        }
    }
}
