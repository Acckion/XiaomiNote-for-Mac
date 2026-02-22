import Foundation

/// 笔记数据转换器
///
/// 纯静态方法的结构体，负责 Note 与服务器数据格式之间的转换。
/// 从 Note.swift 中抽取的转换逻辑，使 Note 保持为纯数据结构。
public struct NoteMapper: Sendable {

    // MARK: - 从服务器响应创建 Note

    /// 从服务器响应创建 Note 对象
    ///
    /// 解析服务器返回的完整笔记数据，支持多种响应格式。
    ///
    /// - Parameter serverResponse: 服务器响应字典
    /// - Returns: Note 对象，如果数据无效则返回 nil
    public static func fromServerResponse(_ serverResponse: [String: Any]) -> Note? {
        var entry: [String: Any]?

        if let data = serverResponse["data"] as? [String: Any],
           let dataEntry = data["entry"] as? [String: Any]
        {
            entry = dataEntry
        } else if let directEntry = serverResponse["entry"] as? [String: Any] {
            entry = directEntry
        } else if serverResponse["id"] != nil {
            entry = serverResponse
        }

        guard let entry else { return nil }
        guard let id = entry["id"] as? String else { return nil }

        var title = ""
        if let extraInfo = entry["extraInfo"] as? String,
           let extraData = extraInfo.data(using: .utf8),
           let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
           let extractedTitle = extraJson["title"] as? String
        {
            title = extractedTitle
        }

        if title.isEmpty, let entryTitle = entry["title"] as? String {
            title = entryTitle
        }

        if title.isEmpty {
            title = "未命名笔记_\(id)"
        }

        title = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "", options: .regularExpression)

        let content: String = if let rawContent = entry["content"] as? String {
            NoteMapper.convertLegacyImageFormat(rawContent)
        } else {
            ""
        }

        let folderId: String = if let folderIdString = entry["folderId"] as? String {
            folderIdString
        } else if let folderIdInt = entry["folderId"] as? Int {
            String(folderIdInt)
        } else {
            "0"
        }

        let isStarred = entry["isStarred"] as? Bool ?? false

        let createdAt = if let createDateMs = entry["createDate"] as? TimeInterval {
            Date(timeIntervalSince1970: createDateMs / 1000)
        } else {
            Date()
        }

        let updatedAt: Date = if let modifyDateMs = entry["modifyDate"] as? TimeInterval {
            Date(timeIntervalSince1970: modifyDateMs / 1000)
        } else {
            createdAt
        }

        var tags: [String] = []
        if let tagsArray = entry["tags"] as? [String] {
            tags = tagsArray
        } else if let tagsString = entry["tags"] as? String, !tagsString.isEmpty {
            if let tagsData = tagsString.data(using: .utf8),
               let tagsArray = try? JSONSerialization.jsonObject(with: tagsData) as? [String]
            {
                tags = tagsArray
            } else {
                tags = [tagsString]
            }
        }

        let snippet = entry["snippet"] as? String
        let colorId = entry["colorId"] as? Int ?? 0
        let type = entry["type"] as? String ?? "note"
        let serverTag = entry["tag"] as? String
        let status = entry["status"] as? String ?? "normal"

        var settingJson: String?
        if let setting = entry["setting"] {
            if let settingData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
               let settingString = String(data: settingData, encoding: .utf8)
            {
                settingJson = settingString
            }
        }

        var extraInfoJson: String?
        if let extraInfo = entry["extraInfo"] as? String {
            extraInfoJson = extraInfo
        } else if let extraInfo = entry["extraInfo"] {
            if let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfo, options: [.sortedKeys]),
               let extraInfoString = String(data: extraInfoData, encoding: .utf8)
            {
                extraInfoJson = extraInfoString
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
            snippet: snippet,
            colorId: colorId,
            type: type,
            serverTag: serverTag,
            status: status,
            settingJson: settingJson,
            extraInfoJson: extraInfoJson
        )
    }

    // MARK: - 从列表数据创建 Note

    /// 从小米笔记 API 列表数据创建 Note 对象
    ///
    /// 注意：此方法创建的对象 content 为空，需要后续调用 fetchNoteDetails 获取完整内容
    ///
    /// - Parameter data: API 返回的笔记数据字典
    /// - Returns: Note 对象，如果数据无效则返回 nil
    public static func fromMinoteListData(_ data: [String: Any]) -> Note? {
        guard let id = data["id"] as? String else { return nil }

        var title = ""
        if let extraInfo = data["extraInfo"] as? String,
           let extraData = extraInfo.data(using: .utf8),
           let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any]
        {
            title = extraJson["title"] as? String ?? ""
        }

        if title.isEmpty, let entryTitle = data["title"] as? String, !entryTitle.isEmpty {
            title = entryTitle
        }

        if title.isEmpty {
            title = "未命名笔记_\(id)"
        }

        title = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "", options: .regularExpression)

        let folderId = (data["folderId"] as? String) ?? (data["folderId"] as? Int)?.description ?? "0"
        let modifyDate = (data["modifyDate"] as? TimeInterval) ?? Date().timeIntervalSince1970 * 1000
        let createDate = (data["createDate"] as? TimeInterval) ?? modifyDate

        let snippet = data["snippet"] as? String
        let colorId = data["colorId"] as? Int ?? 0
        let type = data["type"] as? String ?? "note"
        let serverTag = data["tag"] as? String
        let status = data["status"] as? String ?? "normal"

        var settingJson: String?
        if let setting = data["setting"] {
            if let settingData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
               let settingString = String(data: settingData, encoding: .utf8)
            {
                settingJson = settingString
            }
        }

        var extraInfoJson: String?
        if let extraInfo = data["extraInfo"] as? String {
            extraInfoJson = extraInfo
        } else if let extraInfo = data["extraInfo"] {
            if let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfo, options: [.sortedKeys]),
               let extraInfoString = String(data: extraInfoData, encoding: .utf8)
            {
                extraInfoJson = extraInfoString
            }
        }

        return Note(
            id: id,
            title: title,
            content: "",
            folderId: folderId,
            isStarred: false,
            createdAt: Date(timeIntervalSince1970: createDate / 1000),
            updatedAt: Date(timeIntervalSince1970: modifyDate / 1000),
            tags: [],
            snippet: snippet,
            colorId: colorId,
            type: type,
            serverTag: serverTag,
            status: status,
            settingJson: settingJson,
            extraInfoJson: extraInfoJson
        )
    }

    // MARK: - 从服务器详情更新 Note

    /// 从笔记详情 API 响应更新 Note 内容
    ///
    /// - Parameters:
    ///   - note: 要更新的笔记（inout）
    ///   - details: API 返回的笔记详情字典
    public static func updateFromServerDetails(_ note: inout Note, details: [String: Any]) {
        var entry: [String: Any]?

        if let data = details["data"] as? [String: Any],
           let dataEntry = data["entry"] as? [String: Any]
        {
            entry = dataEntry
        }

        guard let entry else {
            LogService.shared.error(.storage, "updateFromServerDetails 无法从响应中提取 entry")
            return
        }

        if let newContent = entry["content"] as? String {
            let normalizedContent = NoteMapper.convertLegacyImageFormat(newContent)
            note.content = normalizedContent
        }

        var newTitle: String?
        if let extraInfo = entry["extraInfo"] as? String {
            if let extraData = extraInfo.data(using: .utf8),
               let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
               let title = extraJson["title"] as? String, !title.isEmpty
            {
                newTitle = title
            }
        }

        if newTitle == nil, let title = entry["title"] as? String, !title.isEmpty {
            newTitle = title
        }

        if let title = newTitle, !title.isEmpty {
            note.title = title
        } else {
            if !note.title.isEmpty, !note.title.hasPrefix("未命名笔记_") {
                note.title = ""
            }
        }

        if let modifyDate = entry["modifyDate"] as? TimeInterval {
            let serverUpdatedAt = Date(timeIntervalSince1970: modifyDate / 1000)
            if abs(serverUpdatedAt.timeIntervalSince(note.updatedAt)) > 1.0 {
                note.updatedAt = serverUpdatedAt
            }
        }

        if let createDate = entry["createDate"] as? TimeInterval {
            let serverCreatedAt = Date(timeIntervalSince1970: createDate / 1000)
            if abs(serverCreatedAt.timeIntervalSince(note.createdAt)) > 1.0 {
                note.createdAt = serverCreatedAt
            }
        }

        if let folderId = entry["folderId"] as? String {
            note.folderId = folderId
        } else if let folderId = entry["folderId"] as? Int {
            note.folderId = String(folderId)
        }

        if let isStarred = entry["isStarred"] as? Bool {
            note.isStarred = isStarred
        }

        note.snippet = entry["snippet"] as? String
        note.colorId = entry["colorId"] as? Int ?? 0
        note.type = entry["type"] as? String ?? "note"
        note.serverTag = entry["tag"] as? String
        note.status = entry["status"] as? String ?? "normal"

        if let setting = entry["setting"] {
            if let settingData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
               let settingString = String(data: settingData, encoding: .utf8)
            {
                note.settingJson = settingString
            } else {
                note.settingJson = nil
                LogService.shared.warning(.storage, "无法将 setting 转换为 JSON 字符串")
            }
        } else {
            note.settingJson = nil
        }

        if let extraInfo = entry["extraInfo"] as? String {
            note.extraInfoJson = extraInfo
        } else if let extraInfo = entry["extraInfo"] {
            if let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfo, options: [.sortedKeys]),
               let extraInfoString = String(data: extraInfoData, encoding: .utf8)
            {
                note.extraInfoJson = extraInfoString
            } else {
                note.extraInfoJson = nil
                LogService.shared.warning(.storage, "无法将 extraInfo 转换为 JSON 字符串")
            }
        } else {
            note.extraInfoJson = nil
        }
    }

    // MARK: - 转换为上传格式

    /// 将 Note 转换为小米笔记 API 上传格式
    ///
    /// - Parameter note: 要转换的笔记
    /// - Returns: API 格式的字典
    public static func toUploadPayload(_ note: Note) -> [String: Any] {
        var data: [String: Any] = [
            "id": note.id,
            "title": note.title,
            "content": note.content,
            "folderId": note.folderId,
            "isStarred": note.isStarred,
            "createdAt": Int(note.createdAt.timeIntervalSince1970 * 1000),
            "updatedAt": Int(note.updatedAt.timeIntervalSince1970 * 1000),
            "tags": note.tags,
        ]

        if let snippet = note.snippet {
            data["snippet"] = snippet
        }
        data["colorId"] = note.colorId
        data["type"] = note.type
        if let serverTag = note.serverTag {
            data["tag"] = serverTag
        }
        data["status"] = note.status

        if let settingJson = note.settingJson,
           let jsonData = settingJson.data(using: .utf8),
           let setting = try? JSONSerialization.jsonObject(with: jsonData)
        {
            data["setting"] = setting
        }

        if let extraInfoJson = note.extraInfoJson {
            data["extraInfo"] = extraInfoJson
        }

        return data
    }

    // MARK: - 旧版图片格式转换

    /// 更新笔记的 settingJson 中的 data 数组
    ///
    /// 用于图片下载后更新 setting.data
    static func updateSettingData(_ note: inout Note, settingData: [[String: Any]]) {
        var setting: [String: Any] = [:]
        if let existingSettingJson = note.settingJson,
           let jsonData = existingSettingJson.data(using: .utf8),
           let existingSetting = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        {
            setting = existingSetting
        }
        setting["data"] = settingData
        if let data = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8)
        {
            note.settingJson = str
        }
    }

    /// 转换旧版图片格式为新版格式
    ///
    /// - Parameter xml: 原始 XML 内容
    /// - Returns: 转换后的 XML 内容
    static func convertLegacyImageFormat(_ xml: String) -> String {
        let pattern = "☺\\s+([^<]+)<(0|imgshow)\\s*/><([^>]*)\\s*/>"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return xml
        }

        let nsString = xml as NSString
        let matches = regex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsString.length))

        if matches.isEmpty {
            return xml
        }

        var result = xml

        for match in matches.reversed() {
            let fullRange = match.range
            let fileIdRange = match.range(at: 1)
            let imgshowRange = match.range(at: 2)
            let descriptionRange = match.range(at: 3)

            let fileId = nsString.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)
            let imgshow = nsString.substring(with: imgshowRange)
            var description = nsString.substring(with: descriptionRange)

            if description.hasPrefix("["), description.hasSuffix("]") {
                description = String(description.dropFirst().dropLast())
            }

            var normalized = "<img fileid=\"\(fileId)\" imgshow=\"\(imgshow)\""
            if !description.isEmpty {
                normalized += " imgdes=\"\(description)\""
            }
            normalized += " />"

            result = (result as NSString).replacingCharacters(in: fullRange, with: normalized) as String
        }

        return result
    }
}
