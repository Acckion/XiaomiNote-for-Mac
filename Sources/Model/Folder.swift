import Foundation

/// 文件夹数据模型
///
/// 表示一个文件夹，包括：
/// - 基本信息：ID、名称、笔记数量
/// - 系统属性：是否为系统文件夹、是否置顶
/// - 原始数据：rawDataJson 存储从 API 获取的原始 JSON 字符串（包括 tag 等）
///
/// **系统文件夹**：
/// - id = "0": 所有笔记
/// - id = "starred": 置顶笔记
public struct Folder: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var count: Int
    public var isSystem = false
    public var isPinned = false
    public var createdAt = Date()
    public var rawDataJson: String?

    enum CodingKeys: String, CodingKey {
        case id, name, count, isSystem, isPinned, createdAt
    }

    public init(
        id: String,
        name: String,
        count: Int,
        isSystem: Bool = false,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        rawDataJson: String? = nil
    ) {
        self.id = id
        self.name = name
        self.count = count
        self.isSystem = isSystem
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.rawDataJson = rawDataJson
    }

    /// 从 rawDataJson 中解析 tag
    public var tag: String? {
        guard let json = rawDataJson,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict["tag"] as? String
    }

    /// 从 rawDataJson 中解析完整字典
    public var rawDataDict: [String: Any]? {
        guard let json = rawDataJson,
              let data = json.data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Hashable 实现
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Equatable 实现（只比较 id，这样未分类文件夹即使 count 变化也能保持选中状态）
    public static func == (lhs: Folder, rhs: Folder) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - 数据转换

    /// 从小米笔记API数据创建Folder对象
    ///
    /// 解析API返回的文件夹数据，提取名称、ID等信息
    ///
    /// - Parameter data: API返回的文件夹数据字典
    /// - Returns: Folder对象，如果数据无效则返回nil
    static func fromMinoteData(_ data: [String: Any]) -> Folder? {
        if let type = data["type"] as? String, type != "folder" {
            return nil
        }

        var id: String
        if let idString = data["id"] as? String {
            id = idString
        } else if let idInt = data["id"] as? Int {
            id = String(idInt)
        } else {
            return nil
        }

        let name: String
        if let subject = data["subject"] as? String, !subject.isEmpty {
            name = subject
        } else if let nameField = data["name"] as? String, !nameField.isEmpty {
            name = nameField
        } else {
            return nil
        }

        let count = data["count"] as? Int ?? 0
        let isSystem = data["isSystem"] as? Bool ?? false
        let createdAt = if let createDate = data["createDate"] as? Int {
            Date(timeIntervalSince1970: TimeInterval(createDate) / 1000)
        } else if let createDate = data["createdAt"] as? TimeInterval {
            Date(timeIntervalSince1970: createDate / 1000)
        } else {
            Date()
        }

        let rawDataJson: String? = if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []) {
            String(data: jsonData, encoding: .utf8)
        } else {
            nil
        }

        return Folder(id: id, name: name, count: count, isSystem: isSystem, createdAt: createdAt, rawDataJson: rawDataJson)
    }

    /// 转换为小米笔记API格式
    ///
    /// - Returns: API格式的字典
    func toMinoteData() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "count": count,
            "isSystem": isSystem,
            "createdAt": Int(createdAt.timeIntervalSince1970 * 1000),
        ]
    }
}
