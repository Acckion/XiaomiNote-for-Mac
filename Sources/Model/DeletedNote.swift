import Foundation

/// 回收站笔记数据模型
///
/// 表示已删除的笔记，包含删除时间和原始笔记信息
public struct DeletedNote: Identifiable, Codable, Hashable, Equatable {
    /// 笔记ID
    public let id: String

    /// 笔记标题（subject）
    public let subject: String

    /// 笔记摘要（snippet）
    public let snippet: String

    /// 笔记标签（tag）
    public let tag: String

    /// 文件夹ID
    public let folderId: String

    /// 文件夹名称（如果有）
    public let folderName: String?

    /// 创建时间（时间戳，毫秒）
    public let createDate: Int64

    /// 修改时间（时间戳，毫秒）
    public let modifyDate: Int64

    /// 删除时间（时间戳，毫秒）
    public let deleteTime: Int64

    /// 颜色ID
    public let colorId: Int

    /// 提醒日期
    public let alertDate: Int64

    /// 提醒标签
    public let alertTag: Int?

    /// 笔记类型
    public let type: String

    /// 笔记状态（通常为 "deleted"）
    public let status: String

    /// 设置信息（可选）
    public let setting: [String: Any]?

    /// 额外信息（可选，JSON字符串）
    public let extraInfo: String?

    /// 格式化删除时间
    public var formattedDeleteTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(deleteTime) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return formatter.string(from: date)
    }

    /// 格式化创建时间
    public var formattedCreateTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(createDate) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return formatter.string(from: date)
    }

    /// 格式化修改时间
    public var formattedModifyTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(modifyDate) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
        return formatter.string(from: date)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case snippet
        case tag
        case folderId
        case folderName
        case createDate
        case modifyDate
        case deleteTime
        case colorId
        case alertDate
        case alertTag
        case type
        case status
        case setting
        case extraInfo
    }

    /// 公共初始化器
    public init(
        id: String,
        subject: String,
        snippet: String,
        tag: String,
        folderId: String,
        folderName: String? = nil,
        createDate: Int64,
        modifyDate: Int64,
        deleteTime: Int64,
        colorId: Int = 0,
        alertDate: Int64 = 0,
        alertTag: Int? = nil,
        type: String,
        status: String,
        setting: [String: Any]? = nil,
        extraInfo: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.snippet = snippet
        self.tag = tag
        self.folderId = folderId
        self.folderName = folderName
        self.createDate = createDate
        self.modifyDate = modifyDate
        self.deleteTime = deleteTime
        self.colorId = colorId
        self.alertDate = alertDate
        self.alertTag = alertTag
        self.type = type
        self.status = status
        self.setting = setting
        self.extraInfo = extraInfo
    }

    /// 从API响应创建 DeletedNote
    ///
    /// - Parameter data: API返回的笔记数据字典
    /// - Returns: DeletedNote对象，如果数据无效则返回nil
    static func fromAPIResponse(_ data: [String: Any]) -> DeletedNote? {
        guard let id = data["id"] as? String,
              let tag = data["tag"] as? String,
              let createDate = data["createDate"] as? Int64,
              let modifyDate = data["modifyDate"] as? Int64,
              let deleteTime = data["deleteTime"] as? Int64,
              let type = data["type"] as? String,
              let status = data["status"] as? String
        else {
            return nil
        }

        // 处理 folderId（可能是 Int 或 String）
        let folderId: String = if let folderIdInt = data["folderId"] as? Int {
            String(folderIdInt)
        } else if let folderIdStr = data["folderId"] as? String {
            folderIdStr
        } else {
            "0"
        }

        return DeletedNote(
            id: id,
            subject: data["subject"] as? String ?? "",
            snippet: data["snippet"] as? String ?? "",
            tag: tag,
            folderId: folderId,
            folderName: data["folderName"] as? String,
            createDate: createDate,
            modifyDate: modifyDate,
            deleteTime: deleteTime,
            colorId: data["colorId"] as? Int ?? 0,
            alertDate: data["alertDate"] as? Int64 ?? 0,
            alertTag: data["alertTag"] as? Int,
            type: type,
            status: status,
            setting: data["setting"] as? [String: Any],
            extraInfo: data["extraInfo"] as? String
        )
    }

    // MARK: - Codable 实现（处理 setting 和 extraInfo）

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(String.self, forKey: .id)
        self.subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        self.snippet = try container.decodeIfPresent(String.self, forKey: .snippet) ?? ""
        self.tag = try container.decode(String.self, forKey: .tag)

        // 处理 folderId（可能是 Int 或 String）
        if let folderIdInt = try? container.decode(Int.self, forKey: .folderId) {
            self.folderId = String(folderIdInt)
        } else {
            self.folderId = try container.decodeIfPresent(String.self, forKey: .folderId) ?? "0"
        }

        self.folderName = try container.decodeIfPresent(String.self, forKey: .folderName)
        self.createDate = try container.decode(Int64.self, forKey: .createDate)
        self.modifyDate = try container.decode(Int64.self, forKey: .modifyDate)
        self.deleteTime = try container.decode(Int64.self, forKey: .deleteTime)
        self.colorId = try container.decodeIfPresent(Int.self, forKey: .colorId) ?? 0
        self.alertDate = try container.decodeIfPresent(Int64.self, forKey: .alertDate) ?? 0
        self.alertTag = try container.decodeIfPresent(Int.self, forKey: .alertTag)
        self.type = try container.decode(String.self, forKey: .type)
        self.status = try container.decode(String.self, forKey: .status)

        // 处理 setting（字典类型）
        if let settingData = try? container.decode([String: AnyCodable].self, forKey: .setting) {
            self.setting = settingData.mapValues { $0.value }
        } else {
            self.setting = nil
        }

        self.extraInfo = try container.decodeIfPresent(String.self, forKey: .extraInfo)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(subject, forKey: .subject)
        try container.encode(snippet, forKey: .snippet)
        try container.encode(tag, forKey: .tag)
        try container.encode(folderId, forKey: .folderId)
        try container.encodeIfPresent(folderName, forKey: .folderName)
        try container.encode(createDate, forKey: .createDate)
        try container.encode(modifyDate, forKey: .modifyDate)
        try container.encode(deleteTime, forKey: .deleteTime)
        try container.encode(colorId, forKey: .colorId)
        try container.encode(alertDate, forKey: .alertDate)
        try container.encodeIfPresent(alertTag, forKey: .alertTag)
        try container.encode(type, forKey: .type)
        try container.encode(status, forKey: .status)

        // 处理 setting
        if let setting {
            let codableSetting = setting.mapValues { AnyCodable($0) }
            try container.encode(codableSetting, forKey: .setting)
        }

        try container.encodeIfPresent(extraInfo, forKey: .extraInfo)
    }

    // MARK: - Hashable & Equatable

    public static func == (lhs: DeletedNote, rhs: DeletedNote) -> Bool {
        lhs.id == rhs.id && lhs.deleteTime == rhs.deleteTime
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(deleteTime)
    }
}

/// 用于 Codable 的 Any 类型包装器
private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解码 AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            let codableArray = array.map { AnyCodable($0) }
            try container.encode(codableArray)
        case let dict as [String: Any]:
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "无法编码 AnyCodable"))
        }
    }
}
