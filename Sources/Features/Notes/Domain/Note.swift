import Foundation

/// 笔记数据模型
///
/// 纯数据结构，表示一条笔记的所有信息。
/// 转换逻辑（服务器数据解析、格式转换等）已迁移到 NoteMapper。
public struct Note: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var content: String
    public var folderId: String
    public var isStarred = false
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String] = []

    public var snippet: String?
    public var colorId: Int
    public var type: String
    public var serverTag: String?
    public var status: String
    public var settingJson: String?
    public var extraInfoJson: String?

    public init(
        id: String,
        title: String,
        content: String,
        folderId: String,
        isStarred: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        tags: [String] = [],
        snippet: String? = nil,
        colorId: Int = 0,
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
        self.snippet = snippet
        self.colorId = colorId
        self.type = type
        self.serverTag = serverTag
        self.status = status
        self.settingJson = settingJson
        self.extraInfoJson = extraInfoJson
    }

    /// 比较关键字段是否相同
    public static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.content == rhs.content &&
            lhs.folderId == rhs.folderId &&
            lhs.isStarred == rhs.isStarred &&
            lhs.updatedAt == rhs.updatedAt &&
            lhs.serverTag == rhs.serverTag &&
            lhs.status == rhs.status
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - 内容访问

    /// 用于编辑/展示的主 XML 内容
    var primaryXMLContent: String {
        if !content.isEmpty {
            return content
        }

        if let snippet, !snippet.isEmpty {
            if snippet.contains("<text") || snippet.contains("<new-format") {
                if snippet.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<new-format/>") {
                    return snippet
                } else {
                    return "<new-format/>" + snippet
                }
            } else {
                return "<new-format/><text indent=\"1\">\(snippet)</text>"
            }
        }

        return ""
    }

    /// 返回一个内容被更新为指定 XML 的新 Note
    func withPrimaryXMLContent(_ xml: String) -> Note {
        var copy = self
        copy.content = xml
        return copy
    }
}

// MARK: - 图片附件扩展

public extension Note {
    /// 图片附件列表
    var imageAttachments: [NoteImageAttachment] {
        guard let settingJson, !settingJson.isEmpty else { return [] }
        guard let jsonData = settingJson.data(using: .utf8) else { return [] }

        do {
            guard let setting = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return [] }
            guard let dataArray = setting["data"] as? [[String: Any]] else { return [] }

            return dataArray.compactMap { dict -> NoteImageAttachment? in
                guard let fileId = dict["fileId"] as? String,
                      let mimeType = dict["mimeType"] as? String,
                      mimeType.hasPrefix("image/")
                else { return nil }

                let size = dict["size"] as? Int
                return NoteImageAttachment(fileId: fileId, mimeType: mimeType, size: size)
            }
        } catch {
            LogService.shared.error(.storage, "解析 settingJson 失败: \(error)")
            return []
        }
    }

    var firstImageId: String? {
        imageAttachments.first?.fileId
    }

    var hasImages: Bool {
        !imageAttachments.isEmpty
    }

    var hasAudio: Bool {
        content.contains("<sound fileid=")
    }
}
