import Foundation

/// 文件上传操作数据
///
/// 用于 imageUpload 和 audioUpload 操作的类型安全数据结构，
/// 替代手动 JSON 字典构建。
public struct FileUploadOperationData: Codable, Sendable {
    /// 临时文件 ID（格式：local_xxx）
    let temporaryFileId: String
    /// 本地文件路径
    let localFilePath: String
    /// 文件名
    let fileName: String
    /// MIME 类型
    let mimeType: String
    /// 所属笔记 ID
    let noteId: String

    /// 编码为 Data
    func encoded() -> Data {
        try! JSONEncoder().encode(self)
    }

    /// 从 Data 解码
    static func decoded(from data: Data) throws -> FileUploadOperationData {
        try JSONDecoder().decode(FileUploadOperationData.self, from: data)
    }
}
