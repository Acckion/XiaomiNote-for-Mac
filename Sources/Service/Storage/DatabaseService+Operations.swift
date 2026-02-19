import Foundation
import SQLite3

// MARK: - 统一操作队列（UnifiedOperations）

extension DatabaseService {
    /// 保存统一操作
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
        }
    }

    /// 获取所有统一操作
    func getAllUnifiedOperations() throws -> [NoteOperation] {
        try dbQueue.sync {
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
    func getPendingUnifiedOperations() throws -> [NoteOperation] {
        try dbQueue.sync {
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
    func getUnifiedOperations(for noteId: String) throws -> [NoteOperation] {
        try dbQueue.sync {
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
        }
    }

    /// 更新操作中的笔记 ID
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
            LogService.shared.debug(.storage, "更新操作中的笔记 ID: \(oldNoteId) -> \(newNoteId), 影响了 \(changes) 条操作")
        }
    }

    /// 清空所有统一操作
    func clearAllUnifiedOperations() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM unified_operations;"
            executeSQL(sql)
        }
    }
}

// MARK: - 操作历史（OperationHistory）

extension DatabaseService {
    /// 保存操作到历史记录
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
    func getOperationHistory(limit: Int = 100) throws -> [OperationHistoryEntry] {
        try dbQueue.sync {
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
    func clearOperationHistory() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM operation_history;"
            executeSQL(sql)
        }
    }

    /// 清理旧的历史记录（保留最近 N 条）
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
                LogService.shared.debug(.storage, "清理了 \(changes) 条旧的历史记录")
            }
        }
    }
}

// MARK: - ID 映射表（IdMappings）

extension DatabaseService {
    /// 保存 ID 映射
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

            LogService.shared.debug(.storage, "保存 ID 映射: \(mapping.localId) -> \(mapping.serverId)")
        }
    }

    /// 获取 ID 映射
    func getIdMapping(for localId: String) throws -> IdMapping? {
        try dbQueue.sync {
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
    func getIncompleteIdMappings() throws -> [IdMapping] {
        try dbQueue.sync {
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

            LogService.shared.debug(.storage, "标记 ID 映射完成: \(localId)")
        }
    }

    /// 删除已完成的 ID 映射
    func deleteCompletedIdMappings() throws {
        try dbQueue.sync(flags: .barrier) {
            let sql = "DELETE FROM id_mappings WHERE completed = 1;"
            executeSQL(sql)
        }
    }
}
