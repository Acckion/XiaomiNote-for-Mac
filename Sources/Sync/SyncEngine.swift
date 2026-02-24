import Foundation

/// 同步引擎
///
/// 新架构中的同步核心，替代 SyncService。
/// 关键区别：不直接写 DB，通过 EventBus 发布事件让 NoteStore 处理 DB 写入。
public actor SyncEngine {

    // MARK: - 依赖

    let apiClient: APIClient
    let noteAPI: NoteAPI
    let folderAPI: FolderAPI
    let syncAPI: SyncAPI
    let fileAPI: FileAPI
    let eventBus: EventBus
    let operationQueue: UnifiedOperationQueue
    let localStorage: LocalStorageService
    let syncStateManager: SyncStateManager
    let syncGuard: SyncGuard
    let operationProcessor: OperationProcessor
    let audioCacheService: AudioCacheService

    // MARK: - 状态

    var isSyncing = false
    private var subscriptionTask: Task<Void, Never>?

    // MARK: - 初始化

    /// SyncModule 使用的构造器（无默认值）
    init(
        apiClient: APIClient,
        noteAPI: NoteAPI,
        folderAPI: FolderAPI,
        syncAPI: SyncAPI,
        fileAPI: FileAPI,
        eventBus: EventBus,
        operationQueue: UnifiedOperationQueue,
        localStorage: LocalStorageService,
        syncStateManager: SyncStateManager,
        syncGuard: SyncGuard,
        noteStore _: NoteStore?,
        operationProcessor: OperationProcessor,
        audioCacheService: AudioCacheService
    ) {
        self.apiClient = apiClient
        self.noteAPI = noteAPI
        self.folderAPI = folderAPI
        self.syncAPI = syncAPI
        self.fileAPI = fileAPI
        self.eventBus = eventBus
        self.operationQueue = operationQueue
        self.localStorage = localStorage
        self.syncStateManager = syncStateManager
        self.syncGuard = syncGuard
        self.operationProcessor = operationProcessor
        self.audioCacheService = audioCacheService
        LogService.shared.info(.sync, "SyncEngine 初始化完成")
    }

    // MARK: - 生命周期

    /// 启动同步引擎，订阅同步请求事件
    func start() async {
        let stream = await eventBus.subscribe(to: SyncEvent.self)
        subscriptionTask = Task {
            for await event in stream {
                guard !Task.isCancelled else { break }
                if case let .requested(mode) = event {
                    await performSync(mode: mode)
                }
            }
        }
        LogService.shared.info(.sync, "SyncEngine 已启动")
    }

    /// 停止同步引擎
    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        isSyncing = false
        LogService.shared.info(.sync, "SyncEngine 已停止")
    }

    // MARK: - 同步入口

    /// 根据模式分发到增量或全量同步
    func performSync(mode: SyncMode) async {
        guard !isSyncing else {
            LogService.shared.warning(.sync, "同步被阻止：同步正在进行中")
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        await eventBus.publish(SyncEvent.started)
        let startTime = Date()

        do {
            switch mode {
            case .incremental:
                let result = try await performIncrementalSync()
                let duration = Date().timeIntervalSince(startTime)
                await eventBus.publish(SyncEvent.completed(result: SyncEventResult(
                    downloadedCount: result.syncedNotes,
                    uploadedCount: 0,
                    deletedCount: 0,
                    duration: duration
                )))
                // 同步完成后触发队列处理
                await operationProcessor.processQueue()
            case let .full(fullMode):
                let result = try await performFullSync(mode: fullMode)
                let duration = Date().timeIntervalSince(startTime)
                await eventBus.publish(SyncEvent.completed(result: SyncEventResult(
                    downloadedCount: result.syncedNotes,
                    uploadedCount: 0,
                    deletedCount: 0,
                    duration: duration
                )))
                // 同步完成后触发队列处理
                await operationProcessor.processQueue()
            }
        } catch {
            await eventBus.publish(SyncEvent.failed(errorMessage: error.localizedDescription))
        }
    }

    /// 智能同步：有 syncStatus 则增量，否则全量
    func performSmartSync() async throws -> SyncResult {
        LogService.shared.info(.sync, "开始智能同步")

        if hasValidSyncStatus {
            LogService.shared.debug(.sync, "存在有效的同步状态，执行增量同步")
            return try await performIncrementalSync()
        } else {
            LogService.shared.debug(.sync, "不存在有效的同步状态，执行全量同步")
            return try await performFullSync(mode: .normal)
        }
    }

    /// 检查是否存在有效的同步状态
    private var hasValidSyncStatus: Bool {
        guard let status = localStorage.loadSyncStatus() else { return false }
        guard let syncTag = status.syncTag else { return false }
        return status.lastSyncTime != nil && !syncTag.isEmpty
    }

    // MARK: - 增量同步

    /// 执行增量同步
    ///
    /// 三层回退策略：
    /// 1. 轻量级增量同步
    /// 2. 网页版增量同步
    /// 3. 旧 API 增量同步
    func performIncrementalSync() async throws -> SyncResult {
        LogService.shared.info(.sync, "开始执行增量同步")

        guard await apiClient.isAuthenticated() else {
            LogService.shared.error(.sync, "增量同步失败：未认证")
            throw SyncError.notAuthenticated
        }

        guard localStorage.loadSyncStatus() != nil else {
            LogService.shared.info(.sync, "未找到同步记录，执行全量同步")
            return try await performFullSync(mode: .normal)
        }

        await eventBus.publish(SyncEvent.progress(message: "开始增量同步...", percent: 0))

        // 第一层：轻量级增量同步
        do {
            let result = try await performLightweightIncrementalSync()
            LogService.shared.debug(.sync, "轻量级增量同步成功")
            return result
        } catch {
            LogService.shared.warning(.sync, "轻量级增量同步失败，回退到网页版: \(error)")
        }

        // 第二层：网页版增量同步
        do {
            let result = try await performWebIncrementalSync()
            LogService.shared.debug(.sync, "网页版增量同步成功")
            return result
        } catch {
            LogService.shared.warning(.sync, "网页版增量同步失败，回退到旧 API: \(error)")
        }

        // 第三层：旧 API 增量同步
        var result = SyncResult()

        let lastSyncTag = await syncStateManager.getCurrentSyncTag()
        await eventBus.publish(SyncEvent.progress(message: "获取自上次同步以来的更改...", percent: 0.1))

        let syncResponse = try await noteAPI.fetchPage(syncTag: lastSyncTag)

        let notes = ResponseParser.parseNotes(from: syncResponse)
        let folders = ResponseParser.parseFolders(from: syncResponse)

        var syncedNotes = 0
        var cloudNoteIds = Set<String>()
        var cloudFolderIds = Set<String>()

        for note in notes {
            cloudNoteIds.insert(note.id)
        }
        for folder in folders where !folder.isSystem && folder.id != "0" && folder.id != "starred" {
            cloudFolderIds.insert(folder.id)
        }

        // 处理文件夹
        await eventBus.publish(SyncEvent.progress(message: "同步文件夹...", percent: 0.2))
        try await syncFoldersIncremental(cloudFolders: folders, cloudFolderIds: cloudFolderIds)

        // 处理笔记
        for (index, note) in notes.enumerated() {
            let percent = 0.3 + 0.5 * Double(index) / Double(max(notes.count, 1))
            await eventBus.publish(SyncEvent.progress(message: "正在同步笔记: \(note.title)", percent: percent))

            let noteResult = try await syncNoteIncremental(cloudNote: note)
            result.addNoteResult(noteResult)
            if noteResult.success { syncedNotes += 1 }
        }

        // 提取新的 syncTag
        if let newSyncTag = extractSyncTags(from: syncResponse) {
            let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
            try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
        }

        // 处理本地独有项
        await eventBus.publish(SyncEvent.progress(message: "检查本地独有的笔记和文件夹...", percent: 0.9))
        try await syncLocalOnlyItems(cloudNoteIds: cloudNoteIds, cloudFolderIds: cloudFolderIds)

        result.totalNotes = notes.count
        result.syncedNotes = syncedNotes
        result.lastSyncTime = Date()

        LogService.shared.info(.sync, "增量同步完成 - 总计: \(notes.count), 成功: \(syncedNotes)")
        return result
    }

    // MARK: - 网页版增量同步

    /// 使用 syncFull API 进行增量同步
    private func performWebIncrementalSync() async throws -> SyncResult {
        guard await apiClient.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        guard localStorage.loadSyncStatus() != nil else {
            return try await performFullSync(mode: .normal)
        }

        var result = SyncResult()
        let lastSyncTag = await syncStateManager.getCurrentSyncTag()

        await eventBus.publish(SyncEvent.progress(message: "开始网页版增量同步...", percent: 0))

        let syncResponse = try await syncAPI.syncFull(syncTag: lastSyncTag)

        let notes = ResponseParser.parseNotes(from: syncResponse)
        let folders = ResponseParser.parseFolders(from: syncResponse)

        var syncedNotes = 0
        var cloudNoteIds = Set<String>()
        var cloudFolderIds = Set<String>()

        for note in notes {
            cloudNoteIds.insert(note.id)
        }
        for folder in folders where !folder.isSystem && folder.id != "0" && folder.id != "starred" {
            cloudFolderIds.insert(folder.id)
        }

        await eventBus.publish(SyncEvent.progress(message: "同步文件夹...", percent: 0.2))
        try await syncFoldersIncremental(cloudFolders: folders, cloudFolderIds: cloudFolderIds)

        for (index, note) in notes.enumerated() {
            let percent = 0.3 + 0.5 * Double(index) / Double(max(notes.count, 1))
            await eventBus.publish(SyncEvent.progress(message: "正在同步笔记: \(note.title)", percent: percent))

            let noteResult = try await syncNoteIncremental(cloudNote: note)
            result.addNoteResult(noteResult)
            if noteResult.success { syncedNotes += 1 }
        }

        if let newSyncTag = extractSyncTags(from: syncResponse) {
            let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
            try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
        }

        await eventBus.publish(SyncEvent.progress(message: "检查本地独有的笔记和文件夹...", percent: 0.9))
        try await syncLocalOnlyItems(cloudNoteIds: cloudNoteIds, cloudFolderIds: cloudFolderIds)

        result.totalNotes = notes.count
        result.syncedNotes = syncedNotes
        result.lastSyncTime = Date()

        LogService.shared.info(.sync, "网页版增量同步完成 - 总计: \(notes.count), 成功: \(syncedNotes)")
        return result
    }

    // MARK: - 轻量级增量同步

    /// 只同步有修改的条目，效率最高
    private func performLightweightIncrementalSync() async throws -> SyncResult {
        guard await apiClient.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        guard localStorage.loadSyncStatus() != nil else {
            return try await performFullSync(mode: .normal)
        }

        var result = SyncResult()
        let lastSyncTag = await syncStateManager.getCurrentSyncTag()

        await eventBus.publish(SyncEvent.progress(message: "开始轻量级增量同步...", percent: 0))

        let syncResponse = try await syncAPI.syncFull(syncTag: lastSyncTag)
        let (modifiedNotes, modifiedFolders, newSyncTag) = try parseLightweightSyncResponse(syncResponse)

        LogService.shared.info(.sync, "轻量级增量同步：\(modifiedNotes.count) 个笔记，\(modifiedFolders.count) 个文件夹有修改")

        var syncedNotes = 0
        let totalItems = modifiedFolders.count + modifiedNotes.count

        // 处理有修改的文件夹
        for (index, folder) in modifiedFolders.enumerated() {
            let percent = Double(index) / Double(max(totalItems, 1))
            await eventBus.publish(SyncEvent.progress(message: "正在同步文件夹: \(folder.name)", percent: percent))
            try await processModifiedFolder(folder)
        }

        // 处理有修改的笔记
        for (index, note) in modifiedNotes.enumerated() {
            let percent = Double(modifiedFolders.count + index) / Double(max(totalItems, 1))
            await eventBus.publish(SyncEvent.progress(message: "正在同步笔记: \(note.title)", percent: percent))

            let noteResult = try await processModifiedNote(note)
            result.addNoteResult(noteResult)
            if noteResult.success { syncedNotes += 1 }
        }

        if !newSyncTag.isEmpty {
            let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
            try await syncStateManager.stageSyncTag(newSyncTag, hasPendingNotes: hasPendingNotes)
        }

        result.totalNotes = modifiedNotes.count
        result.syncedNotes = syncedNotes
        result.lastSyncTime = Date()

        LogService.shared.info(.sync, "轻量级增量同步完成 - 总计: \(modifiedNotes.count), 成功: \(syncedNotes)")
        return result
    }

    // MARK: - 全量同步

    /// 执行全量同步
    ///
    /// 清除本地数据，从云端拉取全部笔记和文件夹
    func performFullSync(mode: FullSyncMode) async throws -> SyncResult {
        LogService.shared.info(.sync, "开始执行全量同步")

        guard await apiClient.isAuthenticated() else {
            LogService.shared.error(.sync, "全量同步失败：未认证")
            throw SyncError.notAuthenticated
        }

        await eventBus.publish(SyncEvent.progress(message: "开始全量同步...", percent: 0))

        var result = SyncResult()
        var syncTag = ""
        let forceRedownload = mode == .forceRedownload

        do {
            // 1. 清除本地数据（保护临时 ID 笔记）
            await eventBus.publish(SyncEvent.progress(message: "清除本地数据...", percent: 0.05))
            let localNotes = try localStorage.getAllLocalNotes()
            for note in localNotes {
                if NoteOperation.isTemporaryId(note.id) {
                    LogService.shared.debug(.sync, "保护临时 ID 笔记: \(note.id.prefix(8))")
                    continue
                }
                await eventBus.publish(NoteEvent.deleted(noteId: note.id, tag: nil))
            }
            let localFolders = try localStorage.loadFolders()
            for folder in localFolders where !folder.isSystem && folder.id != "0" && folder.id != "starred" {
                await eventBus.publish(FolderEvent.deleted(folderId: folder.id))
            }

            // 2. 分页获取所有笔记列表
            var pageCount = 0
            var totalNotes = 0
            var syncedNotes = 0
            var failedNotes = 0
            var allCloudFolders: [Folder] = []
            var allCloudNotes: [Note] = []
            var finalSyncTag: String?

            while true {
                pageCount += 1
                await eventBus.publish(SyncEvent.progress(message: "正在获取第 \(pageCount) 页...", percent: 0.1))

                let pageResponse: [String: Any]
                do {
                    pageResponse = try await noteAPI.fetchPage(syncTag: syncTag)
                } catch let error as MiNoteError {
                    throw mapMiNoteError(error)
                }

                let notes = ResponseParser.parseNotes(from: pageResponse)
                let folders = ResponseParser.parseFolders(from: pageResponse)

                totalNotes += notes.count

                for folder in folders where !folder.isSystem && folder.id != "0" && folder.id != "starred" {
                    allCloudFolders.append(folder)
                }
                allCloudNotes.append(contentsOf: notes)

                if let nextSyncTag = pageResponse["syncTag"] as? String, !nextSyncTag.isEmpty {
                    syncTag = nextSyncTag
                    finalSyncTag = nextSyncTag
                } else {
                    break
                }
            }

            // 3. 先保存文件夹
            await eventBus.publish(SyncEvent.progress(message: "保存云端文件夹...", percent: 0.2))
            if !allCloudFolders.isEmpty {
                await eventBus.publish(FolderEvent.batchSaved(allCloudFolders))
                LogService.shared.debug(.sync, "已发布 \(allCloudFolders.count) 个云端文件夹保存事件")
            }

            // 4. 处理所有笔记
            for (index, note) in allCloudNotes.enumerated() {
                let percent = 0.25 + 0.55 * Double(index) / Double(max(totalNotes, 1))
                await eventBus.publish(SyncEvent.progress(message: "正在同步笔记: \(note.title)", percent: percent))

                do {
                    let noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                    var updatedNote = note
                    NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id, forceRedownload: forceRedownload) {
                        NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                    }

                    await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                    syncedNotes += 1
                } catch {
                    LogService.shared.error(.sync, "同步笔记失败: \(note.id) - \(error.localizedDescription)")
                    failedNotes += 1
                }
            }

            // 5. 获取并同步私密笔记
            await eventBus.publish(SyncEvent.progress(message: "获取私密笔记...", percent: 0.85))
            do {
                let privateNotesResponse = try await noteAPI.fetchPrivateNotes(folderId: "2", limit: 200)
                let privateNotes = ResponseParser.parseNotes(from: privateNotesResponse)

                LogService.shared.debug(.sync, "获取到 \(privateNotes.count) 条私密笔记")
                totalNotes += privateNotes.count

                for note in privateNotes {
                    let noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                    var updatedNote = note
                    NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id, forceRedownload: forceRedownload) {
                        NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                    }

                    // 确保 folderId 为 "2"
                    if updatedNote.folderId != "2" {
                        updatedNote = Note(
                            id: updatedNote.id,
                            title: updatedNote.title,
                            content: updatedNote.content,
                            folderId: "2",
                            isStarred: updatedNote.isStarred,
                            createdAt: updatedNote.createdAt,
                            updatedAt: updatedNote.updatedAt,
                            tags: updatedNote.tags
                        )
                    }

                    await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                    syncedNotes += 1
                }
            } catch {
                LogService.shared.warning(.sync, "获取私密笔记失败: \(error.localizedDescription)")
            }

            // 6. 更新 syncTag
            if let tag = finalSyncTag, !tag.isEmpty {
                // syncTag 有效
            } else {
                // 尝试从最后一次 API 响应中提取
                do {
                    let lastPageResponse = try await noteAPI.fetchPage(syncTag: "")
                    if let lastSyncTag = lastPageResponse["syncTag"] as? String, !lastSyncTag.isEmpty {
                        finalSyncTag = lastSyncTag
                    } else if let extracted = extractSyncTags(from: lastPageResponse) {
                        finalSyncTag = extracted
                    }
                } catch {
                    LogService.shared.warning(.sync, "获取最后一次 API 响应失败: \(error)")
                }
            }

            if let tag = finalSyncTag, !tag.isEmpty {
                let hasPendingNotes = await syncStateManager.hasPendingUploadNotes()
                try await syncStateManager.stageSyncTag(tag, hasPendingNotes: hasPendingNotes)
            } else {
                LogService.shared.warning(.sync, "全量同步：syncTag 为空，无法暂存")
            }

            result.totalNotes = totalNotes
            result.syncedNotes = syncedNotes
            result.failedNotes = failedNotes
            result.lastSyncTime = Date()

            LogService.shared.info(.sync, "全量同步完成 - 总计: \(totalNotes), 成功: \(syncedNotes), 失败: \(failedNotes), 文件夹: \(allCloudFolders.count)")
        } catch {
            throw error
        }

        return result
    }
}
