import Foundation

/// 文件夹事件
enum FolderEvent: AppEvent {
    // 意图事件
    case created(name: String)
    case renamed(folderId: String, newName: String)
    case deleted(folderId: String)
    case folderSaved(Folder)
    case batchSaved([Folder])
    case folderIdMigrated(oldId: String, newId: String)

    // 结果事件
    case saved(Folder)
    case listChanged([Folder])

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
