import Foundation
import SwiftUI

@MainActor
class NotesViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var folders: [Folder] = []
    @Published var selectedNote: Note?
    @Published var selectedFolder: Folder?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var showLoginView = false
    @Published var syncInterval: Double = 300 // 默认5分钟
    @Published var autoSave: Bool = true
    
    // 同步相关状态
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0
    @Published var syncStatusMessage: String = ""
    @Published var lastSyncTime: Date?
    @Published var syncResult: SyncService.SyncResult?
    
    private let service = MiNoteService.shared
    private let syncService = SyncService.shared
    private let localStorage = LocalStorageService.shared
    private let networkMonitor = NetworkMonitor.shared
    private let offlineQueue = OfflineOperationQueue.shared
    
    // 网络状态
    @Published var isOnline: Bool = true
    
    var filteredNotes: [Note] {
        if searchText.isEmpty {
            if let folder = selectedFolder {
                if folder.id == "starred" {
                    return notes.filter { $0.isStarred }
                } else if folder.id == "0" {
                    return notes
                } else if folder.id == "uncategorized" {
                    // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                    return notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }
                } else {
                    return notes.filter { $0.folderId == folder.id }
                }
            }
            return notes
        } else {
            return notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    /// 未分类文件夹（计算属性）
    var uncategorizedFolder: Folder {
        let uncategorizedCount = notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }.count
        return Folder(id: "uncategorized", name: "未分类", count: uncategorizedCount, isSystem: false)
    }
    
    var isLoggedIn: Bool {
        return service.isAuthenticated()
    }
    
    init() {
        // 加载本地数据
        loadLocalData()
        
        // 加载设置
        loadSettings()
        
        // 加载同步状态
        loadSyncStatus()
        
        // 设置cookie过期处理器
        setupCookieExpiredHandler()
        
        // 监听网络状态
        setupNetworkMonitoring()
        
        // 监听网络恢复通知
        NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleNetworkRestored()
        }
    }
    
    private func setupNetworkMonitoring() {
        // 绑定网络状态
        networkMonitor.$isOnline
            .assign(to: &$isOnline)
    }
    
    @MainActor
    private func handleNetworkRestored() {
        print("[VIEWMODEL] 网络已恢复，开始处理待同步操作")
        Task {
            await processPendingOperations()
        }
    }
    
    /// 处理待同步的离线操作
    private func processPendingOperations() async {
        let operations = offlineQueue.getPendingOperations()
        guard !operations.isEmpty else { return }
        
        print("[VIEWMODEL] 开始处理 \(operations.count) 个待同步操作")
        
        for operation in operations {
            do {
                switch operation.type {
                case .createNote:
                    try await processCreateNoteOperation(operation)
                case .updateNote:
                    try await processUpdateNoteOperation(operation)
                case .deleteNote:
                    try await processDeleteNoteOperation(operation)
                case .uploadImage:
                    // 图片上传操作在更新笔记时一起处理
                    break
                case .createFolder:
                    try await processCreateFolderOperation(operation)
                case .renameFolder:
                    try await processRenameFolderOperation(operation)
                case .deleteFolder:
                    try await processDeleteFolderOperation(operation)
                }
                
                // 操作成功，移除
                try offlineQueue.removeOperation(operation.id)
                print("[VIEWMODEL] 成功处理离线操作: \(operation.type.rawValue), noteId: \(operation.noteId)")
            } catch {
                print("[VIEWMODEL] 处理离线操作失败: \(operation.type.rawValue), noteId: \(operation.noteId), error: \(error.localizedDescription)")
                // 如果操作失败，保留在队列中，下次再试
            }
        }
    }
    
    private func processCreateNoteOperation(_ operation: OfflineOperation) async throws {
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "笔记不存在"])
        }
        
        // 创建笔记到云端
        let response = try await service.createNote(
            title: note.title,
            content: note.content,
            folderId: note.folderId
        )
        
        // 解析响应并更新本地笔记
        if let code = response["code"] as? Int, code == 0,
           let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any],
           let serverNoteId = entry["id"] as? String,
           let tag = entry["tag"] as? String {
            
            // 如果服务器返回的 ID 与本地不同，需要创建新笔记并删除旧的
            if note.id != serverNoteId {
                // 构建更新后的 rawData
                var updatedRawData = note.rawData ?? [:]
                for (key, value) in entry {
                    updatedRawData[key] = value
                }
                updatedRawData["tag"] = tag
                
                // 创建新的笔记对象（使用服务器返回的 ID）
                let updatedNote = Note(
                    id: serverNoteId,
                    title: note.title,
                    content: note.content,
                    folderId: note.folderId,
                    isStarred: note.isStarred,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    tags: note.tags,
                    rawData: updatedRawData
                )
                
                // 删除旧的本地文件
                try? localStorage.deleteNote(noteId: note.id)
                
                // 更新笔记列表
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    notes.remove(at: index)
                    notes.append(updatedNote)
                }
                
                // 保存新笔记
                try localStorage.saveNote(updatedNote)
            } else {
                // 更新现有笔记的 rawData
                var updatedRawData = note.rawData ?? [:]
                for (key, value) in entry {
                    updatedRawData[key] = value
                }
                updatedRawData["tag"] = tag
                
                let updatedNote = Note(
                    id: note.id,
                    title: note.title,
                    content: note.content,
                    folderId: note.folderId,
                    isStarred: note.isStarred,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    tags: note.tags,
                    rawData: updatedRawData
                )
                
                // 更新笔记列表
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    notes[index] = updatedNote
                }
                
                // 保存更新后的笔记
                try localStorage.saveNote(updatedNote)
            }
        }
        
        print("[VIEWMODEL] 离线创建的笔记已同步到云端: \(note.id)")
    }
    
    private func processUpdateNoteOperation(_ operation: OfflineOperation) async throws {
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "笔记不存在"])
        }
        
        // 更新笔记到云端
        try await updateNote(note)
        print("[VIEWMODEL] 离线更新的笔记已同步到云端: \(note.id)")
    }
    
    private func processDeleteNoteOperation(_ operation: OfflineOperation) async throws {
        // 删除操作已经在 deleteNote 中处理，这里只需要确认
        print("[VIEWMODEL] 离线删除的笔记已确认: \(operation.noteId)")
    }
    
    private func processCreateFolderOperation(_ operation: OfflineOperation) async throws {
        // 从操作数据中解析文件夹信息
        guard let operationData = try? JSONDecoder().decode([String: String].self, from: operation.data),
              let folderName = operationData["name"] else {
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"])
        }
        
        // 创建文件夹到云端
        let response = try await service.createFolder(name: folderName)
        
        // 解析响应并更新本地文件夹
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
            
            guard let folderId = serverFolderId,
                  let subject = entry["subject"] as? String else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器返回无效的文件夹信息"])
            }
            
            // 如果服务器返回的 ID 与本地不同，需要更新
            if operation.noteId != folderId {
                // 更新文件夹列表
                if let index = folders.firstIndex(where: { $0.id == operation.noteId }) {
                    let updatedFolder = Folder(
                        id: folderId,
                        name: subject,
                        count: 0,
                        isSystem: false,
                        createdAt: Date()
                    )
                    folders[index] = updatedFolder
                    // 只保存非系统文件夹
                    try localStorage.saveFolders(folders.filter { !$0.isSystem })
                }
            } else {
                // 更新现有文件夹
                if let index = folders.firstIndex(where: { $0.id == operation.noteId }) {
                    let updatedFolder = Folder(
                        id: folderId,
                        name: subject,
                        count: 0,
                        isSystem: false,
                        createdAt: Date()
                    )
                    folders[index] = updatedFolder
                    // 只保存非系统文件夹
                    try localStorage.saveFolders(folders.filter { !$0.isSystem })
                }
            }
        }
        
        print("[VIEWMODEL] 离线创建的文件夹已同步到云端: \(operation.noteId)")
    }
    
    private func processRenameFolderOperation(_ operation: OfflineOperation) async throws {
        // 从操作数据中解析文件夹信息
        guard let operationData = try? JSONDecoder().decode([String: String].self, from: operation.data),
              let oldName = operationData["oldName"],
              let newName = operationData["newName"] else {
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的文件夹重命名操作数据"])
        }
        
        // 获取本地文件夹对象
        guard var folder = folders.first(where: { $0.id == operation.noteId }) else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }
        
        // 获取最新的 tag 和 createDate
        var existingTag = folder.rawData?["tag"] as? String ?? ""
        var originalCreateDate = folder.rawData?["createDate"] as? Int
        
        do {
            let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
            if let data = folderDetails["data"] as? [String: Any],
               let entry = data["entry"] as? [String: Any] {
                if let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                    existingTag = latestTag
                }
                if let latestCreateDate = entry["createDate"] as? Int {
                    originalCreateDate = latestCreateDate
                }
            }
        } catch {
            print("[VIEWMODEL] 处理离线重命名操作时获取最新文件夹信息失败: \(error)，将使用本地存储的 tag")
        }
        
        if existingTag.isEmpty {
            existingTag = folder.id
        }
        
        // 重命名文件夹到云端
        let response = try await service.renameFolder(
            folderId: folder.id,
            newName: newName,
            existingTag: existingTag,
            originalCreateDate: originalCreateDate
        )
        
        if let code = response["code"] as? Int, code == 0 {
            // 更新本地文件夹对象
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[index].name = newName
                folders[index].rawData = response["data"] as? [String: Any] ?? response // 更新 rawData
                try localStorage.saveFolders(folders.filter { !$0.isSystem })
            }
            print("[VIEWMODEL] 离线重命名的文件夹已同步到云端: \(folder.id) -> \(newName)")
        } else {
            let code = response["code"] as? Int ?? -1
            let message = response["description"] as? String ?? response["message"] as? String ?? "同步重命名文件夹失败"
            throw NSError(domain: "MiNote", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    
    private func processDeleteFolderOperation(_ operation: OfflineOperation) async throws {
        // 从操作数据中解析文件夹信息
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let folderId = operationData["folderId"] as? String,
              let tag = operationData["tag"] as? String,
              let purge = operationData["purge"] as? Bool else {
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的文件夹删除操作数据"])
        }
        
        // 删除文件夹到云端
        _ = try await service.deleteFolder(folderId: folderId, tag: tag, purge: purge)
        print("[VIEWMODEL] 离线删除的文件夹已同步到云端: \(folderId)")
    }
    
    private func loadLocalData() {
        // 尝试从本地存储加载数据
        do {
            let localNotes = try localStorage.getAllLocalNotes()
            if !localNotes.isEmpty {
                self.notes = localNotes
                print("从本地存储加载了 \(localNotes.count) 条笔记")
            } else {
                // 如果没有本地数据，加载示例数据
                loadSampleData()
            }
        } catch {
            print("加载本地数据失败: \(error)")
            // 加载示例数据作为后备
            loadSampleData()
        }
        
        // 加载文件夹（优先从本地存储加载）
        loadFolders()
    }
    
    private func loadFolders() {
        do {
            let localFolders = try localStorage.loadFolders()
            if !localFolders.isEmpty {
                // 确保系统文件夹存在
                var foldersWithCount = localFolders
                
                // 检查是否有系统文件夹，如果没有则添加
                let hasAllNotes = foldersWithCount.contains { $0.id == "0" }
                let hasStarred = foldersWithCount.contains { $0.id == "starred" }
                
                if !hasAllNotes {
                    foldersWithCount.insert(Folder(id: "0", name: "所有笔记", count: notes.count, isSystem: true), at: 0)
                }
                if !hasStarred {
                    foldersWithCount.insert(Folder(id: "starred", name: "收藏", count: notes.filter { $0.isStarred }.count, isSystem: true), at: hasAllNotes ? 1 : 0)
                }
                
                // 更新文件夹计数
                for i in 0..<foldersWithCount.count {
                    let folder = foldersWithCount[i]
                    if folder.id == "0" {
                        foldersWithCount[i].count = notes.count
                    } else if folder.id == "starred" {
                        foldersWithCount[i].count = notes.filter { $0.isStarred }.count
                    } else {
                        foldersWithCount[i].count = notes.filter { $0.folderId == folder.id }.count
                    }
                }
                self.folders = foldersWithCount
                print("从本地存储加载了 \(localFolders.count) 个文件夹")
            } else {
                // 如果没有本地文件夹数据，加载示例数据
                loadSampleFolders()
            }
        } catch {
            print("加载文件夹失败: \(error)")
            // 加载示例数据作为后备
            loadSampleFolders()
        }
        
        // 如果没有选择文件夹，选择第一个
        if selectedFolder == nil {
            selectedFolder = folders.first
        }
    }
    
    private func loadSampleData() {
        // 使用XML格式的示例数据，匹配小米笔记真实格式
        // 注意：这里使用与真实数据相同的格式，便于测试和开发
        let sampleXMLContent = """
        <new-format/><text indent="1"><size>一级标题</size></text>
        <text indent="1"><mid-size>二级标题</mid-size></text>
        <text indent="1"><h3-size>三级标题</h3-size></text>
        <text indent="1"><b>加粗</b></text>
        <text indent="1"><i>斜体</i></text>
        <text indent="1"><b><i>加粗斜体</i></b></text>
        <text indent="1"><size><b>一级标题加粗</b></size></text>
        <text indent="1"><size><i>一级标题斜体</i></size></text>
        <text indent="1"><size><b><i>一级标题加粗斜体</i></b></size></text>
        <text indent="1"><background color="#9affe8af">高亮</background></text>
        <text indent="1">普通文本段落，包含各种格式的示例内容。</text>
        """
        
        // 创建示例笔记，使用与真实数据相同的结构
        let now = Date()
        self.notes = [
            Note(
                id: "sample-1",
                title: "购物清单",
                content: sampleXMLContent,
                folderId: "2",
                isStarred: false,
                createdAt: now,
                updatedAt: now,
                rawData: [
                    "id": "sample-1",
                    "title": "购物清单",
                    "content": sampleXMLContent,
                    "snippet": sampleXMLContent,
                    "folderId": "2",
                    "isStarred": false,
                    "createDate": Int(now.timeIntervalSince1970 * 1000),
                    "modifyDate": Int(now.timeIntervalSince1970 * 1000),
                    "type": "note",
                    "status": "normal"
                ]
            ),
            Note(
                id: "sample-2",
                title: "会议记录",
                content: sampleXMLContent,
                folderId: "1",
                isStarred: true,
                createdAt: now,
                updatedAt: now,
                rawData: [
                    "id": "sample-2",
                    "title": "会议记录",
                    "content": sampleXMLContent,
                    "snippet": sampleXMLContent,
                    "folderId": "1",
                    "isStarred": true,
                    "createDate": Int(now.timeIntervalSince1970 * 1000),
                    "modifyDate": Int(now.timeIntervalSince1970 * 1000),
                    "type": "note",
                    "status": "normal"
                ]
            ),
            Note(
                id: "sample-3",
                title: "旅行计划",
                content: sampleXMLContent,
                folderId: "2",
                isStarred: false,
                createdAt: now,
                updatedAt: now,
                rawData: [
                    "id": "sample-3",
                    "title": "旅行计划",
                    "content": sampleXMLContent,
                    "snippet": sampleXMLContent,
                    "folderId": "2",
                    "isStarred": false,
                    "createDate": Int(now.timeIntervalSince1970 * 1000),
                    "modifyDate": Int(now.timeIntervalSince1970 * 1000),
                    "type": "note",
                    "status": "normal"
                ]
            )
        ]
    }
    
    private func loadSampleFolders() {
        // 临时示例文件夹数据
        self.folders = [
            Folder(id: "0", name: "所有笔记", count: notes.count, isSystem: true),
            Folder(id: "starred", name: "收藏", count: notes.filter { $0.isStarred }.count, isSystem: true),
            Folder(id: "1", name: "工作", count: notes.filter { $0.folderId == "1" }.count),
            Folder(id: "2", name: "个人", count: notes.filter { $0.folderId == "2" }.count)
        ]
        
        // 默认选择第一个文件夹
        if selectedFolder == nil {
            selectedFolder = folders.first
        }
    }
    
    private func loadSyncStatus() {
        if let syncStatus = localStorage.loadSyncStatus() {
            lastSyncTime = syncStatus.lastSyncTime
        }
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        syncInterval = defaults.double(forKey: "syncInterval")
        if syncInterval == 0 {
            syncInterval = 300 // 默认值
        }
        autoSave = defaults.bool(forKey: "autoSave")
    }
    
    // MARK: - 同步功能
    
    /// 执行完整同步（拉取所有云端笔记到本地）
    func performFullSync() async {
        print("[VIEWMODEL] 开始执行完整同步")
        print("[VIEWMODEL] 检查认证状态...")
        let authStatus = service.isAuthenticated()
        print("[VIEWMODEL] 认证状态: \(authStatus)")
        
        guard authStatus else {
            print("[VIEWMODEL] 错误：未认证")
            print("[VIEWMODEL] Cookie状态: cookie=\(MiNoteService.shared.hasValidCookie())")
            print("[VIEWMODEL] 检查UserDefaults中的cookie...")
            if let savedCookie = UserDefaults.standard.string(forKey: "minote_cookie") {
                print("[VIEWMODEL] UserDefaults中有cookie，长度: \(savedCookie.count) 字符")
                print("[VIEWMODEL] Cookie内容（前100字符）: \(String(savedCookie.prefix(100)))")
            } else {
                print("[VIEWMODEL] UserDefaults中没有cookie")
            }
            errorMessage = "请先登录小米账号"
            return
        }
        
        print("[VIEWMODEL] 检查同步状态...")
        guard !isSyncing else {
            print("[VIEWMODEL] 错误：同步正在进行中")
            errorMessage = "同步正在进行中"
            return
        }
        
        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "开始同步..."
        errorMessage = nil
        
        print("[VIEWMODEL] 同步状态已设置为进行中")
        
        defer {
            isSyncing = false
            print("[VIEWMODEL] 同步结束，isSyncing设置为false")
        }
        
        do {
            print("[VIEWMODEL] 调用syncService.performFullSync()")
            let result = try await syncService.performFullSync()
            print("[VIEWMODEL] syncService.performFullSync() 成功完成")
            
            // 更新同步结果
            self.syncResult = result
            self.lastSyncTime = result.lastSyncTime
            
            // 重新加载本地数据
            await loadLocalDataAfterSync()
            
            syncProgress = 1.0
            syncStatusMessage = "同步完成: 成功同步 \(result.syncedNotes) 条笔记"
            print("[VIEWMODEL] 同步成功: 同步了 \(result.syncedNotes) 条笔记")
            
        } catch let error as MiNoteError {
            print("[VIEWMODEL] MiNoteError: \(error)")
            handleMiNoteError(error)
            syncStatusMessage = "同步失败"
        } catch {
            print("[VIEWMODEL] 其他错误: \(error)")
            errorMessage = "同步失败: \(error.localizedDescription)"
            syncStatusMessage = "同步失败"
        }
    }
    
    /// 执行增量同步
    func performIncrementalSync() async {
        guard service.isAuthenticated() else {
            errorMessage = "请先登录小米账号"
            return
        }
        
        guard !isSyncing else {
            errorMessage = "同步正在进行中"
            return
        }
        
        isSyncing = true
        syncProgress = 0
        syncStatusMessage = "开始增量同步..."
        errorMessage = nil
        
        defer {
            isSyncing = false
        }
        
        do {
            let result = try await syncService.performIncrementalSync()
            
            // 更新同步结果
            self.syncResult = result
            self.lastSyncTime = result.lastSyncTime
            
            // 重新加载本地数据
            await loadLocalDataAfterSync()
            
            syncProgress = 1.0
            syncStatusMessage = "增量同步完成: 成功同步 \(result.syncedNotes) 条笔记"
            
        } catch let error as MiNoteError {
            handleMiNoteError(error)
            syncStatusMessage = "增量同步失败"
        } catch {
            errorMessage = "增量同步失败: \(error.localizedDescription)"
            syncStatusMessage = "增量同步失败"
        }
    }
    
    /// 同步后重新加载本地数据
    private func loadLocalDataAfterSync() async {
        do {
            let localNotes = try localStorage.getAllLocalNotes()
            self.notes = localNotes
            
            // 重新加载文件夹（从本地存储）
            loadFolders()
            
        } catch {
            print("同步后加载本地数据失败: \(error)")
        }
    }
    
    /// 更新文件夹计数
    private func updateFolderCounts() {
        for i in 0..<folders.count {
            let folder = folders[i]
            
            if folder.id == "0" {
                // 所有笔记
                folders[i].count = notes.count
            } else if folder.id == "starred" {
                // 收藏
                folders[i].count = notes.filter { $0.isStarred }.count
            } else {
                // 普通文件夹
                folders[i].count = notes.filter { $0.folderId == folder.id }.count
            }
        }
    }
    
    /// 取消同步
    func cancelSync() {
        syncService.cancelSync()
        isSyncing = false
        syncStatusMessage = "同步已取消"
    }
    
    /// 重置同步状态
    func resetSyncStatus() {
        do {
            try syncService.resetSyncStatus()
            lastSyncTime = nil
            syncResult = nil
            errorMessage = "同步状态已重置"
        } catch {
            errorMessage = "重置同步状态失败: \(error.localizedDescription)"
        }
    }
    
    /// 获取同步状态摘要
    var syncStatusSummary: String {
        guard let lastSync = lastSyncTime else {
            return "从未同步"
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        return "上次同步: \(formatter.string(from: lastSync))"
    }
    
    // MARK: - 云端数据加载（旧方法，保留兼容性）
    
    /// 从云端加载笔记（首次登录时使用，执行完整同步）
    func loadNotesFromCloud() async {
        guard service.isAuthenticated() else {
            errorMessage = "请先登录小米账号"
            return
        }
        
        // 检查是否已有同步状态
        let hasSyncStatus = localStorage.loadSyncStatus() != nil
        
        if hasSyncStatus {
            // 如果有同步状态，使用增量同步
            await performIncrementalSync()
        } else {
            // 如果没有同步状态（首次登录），使用完整同步
            await performFullSync()
        }
    }
    
    // MARK: - 统一的笔记创建/更新接口（推荐使用）
    
    /// 创建笔记（统一接口，使用 Note 对象，支持离线模式）
    func createNote(_ note: Note) async throws {
        // 先保存到本地（无论在线还是离线）
        try localStorage.saveNote(note)
        
        // 更新视图数据
        if !notes.contains(where: { $0.id == note.id }) {
            notes.append(note)
        }
        selectedNote = note
        updateFolderCounts()
        
        // 如果离线或未认证，添加到离线队列
        if !isOnline || !service.isAuthenticated() {
            let operationData = try JSONEncoder().encode([
                "title": note.title,
                "content": note.content,
                "folderId": note.folderId
            ])
            let operation = OfflineOperation(
                type: .createNote,
                noteId: note.id,
                data: operationData
            )
            try offlineQueue.addOperation(operation)
            print("[VIEWMODEL] 离线模式：笔记已保存到本地，等待同步: \(note.id)")
            return
        }
        
        // 在线模式：尝试上传到云端
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let response = try await service.createNote(
                title: note.title,
                content: note.content,
                folderId: note.folderId
            )
            
            // 解析响应：响应格式为 {"code": 0, "data": {"entry": {...}}}
            var noteId: String?
            var tag: String?
            var entryData: [String: Any]?
            
            // 检查响应格式
            if let code = response["code"] as? Int, code == 0 {
                if let data = response["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any] {
                    noteId = entry["id"] as? String
                    tag = entry["tag"] as? String
                    entryData = entry
                    print("[VIEWMODEL] 从 data.entry 获取笔记信息: id=\(noteId ?? "nil"), tag=\(tag ?? "nil")")
                }
            } else {
                // 兼容旧格式：直接在响应根级别
                noteId = response["id"] as? String
                tag = response["tag"] as? String
                entryData = response
                print("[VIEWMODEL] 使用旧格式响应: id=\(noteId ?? "nil"), tag=\(tag ?? "nil")")
            }
            
            if let noteId = noteId, let tag = tag, !tag.isEmpty {
                // 更新 rawData，包含完整的 entry 数据
                var updatedRawData = note.rawData ?? [:]
                if let entryData = entryData {
                    for (key, value) in entryData {
                        updatedRawData[key] = value
                    }
                }
                updatedRawData["tag"] = tag
                
                // 如果本地笔记的 ID 与服务器返回的不同，需要创建新笔记并删除旧的
                if note.id != noteId {
                    // 创建新的笔记对象（使用服务器返回的 ID）
                    let updatedNote = Note(
                        id: noteId,
                        title: note.title,
                        content: note.content,
                        folderId: note.folderId,
                        isStarred: note.isStarred,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        tags: note.tags,
                        rawData: updatedRawData
                    )
                    
                    // 删除旧的本地文件
                    try? localStorage.deleteNote(noteId: note.id)
                    
                    // 更新笔记列表
                    if let index = notes.firstIndex(where: { $0.id == note.id }) {
                        notes.remove(at: index)
                        notes.append(updatedNote)
                    }
                    
                    // 保存新笔记
                    try localStorage.saveNote(updatedNote)
                    
                    // 更新选中状态
                    selectedNote = updatedNote
                } else {
                    // ID 相同，更新现有笔记
                    let updatedNote = Note(
                        id: note.id,
                        title: note.title,
                        content: note.content,
                        folderId: note.folderId,
                        isStarred: note.isStarred,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        tags: note.tags,
                        rawData: updatedRawData
                    )
                    
                    // 更新笔记列表
                    if let index = notes.firstIndex(where: { $0.id == note.id }) {
                        notes[index] = updatedNote
                    }
                    
                    // 保存更新后的笔记
                    try localStorage.saveNote(updatedNote)
                    
                    // 更新选中状态
                    selectedNote = updatedNote
                }
                
                // 更新文件夹计数
                updateFolderCounts()
            } else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "创建笔记失败：服务器返回无效响应"])
            }
        } catch {
            // 网络错误：添加到离线队列
            if let urlError = error as? URLError {
                let operationData = try JSONEncoder().encode([
                    "title": note.title,
                    "content": note.content,
                    "folderId": note.folderId
                ])
                let operation = OfflineOperation(
                    type: .createNote,
                    noteId: note.id,
                    data: operationData
                )
                try offlineQueue.addOperation(operation)
                print("[VIEWMODEL] 网络错误：笔记已保存到本地，等待同步: \(note.id)")
                errorMessage = "网络错误，笔记已保存到本地，将在网络恢复后自动同步"
            } else {
                errorMessage = "创建笔记失败: \(error.localizedDescription)"
                throw error
            }
        }
    }
    
    /// 更新笔记（统一接口，使用 Note 对象，支持离线模式）
    func updateNote(_ note: Note) async throws {
        // 先保存到本地（无论在线还是离线）
        try localStorage.saveNote(note)
        
        // 更新笔记列表
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
        
        // 如果离线或未认证，添加到离线队列
        if !isOnline || !service.isAuthenticated() {
            let operationData = try JSONEncoder().encode([
                "title": note.title,
                "content": note.content,
                "folderId": note.folderId
            ])
            let operation = OfflineOperation(
                type: .updateNote,
                noteId: note.id,
                data: operationData
            )
            try offlineQueue.addOperation(operation)
            print("[VIEWMODEL] 离线模式：笔记已更新到本地，等待同步: \(note.id)")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            // 参考 Obsidian 插件：每次上传前都先获取云端最新的笔记信息，包括 tag
            var existingTag = note.rawData?["tag"] as? String ?? ""
            var originalCreateDate = note.rawData?["createDate"] as? Int
            
            print("[VIEWMODEL] 上传前获取最新 tag，当前 tag: \(existingTag.isEmpty ? "空" : existingTag)")
            do {
                let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
                if let data = noteDetails["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any] {
                    // 获取最新的 tag
                    if let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                        existingTag = latestTag
                        print("[VIEWMODEL] 从服务器获取到最新 tag: \(existingTag)")
                    }
                    // 获取最新的 createDate
                    if let latestCreateDate = entry["createDate"] as? Int {
                        originalCreateDate = latestCreateDate
                        print("[VIEWMODEL] 从服务器获取到最新 createDate: \(latestCreateDate)")
                    }
                }
            } catch {
                print("[VIEWMODEL] 获取最新笔记信息失败: \(error)，将使用本地存储的 tag")
            }
            
            // 确保 tag 不为空（如果仍然为空，使用 noteId 作为 fallback）
            if existingTag.isEmpty {
                existingTag = note.id
                print("[VIEWMODEL] 警告：tag 仍然为空，使用 noteId 作为 fallback: \(existingTag)")
            }
            
            // 从 rawData 中提取图片信息（setting.data）
            var imageData: [[String: Any]]? = nil
            if let rawData = note.rawData,
               let setting = rawData["setting"] as? [String: Any],
               let settingData = setting["data"] as? [[String: Any]] {
                imageData = settingData
            }
            
            let response = try await service.updateNote(
                noteId: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId,
                existingTag: existingTag,
                originalCreateDate: originalCreateDate,
                imageData: imageData
            )
            
            // 检查响应是否成功（小米笔记API返回格式: {"code": 0, "data": {...}}）
            let code = response["code"] as? Int ?? -1
            if code == 0 {
                // 更新本地笔记
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    var updatedNote = note
                    
                    // 从响应中提取更新后的数据
                    if let data = response["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any] {
                        // 更新 rawData，保留原有数据并合并新数据
                        var updatedRawData = updatedNote.rawData ?? [:]
                        for (key, value) in entry {
                            updatedRawData[key] = value
                        }
                        updatedRawData["tag"] = entry["tag"] ?? existingTag  // 确保tag被更新
                        
                        // 优先使用服务器返回的 modifyDate，确保时间戳一致
                        if let modifyDate = entry["modifyDate"] as? Int {
                            updatedRawData["modifyDate"] = modifyDate
                            updatedNote.updatedAt = Date(timeIntervalSince1970: TimeInterval(modifyDate) / 1000)
                            print("[VIEWMODEL] 使用服务器返回的 modifyDate: \(modifyDate), updatedAt: \(updatedNote.updatedAt)")
                        } else {
                            // 如果服务器没有返回 modifyDate，使用当前时间
                            let currentModifyDate = Int(Date().timeIntervalSince1970 * 1000)
                            updatedRawData["modifyDate"] = currentModifyDate
                            updatedNote.updatedAt = Date()
                            print("[VIEWMODEL] 服务器未返回 modifyDate，使用当前时间: \(currentModifyDate)")
                        }
                        
                        updatedNote.rawData = updatedRawData
                        
                        // 更新笔记内容（如果响应中包含）
                        if let newContent = entry["content"] as? String {
                            updatedNote.content = newContent
                        }
                    } else {
                        // 如果响应格式不同，至少更新rawData
                        var updatedRawData = updatedNote.rawData ?? [:]
                        updatedRawData.merge(response) { (_, new) in new }
                        updatedNote.rawData = updatedRawData
                    }
                    
                    // 保存到本地存储
                    try localStorage.saveNote(updatedNote)
                    
                    notes[index] = updatedNote
                    selectedNote = updatedNote
                    
                    print("[VIEWMODEL] 笔记更新成功: \(note.id), tag: \(updatedNote.rawData?["tag"] as? String ?? "无")")
                }
            } else {
                let message = response["message"] as? String ?? "更新笔记失败"
                print("[VIEWMODEL] 更新笔记失败，code: \(code), message: \(message)")
                throw NSError(domain: "MiNote", code: code, userInfo: [NSLocalizedDescriptionKey: message])
            }
        } catch {
            // 网络错误：添加到离线队列
            if let urlError = error as? URLError {
                let operationData = try? JSONEncoder().encode([
                    "title": note.title,
                    "content": note.content,
                    "folderId": note.folderId
                ])
                if let operationData = operationData {
                    let operation = OfflineOperation(
                        type: .updateNote,
                        noteId: note.id,
                        data: operationData
                    )
                    try? offlineQueue.addOperation(operation)
                    print("[VIEWMODEL] 网络错误：笔记已更新到本地，等待同步: \(note.id)")
                    errorMessage = "网络错误，笔记已更新到本地，将在网络恢复后自动同步"
                } else {
                    errorMessage = "更新笔记失败: \(error.localizedDescription)"
                    throw error
                }
            } else {
                errorMessage = "更新笔记失败: \(error.localizedDescription)"
                throw error
            }
        }
    }
    
    /// 确保笔记有完整内容（如果内容为空，从服务器获取）
    func ensureNoteHasFullContent(_ note: Note) async {
        // 如果笔记已经有完整内容，不需要获取
        if !note.content.isEmpty {
            return
        }
        
        // 如果连 snippet 都没有，可能笔记不存在，不需要获取
        if note.rawData?["snippet"] == nil {
            return
        }
        
        print("[VIEWMODEL] 笔记内容为空，获取完整内容: \(note.id)")
        
        do {
            // 获取笔记详情
            let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
            
            // 更新笔记内容
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                var updatedNote = notes[index]
                updatedNote.updateContent(from: noteDetails)
                
                // 保存到本地
                try localStorage.saveNote(updatedNote)
                
                // 更新列表中的笔记
                notes[index] = updatedNote
                
                // 如果这是当前选中的笔记，更新选中状态
                if selectedNote?.id == note.id {
                    selectedNote = updatedNote
                }
                
                print("[VIEWMODEL] 已获取并更新笔记完整内容: \(note.id), 内容长度: \(updatedNote.content.count)")
            }
        } catch {
            print("[VIEWMODEL] 获取笔记完整内容失败: \(error.localizedDescription)")
            // 不显示错误，因为可能只是网络问题，用户仍然可以查看 snippet
        }
    }
    
    func deleteNote(_ note: Note) {
        // 1. 先在本地删除
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes.remove(at: index)
            
            // 更新文件夹计数
            if let folderIndex = folders.firstIndex(where: { $0.id == note.folderId }) {
                folders[folderIndex].count = max(0, folders[folderIndex].count - 1)
            }
            
            // 如果删除的是当前选中的笔记，清空选择
            if selectedNote?.id == note.id {
                selectedNote = nil
            }
        }
        
        // 2. 从本地存储删除
        do {
            try localStorage.deleteNote(noteId: note.id)
        } catch {
            print("[VIEWMODEL] 删除本地笔记失败: \(error)")
        }
        
        // 3. 尝试使用API删除云端
        Task {
            do {
                // 获取笔记的 tag
                let tag = note.rawData?["tag"] as? String ?? note.id
                
                // 如果 tag 为空，尝试从服务器获取最新的 tag
                var finalTag = tag
                if finalTag.isEmpty || finalTag == note.id {
                    print("[VIEWMODEL] tag 为空或等于 noteId，尝试从服务器获取最新 tag")
                    do {
                        let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
                        if let data = noteDetails["data"] as? [String: Any],
                           let entry = data["entry"] as? [String: Any],
                           let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                            finalTag = latestTag
                            print("[VIEWMODEL] 从服务器获取到最新 tag: \(finalTag)")
                        }
                    } catch {
                        print("[VIEWMODEL] 获取最新 tag 失败: \(error)，将使用 noteId")
                    }
                }
                
                // 确保 tag 不为空
                if finalTag.isEmpty {
                    finalTag = note.id
                }
                
                // 调用删除API
                _ = try await service.deleteNote(noteId: note.id, tag: finalTag, purge: false)
                print("[VIEWMODEL] 云端删除成功: \(note.id)")
                
                // 删除成功，移除待删除记录（如果存在）
                try? localStorage.removePendingDeletion(noteId: note.id)
                
            } catch {
                print("[VIEWMODEL] 云端删除失败: \(error)，保存到待删除列表")
                
                // 删除失败，保存到待删除列表
                let tag = note.rawData?["tag"] as? String ?? note.id
                let pendingDeletion = PendingDeletion(noteId: note.id, tag: tag, purge: false)
                do {
                    try localStorage.addPendingDeletion(pendingDeletion)
                    print("[VIEWMODEL] 已保存到待删除列表: \(note.id)")
                } catch {
                    print("[VIEWMODEL] 保存待删除列表失败: \(error)")
                }
            }
        }
    }
    
    func toggleStar(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index].isStarred.toggle()
            
            // 更新文件夹计数
            if note.isStarred {
                // 从收藏变为非收藏
                if let folderIndex = folders.firstIndex(where: { $0.id == "starred" }) {
                    folders[folderIndex].count = max(0, folders[folderIndex].count - 1)
                }
            } else {
                // 从非收藏变为收藏
                if let folderIndex = folders.firstIndex(where: { $0.id == "starred" }) {
                    folders[folderIndex].count += 1
                }
            }
            
            // 如果更新的是当前选中的笔记，更新选择
            if selectedNote?.id == note.id {
                selectedNote = notes[index]
            }
        }
    }
    
    func selectFolder(_ folder: Folder?) {
        selectedFolder = folder
        selectedNote = nil // 切换文件夹时清空笔记选择
    }
    
    /// 创建文件夹（支持离线模式）
    func createFolder(name: String) async throws {
        // 生成临时文件夹ID（离线时使用）
        let tempFolderId = UUID().uuidString
        
        // 创建本地文件夹对象
        let newFolder = Folder(
            id: tempFolderId,
            name: name,
            count: 0,
            isSystem: false,
            createdAt: Date()
        )
        
        // 先保存到本地（无论在线还是离线）
        let systemFolders = folders.filter { $0.isSystem }
        var userFolders = folders.filter { !$0.isSystem }
        userFolders.append(newFolder)
        try localStorage.saveFolders(userFolders)
        
        // 更新视图数据（系统文件夹在前）
        folders = systemFolders + userFolders
        
        // 如果离线或未认证，添加到离线队列
        if !isOnline || !service.isAuthenticated() {
            let operationData = try JSONEncoder().encode([
                "name": name
            ])
            let operation = OfflineOperation(
                type: .createFolder,
                noteId: tempFolderId, // 对于文件夹操作，使用 folderId
                data: operationData
            )
            try offlineQueue.addOperation(operation)
            print("[VIEWMODEL] 离线模式：文件夹已保存到本地，等待同步: \(tempFolderId)")
            return
        }
        
        // 在线模式：尝试上传到云端
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let response = try await service.createFolder(name: name)
            
            // 解析响应：响应格式为 {"code": 0, "data": {"entry": {...}}}
            var folderId: String?
            var folderName: String?
            var entryData: [String: Any]?
            
            // 检查响应格式
            if let code = response["code"] as? Int, code == 0 {
                if let data = response["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any] {
                    // 处理 ID（可能是 String 或 Int）
                    if let idString = entry["id"] as? String {
                        folderId = idString
                    } else if let idInt = entry["id"] as? Int {
                        folderId = String(idInt)
                    }
                    folderName = entry["subject"] as? String ?? name
                    entryData = entry
                    print("[VIEWMODEL] 从 data.entry 获取文件夹信息: id=\(folderId ?? "nil"), name=\(folderName ?? "nil")")
                }
            }
            
            if let folderId = folderId, let folderName = folderName {
                // 如果服务器返回的 ID 与本地不同，需要更新
                if tempFolderId != folderId {
                    // 创建新的文件夹对象（使用服务器返回的 ID）
                    let updatedFolder = Folder(
                        id: folderId,
                        name: folderName,
                        count: 0,
                        isSystem: false,
                        createdAt: Date()
                    )
                    
                    // 更新文件夹列表（保持系统文件夹在前）
                    let systemFolders = folders.filter { $0.isSystem }
                    var userFolders = folders.filter { !$0.isSystem }
                    
                    if let index = userFolders.firstIndex(where: { $0.id == tempFolderId }) {
                        userFolders.remove(at: index)
                        userFolders.append(updatedFolder)
                    }
                    
                    folders = systemFolders + userFolders
                    
                    // 保存到本地存储
                    try localStorage.saveFolders(userFolders)
                } else {
                    // ID 相同，更新现有文件夹
                    let updatedFolder = Folder(
                        id: folderId,
                        name: folderName,
                        count: 0,
                        isSystem: false,
                        createdAt: Date()
                    )
                    
                    // 更新文件夹列表（保持系统文件夹在前）
                    let systemFolders = folders.filter { $0.isSystem }
                    var userFolders = folders.filter { !$0.isSystem }
                    
                    if let index = userFolders.firstIndex(where: { $0.id == tempFolderId }) {
                        userFolders[index] = updatedFolder
                    }
                    
                    folders = systemFolders + userFolders
                    
                    // 保存到本地存储
                    try localStorage.saveFolders(userFolders)
                }
            } else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "创建文件夹失败：服务器返回无效响应"])
            }
        } catch {
            // 网络错误：添加到离线队列
            if let urlError = error as? URLError {
                let operationData = try JSONEncoder().encode([
                    "name": name
                ])
                let operation = OfflineOperation(
                    type: .createFolder,
                    noteId: tempFolderId,
                    data: operationData
                )
                try offlineQueue.addOperation(operation)
                print("[VIEWMODEL] 网络错误：文件夹已保存到本地，等待同步: \(tempFolderId)")
                errorMessage = "网络错误，文件夹已保存到本地，将在网络恢复后自动同步"
            } else {
                errorMessage = "创建文件夹失败: \(error.localizedDescription)"
                throw error
            }
        }
    }
    
    /// 重命名文件夹
    func renameFolder(_ folder: Folder, newName: String) async throws {
        // 先更新本地（无论在线还是离线）
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index].name = newName
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            // 确保 selectedFolder 也更新
            if selectedFolder?.id == folder.id {
                selectedFolder?.name = newName
            }
        } else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }
        
        // 如果离线或未认证，添加到离线队列
        if !isOnline || !service.isAuthenticated() {
            let operationData = try JSONEncoder().encode([
                "oldName": folder.name,
                "newName": newName
            ])
            let operation = OfflineOperation(
                type: .renameFolder,
                noteId: folder.id, // 对于文件夹操作，使用 folderId
                data: operationData
            )
            try offlineQueue.addOperation(operation)
            print("[VIEWMODEL] 离线模式：文件夹已在本地重命名，等待同步: \(folder.id)")
            return
        }
        
        // 在线模式：尝试上传到云端
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            // 获取最新的 tag 和 createDate
            var existingTag = folder.rawData?["tag"] as? String ?? ""
            var originalCreateDate = folder.rawData?["createDate"] as? Int
            
            print("[VIEWMODEL] 上传前获取最新 tag，当前 tag: \(existingTag.isEmpty ? "空" : existingTag)")
            do {
                let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
                if let data = folderDetails["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any] {
                    if let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                        existingTag = latestTag
                        print("[VIEWMODEL] 从服务器获取到最新 tag: \(existingTag)")
                    }
                    if let latestCreateDate = entry["createDate"] as? Int {
                        originalCreateDate = latestCreateDate
                        print("[VIEWMODEL] 从服务器获取到最新 createDate: \(latestCreateDate)")
                    }
                }
            } catch {
                print("[VIEWMODEL] 获取最新文件夹信息失败: \(error)，将使用本地存储的 tag")
            }
            
            if existingTag.isEmpty {
                existingTag = folder.id
                print("[VIEWMODEL] 警告：tag 仍然为空，使用 folderId 作为 fallback: \(existingTag)")
            }
            
            let response = try await service.renameFolder(
                folderId: folder.id,
                newName: newName,
                existingTag: existingTag,
                originalCreateDate: originalCreateDate
            )
            
            if let code = response["code"] as? Int, code == 0 {
                // 更新本地文件夹对象
                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    var updatedFolder = folders[index]
                    updatedFolder.name = newName
                    updatedFolder.rawData = response["data"] as? [String: Any] ?? response // 更新 rawData
                    folders[index] = updatedFolder
                    try localStorage.saveFolders(folders.filter { !$0.isSystem })
                    if selectedFolder?.id == folder.id {
                        selectedFolder = updatedFolder
                    }
                }
                print("[VIEWMODEL] 文件夹重命名成功: \(folder.id) -> \(newName)")
            } else {
                let code = response["code"] as? Int ?? -1
                let message = response["description"] as? String ?? response["message"] as? String ?? "重命名文件夹失败"
                print("[VIEWMODEL] 重命名文件夹失败，code: \(code), message: \(message)")
                throw NSError(domain: "MiNote", code: code, userInfo: [NSLocalizedDescriptionKey: message])
            }
        } catch {
            if let urlError = error as? URLError {
                let operationData = try JSONEncoder().encode([
                    "oldName": folder.name,
                    "newName": newName
                ])
                let operation = OfflineOperation(
                    type: .renameFolder,
                    noteId: folder.id,
                    data: operationData
                )
                try offlineQueue.addOperation(operation)
                print("[VIEWMODEL] 网络错误：文件夹已在本地重命名，等待同步: \(folder.id)")
                errorMessage = "网络错误，文件夹已在本地重命名，将在网络恢复后自动同步"
            } else {
                errorMessage = "重命名文件夹失败: \(error.localizedDescription)"
                throw error
            }
        }
    }
    
    /// 删除文件夹
    func deleteFolder(_ folder: Folder) async throws {
        // 1. 先在本地删除
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders.remove(at: index)
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            if selectedFolder?.id == folder.id {
                selectedFolder = nil
            }
        } else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }
        
        // 如果离线或未认证，添加到离线队列
        if !isOnline || !service.isAuthenticated() {
            let operationDict: [String: Any] = [
                "folderId": folder.id,
                "tag": folder.rawData?["tag"] as? String ?? folder.id,
                "purge": false
            ]
            let operationData = try JSONSerialization.data(withJSONObject: operationDict)
            let operation = OfflineOperation(
                type: .deleteFolder,
                noteId: folder.id,
                data: operationData
            )
            try offlineQueue.addOperation(operation)
            print("[VIEWMODEL] 离线模式：文件夹已在本地删除，等待同步: \(folder.id)")
            return
        }
        
        // 2. 尝试使用API删除云端
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            var finalTag = folder.rawData?["tag"] as? String ?? folder.id
            if finalTag.isEmpty || finalTag == folder.id {
                print("[VIEWMODEL] 文件夹 tag 为空或等于 folderId，尝试从服务器获取最新 tag")
                do {
                    let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
                    if let data = folderDetails["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any],
                       let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                        finalTag = latestTag
                        print("[VIEWMODEL] 从服务器获取到最新 tag: \(finalTag)")
                    }
                } catch {
                    print("[VIEWMODEL] 获取最新文件夹 tag 失败: \(error)，将使用 folderId")
                }
            }
            
            if finalTag.isEmpty {
                finalTag = folder.id
            }
            
            _ = try await service.deleteFolder(folderId: folder.id, tag: finalTag, purge: false)
            print("[VIEWMODEL] 云端文件夹删除成功: \(folder.id)")
        } catch {
            if let urlError = error as? URLError {
                let operationDict: [String: Any] = [
                    "folderId": folder.id,
                    "tag": folder.rawData?["tag"] as? String ?? folder.id,
                    "purge": false
                ]
                let operationData = try JSONSerialization.data(withJSONObject: operationDict)
                let operation = OfflineOperation(
                    type: .deleteFolder,
                    noteId: folder.id,
                    data: operationData
                )
                try offlineQueue.addOperation(operation)
                print("[VIEWMODEL] 网络错误：文件夹已在本地删除，等待同步: \(folder.id)")
                errorMessage = "网络错误，文件夹已在本地删除，将在网络恢复后自动同步"
            } else {
                errorMessage = "删除文件夹失败: \(error.localizedDescription)"
                throw error
            }
        }
    }
    
    // MARK: - 便捷方法
    
    /// 创建新笔记的便捷方法（用于快速创建空笔记）
    func createNewNote() {
        // 创建一个默认笔记，使用标准的 XML 格式
        let newNote = Note(
            id: UUID().uuidString,
            title: "新笔记",
            content: "<new-format/><text indent=\"1\"></text>",
            folderId: selectedFolder?.id ?? "0",
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        notes.append(newNote)
        selectedNote = newNote
        
        // 更新文件夹计数
        if let index = folders.firstIndex(where: { $0.id == newNote.folderId }) {
            folders[index].count += 1
        }
    }
    
    // MARK: - Cookie过期处理
    
    private func setupCookieExpiredHandler() {
        service.onCookieExpired = { [weak self] in
            DispatchQueue.main.async {
                self?.errorMessage = "Cookie已过期，请重新登录或刷新Cookie"
                self?.showLoginView = true
            }
        }
    }
    
    // MARK: - 图片上传
    
    /// 上传图片并插入到当前笔记
    /// - Parameter imageURL: 图片文件URL
    func uploadImageAndInsertToNote(imageURL: URL) async throws {
        guard let note = selectedNote else {
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "请先选择笔记"])
        }
        
        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
        }
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            // 读取图片数据
            let imageData = try Data(contentsOf: imageURL)
            let fileName = imageURL.lastPathComponent
            
            // 根据文件扩展名推断 MIME 类型
            let fileExtension = (imageURL.pathExtension as NSString).lowercased
            let mimeType: String
            switch fileExtension {
            case "jpg", "jpeg":
                mimeType = "image/jpeg"
            case "png":
                mimeType = "image/png"
            case "gif":
                mimeType = "image/gif"
            case "webp":
                mimeType = "image/webp"
            default:
                mimeType = "image/jpeg"
            }
            
            // 上传图片
            let uploadResult = try await service.uploadImage(
                imageData: imageData,
                fileName: fileName,
                mimeType: mimeType
            )
            
            guard let fileId = uploadResult["fileId"] as? String,
                  let digest = uploadResult["digest"] as? String else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "上传图片失败：服务器返回无效响应"])
            }
            
            print("[VIEWMODEL] 图片上传成功: fileId=\(fileId), digest=\(digest)")
            
            // 保存图片到本地
            let fileType = String(mimeType.dropFirst("image/".count))
            try localStorage.saveImage(imageData: imageData, fileId: fileId, fileType: fileType)
            
            // 更新笔记的 setting.data，添加图片信息
            var updatedNote = note
            var rawData = updatedNote.rawData ?? [:]
            var setting = rawData["setting"] as? [String: Any] ?? [
                "themeId": 0,
                "stickyTime": 0,
                "version": 0
            ]
            
            var settingData = setting["data"] as? [[String: Any]] ?? []
            let imageInfo: [String: Any] = [
                "fileId": fileId,
                "mimeType": mimeType,
                "digest": digest
            ]
            settingData.append(imageInfo)
            setting["data"] = settingData
            rawData["setting"] = setting
            updatedNote.rawData = rawData
            
            // 在笔记内容中添加图片引用（☺格式）
            let imageReference = "☺ \(fileId)<0/><>"
            var newContent = updatedNote.content
            if newContent.isEmpty {
                newContent = "<new-format/><text indent=\"1\">\(imageReference)</text>"
            } else {
                // 在内容末尾添加图片引用
                let cleanedContent = newContent.replacingOccurrences(of: "<new-format/>", with: "")
                newContent = "<new-format/>\(cleanedContent)\n<text indent=\"1\">\(imageReference)</text>"
            }
            updatedNote.content = newContent
            
            // 更新笔记（需要传递 rawData 以包含 setting.data）
            // 注意：updateNote 方法会从 rawData 中提取 setting.data
            try await updateNote(updatedNote)
            
            // 更新本地笔记对象（从服务器响应中获取最新数据）
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                // 重新加载笔记以获取服务器返回的最新数据
                if let updated = try? localStorage.loadNote(noteId: note.id) {
                    notes[index] = updated
                    selectedNote = updated
                } else {
                    // 如果无法加载，至少更新本地对象
                    notes[index] = updatedNote
                    selectedNote = updatedNote
                }
            }
            
            print("[VIEWMODEL] 图片已插入到笔记: \(note.id)")
            
        } catch {
            errorMessage = "上传图片失败: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - Error Handling
    
    private func handleMiNoteError(_ error: MiNoteError) {
        switch error {
        case .cookieExpired:
            errorMessage = "Cookie已过期，请重新登录或刷新Cookie"
            showLoginView = true
        case .notAuthenticated:
            errorMessage = "未登录，请先登录小米账号"
            showLoginView = true
        case .networkError(let underlyingError):
            errorMessage = "网络错误: \(underlyingError.localizedDescription)"
        case .invalidResponse:
            errorMessage = "服务器返回无效响应"
        }
    }
}
