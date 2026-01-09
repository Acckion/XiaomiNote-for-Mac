import Foundation
import Combine

/// 离线操作处理器
/// 
/// 负责执行离线操作队列中的操作，包括：
/// - 并发处理多个操作
/// - 智能重试机制（指数退避）
/// - 错误分类和处理
/// - 进度反馈
/// - 启动时条件检查（网络可用且 Cookie 有效）
/// 
/// 遵循需求 3.1, 3.2, 3.3, 3.4, 3.5
@MainActor
public final class OfflineOperationProcessor: ObservableObject {
    public static let shared = OfflineOperationProcessor()
    
    // MARK: - 依赖服务
    
    private let offlineQueue = OfflineOperationQueue.shared
    private let service = MiNoteService.shared
    private let localStorage = LocalStorageService.shared
    private let onlineStateManager = OnlineStateManager.shared
    private let scheduledTaskManager = ScheduledTaskManager.shared
    
    // MARK: - Combine订阅
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 配置
    
    /// 最大并发操作数
    var maxConcurrentOperations: Int = 3
    
    /// 最大重试次数
    var maxRetryCount: Int = 3
    
    /// 初始重试延迟（秒）
    var initialRetryDelay: TimeInterval = 5.0
    
    // MARK: - 状态
    
    /// 是否正在处理
    @Published public var isProcessing: Bool = false
    
    /// 处理进度（0.0 - 1.0）
    @Published public var progress: Double = 0.0
    
    /// 当前正在处理的操作
    @Published public var currentOperation: OfflineOperation?
    
    /// 已处理的操作数量
    @Published public var processedCount: Int = 0
    
    /// 总操作数量
    @Published public var totalCount: Int = 0
    
    /// 失败的操作列表
    @Published public var failedOperations: [OfflineOperation] = []
    
    /// 处理状态消息
    @Published public var statusMessage: String = ""
    
    /// 最后一次跳过处理的原因
    @Published public var lastSkipReason: SkipReason?
    
    // MARK: - 跳过原因枚举
    
    /// 跳过处理的原因
    public enum SkipReason: String, Sendable {
        case alreadyProcessing = "已在处理中"
        case networkUnavailable = "网络不可用"
        case cookieInvalid = "Cookie 无效"
        case notAuthenticated = "未认证"
        case emptyQueue = "队列为空"
    }
    
    // MARK: - 私有状态
    
    private var processingTask: Task<Void, Never>?
    
    private init() {
        setupOnlineStateMonitoring()
    }
    
    // MARK: - 在线状态监控
    
    /// 设置在线状态监控，自动响应在线状态变化
    private func setupOnlineStateMonitoring() {
        // 监听在线状态变化
        onlineStateManager.$isOnline
            .sink { [weak self] isOnline in
                Task { @MainActor in
                    if isOnline {
                        // 网络恢复，自动处理离线操作
                        print("[OfflineProcessor] 检测到网络恢复，自动处理离线操作")
                        await self?.processOperations()
                    } else {
                        // 网络断开，停止处理
                        print("[OfflineProcessor] 检测到网络断开，停止处理离线操作")
                        self?.cancelProcessing()
                    }
                }
            }
            .store(in: &cancellables)
        
        // 监听在线状态变化通知
        NotificationCenter.default.publisher(for: .onlineStatusDidChange)
            .sink { [weak self] notification in
                Task { @MainActor in
                    if let isOnline = notification.userInfo?["isOnline"] as? Bool, isOnline {
                        // 延迟一下，确保网络完全恢复
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒
                        await self?.processOperations()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - 公共方法
    
    /// 检查是否可以处理离线队列
    /// 
    /// 检查条件：
    /// 1. 网络可用
    /// 2. 已认证（有 Cookie）
    /// 3. Cookie 有效
    /// 
    /// 遵循需求 3.1, 3.2, 3.3
    /// 
    /// - Returns: 如果可以处理返回 (true, nil)，否则返回 (false, 跳过原因)
    public func canProcessQueue() -> (canProcess: Bool, reason: SkipReason?) {
        // 检查是否已在处理中
        if isProcessing {
            return (false, .alreadyProcessing)
        }
        
        // 检查是否已认证（需求 3.3 - Cookie 过期时跳过）
        guard service.isAuthenticated() else {
            return (false, .notAuthenticated)
        }
        
        // 检查在线状态（包含网络可用和 Cookie 有效性检查）
        // OnlineStateManager.isOnline = 网络连接 && 已认证 && Cookie有效
        guard onlineStateManager.isOnline else {
            // 进一步判断具体原因
            if !NetworkMonitor.shared.isConnected {
                return (false, .networkUnavailable)
            }
            if !scheduledTaskManager.isCookieValid {
                return (false, .cookieInvalid)
            }
            return (false, .networkUnavailable)
        }
        
        // 检查队列是否为空
        let pendingOperations = offlineQueue.getPendingOperations()
        if pendingOperations.isEmpty {
            return (false, .emptyQueue)
        }
        
        return (true, nil)
    }
    
    /// 启动时处理离线队列
    /// 
    /// 专门用于应用启动时的离线队列处理，严格检查条件：
    /// - 只在网络可用且 Cookie 有效时处理队列（需求 3.1）
    /// - 网络不可用时保留队列中的操作（需求 3.2）
    /// - Cookie 过期时保留队列中的操作（需求 3.3）
    /// - 处理完成后更新本地数据库（需求 3.4）
    /// - 处理失败的操作保留在队列中（需求 3.5）
    /// 
    /// - Returns: 处理结果，包含处理的操作数量和跳过原因（如果有）
    public func processOperationsAtStartup() async -> (processedCount: Int, skippedReason: SkipReason?) {
        print("[OfflineProcessor] 🚀 启动时处理离线队列")
        
        // 检查是否可以处理
        let (canProcess, reason) = canProcessQueue()
        
        if !canProcess {
            if let reason = reason {
                lastSkipReason = reason
                print("[OfflineProcessor] ⏭️ 跳过处理: \(reason.rawValue)")
                
                // 如果是队列为空，不算跳过
                if reason == .emptyQueue {
                    return (0, nil)
                }
            }
            return (0, reason)
        }
        
        // 清除跳过原因
        lastSkipReason = nil
        
        // 执行处理
        await processOperations()
        
        // 返回处理结果
        let successCount = processedCount - failedOperations.count
        return (successCount, nil)
    }
    
    /// 处理所有待处理的操作
    /// 
    /// 并发处理多个操作，按优先级排序，支持智能重试
    /// 
    /// 遵循需求：
    /// - 3.4: 处理完成后更新本地数据库
    /// - 3.5: 处理失败的操作保留在队列中
    public func processOperations() async {
        guard !isProcessing else {
            print("[OfflineProcessor] 已在处理中，跳过")
            lastSkipReason = .alreadyProcessing
            return
        }
        
        // 检查在线状态（包含网络和 Cookie 有效性）
        guard onlineStateManager.isOnline else {
            // 进一步判断具体原因
            if !NetworkMonitor.shared.isConnected {
                print("[OfflineProcessor] 网络不可用，跳过处理")
                lastSkipReason = .networkUnavailable
            } else if !scheduledTaskManager.isCookieValid {
                print("[OfflineProcessor] Cookie 无效，跳过处理")
                lastSkipReason = .cookieInvalid
            } else if !service.isAuthenticated() {
                print("[OfflineProcessor] 未认证，跳过处理")
                lastSkipReason = .notAuthenticated
            } else {
                print("[OfflineProcessor] 不在线，跳过处理")
                lastSkipReason = .networkUnavailable
            }
            return
        }
        
        // 确保已认证
        guard service.isAuthenticated() else {
            print("[OfflineProcessor] 未认证，跳过处理")
            lastSkipReason = .notAuthenticated
            return
        }
        
        // 清除跳过原因
        lastSkipReason = nil
        
        isProcessing = true
        statusMessage = "开始处理离线操作..."
        
        let operations = offlineQueue.getPendingOperations()
        guard !operations.isEmpty else {
            print("[OfflineProcessor] 没有待处理的操作")
            isProcessing = false
            return
        }
        
        totalCount = operations.count
        processedCount = 0
        failedOperations = []
        progress = 0.0
        
        print("[OfflineProcessor] 开始处理 \(totalCount) 个操作，最大并发数: \(maxConcurrentOperations)")
        
        // 使用 TaskGroup 并发处理
        await withTaskGroup(of: Void.self) { group in
            var activeTasks = 0
            var operationIndex = 0
            
            // 启动初始批次的任务
            while activeTasks < maxConcurrentOperations && operationIndex < operations.count {
                let operation = operations[operationIndex]
                operationIndex += 1
                activeTasks += 1
                
                group.addTask { [weak self] in
                    // 由于 processOperationWithRetry 是 @MainActor 隔离的，直接调用即可
                    await self?.processOperationWithRetry(operation)
                }
            }
            
            // 等待任务完成并启动新任务
            while activeTasks > 0 || operationIndex < operations.count {
                // 等待一个任务完成
                await group.next()
                activeTasks -= 1
                
                // 在启动新任务前检查在线状态
                // 如果网络断开或 Cookie 失效，停止处理新任务
                if !onlineStateManager.isOnline {
                    print("[OfflineProcessor] ⚠️ 在线状态变化，停止处理新任务")
                    break
                }
                
                // 启动新任务
                while activeTasks < maxConcurrentOperations && operationIndex < operations.count {
                    let operation = operations[operationIndex]
                    operationIndex += 1
                    activeTasks += 1
                    
                    group.addTask { [weak self] in
                        // 由于 processOperationWithRetry 是 @MainActor 隔离的，直接调用即可
                        await self?.processOperationWithRetry(operation)
                    }
                }
            }
        }
        
        currentOperation = nil
        isProcessing = false
        
        if failedOperations.isEmpty {
            statusMessage = "所有操作处理完成"
        } else {
            statusMessage = "处理完成，\(failedOperations.count) 个操作失败"
            // 发送通知，提示用户有失败的操作
            NotificationCenter.default.post(
                name: NSNotification.Name("OfflineOperationsFailed"),
                object: nil,
                userInfo: ["count": failedOperations.count]
            )
        }
        
        print("[OfflineProcessor] 处理完成，成功: \(processedCount - failedOperations.count), 失败: \(failedOperations.count)")
        
        // 发送处理完成通知（需求 3.4 - 处理完成后更新本地数据库已在各操作中完成）
        NotificationCenter.default.post(
            name: .offlineQueueProcessingCompleted,
            object: nil,
            userInfo: [
                "totalCount": totalCount,
                "successCount": processedCount - failedOperations.count,
                "failedCount": failedOperations.count
            ]
        )
    }
    
    /// 处理单个操作（带重试）
    /// 
    /// - Parameter operation: 要处理的操作
    private func processOperationWithRetry(_ operation: OfflineOperation) async {
        // 更新当前操作（需要在主线程）
        await MainActor.run {
            currentOperation = operation
            statusMessage = "处理操作: \(operation.type.rawValue)"
        }
        
        var currentRetryCount = operation.retryCount
        
        // 尝试处理，支持重试
        while currentRetryCount <= maxRetryCount {
            do {
                // 更新状态为处理中
                try offlineQueue.updateOperationStatus(operationId: operation.id, status: .processing)
                
                // 执行操作
                try await processOperation(operation)
                
                // 成功：标记为已完成
                try offlineQueue.updateOperationStatus(operationId: operation.id, status: .completed)
                
                await MainActor.run {
                    processedCount += 1
                    progress = Double(processedCount) / Double(totalCount)
                }
                
                print("[OfflineProcessor] ✅ 成功处理操作: \(operation.id), type: \(operation.type.rawValue)")
                return
                
            } catch {
                // 判断是否可重试
                let canRetry = isRetryableError(error)
                let needsUserAction = requiresUserAction(error)
                
                if needsUserAction {
                    // 需要用户操作，标记为失败但不重试
                    let errorMessage = error.localizedDescription
                    try? offlineQueue.updateOperationStatus(operationId: operation.id, status: .failed, error: errorMessage)
                    
                    await MainActor.run {
                        failedOperations.append(operation)
                        processedCount += 1
                        progress = Double(processedCount) / Double(totalCount)
                    }
                    
                    print("[OfflineProcessor] ⚠️ 操作需要用户操作: \(operation.id), error: \(errorMessage)")
                    return
                }
                
                if !canRetry || currentRetryCount >= maxRetryCount {
                    // 不可重试或达到最大重试次数，标记为失败
                    let errorMessage = error.localizedDescription
                    try? offlineQueue.updateOperationStatus(operationId: operation.id, status: .failed, error: errorMessage)
                    
                    await MainActor.run {
                        failedOperations.append(operation)
                        processedCount += 1
                        progress = Double(processedCount) / Double(totalCount)
                    }
                    
                    print("[OfflineProcessor] ❌ 处理操作失败: \(operation.id), error: \(errorMessage), retryCount: \(currentRetryCount)")
                    return
                }
                
                // 可重试：等待后重试
                currentRetryCount += 1
                let delay = calculateRetryDelay(retryCount: currentRetryCount - 1)
                
                print("[OfflineProcessor] ⏳ 操作失败，\(delay)秒后重试 (第\(currentRetryCount)次): \(operation.id)")
                
                // 更新重试次数
                try? offlineQueue.updateOperationStatus(operationId: operation.id, status: .pending, error: error.localizedDescription)
                
                // 等待延迟
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    /// 重试失败的操作
    public func retryFailedOperations() async {
        let failed = failedOperations
        guard !failed.isEmpty else {
            print("[OfflineProcessor] 没有失败的操作需要重试")
            return
        }
        
        print("[OfflineProcessor] 重试 \(failed.count) 个失败的操作")
        
        // 重置失败操作的状态为 pending
        for operation in failed {
            var updatedOperation = operation
            updatedOperation.status = .pending
            updatedOperation.lastError = nil
            try? offlineQueue.addOperation(updatedOperation)
        }
        
        failedOperations = []
        await processOperations()
    }
    
    /// 取消处理
    public func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        statusMessage = "处理已取消"
        print("[OfflineProcessor] 处理已取消")
    }
    
    // MARK: - 私有方法（待实现）
    
    /// 处理单个操作
    /// 
    /// - Parameter operation: 要处理的操作
    /// - Throws: 处理错误
    private func processOperation(_ operation: OfflineOperation) async throws {
        switch operation.type {
        case .createNote:
            try await processCreateNoteOperation(operation)
        case .updateNote:
            try await processUpdateNoteOperation(operation)
        case .deleteNote:
            try await processDeleteNoteOperation(operation)
        case .uploadImage:
            // 图片上传操作在更新笔记时一起处理
            print("[OfflineProcessor] 跳过图片上传操作（已在更新笔记时处理）")
        case .createFolder:
            try await processCreateFolderOperation(operation)
        case .renameFolder:
            try await processRenameFolderOperation(operation)
        case .deleteFolder:
            try await processDeleteFolderOperation(operation)
        }
    }
    
    // MARK: - 具体操作处理方法
    
    /// 处理创建笔记操作
    private func processCreateNoteOperation(_ operation: OfflineOperation) async throws {
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            throw NSError(domain: "OfflineProcessor", code: 404, userInfo: [NSLocalizedDescriptionKey: "笔记不存在"])
        }
        
        // 创建笔记到云端
        let response = try await service.createNote(
            title: note.title,
            content: note.content,
            folderId: note.folderId
        )
        
        // 解析响应并更新本地笔记
        guard isResponseSuccess(response),
              let entry = extractEntry(from: response),
              let serverNoteId = entry["id"] as? String else {
            let message = extractErrorMessage(from: response, defaultMessage: "服务器响应格式不正确")
            throw NSError(domain: "OfflineProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        let tag = extractTag(from: response, fallbackTag: entry["tag"] as? String ?? serverNoteId)
        
        // 获取服务器返回的 folderId
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
        
        // 更新笔记的 rawData
        var updatedRawData = note.rawData ?? [:]
        for (key, value) in entry {
            updatedRawData[key] = value
        }
        updatedRawData["tag"] = tag
        
        // 如果服务器返回的 ID 与本地不同，需要更新
        if note.id != serverNoteId {
            let updatedNote = Note(
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
            
            // 保存新笔记，删除旧笔记
            try localStorage.saveNote(updatedNote)
            try? localStorage.deleteNote(noteId: note.id)
        } else {
            // ID 相同，更新现有笔记
            let updatedNote = Note(
                id: note.id,
                title: note.title,
                content: note.content,
                folderId: serverFolderId,
                isStarred: note.isStarred,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                tags: note.tags,
                rawData: updatedRawData
            )
            try localStorage.saveNote(updatedNote)
        }
        
        print("[OfflineProcessor] ✅ 成功创建笔记: \(operation.noteId) -> \(serverNoteId)")
    }
    
    /// 处理更新笔记操作
    private func processUpdateNoteOperation(_ operation: OfflineOperation) async throws {
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            throw NSError(domain: "OfflineProcessor", code: 404, userInfo: [NSLocalizedDescriptionKey: "笔记不存在"])
        }
        
        // 更新笔记到云端
        try await service.updateNote(
            noteId: note.id,
            title: note.title,
            content: note.content,
            folderId: note.folderId,
            existingTag: note.rawData?["tag"] as? String ?? note.id
        )
        
        print("[OfflineProcessor] ✅ 成功更新笔记: \(operation.noteId)")
    }
    
    /// 处理删除笔记操作
    private func processDeleteNoteOperation(_ operation: OfflineOperation) async throws {
        // 从操作数据中解析 tag
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let tag = operationData["tag"] as? String else {
            throw NSError(domain: "OfflineProcessor", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的删除操作数据"])
        }
        
        // 删除笔记
        _ = try await service.deleteNote(noteId: operation.noteId, tag: tag, purge: false)
        
        print("[OfflineProcessor] ✅ 成功删除笔记: \(operation.noteId)")
    }
    
    /// 处理创建文件夹操作
    private func processCreateFolderOperation(_ operation: OfflineOperation) async throws {
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let folderName = operationData["name"] as? String else {
            throw NSError(domain: "OfflineProcessor", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"])
        }
        
        // 创建文件夹到云端
        let response = try await service.createFolder(name: folderName)
        
        guard isResponseSuccess(response),
              let entry = extractEntry(from: response) else {
            let message = extractErrorMessage(from: response, defaultMessage: "服务器返回无效的文件夹信息")
            throw NSError(domain: "OfflineProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        // 处理服务器返回的文件夹ID
        var serverFolderId: String?
        if let idString = entry["id"] as? String {
            serverFolderId = idString
        } else if let idInt = entry["id"] as? Int {
            serverFolderId = String(idInt)
        }
        
        guard let folderId = serverFolderId,
              let subject = entry["subject"] as? String else {
            throw NSError(domain: "OfflineProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: "服务器返回无效的文件夹信息"])
        }
        
        // 如果服务器返回的 ID 与本地不同，需要更新本地文件夹和笔记
        if operation.noteId != folderId {
            // 更新所有使用旧文件夹ID的笔记
            let notes = try localStorage.getAllLocalNotes()
            for note in notes where note.folderId == operation.noteId {
                var updatedNote = note
                updatedNote.folderId = folderId
                try localStorage.saveNote(updatedNote)
            }
        }
        
        // 保存文件夹到数据库
        let tag = extractTag(from: response, fallbackTag: entry["tag"] as? String ?? folderId)
        var folderRawData: [String: Any] = [:]
        for (key, value) in entry {
            folderRawData[key] = value
        }
        folderRawData["tag"] = tag
        
        let folder = Folder(
            id: folderId,
            name: subject,
            count: 0,
            isSystem: false,
            isPinned: false,
            createdAt: Date(),
            rawData: folderRawData
        )
        
        try DatabaseService.shared.saveFolder(folder)
        
        print("[OfflineProcessor] ✅ 成功创建文件夹: \(operation.noteId) -> \(folderId)")
    }
    
    /// 处理重命名文件夹操作
    private func processRenameFolderOperation(_ operation: OfflineOperation) async throws {
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let newName = operationData["name"] as? String,
              let existingTag = operationData["tag"] as? String else {
            throw NSError(domain: "OfflineProcessor", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"])
        }
        
        // 重命名文件夹
        let response = try await service.renameFolder(
            folderId: operation.noteId,
            newName: newName,
            existingTag: existingTag,
            originalCreateDate: nil
        )
        
        guard isResponseSuccess(response),
              let entry = extractEntry(from: response) else {
            let message = extractErrorMessage(from: response, defaultMessage: "重命名文件夹失败")
            throw NSError(domain: "OfflineProcessor", code: 500, userInfo: [NSLocalizedDescriptionKey: message])
        }
        
        // 更新本地文件夹
        let folders = try? DatabaseService.shared.loadFolders()
        if let folder = folders?.first(where: { $0.id == operation.noteId }) {
            var updatedRawData = folder.rawData ?? [:]
            for (key, value) in entry {
                updatedRawData[key] = value
            }
            updatedRawData["tag"] = extractTag(from: response, fallbackTag: existingTag)
            updatedRawData["subject"] = newName
            
            let updatedFolder = Folder(
                id: folder.id,
                name: newName,
                count: folder.count,
                isSystem: folder.isSystem,
                isPinned: folder.isPinned,
                createdAt: folder.createdAt,
                rawData: updatedRawData
            )
            
            try DatabaseService.shared.saveFolder(updatedFolder)
        }
        
        print("[OfflineProcessor] ✅ 成功重命名文件夹: \(operation.noteId)")
    }
    
    /// 处理删除文件夹操作
    private func processDeleteFolderOperation(_ operation: OfflineOperation) async throws {
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let tag = operationData["tag"] as? String else {
            throw NSError(domain: "OfflineProcessor", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"])
        }
        
        // 删除文件夹
        _ = try await service.deleteFolder(folderId: operation.noteId, tag: tag)
        
        print("[OfflineProcessor] ✅ 成功删除文件夹: \(operation.noteId)")
    }
    
    // MARK: - 辅助方法
    
    /// 检查响应是否成功
    private func isResponseSuccess(_ response: [String: Any]) -> Bool {
        if let code = response["code"] as? Int {
            return code == 0
        }
        // 如果没有 code 字段，但状态码是 200，也认为成功
        return true
    }
    
    /// 提取错误消息
    private func extractErrorMessage(from response: [String: Any], defaultMessage: String) -> String {
        if let message = response["description"] as? String {
            return message
        }
        if let message = response["message"] as? String {
            return message
        }
        return defaultMessage
    }
    
    /// 提取 entry 数据
    private func extractEntry(from response: [String: Any]) -> [String: Any]? {
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any] {
            return entry
        }
        if let entry = response["entry"] as? [String: Any] {
            return entry
        }
        return nil
    }
    
    /// 提取 tag 值
    private func extractTag(from response: [String: Any], fallbackTag: String) -> String {
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any],
           let tag = entry["tag"] as? String {
            return tag
        }
        if let entry = response["entry"] as? [String: Any],
           let tag = entry["tag"] as? String {
            return tag
        }
        if let data = response["data"] as? [String: Any],
           let tag = data["tag"] as? String {
            return tag
        }
        return fallbackTag
    }
    
    /// 判断错误是否可重试
    /// 
    /// - Parameter error: 错误对象
    /// - Returns: 是否可重试
    private func isRetryableError(_ error: Error) -> Bool {
        // MiNoteError 分类
        if let miNoteError = error as? MiNoteError {
            switch miNoteError {
            case .cookieExpired, .notAuthenticated:
                // 认证错误：需要用户操作，不可重试
                return false
            case .networkError(let underlyingError):
                // 网络错误：可重试
                if let urlError = underlyingError as? URLError {
                    // 某些 URL 错误不可重试
                    switch urlError.code {
                    case .badURL, .unsupportedURL, .fileDoesNotExist:
                        return false
                    default:
                        return true
                    }
                }
                return true
            case .invalidResponse:
                // 无效响应：可能是临时问题，可重试
                return true
            }
        }
        
        // NSError 分类
        if let nsError = error as NSError? {
            // 笔记不存在（404）：不可重试
            if nsError.code == 404 {
                return false
            }
            
            // 权限错误（403）：不可重试
            if nsError.code == 403 {
                return false
            }
            
            // 服务器错误（5xx）：可重试
            if nsError.code >= 500 && nsError.code < 600 {
                return true
            }
            
            // 网络相关错误：可重试
            if nsError.domain == NSURLErrorDomain {
                let urlErrorCode = URLError.Code(rawValue: nsError.code)
                switch urlErrorCode {
                case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                    return true
                default:
                    return false
                }
            }
        }
        
        // 默认：不可重试（保守策略）
        return false
    }
    
    /// 判断错误是否需要用户操作
    /// 
    /// - Parameter error: 错误对象
    /// - Returns: 是否需要用户操作
    private func requiresUserAction(_ error: Error) -> Bool {
        if let miNoteError = error as? MiNoteError {
            switch miNoteError {
            case .cookieExpired, .notAuthenticated:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    /// 计算重试延迟（指数退避）
    /// 
    /// - Parameter retryCount: 当前重试次数
    /// - Returns: 延迟时间（秒）
    private func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        return initialRetryDelay * pow(2.0, Double(retryCount))
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    /// 离线队列处理完成通知
    static let offlineQueueProcessingCompleted = Notification.Name("offlineQueueProcessingCompleted")
}

