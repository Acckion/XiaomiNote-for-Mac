import Foundation

struct Folder: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var count: Int
    var isSystem: Bool = false
    var createdAt: Date = Date()
    var rawData: [String: Any]? = nil // 存储原始 API 数据（包括 tag 等）
    
    enum CodingKeys: String, CodingKey {
        case id, name, count, isSystem, createdAt
    }
    
    init(id: String, name: String, count: Int, isSystem: Bool = false, createdAt: Date = Date(), rawData: [String: Any]? = nil) {
        self.id = id
        self.name = name
        self.count = count
        self.isSystem = isSystem
        self.createdAt = createdAt
        self.rawData = rawData
    }
    
    // Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable 实现（忽略 rawData）
    static func == (lhs: Folder, rhs: Folder) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.count == rhs.count &&
               lhs.isSystem == rhs.isSystem &&
               lhs.createdAt == rhs.createdAt
    }
    
    // 从小米笔记API数据创建
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
    
    // 转换为小米笔记API格式
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
