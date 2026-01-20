import Foundation
import Combine

// MARK: - 操作处理器

/// 操作处理器
///
/// 负责执行统一操作队列中的操作，包括：
/// - 立即处理（网络可用时）
/// - 队列处理（批量处理待处理操作）
/// - 重试处理（处理需要重试的操作）
/// - 错误分类和处理
/// - 指数退避重试策略
public actor OperationProcessor {
    
    // MARK: - 单例
    
    /// 共享实例
    /// 
    /// 注意：由于 NetworkMonitor 是 @MainActor 隔离的，
    /// 需要在 MainActor 上初始化此单例
    @MainActor
    public static let shared = OperationProcessor()
    
    // MARK: - 重试配置
    
    /// 最大重试次数
    ///
    /// 需求: 5.2
    private let maxRetryCount: Int = 5
    
    /// 基础重试延迟（秒）
    ///
    /// 需求: 5.2
    private let baseRetryDelay: TimeInterval = 1.0
    
    /// 最大重试延迟（秒）
    ///
    /// 需求: 5.2
    private let maxRetryDelay: TimeInterval = 60.0
    
    // MARK: - 依赖
    
    /// 统一操作队列
    private let operationQueue: UnifiedOperationQueue
    
    /// 小米笔记服务
    private let miNoteService: MiNoteService
    
    /// 本地存储服务
    private let localStorage: LocalStorageService
    
    /// 数据库服务
    private let databaseService: DatabaseService
    
    /// 网络监控
    private let networkMonitor: NetworkMonitor
    
    /// 同步状态管理器
    private let syncStateManager: SyncStateManager
    
    // MARK: - 状态
    
    /// 是否正在处理队列
    private var isProcessingQueue: Bool = false
    
    /// 是否正在处理重试
    private var isProcessingRetries: Bool = false
    
    /// 当前正在处理的操作 ID
    private var currentOperationId: String?
    
    // MARK: - 回调
    
    /// ID 更新回调（临时 ID -> 正式 ID）
    /// 用于通知外部组件更新 ID 引用
    public var onIdMappingCreated: ((String, String) async -> Void)?
    
    // MARK: - 初始化
    
    /// 私有初始化方法（单例模式）
    @MainActor
    private init() {
        self.operationQueue = UnifiedOperationQueue.shared
        self.miNoteService = MiNoteService.shared
        self.localStorage = LocalStorageService.shared
        self.databaseService = DatabaseService.shared
        self.networkMonitor = NetworkMonitor.shared
        self.syncStateManager = SyncStateManager()
    }
    
    /// 用于测试的初始化方法
    ///
    /// - Parameters:
    ///   - operationQueue: 操作队列实例
    ///   - miNoteService: 小米笔记服务实例
    ///   - localStorage: 本地存储服务实例
    ///   - databaseService: 数据库服务实例
    ///   - networkMonitor: 网络监控实例
    ///   - syncStateManager: 同步状态管理器实例
    internal init(
        operationQueue: UnifiedOperationQueue,
        miNoteService: MiNoteService,
        localStorage: LocalStorageService,
        databaseService: DatabaseService,
        networkMonitor: NetworkMonitor,
        syncStateManager: SyncStateManager
    ) {
        self.operationQueue = operationQueue
        self.miNoteService = miNoteService
        self.localStorage = localStorage
        self.databaseService = databaseService
        self.networkMonitor = networkMonitor
        self.syncStateManager = syncStateManager
    }
    
    // MARK: - 网络状态检查
    
    /// 检查网络是否连接
    ///
    /// 由于 NetworkMonitor 是 @MainActor 隔离的，需要在主线程上访问
    private func isNetworkConnected() async -> Bool {
        return await MainActor.run { networkMonitor.isConnected }
    }
    
    // MARK: - 公共属性
    
    /// 获取是否正在处理队列
    public var isProcessing: Bool {
        return isProcessingQueue || isProcessingRetries
    }
    
    /// 获取当前处理的操作 ID
    public var currentOperation: String? {
        return currentOperationId
    }
}


// MARK: - 立即处理

extension OperationProcessor {
    
    /// 立即处理操作（网络可用时调用）
    ///
    /// 当本地保存完成且网络可用时，立即尝试上传，不经过队列等待。
    ///
    /// - Parameter operation: 要处理的操作
    ///
    /// 需求: 2.1
    public func processImmediately(_ operation: NoteOperation) async {
        // 检查网络是否可用
        guard await isNetworkConnected() else {
            print("[OperationProcessor] 网络不可用，跳过立即处理: \(operation.id)")
            return
        }
        
        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            print("[OperationProcessor] 未认证，跳过立即处理: \(operation.id)")
            return
        }
        
        print("[OperationProcessor] 🚀 立即处理操作: \(operation.type.rawValue) for \(operation.noteId)")
        
        currentOperationId = operation.id
        defer { currentOperationId = nil }
        
        do {
            // 标记为处理中
            try operationQueue.markProcessing(operation.id)
            
            // 执行操作
            try await executeOperation(operation)
            
            // 标记为完成
            try operationQueue.markCompleted(operation.id)
            
            print("[OperationProcessor] ✅ 立即处理成功: \(operation.id)")
            
        } catch {
            // 处理失败
            await handleOperationFailure(operation: operation, error: error)
        }
    }
}

// MARK: - 队列处理

extension OperationProcessor {
    
    /// 处理队列中的待处理操作
    ///
    /// 按优先级排序处理所有待处理操作（noteCreate 最高优先级）。
    ///
    /// 需求: 2.1
    public func processQueue() async {
        // 防止重复处理
        guard !isProcessingQueue else {
            print("[OperationProcessor] 队列正在处理中，跳过")
            return
        }
        
        // 检查网络是否可用
        guard await isNetworkConnected() else {
            print("[OperationProcessor] 网络不可用，跳过队列处理")
            return
        }
        
        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            print("[OperationProcessor] 未认证，跳过队列处理")
            return
        }
        
        isProcessingQueue = true
        defer { isProcessingQueue = false }
        
        print("[OperationProcessor] 📋 开始处理队列...")
        
        // 获取待处理操作（已按优先级和时间排序）
        let pendingOperations = operationQueue.getPendingOperations()
        
        guard !pendingOperations.isEmpty else {
            print("[OperationProcessor] 队列为空，无需处理")
            return
        }
        
        print("[OperationProcessor] 待处理操作数量: \(pendingOperations.count)")
        
        var successCount = 0
        var failureCount = 0
        
        // 按顺序处理操作
        for operation in pendingOperations {
            // 检查网络状态（可能在处理过程中断开）
            guard await isNetworkConnected() else {
                print("[OperationProcessor] ⚠️ 网络断开，停止队列处理")
                break
            }
            
            // 跳过已经在处理中的操作
            guard operation.status != .processing else {
                continue
            }
            
            currentOperationId = operation.id
            
            do {
                // 标记为处理中
                try operationQueue.markProcessing(operation.id)
                
                // 执行操作
                try await executeOperation(operation)
                
                // 标记为完成
                try operationQueue.markCompleted(operation.id)
                
                successCount += 1
                print("[OperationProcessor] ✅ 处理成功: \(operation.id), type: \(operation.type.rawValue)")
                
            } catch {
                failureCount += 1
                await handleOperationFailure(operation: operation, error: error)
            }
        }
        
        currentOperationId = nil
        
        print("[OperationProcessor] 📋 队列处理完成，成功: \(successCount), 失败: \(failureCount)")
        
        // 确认暂存的 syncTag（如果存在）
        do {
            let confirmed = try await syncStateManager.confirmPendingSyncTagIfNeeded()
            if confirmed {
                print("[OperationProcessor] ✅ 已确认暂存的 syncTag")
            }
        } catch {
            print("[OperationProcessor] ⚠️ 确认 syncTag 失败: \(error.localizedDescription)")
        }
        
        // 发送处理完成通知
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("OperationQueueProcessingCompleted"),
                object: nil,
                userInfo: [
                    "successCount": successCount,
                    "failureCount": failureCount
                ]
            )
        }
    }
}


// MARK: - 错误分类

extension OperationProcessor {
    
    /// 分类错误类型
    ///
    /// 根据错误类型判断是否可重试以及如何处理。
    ///
    /// - Parameter error: 错误对象
    /// - Returns: 错误类型
    ///
    /// 需求: 5.1
    public func classifyError(_ error: Error) -> OperationErrorType {
        // 处理 MiNoteError
        if let miNoteError = error as? MiNoteError {
            switch miNoteError {
            case .cookieExpired, .notAuthenticated:
                return .authExpired
            case .networkError(let underlyingError):
                return classifyURLError(underlyingError)
            case .invalidResponse:
                return .serverError
            }
        }
        
        // 处理 URLError
        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }
        
        // 处理 NSError
        if let nsError = error as? NSError {
            // 检查 HTTP 状态码
            if nsError.domain == "MiNoteService" {
                switch nsError.code {
                case 401:
                    return .authExpired
                case 404:
                    return .notFound
                case 409:
                    return .conflict
                case 500...599:
                    return .serverError
                default:
                    return .unknown
                }
            }
            
            // 检查网络错误
            if nsError.domain == NSURLErrorDomain {
                return classifyURLErrorCode(nsError.code)
            }
        }
        
        return .unknown
    }
    
    /// 分类 URLError
    ///
    /// - Parameter error: URLError 或其他 Error
    /// - Returns: 错误类型
    private func classifyURLError(_ error: Error) -> OperationErrorType {
        if let urlError = error as? URLError {
            return classifyURLErrorCode(urlError.code.rawValue)
        }
        return .network
    }
    
    /// 根据 URLError 代码分类错误
    ///
    /// - Parameter code: URLError 代码
    /// - Returns: 错误类型
    private func classifyURLErrorCode(_ code: Int) -> OperationErrorType {
        switch code {
        case URLError.timedOut.rawValue:
            return .timeout
        case URLError.notConnectedToInternet.rawValue,
             URLError.networkConnectionLost.rawValue,
             URLError.cannotFindHost.rawValue,
             URLError.cannotConnectToHost.rawValue,
             URLError.dnsLookupFailed.rawValue:
            return .network
        case URLError.badServerResponse.rawValue,
             URLError.cannotParseResponse.rawValue:
            return .serverError
        case URLError.userAuthenticationRequired.rawValue:
            return .authExpired
        default:
            return .network
        }
    }
    
    /// 判断错误是否可重试
    ///
    /// - Parameter error: 错误对象
    /// - Returns: 如果可重试返回 true
    ///
    /// 需求: 5.1
    public func isRetryable(_ error: Error) -> Bool {
        let errorType = classifyError(error)
        return errorType.isRetryable
    }
    
    /// 判断错误是否需要用户操作
    ///
    /// - Parameter error: 错误对象
    /// - Returns: 如果需要用户操作返回 true
    public func requiresUserAction(_ error: Error) -> Bool {
        let errorType = classifyError(error)
        return errorType == .authExpired
    }
}

// MARK: - 重试延迟计算

extension OperationProcessor {
    
    /// 计算重试延迟（指数退避）
    ///
    /// 延迟序列：1s, 2s, 4s, 8s, 16s, 32s, 60s, 60s...
    ///
    /// - Parameter retryCount: 当前重试次数
    /// - Returns: 延迟时间（秒）
    ///
    /// 需求: 5.2
    public func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        // delay = min(baseDelay * 2^retryCount, maxDelay)
        let delay = baseRetryDelay * pow(2.0, Double(retryCount))
        return min(delay, maxRetryDelay)
    }
}


// MARK: - 重试处理

extension OperationProcessor {
    
    /// 处理需要重试的操作
    ///
    /// 检查所有失败的操作，如果已到达重试时间则重新处理。
    ///
    /// 需求: 5.2
    public func processRetries() async {
        // 防止重复处理
        guard !isProcessingRetries else {
            print("[OperationProcessor] 重试正在处理中，跳过")
            return
        }
        
        // 检查网络是否可用
        guard await isNetworkConnected() else {
            print("[OperationProcessor] 网络不可用，跳过重试处理")
            return
        }
        
        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            print("[OperationProcessor] 未认证，跳过重试处理")
            return
        }
        
        isProcessingRetries = true
        defer { isProcessingRetries = false }
        
        // 获取需要重试的操作
        let retryOperations = operationQueue.getOperationsReadyForRetry()
        
        guard !retryOperations.isEmpty else {
            return
        }
        
        print("[OperationProcessor] 🔄 开始处理重试，数量: \(retryOperations.count)")
        
        var successCount = 0
        var failureCount = 0
        
        for operation in retryOperations {
            // 检查网络状态
            guard await isNetworkConnected() else {
                print("[OperationProcessor] ⚠️ 网络断开，停止重试处理")
                break
            }
            
            // 检查是否超过最大重试次数
            guard operation.retryCount < maxRetryCount else {
                print("[OperationProcessor] ⚠️ 操作超过最大重试次数: \(operation.id)")
                continue
            }
            
            currentOperationId = operation.id
            
            do {
                // 标记为处理中
                try operationQueue.markProcessing(operation.id)
                
                // 执行操作
                try await executeOperation(operation)
                
                // 标记为完成
                try operationQueue.markCompleted(operation.id)
                
                successCount += 1
                print("[OperationProcessor] ✅ 重试成功: \(operation.id)")
                
            } catch {
                failureCount += 1
                await handleOperationFailure(operation: operation, error: error)
            }
        }
        
        currentOperationId = nil
        
        if successCount > 0 || failureCount > 0 {
            print("[OperationProcessor] 🔄 重试处理完成，成功: \(successCount), 失败: \(failureCount)")
            
            // 确认暂存的 syncTag（如果存在）
            do {
                let confirmed = try await syncStateManager.confirmPendingSyncTagIfNeeded()
                if confirmed {
                    print("[OperationProcessor] ✅ 已确认暂存的 syncTag")
                }
            } catch {
                print("[OperationProcessor] ⚠️ 确认 syncTag 失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 安排下一次重试检查
    ///
    /// - Parameter delay: 延迟时间（秒）
    public func scheduleRetryCheck(delay: TimeInterval = 30.0) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await processRetries()
    }
}


// MARK: - 成功/失败处理

extension OperationProcessor {
    
    /// 处理操作失败
    ///
    /// 根据错误类型决定是否重试或标记为最终失败。
    ///
    /// - Parameters:
    ///   - operation: 失败的操作
    ///   - error: 错误对象
    ///
    /// 需求: 2.2, 2.3, 2.4
    private func handleOperationFailure(operation: NoteOperation, error: Error) async {
        let errorType = classifyError(error)
        let isRetryable = errorType.isRetryable
        
        print("[OperationProcessor] ❌ 操作失败: \(operation.id), 错误类型: \(errorType.rawValue), 可重试: \(isRetryable)")
        
        do {
            if isRetryable && operation.retryCount < maxRetryCount {
                // 可重试错误：安排重试
                // 需求: 2.3 - 上传失败（网络错误）时保留在队列中等待重试
                let retryDelay = calculateRetryDelay(retryCount: operation.retryCount)
                try operationQueue.scheduleRetry(operation.id, delay: retryDelay)
                
                print("[OperationProcessor] ⏳ 安排重试: \(operation.id), 延迟 \(retryDelay) 秒")
                
            } else if errorType == .authExpired {
                // 认证错误：标记为 authFailed 并通知用户
                // 需求: 2.4 - 上传失败（认证错误）时标记为 authFailed 并通知用户
                try operationQueue.markFailed(operation.id, error: error, errorType: errorType)
                
                // 发送认证失败通知
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OperationAuthFailed"),
                        object: nil,
                        userInfo: [
                            "operationId": operation.id,
                            "noteId": operation.noteId
                        ]
                    )
                }
                
                print("[OperationProcessor] 🔐 认证失败，已通知用户: \(operation.id)")
                
            } else {
                // 不可重试错误或超过最大重试次数：标记为失败
                try operationQueue.markFailed(operation.id, error: error, errorType: errorType)
                
                print("[OperationProcessor] ⛔ 操作最终失败: \(operation.id)")
            }
        } catch {
            print("[OperationProcessor] ⚠️ 更新操作状态失败: \(error)")
        }
    }
    
    /// 处理操作成功
    ///
    /// - Parameter operation: 成功的操作
    ///
    /// 需求: 2.2
    private func handleOperationSuccess(operation: NoteOperation) async {
        print("[OperationProcessor] ✅ 操作成功: \(operation.id), type: \(operation.type.rawValue)")
        
        // 发送成功通知
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("OperationCompleted"),
                object: nil,
                userInfo: [
                    "operationId": operation.id,
                    "noteId": operation.noteId,
                    "type": operation.type.rawValue
                ]
            )
        }
    }
}


// MARK: - 操作执行

extension OperationProcessor {
    
    /// 执行操作
    ///
    /// 根据操作类型调用相应的处理方法。
    ///
    /// - Parameter operation: 要执行的操作
    /// - Throws: 执行错误
    private func executeOperation(_ operation: NoteOperation) async throws {
        switch operation.type {
        case .noteCreate:
            try await processNoteCreate(operation)
        case .cloudUpload:
            try await processCloudUpload(operation)
        case .cloudDelete:
            try await processCloudDelete(operation)
        case .imageUpload:
            try await processImageUpload(operation)
        case .folderCreate:
            try await processFolderCreate(operation)
        case .folderRename:
            try await processFolderRename(operation)
        case .folderDelete:
            try await processFolderDelete(operation)
        }
    }
    
    /// 处理离线创建笔记操作
    ///
    /// 将离线创建的笔记上传到云端，获取云端下发的正式 ID，
    /// 然后触发 ID 更新流程。
    ///
    /// - Parameter operation: noteCreate 操作
    /// - Throws: 执行错误
    ///
    /// 需求: 8.4
    public func processNoteCreate(_ operation: NoteOperation) async throws {
        print("[OperationProcessor] 📝 处理 noteCreate: \(operation.noteId)")
        
        // 1. 从本地加载笔记
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            throw NSError(
                domain: "OperationProcessor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "笔记不存在: \(operation.noteId)"]
            )
        }
        
        // 2. 调用 API 创建笔记
        let response = try await miNoteService.createNote(
            title: note.title,
            content: note.content,
            folderId: note.folderId
        )
        
        // 3. 解析响应，获取云端下发的正式 ID
        guard isResponseSuccess(response),
              let entry = extractEntry(from: response),
              let serverNoteId = entry["id"] as? String else {
            let message = extractErrorMessage(from: response, defaultMessage: "服务器响应格式不正确")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
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
        
        print("[OperationProcessor] 📝 云端创建成功: \(operation.noteId) -> \(serverNoteId)")
        
        // 4. 更新本地笔记
        var updatedRawData = note.rawData ?? [:]
        for (key, value) in entry {
            updatedRawData[key] = value
        }
        updatedRawData["tag"] = tag
        
        // 如果服务器返回的 ID 与本地不同，需要更新
        if note.id != serverNoteId {
            // 创建新笔记（使用正式 ID）
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
            
            // 保存新笔记
            try localStorage.saveNote(updatedNote)
            
            // 删除旧笔记（临时 ID）
            try? localStorage.deleteNote(noteId: note.id)
            
            // 5. 更新操作队列中的 noteId
            try operationQueue.updateNoteIdInPendingOperations(
                oldNoteId: note.id,
                newNoteId: serverNoteId
            )
            
            // 6. 触发 ID 更新回调
            await onIdMappingCreated?(note.id, serverNoteId)
            
            // 7. 发送 ID 变更通知
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("NoteIdChanged"),
                    object: nil,
                    userInfo: [
                        "oldId": note.id,
                        "newId": serverNoteId
                    ]
                )
            }
            
            print("[OperationProcessor] 📝 ID 更新完成: \(note.id) -> \(serverNoteId)")
        } else {
            // ID 相同，只更新 rawData
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
    }
    
    /// 处理云端上传操作
    ///
    /// - Parameter operation: cloudUpload 操作
    /// - Throws: 执行错误
    private func processCloudUpload(_ operation: NoteOperation) async throws {
        print("[OperationProcessor] ☁️ 处理 cloudUpload: \(operation.noteId)")
        
        // 从本地加载笔记
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            throw NSError(
                domain: "OperationProcessor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "笔记不存在: \(operation.noteId)"]
            )
        }
        
        // 获取现有的 tag（从 serverTag 字段，而不是 rawData）
        let existingTag = note.serverTag ?? note.id
        print("[OperationProcessor] 🏷️ 使用 tag: \(existingTag), serverTag: \(note.serverTag ?? "nil")")
        
        // 调用 API 更新笔记
        let response = try await miNoteService.updateNote(
            noteId: note.id,
            title: note.title,
            content: note.content,
            folderId: note.folderId,
            existingTag: existingTag
        )
        
        // 验证响应
        guard isResponseSuccess(response) else {
            let message = extractErrorMessage(from: response, defaultMessage: "更新笔记失败")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        
        // 更新本地笔记的 rawData 和 serverTag
        if let entry = extractEntry(from: response) {
            var updatedRawData = note.rawData ?? [:]
            for (key, value) in entry {
                updatedRawData[key] = value
            }
            
            // 从响应中提取新的 tag
            let newTag = extractTag(from: response, fallbackTag: entry["tag"] as? String ?? existingTag)
            print("[OperationProcessor] 📥 服务器返回新 tag: \(newTag)")
            
            let updatedNote = Note(
                id: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId,
                isStarred: note.isStarred,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                tags: note.tags,
                rawData: updatedRawData,
                snippet: note.snippet,
                colorId: note.colorId,
                subject: note.subject,
                alertDate: note.alertDate,
                type: note.type,
                serverTag: newTag,  // 更新 serverTag
                status: note.status,
                settingJson: note.settingJson,
                extraInfoJson: note.extraInfoJson
            )
            try localStorage.saveNote(updatedNote)
        }
        
        print("[OperationProcessor] ☁️ 上传成功: \(operation.noteId)")
    }
    
    /// 处理云端删除操作
    ///
    /// - Parameter operation: cloudDelete 操作
    /// - Throws: 执行错误
    private func processCloudDelete(_ operation: NoteOperation) async throws {
        print("[OperationProcessor] 🗑️ 处理 cloudDelete: \(operation.noteId)")
        
        // 从操作数据中解析 tag
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let tag = operationData["tag"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的删除操作数据"]
            )
        }
        
        // 调用 API 删除笔记
        _ = try await miNoteService.deleteNote(noteId: operation.noteId, tag: tag, purge: false)
        
        print("[OperationProcessor] 🗑️ 删除成功: \(operation.noteId)")
    }
    
    /// 处理图片上传操作
    ///
    /// - Parameter operation: imageUpload 操作
    /// - Throws: 执行错误
    private func processImageUpload(_ operation: NoteOperation) async throws {
        print("[OperationProcessor] 🖼️ 处理 imageUpload: \(operation.noteId)")
        // 图片上传通常在更新笔记时一起处理
        // 这里可以添加独立的图片上传逻辑
        print("[OperationProcessor] 🖼️ 图片上传操作（已在更新笔记时处理）")
    }
    
    /// 处理创建文件夹操作
    ///
    /// - Parameter operation: folderCreate 操作
    /// - Throws: 执行错误
    private func processFolderCreate(_ operation: NoteOperation) async throws {
        print("[OperationProcessor] 📁 处理 folderCreate: \(operation.noteId)")
        
        // 从操作数据中解析文件夹名称
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let folderName = operationData["name"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }
        
        // 调用 API 创建文件夹
        let response = try await miNoteService.createFolder(name: folderName)
        
        guard isResponseSuccess(response),
              let entry = extractEntry(from: response) else {
            let message = extractErrorMessage(from: response, defaultMessage: "创建文件夹失败")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        
        // 处理服务器返回的文件夹 ID
        var serverFolderId: String?
        if let idString = entry["id"] as? String {
            serverFolderId = idString
        } else if let idInt = entry["id"] as? Int {
            serverFolderId = String(idInt)
        }
        
        guard let folderId = serverFolderId,
              let subject = entry["subject"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "服务器返回无效的文件夹信息"]
            )
        }
        
        // 如果服务器返回的 ID 与本地不同，需要更新本地文件夹和笔记
        if operation.noteId != folderId {
            // 更新所有使用旧文件夹 ID 的笔记
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
        
        try databaseService.saveFolder(folder)
        
        print("[OperationProcessor] 📁 创建文件夹成功: \(operation.noteId) -> \(folderId)")
    }
    
    /// 处理重命名文件夹操作
    ///
    /// - Parameter operation: folderRename 操作
    /// - Throws: 执行错误
    private func processFolderRename(_ operation: NoteOperation) async throws {
        print("[OperationProcessor] 📁 处理 folderRename: \(operation.noteId)")
        
        // 从操作数据中解析参数
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let newName = operationData["name"] as? String,
              let existingTag = operationData["tag"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }
        
        // 调用 API 重命名文件夹
        let response = try await miNoteService.renameFolder(
            folderId: operation.noteId,
            newName: newName,
            existingTag: existingTag,
            originalCreateDate: nil
        )
        
        guard isResponseSuccess(response) else {
            let message = extractErrorMessage(from: response, defaultMessage: "重命名文件夹失败")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        
        // 更新本地文件夹
        if let entry = extractEntry(from: response) {
            let folders = try? databaseService.loadFolders()
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
                
                try databaseService.saveFolder(updatedFolder)
            }
        }
        
        print("[OperationProcessor] 📁 重命名文件夹成功: \(operation.noteId)")
    }
    
    /// 处理删除文件夹操作
    ///
    /// - Parameter operation: folderDelete 操作
    /// - Throws: 执行错误
    private func processFolderDelete(_ operation: NoteOperation) async throws {
        print("[OperationProcessor] 📁 处理 folderDelete: \(operation.noteId)")
        
        // 从操作数据中解析 tag
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let tag = operationData["tag"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }
        
        // 调用 API 删除文件夹
        _ = try await miNoteService.deleteFolder(folderId: operation.noteId, tag: tag, purge: false)
        
        print("[OperationProcessor] 📁 删除文件夹成功: \(operation.noteId)")
    }
}


// MARK: - 响应解析辅助方法

extension OperationProcessor {
    
    /// 检查响应是否成功
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: 如果成功返回 true
    private func isResponseSuccess(_ response: [String: Any]) -> Bool {
        // 检查 code 字段
        if let code = response["code"] as? Int {
            return code == 0
        }
        
        // 检查 R 字段（某些 API 使用）
        if let r = response["R"] as? String {
            return r == "ok" || r == "OK"
        }
        
        // 如果没有错误标识，假设成功
        return true
    }
    
    /// 从响应中提取 entry
    ///
    /// - Parameter response: API 响应字典
    /// - Returns: entry 字典，如果不存在返回 nil
    private func extractEntry(from response: [String: Any]) -> [String: Any]? {
        // 尝试从 data.entry 获取
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any] {
            return entry
        }
        
        // 尝试直接从 entry 获取
        if let entry = response["entry"] as? [String: Any] {
            return entry
        }
        
        return nil
    }
    
    /// 从响应中提取 tag
    ///
    /// - Parameters:
    ///   - response: API 响应字典
    ///   - fallbackTag: 备用 tag
    /// - Returns: tag 字符串
    private func extractTag(from response: [String: Any], fallbackTag: String) -> String {
        // 尝试从 data.entry.tag 获取
        if let data = response["data"] as? [String: Any],
           let entry = data["entry"] as? [String: Any],
           let tag = entry["tag"] as? String {
            return tag
        }
        
        // 尝试从 entry.tag 获取
        if let entry = response["entry"] as? [String: Any],
           let tag = entry["tag"] as? String {
            return tag
        }
        
        // 尝试从顶层 tag 获取
        if let tag = response["tag"] as? String {
            return tag
        }
        
        return fallbackTag
    }
    
    /// 从响应中提取错误信息
    ///
    /// - Parameters:
    ///   - response: API 响应字典
    ///   - defaultMessage: 默认错误信息
    /// - Returns: 错误信息字符串
    private func extractErrorMessage(from response: [String: Any], defaultMessage: String) -> String {
        // 尝试从 description 获取
        if let description = response["description"] as? String {
            return description
        }
        
        // 尝试从 message 获取
        if let message = response["message"] as? String {
            return message
        }
        
        // 尝试从 data.message 获取
        if let data = response["data"] as? [String: Any],
           let message = data["message"] as? String {
            return message
        }
        
        return defaultMessage
    }
}

// MARK: - 启动时处理

extension OperationProcessor {
    
    /// 启动时处理离线队列
    ///
    /// 专门用于应用启动时的离线队列处理。
    ///
    /// - Returns: 处理结果，包含成功和失败的操作数量
    public func processOperationsAtStartup() async -> (successCount: Int, failureCount: Int) {
        print("[OperationProcessor] 🚀 启动时处理离线队列")
        
        // 检查网络是否可用
        guard await isNetworkConnected() else {
            print("[OperationProcessor] 网络不可用，跳过启动处理")
            return (0, 0)
        }
        
        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            print("[OperationProcessor] 未认证，跳过启动处理")
            return (0, 0)
        }
        
        // 处理队列
        await processQueue()
        
        // 返回统计信息
        let stats = operationQueue.getStatistics()
        let successCount = stats["completed"] ?? 0
        let failureCount = (stats["failed"] ?? 0) + (stats["authFailed"] ?? 0) + (stats["maxRetryExceeded"] ?? 0)
        
        return (successCount, failureCount)
    }
}
