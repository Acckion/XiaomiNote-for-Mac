import Foundation

/// 笔记元数据变更
struct NoteMetadataChanges: Sendable {
    var folderId: String?
    var isStarred: Bool?
    var colorId: Int?
    var status: Int?
}

/// 笔记事件
enum NoteEvent: AppEvent {
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

    var id: UUID {
        UUID()
    }

    var timestamp: Date {
        Date()
    }

    var source: EventSource {
        .user
    }
}
