import Combine
import Foundation

// MARK: - 操作处理器

/// 操作处理器（调度层）
///
/// 负责操作的调度、重试和错误分类，具体操作逻辑委托给各 handler：
/// - 立即处理（网络可用时）
/// - 队列处理（批量处理待处理操作）
/// - 重试处理（处理需要重试的操作）
/// - 错误分类和处理
/// - 指数退避重试策略
public actor OperationProcessor {

    // MARK: - 重试配置

    private let maxRetryCount = 8
    private let baseRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 300.0

    // MARK: - 依赖

    private let operationQueue: UnifiedOperationQueue
    private let apiClient: APIClient
    private let syncStateManager: SyncStateManager
    private let eventBus: EventBus
    private let idMappingRegistry: IdMappingRegistry

    /// handler 字典，按操作类型分发
    private let handlers: [OperationType: OperationHandler]

    // MARK: - 状态

    private var isProcessingQueue = false
    private var isProcessingRetries = false
    private var currentOperationId: String?

    // MARK: - 初始化

    init(
        operationQueue: UnifiedOperationQueue,
        apiClient: APIClient,
        syncStateManager: SyncStateManager,
        eventBus: EventBus,
        idMappingRegistry: IdMappingRegistry,
        handlers: [OperationType: OperationHandler]
    ) {
        self.operationQueue = operationQueue
        self.apiClient = apiClient
        self.syncStateManager = syncStateManager
        self.eventBus = eventBus
        self.idMappingRegistry = idMappingRegistry
        self.handlers = handlers
    }

    // MARK: - 网络状态检查

    private func isNetworkConnected() async -> Bool {
        await MainActor.run { NetworkMonitor.shared.isConnected }
    }

    // MARK: - 公共属性

    public var isProcessing: Bool {
        isProcessingQueue || isProcessingRetries
    }

    public var currentOperation: String? {
        currentOperationId
    }
}

// MARK: - 操作执行

extension OperationProcessor {

    /// 根据操作类型查表分发到对应 handler
    private func executeOperation(_ operation: NoteOperation) async throws {
        guard let handler = handlers[operation.type] else {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "不支持的操作类型: \(operation.type.rawValue)"]
            )
        }
        try await handler.handle(operation)
    }
}

// MARK: - 立即处理

public extension OperationProcessor {

    func processImmediately(_ operation: NoteOperation) async {
        guard await isNetworkConnected() else { return }
        guard await apiClient.isAuthenticated() else { return }

        currentOperationId = operation.id
        defer { currentOperationId = nil }

        do {
            try operationQueue.markProcessing(operation.id)
            try await executeOperation(operation)
            try operationQueue.markCompleted(operation.id)
        } catch {
            LogService.shared.error(.sync, "立即处理操作失败 - 操作ID: \(operation.id), 错误: \(error)")
            await handleOperationFailure(operation: operation, error: error)
        }
    }
}

// MARK: - 队列处理

public extension OperationProcessor {

    func processQueue() async {
        guard !isProcessingQueue else {
            LogService.shared.debug(.sync, "队列正在处理中，跳过")
            return
        }

        guard await isNetworkConnected() else {
            LogService.shared.debug(.sync, "网络不可用，跳过队列处理")
            return
        }

        guard await apiClient.isAuthenticated() else {
            LogService.shared.debug(.sync, "未认证，跳过队列处理")
            return
        }

        isProcessingQueue = true
        defer { isProcessingQueue = false }

        LogService.shared.info(.sync, "开始处理队列")

        let pendingOperations = operationQueue.getPendingOperations()

        guard !pendingOperations.isEmpty else {
            LogService.shared.debug(.sync, "队列为空，无需处理")
            return
        }

        LogService.shared.debug(.sync, "OperationProcessor 待处理操作数量: \(pendingOperations.count)")

        var successCount = 0
        var failureCount = 0

        for operation in pendingOperations {
            guard await isNetworkConnected() else {
                LogService.shared.warning(.sync, "OperationProcessor 网络断开，停止队列处理")
                break
            }

            guard operation.status != .processing else { continue }

            // noteCreate 和 cloudUpload 必须等同一笔记的文件上传全部完成后再执行
            if operation.type == .cloudUpload || operation.type == .noteCreate {
                let resolvedNoteId = idMappingRegistry.resolveId(operation.noteId)
                if operationQueue.hasPendingFileUpload(for: resolvedNoteId) ||
                    operationQueue.hasPendingFileUpload(for: operation.noteId)
                {
                    LogService.shared.debug(.sync, "跳过 \(operation.type.rawValue)，等待文件上传完成: \(resolvedNoteId.prefix(8))...")
                    continue
                }
            }

            currentOperationId = operation.id

            do {
                try operationQueue.markProcessing(operation.id)
                try await executeOperation(operation)
                try operationQueue.markCompleted(operation.id)
                successCount += 1
                LogService.shared.debug(.sync, "OperationProcessor 处理成功: \(operation.id), type: \(operation.type.rawValue)")
                await eventBus.publish(OperationEvent.operationCompleted)
            } catch {
                failureCount += 1
                let errorType = classifyError(error)
                if errorType == .authExpired {
                    await eventBus.publish(OperationEvent.authFailed)
                }
                await handleOperationFailure(operation: operation, error: error)
            }
        }

        currentOperationId = nil

        LogService.shared.info(.sync, "OperationProcessor 队列处理完成，成功: \(successCount), 失败: \(failureCount)")

        // 处理过程中可能有新操作入队，检查并处理
        let remainingOperations = operationQueue.getPendingOperations()
        if !remainingOperations.isEmpty, await isNetworkConnected() {
            LogService.shared.debug(.sync, "发现新入队的操作，继续处理: \(remainingOperations.count)")
            for operation in remainingOperations {
                guard await isNetworkConnected() else { break }
                guard operation.status != .processing else { continue }

                if operation.type == .cloudUpload || operation.type == .noteCreate {
                    let resolvedNoteId = idMappingRegistry.resolveId(operation.noteId)
                    if operationQueue.hasPendingFileUpload(for: resolvedNoteId) ||
                        operationQueue.hasPendingFileUpload(for: operation.noteId)
                    {
                        continue
                    }
                }

                currentOperationId = operation.id
                do {
                    try operationQueue.markProcessing(operation.id)
                    try await executeOperation(operation)
                    try operationQueue.markCompleted(operation.id)
                    successCount += 1
                    await eventBus.publish(OperationEvent.operationCompleted)
                } catch {
                    failureCount += 1
                    let errorType = classifyError(error)
                    if errorType == .authExpired {
                        await eventBus.publish(OperationEvent.authFailed)
                    }
                    await handleOperationFailure(operation: operation, error: error)
                }
            }
            currentOperationId = nil
        }

        // 确认暂存的 syncTag
        do {
            let confirmed = try await syncStateManager.confirmPendingSyncTagIfNeeded()
            if confirmed {
                LogService.shared.debug(.sync, "OperationProcessor 已确认暂存的 syncTag")
            }
        } catch {
            LogService.shared.warning(.sync, "OperationProcessor 确认 syncTag 失败: \(error.localizedDescription)")
        }

        await eventBus.publish(OperationEvent.queueProcessingCompleted(successCount: successCount, failedCount: failureCount))
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

    func classifyError(_ error: Error) -> OperationErrorType {
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

        if let urlError = error as? URLError {
            return classifyURLError(urlError)
        }

        if let nsError = error as? NSError {
            let apiDomains: Set<String> = ["NoteAPI", "FolderAPI", "FileAPI", "UserAPI", "OperationProcessor"]
            if apiDomains.contains(nsError.domain) {
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

            if nsError.domain == NSURLErrorDomain {
                return classifyURLErrorCode(nsError.code)
            }
        }

        return .unknown
    }

    private func classifyURLError(_ error: Error) -> OperationErrorType {
        if let urlError = error as? URLError {
            return classifyURLErrorCode(urlError.code.rawValue)
        }
        return .network
    }

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

    func isRetryable(_ error: Error) -> Bool {
        let errorType = classifyError(error)
        return errorType.isRetryable
    }

    func requiresUserAction(_: Error) -> Bool {
        false
    }
}

// MARK: - 重试延迟计算

public extension OperationProcessor {

    func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        let baseDelay = baseRetryDelay * pow(2.0, Double(retryCount))
        let cappedDelay = min(baseDelay, maxRetryDelay)
        let jitter = cappedDelay * Double.random(in: 0 ... 0.25)
        return cappedDelay + jitter
    }
}

// MARK: - 重试处理

public extension OperationProcessor {

    func processRetries() async {
        guard !isProcessingRetries else {
            LogService.shared.debug(.sync, "OperationProcessor 重试正在处理中，跳过")
            return
        }

        guard await isNetworkConnected() else {
            LogService.shared.debug(.sync, "OperationProcessor 网络不可用，跳过重试处理")
            return
        }

        guard await apiClient.isAuthenticated() else {
            LogService.shared.debug(.sync, "OperationProcessor 未认证，跳过重试处理")
            return
        }

        isProcessingRetries = true
        defer { isProcessingRetries = false }

        let retryOperations = operationQueue.getOperationsReadyForRetry()

        guard !retryOperations.isEmpty else { return }

        LogService.shared.info(.sync, "OperationProcessor 开始处理重试，数量: \(retryOperations.count)")

        var successCount = 0
        var failureCount = 0

        for operation in retryOperations {
            guard await isNetworkConnected() else {
                LogService.shared.warning(.sync, "OperationProcessor 网络断开，停止重试处理")
                break
            }

            guard operation.retryCount < maxRetryCount else {
                LogService.shared.warning(.sync, "OperationProcessor 操作超过最大重试次数: \(operation.id)")
                continue
            }

            currentOperationId = operation.id

            do {
                try operationQueue.markProcessing(operation.id)
                try await executeOperation(operation)
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

    func scheduleRetryCheck(delay: TimeInterval = 30.0) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await processRetries()
    }
}

// MARK: - 成功/失败处理

extension OperationProcessor {

    private func handleOperationFailure(operation: NoteOperation, error: Error) async {
        let errorType = classifyError(error)
        let isRetryable = errorType.isRetryable

        LogService.shared.error(.sync, "OperationProcessor 操作失败: \(operation.id), 错误类型: \(errorType.rawValue), 可重试: \(isRetryable)")

        do {
            if isRetryable, operation.retryCount < maxRetryCount {
                let retryDelay = calculateRetryDelay(retryCount: operation.retryCount)
                try operationQueue.scheduleRetry(operation.id, delay: retryDelay)
                LogService.shared.debug(.sync, "OperationProcessor 安排重试: \(operation.id), 延迟 \(retryDelay) 秒")
            } else {
                try operationQueue.markFailed(operation.id, error: error, errorType: errorType)
                LogService.shared.error(.sync, "OperationProcessor 操作最终失败: \(operation.id)")
            }
        } catch {
            LogService.shared.error(.sync, "OperationProcessor 更新操作状态失败: \(error)")
        }
    }

    private func handleOperationSuccess(operation: NoteOperation) async {
        LogService.shared.debug(.sync, "OperationProcessor 操作成功: \(operation.id), type: \(operation.type.rawValue)")
    }
}

// MARK: - 启动时处理

public extension OperationProcessor {

    func processOperationsAtStartup() async -> (successCount: Int, failureCount: Int) {
        LogService.shared.info(.sync, "OperationProcessor 启动时处理离线队列")

        guard await isNetworkConnected() else {
            LogService.shared.debug(.sync, "OperationProcessor 网络不可用，跳过启动处理")
            return (0, 0)
        }

        guard await apiClient.isAuthenticated() else {
            LogService.shared.debug(.sync, "OperationProcessor 未认证，跳过启动处理")
            return (0, 0)
        }

        await processQueue()

        let stats = operationQueue.getStatistics()
        let successCount = stats["completed"] ?? 0
        let failureCount = (stats["failed"] ?? 0) + (stats["authFailed"] ?? 0) + (stats["maxRetryExceeded"] ?? 0)

        return (successCount, failureCount)
    }
}
