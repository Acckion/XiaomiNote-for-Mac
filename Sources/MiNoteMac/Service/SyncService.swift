import Foundation

class SyncService {
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
    
    /// 执行完整同步（拉取所有云端笔记到本地）
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
        syncStatusMessage = "开始同步..."
        
        defer {
            isSyncing = false
            print("[SYNC] 同步结束，isSyncing设置为false")
        }
        
        var result = SyncResult()
        var syncTag = ""
        
        do {
            // 加载现有的同步状态
            var syncStatus = localStorage.loadSyncStatus() ?? SyncStatus()
            print("[SYNC] 加载同步状态：lastSyncTime=\(String(describing: syncStatus.lastSyncTime)), syncTag=\(String(describing: syncStatus.syncTag))")
            
            // 分页获取所有笔记
            var pageCount = 0
            var totalNotes = 0
            var syncedNotes = 0
            
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
                
                // 处理文件夹
                var allFolders: [Folder] = []
                for folder in folders {
                    try await processFolder(folder)
                    allFolders.append(folder)
                }
                
                // 保存文件夹列表到本地
                if !allFolders.isEmpty {
                    try localStorage.saveFolders(allFolders)
                }
                
                // 处理笔记
                for (index, note) in notes.enumerated() {
                    syncProgress = Double(syncedNotes + index) / Double(max(totalNotes, 1))
                    syncStatusMessage = "正在同步笔记: \(note.title)"
                    
                    let noteResult = try await processNote(note)
                    result.addNoteResult(noteResult)
                    
                    if noteResult.success {
                        syncStatus.addSyncedNote(note.id)
                        syncedNotes += 1
                    }
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
            
            // 更新同步状态
            syncStatus.lastSyncTime = Date()
            syncStatus.lastPageSyncTime = Date()
            try localStorage.saveSyncStatus(syncStatus)
            
            // 重试删除失败的笔记
            try await retryPendingDeletions()
            
            // 清理本地已删除的笔记
            try await cleanupDeletedNotes(syncStatus: syncStatus)
            
            syncProgress = 1.0
            syncStatusMessage = "同步完成"
            
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
            
            // 处理文件夹
            var allFolders: [Folder] = []
            for folder in folders {
                try await processFolder(folder)
                allFolders.append(folder)
            }
            
            // 保存文件夹列表到本地
            if !allFolders.isEmpty {
                try localStorage.saveFolders(allFolders)
            }
            
            // 处理笔记
            for (index, note) in notes.enumerated() {
                syncProgress = Double(index) / Double(max(notes.count, 1))
                syncStatusMessage = "正在同步笔记: \(note.title)"
                
                let noteResult = try await processNote(note)
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
    
    // MARK: - 处理单个笔记
    
    private func processNote(_ note: Note) async throws -> NoteSyncResult {
        print("[SYNC] 开始处理笔记: \(note.id) - \(note.title)")
        var result = NoteSyncResult(noteId: note.id, noteTitle: note.title)
        
        do {
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
                    if timeDifference < 2.0 {
                        // 时间相同（在2秒误差内），检查内容是否真的相同
                        print("[SYNC] 时间戳接近（差异: \(timeDifference)秒），检查内容是否相同: \(note.id)")
                        
                        // 比较内容是否相同
                        let localContent = localNote.primaryXMLContent
                        let cloudContent = note.primaryXMLContent
                        
                        if localContent == cloudContent {
                            // 内容相同，跳过
                            print("[SYNC] 笔记未修改（时间和内容都相同），跳过: \(note.id)")
                            result.status = .skipped
                            result.message = "笔记未修改"
                            return result
                        } else {
                            // 内容不同，需要更新（可能是时间戳精度问题）
                            print("[SYNC] 时间戳接近但内容不同，需要更新: \(note.id)")
                        }
                    } else if note.updatedAt < localModDate && timeDifference > 2.0 {
                        // 本地版本明显较新（差异超过2秒），跳过（本地修改尚未上传）
                        print("[SYNC] 本地版本较新，跳过: \(note.id) (本地: \(localModDate), 云端: \(note.updatedAt), 差异: \(timeDifference)秒)")
                        result.status = .skipped
                        result.message = "本地版本较新，跳过同步"
                        return result
                    }
                    // 云端版本较新或时间接近但内容不同，继续更新
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
