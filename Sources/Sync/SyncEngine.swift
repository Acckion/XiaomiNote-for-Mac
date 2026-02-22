import Foundation

/// 同步引擎
///
/// 新架构中的同步核心，替代 SyncService。
/// 关键区别：不直接写 DB，通过 EventBus 发布事件让 NoteStore 处理 DB 写入。
public actor SyncEngine {
    static let shared = SyncEngine()

    // MARK: - 依赖

    private let apiClient: APIClient
    private let noteAPI: NoteAPI
    private let folderAPI: FolderAPI
    private let syncAPI: SyncAPI
    private let fileAPI: FileAPI
    private let eventBus: EventBus
    private let operationQueue: UnifiedOperationQueue
    private let localStorage: LocalStorageService
    private let syncStateManager: SyncStateManager
    private let syncGuard: SyncGuard

    // MARK: - 状态

    private var isSyncing = false
    private var subscriptionTask: Task<Void, Never>?

    // MARK: - 初始化

    init(
        apiClient: APIClient = .shared,
        noteAPI: NoteAPI = .shared,
        folderAPI: FolderAPI = .shared,
        syncAPI: SyncAPI = .shared,
        fileAPI: FileAPI = .shared,
        eventBus: EventBus = .shared,
        operationQueue: UnifiedOperationQueue = .shared,
        localStorage: LocalStorageService = .shared,
        syncStateManager: SyncStateManager = .createDefault(),
        syncGuard: SyncGuard? = nil,
        noteStore: NoteStore? = nil
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
        // SyncGuard 需要 NoteStore 来查询活跃编辑状态
        let store = noteStore ?? NoteStore(db: .shared, eventBus: .shared)
        self.syncGuard = syncGuard ?? SyncGuard(noteStore: store)
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
            case let .full(fullMode):
                let result = try await performFullSync(mode: fullMode)
                let duration = Date().timeIntervalSince(startTime)
                await eventBus.publish(SyncEvent.completed(result: SyncEventResult(
                    downloadedCount: result.syncedNotes,
                    uploadedCount: 0,
                    deletedCount: 0,
                    duration: duration
                )))
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

        guard apiClient.isAuthenticated() else {
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
        guard apiClient.isAuthenticated() else {
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
        guard apiClient.isAuthenticated() else {
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

        guard apiClient.isAuthenticated() else {
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

    // MARK: - 增量同步辅助方法

    /// 增量同步文件夹
    private func syncFoldersIncremental(cloudFolders: [Folder], cloudFolderIds _: Set<String>) async throws {
        let pendingOps = operationQueue.getPendingOperations()
        let localFolders = try localStorage.loadFolders()

        for cloudFolder in cloudFolders {
            if cloudFolder.isSystem || cloudFolder.id == "0" || cloudFolder.id == "starred" {
                continue
            }

            if let localFolder = localFolders.first(where: { $0.id == cloudFolder.id }) {
                // 云端和本地都存在
                if cloudFolder.createdAt > localFolder.createdAt {
                    // 云端较新
                    await eventBus.publish(FolderEvent.folderSaved(cloudFolder))
                    LogService.shared.debug(.sync, "文件夹云端较新，已更新: \(cloudFolder.name)")
                } else if localFolder.createdAt > cloudFolder.createdAt {
                    // 本地较新，添加到上传队列
                    let hasRenameOp = pendingOps.contains { $0.type == .folderRename && $0.noteId == localFolder.id }
                    if !hasRenameOp {
                        let opData: [String: Any] = [
                            "folderId": localFolder.id,
                            "name": localFolder.name,
                        ]
                        let data = try JSONSerialization.data(withJSONObject: opData)
                        let operation = NoteOperation(
                            type: .folderRename,
                            noteId: localFolder.id,
                            data: data,
                            status: .pending,
                            priority: NoteOperation.calculatePriority(for: .folderRename)
                        )
                        _ = try operationQueue.enqueue(operation)
                        LogService.shared.debug(.sync, "文件夹本地较新，已添加到上传队列: \(localFolder.name)")
                    }
                } else {
                    // 时间一致但名称不同
                    if cloudFolder.name != localFolder.name {
                        await eventBus.publish(FolderEvent.folderSaved(cloudFolder))
                        LogService.shared.debug(.sync, "文件夹名称不同，已更新: \(cloudFolder.name)")
                    }
                }
            } else {
                // 只有云端存在
                let hasDeleteOp = pendingOps.contains { $0.type == .folderDelete && $0.noteId == cloudFolder.id }
                if hasDeleteOp {
                    if let tag = cloudFolder.rawData?["tag"] as? String {
                        _ = try await folderAPI.deleteFolder(folderId: cloudFolder.id, tag: tag, purge: false)
                        LogService.shared.debug(.sync, "文件夹在删除队列中，已删除云端: \(cloudFolder.name)")
                    }
                } else {
                    await eventBus.publish(FolderEvent.folderSaved(cloudFolder))
                    LogService.shared.debug(.sync, "新文件夹，已拉取到本地: \(cloudFolder.name)")
                }
            }
        }
    }

    /// 增量同步单个笔记
    private func syncNoteIncremental(cloudNote: Note) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: cloudNote.id, noteTitle: cloudNote.title)
        let pendingOps = operationQueue.getPendingOperations()

        // 同步保护检查
        let shouldSkip = await syncGuard.shouldSkipSync(
            noteId: cloudNote.id,
            cloudTimestamp: cloudNote.updatedAt
        )
        if shouldSkip {
            if let skipReason = await syncGuard.getSkipReason(
                noteId: cloudNote.id,
                cloudTimestamp: cloudNote.updatedAt
            ) {
                LogService.shared.debug(.sync, "同步保护：跳过笔记 \(cloudNote.id.prefix(8)) - \(skipReason.description)")
            }
            result.status = .skipped
            result.message = "同步保护：笔记正在编辑、待上传或使用临时 ID"
            result.success = true
            return result
        }

        if let localNote = try localStorage.loadNote(noteId: cloudNote.id) {
            // 云端和本地都存在
            if localNote.updatedAt > cloudNote.updatedAt {
                // 本地较新，添加到上传队列
                let hasUpdateOp = pendingOps.contains { $0.type == .cloudUpload && $0.noteId == localNote.id }
                if !hasUpdateOp {
                    let opData: [String: Any] = [
                        "title": localNote.title,
                        "content": localNote.content,
                        "folderId": localNote.folderId,
                    ]
                    let data = try JSONSerialization.data(withJSONObject: opData)
                    let operation = NoteOperation(
                        type: .cloudUpload,
                        noteId: localNote.id,
                        data: data,
                        status: .pending,
                        priority: NoteOperation.calculatePriority(for: .cloudUpload)
                    )
                    _ = try operationQueue.enqueue(operation)
                    LogService.shared.debug(.sync, "笔记本地较新，已添加到上传队列: \(localNote.title)")
                }
                result.status = .skipped
                result.message = "本地较新，等待上传"
                result.success = true
            } else if cloudNote.updatedAt > localNote.updatedAt {
                // 云端较新
                let noteDetails = try await noteAPI.fetchNoteDetails(noteId: cloudNote.id)
                var updatedNote = cloudNote
                NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                    NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                }

                await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                result.status = .updated
                result.message = "已从云端更新"
                result.success = true
                LogService.shared.debug(.sync, "笔记云端较新，已更新: \(cloudNote.title)")
            } else {
                // 时间一致，比较内容
                if localNote.primaryXMLContent != cloudNote.primaryXMLContent {
                    let noteDetails = try await noteAPI.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                    }

                    await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                    result.status = .updated
                    result.message = "内容不同，已更新"
                    result.success = true
                } else {
                    result.status = .skipped
                    result.message = "内容相同，跳过"
                    result.success = true
                }
            }
        } else {
            // 只有云端存在
            let hasDeleteOp = pendingOps.contains { $0.type == .cloudDelete && $0.noteId == cloudNote.id }
            if hasDeleteOp {
                if let tag = cloudNote.serverTag {
                    _ = try await noteAPI.deleteNote(noteId: cloudNote.id, tag: tag, purge: false)
                    result.status = .skipped
                    result.message = "在删除队列中，已删除云端"
                    result.success = true
                    LogService.shared.debug(.sync, "笔记在删除队列中，已删除云端: \(cloudNote.title)")
                }
            } else {
                // 再次检查本地是否存在（防止并发问题）
                if let existingNote = try? localStorage.loadNote(noteId: cloudNote.id) {
                    if existingNote.updatedAt < cloudNote.updatedAt {
                        let noteDetails = try await noteAPI.fetchNoteDetails(noteId: cloudNote.id)
                        var updatedNote = cloudNote
                        NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                        if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                            NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                        }

                        await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                        result.status = .updated
                        result.message = "已从云端更新"
                        result.success = true
                    } else {
                        result.status = .skipped
                        result.message = "本地已存在且较新或相同"
                        result.success = true
                    }
                } else {
                    // 新笔记，下载到本地
                    let noteDetails = try await noteAPI.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                    }

                    await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                    result.status = .created
                    result.message = "已从云端拉取"
                    result.success = true
                    LogService.shared.debug(.sync, "新笔记，已拉取到本地: \(cloudNote.title)")
                }
            }
        }

        return result
    }

    /// 处理只有本地存在但云端不存在的笔记和文件夹
    private func syncLocalOnlyItems(cloudNoteIds: Set<String>, cloudFolderIds: Set<String>) async throws {
        let pendingOps = operationQueue.getPendingOperations()
        let localNotes = try localStorage.getAllLocalNotes()
        let localFolders = try localStorage.loadFolders()

        // 处理本地独有的笔记
        for localNote in localNotes {
            if NoteOperation.isTemporaryId(localNote.id) { continue }
            if cloudNoteIds.contains(localNote.id) { continue }

            let hasCreateOp = pendingOps.contains { $0.type == .noteCreate && $0.noteId == localNote.id }
            if hasCreateOp {
                do {
                    let response = try await noteAPI.createNote(
                        title: localNote.title,
                        content: localNote.content,
                        folderId: localNote.folderId
                    )

                    if let code = response["code"] as? Int, code == 0,
                       let data = response["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any],
                       let serverNoteId = entry["id"] as? String,
                       serverNoteId != localNote.id
                    {
                        let updatedNote = Note(
                            id: serverNoteId,
                            title: localNote.title,
                            content: localNote.content,
                            folderId: localNote.folderId,
                            isStarred: localNote.isStarred,
                            createdAt: localNote.createdAt,
                            updatedAt: localNote.updatedAt,
                            tags: localNote.tags,
                            serverTag: entry["tag"] as? String ?? localNote.serverTag,
                            settingJson: localNote.settingJson,
                            extraInfoJson: localNote.extraInfoJson
                        )

                        // 通过事件保存新笔记并删除旧笔记
                        await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                        await eventBus.publish(NoteEvent.deleted(noteId: localNote.id, tag: nil))
                        LogService.shared.info(.sync, "笔记上传后 ID 变更: \(localNote.id.prefix(8)) -> \(serverNoteId.prefix(8))")
                    }
                } catch {
                    LogService.shared.error(.sync, "上传笔记失败: \(error.localizedDescription)")
                }
            } else {
                let hasUpdateOp = pendingOps.contains { $0.type == .cloudUpload && $0.noteId == localNote.id }
                if !hasUpdateOp {
                    await eventBus.publish(NoteEvent.deleted(noteId: localNote.id, tag: nil))
                    LogService.shared.debug(.sync, "笔记不在新建队列，已删除本地: \(localNote.title)")
                }
            }
        }

        // 处理本地独有的文件夹
        for localFolder in localFolders {
            if localFolder.isSystem || localFolder.id == "0" || localFolder.id == "starred" { continue }
            if cloudFolderIds.contains(localFolder.id) { continue }

            let hasCreateOp = pendingOps.contains { $0.type == .folderCreate && $0.noteId == localFolder.id }
            if hasCreateOp {
                let response = try await folderAPI.createFolder(name: localFolder.name)

                if let code = response["code"] as? Int, code == 0,
                   let data = response["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any]
                {
                    var serverFolderId: String?
                    if let idString = entry["id"] as? String {
                        serverFolderId = idString
                    } else if let idInt = entry["id"] as? Int {
                        serverFolderId = String(idInt)
                    }

                    if let folderId = serverFolderId, folderId != localFolder.id {
                        // 通过事件迁移文件夹 ID 并删除旧文件夹
                        await eventBus.publish(FolderEvent.folderIdMigrated(oldId: localFolder.id, newId: folderId))

                        let updatedFolder = Folder(
                            id: folderId,
                            name: entry["subject"] as? String ?? localFolder.name,
                            count: 0,
                            isSystem: false,
                            createdAt: Date()
                        )
                        await eventBus.publish(FolderEvent.folderSaved(updatedFolder))

                        LogService.shared.info(.sync, "文件夹 ID 已更新: \(localFolder.id.prefix(8)) -> \(folderId.prefix(8))")
                    }
                } else {
                    LogService.shared.warning(.sync, "文件夹上传后服务器返回无效响应: \(localFolder.name)")
                }
            } else {
                await eventBus.publish(FolderEvent.deleted(folderId: localFolder.id))
                LogService.shared.debug(.sync, "文件夹不在新建队列，已删除本地: \(localFolder.name)")
            }
        }
    }

    // MARK: - 轻量级同步辅助方法

    /// 解析轻量级同步响应
    private func parseLightweightSyncResponse(_ response: [String: Any]) throws -> (notes: [Note], folders: [Folder], syncTag: String) {
        var syncTag = ""
        if let data = response["data"] as? [String: Any],
           let noteView = data["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any],
           let newSyncTag = noteViewData["syncTag"] as? String
        {
            syncTag = newSyncTag
        }

        var modifiedNotes: [Note] = []
        var modifiedFolders: [Folder] = []

        if let data = response["data"] as? [String: Any],
           let noteView = data["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any]
        {
            if let entries = noteViewData["entries"] as? [[String: Any]] {
                for entry in entries {
                    if let note = NoteMapper.fromMinoteListData(entry) {
                        modifiedNotes.append(note)
                    }
                }
            }

            if let folders = noteViewData["folders"] as? [[String: Any]] {
                for folderEntry in folders {
                    if let folder = Folder.fromMinoteData(folderEntry) {
                        modifiedFolders.append(folder)
                    }
                }
            }
        }

        LogService.shared.debug(.sync, "解析轻量级同步响应: \(modifiedNotes.count) 个笔记, \(modifiedFolders.count) 个文件夹")
        return (modifiedNotes, modifiedFolders, syncTag)
    }

    /// 处理有修改的文件夹
    private func processModifiedFolder(_ folder: Folder) async throws {
        if let rawData = folder.rawData,
           let status = rawData["status"] as? String,
           status == "deleted"
        {
            await eventBus.publish(FolderEvent.deleted(folderId: folder.id))
            LogService.shared.debug(.sync, "文件夹已删除: \(folder.id)")
        } else {
            await eventBus.publish(FolderEvent.folderSaved(folder))
            LogService.shared.debug(.sync, "文件夹已更新: \(folder.name)")
        }
    }

    /// 处理有修改的笔记
    private func processModifiedNote(_ note: Note) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)

        let shouldSkip = await syncGuard.shouldSkipSync(
            noteId: note.id,
            cloudTimestamp: note.updatedAt
        )
        if shouldSkip {
            if let skipReason = await syncGuard.getSkipReason(
                noteId: note.id,
                cloudTimestamp: note.updatedAt
            ) {
                LogService.shared.debug(.sync, "同步保护：跳过笔记 \(note.id.prefix(8)) - \(skipReason.description)")
            }
            result.status = .skipped
            result.message = "同步保护：笔记正在编辑、待上传或使用临时 ID"
            result.success = true
            return result
        }

        // 已删除的笔记
        if note.status == "deleted" {
            await eventBus.publish(NoteEvent.deleted(noteId: note.id, tag: nil))
            result.status = .skipped
            result.message = "笔记已从云端删除"
            result.success = true
            return result
        }

        do {
            let noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
            var updatedNote = note
            NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

            if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
            }

            await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))

            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)
            result.status = existsLocally ? .updated : .created
            result.message = existsLocally ? "笔记已更新" : "新笔记已下载"
            result.success = true
        } catch let error as MiNoteError {
            throw mapMiNoteError(error)
        } catch {
            LogService.shared.error(.sync, "获取笔记详情失败: \(error)")
            throw SyncError.networkError(error)
        }

        return result
    }

    /// 处理单个笔记（全量同步模式）
    private func processNote(_ note: Note, isFullSync: Bool = false) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)

        do {
            if isFullSync {
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    throw mapMiNoteError(error)
                }

                var updatedNote = note
                NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                }

                await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))

                let existsLocally = localStorage.noteExistsLocally(noteId: note.id)
                result.status = existsLocally ? .updated : .created
                result.message = result.status == .updated ? "笔记已替换" : "笔记已下载"
                result.success = true
                return result
            }

            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)

            if existsLocally {
                if let localNote = try? localStorage.loadNote(noteId: note.id) {
                    let timeDifference = abs(note.updatedAt.timeIntervalSince(localNote.updatedAt))

                    if note.updatedAt < localNote.updatedAt, timeDifference > 2.0 {
                        result.status = .skipped
                        result.message = "本地版本较新，跳过同步"
                        result.success = true
                        return result
                    }

                    if timeDifference < 2.0 {
                        do {
                            let noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                            var cloudNote = note
                            NoteMapper.updateFromServerDetails(&cloudNote, details: noteDetails)

                            if localNote.primaryXMLContent == cloudNote.primaryXMLContent {
                                result.status = .skipped
                                result.message = "笔记未修改"
                                result.success = true
                                return result
                            } else {
                                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                                    NoteMapper.updateSettingData(&cloudNote, settingData: updatedSettingData)
                                }

                                await eventBus.publish(SyncEvent.noteDownloaded(cloudNote))
                                result.status = .updated
                                result.message = "笔记已更新"
                                result.success = true
                                return result
                            }
                        } catch {
                            LogService.shared.warning(.sync, "获取笔记详情失败，继续使用原有逻辑: \(error)")
                        }
                    }
                }

                let noteDetails: [String: Any]
                do {
                    noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    throw mapMiNoteError(error)
                }

                var updatedNote = note
                NoteMapper.updateFromServerDetails(&updatedNote, details: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    NoteMapper.updateSettingData(&updatedNote, settingData: updatedSettingData)
                }

                await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
                result.status = .updated
                result.message = "笔记已更新"
            } else {
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await noteAPI.fetchNoteDetails(noteId: note.id)
                } catch let error as MiNoteError {
                    throw mapMiNoteError(error)
                }

                var newNote = note
                NoteMapper.updateFromServerDetails(&newNote, details: noteDetails)

                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    NoteMapper.updateSettingData(&newNote, settingData: updatedSettingData)
                }

                await eventBus.publish(SyncEvent.noteDownloaded(newNote))
                result.status = .created
                result.message = "新笔记已下载"
            }

            result.success = true
        } catch let error as SyncError {
            throw error
        } catch {
            result.success = false
            result.status = .failed
            result.message = "处理失败: \(error.localizedDescription)"
        }

        return result
    }

    // MARK: - 附件处理（图片和音频）

    /// 下载笔记中的附件
    private func downloadNoteImages(from noteDetails: [String: Any], noteId: String, forceRedownload: Bool = false) async throws -> [[String: Any]]? {
        var entry: [String: Any]?
        if let data = noteDetails["data"] as? [String: Any] {
            if let dataEntry = data["entry"] as? [String: Any] {
                entry = dataEntry
            }
        } else if let directEntry = noteDetails["entry"] as? [String: Any] {
            entry = directEntry
        } else if noteDetails["id"] != nil || noteDetails["content"] != nil {
            entry = noteDetails
        }

        guard let entry else {
            LogService.shared.debug(.sync, "无法提取 entry，跳过附件下载: \(noteId)")
            return nil
        }

        var settingData: [[String: Any]] = []

        if let setting = entry["setting"] as? [String: Any],
           let existingData = setting["data"] as? [[String: Any]]
        {
            settingData = existingData
        }

        for index in 0 ..< settingData.count {
            let attachmentData = settingData[index]

            guard let fileId = attachmentData["fileId"] as? String else { continue }
            guard let mimeType = attachmentData["mimeType"] as? String else { continue }

            if mimeType.hasPrefix("image/") {
                let fileType = String(mimeType.dropFirst("image/".count))

                if !forceRedownload {
                    if localStorage.validateImage(fileId: fileId, fileType: fileType) {
                        var updatedData = attachmentData
                        updatedData["localExists"] = true
                        settingData[index] = updatedData
                        continue
                    }
                }

                do {
                    let imageData = try await downloadImageWithRetry(fileId: fileId, type: "note_img")
                    try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    updatedData["downloaded"] = true
                    settingData[index] = updatedData
                } catch {
                    LogService.shared.error(.sync, "图片下载失败: \(fileId).\(fileType) - \(error.localizedDescription)")
                }
            } else if mimeType.hasPrefix("audio/") {
                if AudioCacheService.shared.isCached(fileId: fileId) {
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    settingData[index] = updatedData
                    continue
                }

                do {
                    let audioData = try await fileAPI.downloadAudio(fileId: fileId)
                    try AudioCacheService.shared.cacheFile(data: audioData, fileId: fileId, mimeType: mimeType)
                    var updatedData = attachmentData
                    updatedData["localExists"] = true
                    updatedData["downloaded"] = true
                    settingData[index] = updatedData
                } catch {
                    LogService.shared.error(.sync, "音频下载失败: \(fileId) - \(error.localizedDescription)")
                }
            }
        }

        // 从 content 中提取额外的附件
        if let content = entry["content"] as? String {
            let allAttachmentData = await extractAndDownloadAllAttachments(
                from: content,
                existingSettingData: settingData,
                forceRedownload: forceRedownload
            )
            settingData = allAttachmentData
        }

        return settingData
    }

    /// 带重试的图片下载
    private func downloadImageWithRetry(
        fileId: String,
        type: String,
        maxRetries: Int = 3
    ) async throws -> Data {
        var lastError: Error?

        for attempt in 1 ... maxRetries {
            do {
                return try await fileAPI.downloadFile(fileId: fileId, type: type)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let delay = TimeInterval(attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        LogService.shared.error(.sync, "图片下载失败（已重试 \(maxRetries) 次）: \(fileId)")
        throw lastError ?? SyncError.networkError(NSError(domain: "SyncEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "图片下载失败"]))
    }

    /// 从 content 中提取所有附件并下载
    private func extractAndDownloadAllAttachments(
        from content: String,
        existingSettingData: [[String: Any]],
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        var allSettingData = existingSettingData
        var existingFileIds = Set<String>()

        for entry in existingSettingData {
            if let fileId = entry["fileId"] as? String {
                existingFileIds.insert(fileId)
            }
        }

        let legacyImageData = await extractLegacyImages(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !legacyImageData.isEmpty {
            allSettingData.append(contentsOf: legacyImageData)
            for entry in legacyImageData {
                if let fileId = entry["fileId"] as? String { existingFileIds.insert(fileId) }
            }
        }

        let newImageData = await extractNewFormatImages(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !newImageData.isEmpty {
            allSettingData.append(contentsOf: newImageData)
            for entry in newImageData {
                if let fileId = entry["fileId"] as? String { existingFileIds.insert(fileId) }
            }
        }

        let audioData = await extractAudioAttachments(from: content, existingFileIds: existingFileIds, forceRedownload: forceRedownload)
        if !audioData.isEmpty {
            allSettingData.append(contentsOf: audioData)
        }

        return allSettingData
    }

    /// 提取旧版格式图片
    private func extractLegacyImages(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "\u{263A} ([^<]+)<0/></>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_img",
                attachmentType: "image",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 提取新版格式图片
    private func extractNewFormatImages(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "<img[^>]+fileid=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_img",
                attachmentType: "image",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 提取音频附件
    private func extractAudioAttachments(
        from content: String,
        existingFileIds: Set<String>,
        forceRedownload: Bool
    ) async -> [[String: Any]] {
        let pattern = "<sound[^>]+fileid=\"([^\"]+)\"[^>]*/?>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
        if matches.isEmpty { return [] }

        var settingDataEntries: [[String: Any]] = []

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fileIdRange = match.range(at: 1)
            let fileId = nsContent.substring(with: fileIdRange).trimmingCharacters(in: .whitespaces)

            if existingFileIds.contains(fileId) { continue }

            if let entry = await downloadAndCreateSettingEntry(
                fileId: fileId,
                type: "note_audio",
                attachmentType: "audio",
                forceRedownload: forceRedownload
            ) {
                settingDataEntries.append(entry)
            }
        }

        return settingDataEntries
    }

    /// 下载附件并创建 setting.data 条目
    private func downloadAndCreateSettingEntry(
        fileId: String,
        type: String,
        attachmentType: String,
        forceRedownload: Bool
    ) async -> [String: Any]? {
        var existingFormat: String?
        var fileSize = 0

        if !forceRedownload {
            if attachmentType == "image" {
                let formats = ["jpg", "jpeg", "png", "gif", "webp"]
                for format in formats {
                    if localStorage.validateImage(fileId: fileId, fileType: format) {
                        existingFormat = format
                        if let imageData = localStorage.loadImage(fileId: fileId, fileType: format) {
                            fileSize = imageData.count
                        }
                        break
                    }
                }
            } else if attachmentType == "audio" {
                if AudioCacheService.shared.isCached(fileId: fileId) {
                    existingFormat = "amr"
                    if let cachedFileURL = AudioCacheService.shared.getCachedFile(for: fileId) {
                        if let attributes = try? FileManager.default.attributesOfItem(atPath: cachedFileURL.path),
                           let size = attributes[.size] as? Int
                        {
                            fileSize = size
                        }
                    }
                }
            }
        }

        var downloadedFormat: String?

        if existingFormat == nil {
            do {
                let data = try await downloadImageWithRetry(fileId: fileId, type: type)
                fileSize = data.count

                if attachmentType == "image" {
                    let detectedFormat = detectImageFormat(from: data)
                    downloadedFormat = detectedFormat
                    try localStorage.saveImage(imageData: data, fileId: fileId, fileType: detectedFormat)
                } else if attachmentType == "audio" {
                    let detectedFormat = detectAudioFormat(from: data)
                    downloadedFormat = detectedFormat
                    let mimeType = "audio/\(detectedFormat)"
                    do {
                        try AudioCacheService.shared.cacheFile(data: data, fileId: fileId, mimeType: mimeType)
                    } catch {
                        LogService.shared.error(.sync, "音频保存失败: \(fileId) - \(error)")
                        return nil
                    }
                }
            } catch {
                LogService.shared.error(.sync, "附件下载失败: \(fileId) - \(error.localizedDescription)")
                return nil
            }
        }

        let finalFormat = downloadedFormat ?? existingFormat ?? (attachmentType == "image" ? "jpeg" : "amr")
        let mimeType = attachmentType == "image" ? "image/\(finalFormat)" : "audio/\(finalFormat)"

        return [
            "fileId": fileId,
            "mimeType": mimeType,
            "size": fileSize,
        ]
    }

    // MARK: - 格式检测

    /// 检测图片格式
    private func detectImageFormat(from data: Data) -> String {
        guard data.count >= 12 else { return "jpeg" }

        let bytes = [UInt8](data.prefix(12))

        // PNG: 89 50 4E 47
        if bytes.count >= 4, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return "png"
        }

        // GIF: 47 49 46
        if bytes.count >= 3, bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
            return "gif"
        }

        // WebP: 52 49 46 46 ... 57 45 42 50
        if bytes.count >= 12, bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50
        {
            return "webp"
        }

        // JPEG: FF D8 FF
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "jpeg"
        }

        return "jpeg"
    }

    /// 检测音频格式
    private func detectAudioFormat(from data: Data) -> String {
        guard data.count >= 12 else { return "amr" }

        let bytes = [UInt8](data.prefix(12))

        // AMR: #!AMR\n
        if bytes.count >= 6,
           bytes[0] == 0x23, bytes[1] == 0x21,
           bytes[2] == 0x41, bytes[3] == 0x4D,
           bytes[4] == 0x52, bytes[5] == 0x0A
        {
            return "amr"
        }

        // MP3: ID3 或 0xFF 0xFB
        if bytes.count >= 3,
           (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
           (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)
        {
            return "mp3"
        }

        // M4A: ftyp
        if bytes.count >= 8,
           bytes[4] == 0x66, bytes[5] == 0x74,
           bytes[6] == 0x79, bytes[7] == 0x70
        {
            return "m4a"
        }

        // WAV: RIFF...WAVE
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49,
           bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x41,
           bytes[10] == 0x56, bytes[11] == 0x45
        {
            return "wav"
        }

        return "amr"
    }

    // MARK: - 公共辅助方法

    /// 手动重新下载笔记的所有图片
    func redownloadNoteImages(noteId: String) async throws -> (success: Int, failed: Int) {
        LogService.shared.info(.sync, "手动重新下载笔记图片: \(noteId)")

        guard apiClient.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        let noteDetails = try await noteAPI.fetchNoteDetails(noteId: noteId)

        guard let updatedSettingData = try await downloadNoteImages(
            from: noteDetails,
            noteId: noteId,
            forceRedownload: true
        ) else {
            return (0, 0)
        }

        var successCount = 0
        var failedCount = 0

        for data in updatedSettingData {
            if let downloaded = data["downloaded"] as? Bool, downloaded {
                successCount += 1
            } else if let mimeType = data["mimeType"] as? String, mimeType.hasPrefix("image/") {
                failedCount += 1
            }
        }

        LogService.shared.info(.sync, "图片重新下载完成: 成功 \(successCount), 失败 \(failedCount)")
        return (successCount, failedCount)
    }

    /// 手动同步单个笔记
    func syncSingleNote(noteId: String) async throws -> NoteSyncResult {
        guard apiClient.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }

        let noteDetails: [String: Any]
        do {
            noteDetails = try await noteAPI.fetchNoteDetails(noteId: noteId)
        } catch let error as MiNoteError {
            throw mapMiNoteError(error)
        }

        guard let note = NoteMapper.fromMinoteListData(noteDetails) else {
            throw SyncError.invalidNoteData
        }

        return try await processNote(note)
    }

    /// 取消同步
    func cancelSync() {
        isSyncing = false
        LogService.shared.info(.sync, "同步已取消")
    }

    /// 重置同步状态
    func resetSyncStatus() throws {
        try localStorage.clearSyncStatus()
        LogService.shared.info(.sync, "同步状态已重置")
    }

    // MARK: - 私有辅助方法

    /// 从响应中提取 syncTag
    private func extractSyncTags(from response: [String: Any]) -> String? {
        var syncTag: String?

        // 旧 API 格式
        if let oldSyncTag = response["syncTag"] as? String {
            syncTag = oldSyncTag
        }

        // data.syncTag 格式
        if let data = response["data"] as? [String: Any] {
            if let dataSyncTag = data["syncTag"] as? String {
                syncTag = dataSyncTag
            }

            // 网页版 API 格式：note_view.data.syncTag
            if let noteView = data["note_view"] as? [String: Any],
               let noteViewData = noteView["data"] as? [String: Any],
               let webSyncTag = noteViewData["syncTag"] as? String
            {
                syncTag = webSyncTag
            }
        }

        // 顶层 note_view.data.syncTag
        if let noteView = response["note_view"] as? [String: Any],
           let noteViewData = noteView["data"] as? [String: Any],
           let webSyncTag = noteViewData["syncTag"] as? String
        {
            syncTag = webSyncTag
        }

        if syncTag == nil {
            LogService.shared.warning(.sync, "无法从响应中提取 syncTag")
        }

        return syncTag
    }

    /// 将 MiNoteError 转换为 SyncError
    private func mapMiNoteError(_ error: MiNoteError) -> SyncError {
        switch error {
        case .cookieExpired:
            .cookieExpired
        case .notAuthenticated:
            .notAuthenticated
        case let .networkError(underlyingError):
            .networkError(underlyingError)
        case .invalidResponse:
            .networkError(error)
        }
    }

    // MARK: - 内部类型

    /// 同步结果
    struct SyncResult {
        var totalNotes = 0
        var syncedNotes = 0
        var failedNotes = 0
        var skippedNotes = 0
        var lastSyncTime: Date?
        var noteResults: [NoteSyncResult] = []

        mutating func addNoteResult(_ result: NoteSyncResult) {
            noteResults.append(result)

            if result.success {
                switch result.status {
                case .created, .updated:
                    syncedNotes += 1
                case .skipped:
                    skippedNotes += 1
                case .failed:
                    failedNotes += 1
                }
            } else {
                failedNotes += 1
            }
        }
    }

    /// 单个笔记的同步结果
    struct NoteSyncResult {
        let noteId: String
        let noteTitle: String
        var success = false
        var status: SyncStatusType = .failed
        var message = ""

        enum SyncStatusType {
            case created
            case updated
            case skipped
            case failed
        }
    }

    /// 同步错误类型
    enum SyncError: LocalizedError {
        case alreadySyncing
        case notAuthenticated
        case invalidNoteData
        case cookieExpired
        case networkError(Error)
        case storageError(Error)

        var errorDescription: String? {
            switch self {
            case .alreadySyncing:
                "同步正在进行中"
            case .notAuthenticated:
                "未登录小米账号"
            case .invalidNoteData:
                "笔记数据格式无效"
            case .cookieExpired:
                "Cookie已过期，请重新登录或刷新Cookie"
            case let .networkError(error):
                "网络错误: \(error.localizedDescription)"
            case let .storageError(error):
                "存储错误: \(error.localizedDescription)"
            }
        }
    }
}
