import Foundation
import SQLite3

// MARK: - 内部辅助方法

extension DatabaseService {
    /// 验证笔记数据
    ///
    /// 检查笔记字段是否符合约束条件
    ///
    /// - Parameter note: 要验证的笔记对象
    /// - Throws: DatabaseError.validationFailed（数据验证失败）
    func validateNote(_ note: Note) throws {
        guard !note.id.isEmpty else {
            throw DatabaseError.validationFailed("笔记 ID 不能为空")
        }

        guard !note.folderId.isEmpty else {
            throw DatabaseError.validationFailed("文件夹 ID 不能为空")
        }

        guard note.colorId >= 0, note.colorId <= 10 else {
            throw DatabaseError.validationFailed("颜色 ID 必须在 0-10 之间，当前值: \(note.colorId)")
        }

        guard !note.type.isEmpty else {
            throw DatabaseError.validationFailed("笔记类型不能为空")
        }

        guard !note.status.isEmpty else {
            throw DatabaseError.validationFailed("笔记状态不能为空")
        }

        if let settingJson = note.settingJson, !settingJson.isEmpty {
            guard let jsonData = settingJson.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: jsonData, options: [])) != nil
            else {
                throw DatabaseError.validationFailed("setting_json 格式无效")
            }
        }

        if let extraInfoJson = note.extraInfoJson, !extraInfoJson.isEmpty {
            guard let jsonData = extraInfoJson.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: jsonData, options: [])) != nil
            else {
                throw DatabaseError.validationFailed("extra_info_json 格式无效")
            }
        }

        let now = Date()
        let minDate = Date(timeIntervalSince1970: 0)

        guard note.createdAt >= minDate, note.createdAt <= now.addingTimeInterval(86400) else {
            throw DatabaseError.validationFailed("创建时间不合理: \(note.createdAt)")
        }

        guard note.updatedAt >= minDate, note.updatedAt <= now.addingTimeInterval(86400) else {
            throw DatabaseError.validationFailed("更新时间不合理: \(note.updatedAt)")
        }

        let timeDifference = note.createdAt.timeIntervalSince(note.updatedAt)
        guard timeDifference <= 1.0 else {
            throw DatabaseError.validationFailed("更新时间不能早于创建时间（差异: \(timeDifference) 秒）")
        }
    }

    /// 将 Note 的所有字段绑定到 prepared statement
    ///
    /// 封装 18 个字段的绑定逻辑，包括 tags/rawData 的 JSON 序列化和所有可选字段的 null 绑定。
    ///
    /// - Parameters:
    ///   - note: 要绑定的笔记对象
    ///   - statement: SQLite prepared statement 指针
    ///   - startIndex: 起始绑定索引（默认为 1）
    /// - Throws: DatabaseError.validationFailed（JSON 序列化失败）
    func bindNote(_ note: Note, to statement: OpaquePointer, startIndex: Int32 = 1) throws {
        var idx = startIndex

        sqlite3_bind_text(statement, idx, (note.id as NSString).utf8String, -1, nil)
        idx += 1
        sqlite3_bind_text(statement, idx, (note.title as NSString).utf8String, -1, nil)
        idx += 1
        sqlite3_bind_text(statement, idx, (note.content as NSString).utf8String, -1, nil)
        idx += 1
        sqlite3_bind_text(statement, idx, (note.folderId as NSString).utf8String, -1, nil)
        idx += 1
        sqlite3_bind_int(statement, idx, note.isStarred ? 1 : 0)
        idx += 1
        sqlite3_bind_double(statement, idx, note.createdAt.timeIntervalSince1970)
        idx += 1
        sqlite3_bind_double(statement, idx, note.updatedAt.timeIntervalSince1970)
        idx += 1

        do {
            let tagsJSON = try JSONEncoder().encode(note.tags)
            if let tagsString = String(data: tagsJSON, encoding: .utf8) {
                sqlite3_bind_text(statement, idx, (tagsString as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(statement, idx)
            }
        } catch {
            throw DatabaseError.validationFailed("tags JSON 序列化失败: \(error)")
        }
        idx += 1

        if let rawData = note.rawData {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [])
                if let rawDataString = String(data: jsonData, encoding: .utf8) {
                    sqlite3_bind_text(statement, idx, (rawDataString as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, idx)
                }
            } catch {
                throw DatabaseError.validationFailed("rawData JSON 序列化失败: \(error)")
            }
        } else {
            sqlite3_bind_null(statement, idx)
        }
        idx += 1

        if let snippet = note.snippet {
            sqlite3_bind_text(statement, idx, (snippet as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, idx)
        }
        idx += 1

        sqlite3_bind_int(statement, idx, Int32(note.colorId))
        idx += 1

        if let subject = note.subject {
            sqlite3_bind_text(statement, idx, (subject as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, idx)
        }
        idx += 1

        if let alertDate = note.alertDate {
            sqlite3_bind_int64(statement, idx, Int64(alertDate.timeIntervalSince1970 * 1000))
        } else {
            sqlite3_bind_null(statement, idx)
        }
        idx += 1

        sqlite3_bind_text(statement, idx, (note.type as NSString).utf8String, -1, nil)
        idx += 1

        if let serverTag = note.serverTag {
            sqlite3_bind_text(statement, idx, (serverTag as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, idx)
        }
        idx += 1

        sqlite3_bind_text(statement, idx, (note.status as NSString).utf8String, -1, nil)
        idx += 1

        if let settingJson = note.settingJson {
            sqlite3_bind_text(statement, idx, (settingJson as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, idx)
        }
        idx += 1

        if let extraInfoJson = note.extraInfoJson {
            sqlite3_bind_text(statement, idx, (extraInfoJson as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, idx)
        }
    }

    /// 从数据库行解析 Note 对象
    ///
    /// - Parameter statement: SQLite 查询语句指针
    /// - Returns: Note 对象，如果解析失败则返回 nil
    /// - Throws: DatabaseError（数据库操作失败）
    func parseNote(from statement: OpaquePointer?) throws -> Note? {
        guard let statement else {
            return nil
        }

        let id = String(cString: sqlite3_column_text(statement, 0))
        let title = String(cString: sqlite3_column_text(statement, 1))
        let content = String(cString: sqlite3_column_text(statement, 2))
        let folderId = String(cString: sqlite3_column_text(statement, 3))
        let isStarred = sqlite3_column_int(statement, 4) != 0
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))

        var tags: [String] = []
        if let tagsText = sqlite3_column_text(statement, 7) {
            let tagsString = String(cString: tagsText)
            if !tagsString.isEmpty, let tagsData = tagsString.data(using: .utf8) {
                do {
                    tags = try JSONDecoder().decode([String].self, from: tagsData)
                } catch {
                    LogService.shared.error(.storage, "解析 tags JSON 失败 (id=\(id)): \(error)")
                    tags = []
                }
            }
        }

        var rawData: [String: Any]?
        if let rawDataText = sqlite3_column_text(statement, 8) {
            let rawDataString = String(cString: rawDataText)
            if !rawDataString.isEmpty, let rawDataData = rawDataString.data(using: .utf8) {
                do {
                    rawData = try JSONSerialization.jsonObject(with: rawDataData, options: []) as? [String: Any]
                } catch {
                    LogService.shared.error(.storage, "解析 raw_data JSON 失败 (id=\(id)): \(error)")
                    rawData = nil
                }
            }
        }

        var snippet: String?
        if sqlite3_column_type(statement, 9) != SQLITE_NULL,
           let snippetText = sqlite3_column_text(statement, 9)
        {
            snippet = String(cString: snippetText)
        }

        let colorId = if sqlite3_column_type(statement, 10) != SQLITE_NULL {
            Int(sqlite3_column_int(statement, 10))
        } else {
            0
        }

        var subject: String?
        if sqlite3_column_type(statement, 11) != SQLITE_NULL,
           let subjectText = sqlite3_column_text(statement, 11)
        {
            subject = String(cString: subjectText)
        }

        var alertDate: Date?
        if sqlite3_column_type(statement, 12) != SQLITE_NULL {
            let alertDateMs = sqlite3_column_int64(statement, 12)
            if alertDateMs > 0 {
                alertDate = Date(timeIntervalSince1970: TimeInterval(alertDateMs) / 1000.0)
            }
        }

        let type = if sqlite3_column_type(statement, 13) != SQLITE_NULL,
                      let typeText = sqlite3_column_text(statement, 13)
        {
            String(cString: typeText)
        } else {
            "note"
        }

        var serverTag: String?
        if sqlite3_column_type(statement, 14) != SQLITE_NULL,
           let tagText = sqlite3_column_text(statement, 14)
        {
            serverTag = String(cString: tagText)
            LogService.shared.debug(.storage, "读取 serverTag: \(serverTag ?? "nil"), id: \(id)")
        } else {
            LogService.shared.debug(.storage, "serverTag 为 NULL, id: \(id)")
        }

        let status = if sqlite3_column_type(statement, 15) != SQLITE_NULL,
                        let statusText = sqlite3_column_text(statement, 15)
        {
            String(cString: statusText)
        } else {
            "normal"
        }

        var settingJson: String?
        if sqlite3_column_type(statement, 16) != SQLITE_NULL,
           let settingText = sqlite3_column_text(statement, 16)
        {
            let settingString = String(cString: settingText)
            if !settingString.isEmpty {
                settingJson = settingString
                if let jsonData = settingJson?.data(using: .utf8) {
                    do {
                        _ = try JSONSerialization.jsonObject(with: jsonData, options: [])
                    } catch {
                        LogService.shared.error(.storage, "setting_json 格式无效 (id=\(id)): \(error)")
                        settingJson = nil
                    }
                }
            }
        }

        var extraInfoJson: String?
        if sqlite3_column_type(statement, 17) != SQLITE_NULL,
           let extraInfoText = sqlite3_column_text(statement, 17)
        {
            let extraInfoString = String(cString: extraInfoText)
            if !extraInfoString.isEmpty {
                extraInfoJson = extraInfoString
                if let jsonData = extraInfoJson?.data(using: .utf8) {
                    do {
                        _ = try JSONSerialization.jsonObject(with: jsonData, options: [])
                    } catch {
                        LogService.shared.error(.storage, "extra_info_json 格式无效 (id=\(id)): \(error)")
                        extraInfoJson = nil
                    }
                }
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
            extraInfoJson: extraInfoJson
        )
    }

    /// 从数据库行解析 Folder 对象
    func parseFolder(from statement: OpaquePointer?) throws -> Folder? {
        guard let statement else { return nil }

        let id = String(cString: sqlite3_column_text(statement, 0))
        let name = String(cString: sqlite3_column_text(statement, 1))
        let count = Int(sqlite3_column_int(statement, 2))
        let isSystem = sqlite3_column_int(statement, 3) != 0

        let isPinned: Bool
        let createdAtIndex: Int32
        let rawDataIndex: Int32

        if sqlite3_column_type(statement, 4) == SQLITE_INTEGER {
            isPinned = sqlite3_column_int(statement, 4) != 0
            createdAtIndex = 5
            rawDataIndex = 6
        } else {
            isPinned = false
            createdAtIndex = 4
            rawDataIndex = 5
        }

        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, createdAtIndex))

        var rawData: [String: Any]?
        if sqlite3_column_type(statement, rawDataIndex) != SQLITE_NULL {
            if let rawDataText = sqlite3_column_text(statement, rawDataIndex) {
                let rawDataString = String(cString: rawDataText)
                if !rawDataString.isEmpty, let rawDataData = rawDataString.data(using: .utf8), !rawDataData.isEmpty {
                    do {
                        rawData = try JSONSerialization.jsonObject(with: rawDataData, options: []) as? [String: Any]
                    } catch {
                        LogService.shared.error(.storage, "parseFolder: 解析 raw_data 失败 (id=\(id)): \(error)")
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

    /// 解析统一操作
    func parseUnifiedOperation(from statement: OpaquePointer?) -> NoteOperation? {
        guard let statement else { return nil }

        let id = String(cString: sqlite3_column_text(statement, 0))
        let typeString = String(cString: sqlite3_column_text(statement, 1))
        guard let type = OperationType(rawValue: typeString) else { return nil }

        let noteId = String(cString: sqlite3_column_text(statement, 2))

        let dataLength = sqlite3_column_bytes(statement, 3)
        guard let dataPointer = sqlite3_column_blob(statement, 3) else { return nil }
        let data = Data(bytes: dataPointer, count: Int(dataLength))

        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4)))

        var localSaveTimestamp: Date?
        if sqlite3_column_type(statement, 5) != SQLITE_NULL {
            localSaveTimestamp = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5)))
        }

        let statusString = String(cString: sqlite3_column_text(statement, 6))
        let status = OperationStatus(rawValue: statusString) ?? .pending

        let priority = Int(sqlite3_column_int(statement, 7))
        let retryCount = Int(sqlite3_column_int(statement, 8))

        var nextRetryAt: Date?
        if sqlite3_column_type(statement, 9) != SQLITE_NULL {
            nextRetryAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 9)))
        }

        var lastError: String?
        if sqlite3_column_type(statement, 10) != SQLITE_NULL {
            if let errorText = sqlite3_column_text(statement, 10) {
                lastError = String(cString: errorText)
            }
        }

        var errorType: OperationErrorType?
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

    /// 解析历史操作记录
    func parseOperationHistory(from statement: OpaquePointer?) -> OperationHistoryEntry? {
        guard let statement else { return nil }

        let id = String(cString: sqlite3_column_text(statement, 0))
        let typeString = String(cString: sqlite3_column_text(statement, 1))
        guard let type = OperationType(rawValue: typeString) else { return nil }

        let noteId = String(cString: sqlite3_column_text(statement, 2))

        let dataLength = sqlite3_column_bytes(statement, 3)
        guard let dataPointer = sqlite3_column_blob(statement, 3) else { return nil }
        let data = Data(bytes: dataPointer, count: Int(dataLength))

        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4)))
        let completedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5)))

        let statusString = String(cString: sqlite3_column_text(statement, 6))
        let status = OperationStatus(rawValue: statusString) ?? .completed

        let retryCount = Int(sqlite3_column_int(statement, 7))

        var lastError: String?
        if sqlite3_column_type(statement, 8) != SQLITE_NULL {
            if let errorText = sqlite3_column_text(statement, 8) {
                lastError = String(cString: errorText)
            }
        }

        var errorType: OperationErrorType?
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

    /// 解析 ID 映射
    func parseIdMapping(from statement: OpaquePointer?) -> IdMapping? {
        guard let statement else { return nil }

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
enum DatabaseError: Error {
    case prepareFailed(String)
    case executionFailed(String)
    case validationFailed(String)
    case connectionFailed(String)
    case jsonParseFailed(String)
    case transactionFailed(String)
    case invalidData(String)
    case schemaError(String)
}

extension DatabaseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .prepareFailed(message):
            "SQL 准备失败: \(message)"
        case let .executionFailed(message):
            "SQL 执行失败: \(message)"
        case let .validationFailed(message):
            "数据验证失败: \(message)"
        case let .connectionFailed(message):
            "数据库连接失败: \(message)"
        case let .jsonParseFailed(message):
            "JSON 解析失败: \(message)"
        case let .transactionFailed(message):
            "事务操作失败: \(message)"
        case let .invalidData(message):
            "数据格式无效: \(message)"
        case let .schemaError(message):
            "表结构错误: \(message)"
        }
    }
}
