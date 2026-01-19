import Foundation

/// 图片附件信息
///
/// 从笔记的 `settingJson` 字段中解析出的图片附件信息。
/// 用于在笔记列表中显示图片预览。
///
/// **数据来源**：
/// - `settingJson` 字段包含一个 JSON 对象
/// - JSON 对象中的 `data` 数组包含附件信息
/// - 每个附件包含 `fileId`、`mimeType`、`size` 等字段
///
/// **示例 JSON**：
/// ```json
/// {
///   "data": [
///     {
///       "fileId": "1315204657.mqD6sEiru5CFpGR0vUZaMA",
///       "mimeType": "image/png",
///       "size": 118307
///     }
///   ]
/// }
/// ```
public struct ImageAttachment: Codable, Identifiable, Equatable, Hashable {
    /// 文件ID（完整格式：userId.fileId）
    public let fileId: String
    
    /// MIME 类型（如 "image/png", "image/jpeg"）
    public let mimeType: String
    
    /// 文件大小（字节）
    public let size: Int?
    
    /// Identifiable 协议要求的 id
    public var id: String { fileId }
    
    /// 文件类型（从 mimeType 提取）
    ///
    /// 例如：
    /// - "image/png" -> "png"
    /// - "image/jpeg" -> "jpg"
    /// - "image/gif" -> "gif"
    public var fileType: String {
        // 从 mimeType 提取文件扩展名
        let components = mimeType.split(separator: "/")
        guard components.count == 2 else {
            return "jpg" // 默认为 jpg
        }
        
        let type = String(components[1]).lowercased()
        
        // 处理特殊情况
        switch type {
        case "jpeg":
            return "jpg"
        default:
            return type
        }
    }
    
    public init(fileId: String, mimeType: String, size: Int?) {
        self.fileId = fileId
        self.mimeType = mimeType
        self.size = size
    }
}
