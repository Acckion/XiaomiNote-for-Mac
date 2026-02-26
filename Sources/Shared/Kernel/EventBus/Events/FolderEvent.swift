import Foundation

/// 文件夹事件
public enum FolderEvent: AppEvent {
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
