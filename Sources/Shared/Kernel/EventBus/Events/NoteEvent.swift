import Foundation

/// 笔记元数据变更
public struct NoteMetadataChanges: Sendable {
    public var folderId: String?
    public var isStarred: Bool?
    public var colorId: Int?
    public var status: Int?

    public init(folderId: String? = nil, isStarred: Bool? = nil, colorId: Int? = nil, status: Int? = nil) {
        self.folderId = folderId
        self.isStarred = isStarred
        self.colorId = colorId
        self.status = status
    }
}

/// 笔记事件
public enum NoteEvent: AppEvent {
    // 意图事件
    case created(Note)
    case contentUpdated(noteId: String, title: String, content: String)
    case metadataUpdated(noteId: String, changes: NoteMetadataChanges)
    case deleted(noteId: String, tag: String?)
    case moved(noteId: String, fromFolder: String, toFolder: String)
    case starred(noteId: String, isStarred: Bool)

    // 结果事件
    case saved(Note)
    case listChanged([Note])
    case idMigrated(oldId: String, newId: String, note: Note)

    // MARK: - AppEvent

    public var id: UUID {
        UUID()
    }

    public var timestamp: Date {
        Date()
    }

    public var source: EventSource {
        .user
    }
}
