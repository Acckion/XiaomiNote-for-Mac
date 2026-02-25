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
    @Published public var selectedFolderId: String?
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
        let storeNotes = await noteStore.notes
        folders = ensureSystemFolders(in: storeFolders, notes: storeNotes)

        folderEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: FolderEvent.self)
            for await event in stream {
                guard !Task.isCancelled else { break }
                switch event {
                case let .listChanged(updatedFolders):
                    let currentNotes = await noteStore.notes
                    folders = ensureSystemFolders(in: updatedFolders, notes: currentNotes)
                default:
                    break
                }
            }
        }
    }

    // MARK: - 系统文件夹注入

    /// 确保系统文件夹（所有笔记、置顶笔记、私密笔记）始终存在
    private func ensureSystemFolders(in folderList: [Folder], notes: [Note]) -> [Folder] {
        var result = folderList

        let allNotesCount = notes.count
        let starredCount = notes.count(where: { $0.isStarred })
        let privateCount = notes.count(where: { $0.folderId == "2" })

        let hasAllNotes = result.contains { $0.id == "0" }
        let hasStarred = result.contains { $0.id == "starred" }
        let hasPrivate = result.contains { $0.id == "2" }

        // 按固定顺序插入缺失的系统文件夹
        if !hasPrivate {
            result.insert(Folder(id: "2", name: "私密笔记", count: privateCount, isSystem: true), at: 0)
        }
        if !hasStarred {
            result.insert(Folder(id: "starred", name: "置顶", count: starredCount, isSystem: true), at: 0)
        }
        if !hasAllNotes {
            result.insert(Folder(id: "0", name: "所有笔记", count: allNotesCount, isSystem: true), at: 0)
        }

        // 更新已存在的系统文件夹的笔记数量
        result = result.map { folder in
            switch folder.id {
            case "0":
                var f = folder
                f.count = allNotesCount
                return f
            case "starred":
                var f = folder
                f.count = starredCount
                return f
            case "2":
                var f = folder
                f.count = privateCount
                return f
            default:
                return folder
            }
        }

        // 排序：系统文件夹在前，按固定顺序
        return result.sorted { f1, f2 in
            if f1.isSystem, !f2.isSystem { return true }
            if !f1.isSystem, f2.isSystem { return false }
            if f1.isSystem, f2.isSystem {
                let order = ["0", "starred", "2"]
                let i1 = order.firstIndex(of: f1.id) ?? Int.max
                let i2 = order.firstIndex(of: f2.id) ?? Int.max
                return i1 < i2
            }
            return f1.createdAt < f2.createdAt
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
