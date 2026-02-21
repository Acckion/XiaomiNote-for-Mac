import SwiftUI

/// 文件夹状态管理
///
/// 替代 NotesViewModel 中的文件夹管理功能，
/// 负责文件夹的选择、创建、重命名、删除和排序设置。
@MainActor
public final class FolderState: ObservableObject {
    // MARK: - Published 属性

    @Published var folders: [Folder] = []
    @Published public var selectedFolder: Folder?
    @Published var selectedFolderId: String?
    @Published var folderSortOrders: [String: NoteSortOrder] = [:]

    // MARK: - 依赖

    private let eventBus: EventBus
    private let noteStore: NoteStore

    // MARK: - 事件订阅任务

    private var folderEventTask: Task<Void, Never>?

    // MARK: - 初始化

    init(eventBus: EventBus = .shared, noteStore: NoteStore) {
        self.eventBus = eventBus
        self.noteStore = noteStore
    }

    // MARK: - 生命周期

    func start() async {
        let storeFolders = await noteStore.folders
        folders = storeFolders

        folderEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: FolderEvent.self)
            for await event in stream {
                guard !Task.isCancelled else { break }
                switch event {
                case let .listChanged(updatedFolders):
                    folders = updatedFolders
                default:
                    break
                }
            }
        }
    }

    func stop() {
        folderEventTask?.cancel()
        folderEventTask = nil
    }

    // MARK: - 文件夹选择

    func selectFolder(_ folder: Folder?) {
        selectedFolder = folder
        selectedFolderId = folder?.id
    }

    // MARK: - 文件夹操作

    func createFolder(name: String) async {
        await eventBus.publish(FolderEvent.created(name: name))
    }

    func renameFolder(_ folder: Folder, newName: String) async {
        await eventBus.publish(FolderEvent.renamed(folderId: folder.id, newName: newName))
    }

    func deleteFolder(_ folder: Folder) async {
        await eventBus.publish(FolderEvent.deleted(folderId: folder.id))
    }

    func toggleFolderPin(_ folder: Folder) async {
        var updated = folder
        updated.isPinned = !folder.isPinned
        await eventBus.publish(FolderEvent.folderSaved(updated))
    }

    // MARK: - 排序设置

    func setFolderSortOrder(_ folder: Folder, sortOrder: NoteSortOrder) {
        folderSortOrders[folder.id] = sortOrder
    }

    func getFolderSortOrder(_ folder: Folder) -> NoteSortOrder? {
        folderSortOrders[folder.id]
    }

    // MARK: - 计算属性

    /// 未分类文件夹（虚拟文件夹），笔记数量从 NoteStore 获取
    var uncategorizedFolder: Folder {
        // 使用同步方式计算，基于已知的文件夹信息
        // 实际笔记数量需要外部设置或通过 NoteListState 获取
        Folder(id: "uncategorized", name: "未分类", count: 0, isSystem: false)
    }

    /// 根据笔记列表计算未分类文件夹
    func uncategorizedFolder(noteCount: Int) -> Folder {
        Folder(id: "uncategorized", name: "未分类", count: noteCount, isSystem: false)
    }
}
