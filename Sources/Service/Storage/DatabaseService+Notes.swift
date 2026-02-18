import Foundation
import SQLite3

// MARK: - 笔记操作

extension DatabaseService {
    /// 保存笔记（插入或更新）
    ///
    /// 如果笔记已存在，则更新；否则插入新记录
    /// 包含数据验证，确保字段类型和约束正确
    ///
    /// - Parameter note: 要保存的笔记对象
    /// - Throws: DatabaseError（数据库操作失败或数据验证失败）
    func saveNote(_ note: Note) throws {
        print("[[调试]] 保存笔记，ID: \(note.id), 标题: \(note.title), content长度: \(note.content.count)")

        try validateNote(note)

        try dbQueue.sync(flags: .barrier) {
            let sql = """
            INSERT OR REPLACE INTO notes (
                id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                snippet, color_id, subject, alert_date, type, tag, status,
                setting_json, extra_info_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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

            try bindNote(note, to: statement!)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                print("[[调试]] SQL执行失败: \(errorMsg)")
                throw DatabaseError.executionFailed(errorMsg)
            }

            print("[[调试]] 保存笔记到数据库成功，ID: \(note.id)")
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
            guard let self else {
                completion(DatabaseError.connectionFailed("数据库连接已关闭"))
                return
            }

            do {
                let sql = """
                INSERT OR REPLACE INTO notes (
                    id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                    snippet, color_id, subject, alert_date, type, tag, status,
                    setting_json, extra_info_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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

                try bindNote(note, to: statement!)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    throw DatabaseError.executionFailed(errorMsg)
                }

                Swift.print("[[调试]] 异步保存笔记到数据库成功，ID: \(note.id.prefix(8))...")
                completion(nil)
            } catch {
                Swift.print("[[调试]] 异步保存笔记失败: \(error)")
                completion(error)
            }
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
            executeSQL("BEGIN TRANSACTION;")

            do {
                let sql = """
                INSERT OR REPLACE INTO notes (
                    id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                    snippet, color_id, subject, alert_date, type, tag, status,
                    setting_json, extra_info_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """

                for note in notes {
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

                    try bindNote(note, to: statement!)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        let errorMsg = String(cString: sqlite3_errmsg(db))
                        throw DatabaseError.executionFailed(errorMsg)
                    }
                }

                executeSQL("COMMIT;")
                print("[[调试]] 批量保存 \(notes.count) 条笔记成功")
            } catch {
                executeSQL("ROLLBACK;")
                print("[[调试]] 批量保存笔记失败，事务已回滚: \(error)")
                throw error
            }
        }
    }

    /// 加载笔记
    ///
    /// - Parameter noteId: 笔记ID
    /// - Returns: 笔记对象，如果不存在则返回nil
    /// - Throws: DatabaseError（数据库操作失败）
    func loadNote(noteId: String) throws -> Note? {
        try dbQueue.sync {
            let sql = """
            SELECT id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                   snippet, color_id, subject, alert_date, type, tag, status,
                   setting_json, extra_info_json
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

            return try parseNote(from: statement)
        }
    }

    /// 获取所有笔记
    ///
    /// 按更新时间倒序排列（最新的在前）
    ///
    /// - Returns: 笔记数组
    /// - Throws: DatabaseError（数据库操作失败）
    func getAllNotes() throws -> [Note] {
        try dbQueue.sync {
            let sql = """
            SELECT id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                   snippet, color_id, subject, alert_date, type, tag, status,
                   setting_json, extra_info_json
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
                    if let note = try parseNote(from: statement) {
                        notes.append(note)
                    }
                } catch {
                    // 静默处理解析错误，继续处理下一行
                }
            }

            print("[[调试]] getAllNotes: 处理了 \(rowCount) 行，成功解析 \(notes.count) 条笔记")
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

            print("[[调试]] 删除笔记: \(noteId)")
        }
    }

    /// 检查笔记是否存在
    ///
    /// - Parameter noteId: 笔记ID
    /// - Returns: 如果存在返回true，否则返回false
    func noteExists(noteId: String) -> Bool {
        dbQueue.sync {
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
            let selectSQL = """
            SELECT id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                   snippet, color_id, subject, alert_date, type, tag, status,
                   setting_json, extra_info_json
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
                print("[[调试]] 更新笔记 ID 失败：找不到笔记 \(oldId)")
                return
            }

            guard let parsedNote = try parseNote(from: selectStatement) else {
                print("[[调试]] 更新笔记 ID 失败：无法解析笔记 \(oldId)")
                return
            }

            let note = Note(
                id: newId,
                title: parsedNote.title,
                content: parsedNote.content,
                folderId: parsedNote.folderId,
                isStarred: parsedNote.isStarred,
                createdAt: parsedNote.createdAt,
                updatedAt: parsedNote.updatedAt,
                tags: parsedNote.tags,
                rawData: parsedNote.rawData,
                snippet: parsedNote.snippet,
                colorId: parsedNote.colorId,
                subject: parsedNote.subject,
                alertDate: parsedNote.alertDate,
                type: parsedNote.type,
                serverTag: parsedNote.serverTag,
                status: parsedNote.status,
                settingJson: parsedNote.settingJson,
                extraInfoJson: parsedNote.extraInfoJson
            )

            let insertSQL = """
            INSERT INTO notes (
                id, title, content, folder_id, is_starred, created_at, updated_at, tags, raw_data,
                snippet, color_id, subject, alert_date, type, tag, status,
                setting_json, extra_info_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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

            try bindNote(note, to: insertStatement!)

            guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                throw DatabaseError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }

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

            print("[[调试]] 更新笔记 ID: \(oldId) -> \(newId)")
        }
    }
}
