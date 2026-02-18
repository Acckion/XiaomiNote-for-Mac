import Foundation
import SQLite3

// MARK: - 同步状态

extension DatabaseService {
    /// 保存同步状态
    ///
    /// 同步状态是单行表（id = 1），每次保存都会替换现有记录
    ///
    /// - Parameter status: 同步状态对象
    /// - Throws: DatabaseError（数据库操作失败）
    func saveSyncStatus(_ status: SyncStatus) throws {
        print("[[调试]] 开始保存同步状态: syncTag=\(status.syncTag ?? "nil")")

        try dbQueue.sync(flags: .barrier) {
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
                print("[[调试]] SQL准备失败: \(errorMsg)")
                throw DatabaseError.prepareFailed(errorMsg)
            }

            if let lastSyncTime = status.lastSyncTime {
                sqlite3_bind_double(statement, 1, lastSyncTime.timeIntervalSince1970)
                print("[[调试]] 绑定 lastSyncTime: \(lastSyncTime)")
            } else {
                sqlite3_bind_null(statement, 1)
                print("[[调试]] 绑定 lastSyncTime: NULL")
            }

            if let syncTag = status.syncTag {
                sqlite3_bind_text(statement, 2, (syncTag as NSString).utf8String, -1, nil)
                print("[[调试]] 绑定 syncTag: \(syncTag)")
            } else {
                sqlite3_bind_null(statement, 2)
                print("[[调试]] 绑定 syncTag: NULL")
            }

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("[[调试]] SQL执行失败: \(errorMsg)")
                throw DatabaseError.executionFailed(errorMsg)
            }

            print("[[调试]] 保存同步状态成功: syncTag=\(status.syncTag ?? "nil")")
        }
    }

    /// 加载同步状态
    ///
    /// - Returns: 同步状态对象，如果不存在则返回nil
    /// - Throws: DatabaseError（数据库操作失败）
    func loadSyncStatus() throws -> SyncStatus? {
        try dbQueue.sync {
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

            var lastSyncTime: Date?
            if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                lastSyncTime = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            }

            var syncTag: String?
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
    func clearSyncStatus() {
        dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM sync_status WHERE id = 1;"
            executeSQL(sql)
            print("[[调试]] 清除同步状态")
        }
    }
}
