import Foundation
import SwiftUI
import Combine

/// 笔记视图模型
/// 
/// 负责管理应用的主要业务逻辑和状态，包括：
/// - 笔记和文件夹的数据管理
/// - 同步操作（完整同步、增量同步）
/// - 离线操作队列处理
/// - 网络状态监控
/// - Cookie过期处理
/// 
/// **线程安全**：使用@MainActor确保所有UI更新在主线程执行
@MainActor
public class NotesViewModel: ObservableObject {
    // MARK: - 数据状态
    
    /// 笔记列表
    @Published public var notes: [Note] = []
    
    /// 文件夹列表
    @Published public var folders: [Folder] = []
    
    /// 当前选中的笔记
    @Published public var selectedNote: Note?
    
    /// 当前选中的文件夹
    @Published public var selectedFolder: Folder?
    
    // MARK: - UI状态
    
    /// 是否正在加载
    @Published var isLoading = false
    
    /// 错误消息（用于显示错误提示）
    @Published var errorMessage: String?
    
    /// 搜索文本
    @Published var searchText = ""
    
    /// 是否显示登录视图
    @Published var showLoginView: Bool = false
    
    /// 是否显示Cookie刷新视图
    @Published var showCookieRefreshView: Bool = false
    
    // MARK: - 设置
    
    /// 同步间隔（秒），默认5分钟
    @Published var syncInterval: Double = 300
    
    /// 是否自动保存
    @Published var autoSave: Bool = true
    
    // MARK: - 同步状态
    
    /// 是否正在同步
    @Published var isSyncing = false
    
    /// 同步进度（0.0 - 1.0）
    @Published var syncProgress: Double = 0
    
    /// 同步状态消息
    @Published var syncStatusMessage: String = ""
    
    /// 上次同步时间
    @Published var lastSyncTime: Date?
    
    /// 同步结果
    @Published var syncResult: SyncService.SyncResult?
    
    // MARK: - 网络状态（从 AuthenticationStateManager 同步）
    
    /// 是否在线（需要同时满足网络连接和Cookie有效）
    @Published var isOnline: Bool = true
    
    /// Cookie是否失效
    @Published var isCookieExpired: Bool = false
    
    /// 是否已显示Cookie失效提示（避免重复提示）
    @Published var cookieExpiredShown: Bool = false
    
    /// 是否显示Cookie失效弹窗
    @Published var showCookieExpiredAlert: Bool = false
    
    /// 是否保持离线模式（用户点击"取消"后设置为true，阻止后续请求）
    @Published var shouldStayOffline: Bool = false
    
    // MARK: - 依赖服务
    
    /// 小米笔记API服务
    private let service = MiNoteService.shared
    
    /// 同步服务
    private let syncService = SyncService.shared
    
    /// 本地存储服务
    private let localStorage = LocalStorageService.shared
    
    /// 认证状态管理器（统一管理登录、Cookie刷新和在线状态）
    private let authStateManager = AuthenticationStateManager()
    
    /// 网络监控服务
    private let networkMonitor = NetworkMonitor.shared
    
    /// 离线操作队列
    private let offlineQueue = OfflineOperationQueue.shared
    
    /// Combine订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 计算属性
    
    /// 过滤后的笔记列表
    /// 
    /// 根据搜索文本和选中的文件夹过滤笔记
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
    
    /// 未分类文件夹（虚拟文件夹）
    /// 
    /// 显示folderId为"0"或空的笔记，用于组织未分类的笔记
    var uncategorizedFolder: Folder {
        let uncategorizedCount = notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }.count
        return Folder(id: "uncategorized", name: "未分类", count: uncategorizedCount, isSystem: false)
    }
    
    /// 是否已登录（是否有有效的Cookie）
    var isLoggedIn: Bool {
        return service.isAuthenticated()
    }
    
    // MARK: - 初始化
    
    /// 初始化视图模型
    /// 
    /// 执行以下初始化操作：
    /// 1. 加载本地数据
    /// 2. 加载设置
    /// 3. 加载同步状态
    /// 4. 恢复上次选中的笔记
    /// 5. 设置Cookie过期处理器
    /// 6. 监听网络状态
    public init() {
        // 加载本地数据
        loadLocalData()
        
        // 加载设置
        loadSettings()
        
        // 加载同步状态
        loadSyncStatus()
        
        // 恢复上次选中的笔记
        restoreLastSelectedNote()
        
        // 同步 AuthenticationStateManager 的状态到 ViewModel
        // 这样 AuthenticationStateManager 的状态变化会触发 ViewModel 的 @Published 属性更新，进而触发 UI 更新
        setupAuthStateSync()
        
        // 监听selectedNote变化，保存到UserDefaults
        $selectedNote
            .sink { [weak self] note in
                self?.saveLastSelectedNote(note)
            }
            .store(in: &cancellables)
        
        // 监听网络恢复通知
        NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleNetworkRestored()
        }
    }
    
    /// 同步 AuthenticationStateManager 的状态到 ViewModel
    /// 
    /// 通过 Combine 将 AuthenticationStateManager 的 @Published 属性同步到 ViewModel 的 @Published 属性
    /// 这样 AuthenticationStateManager 的状态变化会自动触发 ViewModel 的状态更新，进而触发 UI 更新
    private func setupAuthStateSync() {
        // 同步 isOnline
        authStateManager.$isOnline
            .assign(to: &$isOnline)
        
        // 同步 isCookieExpired
        authStateManager.$isCookieExpired
            .assign(to: &$isCookieExpired)
        
        // 同步 cookieExpiredShown
        authStateManager.$cookieExpiredShown
            .assign(to: &$cookieExpiredShown)
        
        // 同步 showCookieExpiredAlert
        authStateManager.$showCookieExpiredAlert
            .assign(to: &$showCookieExpiredAlert)
        
        // 同步 shouldStayOffline
        authStateManager.$shouldStayOffline
            .assign(to: &$shouldStayOffline)
        
        // 同步 showLoginView
        authStateManager.$showLoginView
            .assign(to: &$showLoginView)
        
        // 同步 showCookieRefreshView
        authStateManager.$showCookieRefreshView
            .assign(to: &$showCookieRefreshView)
    }
    
    @MainActor
    private func handleNetworkRestored() {
        print("[VIEWMODEL] 网络已恢复，开始处理待同步操作")
        Task {
            await processPendingOperations()
        }
    }
    
    // MARK: - 离线操作辅助方法
    
    /// 从 API 响应中提取 tag 值
    /// 
    /// 优先从 response["data"]["tag"] 获取，其次从 response["entry"]["tag"] 获取
    /// - Parameter response: API 响应字典
    /// - Parameter fallbackTag: 如果响应中没有 tag，使用的默认值
    /// - Returns: 提取到的 tag 值，如果都没有则返回 fallbackTag
    private func extractTag(from response: [String: Any], fallbackTag: String) -> String {
        var tagValue: String? = nil
        
        // 优先从 data.entry.tag 获取
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any] {
            tagValue = entry["tag"] as? String
        }
        
        // 其次从根级别的 entry.tag 获取
        if tagValue == nil, let entry = response["entry"] as? [String: Any] {
            tagValue = entry["tag"] as? String
        }
        
        // 最后从 data.tag 获取
        if tagValue == nil, let data = response["data"] as? [String: Any] {
            tagValue = data["tag"] as? String
        }
        
        return tagValue ?? fallbackTag
    }
    
    /// 从 API 响应中提取 entry 数据
    /// 
    /// 优先从 response["data"]["entry"] 获取，其次从 response["entry"] 获取
    /// - Parameter response: API 响应字典
    /// - Returns: entry 字典，如果不存在则返回 nil
    private func extractEntry(from response: [String: Any]) -> [String: Any]? {
        // 优先从 data.entry 获取
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any] {
            return entry
        }
        
        // 其次从根级别的 entry 获取
        if let entry = response["entry"] as? [String: Any] {
            return entry
        }
        
        return nil
    }
    
    /// 检查 API 响应是否成功
    /// 
    /// - Parameter response: API 响应字典
    /// - Returns: 如果成功返回 true，否则返回 false
    private func isResponseSuccess(_ response: [String: Any]) -> Bool {
        if let code = response["code"] as? Int {
            return code == 0
        }
        // 如果没有 code 字段，检查 result 字段
        if let result = response["result"] as? String {
            return result == "ok"
        }
        return false
    }
    
    /// 从 API 响应中提取错误信息
    /// 
    /// - Parameter response: API 响应字典
    /// - Returns: 错误消息，如果无法提取则返回默认消息
    private func extractErrorMessage(from response: [String: Any], defaultMessage: String = "操作失败") -> String {
        return response["description"] as? String 
            ?? response["message"] as? String 
            ?? defaultMessage
    }
    
    /// 统一处理离线操作的错误
    /// 
    /// - Parameters:
    ///   - operation: 离线操作
    ///   - error: 发生的错误
    ///   - context: 操作上下文描述（用于日志）
    private func handleOfflineOperationError(_ operation: OfflineOperation, error: Error, context: String) {
        print("[VIEWMODEL] ❌ \(context)失败: \(operation.type.rawValue), noteId: \(operation.noteId)")
        print("[VIEWMODEL] 错误详情: \(error)")
        print("[VIEWMODEL] 错误堆栈: \(error.localizedDescription)")
        // 操作失败时保留在队列中，下次再试
    }
    
    // MARK: - 统一的离线队列管理
    
    /// 统一处理错误并将操作添加到离线队列
    /// 
    /// 此方法处理以下情况：
    /// - 401 Cookie过期：设置离线状态，添加到队列
    /// - 网络错误：添加到队列
    /// - 其他错误：根据错误类型决定是否添加到队列
    /// 
    /// - Parameters:
    ///   - error: 发生的错误
    ///   - operationType: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - operationData: 操作数据（需要JSON编码）
    ///   - context: 操作上下文（用于日志）
    /// - Returns: 是否成功添加到离线队列
    @MainActor
    private func handleErrorAndAddToOfflineQueue(
        error: Error,
        operationType: OfflineOperationType,
        noteId: String,
        operationData: [String: Any],
        context: String
    ) -> Bool {
        print("[OfflineQueue] 统一处理错误并添加到离线队列: \(operationType.rawValue), noteId: \(noteId), context: \(context)")
        
        // 处理401 Cookie过期错误
        if case MiNoteError.cookieExpired = error {
            print("[OfflineQueue] 检测到Cookie过期错误，设置为离线状态")
            setOfflineStatus(reason: "Cookie过期")
            
            // 添加到离线队列
            if addOperationToOfflineQueue(type: operationType, noteId: noteId, data: operationData) {
                print("[OfflineQueue] ✅ Cookie过期：操作已添加到离线队列: \(operationType.rawValue)")
                return true
            } else {
                print("[OfflineQueue] ❌ Cookie过期：添加到离线队列失败")
                return false
            }
        }
        
        // 处理网络错误
        if let urlError = error as? URLError {
            print("[OfflineQueue] 检测到网络错误: \(urlError.localizedDescription)")
            
            // 添加到离线队列
            if addOperationToOfflineQueue(type: operationType, noteId: noteId, data: operationData) {
                print("[OfflineQueue] ✅ 网络错误：操作已添加到离线队列: \(operationType.rawValue)")
                return true
            } else {
                print("[OfflineQueue] ❌ 网络错误：添加到离线队列失败")
                return false
            }
        }
        
        // 其他错误：不添加到队列
        print("[OfflineQueue] ⚠️ 其他错误，不添加到离线队列: \(error.localizedDescription)")
        return false
    }
    
    /// 将操作添加到离线队列（内部方法，统一编码逻辑）
    /// 
    /// - Parameters:
    ///   - type: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - data: 操作数据字典
    /// - Returns: 是否成功添加
    @MainActor
    private func addOperationToOfflineQueue(
        type: OfflineOperationType,
        noteId: String,
        data: [String: Any]
    ) -> Bool {
        do {
            // 使用 JSONSerialization 编码 [String: Any] 字典
            let operationData = try JSONSerialization.data(withJSONObject: data, options: [])
            let operation = OfflineOperation(
                type: type,
                noteId: noteId,
                data: operationData
            )
            try offlineQueue.addOperation(operation)
            return true
        } catch {
            print("[OfflineQueue] ❌ 编码操作数据失败: \(error)")
            return false
        }
    }
    
    /// 设置离线状态
    /// 
    /// - Parameter reason: 离线原因（用于日志）
    @MainActor
    private func setOfflineStatus(reason: String) {
        print("[OfflineStatus] 设置为离线状态，原因: \(reason)")
        isOnline = false
        isCookieExpired = true
        
        // 仅在首次设置为离线时显示提示
        if !cookieExpiredShown {
            cookieExpiredShown = true
            errorMessage = "已切换到离线模式。操作将保存到离线队列，请重新登录后同步。"
            
            // 3秒后清除错误消息
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.errorMessage = nil
            }
        }
    }
    
    /// 恢复在线状态
    /// 
    /// 当Cookie恢复有效时调用此方法
    @MainActor
    private func restoreOnlineStatus() {
        guard service.hasValidCookie() else {
            print("[OfflineStatus] Cookie仍然无效，不能恢复在线状态")
            return
        }
        
        print("[OfflineStatus] 恢复在线状态")
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false  // 清除离线模式标志
        showCookieExpiredAlert = false  // 清除弹窗状态
        
        // 重新计算在线状态（需要网络和Cookie都有效）
        let networkOnline = networkMonitor.isOnline
        isOnline = networkOnline && service.hasValidCookie()
        
        if isOnline {
            print("[OfflineStatus] ✅ 已恢复在线状态，开始处理待同步操作")
            // 触发离线队列处理
            Task {
                await processPendingOperations()
            }
        } else {
            print("[OfflineStatus] ⚠️ Cookie已恢复，但网络未连接，仍保持离线状态")
        }
    }
    
    /// 处理待同步的离线操作
    /// 
    /// 当网络恢复时，处理离线操作队列中的操作：
    /// - 创建笔记：上传到云端
    /// - 更新笔记：同步到云端
    /// - 删除笔记：从云端删除
    /// - 文件夹操作：同步到云端
    /// 
    /// **注意**：操作失败时会保留在队列中，下次网络恢复时重试
    @MainActor
    private func processPendingOperations() async {
        // 确保在线且已认证
        guard isOnline && service.isAuthenticated() else {
            print("[VIEWMODEL] 网络未恢复或未认证，跳过处理离线操作")
            return
        }
        
        let operations = offlineQueue.getPendingOperations()
        guard !operations.isEmpty else {
            print("[VIEWMODEL] 没有待处理的离线操作")
            return
        }
        
        print("[VIEWMODEL] 开始处理 \(operations.count) 个待同步操作")
        
        for operation in operations {
            do {
                print("[VIEWMODEL] 处理离线操作: \(operation.type.rawValue), noteId: \(operation.noteId)")
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
                print("[VIEWMODEL] ✅ 成功处理离线操作: \(operation.type.rawValue), noteId: \(operation.noteId)")
            } catch {
                handleOfflineOperationError(operation, error: error, context: "处理离线操作")
            }
        }
        
        print("[VIEWMODEL] 离线操作处理完成")
    }
    
    @MainActor
    private func processCreateNoteOperation(_ operation: OfflineOperation) async throws {
        print("[VIEWMODEL] processCreateNoteOperation: 开始处理，noteId=\(operation.noteId)")
        
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            print("[VIEWMODEL] processCreateNoteOperation: ❌ 笔记不存在，noteId=\(operation.noteId)")
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "笔记不存在"])
        }
        
        print("[VIEWMODEL] processCreateNoteOperation: 找到笔记，title=\(note.title), folderId=\(note.folderId)")
        
        // 创建笔记到云端
        print("[VIEWMODEL] processCreateNoteOperation: 调用 API 创建笔记到云端...")
        let response = try await service.createNote(
            title: note.title,
            content: note.content,
            folderId: note.folderId
        )
        print("[VIEWMODEL] processCreateNoteOperation: API 调用成功，响应: \(response)")
        
        // 解析响应并更新本地笔记
        guard isResponseSuccess(response),
              let entry = extractEntry(from: response),
              let serverNoteId = entry["id"] as? String else {
            let message = extractErrorMessage(from: response, defaultMessage: "服务器响应格式不正确")
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        let tag = extractTag(from: response, fallbackTag: entry["tag"] as? String ?? serverNoteId)
        
        // 获取服务器返回的 folderId（如果有）
        let serverFolderId: String
        if let folderIdValue = entry["folderId"] {
            if let folderIdInt = folderIdValue as? Int {
                serverFolderId = String(folderIdInt)
            } else if let folderIdStr = folderIdValue as? String {
                serverFolderId = folderIdStr
            } else {
                serverFolderId = note.folderId
            }
        } else {
            serverFolderId = note.folderId
        }
        
        // 如果服务器返回的 ID 与本地不同，需要创建新笔记并删除旧的
        if note.id != serverNoteId {
                // 检查新ID的笔记是否已存在（可能由增量同步创建）
                if let existingNote = try? localStorage.loadNote(noteId: serverNoteId) {
                    // 新ID的笔记已存在，合并内容（保留较新的版本）
                    print("[VIEWMODEL] processCreateNoteOperation: ⚠️ 新ID的笔记已存在，合并内容: \(serverNoteId)")
                    
                    // 比较时间戳，保留较新的版本
                    let shouldUseLocal = note.updatedAt > existingNote.updatedAt
                    let finalNote: Note
                    
                    if shouldUseLocal {
                        // 本地版本较新，使用本地内容但保留服务器返回的ID和rawData
                        var updatedRawData = note.rawData ?? [:]
                        for (key, value) in entry {
                            updatedRawData[key] = value
                        }
                        updatedRawData["tag"] = tag
                        
                        finalNote = Note(
                            id: serverNoteId,
                            title: note.title,
                            content: note.content,
                            folderId: serverFolderId,
                            isStarred: note.isStarred,
                            createdAt: note.createdAt,
                            updatedAt: note.updatedAt,
                            tags: note.tags,
                            rawData: updatedRawData
                        )
                    } else {
                        // 已存在的版本较新，保留它
                        finalNote = existingNote
                    }
                    
                    // 删除旧的本地笔记
                    try? localStorage.deleteNote(noteId: note.id)
                    
                    // 更新笔记列表（在主线程）
                    await MainActor.run {
                        // 移除旧笔记
                        if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                            self.notes.remove(at: index)
                        }
                        // 添加或更新新笔记
                        if let index = self.notes.firstIndex(where: { $0.id == serverNoteId }) {
                            self.notes[index] = finalNote
                        } else {
                            self.notes.append(finalNote)
                        }
                        // 如果当前选中的是旧笔记，更新为新笔记
                        if self.selectedNote?.id == note.id {
                            self.selectedNote = finalNote
                        }
                        // 更新文件夹计数
                        self.updateFolderCounts()
                    }
                    
                    // 保存最终笔记
                    try localStorage.saveNote(finalNote)
                    print("[VIEWMODEL] processCreateNoteOperation: ✅ 成功合并笔记 ID: \(note.id) -> \(serverNoteId)")
                } else {
                    // 新ID的笔记不存在，正常创建
                    // 构建更新后的 rawData
                    var updatedRawData = note.rawData ?? [:]
                    for (key, value) in entry {
                        updatedRawData[key] = value
                    }
                    updatedRawData["tag"] = tag
                    
                    // 创建新的笔记对象（使用服务器返回的 ID 和 folderId）
                    let updatedNote = Note(
                        id: serverNoteId,
                        title: note.title,
                        content: note.content,
                        folderId: serverFolderId, // 使用服务器返回的 folderId
                        isStarred: note.isStarred,
                        createdAt: note.createdAt,
                        updatedAt: note.updatedAt,
                        tags: note.tags,
                        rawData: updatedRawData
                    )
                    
                    // 先保存新笔记，再删除旧笔记（防止竞态条件）
                    try localStorage.saveNote(updatedNote)
                    
                    // 删除旧的本地文件
                    try? localStorage.deleteNote(noteId: note.id)
                    
                    // 更新笔记列表（在主线程）
                    await MainActor.run {
                        if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                            self.notes.remove(at: index)
                            self.notes.append(updatedNote)
                        }
                        // 如果当前选中的是旧笔记，更新为新笔记
                        if self.selectedNote?.id == note.id {
                            self.selectedNote = updatedNote
                        }
                        // 更新文件夹计数
                        self.updateFolderCounts()
                    }
                    
                    print("[VIEWMODEL] processCreateNoteOperation: ✅ 成功更新笔记 ID: \(note.id) -> \(serverNoteId)")
                }
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
                    folderId: serverFolderId, // 使用服务器返回的 folderId
                    isStarred: note.isStarred,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    tags: note.tags,
                    rawData: updatedRawData
                )
                
                // 更新笔记列表（在主线程）
                await MainActor.run {
                    if let index = self.notes.firstIndex(where: { $0.id == note.id }) {
                        self.notes[index] = updatedNote
                    }
                    // 如果当前选中的是这个笔记，更新它
                    if self.selectedNote?.id == note.id {
                        self.selectedNote = updatedNote
                    }
                    // 更新文件夹计数
                    self.updateFolderCounts()
                }
                
                // 保存更新后的笔记
                try localStorage.saveNote(updatedNote)
                print("[VIEWMODEL] processCreateNoteOperation: ✅ 成功更新笔记: \(note.id)")
            }
        // 响应已在 guard 语句中验证，这里不需要 else 分支
        
        print("[VIEWMODEL] processCreateNoteOperation: ✅ 离线创建的笔记已同步到云端: \(note.id)")
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
        guard isResponseSuccess(response),
              let entry = extractEntry(from: response) else {
            let message = extractErrorMessage(from: response, defaultMessage: "服务器返回无效的文件夹信息")
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
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
            let oldFolderId = operation.noteId
            
            // 1. 更新所有使用旧文件夹ID的笔记，将它们的 folder_id 更新为新ID
            try DatabaseService.shared.updateNotesFolderId(oldFolderId: oldFolderId, newFolderId: folderId)
            
            // 2. 更新内存中的笔记列表
            for i in 0..<notes.count {
                if notes[i].folderId == oldFolderId {
                    notes[i].folderId = folderId
                }
            }
            
            // 3. 删除数据库中的旧文件夹记录
            try DatabaseService.shared.deleteFolder(folderId: oldFolderId)
            
            // 4. 更新文件夹列表
            if let index = folders.firstIndex(where: { $0.id == oldFolderId }) {
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
                
                print("[VIEWMODEL] ✅ 文件夹ID已更新: \(oldFolderId) -> \(folderId), 并删除了旧文件夹记录")
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
        
        print("[VIEWMODEL] 离线创建的文件夹已同步到云端: \(operation.noteId)")
    }
    
    private func processRenameFolderOperation(_ operation: OfflineOperation) async throws {
        print("[FolderRename] ========== processRenameFolderOperation() 开始 ==========")
        print("[FolderRename] 操作 ID: \(operation.id)")
        print("[FolderRename] 文件夹 ID: \(operation.noteId)")
        
        // 从操作数据中解析文件夹信息
        guard let operationData = try? JSONDecoder().decode([String: String].self, from: operation.data),
              let oldName = operationData["oldName"],
              let newName = operationData["newName"] else {
            print("[FolderRename] ❌ 错误：无效的文件夹重命名操作数据")
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的文件夹重命名操作数据"])
        }
        
        print("[FolderRename] 旧名称: '\(oldName)' -> 新名称: '\(newName)'")
        
        // 获取本地文件夹对象
        guard var folder = folders.first(where: { $0.id == operation.noteId }) else {
            print("[FolderRename] ❌ 错误：文件夹不存在，folderId: \(operation.noteId)")
            print("[FolderRename] 当前 folders 数组: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }
        
        print("[FolderRename] ✅ 找到文件夹: id=\(folder.id), name='\(folder.name)'")
        
        // 获取最新的 tag 和 createDate
        var existingTag = folder.rawData?["tag"] as? String ?? ""
        var originalCreateDate = folder.rawData?["createDate"] as? Int
        
        print("[FolderRename] 当前 tag: \(existingTag.isEmpty ? "空" : existingTag)")
        
        do {
            let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
            if let data = folderDetails["data"] as? [String: Any],
               let entry = data["entry"] as? [String: Any] {
                if let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                    existingTag = latestTag
                    print("[FolderRename] 从服务器获取到最新 tag: \(existingTag)")
                }
                if let latestCreateDate = entry["createDate"] as? Int {
                    originalCreateDate = latestCreateDate
                    print("[FolderRename] 从服务器获取到最新 createDate: \(latestCreateDate)")
                }
            }
        } catch {
            print("[FolderRename] ⚠️ 获取最新文件夹信息失败: \(error)，将使用本地存储的 tag")
        }
        
        if existingTag.isEmpty {
            existingTag = folder.id
            print("[FolderRename] 警告：tag 仍然为空，使用 folderId 作为 fallback: \(existingTag)")
        }
        
        // 重命名文件夹到云端
        print("[FolderRename] 调用云端 API 重命名文件夹...")
        let response = try await service.renameFolder(
            folderId: folder.id,
            newName: newName,
            existingTag: existingTag,
            originalCreateDate: originalCreateDate
        )
        
        if let code = response["code"] as? Int, code == 0 {
            print("[FolderRename] ✅ 云端重命名成功，更新本地数据")
            print("[FolderRename] 当前 folders 数组数量: \(folders.count)")
            print("[FolderRename] 当前 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            
            // 更新本地文件夹对象
            guard let index = folders.firstIndex(where: { $0.id == folder.id }) else {
                print("[FolderRename] ❌ 错误：在 folders 数组中未找到文件夹")
                throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
            }
            
            print("[FolderRename] ✅ 找到文件夹，索引: \(index)")
            print("[FolderRename] 更新前的文件夹: id=\(folders[index].id), name='\(folders[index].name)'")
            
            var updatedFolder = folders[index]
            updatedFolder.name = newName
            
            // 更新 rawData（使用统一的提取方法）
            var updatedRawData = updatedFolder.rawData ?? [:]
            if let entry = extractEntry(from: response) {
                for (key, value) in entry {
                    updatedRawData[key] = value
                }
            }
            updatedRawData["subject"] = newName
            // 从响应中获取 tag（使用统一的提取方法）
            let tagValue = extractTag(from: response, fallbackTag: updatedRawData["tag"] as? String ?? existingTag)
            updatedRawData["tag"] = tagValue
            updatedFolder.rawData = updatedRawData
            
            print("[FolderRename] 更新后的文件夹对象: id=\(updatedFolder.id), name='\(updatedFolder.name)', tag='\(tagValue)'")
            
            // 重新创建数组以确保 SwiftUI 检测到变化
            var updatedFolders = folders
            print("[FolderRename] 更新前 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
            updatedFolders[index] = updatedFolder
            folders = updatedFolders
            print("[FolderRename] 更新后 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
            print("[FolderRename] 更新后 folders 数组数量: \(folders.count)")
            print("[FolderRename] 更新后 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            
            // 强制触发 UI 更新
            print("[FolderRename] 调用 objectWillChange.send() 触发 UI 更新")
            objectWillChange.send()
            
            // 更新选中的文件夹（如果当前选中的是这个文件夹）
            if selectedFolder?.id == folder.id {
                print("[FolderRename] 更新 selectedFolder: '\(selectedFolder?.name ?? "nil")' -> '\(newName)'")
                selectedFolder = updatedFolder
                print("[FolderRename] ✅ selectedFolder 已更新: '\(selectedFolder?.name ?? "nil")'")
            } else {
                print("[FolderRename] selectedFolder 不是当前文件夹，无需更新")
            }
            
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            print("[FolderRename] ✅ 已保存到本地存储")
            
            print("[FolderRename] ✅ 离线重命名的文件夹已同步到云端: \(folder.id) -> \(newName)")
            print("[FolderRename] ========== processRenameFolderOperation() 完成 ==========")
        } else {
            let message = extractErrorMessage(from: response, defaultMessage: "同步重命名文件夹失败")
            let code = response["code"] as? Int ?? -1
            print("[FolderRename] ❌ 云端重命名失败，code: \(code), message: \(message)")
            throw NSError(domain: "MiNote", code: code, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    
    private func processDeleteFolderOperation(_ operation: OfflineOperation) async throws {
        // 从操作数据中解析文件夹信息（离线队列中只保存了 folderID）
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let folderId = operationData["folderId"] as? String else {
            throw NSError(domain: "MiNote", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的文件夹删除操作数据"])
        }
        
        let purge = operationData["purge"] as? Bool ?? false
        
        // 通过 folderID 查询服务器获取 tag
        var finalTag: String? = nil
        
        print("[VIEWMODEL] 处理离线删除文件夹操作，通过 folderID 查询 tag: \(folderId)")
        do {
            let folderDetails = try await service.fetchFolderDetails(folderId: folderId)
            if let data = folderDetails["data"] as? [String: Any],
               let entry = data["entry"] as? [String: Any],
               let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                finalTag = latestTag
                print("[VIEWMODEL] ✅ 从服务器获取到最新 tag: \(finalTag!)")
            } else {
                // 尝试从 data.tag 获取（如果 entry.tag 不存在）
                if let data = folderDetails["data"] as? [String: Any],
                   let dataTag = data["tag"] as? String, !dataTag.isEmpty {
                    finalTag = dataTag
                    print("[VIEWMODEL] ✅ 从 data.tag 获取到 tag: \(finalTag!)")
                } else {
                    print("[VIEWMODEL] ⚠️ 服务器响应中没有 tag 字段")
                }
            }
        } catch {
            print("[VIEWMODEL] ❌ 获取文件夹 tag 失败: \(error)")
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法获取文件夹 tag，删除失败: \(error.localizedDescription)"])
        }
        
        // 确保获取到了 tag
        guard let tag = finalTag, !tag.isEmpty else {
            print("[VIEWMODEL] ❌ 无法从服务器获取有效的 tag，无法删除文件夹")
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法从服务器获取文件夹 tag，删除失败"])
        }
        
        // 使用获取到的 tag 删除文件夹到云端
        _ = try await service.deleteFolder(folderId: folderId, tag: tag, purge: purge)
        print("[VIEWMODEL] ✅ 离线删除的文件夹已同步到云端: \(folderId), tag: \(tag)")
        
        // 云端删除成功后，删除本地数据
        // 删除文件夹的图片目录
        do {
            try LocalStorageService.shared.deleteFolderImageDirectory(folderId: folderId)
            print("[VIEWMODEL] ✅ 已删除文件夹图片目录: \(folderId)")
        } catch {
            print("[VIEWMODEL] ⚠️ 删除文件夹图片目录失败: \(error.localizedDescription)")
            // 不抛出错误，继续执行删除操作
        }
        
        // 从本地删除文件夹
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            folders.remove(at: index)
            // 从数据库删除文件夹记录
            try DatabaseService.shared.deleteFolder(folderId: folderId)
            // 保存剩余的文件夹列表
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            if selectedFolder?.id == folderId {
                selectedFolder = nil
            }
            print("[VIEWMODEL] ✅ 已从本地删除文件夹: \(folderId)")
        } else {
            print("[VIEWMODEL] ⚠️ 文件夹列表中未找到要删除的文件夹: \(folderId)")
        }
        
        // 刷新文件夹列表和笔记列表
        loadFolders()
        updateFolderCounts()
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
        print("[FolderRename] ========== loadFolders() 开始 ==========")
        print("[FolderRename] 调用栈: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
        print("[FolderRename] 当前 folders 数组数量: \(folders.count)")
        print("[FolderRename] 当前 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
        print("[FolderRename] 当前 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
        
        do {
            let localFolders = try localStorage.loadFolders()
            print("[FolderRename] 从数据库加载了 \(localFolders.count) 个文件夹")
            for folder in localFolders {
                print("[FolderRename]   - id: \(folder.id), name: '\(folder.name)', isSystem: \(folder.isSystem)")
            }
            
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
                    foldersWithCount.insert(Folder(id: "starred", name: "置顶", count: notes.filter { $0.isStarred }.count, isSystem: true), at: hasAllNotes ? 1 : 0)
                }
                
                // 更新文件夹计数
                for i in 0..<foldersWithCount.count {
                    let folder = foldersWithCount[i]
                    if folder.id == "0" {
                        foldersWithCount[i].count = notes.count
                    } else if folder.id == "starred" {
                        foldersWithCount[i].count = notes.filter { $0.isStarred }.count
                    } else if folder.id == "uncategorized" {
                        // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                        foldersWithCount[i].count = notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }.count
                    } else {
                        foldersWithCount[i].count = notes.filter { $0.folderId == folder.id }.count
                    }
                }
                
                print("[FolderRename] 准备更新 folders 数组")
                print("[FolderRename] 更新前 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
                print("[FolderRename] 新 folders 数组内容: \(foldersWithCount.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
                
                self.folders = foldersWithCount
                
                print("[FolderRename] 更新后 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
                print("[FolderRename] 最终 folders 数组包含 \(folders.count) 个文件夹:")
                for folder in folders {
                    print("[FolderRename]   - id: \(folder.id), name: '\(folder.name)', isSystem: \(folder.isSystem), count: \(folder.count)")
                }
                
                // 强制触发 UI 更新
                print("[FolderRename] 调用 objectWillChange.send() 触发 UI 更新")
                objectWillChange.send()
            } else {
                // 如果没有本地文件夹数据，加载示例数据
                print("[FolderRename] 数据库中没有文件夹，加载示例数据")
                loadSampleFolders()
            }
        } catch {
            print("[FolderRename] ❌ 加载文件夹失败: \(error)")
            // 加载示例数据作为后备
            loadSampleFolders()
        }
        
        // 如果没有选择文件夹，选择第一个
        if selectedFolder == nil {
            selectedFolder = folders.first
            print("[FolderRename] 自动选择第一个文件夹: '\(selectedFolder?.name ?? "nil")'")
        }
        
        print("[FolderRename] ========== loadFolders() 完成 ==========")
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
            Folder(id: "starred", name: "置顶", count: notes.filter { $0.isStarred }.count, isSystem: true),
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
    
    /// 保存最后选中的笔记ID
    private func saveLastSelectedNote(_ note: Note?) {
        let defaults = UserDefaults.standard
        if let noteId = note?.id {
            defaults.set(noteId, forKey: "lastSelectedNoteId")
            print("[VIEWMODEL] 已保存最后选中的笔记ID: \(noteId)")
        } else {
            defaults.removeObject(forKey: "lastSelectedNoteId")
            print("[VIEWMODEL] 已清除最后选中的笔记ID")
        }
    }
    
    /// 恢复上次选中的笔记，如果没有则选中第一篇笔记
    private func restoreLastSelectedNote() {
        // 等待notes加载完成后再恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            
            // 如果已经有选中的笔记，不覆盖
            if self.selectedNote != nil {
                return
            }
            
            // 尝试恢复上次选中的笔记
            let defaults = UserDefaults.standard
            if let lastNoteId = defaults.string(forKey: "lastSelectedNoteId"),
               let lastNote = self.notes.first(where: { $0.id == lastNoteId }) {
                // 找到上次选中的笔记，选中它
                self.selectedNote = lastNote
                // 确保选中的文件夹也正确
                let folderId = lastNote.folderId
                if !folderId.isEmpty && folderId != "0" {
                    if let folder = self.folders.first(where: { $0.id == folderId }) {
                        self.selectedFolder = folder
                    }
                } else {
                    // 如果笔记在"所有笔记"或未分类，确保选中正确的文件夹
                    if self.selectedFolder == nil {
                        self.selectedFolder = self.folders.first(where: { $0.id == "0" })
                    }
                }
                print("[VIEWMODEL] 已恢复上次选中的笔记: \(lastNoteId)")
            } else {
                // 没有上次选中的笔记，选中第一篇笔记
                if let firstNote = self.notes.first {
                    self.selectedNote = firstNote
                    // 确保选中的文件夹也正确
                    let folderId = firstNote.folderId
                    if !folderId.isEmpty && folderId != "0" {
                        if let folder = self.folders.first(where: { $0.id == folderId }) {
                            self.selectedFolder = folder
                        }
                    } else {
                        // 如果笔记在"所有笔记"或未分类，确保选中正确的文件夹
                        if self.selectedFolder == nil {
                            self.selectedFolder = self.folders.first(where: { $0.id == "0" })
                        }
                    }
                    print("[VIEWMODEL] 已选中第一篇笔记: \(firstNote.id)")
                }
            }
        }
    }
    
    // MARK: - 同步功能
    
    /// 执行完整同步
    /// 
    /// 完整同步会清除所有本地数据，然后从云端拉取所有笔记和文件夹
    /// 
    /// **注意**：此操作会丢失所有本地未同步的更改
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
            print("[FolderRename] ========== performFullSync() 开始 ==========")
            print("[FolderRename] 同步前 folders 数组数量: \(folders.count)")
            print("[FolderRename] 同步前 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            
            print("[VIEWMODEL] 调用syncService.performFullSync()")
            let result = try await syncService.performFullSync()
            print("[VIEWMODEL] syncService.performFullSync() 成功完成")
            
            // 更新同步结果
            self.syncResult = result
            self.lastSyncTime = result.lastSyncTime
            
            // 重新加载本地数据
            print("[FolderRename] 同步完成，准备重新加载本地数据...")
            await loadLocalDataAfterSync()
            
            print("[FolderRename] 同步后 folders 数组数量: \(folders.count)")
            print("[FolderRename] 同步后 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            
            syncProgress = 1.0
            syncStatusMessage = "同步完成: 成功同步 \(result.syncedNotes) 条笔记"
            print("[VIEWMODEL] 同步成功: 同步了 \(result.syncedNotes) 条笔记")
            print("[FolderRename] ========== performFullSync() 完成 ==========")
            
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
    /// 
    /// 增量同步只同步自上次同步以来的更改，不会清除本地数据
    /// 如果从未同步过，会自动执行完整同步
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
        print("[FolderRename] ========== loadLocalDataAfterSync() 开始 ==========")
        print("[FolderRename] 同步前 folders 数组数量: \(folders.count)")
        print("[FolderRename] 同步前 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
        
        do {
            // 保存当前选中的笔记ID
            let currentSelectedNoteId = selectedNote?.id
            
            let localNotes = try localStorage.getAllLocalNotes()
            self.notes = localNotes
            
            // 重新加载文件夹（从本地存储）
            print("[FolderRename] 调用 loadFolders() 重新加载文件夹列表")
            loadFolders()
            
            print("[FolderRename] 同步后 folders 数组数量: \(folders.count)")
            print("[FolderRename] 同步后 folders 数组内容: \(folders.map { "\($0.id):'\($0.name)'" }.joined(separator: ", "))")
            
            // 如果之前有选中的笔记，更新为重新加载的版本（确保内容是最新的）
            if let noteId = currentSelectedNoteId,
               let updatedNote = localNotes.first(where: { $0.id == noteId }) {
                // 更新选中的笔记，这会触发 NoteDetailView 的 onChange
                await MainActor.run {
                    self.selectedNote = updatedNote
                    print("[VIEWMODEL] 同步后更新选中笔记: \(noteId)")
                }
            } else {
                // 如果没有选中的笔记，尝试恢复上次选中的笔记
                restoreLastSelectedNote()
            }
            
            print("[FolderRename] ========== loadLocalDataAfterSync() 完成 ==========")
            
        } catch {
            print("[FolderRename] ❌ 同步后加载本地数据失败: \(error)")
            print("[FolderRename] ========== loadLocalDataAfterSync() 失败 ==========")
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
            } else if folder.id == "uncategorized" {
                // 未分类文件夹：显示 folderId 为 "0" 或空的笔记
                folders[i].count = notes.filter { $0.folderId == "0" || $0.folderId.isEmpty }.count
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
    
    // MARK: - 笔记CRUD操作（统一接口）
    
    /// 创建笔记
    /// 
    /// **统一接口**：推荐使用此方法创建笔记，而不是直接调用API
    /// 
    /// **特性**：
    /// - 支持离线模式：如果离线，会保存到本地并添加到离线队列
    /// - 自动处理ID变更：如果服务器返回新的ID，会自动更新本地笔记
    /// - 自动更新UI：创建后会自动更新笔记列表和文件夹计数
    /// 
    /// - Parameter note: 要创建的笔记对象
    /// - Throws: 创建失败时抛出错误（网络错误、认证错误等）
    public func createNote(_ note: Note) async throws {
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
                // 获取服务器返回的 folderId（如果有）
                let serverFolderId: String
                if let entryData = entryData, let folderIdValue = entryData["folderId"] {
                    if let folderIdInt = folderIdValue as? Int {
                        serverFolderId = String(folderIdInt)
                    } else if let folderIdStr = folderIdValue as? String {
                        serverFolderId = folderIdStr
                    } else {
                        serverFolderId = note.folderId
                    }
                } else {
                    serverFolderId = note.folderId
                }
                
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
                    // 创建新的笔记对象（使用服务器返回的 ID 和 folderId）
                    let updatedNote = Note(
                        id: noteId,
                        title: note.title,
                        content: note.content,
                        folderId: serverFolderId, // 使用服务器返回的 folderId
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
            // 使用统一的错误处理和离线队列添加逻辑
            _ = handleErrorAndAddToOfflineQueue(
                error: error,
                operationType: .createNote,
                noteId: note.id,
                operationData: [
                    "title": note.title,
                    "content": note.content,
                    "folderId": note.folderId
                ],
                context: "创建笔记"
            )
            // 不设置 errorMessage，避免弹窗提示
        }
    }
    
    /// 更新笔记
    /// 
    /// **统一接口**：推荐使用此方法更新笔记，而不是直接调用API
    /// 
    /// **特性**：
    /// - 支持离线模式：如果离线，会保存到本地并添加到离线队列
    /// - 自动获取最新tag：更新前会从服务器获取最新的tag，避免并发冲突
    /// - 自动更新UI：更新后会自动更新笔记列表
    /// 
    /// - Parameter note: 要更新的笔记对象
    /// - Throws: 更新失败时抛出错误（网络错误、认证错误等）
    func updateNote(_ note: Note) async throws {
        print("[[调试]]步骤19 [VIEWMODEL] 进入updateNote方法，笔记ID: \(note.id), 标题: \(note.title)")
        // 先保存到本地（无论在线还是离线）
        // 这确保了即使云端保存失败，本地数据也不会丢失
        print("[[调试]]步骤20 [VIEWMODEL] 保存到本地数据库，笔记ID: \(note.id)")
        try localStorage.saveNote(note)
        
        // 更新笔记列表
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
            print("[[调试]]步骤21 [VIEWMODEL] 更新笔记列表，笔记ID: \(note.id), 列表索引: \(index)")
        } else {
            // 如果笔记不在列表中（新建笔记），添加到列表
            notes.append(note)
            print("[[调试]]步骤21 [VIEWMODEL] 更新笔记列表，笔记ID: \(note.id), 列表索引: 新增")
        }
        
        // 如果离线或未认证，添加到离线队列
        print("[[调试]]步骤22 [VIEWMODEL] 检查在线状态，isOnline: \(isOnline), isAuthenticated: \(service.isAuthenticated())")
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
            print("[[调试]]步骤23 [VIEWMODEL] 离线模式，添加到离线队列，笔记ID: \(note.id)")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            // 参考 Obsidian 插件：每次上传前都先获取云端最新的笔记信息，包括 tag
            var existingTag = note.rawData?["tag"] as? String ?? ""
            var originalCreateDate = note.rawData?["createDate"] as? Int
            
            print("[[调试]]步骤26 [VIEWMODEL] 获取现有tag，当前tag: \(existingTag.isEmpty ? "空" : existingTag)")
            
            // 检查笔记是否已存在于云端
            var noteExistsInCloud = false
            print("[[调试]]步骤27 [VIEWMODEL] 检查笔记是否存在于云端，笔记ID: \(note.id)")
            do {
                let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
                noteExistsInCloud = true
                if let data = noteDetails["data"] as? [String: Any],
                   let entry = data["entry"] as? [String: Any] {
                    // 获取最新的 tag
                    if let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                        existingTag = latestTag
                        print("[[调试]]步骤28 [VIEWMODEL] 从服务器获取到最新 tag: \(existingTag)")
                    }
                    // 获取最新的 createDate
                    if let latestCreateDate = entry["createDate"] as? Int {
                        originalCreateDate = latestCreateDate
                        print("[[调试]]步骤28 [VIEWMODEL] 从服务器获取到最新 createDate: \(latestCreateDate)")
                    }
                    print("[[调试]]步骤28 [VIEWMODEL] 从服务器获取最新信息，tag: \(existingTag.isEmpty ? "无" : existingTag), createDate: \(originalCreateDate != nil ? String(originalCreateDate!) : "无")")
                }
            } catch {
                // 获取失败，可能是新建笔记还没上传，或者笔记不存在
                print("[[调试]]步骤27.1 [VIEWMODEL] 获取最新笔记信息失败: \(error)，将使用本地存储的 tag")
                noteExistsInCloud = false
            }
            
            // 如果笔记不存在于云端，可能是新建笔记，先创建它
            if !noteExistsInCloud {
                print("[[调试]]步骤29 [VIEWMODEL] 笔记不存在于云端，尝试创建，笔记ID: \(note.id)")
                do {
                    let createResponse = try await service.createNote(
                        title: note.title,
                        content: note.content,
                        folderId: note.folderId
                    )
                    
                    // 如果创建成功，更新笔记ID和rawData
                    if let code = createResponse["code"] as? Int, code == 0,
                       let data = createResponse["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any] {
                        if let newNoteId = entry["id"] as? String {
                            if newNoteId != note.id {
                                // ID 发生变化，需要更新本地笔记
                                print("[VIEWMODEL] ✅ 笔记创建成功，ID更新: \(note.id) -> \(newNoteId)")
                                
                                // 更新rawData
                                var updatedRawData = note.rawData ?? [:]
                                for (key, value) in entry {
                                    updatedRawData[key] = value
                                }
                                
                                // 创建新的 Note 实例（因为 id 是 let 常量）
                                let updatedNote = Note(
                                    id: newNoteId,
                                    title: note.title,
                                    content: note.content,
                                    folderId: note.folderId,
                                    isStarred: note.isStarred,
                                    createdAt: note.createdAt,
                                    updatedAt: note.updatedAt,
                                    tags: note.tags,
                                    rawData: updatedRawData,
                                    rtfData: note.rtfData
                                )
                                
                                // 更新笔记列表
                                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                                    notes[index] = updatedNote
                                }
                                
                                // 如果当前选中的笔记，也更新它
                                if selectedNote?.id == note.id {
                                    selectedNote = updatedNote
                                }
                                
                                // 保存到本地
                                try localStorage.saveNote(updatedNote)
                                
                                print("[VIEWMODEL] ✅ 新建笔记创建并保存成功: \(newNoteId)")
                                return
                            } else {
                                // ID 相同，更新 rawData
                                print("[VIEWMODEL] ✅ 笔记创建成功，ID相同，更新 rawData: \(note.id)")
                                
                                var updatedNote = note
                                var updatedRawData = updatedNote.rawData ?? [:]
                                for (key, value) in entry {
                                    updatedRawData[key] = value
                                }
                                updatedNote.rawData = updatedRawData
                                
                                // 更新笔记列表
                                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                                    notes[index] = updatedNote
                                }
                                
                                // 如果当前选中的笔记，也更新它
                                if selectedNote?.id == note.id {
                                    selectedNote = updatedNote
                                }
                                
                                // 保存到本地
                                try localStorage.saveNote(updatedNote)
                                
                                print("[VIEWMODEL] ✅ 新建笔记创建并保存成功: \(note.id)")
                                return
                            }
                        }
                    }
                } catch {
                    print("[VIEWMODEL] ⚠️ 创建笔记失败: \(error)，将尝试更新（可能会失败）")
                    // 继续尝试更新，可能会失败，但至少本地已保存
                }
            }
            
            // 确保 tag 不为空（如果仍然为空，使用 noteId 作为 fallback）
            if existingTag.isEmpty {
                existingTag = note.id
                print("[[调试]]步骤32 [VIEWMODEL] 警告：tag 仍然为空，使用 noteId 作为 fallback: \(existingTag)")
            }
            
            // 从 rawData 中提取图片信息（setting.data）
            var imageData: [[String: Any]]? = nil
            if let rawData = note.rawData,
               let setting = rawData["setting"] as? [String: Any],
               let settingData = setting["data"] as? [[String: Any]] {
                imageData = settingData
            }
            print("[[调试]]步骤31 [VIEWMODEL] 提取图片信息，imageData数量: \(imageData?.count ?? 0)")
            
            // 使用 nonisolated(unsafe) 来标记这个变量是安全的（这些数据只是被读取和传递）
            nonisolated(unsafe) let unsafeImageData = imageData
            
            print("[[调试]]步骤33 [VIEWMODEL] 调用service.updateNote上传，笔记ID: \(note.id), title: \(note.title), content长度: \(note.content.count)")
            
            let response = try await service.updateNote(
                noteId: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId,
                existingTag: existingTag,
                originalCreateDate: originalCreateDate,
                imageData: unsafeImageData
            )
            
            // 检查响应是否成功（小米笔记API返回格式: {"code": 0, "data": {...}}）
            let code = response["code"] as? Int ?? -1
            print("[[调试]]步骤48 [VIEWMODEL] 检查响应code，code: \(code), 是否成功: \(code == 0)")
            if code == 0 {
                // 更新本地笔记
                if let index = notes.firstIndex(where: { $0.id == note.id }) {
                    var updatedNote = note
                    print("[[调试]]步骤48.1 [VIEWMODEL] 创建updatedNote副本，rtfData存在: \(updatedNote.rtfData != nil), rtfData长度: \(updatedNote.rtfData?.count ?? 0)")
                    
                    // 从响应中提取更新后的数据
                    if let data = response["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any] {
                        print("[[调试]]步骤49 [VIEWMODEL] 提取响应数据，entry字段存在: true")
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
                            print("[[调试]]步骤50 [VIEWMODEL] 使用服务器返回的 modifyDate: \(modifyDate), updatedAt: \(updatedNote.updatedAt)")
                        } else {
                            // 如果服务器没有返回 modifyDate，使用当前时间
                            let currentModifyDate = Int(Date().timeIntervalSince1970 * 1000)
                            updatedRawData["modifyDate"] = currentModifyDate
                            updatedNote.updatedAt = Date()
                            print("[[调试]]步骤50 [VIEWMODEL] 服务器未返回 modifyDate，使用当前时间: \(currentModifyDate)")
                        }
                        
                        updatedNote.rawData = updatedRawData
                        print("[[调试]]步骤51 [VIEWMODEL] 更新rawData，tag: \(updatedRawData["tag"] as? String ?? "无"), modifyDate: \(updatedRawData["modifyDate"] ?? "无")")
                        
                        // 更新笔记内容（如果响应中包含）
                        if let newContent = entry["content"] as? String {
                            updatedNote.content = newContent
                        }
                    } else {
                        // 如果响应格式不同，至少更新rawData
                        print("[[调试]]步骤49 [VIEWMODEL] 提取响应数据，entry字段存在: false")
                        var updatedRawData = updatedNote.rawData ?? [:]
                        updatedRawData.merge(response) { (_, new) in new }
                        updatedNote.rawData = updatedRawData
                    }
                    
                    // 确保保留 rtfData（重要：服务器响应不包含rtfData，必须保留原有的）
                    print("[[调试]]步骤52 [VIEWMODEL] 检查rtfData，更新前rtfData存在: \(updatedNote.rtfData != nil), 原始note.rtfData存在: \(note.rtfData != nil)")
                    if updatedNote.rtfData == nil && note.rtfData != nil {
                        updatedNote.rtfData = note.rtfData
                        print("[[调试]]步骤52 [VIEWMODEL] ⚠️ rtfData丢失，已恢复，长度: \(updatedNote.rtfData?.count ?? 0)")
                    }
                    
                    // 保存到本地存储
                    print("[[调试]]步骤53 [VIEWMODEL] 保存更新后的笔记到本地，笔记ID: \(updatedNote.id), rtfData存在: \(updatedNote.rtfData != nil), rtfData长度: \(updatedNote.rtfData?.count ?? 0)")
                    try localStorage.saveNote(updatedNote)
                    
                    notes[index] = updatedNote
                    selectedNote = updatedNote
                    print("[[调试]]步骤54 [VIEWMODEL] 更新UI状态，笔记ID: \(updatedNote.id)")
                    
                    print("[[调试]]步骤54.1 [VIEWMODEL] 笔记更新成功，笔记ID: \(note.id), tag: \(updatedNote.rawData?["tag"] as? String ?? "无")")
                }
            } else {
                let message = response["message"] as? String ?? "更新笔记失败"
                print("[[调试]]步骤48.1 [VIEWMODEL] 更新笔记失败，code: \(code), message: \(message)")
                throw NSError(domain: "MiNote", code: code, userInfo: [NSLocalizedDescriptionKey: message])
            }
        } catch {
            // 网络错误或cookie失效：添加到离线队列，不显示弹窗
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
                    print("[[调试]]步骤55 [VIEWMODEL] 网络错误，添加到离线队列，笔记ID: \(note.id), 错误: \(error.localizedDescription)")
                }
            } else if case MiNoteError.cookieExpired = error {
                // Cookie失效：保存到离线队列
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
                    print("[[调试]]步骤56 [VIEWMODEL] Cookie失效，添加到离线队列，笔记ID: \(note.id)")
                }
            } else {
                // 其他错误：静默处理，不显示弹窗
                print("[[调试]]步骤57 [VIEWMODEL] 更新笔记失败，笔记ID: \(note.id), 错误: \(error.localizedDescription)")
            }
            // 不设置 errorMessage，避免弹窗提示
        }
    }
    
    /// 确保笔记有完整内容
    /// 
    /// 如果笔记内容为空（只有snippet），会从服务器获取完整内容
    /// 用于延迟加载，提高列表加载速度
    /// 
    /// - Parameter note: 要检查的笔记对象
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
                print("[[调试]] [VIEWMODEL] ensureNoteHasFullContent更新完成，rtfData存在: \(updatedNote.rtfData != nil), rtfData长度: \(updatedNote.rtfData?.count ?? 0)")
                
                // 保存到本地（updateContent已经生成了rtfData）
                print("[[调试]] [VIEWMODEL] ensureNoteHasFullContent保存到本地，rtfData存在: \(updatedNote.rtfData != nil)")
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
                // 总是先从服务器获取最新的 tag（确保使用最新的 tag）
                var finalTag = note.rawData?["tag"] as? String ?? note.id
                
                print("[VIEWMODEL] 删除笔记前，尝试从服务器获取最新 tag，当前 tag: \(finalTag)")
                do {
                    let noteDetails = try await service.fetchNoteDetails(noteId: note.id)
                    if let data = noteDetails["data"] as? [String: Any],
                       let entry = data["entry"] as? [String: Any],
                       let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                        finalTag = latestTag
                        print("[VIEWMODEL] ✅ 从服务器获取到最新 tag: \(finalTag)（之前: \(note.rawData?["tag"] as? String ?? "nil")）")
                    } else {
                        print("[VIEWMODEL] ⚠️ 服务器响应中没有 tag，使用本地 tag: \(finalTag)")
                    }
                } catch {
                    print("[VIEWMODEL] ⚠️ 获取最新 tag 失败: \(error)，将使用本地 tag: \(finalTag)")
                    // 如果获取失败，继续使用本地 tag
                }
                
                // 确保 tag 不为空
                if finalTag.isEmpty {
                    finalTag = note.id
                    print("[VIEWMODEL] ⚠️ tag 最终为空，使用 noteId: \(finalTag)")
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
    
    public func toggleStar(_ note: Note) {
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
    
    /// 创建文件夹
    /// 
    /// **特性**：
    /// - 支持离线模式：如果离线，会保存到本地并添加到离线队列
    /// - 自动处理ID变更：如果服务器返回新的ID，会自动更新本地文件夹
    /// 
    /// - Parameter name: 文件夹名称
    /// - Throws: 创建失败时抛出错误
    public func createFolder(name: String) async throws {
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
            // 刷新文件夹列表
            loadFolders()
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
                    // 1. 更新所有使用旧文件夹ID的笔记，将它们的 folder_id 更新为新ID
                    try DatabaseService.shared.updateNotesFolderId(oldFolderId: tempFolderId, newFolderId: folderId)
                    
                    // 2. 更新内存中的笔记列表
                    for i in 0..<notes.count {
                        if notes[i].folderId == tempFolderId {
                            notes[i].folderId = folderId
                        }
                    }
                    
                    // 3. 删除数据库中的旧文件夹记录
                    try DatabaseService.shared.deleteFolder(folderId: tempFolderId)
                    
                    // 4. 创建新的文件夹对象（使用服务器返回的 ID）
                    let updatedFolder = Folder(
                        id: folderId,
                        name: folderName,
                        count: 0,
                        isSystem: false,
                        createdAt: Date()
                    )
                    
                    // 5. 更新文件夹列表（保持系统文件夹在前）
                    let systemFolders = folders.filter { $0.isSystem }
                    var userFolders = folders.filter { !$0.isSystem }
                    
                    if let index = userFolders.firstIndex(where: { $0.id == tempFolderId }) {
                        userFolders.remove(at: index)
                        userFolders.append(updatedFolder)
                    }
                    
                    folders = systemFolders + userFolders
                    
                    // 6. 保存到本地存储
                    try localStorage.saveFolders(userFolders)
                    
                    print("[VIEWMODEL] ✅ 文件夹ID已更新: \(tempFolderId) -> \(folderId), 并删除了旧文件夹记录")
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
            // 使用统一的错误处理和离线队列添加逻辑
            _ = handleErrorAndAddToOfflineQueue(
                error: error,
                operationType: .createFolder,
                noteId: tempFolderId,
                operationData: [
                    "name": name
                ],
                context: "创建文件夹"
            )
            // 不设置 errorMessage，避免弹窗提示
        }
    }
    
    /// 切换文件夹置顶状态
    func toggleFolderPin(_ folder: Folder) async throws {
        // 先更新本地（无论在线还是离线）
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index].isPinned.toggle()
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            // 确保 selectedFolder 也更新
            if selectedFolder?.id == folder.id {
                selectedFolder?.isPinned.toggle()
            }
            // 重新加载文件夹列表以更新排序
            loadFolders()
        } else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }
        
        // 如果离线或未认证，保存到本地即可（置顶状态是本地功能，不需要同步到云端）
        if !isOnline || !service.isAuthenticated() {
            print("[VIEWMODEL] 离线模式：文件夹置顶状态已更新: \(folder.id)")
            return
        }
        
        // 在线模式：保存到本地数据库（置顶状态是本地功能，不需要同步到云端）
        print("[VIEWMODEL] 文件夹置顶状态已更新: \(folder.id)")
    }
    
    /// 重命名文件夹
    func renameFolder(_ folder: Folder, newName: String) async throws {
        // 先更新本地（无论在线还是离线）
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            var updatedFolder = folders[index]
            updatedFolder.name = newName
            // 更新 rawData 中的 subject 字段
            var updatedRawData = updatedFolder.rawData ?? [:]
            updatedRawData["subject"] = newName
            updatedFolder.rawData = updatedRawData
            
            // 重新创建数组以确保 SwiftUI 检测到变化
            var updatedFolders = folders
            updatedFolders[index] = updatedFolder
            folders = updatedFolders
            
            // 强制触发 UI 更新（通过 objectWillChange）
            objectWillChange.send()
            
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            
            // 确保 selectedFolder 也更新（使用新的 updatedFolder 实例）
            if selectedFolder?.id == folder.id {
                selectedFolder = updatedFolder
                print("[VIEWMODEL] ✅ 已更新 selectedFolder（初始）: \(newName)")
            }
            
            // 打印调试信息
            print("[VIEWMODEL] 🔍 调试：初始更新后，文件夹名称 = \(updatedFolder.name)")
        } else {
            throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
        }
        
        // 如果离线或未认证，添加到离线队列（本地已更新，等待上线后同步）
        if !isOnline || !service.isAuthenticated() {
            print("[FolderRename] ========== 离线模式 ==========")
            print("[FolderRename] isOnline: \(isOnline), isAuthenticated: \(service.isAuthenticated())")
            print("[FolderRename] 文件夹已在本地重命名（'\(folder.name)' -> '\(newName)'），添加到离线队列")
            
            let operationData = try JSONEncoder().encode([
                "oldName": folder.name,  // 保存原始名称（重命名前的名称）
                "newName": newName       // 保存新名称
            ])
            let operation = OfflineOperation(
                type: .renameFolder,
                noteId: folder.id, // 对于文件夹操作，使用 folderId
                data: operationData
            )
            try offlineQueue.addOperation(operation)
            print("[FolderRename] ✅ 离线重命名操作已添加到队列: \(folder.id)")
            print("[FolderRename] ========== 离线模式处理完成 ==========")
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
            
            // 检查响应是否成功（code == 0 或没有 code 字段但 result == "ok"）
            let code = response["code"] as? Int
            let isSuccess = (code == 0) || (code == nil && response["result"] as? String == "ok")
            
            if isSuccess {
                print("[FolderRename] ========== 云端重命名成功，更新本地数据 ==========")
                print("[FolderRename] 响应 code: \(code ?? -1)")
                print("[FolderRename] 当前 folders 数组数量: \(folders.count)")
                print("[FolderRename] 当前 folders 数组内容: \(folders.map { "\($0.id):\($0.name)" }.joined(separator: ", "))")
                
                // 更新本地文件夹对象（类已经是 @MainActor，不需要额外的 MainActor.run）
                guard let index = folders.firstIndex(where: { $0.id == folder.id }) else {
                    print("[FolderRename] ❌ 错误：在 folders 数组中未找到文件夹，folderId: \(folder.id)")
                    print("[FolderRename] 当前 folders 数组: \(folders.map { "\($0.id):\($0.name)" }.joined(separator: ", "))")
                    throw NSError(domain: "MiNote", code: 404, userInfo: [NSLocalizedDescriptionKey: "文件夹不存在"])
                }
                
                print("[FolderRename] ✅ 找到文件夹，索引: \(index)")
                print("[FolderRename] 更新前的文件夹: id=\(folders[index].id), name='\(folders[index].name)'")
                
                // 从当前 folders 数组获取最新的文件夹对象
                var updatedFolder = folders[index]
                updatedFolder.name = newName
                
                // 构建更新的 rawData
                // 先保留原有的 rawData（包含 subject 等字段）
                var updatedRawData: [String: Any] = updatedFolder.rawData ?? [:]
                
                // 如果有 data 字段，合并它（包含新的 tag、modifyDate 等）
                if let data = response["data"] as? [String: Any] {
                    // 合并 data，但保留原有的 subject 字段（因为 data 中没有 subject）
                    updatedRawData = updatedRawData.merging(data) { (old, new) in new }
                    print("[FolderRename] 合并 response.data 到 rawData")
                }
                
                // 如果有 entry 字段（根级别），也合并进去（包含完整的文件夹信息）
                if let entry = response["entry"] as? [String: Any] {
                    updatedRawData = updatedRawData.merging(entry) { (_, new) in new }
                    print("[FolderRename] 合并 response.entry 到 rawData")
                }
                
                // 使用统一的提取方法获取 tag
                let tagValue = extractTag(from: response, fallbackTag: existingTag)
                updatedRawData["tag"] = tagValue
                // 确保 subject 字段设置为新名称（因为 API 响应中可能没有 subject）
                updatedRawData["subject"] = newName
                // 确保 id 字段正确
                updatedRawData["id"] = folder.id
                // 确保 type 字段
                updatedRawData["type"] = "folder"
                
                updatedFolder.rawData = updatedRawData
                
                print("[FolderRename] 更新后的文件夹对象: id=\(updatedFolder.id), name='\(updatedFolder.name)', tag='\(tagValue)'")
                
                // 更新文件夹列表：重新创建数组以确保 SwiftUI 检测到变化
                // 由于 Folder 的 Equatable 只比较 id，我们需要确保创建新数组来触发 SwiftUI 更新
                var updatedFolders = folders
                print("[FolderRename] 更新前 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
                updatedFolders[index] = updatedFolder
                folders = updatedFolders
                print("[FolderRename] 更新后 folders 数组引用: \(Unmanaged.passUnretained(folders as AnyObject).toOpaque())")
                print("[FolderRename] 更新后 folders 数组数量: \(folders.count)")
                print("[FolderRename] 更新后 folders 数组内容: \(folders.map { "\($0.id):\($0.name)" }.joined(separator: ", "))")
                
                // 强制触发 UI 更新（通过 objectWillChange）
                print("[FolderRename] 调用 objectWillChange.send() 触发 UI 更新")
                objectWillChange.send()
                
                // 更新选中的文件夹（如果当前选中的是这个文件夹）
                if selectedFolder?.id == folder.id {
                    print("[FolderRename] 更新 selectedFolder: '\(selectedFolder?.name ?? "nil")' -> '\(newName)'")
                    selectedFolder = updatedFolder
                    print("[FolderRename] ✅ selectedFolder 已更新: '\(selectedFolder?.name ?? "nil")'")
                } else {
                    print("[FolderRename] selectedFolder 不是当前文件夹，无需更新")
                }
                
                // 保存到本地存储（保存的是更新后的 folders）
                print("[FolderRename] 保存到本地存储...")
                try localStorage.saveFolders(folders.filter { !$0.isSystem })
                print("[FolderRename] ✅ 已保存到本地存储")
                
                // 验证保存后的数据
                if let savedFolders = try? localStorage.loadFolders() {
                    if let savedFolder = savedFolders.first(where: { $0.id == folder.id }) {
                        print("[FolderRename] ✅ 验证：从数据库读取的文件夹名称 = '\(savedFolder.name)'")
                    } else {
                        print("[FolderRename] ⚠️ 验证：从数据库读取时未找到文件夹")
                    }
                }
                
                print("[FolderRename] ✅ 文件夹重命名成功: \(folder.id) -> \(newName), 新 tag: \(tagValue)")
                print("[FolderRename] ========== 云端重命名完成 ==========")
            } else {
                let errorCode = code ?? -1
                let message = response["description"] as? String ?? response["message"] as? String ?? "重命名文件夹失败"
                print("[VIEWMODEL] 重命名文件夹失败，code: \(errorCode), message: \(message)")
                throw NSError(domain: "MiNote", code: errorCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
        } catch {
            // 使用统一的错误处理和离线队列添加逻辑
            _ = handleErrorAndAddToOfflineQueue(
                error: error,
                operationType: .renameFolder,
                noteId: folder.id,
                operationData: [
                    "oldName": folder.name,
                    "newName": newName
                ],
                context: "重命名文件夹"
            )
            // 不设置 errorMessage，避免弹窗提示
        }
    }
    
    /// 删除文件夹
    func deleteFolder(_ folder: Folder) async throws {
        // 如果离线或未认证，先删除本地文件夹，然后添加到离线队列
        if !isOnline || !service.isAuthenticated() {
            print("[VIEWMODEL] 离线模式：先删除本地文件夹，然后添加到离线队列，folderId: \(folder.id)")
            
            // 1. 先删除本地文件夹
            // 删除文件夹的图片目录
            do {
                try LocalStorageService.shared.deleteFolderImageDirectory(folderId: folder.id)
                print("[VIEWMODEL] ✅ 已删除文件夹图片目录: \(folder.id)")
            } catch {
                print("[VIEWMODEL] ⚠️ 删除文件夹图片目录失败: \(error.localizedDescription)")
                // 不抛出错误，继续执行删除操作
            }
            
            // 从本地删除文件夹
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                folders.remove(at: index)
                // 从数据库删除文件夹记录
                try DatabaseService.shared.deleteFolder(folderId: folder.id)
                // 保存剩余的文件夹列表
                try localStorage.saveFolders(folders.filter { !$0.isSystem })
                if selectedFolder?.id == folder.id {
                    selectedFolder = nil
                }
                print("[VIEWMODEL] ✅ 已从本地删除文件夹: \(folder.id)")
            } else {
                print("[VIEWMODEL] ⚠️ 文件夹列表中未找到要删除的文件夹: \(folder.id)")
            }
            
            // 2. 添加到离线队列（只保存 folderID，等待上线后再通过 folderID 查询 tag 并删除）
            let operationDict: [String: Any] = [
                "folderId": folder.id,
                "purge": false
            ]
            
            guard let operationData = try? JSONSerialization.data(withJSONObject: operationDict) else {
                throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法序列化删除操作数据"])
            }
            
            let operation = OfflineOperation(
                type: .deleteFolder,
                noteId: folder.id,
                data: operationData
            )
            try offlineQueue.addOperation(operation)
            print("[VIEWMODEL] ✅ 离线删除操作已添加到队列: \(folder.id)")
            
            // 刷新文件夹列表和笔记列表
            loadFolders()
            updateFolderCounts()
            return
        }
        
        // 在线模式：执行删除操作
        // 1. 从服务器获取最新的 tag
        var finalTag: String? = nil
        
        print("[VIEWMODEL] 删除文件夹前，从服务器获取最新 tag")
        do {
            let folderDetails = try await service.fetchFolderDetails(folderId: folder.id)
            if let data = folderDetails["data"] as? [String: Any],
               let entry = data["entry"] as? [String: Any],
               let latestTag = entry["tag"] as? String, !latestTag.isEmpty {
                finalTag = latestTag
                print("[VIEWMODEL] ✅ 从服务器获取到最新 tag: \(finalTag!)")
            } else {
                // 尝试从 data.tag 获取（如果 entry.tag 不存在）
                if let data = folderDetails["data"] as? [String: Any],
                   let dataTag = data["tag"] as? String, !dataTag.isEmpty {
                    finalTag = dataTag
                    print("[VIEWMODEL] ✅ 从 data.tag 获取到 tag: \(finalTag!)")
                } else {
                    print("[VIEWMODEL] ⚠️ 服务器响应中没有 tag 字段")
                }
            }
        } catch {
            print("[VIEWMODEL] ⚠️ 获取最新文件夹 tag 失败: \(error)")
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法获取文件夹 tag，删除失败: \(error.localizedDescription)"])
        }
        
        // 确保获取到了 tag
        guard let tag = finalTag, !tag.isEmpty else {
            print("[VIEWMODEL] ❌ 无法从服务器获取有效的 tag，无法删除文件夹")
            throw NSError(domain: "MiNote", code: 500, userInfo: [NSLocalizedDescriptionKey: "无法从服务器获取文件夹 tag，删除失败"])
        }
        
        finalTag = tag
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        // 2. 调用API删除云端
        do {
            _ = try await service.deleteFolder(folderId: folder.id, tag: finalTag!, purge: false)
            print("[VIEWMODEL] ✅ 云端文件夹删除成功: \(folder.id), tag: \(finalTag!)")
        } catch {
            // 云端删除失败，保存到离线队列以便后续重试
            print("[VIEWMODEL] ⚠️ 云端删除文件夹失败: \(error.localizedDescription)，已保存到离线队列")
            
            let operationDict: [String: Any] = [
                "folderId": folder.id,
                "purge": false
            ]
            
            if let operationData = try? JSONSerialization.data(withJSONObject: operationDict) {
                let operation = OfflineOperation(
                    type: .deleteFolder,
                    noteId: folder.id,
                    data: operationData
                )
                try? offlineQueue.addOperation(operation)
                print("[VIEWMODEL] 云端删除失败，已保存到离线队列等待重试: \(folder.id)")
            }
            throw error
        }
        
        // 3. 云端删除成功后，删除本地数据
        // 删除文件夹的图片目录
        do {
            try LocalStorageService.shared.deleteFolderImageDirectory(folderId: folder.id)
            print("[VIEWMODEL] ✅ 已删除文件夹图片目录: \(folder.id)")
        } catch {
            print("[VIEWMODEL] ⚠️ 删除文件夹图片目录失败: \(error.localizedDescription)")
            // 不抛出错误，继续执行删除操作
        }
        
        // 从本地删除文件夹
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders.remove(at: index)
            // 从数据库删除文件夹记录
            try DatabaseService.shared.deleteFolder(folderId: folder.id)
            // 保存剩余的文件夹列表
            try localStorage.saveFolders(folders.filter { !$0.isSystem })
            if selectedFolder?.id == folder.id {
                selectedFolder = nil
            }
            print("[VIEWMODEL] ✅ 已从本地删除文件夹: \(folder.id)")
        } else {
            print("[VIEWMODEL] ⚠️ 文件夹列表中未找到要删除的文件夹: \(folder.id)")
        }
        
        // 刷新文件夹列表和笔记列表
        loadFolders()
        updateFolderCounts()
    }
    
    // MARK: - 便捷方法
    
    /// 创建新笔记的便捷方法（用于快速创建空笔记）
    public func createNewNote() {
        // 创建一个默认笔记，使用标准的 XML 格式
        // 使用临时 ID（如果离线）或等待 API 返回的真实 ID（如果在线）
        let tempId = UUID().uuidString
        let newNote = Note(
            id: tempId,
            title: "新笔记",
            content: "<new-format/><text indent=\"1\"></text>",
            folderId: selectedFolder?.id ?? "0",
            isStarred: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // 使用统一的创建接口，它会处理在线/离线逻辑
        Task {
            do {
                try await createNote(newNote)
            } catch {
                print("[VIEWMODEL] 创建笔记失败: \(error)")
                errorMessage = "创建笔记失败: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Cookie过期处理（委托给 AuthenticationStateManager）
    
    /// 处理Cookie失效弹窗的"刷新Cookie"选项
    @MainActor
    func handleCookieExpiredRefresh() {
        authStateManager.handleCookieExpiredRefresh()
    }
    
    /// 处理Cookie失效弹窗的"取消"选项
    @MainActor
    func handleCookieExpiredCancel() {
        authStateManager.handleCookieExpiredCancel()
    }
    
    /// 处理Cookie刷新完成
    /// 
    /// Cookie刷新成功后调用此方法
    @MainActor
    func handleCookieRefreshed() {
        authStateManager.handleCookieRefreshed()
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
            // 上传失败：静默处理，不显示弹窗
            print("[VIEWMODEL] 上传图片失败: \(error.localizedDescription)")
            // 不设置 errorMessage，避免弹窗提示
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
