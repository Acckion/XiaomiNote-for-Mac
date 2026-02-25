import Foundation

/// 笔记操作错误
public enum NoteOperationError: Error, Sendable {
    /// 保存失败
    case saveFailed(String)
    /// 上传失败
    case uploadFailed(String)
    /// 网络不可用
    case networkUnavailable
    /// 笔记不存在
    case noteNotFound(noteId: String)
    /// 持久化失败
    case persistenceFailed(String)
    /// 临时 ID 笔记创建失败
    case temporaryNoteCreationFailed(String)
}
