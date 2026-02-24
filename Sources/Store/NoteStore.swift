import Foundation

/// 笔记数据仓库
///
/// 作为唯一的数据库写入者，订阅意图事件，执行 DB 操作，发布结果事件。
/// 内部维护笔记和文件夹的内存缓存，提供只读查询方法。
/// 同时管理活跃编辑状态、离线创建、保存上传等操作（原 NoteOperationCoordinator 的职责）。
public actor NoteStore {
    private let db: DatabaseService
    private let eventBus: EventBus
    private let operationQueue: UnifiedOperationQueue
    private let idMappingRegistry: IdMappingRegistry
    private let localStorage: LocalStorageService
    private let operationProcessor: OperationProcessor
    private(set) var notes: [Note] = []
    private(set) var folders: [Folder] = []
    private var noteEventTask: Task<Void, Never>?
    private var syncEventTask: Task<Void, Never>?
    private var folderEventTask: Task<Void, Never>?

    /// 当前活跃编辑的笔记 ID
    private var activeEditingNoteId: String?

    init(
        db: DatabaseService,
        eventBus: EventBus,
        operationQueue: UnifiedOperationQueue,
        idMappingRegistry: IdMappingRegistry,
        localStorage: LocalStorageService,
        operationProcessor: OperationProcessor
    ) {
        self.db = db
        self.eventBus = eventBus
        self.operationQueue = operationQueue
        self.idMappingRegistry = idMappingRegistry
        self.localStorage = localStorage
        self.operationProcessor = operationProcessor
    }

    // MARK: - 生命周期

    public func start() async {
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

    public func stop() {
        noteEventTask?.cancel()
        syncEventTask?.cancel()
        folderEventTask?.cancel()
    }

    // MARK: - 只读查询

    public func getNote(byId id: String) -> Note? {
        notes.first { $0.id == id }
    }

    public func getNotes(inFolder folderId: String) -> [Note] {
        notes.filter { $0.folderId == folderId }
    }

    /// 从 DB 读取最新 serverTag，确保不使用过期缓存
    public func getLatestServerTag(noteId: String) -> String? {
        do {
            let note = try db.loadNote(noteId: noteId)
            return note?.serverTag
        } catch {
            LogService.shared.error(.storage, "NoteStore 读取 serverTag 失败: \(error)")
            return nil
        }
    }

    // MARK: - 活跃编辑管理

    /// 设置活跃编辑笔记
    public func setActiveEditingNote(_ noteId: String?) {
        if let oldNoteId = activeEditingNoteId, oldNoteId != noteId {
            LogService.shared.debug(.sync, "切换活跃编辑笔记: \(oldNoteId.prefix(8))... -> \(noteId?.prefix(8) ?? "nil")")
        } else if let newNoteId = noteId {
            LogService.shared.debug(.sync, "设置活跃编辑笔记: \(newNoteId.prefix(8))...")
        } else {
            LogService.shared.debug(.sync, "清除活跃编辑状态")
        }
        activeEditingNoteId = noteId
    }

    /// 检查笔记是否正在编辑
    public func isNoteActivelyEditing(_ noteId: String) -> Bool {
        activeEditingNoteId == noteId
    }

    /// 获取当前活跃编辑的笔记 ID
    public func getActiveEditingNoteId() -> String? {
        activeEditingNoteId
    }

    // MARK: - 离线创建笔记

    /// 离线创建笔记
    ///
    /// 生成临时 ID，保存到 DB，创建 noteCreate 操作到 UnifiedOperationQueue。
    public func createNoteOffline(title: String, content: String, folderId: String) async throws -> Note {
        let temporaryId = NoteOperation.generateTemporaryId()
        LogService.shared.info(.sync, "离线创建笔记，临时 ID: \(temporaryId.prefix(16))...")

        let now = Date()
        let note = Note(
            id: temporaryId,
            title: title,
            content: content,
            folderId: folderId,
            isStarred: false,
            createdAt: now,
            updatedAt: now,
            tags: []
        )

        do {
            try db.saveNote(note)
            LogService.shared.debug(.sync, "离线笔记本地保存成功: \(temporaryId.prefix(16))...")
        } catch {
            LogService.shared.error(.sync, "离线笔记本地保存失败: \(error)")
            throw NoteOperationError.temporaryNoteCreationFailed(error.localizedDescription)
        }

        refreshNotesCache()
        await eventBus.publish(NoteEvent.saved(note))
        await eventBus.publish(NoteEvent.listChanged(notes))

        do {
            try operationQueue.enqueueNoteCreate(noteId: temporaryId)
            LogService.shared.debug(.sync, "已创建 noteCreate 操作: \(temporaryId.prefix(16))...")
        } catch {
            LogService.shared.error(.sync, "创建 noteCreate 操作失败: \(error)")
        }

        await triggerImmediateUploadIfOnline(noteId: temporaryId)

        return note
    }

    // MARK: - 临时笔记删除

    /// 删除临时 ID 笔记
    public func deleteTemporaryNote(_ noteId: String) async throws {
        guard NoteOperation.isTemporaryId(noteId) else {
            LogService.shared.warning(.sync, "不是临时 ID 笔记: \(noteId.prefix(8))...")
            return
        }

        LogService.shared.info(.sync, "删除临时 ID 笔记: \(noteId.prefix(16))...")

        do {
            try operationQueue.cancelOperations(for: noteId)
            LogService.shared.debug(.sync, "已取消待处理操作: \(noteId.prefix(16))...")
        } catch {
            LogService.shared.error(.sync, "取消操作失败: \(error)")
        }

        do {
            try db.deleteNote(noteId: noteId)
            LogService.shared.debug(.sync, "已删除本地笔记: \(noteId.prefix(16))...")
        } catch {
            LogService.shared.error(.sync, "删除本地笔记失败: \(error)")
            throw NoteOperationError.saveFailed(error.localizedDescription)
        }

        refreshNotesCache()
        await eventBus.publish(NoteEvent.listChanged(notes))

        if activeEditingNoteId == noteId {
            activeEditingNoteId = nil
            LogService.shared.debug(.sync, "清除活跃编辑状态")
        }
    }

    // MARK: - 笔记保存（本地 + 触发上传）

    /// 保存笔记并触发上传
    ///
    /// 保存到 DB，创建 cloudUpload 操作，网络可用时触发立即上传。
    public func saveNoteAndUpload(_ note: Note) async {
        let timestamp = Date()

        do {
            try db.saveNote(note)
        } catch {
            LogService.shared.error(.sync, "本地保存失败: \(error)")
            return
        }

        refreshNotesCache()
        await eventBus.publish(NoteEvent.saved(note))
        await eventBus.publish(NoteEvent.listChanged(notes))

        do {
            try operationQueue.enqueueCloudUpload(
                noteId: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId,
                localSaveTimestamp: timestamp
            )
        } catch {
            LogService.shared.error(.sync, "创建 cloudUpload 操作失败: \(error)")
        }

        await triggerImmediateUploadIfOnline(noteId: note.id)
    }

    /// 立即保存笔记并触发上传（不使用防抖）
    public func saveNoteImmediately(_ note: Note) async throws {
        let timestamp = Date()

        do {
            try db.saveNote(note)
            LogService.shared.debug(.sync, "立即保存成功: \(note.id.prefix(8))...")
        } catch {
            LogService.shared.error(.sync, "立即保存失败: \(error)")
            throw NoteOperationError.saveFailed(error.localizedDescription)
        }

        refreshNotesCache()
        await eventBus.publish(NoteEvent.saved(note))
        await eventBus.publish(NoteEvent.listChanged(notes))

        do {
            try operationQueue.enqueueCloudUpload(
                noteId: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId,
                localSaveTimestamp: timestamp
            )
            LogService.shared.debug(.sync, "已创建 cloudUpload 操作（立即）: \(note.id.prefix(8))...")
        } catch {
            LogService.shared.error(.sync, "创建 cloudUpload 操作失败: \(error)")
        }

        await triggerImmediateUploadIfOnline(noteId: note.id)
    }

    // MARK: - ID 更新处理

    /// 处理笔记创建成功，更新临时 ID 到正式 ID
    public func handleNoteCreateSuccess(temporaryId: String, serverId: String) async throws {
        LogService.shared.info(.sync, "处理笔记创建成功: \(temporaryId.prefix(16))... -> \(serverId.prefix(8))...")

        try await idMappingRegistry.updateAllReferences(localId: temporaryId, serverId: serverId)

        if activeEditingNoteId == temporaryId {
            activeEditingNoteId = serverId
            LogService.shared.debug(.sync, "更新活跃编辑笔记 ID: \(temporaryId.prefix(16))... -> \(serverId.prefix(8))...")
        }

        try idMappingRegistry.markCompleted(localId: temporaryId)

        refreshNotesCache()
        LogService.shared.info(.sync, "笔记创建成功处理完成: \(serverId.prefix(8))...")
    }

    // MARK: - 上传触发

    /// 网络可用时立即触发上传
    private func triggerImmediateUploadIfOnline(noteId: String) async {
        let isOnline = await MainActor.run { NetworkMonitor.shared.isConnected }

        if isOnline {
            if let operation = operationQueue.getPendingUpload(for: noteId) {
                await operationProcessor.processImmediately(operation)
            }
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

        case let .deleted(noteId, tag):
            // 临时笔记走专用删除流程，不入队云端操作
            if NoteOperation.isTemporaryId(noteId) {
                try? await deleteTemporaryNote(noteId)
                return
            }

            do {
                try db.deleteNote(noteId: noteId)
                refreshNotesCache()
                await eventBus.publish(NoteEvent.listChanged(notes))
            } catch {
                LogService.shared.error(.storage, "NoteStore 删除笔记失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "deleteNote", errorMessage: error.localizedDescription))
                return
            }

            // 入队 cloudDelete 操作，同步删除到云端
            if let deleteTag = tag {
                do {
                    try operationQueue.enqueueCloudDelete(noteId: noteId, tag: deleteTag)
                    LogService.shared.debug(.sync, "已入队 cloudDelete 操作: \(noteId.prefix(8))...")
                    await triggerImmediateUploadIfOnline(noteId: noteId)
                } catch {
                    LogService.shared.error(.sync, "创建 cloudDelete 操作失败: \(error)")
                }
            }

        case let .moved(noteId, _, toFolder):
            let changes = NoteMetadataChanges(folderId: toFolder)
            await applyMetadataChanges(noteId: noteId, changes: changes)

        case let .starred(noteId, isStarred):
            let changes = NoteMetadataChanges(isStarred: isStarred)
            await applyMetadataChanges(noteId: noteId, changes: changes)

        case .saved, .listChanged:
            break

        case let .idMigrated(oldId, newId, _):
            if activeEditingNoteId == oldId {
                activeEditingNoteId = newId
                LogService.shared.debug(.storage, "NoteStore 更新活跃编辑笔记 ID: \(oldId.prefix(8))... -> \(newId.prefix(8))...")
            }
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
                return
            }

            // 入队 folderCreate 操作，同步到云端
            do {
                try operationQueue.enqueueFolderCreate(folderId: folder.id, name: name)
                LogService.shared.debug(.sync, "已入队 folderCreate 操作: \(folder.id.prefix(8))...")
            } catch {
                LogService.shared.error(.sync, "创建 folderCreate 操作失败: \(error)")
            }

        case let .renamed(folderId, newName):
            guard var folder = folders.first(where: { $0.id == folderId }) else {
                LogService.shared.warning(.storage, "NoteStore renamed: 文件夹不存在 \(folderId)")
                return
            }
            let existingTag = folder.tag
            folder.name = newName
            do {
                try db.saveFolders([folder])
                refreshFoldersCache()
                await eventBus.publish(FolderEvent.listChanged(folders))
            } catch {
                LogService.shared.error(.storage, "NoteStore 重命名文件夹失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "renameFolder", errorMessage: error.localizedDescription))
                return
            }

            // 入队 folderRename 操作，同步到云端
            if let tag = existingTag {
                do {
                    try operationQueue.enqueueFolderRename(folderId: folderId, name: newName, tag: tag)
                    LogService.shared.debug(.sync, "已入队 folderRename 操作: \(folderId.prefix(8))...")
                } catch {
                    LogService.shared.error(.sync, "创建 folderRename 操作失败: \(error)")
                }
            } else {
                LogService.shared.warning(.sync, "文件夹缺少 tag，无法同步重命名: \(folderId.prefix(8))...")
            }

        case let .deleted(folderId):
            // 删除前获取 tag，用于云端同步
            let existingTag = folders.first(where: { $0.id == folderId })?.tag
            do {
                try db.deleteFolder(folderId: folderId)
                refreshFoldersCache()
                await eventBus.publish(FolderEvent.listChanged(folders))
            } catch {
                LogService.shared.error(.storage, "NoteStore 删除文件夹失败: \(error)")
                await eventBus.publish(ErrorEvent.storageFailed(operation: "deleteFolder", errorMessage: error.localizedDescription))
                return
            }

            // 入队 folderDelete 操作，同步到云端
            if let tag = existingTag {
                do {
                    try operationQueue.enqueueFolderDelete(folderId: folderId, tag: tag)
                    LogService.shared.debug(.sync, "已入队 folderDelete 操作: \(folderId.prefix(8))...")
                } catch {
                    LogService.shared.error(.sync, "创建 folderDelete 操作失败: \(error)")
                }
            } else {
                LogService.shared.warning(.sync, "文件夹缺少 tag，无法同步删除: \(folderId.prefix(8))...")
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
                // 重命名图片目录（从 DatabaseService 层上移到此处）
                if newId != "0", oldId != "0" {
                    try localStorage.renameFolderImageDirectory(oldFolderId: oldId, newFolderId: newId)
                }
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

            // 入队 cloudUpload 操作，同步元数据变更到云端
            do {
                try operationQueue.enqueueCloudUpload(
                    noteId: note.id,
                    title: note.title,
                    content: note.content,
                    folderId: note.folderId,
                    localSaveTimestamp: note.updatedAt
                )
                LogService.shared.debug(.sync, "元数据变更已入队 cloudUpload: \(noteId.prefix(8))...")
                await triggerImmediateUploadIfOnline(noteId: noteId)
            } catch {
                LogService.shared.error(.sync, "元数据变更创建 cloudUpload 操作失败: \(error)")
            }
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
