import Combine
import Foundation

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
    private let maxRetryCount = 5

    /// 基础重试延迟（秒）
    ///
    private let baseRetryDelay: TimeInterval = 1.0

    /// 最大重试延迟（秒）
    ///
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

    /// 事件总线
    private let eventBus: EventBus

    // MARK: - 状态

    /// 是否正在处理队列
    private var isProcessingQueue = false

    /// 是否正在处理重试
    private var isProcessingRetries = false

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
        self.syncStateManager = SyncStateManager.createDefault()
        self.eventBus = EventBus.shared
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
    init(
        operationQueue: UnifiedOperationQueue,
        miNoteService: MiNoteService,
        localStorage: LocalStorageService,
        databaseService: DatabaseService,
        networkMonitor: NetworkMonitor,
        syncStateManager: SyncStateManager,
        eventBus: EventBus = EventBus.shared
    ) {
        self.operationQueue = operationQueue
        self.miNoteService = miNoteService
        self.localStorage = localStorage
        self.databaseService = databaseService
        self.networkMonitor = networkMonitor
        self.syncStateManager = syncStateManager
        self.eventBus = eventBus
    }

    // MARK: - 网络状态检查

    /// 检查网络是否连接
    ///
    /// 由于 NetworkMonitor 是 @MainActor 隔离的，需要在主线程上访问
    private func isNetworkConnected() async -> Bool {
        await MainActor.run { networkMonitor.isConnected }
    }

    // MARK: - 公共属性

    /// 获取是否正在处理队列
    public var isProcessing: Bool {
        isProcessingQueue || isProcessingRetries
    }

    /// 获取当前处理的操作 ID
    public var currentOperation: String? {
        currentOperationId
    }
}

// MARK: - 立即处理

public extension OperationProcessor {

    /// 立即处理操作（网络可用时调用）
    ///
    /// 当本地保存完成且网络可用时，立即尝试上传，不经过队列等待。
    ///
    /// - Parameter operation: 要处理的操作
    ///
    func processImmediately(_ operation: NoteOperation) async {
        // 检查网络是否可用
        guard await isNetworkConnected() else {
            return
        }

        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            return
        }

        currentOperationId = operation.id
        defer { currentOperationId = nil }

        do {
            // 标记为处理中
            try operationQueue.markProcessing(operation.id)

            // 执行操作
            try await executeOperation(operation)

            // 标记为完成
            try operationQueue.markCompleted(operation.id)
        } catch {
            LogService.shared.error(.sync, "立即处理操作失败 - 操作ID: \(operation.id), 错误: \(error)")
            // 处理失败
            await handleOperationFailure(operation: operation, error: error)
        }
    }
}

// MARK: - 队列处理

public extension OperationProcessor {

    /// 处理队列中的待处理操作
    ///
    /// 按优先级排序处理所有待处理操作（noteCreate 最高优先级）。
    ///
    func processQueue() async {
        // 防止重复处理
        guard !isProcessingQueue else {
            LogService.shared.debug(.sync, "队列正在处理中，跳过")
            return
        }

        // 检查网络是否可用
        guard await isNetworkConnected() else {
            LogService.shared.debug(.sync, "网络不可用，跳过队列处理")
            return
        }

        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            LogService.shared.debug(.sync, "未认证，跳过队列处理")
            return
        }

        isProcessingQueue = true
        defer { isProcessingQueue = false }

        LogService.shared.info(.sync, "开始处理队列")

        // 获取待处理操作（已按优先级和时间排序）
        let pendingOperations = operationQueue.getPendingOperations()

        guard !pendingOperations.isEmpty else {
            LogService.shared.debug(.sync, "队列为空，无需处理")
            return
        }

        LogService.shared.debug(.sync, "OperationProcessor 待处理操作数量: \(pendingOperations.count)")

        var successCount = 0
        var failureCount = 0

        // 按顺序处理操作
        for operation in pendingOperations {
            // 检查网络状态（可能在处理过程中断开）
            guard await isNetworkConnected() else {
                LogService.shared.warning(.sync, "OperationProcessor 网络断开，停止队列处理")
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
                LogService.shared.debug(.sync, "OperationProcessor 处理成功: \(operation.id), type: \(operation.type.rawValue)")
            } catch {
                failureCount += 1
                await handleOperationFailure(operation: operation, error: error)
            }
        }

        currentOperationId = nil

        LogService.shared.info(.sync, "OperationProcessor 队列处理完成，成功: \(successCount), 失败: \(failureCount)")

        // 确认暂存的 syncTag（如果存在）
        do {
            let confirmed = try await syncStateManager.confirmPendingSyncTagIfNeeded()
            if confirmed {
                LogService.shared.debug(.sync, "OperationProcessor 已确认暂存的 syncTag")
            }
        } catch {
            LogService.shared.warning(.sync, "OperationProcessor 确认 syncTag 失败: \(error.localizedDescription)")
        }

        // 发送处理完成事件
        await eventBus.publish(SyncEvent.completed(result: SyncEventResult(
            downloadedCount: 0,
            uploadedCount: successCount,
            deletedCount: 0,
            duration: 0
        )))
    }
}

// MARK: - 错误分类

public extension OperationProcessor {

    /// 分类错误类型
    ///
    /// 根据错误类型判断是否可重试以及如何处理。
    ///
    /// - Parameter error: 错误对象
    /// - Returns: 错误类型
    ///
    func classifyError(_ error: Error) -> OperationErrorType {
        // 处理 MiNoteError
        if let miNoteError = error as? MiNoteError {
            switch miNoteError {
            case .cookieExpired, .notAuthenticated:
                return .authExpired
            case let .networkError(underlyingError):
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
                case 500 ... 599:
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
            .timeout
        case URLError.notConnectedToInternet.rawValue,
             URLError.networkConnectionLost.rawValue,
             URLError.cannotFindHost.rawValue,
             URLError.cannotConnectToHost.rawValue,
             URLError.dnsLookupFailed.rawValue:
            .network
        case URLError.badServerResponse.rawValue,
             URLError.cannotParseResponse.rawValue:
            .serverError
        case URLError.userAuthenticationRequired.rawValue:
            .authExpired
        default:
            .network
        }
    }

    /// 判断错误是否可重试
    ///
    /// - Parameter error: 错误对象
    /// - Returns: 如果可重试返回 true
    ///
    func isRetryable(_ error: Error) -> Bool {
        let errorType = classifyError(error)
        return errorType.isRetryable
    }

    /// 判断错误是否需要用户操作
    ///
    /// - Parameter error: 错误对象
    /// - Returns: 如果需要用户操作返回 true
    func requiresUserAction(_ error: Error) -> Bool {
        let errorType = classifyError(error)
        return errorType == .authExpired
    }
}

// MARK: - 重试延迟计算

public extension OperationProcessor {

    /// 计算重试延迟（指数退避）
    ///
    /// 延迟序列：1s, 2s, 4s, 8s, 16s, 32s, 60s, 60s...
    ///
    /// - Parameter retryCount: 当前重试次数
    /// - Returns: 延迟时间（秒）
    ///
    func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        // delay = min(baseDelay * 2^retryCount, maxDelay)
        let delay = baseRetryDelay * pow(2.0, Double(retryCount))
        return min(delay, maxRetryDelay)
    }
}

// MARK: - 重试处理

public extension OperationProcessor {

    /// 处理需要重试的操作
    ///
    /// 检查所有失败的操作，如果已到达重试时间则重新处理。
    ///
    func processRetries() async {
        // 防止重复处理
        guard !isProcessingRetries else {
            LogService.shared.debug(.sync, "OperationProcessor 重试正在处理中，跳过")
            return
        }

        // 检查网络是否可用
        guard await isNetworkConnected() else {
            LogService.shared.debug(.sync, "OperationProcessor 网络不可用，跳过重试处理")
            return
        }

        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            LogService.shared.debug(.sync, "OperationProcessor 未认证，跳过重试处理")
            return
        }

        isProcessingRetries = true
        defer { isProcessingRetries = false }

        // 获取需要重试的操作
        let retryOperations = operationQueue.getOperationsReadyForRetry()

        guard !retryOperations.isEmpty else {
            return
        }

        LogService.shared.info(.sync, "OperationProcessor 开始处理重试，数量: \(retryOperations.count)")

        var successCount = 0
        var failureCount = 0

        for operation in retryOperations {
            // 检查网络状态
            guard await isNetworkConnected() else {
                LogService.shared.warning(.sync, "OperationProcessor 网络断开，停止重试处理")
                break
            }

            // 检查是否超过最大重试次数
            guard operation.retryCount < maxRetryCount else {
                LogService.shared.warning(.sync, "OperationProcessor 操作超过最大重试次数: \(operation.id)")
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
                LogService.shared.debug(.sync, "OperationProcessor 重试成功: \(operation.id)")
            } catch {
                failureCount += 1
                await handleOperationFailure(operation: operation, error: error)
            }
        }

        currentOperationId = nil

        if successCount > 0 || failureCount > 0 {
            LogService.shared.info(.sync, "OperationProcessor 重试处理完成，成功: \(successCount), 失败: \(failureCount)")

            // 确认暂存的 syncTag（如果存在）
            do {
                let confirmed = try await syncStateManager.confirmPendingSyncTagIfNeeded()
                if confirmed {
                    LogService.shared.debug(.sync, "OperationProcessor 已确认暂存的 syncTag")
                }
            } catch {
                LogService.shared.warning(.sync, "OperationProcessor 确认 syncTag 失败: \(error.localizedDescription)")
            }
        }
    }

    /// 安排下一次重试检查
    ///
    /// - Parameter delay: 延迟时间（秒）
    func scheduleRetryCheck(delay: TimeInterval = 30.0) async {
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
    private func handleOperationFailure(operation: NoteOperation, error: Error) async {
        let errorType = classifyError(error)
        let isRetryable = errorType.isRetryable

        LogService.shared.error(.sync, "OperationProcessor 操作失败: \(operation.id), 错误类型: \(errorType.rawValue), 可重试: \(isRetryable)")

        do {
            if isRetryable, operation.retryCount < maxRetryCount {
                // 可重试错误：安排重试
                let retryDelay = calculateRetryDelay(retryCount: operation.retryCount)
                try operationQueue.scheduleRetry(operation.id, delay: retryDelay)

                LogService.shared.debug(.sync, "OperationProcessor 安排重试: \(operation.id), 延迟 \(retryDelay) 秒")
            } else if errorType == .authExpired {
                // 认证错误：标记为 authFailed 并通知用户
                try operationQueue.markFailed(operation.id, error: error, errorType: errorType)

                // 发送认证失败事件
                await eventBus.publish(ErrorEvent.authRequired(reason: "操作处理认证失败: \(operation.noteId)"))

                LogService.shared.error(.sync, "OperationProcessor 认证失败，已通知用户: \(operation.id)")
            } else {
                // 不可重试错误或超过最大重试次数：标记为失败
                try operationQueue.markFailed(operation.id, error: error, errorType: errorType)

                LogService.shared.error(.sync, "OperationProcessor 操作最终失败: \(operation.id)")
            }
        } catch {
            LogService.shared.error(.sync, "OperationProcessor 更新操作状态失败: \(error)")
        }
    }

    /// 处理操作成功
    ///
    /// - Parameter operation: 成功的操作
    ///
    private func handleOperationSuccess(operation: NoteOperation) async {
        LogService.shared.debug(.sync, "OperationProcessor 操作成功: \(operation.id), type: \(operation.type.rawValue)")
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
    public func processNoteCreate(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "OperationProcessor 处理 noteCreate: \(operation.noteId)")

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
              let serverNoteId = entry["id"] as? String
        else {
            let message = extractErrorMessage(from: response, defaultMessage: "服务器响应格式不正确")
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let tag = extractTag(from: response, fallbackTag: entry["tag"] as? String ?? serverNoteId)

        // 获取服务器返回的 folderId
        let serverFolderId: String = if let folderIdValue = entry["folderId"] {
            if let folderIdInt = folderIdValue as? Int {
                String(folderIdInt)
            } else if let folderIdStr = folderIdValue as? String {
                folderIdStr
            } else {
                note.folderId
            }
        } else {
            note.folderId
        }

        LogService.shared.info(.sync, "OperationProcessor 云端创建成功: \(operation.noteId) -> \(serverNoteId)")

        // 4. 更新本地笔记
        let serverTag = tag

        // 如果服务器返回的 ID 与本地不同，需要更新
        if note.id != serverNoteId {
            var updatedNote = Note(
                id: serverNoteId,
                title: note.title,
                content: note.content,
                folderId: serverFolderId,
                isStarred: note.isStarred,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                tags: note.tags,
                serverTag: serverTag,
                settingJson: note.settingJson,
                extraInfoJson: note.extraInfoJson
            )

            // 保存新笔记
            await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))

            // 删除旧笔记（临时 ID）
            await eventBus.publish(NoteEvent.deleted(noteId: note.id, tag: nil))

            // 5. 更新操作队列中的 noteId
            try operationQueue.updateNoteIdInPendingOperations(
                oldNoteId: note.id,
                newNoteId: serverNoteId
            )

            // 6. 触发 ID 更新回调
            await onIdMappingCreated?(note.id, serverNoteId)

            // 7. 发送 ID 变更事件
            await eventBus.publish(NoteEvent.saved(updatedNote))

            LogService.shared.info(.sync, "OperationProcessor ID 更新完成: \(note.id) -> \(serverNoteId)")
        } else {
            // ID 相同，只更新 serverTag
            var updatedNote = note
            updatedNote.serverTag = serverTag
            updatedNote.folderId = serverFolderId
            await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
        }
    }

    /// 处理云端上传操作
    ///
    /// - Parameter operation: cloudUpload 操作
    /// - Throws: 执行错误
    private func processCloudUpload(_ operation: NoteOperation) async throws {
        // 从本地加载笔记
        guard let note = try? localStorage.loadNote(noteId: operation.noteId) else {
            throw NSError(
                domain: "OperationProcessor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "笔记不存在: \(operation.noteId)"]
            )
        }

        let existingTag = note.serverTag ?? note.id

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

        // 检测服务器返回的 conflict 标志
        // 当 tag 不匹配时，服务器返回 conflict: true 且新 tag 等于旧 tag（实际未更新）
        let isConflict: Bool = if let data = response["data"] as? [String: Any],
                                  let conflict = data["conflict"] as? Bool
        {
            conflict
        } else {
            false
        }

        let newTag: String = if let data = response["data"] as? [String: Any],
                                let tag = data["tag"] as? String
        {
            tag
        } else {
            existingTag
        }

        if isConflict {
            // 服务器拒绝了更新（tag 不匹配），使用服务器返回的最新 tag 重试
            LogService.shared.warning(.sync, "云端上传冲突，使用服务器最新 tag 重试: \(operation.noteId.prefix(8))...")

            // 用服务器返回的正确 tag 更新
            await propagateServerTag(newTag, forNoteId: note.id)

            // 使用正确的 tag 重新上传
            let retryResponse = try await miNoteService.updateNote(
                noteId: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId,
                existingTag: newTag
            )

            guard isResponseSuccess(retryResponse) else {
                let message = extractErrorMessage(from: retryResponse, defaultMessage: "重试上传失败")
                throw NSError(
                    domain: "OperationProcessor",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }

            // 提取重试后的 tag
            let retryTag: String = if let data = retryResponse["data"] as? [String: Any],
                                      let tag = data["tag"] as? String
            {
                tag
            } else {
                newTag
            }

            // 保存重试后的 tag
            await propagateServerTag(retryTag, forNoteId: note.id)

            LogService.shared.info(.sync, "云端上传冲突重试成功: \(operation.noteId.prefix(8))...")
            return
        }

        // 正常成功路径：传播新 tag 到 NoteStore 和内存
        await propagateServerTag(newTag, forNoteId: note.id)

        LogService.shared.info(.sync, "云端上传成功: \(operation.noteId.prefix(8))...")
    }

    /// 将服务器返回的新 tag 传播到内存中的 notes 数组
    ///
    /// 解决 tag 过期问题：processCloudUpload 保存新 tag 到数据库后，
    /// 内存中的 viewModel.notes 仍持有旧 tag，导致下次编辑保存时覆盖数据库中的新 tag
    private func propagateServerTag(_ newTag: String, forNoteId noteId: String) async {
        await eventBus.publish(SyncEvent.tagUpdated(noteId: noteId, newTag: newTag))
    }

    /// 处理云端删除操作
    ///
    /// - Parameter operation: cloudDelete 操作
    /// - Throws: 执行错误
    private func processCloudDelete(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "OperationProcessor 处理 cloudDelete: \(operation.noteId)")

        // 从操作数据中解析 tag
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let tag = operationData["tag"] as? String
        else {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的删除操作数据"]
            )
        }

        // 调用 API 删除笔记
        _ = try await miNoteService.deleteNote(noteId: operation.noteId, tag: tag, purge: false)

        LogService.shared.info(.sync, "OperationProcessor 删除成功: \(operation.noteId)")
    }

    /// 处理图片上传操作
    ///
    /// - Parameter operation: imageUpload 操作
    /// - Throws: 执行错误
    private func processImageUpload(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "OperationProcessor 处理 imageUpload: \(operation.noteId)")
        // 图片上传通常在更新笔记时一起处理
    }

    /// 处理创建文件夹操作
    ///
    /// - Parameter operation: folderCreate 操作
    /// - Throws: 执行错误
    private func processFolderCreate(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "OperationProcessor 处理 folderCreate: \(operation.noteId)")

        // 从操作数据中解析文件夹名称
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let folderName = operationData["name"] as? String
        else {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }

        // 调用 API 创建文件夹
        let response = try await miNoteService.createFolder(name: folderName)

        guard isResponseSuccess(response),
              let entry = extractEntry(from: response)
        else {
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
              let subject = entry["subject"] as? String
        else {
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
                await eventBus.publish(SyncEvent.noteDownloaded(updatedNote))
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

        LogService.shared.info(.sync, "OperationProcessor 创建文件夹成功: \(operation.noteId) -> \(folderId)")
    }

    /// 处理重命名文件夹操作
    ///
    /// - Parameter operation: folderRename 操作
    /// - Throws: 执行错误
    private func processFolderRename(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "OperationProcessor 处理 folderRename: \(operation.noteId)")

        // 从操作数据中解析参数
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let newName = operationData["name"] as? String,
              let existingTag = operationData["tag"] as? String
        else {
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

        LogService.shared.info(.sync, "OperationProcessor 重命名文件夹成功: \(operation.noteId)")
    }

    /// 处理删除文件夹操作
    ///
    /// - Parameter operation: folderDelete 操作
    /// - Throws: 执行错误
    private func processFolderDelete(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "OperationProcessor 处理 folderDelete: \(operation.noteId)")

        // 从操作数据中解析 tag
        guard let operationData = try? JSONSerialization.jsonObject(with: operation.data) as? [String: Any],
              let tag = operationData["tag"] as? String
        else {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }

        // 调用 API 删除文件夹
        _ = try await miNoteService.deleteFolder(folderId: operation.noteId, tag: tag, purge: false)

        LogService.shared.info(.sync, "OperationProcessor 删除文件夹成功: \(operation.noteId)")
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
           let entry = data["entry"] as? [String: Any]
        {
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
           let tag = entry["tag"] as? String
        {
            return tag
        }

        // 尝试从 entry.tag 获取
        if let entry = response["entry"] as? [String: Any],
           let tag = entry["tag"] as? String
        {
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
           let message = data["message"] as? String
        {
            return message
        }

        return defaultMessage
    }
}

// MARK: - 启动时处理

public extension OperationProcessor {

    /// 启动时处理离线队列
    ///
    /// 专门用于应用启动时的离线队列处理。
    ///
    /// - Returns: 处理结果，包含成功和失败的操作数量
    func processOperationsAtStartup() async -> (successCount: Int, failureCount: Int) {
        LogService.shared.info(.sync, "OperationProcessor 启动时处理离线队列")

        // 检查网络是否可用
        guard await isNetworkConnected() else {
            LogService.shared.debug(.sync, "OperationProcessor 网络不可用，跳过启动处理")
            return (0, 0)
        }

        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            LogService.shared.debug(.sync, "OperationProcessor 未认证，跳过启动处理")
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
