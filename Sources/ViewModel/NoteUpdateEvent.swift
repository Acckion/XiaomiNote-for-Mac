import Foundation

// MARK: - 笔记更新事件

/// 笔记更新事件
///
/// 描述笔记的各种更新类型，用于确定是否需要触发列表动画和保持选择状态
///
public enum NoteUpdateEvent: Equatable {
    /// 笔记内容变化
    /// - Parameter noteId: 笔记ID
    /// - Parameter newContent: 新内容
    case contentChanged(noteId: String, newContent: String)

    /// 笔记标题变化
    /// - Parameter noteId: 笔记ID
    /// - Parameter newTitle: 新标题
    case titleChanged(noteId: String, newTitle: String)

    /// 笔记时间戳更新
    /// - Parameter noteId: 笔记ID
    /// - Parameter newTimestamp: 新时间戳
    case timestampUpdated(noteId: String, newTimestamp: Date)

    /// 笔记元数据变化（如标签、收藏状态等）
    /// - Parameter noteId: 笔记ID
    case metadataChanged(noteId: String)

    /// 笔记收藏状态变化
    /// - Parameter noteId: 笔记ID
    /// - Parameter isStarred: 是否收藏
    case starredChanged(noteId: String, isStarred: Bool)

    /// 笔记文件夹变化
    /// - Parameter noteId: 笔记ID
    /// - Parameter newFolderId: 新文件夹ID
    case folderChanged(noteId: String, newFolderId: String)

    /// 笔记被删除
    /// - Parameter noteId: 笔记ID
    case deleted(noteId: String)

    /// 笔记被创建
    /// - Parameter noteId: 笔记ID
    case created(noteId: String)

    /// 批量更新
    /// - Parameter noteIds: 笔记ID列表
    case batchUpdate(noteIds: [String])

    // MARK: - 计算属性

    /// 是否需要触发列表动画
    ///
    /// 当笔记的排序位置可能改变时返回 true
    ///
    public var requiresListAnimation: Bool {
        switch self {
        case .timestampUpdated:
            // 时间戳变化可能导致排序位置改变
            true
        case .titleChanged:
            // 如果按标题排序，标题变化可能导致位置改变
            true
        case .starredChanged:
            // 收藏状态变化可能影响在"置顶"文件夹中的显示
            true
        case .folderChanged:
            // 文件夹变化会影响笔记在列表中的显示
            true
        case .deleted, .created:
            // 删除和创建需要动画
            true
        case .batchUpdate:
            // 批量更新需要动画
            true
        case .contentChanged, .metadataChanged:
            // 内容和元数据变化通常不影响排序
            false
        }
    }

    /// 是否需要保持选择状态
    ///
    /// 大多数更新操作都应该保持当前的选择状态
    ///
    public var shouldPreserveSelection: Bool {
        switch self {
        case .deleted:
            // 删除笔记后不能保持选择（笔记已不存在）
            false
        case .folderChanged:
            // 文件夹变化后，如果笔记移出当前文件夹，可能需要清除选择
            // 但这个决定应该由 ViewStateCoordinator 根据上下文做出
            true
        default:
            // 其他所有更新都应该保持选择状态
            true
        }
    }

    /// 获取关联的笔记ID
    public var noteId: String? {
        switch self {
        case let .contentChanged(noteId, _),
             let .titleChanged(noteId, _),
             let .timestampUpdated(noteId, _),
             let .metadataChanged(noteId),
             let .starredChanged(noteId, _),
             let .folderChanged(noteId, _),
             let .deleted(noteId),
             let .created(noteId):
            noteId
        case .batchUpdate:
            nil
        }
    }

    /// 获取关联的笔记ID列表
    public var noteIds: [String] {
        switch self {
        case let .batchUpdate(noteIds):
            return noteIds
        default:
            if let noteId {
                return [noteId]
            }
            return []
        }
    }

    /// 事件描述（用于日志）
    public var logDescription: String {
        switch self {
        case let .contentChanged(noteId, _):
            "内容变化: \(noteId)"
        case let .titleChanged(noteId, newTitle):
            "标题变化: \(noteId) -> \(newTitle)"
        case let .timestampUpdated(noteId, newTimestamp):
            "时间戳更新: \(noteId) -> \(newTimestamp)"
        case let .metadataChanged(noteId):
            "元数据变化: \(noteId)"
        case let .starredChanged(noteId, isStarred):
            "收藏状态变化: \(noteId) -> \(isStarred)"
        case let .folderChanged(noteId, newFolderId):
            "文件夹变化: \(noteId) -> \(newFolderId)"
        case let .deleted(noteId):
            "笔记删除: \(noteId)"
        case let .created(noteId):
            "笔记创建: \(noteId)"
        case let .batchUpdate(noteIds):
            "批量更新: \(noteIds.count) 个笔记"
        }
    }
}

// MARK: - 更新事件构建器

/// 更新事件构建器
///
/// 提供便捷方法来创建更新事件
public extension NoteUpdateEvent {
    /// 从笔记变化创建更新事件
    ///
    /// 比较两个笔记对象，确定发生了什么类型的变化
    ///
    /// - Parameters:
    ///   - oldNote: 旧笔记
    ///   - newNote: 新笔记
    /// - Returns: 更新事件列表
    static func fromNoteChange(oldNote: Note, newNote: Note) -> [NoteUpdateEvent] {
        var events: [NoteUpdateEvent] = []

        // 检查内容变化
        if oldNote.content != newNote.content {
            events.append(.contentChanged(noteId: newNote.id, newContent: newNote.content))
        }

        // 检查标题变化
        if oldNote.title != newNote.title {
            events.append(.titleChanged(noteId: newNote.id, newTitle: newNote.title))
        }

        // 检查时间戳变化
        if oldNote.updatedAt != newNote.updatedAt {
            events.append(.timestampUpdated(noteId: newNote.id, newTimestamp: newNote.updatedAt))
        }

        // 检查收藏状态变化
        if oldNote.isStarred != newNote.isStarred {
            events.append(.starredChanged(noteId: newNote.id, isStarred: newNote.isStarred))
        }

        // 检查文件夹变化
        if oldNote.folderId != newNote.folderId {
            events.append(.folderChanged(noteId: newNote.id, newFolderId: newNote.folderId))
        }

        // 检查标签变化
        if oldNote.tags != newNote.tags {
            events.append(.metadataChanged(noteId: newNote.id))
        }

        return events
    }
}
