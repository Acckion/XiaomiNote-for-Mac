import Foundation
import AppKit

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
public struct Note: Identifiable, Codable, Hashable {
    public let id: String
    public var title: String
    public var content: String
    public var folderId: String
    public var isStarred: Bool = false
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String] = []
    
    // 小米笔记格式的原始数据
    public var rawData: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, folderId, isStarred, createdAt, updatedAt, tags, rawData
    }
    
    public init(id: String, title: String, content: String, folderId: String, isStarred: Bool = false, 
         createdAt: Date, updatedAt: Date, tags: [String] = [], rawData: [String: Any]? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.folderId = folderId
        self.isStarred = isStarred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.rawData = rawData
    }
    
    // 自定义编码
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
        
        // 编码 rawData 为 JSON 数据，使用更稳定的选项
        if let rawData = rawData {
            let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [.fragmentsAllowed, .sortedKeys])
            try container.encode(jsonData, forKey: .rawData)
        } else {
            try container.encodeNil(forKey: .rawData)
        }
    }
    
    // 自定义解码
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        folderId = try container.decode(String.self, forKey: .folderId)
        isStarred = try container.decode(Bool.self, forKey: .isStarred)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        tags = try container.decode([String].self, forKey: .tags)
        
        // 解码 rawData，使用更健壮的错误处理
        do {
            if let jsonData = try container.decodeIfPresent(Data.self, forKey: .rawData) {
                // 尝试解析为 [String: Any]
                if let dict = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed, .mutableContainers]) as? [String: Any] {
                    rawData = dict
                } else if let array = try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed]) as? [Any] {
                    // 如果是数组，包装为字典
                    rawData = ["data": array]
                } else {
                    // 其他类型，包装为字典
                    rawData = ["value": try JSONSerialization.jsonObject(with: jsonData, options: [.fragmentsAllowed])]
                }
            } else {
                rawData = nil
            }
        } catch {
            print("[Note] 解码 rawData 失败: \(error)")
            rawData = nil
        }
    }
    
    // 自定义 Equatable 实现
    public static func == (lhs: Note, rhs: Note) -> Bool {
        // 比较基本字段
        guard lhs.id == rhs.id &&
              lhs.title == rhs.title &&
              lhs.content == rhs.content &&
              lhs.folderId == rhs.folderId &&
              lhs.isStarred == rhs.isStarred &&
              lhs.createdAt == rhs.createdAt &&
              lhs.updatedAt == rhs.updatedAt &&
              lhs.tags == rhs.tags else {
            return false
        }
        
        // 比较 rawData，特别关注图片信息
        return compareRawData(lhs.rawData, rhs.rawData)
    }
    
    // Hashable 实现
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(content)
        hasher.combine(folderId)
        hasher.combine(isStarred)
        hasher.combine(createdAt)
        hasher.combine(updatedAt)
        hasher.combine(tags)
        
        // 使用专门的 rawData 哈希方法
        hashRawData(into: &hasher)
    }
    
    /// 比较两个 rawData 字典是否相等，特别关注图片信息
    private static func compareRawData(_ lhs: [String: Any]?, _ rhs: [String: Any]?) -> Bool {
        // 如果两个都是 nil，相等
        if lhs == nil && rhs == nil {
            return true
        }
        
        // 如果只有一个为 nil，不相等
        guard let lhs = lhs, let rhs = rhs else {
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
              let rhsDict = rhs as? [String: Any] else {
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
        for i in 0..<lhsData.count {
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
        guard let rawData = rawData else {
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
           let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any] {
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
        print("[NOTE] 开始更新内容，响应结构: \(noteDetails.keys)")
        
        var entry: [String: Any]?
        
        // 尝试不同的响应格式
        // 格式1: {"data": {"entry": {...}}}
        if let data = noteDetails["data"] as? [String: Any],
           let dataEntry = data["entry"] as? [String: Any] {
            entry = dataEntry
            print("[NOTE] 使用格式1: data->entry")
        }
        // 格式2: 直接是entry对象
        else if let directEntry = noteDetails["entry"] as? [String: Any] {
            entry = directEntry
            print("[NOTE] 使用格式2: 直接entry")
        }
        // 格式3: 响应本身就是entry
        else if noteDetails["id"] != nil || noteDetails["content"] != nil {
            entry = noteDetails
            print("[NOTE] 使用格式3: 响应本身就是entry")
        }
        
        guard let entry = entry else {
            print("[NOTE] 错误：无法从响应中提取entry")
            print("[NOTE] 完整响应: \(noteDetails)")
            return
        }
        
        print("[NOTE] 找到entry，包含字段: \(entry.keys)")
        
        // 更新内容
        if let newContent = entry["content"] as? String {
            self.content = newContent
            print("[NOTE] 更新内容，长度: \(newContent.count)")
        } else {
            print("[NOTE] 警告：entry中没有content字段")
        }
        
        // 更新标题
        var newTitle: String? = nil
        
        // 首先尝试从extraInfo中获取
        if let extraInfo = entry["extraInfo"] as? String {
            print("[NOTE] 找到extraInfo: \(extraInfo.prefix(100))...")
            if let extraData = extraInfo.data(using: .utf8),
               let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
               let title = extraJson["title"] as? String, !title.isEmpty {
                newTitle = title
                print("[NOTE] 从extraInfo获取标题: \(title)")
            }
        }
        
        // 如果extraInfo中没有标题，尝试从entry直接获取
        if newTitle == nil, let title = entry["title"] as? String, !title.isEmpty {
            newTitle = title
            print("[NOTE] 从entry直接获取标题: \(title)")
        }
        
        // 不再从snippet或content中提取标题
        // 如果还是没有标题，保持为空或"未命名笔记_xxx"格式
        
        // 更新标题（如果找到了新的标题）
        if let title = newTitle, !title.isEmpty {
            self.title = title
            print("[NOTE] 最终标题: \(title)")
        } else {
            // 如果没有找到新的标题，且当前标题是"未命名笔记_xxx"格式，保持它
            // 否则，如果当前标题是从内容中提取的，清空它
            if !self.title.isEmpty && !self.title.hasPrefix("未命名笔记_") {
                // 检查当前标题是否可能是从内容中提取的
                // 如果是，清空它，让它显示为"无标题"
                self.title = ""
                print("[NOTE] 清空从内容中提取的标题")
            } else {
                print("[NOTE] 保持原标题: \(self.title)")
            }
        }
        
        // 更新其他字段
        if let modifyDate = entry["modifyDate"] as? TimeInterval {
            self.updatedAt = Date(timeIntervalSince1970: modifyDate / 1000)
            print("[NOTE] 更新修改时间: \(self.updatedAt)")
        }
        
        if let createDate = entry["createDate"] as? TimeInterval {
            self.createdAt = Date(timeIntervalSince1970: createDate / 1000)
            print("[NOTE] 更新创建时间: \(self.createdAt)")
        }
        
        if let folderId = entry["folderId"] as? String {
            self.folderId = folderId
            print("[NOTE] 更新文件夹ID: \(folderId)")
        } else if let folderId = entry["folderId"] as? Int {
            self.folderId = String(folderId)
            print("[NOTE] 更新文件夹ID: \(folderId)")
        }
        
        // 更新收藏状态
        if let isStarred = entry["isStarred"] as? Bool {
            self.isStarred = isStarred
            print("[NOTE] 更新收藏状态: \(isStarred)")
        }
        
        // 更新rawData
        var updatedRawData = self.rawData ?? [:]
        for (key, value) in entry {
            updatedRawData[key] = value
        }
        self.rawData = updatedRawData
    }
    
    // MARK: - 内容访问/更新工具
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
            "tags": tags
        ]
        
        // 保留原始数据中的其他字段
        if let rawData = rawData {
            for (key, value) in rawData {
                if !data.keys.contains(key) {
                    data[key] = value
                }
            }
        }
        
        return data
    }
}
