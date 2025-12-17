import Foundation

struct Note: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var content: String
    var folderId: String
    var isStarred: Bool = false
    var createdAt: Date
    var updatedAt: Date
    var tags: [String] = []
    
    // 小米笔记格式的原始数据
    var rawData: [String: Any]?
    
    enum CodingKeys: String, CodingKey {
        case id, title, content, folderId, isStarred, createdAt, updatedAt, tags, rawData
    }
    
    init(id: String, title: String, content: String, folderId: String, isStarred: Bool = false, 
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
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(folderId, forKey: .folderId)
        try container.encode(isStarred, forKey: .isStarred)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(tags, forKey: .tags)
        
        // 编码 rawData 为 JSON 数据
        if let rawData = rawData {
            let jsonData = try JSONSerialization.data(withJSONObject: rawData, options: [])
            try container.encode(jsonData, forKey: .rawData)
        } else {
            try container.encodeNil(forKey: .rawData)
        }
    }
    
    // 自定义解码
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        folderId = try container.decode(String.self, forKey: .folderId)
        isStarred = try container.decode(Bool.self, forKey: .isStarred)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        tags = try container.decode([String].self, forKey: .tags)
        
        // 解码 rawData
        if let jsonData = try? container.decode(Data?.self, forKey: .rawData) {
            rawData = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        } else {
            rawData = nil
        }
    }
    
    // 自定义 Equatable 实现
    static func == (lhs: Note, rhs: Note) -> Bool {
        // 比较 rawData 时，只比较关键字段
        let lhsRawData = lhs.rawData ?? [:]
        let rhsRawData = rhs.rawData ?? [:]
        
        // 将 rawData 转换为字符串进行比较
        let lhsRawDataString = String(describing: lhsRawData.sorted(by: { $0.key < $1.key }))
        let rhsRawDataString = String(describing: rhsRawData.sorted(by: { $0.key < $1.key }))
        
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.content == rhs.content &&
               lhs.folderId == rhs.folderId &&
               lhs.isStarred == rhs.isStarred &&
               lhs.createdAt == rhs.createdAt &&
               lhs.updatedAt == rhs.updatedAt &&
               lhs.tags == rhs.tags &&
               lhsRawDataString == rhsRawDataString
    }
    
    // Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(content)
        hasher.combine(folderId)
        hasher.combine(isStarred)
        hasher.combine(createdAt)
        hasher.combine(updatedAt)
        hasher.combine(tags)
        
        // 将 rawData 转换为字符串进行哈希
        if let rawData = rawData {
            let rawDataString = String(describing: rawData.sorted(by: { $0.key < $1.key }))
            hasher.combine(rawDataString)
        }
    }
    
    // 从小米笔记API数据创建
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
        
        // 如果extraInfo中没有标题，使用snippet的第一行
        if title.isEmpty, let snippet = data["snippet"] as? String {
            title = snippet.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        
        // 如果还是没有标题，使用ID
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
    
    // 从笔记详情API响应更新内容
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
        // 首先尝试从extraInfo中获取
        if let extraInfo = entry["extraInfo"] as? String {
            print("[NOTE] 找到extraInfo: \(extraInfo.prefix(100))...")
            if let extraData = extraInfo.data(using: .utf8),
               let extraJson = try? JSONSerialization.jsonObject(with: extraData) as? [String: Any],
               let newTitle = extraJson["title"] as? String {
                self.title = newTitle
                print("[NOTE] 从extraInfo更新标题: \(newTitle)")
            }
        }
        
        // 如果extraInfo中没有标题，尝试从entry直接获取
        if let newTitle = entry["title"] as? String, !newTitle.isEmpty {
            self.title = newTitle
            print("[NOTE] 从entry直接更新标题: \(newTitle)")
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
        
        print("[NOTE] 内容更新完成，最终内容长度: \(self.content.count)")
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
    
    // 转换为小米笔记API格式
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
