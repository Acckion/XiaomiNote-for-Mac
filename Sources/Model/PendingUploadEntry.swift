import Foundation

/// 待上传条目
///
/// 记录有本地修改等待上传的笔记信息
/// 用于 PendingUploadRegistry 和 DatabaseService
public struct PendingUploadEntry: Codable, Equatable, Sendable {
    /// 笔记 ID
    public let noteId: String
    /// 本地保存时间戳
    public let localSaveTimestamp: Date
    /// 注册时间
    public let registeredAt: Date

    public init(noteId: String, localSaveTimestamp: Date, registeredAt: Date = Date()) {
        self.noteId = noteId
        self.localSaveTimestamp = localSaveTimestamp
        self.registeredAt = registeredAt
    }
}
