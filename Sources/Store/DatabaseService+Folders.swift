import Foundation
import SQLite3

// MARK: - 文件夹操作

extension DatabaseService {
    /// 保存文件夹（插入或更新）
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

            var rawDataJSON: String?
            if let rawData = folder.rawData {
                let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [])
                rawDataJSON = String(data: jsonData, encoding: .utf8)
            }
            sqlite3_bind_text(statement, 7, rawDataJSON, -1, nil)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }

            LogService.shared.debug(.storage, "保存文件夹: \(folder.id)")
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
        try dbQueue.sync {
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

            LogService.shared.debug(.storage, "loadFolders: 处理了 \(rowCount) 行，成功解析 \(folders.count) 个文件夹")
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

            LogService.shared.debug(.storage, "删除文件夹: \(folderId)")
        }
    }

    /// 更新笔记的文件夹ID
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
            LogService.shared.debug(.storage, "更新笔记文件夹ID: \(oldFolderId) -> \(newFolderId), 影响了 \(changes) 条笔记")

            if newFolderId != "0", oldFolderId != "0" {
                try LocalStorageService.shared.renameFolderImageDirectory(oldFolderId: oldFolderId, newFolderId: newFolderId)
            }
        }
    }

    /// 保存文件夹排序信息
    func saveFolderSortInfo(eTag: String, orders: [String]) throws {
        try dbQueue.sync(flags: .barrier) {
            let createTableSQL = """
            CREATE TABLE IF NOT EXISTS folder_sort_info (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                e_tag TEXT NOT NULL,
                orders TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """
            executeSQL(createTableSQL)

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

            let ordersJSON = try JSONEncoder().encode(orders)
            sqlite3_bind_text(statement, 2, String(data: ordersJSON, encoding: .utf8), -1, nil)

            sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }

            LogService.shared.debug(.storage, "保存文件夹排序信息: eTag=\(eTag), orders数量=\(orders.count)")
        }
    }

    /// 加载文件夹排序信息
    func loadFolderSortInfo() throws -> (eTag: String, orders: [String])? {
        try dbQueue.sync {
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

            LogService.shared.debug(.storage, "加载文件夹排序信息: eTag=\(eTag), orders数量=\(orders.count)")
            return (eTag: eTag, orders: orders)
        }
    }

    /// 清除文件夹排序信息
    func clearFolderSortInfo() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM folder_sort_info WHERE id = 1;"
            executeSQL(sql)
            LogService.shared.debug(.storage, "清除文件夹排序信息")
        }
    }
}
