import Foundation

/// 文件夹数据模型
/// 
/// 表示一个文件夹，包括：
/// - 基本信息：ID、名称、笔记数量
/// - 系统属性：是否为系统文件夹、是否置顶
/// - 原始数据：rawData存储从API获取的原始数据（包括tag等）
/// 
/// **系统文件夹**：
/// - id = "0": 所有笔记
/// - id = "starred": 置顶笔记
public struct Folder: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var count: Int
    public var isSystem: Bool = false
    public var isPinned: Bool = false  // 是否置顶
    public var createdAt: Date = Date()
    public var rawData: [String: Any]? = nil // 存储原始 API 数据（包括 tag 等）
    
    enum CodingKeys: String, CodingKey {
        case id, name, count, isSystem, isPinned, createdAt
    }
    
    public init(id: String, name: String, count: Int, isSystem: Bool = false, isPinned: Bool = false, createdAt: Date = Date(), rawData: [String: Any]? = nil) {
        self.id = id
        self.name = name
        self.count = count
        self.isSystem = isSystem
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.rawData = rawData
    }
    
    // Hashable 实现
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable 实现（只比较 id，这样未分类文件夹即使 count 变化也能保持选中状态）
    public static func == (lhs: Folder, rhs: Folder) -> Bool {
        return lhs.id == rhs.id
    }
    
    // MARK: - 数据转换
    
    /// 从小米笔记API数据创建Folder对象
    /// 
    /// 解析API返回的文件夹数据，提取名称、ID等信息
    /// 
    /// - Parameter data: API返回的文件夹数据字典
    /// - Returns: Folder对象，如果数据无效则返回nil
    static func fromMinoteData(_ data: [String: Any]) -> Folder? {
        // 检查类型，只处理文件夹类型
        if let type = data["type"] as? String, type != "folder" {
            return nil
        }
        
        // 获取ID（可能是String或Int，需要转换）
        var id: String
        if let idString = data["id"] as? String {
            id = idString
        } else if let idInt = data["id"] as? Int {
            id = String(idInt)
        } else {
            return nil
        }
        
        // 获取名称（小米笔记API使用 subject 字段，不是 name）
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
        let createdAt: Date
        if let createDate = data["createDate"] as? Int {
            createdAt = Date(timeIntervalSince1970: TimeInterval(createDate) / 1000)
        } else if let createDate = data["createdAt"] as? TimeInterval {
            createdAt = Date(timeIntervalSince1970: createDate / 1000)
        } else {
            createdAt = Date()
        }
        
        return Folder(id: id, name: name, count: count, isSystem: isSystem, createdAt: createdAt, rawData: data)
    }
    
    /// 转换为小米笔记API格式
    /// 
    /// - Returns: API格式的字典
    func toMinoteData() -> [String: Any] {
        return [
            "id": id,
            "name": name,
            "count": count,
            "isSystem": isSystem,
            "createdAt": Int(createdAt.timeIntervalSince1970 * 1000)
        ]
    }
}
