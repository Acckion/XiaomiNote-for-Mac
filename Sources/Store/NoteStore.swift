import Foundation

/// 笔记数据仓库
///
/// 作为唯一的数据库写入者，订阅意图事件，执行 DB 操作，发布结果事件。
/// 内部维护笔记和文件夹的内存缓存，提供只读查询方法。
actor NoteStore {
    private let db: DatabaseService
    private let eventBus: EventBus
    private(set) var notes: [Note] = []
    private(set) var folders: [Folder] = []
    private var noteEventTask: Task<Void, Never>?
    private var syncEventTask: Task<Void, Never>?
    private var folderEventTask: Task<Void, Never>?

    init(db: DatabaseService, eventBus: EventBus) {
        self.db = db
        self.eventBus = eventBus
    }

    // MARK: - 生命周期

    func start() async {
        do {
            notes = try db.getAllNotes()
            folders = try db.loadFolders()
        } catch {
            LogService.shared.error(.storage, "NoteStore 加载初始数据失败: \(error)")
        }

        noteEventTask = Task { await subscribeNoteEvents() }
        syncEventTask = Task { await subscribeSyncEvents() }
        folderEventTask = Task { await subscribeFolderEvents() }
    }

    func stop() {
        noteEventTask?.cancel()
        syncEventTask?.cancel()
        folderEventTask?.cancel()
    }

    // MARK: - 只读查询

    func getNote(byId id: String) -> Note? {
        notes.first { $0.id == id }
    }

    func getNotes(inFolder folderId: String) -> [Note] {
        notes.filter { $0.folderId == folderId }
    }

    /// 从 DB 读取最新 serverTag，确保不使用过期缓存
    func getLatestServerTag(noteId: String) -> String? {
        do {
            let note = try db.loadNote(noteId: noteId)
            return note?.serverTag
        } catch {
            LogService.shared.error(.storage, "NoteStore 读取 serverTag 失败: \(error)")
            return nil
        }
    }

    // MARK: - 事件订阅

    private func subscribeNoteEvents() async {
        let stream = await eventBus.subscribe(to: NoteEvent.self)
        for await event in stream {
            guard !Task.isCancelled else { break }
            await handleNoteEvent(event)
        }
    }

    private func subscribeSyncEvents() async {
        let stream = await eventBus.subscribe(to: SyncEvent.self)
        for await event in stream {
            guard !Task.isCancelled else { break }
            await handleSyncEvent(event)
        }
    }

    private func subscribeFolderEvents() async {
        let stream = await eventBus.subscribe(to: FolderEvent.self)
        for await event in stream {
            guard !Task.isCancelled else { break }
            await handleFolderEvent(event)
        }
    }

    // MARK: - 笔记事件处理

    private func handleNoteEvent(_ event: NoteEvent) async {
        switch event {
        case let .created(note):
            do {
                try db.saveNote(note)
                refreshNotesCache()
                await eventBus.publish(NoteEvent.saved(note))
                await eventBus.publish(NoteEvent.listChanged(notes))
            } catch {
                LogService.shared.error(.storage, "NoteStore 保存新笔记失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "createNote", errorMessage: error.localizedDescription))
            }

        case let .contentUpdated(noteId, title, content):
            do {
                guard var note = try db.loadNote(noteId: noteId) else {
                    LogService.shared.warning(.storage, "NoteStore contentUpdated: 笔记不存在 \(noteId)")
                    return
                }
                note.title = title
                note.content = content
                note.updatedAt = Date()
                try db.saveNote(note)
                refreshNotesCache()
                await eventBus.publish(NoteEvent.saved(note))
                await eventBus.publish(NoteEvent.listChanged(notes))
            } catch {
                LogService.shared.error(.storage, "NoteStore 更新笔记内容失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "contentUpdated", errorMessage: error.localizedDescription))
            }

        case let .metadataUpdated(noteId, changes):
            await applyMetadataChanges(noteId: noteId, changes: changes)

        case let .deleted(noteId, _):
            do {
                try db.deleteNote(noteId: noteId)
                refreshNotesCache()
                await eventBus.publish(NoteEvent.listChanged(notes))
            } catch {
                LogService.shared.error(.storage, "NoteStore 删除笔记失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "deleteNote", errorMessage: error.localizedDescription))
            }

        case let .moved(noteId, _, toFolder):
            let changes = NoteMetadataChanges(folderId: toFolder)
            await applyMetadataChanges(noteId: noteId, changes: changes)

        case let .starred(noteId, isStarred):
            let changes = NoteMetadataChanges(isStarred: isStarred)
            await applyMetadataChanges(noteId: noteId, changes: changes)

        case .saved, .listChanged:
            break
        }
    }

    // MARK: - 同步事件处理

    private func handleSyncEvent(_ event: SyncEvent) async {
        switch event {
        case let .noteDownloaded(note):
            do {
                try db.saveNote(note)
                refreshNotesCache()
                await eventBus.publish(NoteEvent.saved(note))
            } catch {
                LogService.shared.error(.storage, "NoteStore 保存下载笔记失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "noteDownloaded", errorMessage: error.localizedDescription))
            }

        case let .tagUpdated(noteId, newTag):
            do {
                guard var note = try db.loadNote(noteId: noteId) else {
                    LogService.shared.warning(.storage, "NoteStore tagUpdated: 笔记不存在 \(noteId)")
                    return
                }
                note.serverTag = newTag
                try db.saveNote(note)
                refreshNotesCache()
                await eventBus.publish(NoteEvent.saved(note))
            } catch {
                LogService.shared.error(.storage, "NoteStore 更新 serverTag 失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "tagUpdated", errorMessage: error.localizedDescription))
            }

        case .completed:
            refreshNotesCache()
            await eventBus.publish(NoteEvent.listChanged(notes))

        case .requested, .started, .progress, .failed:
            break
        }
    }

    // MARK: - 文件夹事件处理

    private func handleFolderEvent(_ event: FolderEvent) async {
        switch event {
        case let .created(name):
            let folder = Folder(
                id: UUID().uuidString,
                name: name,
                count: 0
            )
            do {
                try db.saveFolders([folder])
                refreshFoldersCache()
                await eventBus.publish(FolderEvent.saved(folder))
                await eventBus.publish(FolderEvent.listChanged(folders))
            } catch {
                LogService.shared.error(.storage, "NoteStore 创建文件夹失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "createFolder", errorMessage: error.localizedDescription))
            }

        case let .renamed(folderId, newName):
            guard var folder = folders.first(where: { $0.id == folderId }) else {
                LogService.shared.warning(.storage, "NoteStore renamed: 文件夹不存在 \(folderId)")
                return
            }
            folder.name = newName
            do {
                try db.saveFolders([folder])
                refreshFoldersCache()
                await eventBus.publish(FolderEvent.listChanged(folders))
            } catch {
                LogService.shared.error(.storage, "NoteStore 重命名文件夹失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "renameFolder", errorMessage: error.localizedDescription))
            }

        case let .deleted(folderId):
            do {
                try db.deleteFolder(folderId: folderId)
                refreshFoldersCache()
                await eventBus.publish(FolderEvent.listChanged(folders))
            } catch {
                LogService.shared.error(.storage, "NoteStore 删除文件夹失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "deleteFolder", errorMessage: error.localizedDescription))
            }

        case let .folderSaved(folder):
            do {
                try db.saveFolders([folder])
                refreshFoldersCache()
                await eventBus.publish(FolderEvent.saved(folder))
                await eventBus.publish(FolderEvent.listChanged(folders))
            } catch {
                LogService.shared.error(.storage, "NoteStore 保存文件夹失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "folderSaved", errorMessage: error.localizedDescription))
            }

        case let .batchSaved(folderList):
            do {
                try db.saveFolders(folderList)
                refreshFoldersCache()
                await eventBus.publish(FolderEvent.listChanged(folders))
            } catch {
                LogService.shared.error(.storage, "NoteStore 批量保存文件夹失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "batchSaved", errorMessage: error.localizedDescription))
            }

        case let .folderIdMigrated(oldId, newId):
            do {
                try db.updateNotesFolderId(oldFolderId: oldId, newFolderId: newId)
                try db.deleteFolder(folderId: oldId)
                refreshNotesCache()
                refreshFoldersCache()
                await eventBus.publish(NoteEvent.listChanged(notes))
                await eventBus.publish(FolderEvent.listChanged(folders))
            } catch {
                LogService.shared.error(.storage, "NoteStore 文件夹ID迁移失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "folderIdMigrated", errorMessage: error.localizedDescription))
            }

        case .saved, .listChanged:
            break
        }
    }

    // MARK: - 辅助方法

    /// 应用元数据变更到指定笔记
    private func applyMetadataChanges(noteId: String, changes: NoteMetadataChanges) async {
        do {
            guard var note = try db.loadNote(noteId: noteId) else {
                LogService.shared.warning(.storage, "NoteStore metadataUpdated: 笔记不存在 \(noteId)")
                return
            }
            if let folderId = changes.folderId { note.folderId = folderId }
            if let isStarred = changes.isStarred { note.isStarred = isStarred }
            if let colorId = changes.colorId { note.colorId = colorId }
            if let status = changes.status { note.status = String(status) }
            note.updatedAt = Date()
            try db.saveNote(note)
            refreshNotesCache()
            await eventBus.publish(NoteEvent.saved(note))
            await eventBus.publish(NoteEvent.listChanged(notes))
        } catch {
            LogService.shared.error(.storage, "NoteStore 更新笔记元数据失败: \(error)")
            await eventBus.publish(ErrorEvent.storageFailed(operation: "metadataUpdated", errorMessage: error.localizedDescription))
        }
    }

    private func refreshNotesCache() {
        do {
            notes = try db.getAllNotes()
        } catch {
            LogService.shared.error(.storage, "NoteStore 刷新笔记缓存失败: \(error)")
        }
    }

    private func refreshFoldersCache() {
        do {
            folders = try db.loadFolders()
        } catch {
            LogService.shared.error(.storage, "NoteStore 刷新文件夹缓存失败: \(error)")
        }
    }
}
