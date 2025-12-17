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
    @Published var syncResult: SyncResult?
    
    private let service = MiNoteService.shared
    private let syncService = SyncService.shared
    private let localStorage = LocalStorageService.shared
    
    var filteredNotes: [Note] {
        if searchText.isEmpty {
            if let folder = selectedFolder {
                if folder.id == "starred" {
                    return notes.filter { $0.isStarred }
                } else if folder.id == "0" {
                    return notes
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
    
    func loadNotesFromCloud() async {
        guard service.isAuthenticated() else {
            errorMessage = "请先登录小米账号"
            return
        }
        
        // 在加载笔记前，先重试删除失败的笔记
        do {
            try await syncService.retryPendingDeletions()
        } catch {
            print("[VIEWMODEL] 重试删除失败: \(error)")
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await service.fetchPage()
            let newNotes = service.parseNotes(from: response)
            let newFolders = service.parseFolders(from: response)
            
            // 更新数据
            self.notes = newNotes
            self.folders = newFolders
            
            // 保存文件夹到本地存储
            do {
                try localStorage.saveFolders(newFolders)
            } catch {
                print("保存文件夹失败: \(error)")
            }
            
            // 如果没有选择文件夹，选择第一个
            if selectedFolder == nil {
                selectedFolder = folders.first
            }
            
        } catch let error as MiNoteError {
            handleMiNoteError(error)
        } catch {
            errorMessage = "加载笔记失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - 统一的笔记创建/更新接口（推荐使用）
    
    /// 创建笔记（统一接口，使用 Note 对象）
    func createNote(_ note: Note) async throws {
        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
        }
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let response = try await service.createNote(
                title: note.title,
                content: note.content,
                folderId: note.folderId
            )
            
            if let noteId = response["id"] as? String,
               let _ = response["tag"] as? String {
                // 创建本地笔记对象
                let newNote = Note(
                    id: noteId,
                    title: note.title,
                    content: note.content,
                    folderId: note.folderId,
                    isStarred: note.isStarred,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    tags: note.tags,
                    rawData: response
                )
                
                // 保存到本地存储
                try localStorage.saveNote(newNote)
                
                // 更新视图数据
                notes.append(newNote)
                selectedNote = newNote
                
                // 更新文件夹计数
                updateFolderCounts()
            } else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "创建笔记失败：服务器返回无效响应"])
            }
        } catch {
            errorMessage = "创建笔记失败: \(error.localizedDescription)"
            throw error
        }
    }
    
    /// 更新笔记（统一接口，使用 Note 对象）
    func updateNote(_ note: Note) async throws {
        guard service.isAuthenticated() else {
            throw NSError(domain: "MiNote", code: 401, userInfo: [NSLocalizedDescriptionKey: "请先登录小米账号"])
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
            
            let response = try await service.updateNote(
                noteId: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId,
                existingTag: existingTag,
                originalCreateDate: originalCreateDate
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
            errorMessage = "更新笔记失败: \(error.localizedDescription)"
            throw error
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
