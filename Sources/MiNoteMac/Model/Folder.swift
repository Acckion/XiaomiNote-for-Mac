import Foundation

struct Folder: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var count: Int
    var isSystem: Bool = false
    var createdAt: Date = Date()
    
    enum CodingKeys: String, CodingKey {
        case id, name, count, isSystem, createdAt
    }
    
    init(id: String, name: String, count: Int, isSystem: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.count = count
        self.isSystem = isSystem
        self.createdAt = createdAt
    }
    
    // Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
        let createdAt = (data["createdAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        
        return Folder(id: id, name: name, count: count, isSystem: isSystem, createdAt: createdAt)
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
