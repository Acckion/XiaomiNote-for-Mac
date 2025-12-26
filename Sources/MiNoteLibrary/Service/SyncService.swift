import Foundation

/// 同步服务
/// 
/// 负责管理本地笔记与云端笔记的同步，包括：
/// - 完整同步：清除所有本地数据，从云端拉取全部笔记
/// - 增量同步：只同步自上次同步以来的更改
/// - 冲突解决：处理本地和云端同时修改的情况
/// - 离线操作队列：管理网络断开时的操作
final class SyncService: @unchecked Sendable {
    static let shared = SyncService()
    
    // MARK: - 依赖服务
    
    /// 小米笔记API服务
    private let miNoteService = MiNoteService.shared
    
    /// 本地存储服务
    private let localStorage = LocalStorageService.shared
    
    // MARK: - 同步状态
    
    /// 是否正在同步
    private var isSyncing = false
    
    /// 同步进度（0.0 - 1.0）
    private var syncProgress: Double = 0
    
    /// 同步状态消息（用于UI显示）
    private var syncStatusMessage: String = ""
    
    var isSyncingNow: Bool {
        return isSyncing
    }
    
    var currentProgress: Double {
        return syncProgress
    }
    
    var currentStatusMessage: String {
        return syncStatusMessage
    }
    
    // MARK: - 完整同步
    
    /// 执行完整同步
    /// 
    /// 完整同步会：
    /// 1. 清除所有本地笔记和文件夹
    /// 2. 从云端拉取所有笔记和文件夹
    /// 3. 下载笔记的完整内容和图片
    /// 
    /// **注意**：完整同步会丢失所有本地未同步的更改，请谨慎使用
    /// 
    /// - Returns: 同步结果，包含同步的笔记数量等信息
    /// - Throws: SyncError（同步错误、网络错误等）
    func performFullSync() async throws -> SyncResult {
        print("[SYNC] 开始执行完整同步")
        guard !isSyncing else {
            print("[SYNC] 错误：同步正在进行中")
            throw SyncError.alreadySyncing
        }
        
        guard miNoteService.isAuthenticated() else {
            print("[SYNC] 错误：未认证")
            throw SyncError.notAuthenticated
        }
        
        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "开始完整同步..."
        
        defer {
            isSyncing = false
            print("[SYNC] 同步结束，isSyncing设置为false")
        }
        
        var result = SyncResult()
        var syncTag = ""
        
        do {
            // 1. 清除所有本地数据
            syncStatusMessage = "清除所有本地数据..."
            print("[SYNC] 清除所有本地笔记和文件夹")
            let localNotes = try localStorage.getAllLocalNotes()
            for note in localNotes {
                try localStorage.deleteNote(noteId: note.id)
            }
            let localFolders = try localStorage.loadFolders()
            for folder in localFolders {
                if !folder.isSystem && folder.id != "0" && folder.id != "starred" {
                    try DatabaseService.shared.deleteFolder(folderId: folder.id)
                }
            }
            print("[SYNC] 已清除所有本地数据")
            
            // 2. 拉取所有云端文件夹和笔记
            var syncStatus = SyncStatus()
            var pageCount = 0
            var totalNotes = 0
            var syncedNotes = 0
            var allCloudFolders: [Folder] = []
            
            while true {
                pageCount += 1
                syncStatusMessage = "正在获取第 \(pageCount) 页..."
                
                // 获取一页数据
                let pageResponse: [String: Any]
                do {
                    pageResponse = try await miNoteService.fetchPage(syncTag: syncTag)
                } catch let error as MiNoteError {
                    switch error {
                    case .cookieExpired:
                        throw SyncError.cookieExpired
                    case .notAuthenticated:
                        throw SyncError.notAuthenticated
                    case .networkError(let underlyingError):
                        throw SyncError.networkError(underlyingError)
                    case .invalidResponse:
                        throw SyncError.networkError(error)
                    }
                } catch {
                    throw SyncError.networkError(error)
                }
                
                // 解析笔记和文件夹
                let notes = miNoteService.parseNotes(from: pageResponse)
                let folders = miNoteService.parseFolders(from: pageResponse)
                
                totalNotes += notes.count
                
                // 收集所有云端文件夹
                for folder in folders {
                    if !folder.isSystem && folder.id != "0" && folder.id != "starred" {
                        allCloudFolders.append(folder)
                }
                }
                
                // 处理笔记（直接保存，因为已经清除了本地数据）
                for (index, note) in notes.enumerated() {
                    syncProgress = Double(syncedNotes + index) / Double(max(totalNotes, 1))
                    syncStatusMessage = "正在同步笔记: \(note.title)"
                    
                    // 获取笔记详情
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    var updatedNote = note
                    updatedNote.updateContent(from: noteDetails)
                    print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")
                    
                    // 下载图片，并获取更新后的 setting.data
                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                        // 更新笔记的 rawData 中的 setting.data
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData
                        print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                    }
                    
                    // 保存到本地
                    print("[SYNC] 保存笔记: \(updatedNote.id)")
                    try localStorage.saveNote(updatedNote)
                        syncStatus.addSyncedNote(note.id)
                        syncedNotes += 1
                }
                
                // 检查是否还有下一页
                if let nextSyncTag = pageResponse["syncTag"] as? String, !nextSyncTag.isEmpty {
                    syncTag = nextSyncTag
                    syncStatus.syncTag = nextSyncTag
                } else {
                    // 没有更多页面
                    break
                }
            }
            
            // 3. 获取并同步私密笔记
            syncStatusMessage = "获取私密笔记..."
            do {
                let privateNotesResponse = try await miNoteService.fetchPrivateNotes(folderId: "2", limit: 200)
                let privateNotes = miNoteService.parseNotes(from: privateNotesResponse)
                
                print("[SYNC] 获取到 \(privateNotes.count) 条私密笔记")
                totalNotes += privateNotes.count
                
                // 处理私密笔记
                for (index, note) in privateNotes.enumerated() {
                    syncProgress = Double(syncedNotes + index) / Double(max(totalNotes, 1))
                    syncStatusMessage = "正在同步私密笔记: \(note.title)"
                    
                    // 获取笔记详情
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    var updatedNote = note
                    updatedNote.updateContent(from: noteDetails)
                    print("[SYNC] 更新私密笔记内容，content长度: \(updatedNote.content.count)")
                    
                    // 下载图片，并获取更新后的 setting.data
                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                        // 更新笔记的 rawData 中的 setting.data
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData
                        print("[SYNC] 更新私密笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                    }
                    
                    // 保存到本地（确保 folderId 为 "2"）
                    var finalNote = updatedNote
                    if finalNote.folderId != "2" {
                        finalNote = Note(
                            id: finalNote.id,
                            title: finalNote.title,
                            content: finalNote.content,
                            folderId: "2",
                            isStarred: finalNote.isStarred,
                            createdAt: finalNote.createdAt,
                            updatedAt: finalNote.updatedAt,
                            tags: finalNote.tags,
                            rawData: finalNote.rawData
                        )
                    }
                    
                    print("[SYNC] 保存私密笔记: \(finalNote.id)")
                    try localStorage.saveNote(finalNote)
                    syncStatus.addSyncedNote(finalNote.id)
                    syncedNotes += 1
                }
            } catch {
                print("[SYNC] ⚠️ 获取私密笔记失败: \(error.localizedDescription)")
                // 不抛出错误，继续执行同步流程
            }
            
            // 4. 保存所有云端文件夹
            syncStatusMessage = "保存云端文件夹..."
            if !allCloudFolders.isEmpty {
                try localStorage.saveFolders(allCloudFolders)
                print("[SYNC] 已保存 \(allCloudFolders.count) 个云端文件夹")
            }
            
            // 更新同步状态
            syncStatus.lastSyncTime = Date()
            syncStatus.lastPageSyncTime = Date()
            try localStorage.saveSyncStatus(syncStatus)
            
            syncProgress = 1.0
            syncStatusMessage = "完整同步完成"
            
            result.totalNotes = totalNotes
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()
            
        } catch {
            syncStatusMessage = "同步失败: \(error.localizedDescription)"
            throw error
        }
        
        return result
    }
    
    // MARK: - 增量同步
    
    /// 执行增量同步
    /// 
    /// 增量同步会：
    /// 1. 使用上次同步的syncTag获取自上次同步以来的更改
    /// 2. 比较本地和云端的时间戳，决定使用哪个版本
    /// 3. 处理冲突：本地较新则上传，云端较新则下载
    /// 4. 处理离线操作队列中的操作
    /// 
    /// **同步策略**：
    /// - 如果本地修改时间 > 云端修改时间：保留本地版本，上传到云端
    /// - 如果云端修改时间 > 本地修改时间：下载云端版本，覆盖本地
    /// - 如果时间相同但内容不同：下载云端版本（以云端为准）
    /// 
    /// - Returns: 同步结果，包含同步的笔记数量等信息
    /// - Throws: SyncError（同步错误、网络错误等）
    func performIncrementalSync() async throws -> SyncResult {
        print("[SYNC] 开始执行增量同步")
        guard !isSyncing else {
            print("[SYNC] 错误：同步正在进行中")
            throw SyncError.alreadySyncing
        }
        
        guard miNoteService.isAuthenticated() else {
            print("[SYNC] 错误：未认证")
            throw SyncError.notAuthenticated
        }
        
        // 加载现有的同步状态
        guard let syncStatus = localStorage.loadSyncStatus() else {
            // 如果没有同步状态，执行完整同步（在设置 isSyncing 之前检查）
            print("[SYNC] 未找到同步记录，执行完整同步...")
            return try await performFullSync()
        }
        
        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "开始增量同步..."
        
        defer {
            isSyncing = false
            print("[SYNC] 增量同步结束，isSyncing设置为false")
        }
        
        var result = SyncResult()
        
        do {
            
            let lastSyncTag = syncStatus.syncTag ?? ""
            syncStatusMessage = "获取自上次同步以来的更改..."
            
            // 获取自上次同步以来的更改
            let pageResponse: [String: Any]
            do {
                pageResponse = try await miNoteService.fetchPage(syncTag: lastSyncTag)
            } catch let error as MiNoteError {
                switch error {
                case .cookieExpired:
                    throw SyncError.cookieExpired
                case .notAuthenticated:
                    throw SyncError.notAuthenticated
                case .networkError(let underlyingError):
                    throw SyncError.networkError(underlyingError)
                case .invalidResponse:
                    throw SyncError.networkError(error)
                }
            } catch {
                throw SyncError.networkError(error)
            }
            
            // 解析笔记和文件夹
            let notes = miNoteService.parseNotes(from: pageResponse)
            let folders = miNoteService.parseFolders(from: pageResponse)
            
            var syncedNotes = 0
            var cloudNoteIds = Set<String>() // 收集云端笔记ID
            var cloudFolderIds = Set<String>() // 收集云端文件夹ID
            
            // 收集云端笔记和文件夹ID
            for note in notes {
                cloudNoteIds.insert(note.id)
            }
            for folder in folders {
                if !folder.isSystem && folder.id != "0" && folder.id != "starred" {
                    cloudFolderIds.insert(folder.id)
                }
            }
            
            // 处理文件夹（按照增量同步规则）
            syncStatusMessage = "同步文件夹..."
            try await syncFoldersIncremental(cloudFolders: folders, cloudFolderIds: cloudFolderIds)
            
            // 处理笔记（按照增量同步规则）
            for (index, note) in notes.enumerated() {
                syncProgress = Double(index) / Double(max(notes.count, 1))
                syncStatusMessage = "正在同步笔记: \(note.title)"
                
                let noteResult = try await syncNoteIncremental(cloudNote: note)
                result.addNoteResult(noteResult)
                
                if noteResult.success {
                    syncedNotes += 1
                }
            }
            
            // 更新同步状态
            var updatedStatus = syncStatus
            if let newSyncTag = pageResponse["syncTag"] as? String {
                updatedStatus.syncTag = newSyncTag
            }
            updatedStatus.lastSyncTime = Date()
            try localStorage.saveSyncStatus(updatedStatus)
            
            // 处理只有本地存在但云端不存在的笔记和文件夹
            syncStatusMessage = "检查本地独有的笔记和文件夹..."
            try await syncLocalOnlyItems(cloudNoteIds: cloudNoteIds, cloudFolderIds: cloudFolderIds)
            
            // 重试删除失败的笔记
            try await retryPendingDeletions()
            
            syncProgress = 1.0
            syncStatusMessage = "增量同步完成"
            
            result.totalNotes = notes.count
            result.syncedNotes = syncedNotes
            result.lastSyncTime = Date()
            
        } catch {
            syncStatusMessage = "增量同步失败: \(error.localizedDescription)"
            throw error
        }
        
        return result
    }
    
    // MARK: - 增量同步辅助方法
    
    /// 增量同步文件夹
    /// 
    /// 处理文件夹的增量同步逻辑：
    /// - 如果云端和本地都存在：比较时间戳，使用较新的版本
    /// - 如果只有云端存在：检查是否在删除队列中，如果是则删除云端，否则拉取到本地
    /// - 如果只有本地存在：检查是否在创建队列中，如果是则上传到云端，否则删除本地
    /// 
    /// - Parameters:
    ///   - cloudFolders: 云端文件夹列表
    ///   - cloudFolderIds: 云端文件夹ID集合（用于快速查找）
    private func syncFoldersIncremental(cloudFolders: [Folder], cloudFolderIds: Set<String>) async throws {
        let offlineQueue = OfflineOperationQueue.shared
        let pendingOps = offlineQueue.getPendingOperations()
        let localFolders = try localStorage.loadFolders()
        
        for cloudFolder in cloudFolders {
            // 跳过系统文件夹
            if cloudFolder.isSystem || cloudFolder.id == "0" || cloudFolder.id == "starred" {
                continue
            }
            
            if let localFolder = localFolders.first(where: { $0.id == cloudFolder.id }) {
                // 情况1：云端和本地都存在
                // 比较时间戳
                if cloudFolder.createdAt > localFolder.createdAt {
                    // 1.2 云端较新，拉取云端覆盖本地
                    try localStorage.saveFolders([cloudFolder])
                    print("[SYNC] 文件夹云端较新，已更新: \(cloudFolder.name)")
                } else if localFolder.createdAt > cloudFolder.createdAt {
                    // 1.1 本地较新，上传本地到云端（通过离线队列）
                    // 这里需要检查是否有重命名操作
                    let hasRenameOp = pendingOps.contains { op in
                        op.type == .renameFolder && op.noteId == localFolder.id
                    }
                    if !hasRenameOp {
                        // 创建更新操作
                        let opData: [String: Any] = [
                            "folderId": localFolder.id,
                            "name": localFolder.name
                        ]
                        let data = try JSONSerialization.data(withJSONObject: opData)
                        let operation = OfflineOperation(
                            type: .renameFolder,
                            noteId: localFolder.id,
                            data: data
                        )
                        try offlineQueue.addOperation(operation)
                        print("[SYNC] 文件夹本地较新，已添加到上传队列: \(localFolder.name)")
                    }
                } else {
                    // 1.3 时间一致，考虑内容（这里简单比较名称）
                    if cloudFolder.name != localFolder.name {
                        // 名称不同，使用云端版本
                        try localStorage.saveFolders([cloudFolder])
                        print("[SYNC] 文件夹名称不同，已更新: \(cloudFolder.name)")
                    }
                }
            } else {
                // 情况2：只有云端存在，本地不存在
                // 2.1 检查离线删除队列
                let hasDeleteOp = pendingOps.contains { op in
                    op.type == .deleteFolder && op.noteId == cloudFolder.id
                }
                if hasDeleteOp {
                    // 在删除队列中，删除云端文件夹
                    if let tag = cloudFolder.rawData?["tag"] as? String {
                        _ = try await miNoteService.deleteFolder(folderId: cloudFolder.id, tag: tag, purge: false)
                        print("[SYNC] 文件夹在删除队列中，已删除云端: \(cloudFolder.name)")
                    }
                } else {
                    // 2.2 不在删除队列，拉取到本地
                    try localStorage.saveFolders([cloudFolder])
                    print("[SYNC] 新文件夹，已拉取到本地: \(cloudFolder.name)")
                }
            }
        }
    }
    
    /// 增量同步单个笔记
    /// 
    /// 处理单个笔记的增量同步逻辑：
    /// - 如果本地和云端都存在：
    ///   - 本地较新：添加到更新队列，等待上传
    ///   - 云端较新：下载并覆盖本地
    ///   - 时间相同：比较内容，如果不同则下载云端版本
    /// - 如果只有云端存在：
    ///   - 在删除队列中：删除云端笔记
    ///   - 不在删除队列：下载到本地
    /// 
    /// - Parameter cloudNote: 云端笔记对象
    /// - Returns: 同步结果，包含同步状态和消息
    private func syncNoteIncremental(cloudNote: Note) async throws -> NoteSyncResult {
        var result = NoteSyncResult(noteId: cloudNote.id, noteTitle: cloudNote.title)
        let offlineQueue = OfflineOperationQueue.shared
        let pendingOps = offlineQueue.getPendingOperations()
        
        if let localNote = try localStorage.loadNote(noteId: cloudNote.id) {
            // 情况1：云端和本地都存在
            if localNote.updatedAt > cloudNote.updatedAt {
                // 1.1 本地较新，上传本地到云端
                let hasUpdateOp = pendingOps.contains { op in
                    op.type == .updateNote && op.noteId == localNote.id
                }
                if !hasUpdateOp {
                    // 创建更新操作
                    let opData: [String: Any] = [
                        "title": localNote.title,
                        "content": localNote.content,
                        "folderId": localNote.folderId
                    ]
                    let data = try JSONSerialization.data(withJSONObject: opData)
                    let operation = OfflineOperation(
                        type: .updateNote,
                        noteId: localNote.id,
                        data: data
                    )
                    try offlineQueue.addOperation(operation)
                    print("[SYNC] 笔记本地较新，已添加到上传队列: \(localNote.title)")
                }
                result.status = .skipped
                result.message = "本地较新，等待上传"
                result.success = true
            } else if cloudNote.updatedAt > localNote.updatedAt {
                // 1.2 云端较新，拉取云端覆盖本地
                let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                var updatedNote = cloudNote
                updatedNote.updateContent(from: noteDetails)
                print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")
                
                // 下载图片，并获取更新后的 setting.data
                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                    // 更新笔记的 rawData 中的 setting.data
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                    print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                }
                
                print("[SYNC] 保存笔记: \(updatedNote.id)")
                try localStorage.saveNote(updatedNote)
                result.status = .updated
                result.message = "已从云端更新"
                result.success = true
                print("[SYNC] 笔记云端较新，已更新: \(cloudNote.title)")
            } else {
                // 1.3 时间一致，比较内容
                if localNote.primaryXMLContent != cloudNote.primaryXMLContent {
                    // 内容不同，获取详情并更新
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    updatedNote.updateContent(from: noteDetails)
                    print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")
                    
                    // 下载图片，并获取更新后的 setting.data
                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        // 更新笔记的 rawData 中的 setting.data
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData
                        print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                    }
                    
                    print("[SYNC] 保存笔记: \(updatedNote.id)")
                    try localStorage.saveNote(updatedNote)
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
            // 情况2：只有云端存在，本地不存在
            // 2.1 检查离线删除队列
            let hasDeleteOp = pendingOps.contains { op in
                op.type == .deleteNote && op.noteId == cloudNote.id
            }
            if hasDeleteOp {
                // 在删除队列中，删除云端笔记
                if let tag = cloudNote.rawData?["tag"] as? String {
                    _ = try await miNoteService.deleteNote(noteId: cloudNote.id, tag: tag, purge: false)
                    result.status = .skipped
                    result.message = "在删除队列中，已删除云端"
                    result.success = true
                    print("[SYNC] 笔记在删除队列中，已删除云端: \(cloudNote.title)")
                }
            } else {
                // 2.2 不在删除队列，拉取到本地
                // 再次检查本地是否已存在（防止竞态条件）
                if let existingNote = try? localStorage.loadNote(noteId: cloudNote.id) {
                    // 笔记已存在，使用更新逻辑而不是创建逻辑
                    if existingNote.updatedAt < cloudNote.updatedAt {
                        // 云端较新，更新本地
                        let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                        var updatedNote = cloudNote
                        updatedNote.updateContent(from: noteDetails)
                        print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")
                        
                        // 下载图片，并获取更新后的 setting.data
                        if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                            // 更新笔记的 rawData 中的 setting.data
                            var rawData = updatedNote.rawData ?? [:]
                            var setting = rawData["setting"] as? [String: Any] ?? [:]
                            setting["data"] = updatedSettingData
                            rawData["setting"] = setting
                            updatedNote.rawData = rawData
                            print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                        }
                        
                        print("[SYNC] 保存笔记: \(updatedNote.id)")
                        try localStorage.saveNote(updatedNote)
                        result.status = .updated
                        result.message = "已从云端更新"
                        result.success = true
                        print("[SYNC] 笔记已存在但云端较新，已更新: \(cloudNote.title)")
                    } else {
                        // 本地较新或相同，跳过
                        result.status = .skipped
                        result.message = "本地已存在且较新或相同"
                        result.success = true
                        print("[SYNC] 笔记已存在且本地较新或相同，跳过: \(cloudNote.title)")
                    }
                } else {
                    // 确实不存在，拉取到本地
                    let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                    var updatedNote = cloudNote
                    updatedNote.updateContent(from: noteDetails)
                    print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")
                    
                    // 下载图片，并获取更新后的 setting.data
                    if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id) {
                        // 更新笔记的 rawData 中的 setting.data
                        var rawData = updatedNote.rawData ?? [:]
                        var setting = rawData["setting"] as? [String: Any] ?? [:]
                        setting["data"] = updatedSettingData
                        rawData["setting"] = setting
                        updatedNote.rawData = rawData
                        print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                    }
                    
                    print("[SYNC] 保存笔记: \(updatedNote.id)")
                    try localStorage.saveNote(updatedNote)
                    result.status = .created
                    result.message = "已从云端拉取"
                    result.success = true
                    print("[SYNC] 新笔记，已拉取到本地: \(cloudNote.title)")
                }
            }
        }
        
        return result
    }
    
    /// 处理只有本地存在但云端不存在的笔记和文件夹
    /// 
    /// 这种情况可能发生在：
    /// 1. 本地创建了笔记但尚未上传（在创建队列中）
    /// 2. 云端已删除但本地仍存在（需要删除本地）
    /// 
    /// **处理策略**：
    /// - 如果在创建队列中：上传到云端
    /// - 如果不在创建队列中：删除本地（说明云端已删除）
    /// 
    /// - Parameters:
    ///   - cloudNoteIds: 云端笔记ID集合
    ///   - cloudFolderIds: 云端文件夹ID集合
    private func syncLocalOnlyItems(cloudNoteIds: Set<String>, cloudFolderIds: Set<String>) async throws {
        let offlineQueue = OfflineOperationQueue.shared
        let pendingOps = offlineQueue.getPendingOperations()
        let localNotes = try localStorage.getAllLocalNotes()
        let localFolders = try localStorage.loadFolders()
        
        // 处理本地独有的笔记
        for localNote in localNotes {
            if !cloudNoteIds.contains(localNote.id) {
                // 情况3：只有本地存在，云端不存在
                // 3.1 检查离线新建队列
                let hasCreateOp = pendingOps.contains { op in
                    op.type == .createNote && op.noteId == localNote.id
                }
                if hasCreateOp {
                    // 在新建队列中，上传到云端
                    // 注意：上传后可能会返回新的ID，但此时增量同步已经完成，不会导致重复
                    // 因为下次同步时会正确处理ID变更
                    do {
                        let response = try await miNoteService.createNote(
                            title: localNote.title,
                            content: localNote.content,
                            folderId: localNote.folderId
                        )
                        
                        // 如果服务器返回了新的ID，更新本地笔记
                        if let code = response["code"] as? Int, code == 0,
                           let data = response["data"] as? [String: Any],
                           let entry = data["entry"] as? [String: Any],
                           let serverNoteId = entry["id"] as? String,
                           serverNoteId != localNote.id {
                            // 服务器返回了新的ID，需要更新本地笔记
                            var updatedRawData = localNote.rawData ?? [:]
                            for (key, value) in entry {
                                updatedRawData[key] = value
                            }
                            
                            let updatedNote = Note(
                                id: serverNoteId,
                                title: localNote.title,
                                content: localNote.content,
                                folderId: localNote.folderId,
                                isStarred: localNote.isStarred,
                                createdAt: localNote.createdAt,
                                updatedAt: localNote.updatedAt,
                                tags: localNote.tags,
                                rawData: updatedRawData
                            )
                            
                            // 先保存新笔记，再删除旧笔记
                            try localStorage.saveNote(updatedNote)
                            try localStorage.deleteNote(noteId: localNote.id)
                            print("[SYNC] 笔记上传后ID变更: \(localNote.id) -> \(serverNoteId)")
                        } else {
                            print("[SYNC] 笔记在新建队列中，已上传到云端: \(localNote.title)")
                        }
                    } catch {
                        print("[SYNC] 上传笔记失败: \(error.localizedDescription)")
                        // 继续处理，不中断同步
                    }
                } else {
                    // 3.2 不在新建队列，删除本地笔记
                    // 但需要检查是否有待处理的更新操作（可能笔记正在上传中）
                    let hasUpdateOp = pendingOps.contains { op in
                        op.type == .updateNote && op.noteId == localNote.id
                    }
                    if !hasUpdateOp {
                        // 没有待处理的操作，删除本地笔记
                        try localStorage.deleteNote(noteId: localNote.id)
                        print("[SYNC] 笔记不在新建队列，已删除本地: \(localNote.title)")
                    } else {
                        print("[SYNC] 笔记有待处理的更新操作，保留本地: \(localNote.title)")
                    }
                }
            }
        }
        
        // 处理本地独有的文件夹
        for localFolder in localFolders {
            if !localFolder.isSystem && 
               localFolder.id != "0" && 
               localFolder.id != "starred" &&
               !cloudFolderIds.contains(localFolder.id) {
                // 情况3：只有本地存在，云端不存在
                // 3.1 检查离线新建队列
                let hasCreateOp = pendingOps.contains { op in
                    op.type == .createFolder && op.noteId == localFolder.id
                }
                if hasCreateOp {
                    // 在新建队列中，上传到云端
                    let response = try await miNoteService.createFolder(name: localFolder.name)
                    
                    // 解析响应并获取服务器返回的文件夹ID
                    if let code = response["code"] as? Int, code == 0,
                       let data = response["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any] {
                        
                        // 处理 ID（可能是 String 或 Int）
                        var serverFolderId: String?
                        if let idString = entry["id"] as? String {
                            serverFolderId = idString
                        } else if let idInt = entry["id"] as? Int {
                            serverFolderId = String(idInt)
                        }
                        
                        if let folderId = serverFolderId, folderId != localFolder.id {
                            // ID不同，需要更新
                            // 1. 更新所有使用旧文件夹ID的笔记
                            try DatabaseService.shared.updateNotesFolderId(oldFolderId: localFolder.id, newFolderId: folderId)
                            
                            // 2. 删除旧的文件夹记录
                            try DatabaseService.shared.deleteFolder(folderId: localFolder.id)
                            
                            // 3. 创建新文件夹并保存
                            let updatedFolder = Folder(
                                id: folderId,
                                name: entry["subject"] as? String ?? localFolder.name,
                                count: 0,
                                isSystem: false,
                                createdAt: Date()
                            )
                            try localStorage.saveFolders([updatedFolder])
                            
                            print("[SYNC] ✅ 文件夹ID已更新: \(localFolder.id) -> \(folderId), 并删除了旧文件夹记录")
                        } else {
                            print("[SYNC] 文件夹在新建队列中，已上传到云端: \(localFolder.name), ID: \(serverFolderId ?? localFolder.id)")
                        }
                    } else {
                        print("[SYNC] ⚠️ 文件夹在新建队列中，已上传到云端，但服务器返回无效响应: \(localFolder.name)")
                    }
                } else {
                    // 3.2 不在新建队列，删除本地文件夹
                    try DatabaseService.shared.deleteFolder(folderId: localFolder.id)
                    print("[SYNC] 文件夹不在新建队列，已删除本地: \(localFolder.name)")
                }
            }
        }
    }
    
    // MARK: - 处理单个笔记
    
    /// 处理单个笔记（完整同步模式）
    /// 
    /// 在完整同步模式下，直接下载并替换本地笔记，不进行任何比较
    /// 
    /// - Parameters:
    ///   - note: 要处理的笔记
    ///   - isFullSync: 是否为完整同步模式
    /// - Returns: 同步结果
    private func processNote(_ note: Note, isFullSync: Bool = false) async throws -> NoteSyncResult {
        print("[SYNC] 开始处理笔记: \(note.id) - \(note.title), 完整同步模式: \(isFullSync)")
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)
        
        do {
            // 如果是完整同步模式，直接下载并替换，不进行任何比较
            if isFullSync {
                print("[SYNC] 完整同步模式：直接下载并替换笔记: \(note.id)")
                // 获取笔记详情（包含完整内容）
                syncStatusMessage = "下载笔记: \(note.title)"
                print("[SYNC] 获取笔记详情: \(note.id)")
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    print("[SYNC] 获取笔记详情成功: \(note.id)")
                } catch let error as MiNoteError {
                    print("[SYNC] 获取笔记详情失败 (MiNoteError): \(error)")
                    switch error {
                    case .cookieExpired:
                        throw SyncError.cookieExpired
                    case .notAuthenticated:
                        throw SyncError.notAuthenticated
                    case .networkError(let underlyingError):
                        throw SyncError.networkError(underlyingError)
                    case .invalidResponse:
                        throw SyncError.networkError(error)
                    }
                } catch {
                    print("[SYNC] 获取笔记详情失败: \(error)")
                    throw SyncError.networkError(error)
                }
                
                // 更新笔记内容
                var updatedNote = note
                updatedNote.updateContent(from: noteDetails)
                print("[SYNC] 更新笔记内容完成: \(note.id), 内容长度: \(updatedNote.content.count)")
                
                // 处理图片：下载笔记中的图片，并获取更新后的 setting.data
                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    // 更新笔记的 rawData 中的 setting.data
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                    print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                }
                
                // 保存到本地（替换现有文件）
                print("[SYNC] 保存笔记到本地: \(updatedNote.id)")
                try localStorage.saveNote(updatedNote)
                print("[SYNC] 保存笔记到本地: \(note.id)")
                
                result.status = localStorage.noteExistsLocally(noteId: note.id) ? .updated : .created
                result.message = result.status == .updated ? "笔记已替换" : "笔记已下载"
                result.success = true
                return result
            }
            
            // 检查笔记是否已存在本地
            let existsLocally = localStorage.noteExistsLocally(noteId: note.id)
            print("[SYNC] 笔记 \(note.id) 本地存在: \(existsLocally)")
            
            if existsLocally {
                // 获取本地笔记对象（使用笔记对象中的updatedAt，而不是文件系统时间）
                if let localNote = try? localStorage.loadNote(noteId: note.id) {
                    let localModDate = localNote.updatedAt
                    print("[SYNC] 本地修改时间: \(localModDate), 云端修改时间: \(note.updatedAt)")
                    
                    // 比较修改时间（允许2秒的误差，因为时间戳可能有精度差异和网络延迟）
                    let timeDifference = abs(note.updatedAt.timeIntervalSince(localModDate))
                    
                    // 如果云端时间早于本地时间，且差异超过2秒，说明本地版本较新
                    if note.updatedAt < localModDate && timeDifference > 2.0 {
                        // 本地版本明显较新（差异超过2秒），跳过（本地修改尚未上传）
                        print("[SYNC] 本地版本较新，跳过: \(note.id) (本地: \(localModDate), 云端: \(note.updatedAt), 差异: \(timeDifference)秒)")
                        result.status = .skipped
                        result.message = "本地版本较新，跳过同步"
                        result.success = true
                        return result
                    }
                    
                    // 如果时间戳接近（在2秒误差内），需要获取完整内容进行比较
                    if timeDifference < 2.0 {
                        // 时间相同（在2秒误差内），需要获取完整内容检查是否真的相同
                        print("[SYNC] 时间戳接近（差异: \(timeDifference)秒），获取完整内容进行比较: \(note.id)")
                        
                        // 获取云端笔记的完整内容
                        do {
                            let noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                            var cloudNote = note
                            cloudNote.updateContent(from: noteDetails)
                            print("[SYNC] 更新笔记内容，content长度: \(cloudNote.content.count)")
                            
                            // 比较完整内容
                            let localContent = localNote.primaryXMLContent
                            let cloudContent = cloudNote.primaryXMLContent
                            
                            if localContent == cloudContent {
                                // 内容相同，跳过
                                print("[SYNC] 笔记未修改（时间和内容都相同），跳过: \(note.id)")
                                result.status = .skipped
                                result.message = "笔记未修改"
                                result.success = true
                                return result
                            } else {
                                // 内容不同，需要更新
                                print("[SYNC] 时间戳接近但内容不同，需要更新: \(note.id)")
                                // 处理图片：下载笔记中的图片，并获取更新后的 setting.data
                                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                                    // 更新笔记的 rawData 中的 setting.data
                                    var rawData = cloudNote.rawData ?? [:]
                                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                                    setting["data"] = updatedSettingData
                                    rawData["setting"] = setting
                                    cloudNote.rawData = rawData
                                    print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                                }
                                
                                // 使用已获取的 noteDetails 继续更新流程
                                var updatedNote = cloudNote
                                updatedNote.updateContent(from: noteDetails)
                                print("[SYNC] 更新笔记内容，content长度: \(updatedNote.content.count)")
                                print("[SYNC] 保存笔记到本地: \(updatedNote.id)")
                                try localStorage.saveNote(updatedNote)
                                print("[SYNC] 保存笔记到本地: \(note.id)")
                                result.status = .updated
                                result.message = "笔记已更新"
                                result.success = true
                                return result
                            }
                        } catch {
                            print("[SYNC] 获取笔记详情失败，继续使用原有逻辑: \(error)")
                            // 如果获取详情失败，继续使用原有逻辑（会在后面获取详情）
                        }
                    }
                    
                    // 云端版本较新，继续更新（会在后面获取详情并更新）
                    print("[SYNC] 需要更新笔记: \(note.id)")
                } else {
                    print("[SYNC] 无法加载本地笔记，继续同步")
                }
                
                // 获取笔记详情（包含完整内容）
                syncStatusMessage = "获取笔记详情: \(note.title)"
                print("[SYNC] 获取笔记详情: \(note.id)")
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    print("[SYNC] 获取笔记详情成功: \(note.id)")
                    print("[SYNC] 笔记详情响应结构: \(noteDetails.keys)")
                    
                    // 调试：打印响应结构
                    if let data = noteDetails["data"] as? [String: Any] {
                        print("[SYNC] data字段存在，包含: \(data.keys)")
                        if let entry = data["entry"] as? [String: Any] {
                            print("[SYNC] entry字段存在，包含: \(entry.keys)")
                            if let content = entry["content"] as? String {
                                print("[SYNC] 找到content字段，长度: \(content.count)")
                            } else {
                                print("[SYNC] entry中没有content字段")
                            }
                        } else {
                            print("[SYNC] data中没有entry字段")
                        }
                    } else {
                        print("[SYNC] 响应中没有data字段")
                        // 尝试直接查找content
                        if let content = noteDetails["content"] as? String {
                            print("[SYNC] 直接找到content字段，长度: \(content.count)")
                        }
                    }
                } catch let error as MiNoteError {
                    print("[SYNC] 获取笔记详情失败 (MiNoteError): \(error)")
                    switch error {
                    case .cookieExpired:
                        throw SyncError.cookieExpired
                    case .notAuthenticated:
                        throw SyncError.notAuthenticated
                    case .networkError(let underlyingError):
                        throw SyncError.networkError(underlyingError)
                    case .invalidResponse:
                        throw SyncError.networkError(error)
                    }
                } catch {
                    print("[SYNC] 获取笔记详情失败: \(error)")
                    throw SyncError.networkError(error)
                }
                
                // 更新笔记内容
                var updatedNote = note
                updatedNote.updateContent(from: noteDetails)
                print("[SYNC] 更新笔记内容完成: \(note.id), 内容长度: \(updatedNote.content.count)")
                
                // 处理图片：下载笔记中的图片，并获取更新后的 setting.data
                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    // 更新笔记的 rawData 中的 setting.data
                    var rawData = updatedNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    updatedNote.rawData = rawData
                    print("[SYNC] 更新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                }
                
                // 调试：检查更新后的内容
                if updatedNote.content.isEmpty {
                    print("[SYNC] 警告：更新后内容仍然为空！")
                    print("[SYNC] 原始响应: \(noteDetails)")
                }
                
                // 保存到本地
                print("[SYNC] 保存笔记到本地: \(updatedNote.id)")
                try localStorage.saveNote(updatedNote)
                print("[SYNC] 保存笔记到本地: \(note.id)")
                
                result.status = .updated
                result.message = "笔记已更新"
                
            } else {
                // 新笔记，获取详情并保存
                syncStatusMessage = "下载新笔记: \(note.title)"
                print("[SYNC] 下载新笔记: \(note.id)")
                let noteDetails: [String: Any]
                do {
                    noteDetails = try await miNoteService.fetchNoteDetails(noteId: note.id)
                    print("[SYNC] 获取新笔记详情成功: \(note.id)")
                    print("[SYNC] 新笔记详情响应结构: \(noteDetails.keys)")
                    
                    // 调试：打印响应结构
                    if let data = noteDetails["data"] as? [String: Any] {
                        print("[SYNC] data字段存在，包含: \(data.keys)")
                        if let entry = data["entry"] as? [String: Any] {
                            print("[SYNC] entry字段存在，包含: \(entry.keys)")
                            if let content = entry["content"] as? String {
                                print("[SYNC] 找到content字段，长度: \(content.count)")
                            } else {
                                print("[SYNC] entry中没有content字段")
                            }
                        } else {
                            print("[SYNC] data中没有entry字段")
                        }
                    } else {
                        print("[SYNC] 响应中没有data字段")
                        // 尝试直接查找content
                        if let content = noteDetails["content"] as? String {
                            print("[SYNC] 直接找到content字段，长度: \(content.count)")
                        }
                    }
                } catch let error as MiNoteError {
                    print("[SYNC] 获取新笔记详情失败 (MiNoteError): \(error)")
                    switch error {
                    case .cookieExpired:
                        throw SyncError.cookieExpired
                    case .notAuthenticated:
                        throw SyncError.notAuthenticated
                    case .networkError(let underlyingError):
                        throw SyncError.networkError(underlyingError)
                    case .invalidResponse:
                        throw SyncError.networkError(error)
                    }
                } catch {
                    print("[SYNC] 获取新笔记详情失败: \(error)")
                    throw SyncError.networkError(error)
                }
                
                // 更新笔记内容
                var newNote = note
                newNote.updateContent(from: noteDetails)
                print("[SYNC] 更新新笔记内容完成: \(note.id), 内容长度: \(newNote.content.count)")
                
                // 处理图片：下载笔记中的图片，并获取更新后的 setting.data
                if let updatedSettingData = try await downloadNoteImages(from: noteDetails, noteId: note.id) {
                    // 更新笔记的 rawData 中的 setting.data
                    var rawData = newNote.rawData ?? [:]
                    var setting = rawData["setting"] as? [String: Any] ?? [:]
                    setting["data"] = updatedSettingData
                    rawData["setting"] = setting
                    newNote.rawData = rawData
                    print("[SYNC] 更新新笔记的 setting.data，包含 \(updatedSettingData.count) 个图片条目")
                }
                
                // 调试：检查更新后的内容
                if newNote.content.isEmpty {
                    print("[SYNC] 警告：新笔记更新后内容仍然为空！")
                    print("[SYNC] 原始响应: \(noteDetails)")
                }
                
                // 保存到本地
                print("[SYNC] 保存新笔记到本地: \(newNote.id)")
                try localStorage.saveNote(newNote)
                print("[SYNC] 保存新笔记到本地: \(note.id)")
                
                result.status = .created
                result.message = "新笔记已下载"
            }
            
            result.success = true
            print("[SYNC] 笔记处理成功: \(note.id)")
            
        } catch let error as SyncError {
            // 如果是SyncError，直接重新抛出
            print("[SYNC] SyncError: \(error)")
            throw error
        } catch {
            print("[SYNC] 其他错误: \(error)")
            result.success = false
            result.status = .failed
            result.message = "处理失败: \(error.localizedDescription)"
        }
        
        return result
    }
    
    // MARK: - 处理文件夹
    
    /// 处理文件夹（创建本地目录）
    /// 
    /// 注意：此方法已废弃，文件夹现在通过数据库管理，不再使用文件系统目录
    /// 
    /// - Parameter folder: 要处理的文件夹
    private func processFolder(_ folder: Folder) async throws {
        // 创建文件夹目录
        do {
            _ = try localStorage.createFolder(folder.name)
        } catch {
            print("创建文件夹失败 \(folder.name): \(error)")
        }
    }
    
    // MARK: - 图片处理
    
    /// 下载笔记中的图片
    /// 
    /// 从笔记的setting.data字段中提取图片信息，并下载到本地
    /// 图片信息包括：fileId、mimeType等
    /// 
    /// - Parameters:
    ///   - noteDetails: 笔记详情响应（包含setting.data字段）
    ///   - noteId: 笔记ID（用于日志和错误处理）
    /// - Returns: 更新后的setting.data数组，包含图片下载状态信息
    private func downloadNoteImages(from noteDetails: [String: Any], noteId: String) async throws -> [[String: Any]]? {
        print("[SYNC] 开始下载笔记图片: \(noteId)")
        print("[SYNC] noteDetails 键: \(noteDetails.keys)")
        
        // 提取 entry 对象
        var entry: [String: Any]?
        if let data = noteDetails["data"] as? [String: Any] {
            print("[SYNC] 找到 data 字段，包含键: \(Array(data.keys))")
            if let dataEntry = data["entry"] as? [String: Any] {
                entry = dataEntry
                print("[SYNC] 从 data.entry 提取到 entry，包含键: \(Array(dataEntry.keys))")
            }
        } else if let directEntry = noteDetails["entry"] as? [String: Any] {
            entry = directEntry
            print("[SYNC] 从顶层 entry 提取到 entry，包含键: \(Array(directEntry.keys))")
        } else if noteDetails["id"] != nil || noteDetails["content"] != nil {
            entry = noteDetails
            print("[SYNC] 使用 noteDetails 本身作为 entry，包含键: \(Array(noteDetails.keys))")
        }
        
        guard let entry = entry else {
            print("[SYNC] 无法提取 entry，跳过图片下载: \(noteId)")
            return nil
        }
        
        // 从 setting.data 中提取图片信息
        guard let setting = entry["setting"] as? [String: Any] else {
            print("[SYNC] entry 中没有 setting 字段，跳过图片下载: \(noteId)")
            print("[SYNC] entry 包含的键: \(entry.keys)")
            return nil
        }
        
        print("[SYNC] 找到 setting 字段，包含键: \(setting.keys)")
        
        guard var settingData = setting["data"] as? [[String: Any]] else {
            print("[SYNC] setting 中没有 data 字段或 data 不是数组，跳过图片下载: \(noteId)")
            return nil
        }
        
        print("[SYNC] 找到 \(settingData.count) 个图片条目")
        
        // 使用简单的异步循环，避免复杂的并发问题
        for index in 0..<settingData.count {
            let imgData = settingData[index]
            print("[SYNC] 处理图片条目 \(index + 1)/\(settingData.count): \(imgData.keys)")
            
            guard let fileId = imgData["fileId"] as? String else {
                print("[SYNC] 图片条目 \(index + 1) 没有 fileId，跳过")
                continue
            }
            
            guard let mimeType = imgData["mimeType"] as? String else {
                print("[SYNC] 图片条目 \(index + 1) 没有 mimeType，跳过")
                continue
            }
            
            guard mimeType.hasPrefix("image/") else {
                print("[SYNC] 图片条目 \(index + 1) mimeType 不是图片类型: \(mimeType)，跳过")
                continue
            }
            
            // 提取文件类型（如 "jpeg", "png"）
            let fileType = String(mimeType.dropFirst("image/".count))
            print("[SYNC] 找到图片: fileId=\(fileId), fileType=\(fileType)")
            
            // 检查图片是否已存在
            if localStorage.imageExists(fileId: fileId, fileType: fileType) {
                print("[SYNC] 图片已存在，跳过下载: \(fileId).\(fileType)")
                // 更新 settingData 条目，添加本地存在标志
                var updatedImgData = imgData
                updatedImgData["localExists"] = true
                settingData[index] = updatedImgData
                continue
            }
            
            // 下载图片
            do {
                print("[SYNC] 开始下载图片: \(fileId).\(fileType)")
                let imageData = try await miNoteService.downloadFile(fileId: fileId, type: "note_img")
                print("[SYNC] 图片下载完成，大小: \(imageData.count) 字节")
                try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)
                print("[SYNC] 图片保存成功: \(fileId).\(fileType)")
                
                // 更新 settingData 条目，添加下载成功标志
                var updatedImgData = imgData
                updatedImgData["localExists"] = true
                updatedImgData["downloaded"] = true
                settingData[index] = updatedImgData
            } catch {
                print("[SYNC] 图片下载失败: \(fileId).\(fileType), 错误: \(error.localizedDescription)")
                // 下载失败，不更新 settingData
            }
        }
        
        print("[SYNC] 所有图片处理完成，共处理 \(settingData.count) 个条目")
        return settingData
    }
    
    // MARK: - 清理已删除的笔记
    
    /// 清理已删除的笔记（已废弃）
    /// 
    /// 此方法目前只记录日志，不执行实际清理操作
    /// 删除逻辑已整合到增量同步中
    /// 
    /// - Parameter syncStatus: 同步状态
    private func cleanupDeletedNotes(syncStatus: SyncStatus) async throws {
        syncStatusMessage = "清理已删除的笔记..."
        
        // 获取所有本地笔记
        let localNotes = try localStorage.getAllLocalNotes()
        
        // 检查哪些本地笔记不在同步状态中
        for localNote in localNotes {
            if !syncStatus.isNoteSynced(localNote.id) {
                // 笔记不在同步列表中，可能已被删除
                // 这里可以添加逻辑来确认笔记是否真的被删除
                // 暂时只是记录
                print("笔记可能已被删除: \(localNote.title) (\(localNote.id))")
            }
        }
    }
    
    // MARK: - 手动同步单个笔记
    
    /// 手动同步单个笔记
    /// 
    /// 用于用户手动触发单个笔记的同步，例如在笔记详情页面点击"同步"按钮
    /// 
    /// - Parameter noteId: 要同步的笔记ID
    /// - Returns: 同步结果
    /// - Throws: SyncError（同步错误、网络错误等）
    func syncSingleNote(noteId: String) async throws -> NoteSyncResult {
        guard miNoteService.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }
        
        syncStatusMessage = "同步单个笔记..."
        
        // 获取笔记详情
        let noteDetails: [String: Any]
        do {
            noteDetails = try await miNoteService.fetchNoteDetails(noteId: noteId)
        } catch let error as MiNoteError {
            switch error {
            case .cookieExpired:
                throw SyncError.cookieExpired
            case .notAuthenticated:
                throw SyncError.notAuthenticated
            case .networkError(let underlyingError):
                throw SyncError.networkError(underlyingError)
            case .invalidResponse:
                throw SyncError.networkError(error)
            }
        } catch {
            throw SyncError.networkError(error)
        }
        
        // 转换为Note对象
        guard let note = Note.fromMinoteData(noteDetails) else {
            throw SyncError.invalidNoteData
        }
        
        // 处理笔记
        return try await processNote(note)
    }
    
    // MARK: - 取消同步
    
    /// 取消正在进行的同步
    /// 
    /// 注意：此方法只是设置标志位，不会立即中断正在执行的网络请求
    func cancelSync() {
        isSyncing = false
        syncStatusMessage = "同步已取消"
    }
    
    // MARK: - 重试待删除的笔记
    
    /// 重试删除失败的笔记
    /// 
    /// 当笔记删除失败时（例如网络错误），会保存到待删除列表
    /// 此方法会尝试重新删除这些笔记
    /// 
    /// 建议在以下时机调用：
    /// - 应用启动时
    /// - 网络恢复时
    /// - 同步开始时
    func retryPendingDeletions() async throws {
        let pendingDeletions = localStorage.loadPendingDeletions()
        
        if pendingDeletions.isEmpty {
            return
        }
        
        print("[SYNC] 开始重试 \(pendingDeletions.count) 个待删除的笔记")
        
        guard miNoteService.isAuthenticated() else {
            print("[SYNC] 未认证，无法重试删除")
            return
        }
        
        // 如果正在同步，更新状态消息
        if isSyncing {
            syncStatusMessage = "重试删除失败的笔记..."
        }
        
        for deletion in pendingDeletions {
            do {
                // 尝试删除
                _ = try await miNoteService.deleteNote(noteId: deletion.noteId, tag: deletion.tag, purge: deletion.purge)
                print("[SYNC] 重试删除成功: \(deletion.noteId)")
                
                // 删除成功，移除待删除记录
                try localStorage.removePendingDeletion(noteId: deletion.noteId)
            } catch {
                print("[SYNC] 重试删除失败: \(deletion.noteId), 错误: \(error)")
                // 删除失败，保留在待删除列表中，下次再试
            }
        }
        
        print("[SYNC] 重试删除完成")
    }
    
    // MARK: - 重置同步状态
    
    /// 重置同步状态
    /// 
    /// 清除所有同步记录，下次同步将执行完整同步
    /// 用于解决同步问题或重新开始同步
    func resetSyncStatus() throws {
        try localStorage.clearSyncStatus()
    }
    
    // MARK: - 同步结果模型
    
    /// 同步结果
    /// 
    /// 包含同步操作的统计信息，用于UI显示和日志记录
    struct SyncResult {
        var totalNotes: Int = 0
        var syncedNotes: Int = 0
        var failedNotes: Int = 0
        var skippedNotes: Int = 0
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
        var success: Bool = false
        var status: SyncStatusType = .failed
        var message: String = ""
        
        /// 同步状态类型
        enum SyncStatusType {
            case created
            case updated
            case skipped
            case failed
        }
    }
    
    // MARK: - 同步错误
    
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
                return "同步正在进行中"
            case .notAuthenticated:
                return "未登录小米账号"
            case .invalidNoteData:
                return "笔记数据格式无效"
            case .cookieExpired:
                return "Cookie已过期，请重新登录或刷新Cookie"
            case .networkError(let error):
                return "网络错误: \(error.localizedDescription)"
            case .storageError(let error):
                return "存储错误: \(error.localizedDescription)"
            }
        }
    }
}
