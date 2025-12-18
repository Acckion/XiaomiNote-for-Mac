import Foundation

final class SyncService: @unchecked Sendable {
    static let shared = SyncService()
    
    private let miNoteService = MiNoteService.shared
    private let localStorage = LocalStorageService.shared
    
    private var isSyncing = false
    private var syncProgress: Double = 0
    private var syncStatusMessage: String = ""
    
    // MARK: - 同步状态
    
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
    
    /// 执行完整同步（清除所有本地数据，拉取所有云端文件夹）
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
                    
                    // 下载图片
                    try await downloadNoteImages(from: noteDetails, noteId: note.id)
                    
                    // 保存到本地
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
            
            // 3. 保存所有云端文件夹
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
    
    /// 执行增量同步（只同步自上次同步以来的更改）
    func performIncrementalSync() async throws -> SyncResult {
        guard !isSyncing else {
            throw SyncError.alreadySyncing
        }
        
        guard miNoteService.isAuthenticated() else {
            throw SyncError.notAuthenticated
        }
        
        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "开始增量同步..."
        
        defer {
            isSyncing = false
        }
        
        var result = SyncResult()
        
        do {
            // 加载现有的同步状态
            guard let syncStatus = localStorage.loadSyncStatus() else {
                // 如果没有同步状态，执行完整同步
                syncStatusMessage = "未找到同步记录，执行完整同步..."
                return try await performFullSync()
            }
            
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
                try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id)
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
                    try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id)
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
                let noteDetails = try await miNoteService.fetchNoteDetails(noteId: cloudNote.id)
                var updatedNote = cloudNote
                updatedNote.updateContent(from: noteDetails)
                try await downloadNoteImages(from: noteDetails, noteId: cloudNote.id)
                try localStorage.saveNote(updatedNote)
                result.status = .created
                result.message = "已从云端拉取"
                result.success = true
                print("[SYNC] 新笔记，已拉取到本地: \(cloudNote.title)")
            }
        }
        
        return result
    }
    
    /// 处理只有本地存在但云端不存在的笔记和文件夹
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
                    _ = try await miNoteService.createNote(
                        title: localNote.title,
                        content: localNote.content,
                        folderId: localNote.folderId
                    )
                    print("[SYNC] 笔记在新建队列中，已上传到云端: \(localNote.title)")
                } else {
                    // 3.2 不在新建队列，删除本地笔记
                    try localStorage.deleteNote(noteId: localNote.id)
                    print("[SYNC] 笔记不在新建队列，已删除本地: \(localNote.title)")
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
                    _ = try await miNoteService.createFolder(name: localFolder.name)
                    print("[SYNC] 文件夹在新建队列中，已上传到云端: \(localFolder.name)")
                } else {
                    // 3.2 不在新建队列，删除本地文件夹
                    try DatabaseService.shared.deleteFolder(folderId: localFolder.id)
                    print("[SYNC] 文件夹不在新建队列，已删除本地: \(localFolder.name)")
                }
            }
        }
    }
    
    // MARK: - 处理单个笔记
    
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
                
                // 处理图片：下载笔记中的图片
                try await downloadNoteImages(from: noteDetails, noteId: note.id)
                
                // 保存到本地（替换现有文件）
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
                                // 处理图片：下载笔记中的图片
                                try await downloadNoteImages(from: noteDetails, noteId: note.id)
                                // 使用已获取的 noteDetails 继续更新流程
                                var updatedNote = cloudNote
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
                
                // 处理图片：下载笔记中的图片
                try await downloadNoteImages(from: noteDetails, noteId: note.id)
                
                // 调试：检查更新后的内容
                if updatedNote.content.isEmpty {
                    print("[SYNC] 警告：更新后内容仍然为空！")
                    print("[SYNC] 原始响应: \(noteDetails)")
                }
                
                // 保存到本地
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
                
                // 处理图片：下载笔记中的图片
                try await downloadNoteImages(from: noteDetails, noteId: note.id)
                
                // 调试：检查更新后的内容
                if newNote.content.isEmpty {
                    print("[SYNC] 警告：新笔记更新后内容仍然为空！")
                    print("[SYNC] 原始响应: \(noteDetails)")
                }
                
                // 保存到本地
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
    
    // MARK: 处理文件夹
    
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
    /// - Parameters:
    ///   - noteDetails: 笔记详情响应
    ///   - noteId: 笔记ID（用于日志）
    private func downloadNoteImages(from noteDetails: [String: Any], noteId: String) async throws {
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
            return
        }
        
        // 从 setting.data 中提取图片信息
        guard let setting = entry["setting"] as? [String: Any] else {
            print("[SYNC] entry 中没有 setting 字段，跳过图片下载: \(noteId)")
            print("[SYNC] entry 包含的键: \(entry.keys)")
            return
        }
        
        print("[SYNC] 找到 setting 字段，包含键: \(setting.keys)")
        
        guard let settingData = setting["data"] as? [[String: Any]] else {
            print("[SYNC] setting 中没有 data 字段或 data 不是数组，跳过图片下载: \(noteId)")
            return
        }
        
        print("[SYNC] 找到 \(settingData.count) 个图片条目")
        
        var imageTasks: [Task<Void, Never>] = []
        var imageCount = 0
        
        for (index, imgData) in settingData.enumerated() {
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
            imageCount += 1
            print("[SYNC] 找到图片 \(imageCount): fileId=\(fileId), fileType=\(fileType)")
            
            // 检查图片是否已存在
            if localStorage.imageExists(fileId: fileId, fileType: fileType) {
                print("[SYNC] 图片已存在，跳过下载: \(fileId).\(fileType)")
                continue
            }
            
            // 创建下载任务（不抛出错误，错误在内部处理）
            let task = Task<Void, Never> {
                do {
                    print("[SYNC] 开始下载图片: \(fileId).\(fileType)")
                    let imageData = try await miNoteService.downloadFile(fileId: fileId, type: "note_img")
                    print("[SYNC] 图片下载完成，大小: \(imageData.count) 字节")
                    try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)
                    print("[SYNC] 图片保存成功: \(fileId).\(fileType)")
                } catch {
                    print("[SYNC] 图片下载失败: \(fileId).\(fileType), 错误: \(error.localizedDescription)")
                    // 不抛出错误，继续下载其他图片
                }
            }
            imageTasks.append(task)
        }
        
        // 等待所有图片下载完成
        if !imageTasks.isEmpty {
            print("[SYNC] 等待 \(imageTasks.count) 张图片下载完成...")
            for task in imageTasks {
                await task.value
            }
            print("[SYNC] 所有图片下载完成")
        } else {
            print("[SYNC] 没有需要下载的图片（共找到 \(imageCount) 个图片条目）")
        }
    }
    
    // MARK: 清理已删除的笔记
    
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
    
    func cancelSync() {
        isSyncing = false
        syncStatusMessage = "同步已取消"
    }
    
    // MARK: - 重试待删除的笔记
    
    /// 重试删除失败的笔记（可在应用启动时或同步时调用）
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
    
    func resetSyncStatus() throws {
        try localStorage.clearSyncStatus()
    }
    
    // MARK: - 同步结果模型
    
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
    
    struct NoteSyncResult {
        let noteId: String
        let noteTitle: String
        var success: Bool = false
        var status: SyncStatusType = .failed
        var message: String = ""
        
        enum SyncStatusType {
            case created
            case updated
            case skipped
            case failed
        }
    }
    
    // MARK: - 同步错误
    
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
