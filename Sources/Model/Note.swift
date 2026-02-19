import AppKit
import Foundation

/// 笔记数据模型
///
/// 表示一条笔记的所有信息，包括：
/// - 基本信息：ID、标题、内容、文件夹ID等
/// - 元数据：创建时间、更新时间、标签、收藏状态等
/// - 原始数据：rawData存储从API获取的原始数据（包括tag等）
///
/// **数据格式**：
/// - content: XML格式的笔记内容（小米笔记格式）
/// - rawData: 包含tag、createDate等API需要的字段
public struct Note: Identifiable, Codable, Hashable, @unchecked Sendable {
    public let id: String
    public var title: String
    public var content: String
    public var folderId: String
    public var isStarred = false
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String] = []

    // 新增字段 - 数据库优化
    public var snippet: String? // 笔记摘要，用于列表显示
    public var colorId: Int // 笔记颜色ID，默认值 0
    public var subject: String? // 笔记主题
    public var alertDate: Date? // 提醒时间
    public var type: String // 笔记类型 (note/checklist等)，默认值 "note"
    public var serverTag: String? // 服务器标签，用于同步
    public var status: String // 笔记状态 (normal/deleted等)，默认值 "normal"
    public var settingJson: String? // setting 对象的 JSON
    public var extraInfoJson: String? // extraInfo 的 JSON

    /// 小米笔记格式的原始数据
    public var rawData: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case id, title, content, folderId, isStarred, createdAt, updatedAt, tags, rawData
        case snippet, colorId, subject, alertDate, type, serverTag, status, settingJson, extraInfoJson
    }

    public init(
        id: String,
        title: String,
        content: String,
        folderId: String,
        isStarred: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        tags: [String] = [],
        rawData: [String: Any]? = nil,
        snippet: String? = nil,
        colorId: Int = 0,
        subject: String? = nil,
        alertDate: Date? = nil,
        type: String = "note",
        serverTag: String? = nil,
        status: String = "normal",
        settingJson: String? = nil,
        extraInfoJson: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.folderId = folderId
        self.isStarred = isStarred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.rawData = rawData
        self.snippet = snippet
        self.colorId = colorId
        self.subject = subject
        self.alertDate = alertDate
        self.type = type
        self.serverTag = serverTag
        self.status = status
        self.settingJson = settingJson
        self.extraInfoJson = extraInfoJson
    }

    /// 自定义编码
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(folderId, forKey: .folderId)
        try container.encode(isStarred, forKey: .isStarred)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(tags, forKey: .tags)

        // 编码新增字段
        try container.encodeIfPresent(snippet, forKey: .snippet)
        try container.encode(colorId, forKey: .colorId)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encodeIfPresent(alertDate, forKey: .alertDate)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(serverTag, forKey: .serverTag)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(settingJson, forKey: .settingJson)
        try container.encodeIfPresent(extraInfoJson, forKey: .extraInfoJson)

        // 编码 rawData 为 JSON 数据，使用更稳定的选项
        if let rawData {
            let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [.fragmentsAllowed, .sortedKeys])
            try container.encode(jsonData, forKey: .rawData)
        } else {
            try container.encodeNil(forKey: .rawData)
        }
    }

    /// 自定义解码
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.folderId = try container.decode(String.self, forKey: .folderId)
        self.isStarred = try container.decode(Bool.self, forKey: .isStarred)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.tags = try container.decode([String].self, forKey: .tags)

        // 解码新增字段，使用默认值
        self.snippet = try container.decodeIfPresent(String.self, forKey: .snippet)
        self.colorId = try container.decodeIfPresent(Int.self, forKey: .colorId) ?? 0
        self.subject = try container.decodeIfPresent(String.self, forKey: .subject)
        self.alertDate = try container.decodeIfPresent(Date.self, forKey: .alertDate)
        self.type = try container.decodeIfPresent(String.self, forKey: .type) ?? "note"
        self.serverTag = try container.decodeIfPresent(String.self, forKey: .serverTag)
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "normal"
        self.settingJson = try container.decodeIfPresent(String.self, forKey: .settingJson)
        self.extraInfoJson = try container.decodeIfPresent(String.self, forKey: .extraInfoJson)

        // 解码 rawData
        do {
            if let jsonData = try container.decodeIfPresent(Data.self, forKey: .rawData) {
                if let dict = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed, .mutableContainers]) as? [String: Any] {
                    self.rawData = dict
                } else if let array = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed]) as? [Any] {
                    self.rawData = ["data": array]
                } else {
                    self.rawData = try ["value": JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])]
                }
            } else {
                self.rawData = nil
            }
        } catch {
            LogService.shared.error(.storage, "解码 rawData 失败: \(error)")
            self.rawData = nil
        }
    }

    /// 自定义 Equatable 实现
    /// 只比较 id，这样当笔记内容更新时，SwiftUI 的 List selection 不会因为
    /// updatedAt 等字段的变化而认为是不同的笔记，从而保持选择状态
    public static func == (lhs: Note, rhs: Note) -> Bool {
        // 只比较 id，确保选择状态在内容更新时保持不变
        lhs.id == rhs.id
    }

    /// Hashable 实现
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// 比较两个笔记的内容是否完全相同（包括所有字段）
    ///
    /// 此方法用于需要完整比较的场景，如检测笔记是否有未保存的更改。
    /// 与 `==` 运算符不同，此方法比较所有字段而不仅仅是 id。
    ///
    /// - Parameter other: 要比较的另一个笔记
    /// - Returns: 如果所有字段都相同则返回 true
    public func contentEquals(_ other: Note) -> Bool {
        guard id == other.id,
              title == other.title,
              content == other.content,
              folderId == other.folderId,
              isStarred == other.isStarred,
              createdAt == other.createdAt,
              updatedAt == other.updatedAt,
              tags == other.tags,
              snippet == other.snippet,
              colorId == other.colorId,
              subject == other.subject,
              alertDate == other.alertDate,
              type == other.type,
              serverTag == other.serverTag,
              status == other.status,
              settingJson == other.settingJson,
              extraInfoJson == other.extraInfoJson
        else {
            return false
        }

        // 比较 rawData
        return Note.compareRawData(rawData, other.rawData)
    }

    /// 比较两个 rawData 字典是否相等，特别关注图片信息
    private static func compareRawData(_ lhs: [String: Any]?, _ rhs: [String: Any]?) -> Bool {
        // 如果两个都是 nil，相等
        if lhs == nil, rhs == nil {
            return true
        }

        // 如果只有一个为 nil，不相等
        guard let lhs, let rhs else {
            return false
        }

        // 比较关键字段
        let lhsKeys = Set(lhs.keys)
        let rhsKeys = Set(rhs.keys)

        // 如果键的数量不同，不相等
        if lhsKeys != rhsKeys {
            return false
        }

        // 比较每个键的值
        for key in lhsKeys {
            guard let lhsValue = lhs[key], let rhsValue = rhs[key] else {
                return false
            }

            // 特别处理 setting.data 数组（包含图片信息）
            if key == "setting" {
                if !compareSettingData(lhsValue, rhsValue) {
                    return false
                }
                continue
            }

            // 其他字段使用字符串比较
            let lhsString = String(describing: lhsValue)
            let rhsString = String(describing: rhsValue)
            if lhsString != rhsString {
                return false
            }
        }

        return true
    }

    /// 比较 setting.data 数组，特别关注图片信息
    private static func compareSettingData(_ lhs: Any, _ rhs: Any) -> Bool {
        // 尝试解析为字典
        guard let lhsDict = lhs as? [String: Any],
              let rhsDict = rhs as? [String: Any]
        else {
            // 如果无法解析为字典，使用字符串比较
            return String(describing: lhs) == String(describing: rhs)
        }

        // 比较 data 数组
        let lhsData = lhsDict["data"] as? [[String: Any]] ?? []
        let rhsData = rhsDict["data"] as? [[String: Any]] ?? []

        // 如果数组长度不同，不相等
        if lhsData.count != rhsData.count {
            return false
        }

        // 比较每个图片信息
        for i in 0 ..< lhsData.count {
            let lhsItem = lhsData[i]
            let rhsItem = rhsData[i]

            // 比较图片关键字段
            let lhsFileId = lhsItem["fileId"] as? String ?? ""
            let rhsFileId = rhsItem["fileId"] as? String ?? ""
            let lhsMimeType = lhsItem["mimeType"] as? String ?? ""
            let rhsMimeType = rhsItem["mimeType"] as? String ?? ""

            if lhsFileId != rhsFileId || lhsMimeType != rhsMimeType {
                return false
            }
        }

        // 比较其他 setting 字段
        let lhsOtherKeys = Set(lhsDict.keys).subtracting(["data"])
        let rhsOtherKeys = Set(rhsDict.keys).subtracting(["data"])

        if lhsOtherKeys != rhsOtherKeys {
            return false
        }

        for key in lhsOtherKeys {
            guard let lhsValue = lhsDict[key], let rhsValue = rhsDict[key] else {
                return false
            }

            if String(describing: lhsValue) != String(describing: rhsValue) {
                return false
            }
        }

        return true
    }

    /// 哈希 rawData，特别关注图片信息
    private func hashRawData(into hasher: inout Hasher) {
        guard let rawData else {
            hasher.combine(0) // nil 的哈希值
            return
        }

        // 对每个键值对进行哈希
        for (key, value) in rawData.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)

            // 特别处理 setting.data
            if key == "setting", let settingDict = value as? [String: Any] {
                hashSettingData(settingDict, into: &hasher)
            } else {
                hasher.combine(String(describing: value))
            }
        }
    }

    /// 哈希 setting.data 数组
    private func hashSettingData(_ settingDict: [String: Any], into hasher: inout Hasher) {
        // 哈希其他 setting 字段
        for (key, value) in settingDict.sorted(by: { $0.key < $1.key }) where key != "data" {
            hasher.combine(key)
            hasher.combine(String(describing: value))
        }

        // 哈希 data 数组中的图片信息
        if let dataArray = settingDict["data"] as? [[String: Any]] {
            for item in dataArray {
                if let fileId = item["fileId"] as? String {
                    hasher.combine(fileId)
                }
                if let mimeType = item["mimeType"] as? String {
                    hasher.combine(mimeType)
                }
            }
        }
    }

    // MARK: - 数据转换

    /// 从服务器响应初始化 Note 对象
    ///
    /// 解析服务器返回的完整笔记数据，包括所有新增字段。
    /// 此方法用于从服务器响应中创建完整的 Note 对象。
    ///
    /// - Parameter serverResponse: 服务器响应字典，可能包含 data.entry、entry 或直接是笔记数据
    /// - Returns: Note 对象，如果数据无效则返回 nil
    public init?(from serverResponse: [String: Any]) {
        // 提取 entry 数据
        var entry: [String: Any]?

        // 格式1: {"data": {"entry": {...}}}
        if let data = serverResponse["data"] as? [String: Any],
           let dataEntry = data["entry"] as? [String: Any]
        {
            entry = dataEntry
        }
        // 格式2: {"entry": {...}}
        else if let directEntry = serverResponse["entry"] as? [String: Any] {
            entry = directEntry
        }
        // 格式3: 响应本身就是 entry
        else if serverResponse["id"] != nil {
            entry = serverResponse
        }

        guard let entry else {
            return nil
        }

        // 必需字段：id
        guard let id = entry["id"] as? String else {
            return nil
        }

        // 解析基本字段
        self.id = id

        // 解析标题（从 extraInfo 或 title 字段）
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

        // 清理标题中的 HTML 标签和非法字符
        title = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "", options: .regularExpression)
        self.title = title

        // 解析内容
        if let content = entry["content"] as? String {
            self.content = Self.convertLegacyImageFormat(content)
        } else {
            self.content = ""
        }

        // 解析文件夹 ID
        if let folderIdString = entry["folderId"] as? String {
            self.folderId = folderIdString
        } else if let folderIdInt = entry["folderId"] as? Int {
            self.folderId = String(folderIdInt)
        } else {
            self.folderId = "0"
        }

        // 解析收藏状态
        self.isStarred = entry["isStarred"] as? Bool ?? false

        // 解析时间戳（毫秒转 Date）
        if let createDateMs = entry["createDate"] as? TimeInterval {
            self.createdAt = Date(timeIntervalSince1970: createDateMs / 1000)
        } else {
            self.createdAt = Date()
        }

        if let modifyDateMs = entry["modifyDate"] as? TimeInterval {
            self.updatedAt = Date(timeIntervalSince1970: modifyDateMs / 1000)
        } else {
            self.updatedAt = createdAt
        }

        // 解析标签
        if let tagsArray = entry["tags"] as? [String] {
            self.tags = tagsArray
        } else if let tagsString = entry["tags"] as? String, !tagsString.isEmpty {
            // 如果 tags 是字符串，尝试解析为 JSON 数组
            if let tagsData = tagsString.data(using: .utf8),
               let tagsArray = try? JSONSerialization.jsonObject(with: tagsData) as? [String]
            {
                self.tags = tagsArray
            } else {
                // 如果无法解析，将整个字符串作为单个标签
                self.tags = [tagsString]
            }
        } else {
            self.tags = []
        }

        // 解析新增字段
        self.snippet = entry["snippet"] as? String
        self.colorId = entry["colorId"] as? Int ?? 0
        self.subject = entry["subject"] as? String

        // 解析提醒时间（毫秒转 Date）
        if let alertDateMs = entry["alertDate"] as? TimeInterval, alertDateMs > 0 {
            self.alertDate = Date(timeIntervalSince1970: alertDateMs / 1000)
        } else {
            self.alertDate = nil
        }

        self.type = entry["type"] as? String ?? "note"
        self.serverTag = entry["tag"] as? String
        self.status = entry["status"] as? String ?? "normal"

        // 解析 JSON 字段
        if let setting = entry["setting"] {
            // 将 setting 对象转换为 JSON 字符串
            if let settingData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
               let settingString = String(data: settingData, encoding: .utf8)
            {
                self.settingJson = settingString
            } else {
                self.settingJson = nil
            }
        } else {
            self.settingJson = nil
        }

        if let extraInfo = entry["extraInfo"] as? String {
            self.extraInfoJson = extraInfo
        } else if let extraInfo = entry["extraInfo"] {
            // 如果 extraInfo 不是字符串，尝试转换为 JSON 字符串
            if let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfo, options: [.sortedKeys]),
               let extraInfoString = String(data: extraInfoData, encoding: .utf8)
            {
                self.extraInfoJson = extraInfoString
            } else {
                self.extraInfoJson = nil
            }
        } else {
            self.extraInfoJson = nil
        }

        // 保存原始数据
        self.rawData = entry
    }

    /// 从小米笔记API数据创建Note对象
    ///
    /// 解析API返回的笔记数据，提取标题、时间戳等信息
    /// 注意：此方法创建的对象content为空，需要后续调用fetchNoteDetails获取完整内容
    ///
    /// - Parameter data: API返回的笔记数据字典
    /// - Returns: Note对象，如果数据无效则返回nil
    static func fromMinoteData(_ data: [String: Any]) -> Note? {
        guard let id = data["id"] as? String else {
            return nil
        }

        // 解析标题
        var title = ""
        if let extraInfo = data["extraInfo"] as? String,
           let extraData = extraInfo.data(using: .utf8),
           let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any]
        {
            title = extraJson["title"] as? String ?? ""
        }

        // 如果extraInfo中没有标题，尝试从entry直接获取
        if title.isEmpty, let entryTitle = data["title"] as? String, !entryTitle.isEmpty {
            title = entryTitle
        }

        // 如果还是没有标题，使用ID（不再从snippet或content中提取）
        if title.isEmpty {
            title = "未命名笔记_\(id)"
        }

        // 去除标题中的HTML标签和非法字符
        title = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "", options: .regularExpression)

        // 解析文件夹ID
        let folderId = (data["folderId"] as? String) ?? (data["folderId"] as? Int)?.description ?? "0"

        // 解析时间戳
        let modifyDate = (data["modifyDate"] as? TimeInterval) ?? Date().timeIntervalSince1970 * 1000
        let createDate = (data["createDate"] as? TimeInterval) ?? modifyDate

        // 内容暂时为空，需要后续调用fetchNoteDetails获取完整内容
        let content = ""

        return Note(
            id: id,
            title: title,
            content: content,
            folderId: folderId,
            isStarred: false, // 需要从API获取收藏状态
            createdAt: Date(timeIntervalSince1970: createDate / 1000),
            updatedAt: Date(timeIntervalSince1970: modifyDate / 1000),
            tags: [],
            rawData: data
        )
    }

    /// 从笔记详情API响应更新内容
    ///
    /// 解析API返回的笔记详情，更新content、title等字段
    /// 支持多种响应格式（data.entry、直接entry、响应本身）
    ///
    /// - Parameter noteDetails: API返回的笔记详情字典
    mutating func updateContent(from noteDetails: [String: Any]) {
        var entry: [String: Any]?

        // 尝试不同的响应格式
        // 格式1: {"data": {"entry": {...}}}
        if let data = noteDetails["data"] as? [String: Any],
           let dataEntry = data["entry"] as? [String: Any]
        {
            entry = dataEntry
        }

        guard let entry else {
            LogService.shared.error(.storage, "updateContent 无法从响应中提取 entry")
            return
        }

        // 更新内容，并转换旧版图片格式
        if let newContent = entry["content"] as? String {
            // 简单转换旧版格式为新版格式（不依赖 XMLNormalizer 避免 actor 隔离问题）
            let normalizedContent = Self.convertLegacyImageFormat(newContent)
            content = normalizedContent
        }

        // 更新标题
        var newTitle: String?

        // 首先尝试从extraInfo中获取
        if let extraInfo = entry["extraInfo"] as? String {
            if let extraData = extraInfo.data(using: .utf8),
               let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
               let title = extraJson["title"] as? String, !title.isEmpty
            {
                newTitle = title
            }
        }

        // 如果extraInfo中没有标题，尝试从entry直接获取
        if newTitle == nil, let title = entry["title"] as? String, !title.isEmpty {
            newTitle = title
        }

        // 不再从snippet或content中提取标题
        // 如果还是没有标题，保持为空或"未命名笔记_xxx"格式

        // 更新标题（如果找到了新的标题）
        if let title = newTitle, !title.isEmpty {
            self.title = title
        } else {
            // 如果没有找到新的标题，且当前标题是"未命名笔记_xxx"格式，保持它
            // 否则，如果当前标题是从内容中提取的，清空它
            if !title.isEmpty, !title.hasPrefix("未命名笔记_") {
                title = ""
            }
        }

        // 更新其他字段
        // 只有当服务器返回的时间戳与本地不同时才更新，避免不必要的排序变化
        if let modifyDate = entry["modifyDate"] as? TimeInterval {
            let serverUpdatedAt = Date(timeIntervalSince1970: modifyDate / 1000)
            if abs(serverUpdatedAt.timeIntervalSince(updatedAt)) > 1.0 {
                updatedAt = serverUpdatedAt
            }
        }

        if let createDate = entry["createDate"] as? TimeInterval {
            let serverCreatedAt = Date(timeIntervalSince1970: createDate / 1000)
            if abs(serverCreatedAt.timeIntervalSince(createdAt)) > 1.0 {
                createdAt = serverCreatedAt
            }
        }

        if let folderId = entry["folderId"] as? String {
            self.folderId = folderId
        } else if let folderId = entry["folderId"] as? Int {
            self.folderId = String(folderId)
        }

        // 更新收藏状态
        if let isStarred = entry["isStarred"] as? Bool {
            self.isStarred = isStarred
        }

        // 更新新增字段
        snippet = entry["snippet"] as? String
        colorId = entry["colorId"] as? Int ?? 0
        subject = entry["subject"] as? String

        // 更新提醒时间（毫秒转 Date）
        if let alertDateMs = entry["alertDate"] as? TimeInterval, alertDateMs > 0 {
            alertDate = Date(timeIntervalSince1970: alertDateMs / 1000)
        } else {
            alertDate = nil
        }

        type = entry["type"] as? String ?? "note"
        serverTag = entry["tag"] as? String
        status = entry["status"] as? String ?? "normal"

        // 更新 JSON 字段
        if let setting = entry["setting"] {
            if let settingData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
               let settingString = String(data: settingData, encoding: .utf8)
            {
                settingJson = settingString
            } else {
                settingJson = nil
                LogService.shared.warning(.storage, "无法将 setting 转换为 JSON 字符串")
            }
        } else {
            settingJson = nil
        }

        if let extraInfo = entry["extraInfo"] as? String {
            extraInfoJson = extraInfo
        } else if let extraInfo = entry["extraInfo"] {
            // 如果 extraInfo 不是字符串，尝试转换为 JSON 字符串
            if let extraInfoData = try? JSONSerialization.data(withJSONObject: extraInfo, options: [.sortedKeys]),
               let extraInfoString = String(data: extraInfoData, encoding: .utf8)
            {
                extraInfoJson = extraInfoString
            } else {
                extraInfoJson = nil
                LogService.shared.warning(.storage, "无法将 extraInfo 转换为 JSON 字符串")
            }
        } else {
            extraInfoJson = nil
        }

        // 更新rawData
        var updatedRawData = rawData ?? [:]
        for (key, value) in entry {
            updatedRawData[key] = value
        }
        rawData = updatedRawData
    }

    // MARK: - 内容访问/更新工具

    /// 转换旧版图片格式为新版格式
    /// - Parameter xml: 原始 XML 内容
    /// - Returns: 转换后的 XML 内容
    private static func convertLegacyImageFormat(_ xml: String) -> String {
        // 使用正则表达式匹配旧版格式：☺ fileId<0/><description/> 或 ☺ fileId<imgshow/><description/>
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

        // 从后往前替换，避免索引变化
        for match in matches.reversed() {
            let fullRange = match.range
            let fileIdRange = match.range(at: 1)
            let imgshowRange = match.range(at: 2)
            let descriptionRange = match.range(at: 3)

            let fileId = nsString.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)
            let imgshow = nsString.substring(with: imgshowRange)
            var description = nsString.substring(with: descriptionRange)

            // 处理描述：移除方括号
            if description.hasPrefix("["), description.hasSuffix("]") {
                description = String(description.dropFirst().dropLast())
            }

            // 转换为新版格式
            var normalized = "<img fileid=\"\(fileId)\" imgshow=\"\(imgshow)\""
            if !description.isEmpty {
                normalized += " imgdes=\"\(description)\""
            }
            normalized += " />"

            result = (result as NSString).replacingCharacters(in: fullRange, with: normalized) as String
        }

        return result
    }

    /// 用于编辑/展示的主 XML 内容。
    /// 优先使用 `content`；为空时回退到 `rawData["snippet"]`，并在需要时补上 `<new-format/>` 前缀。
    var primaryXMLContent: String {
        if !content.isEmpty {
            return content
        }

        if let snippet = rawData?["snippet"] as? String, !snippet.isEmpty {
            // 如果 snippet 已经是新格式，则直接使用或补上前缀
            if snippet.contains("<text") || snippet.contains("<new-format") {
                if snippet.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<new-format/>") {
                    return snippet
                } else {
                    return "<new-format/>" + snippet
                }
            } else {
                // 纯文本 snippet，包装成一个简单段落
                return "<new-format/><text indent=\"1\">\(snippet)</text>"
            }
        }

        return ""
    }

    /// 返回一个内容被更新为指定 XML 的新 Note，用于 ViewModel 内部构造更新后的笔记。
    func withPrimaryXMLContent(_ xml: String) -> Note {
        var copy = self
        copy.content = xml
        return copy
    }

    /// 转换为小米笔记API格式
    ///
    /// 将Note对象转换为API需要的字典格式
    ///
    /// - Returns: API格式的字典
    func toMinoteData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "title": title,
            "content": content,
            "folderId": folderId,
            "isStarred": isStarred,
            "createdAt": Int(createdAt.timeIntervalSince1970 * 1000),
            "updatedAt": Int(updatedAt.timeIntervalSince1970 * 1000),
            "tags": tags,
        ]

        // 保留原始数据中的其他字段
        if let rawData {
            for (key, value) in rawData {
                if !data.keys.contains(key) {
                    data[key] = value
                }
            }
        }

        return data
    }
}

// MARK: - 图片附件扩展

public extension Note {
    /// 图片附件列表
    ///
    /// 从 `settingJson` 字段中解析图片附件信息。
    /// 只返回 `mimeType` 以 "image/" 开头的附件。
    ///
    /// - Returns: 图片附件数组，如果没有图片或解析失败则返回空数组
    var imageAttachments: [NoteImageAttachment] {
        // 检查 settingJson 是否存在
        guard let settingJson,
              !settingJson.isEmpty
        else {
            return []
        }

        // 解析 JSON
        guard let jsonData = settingJson.data(using: .utf8) else {
            return []
        }

        do {
            // 解析为字典
            guard let setting = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                return []
            }

            // 提取 data 数组
            guard let dataArray = setting["data"] as? [[String: Any]] else {
                return []
            }

            // 过滤并转换为 NoteImageAttachment
            return dataArray.compactMap { dict -> NoteImageAttachment? in
                guard let fileId = dict["fileId"] as? String,
                      let mimeType = dict["mimeType"] as? String,
                      mimeType.hasPrefix("image/")
                else {
                    return nil
                }

                let size = dict["size"] as? Int
                return NoteImageAttachment(fileId: fileId, mimeType: mimeType, size: size)
            }
        } catch {
            LogService.shared.error(.storage, "解析 settingJson 失败: \(error)")
            return []
        }
    }

    /// 第一张图片的 fileId
    ///
    /// 用于快速获取笔记的第一张图片，用于列表预览。
    ///
    /// - Returns: 第一张图片的 fileId，如果没有图片则返回 nil
    var firstImageId: String? {
        imageAttachments.first?.fileId
    }

    /// 是否包含图片
    ///
    /// 用于判断笔记是否包含图片附件。
    ///
    /// - Returns: 如果包含至少一张图片则返回 true
    var hasImages: Bool {
        !imageAttachments.isEmpty
    }

    /// 是否包含音频
    ///
    /// 通过检查笔记内容中是否包含 `<sound fileid="xxx" />` 标签来判断。
    ///
    /// - Returns: 如果包含至少一个音频附件则返回 true
    var hasAudio: Bool {
        content.contains("<sound fileid=")
    }
}
