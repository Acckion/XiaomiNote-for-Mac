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

    // MARK: - 重试配置

    /// 最大重试次数
    ///
    private let maxRetryCount = 8

    /// 基础重试延迟（秒）
    ///
    private let baseRetryDelay: TimeInterval = 1.0

    /// 最大重试延迟（秒）
    ///
    private let maxRetryDelay: TimeInterval = 300.0

    // MARK: - 依赖

    /// 统一操作队列
    private let operationQueue: UnifiedOperationQueue

    /// API 客户端
    private let apiClient: APIClient
    /// 笔记 API
    private let noteAPI: NoteAPI
    /// 文件夹 API
    private let folderAPI: FolderAPI
    /// 文件 API
    private let fileAPI: FileAPI

    /// 本地存储服务
    private let localStorage: LocalStorageService

    /// 数据库服务
    private let databaseService: DatabaseService

    /// 同步状态管理器
    private let syncStateManager: SyncStateManager

    /// 事件总线
    private let eventBus: EventBus

    /// ID 映射注册表
    private let idMappingRegistry: IdMappingRegistry

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

    /// 初始化方法
    ///
    /// - Parameters:
    ///   - operationQueue: 操作队列实例
    ///   - apiClient: API 客户端实例
    ///   - noteAPI: 笔记 API 实例
    ///   - folderAPI: 文件夹 API 实例
    ///   - fileAPI: 文件 API 实例
    ///   - localStorage: 本地存储服务实例
    ///   - databaseService: 数据库服务实例
    ///   - syncStateManager: 同步状态管理器实例
    ///   - eventBus: 事件总线实例
    ///   - idMappingRegistry: ID 映射注册表实例
    init(
        operationQueue: UnifiedOperationQueue,
        apiClient: APIClient,
        noteAPI: NoteAPI,
        folderAPI: FolderAPI,
        fileAPI: FileAPI,
        localStorage: LocalStorageService,
        databaseService: DatabaseService,
        syncStateManager: SyncStateManager,
        eventBus: EventBus,
        idMappingRegistry: IdMappingRegistry
    ) {
        self.operationQueue = operationQueue
        self.apiClient = apiClient
        self.noteAPI = noteAPI
        self.folderAPI = folderAPI
        self.fileAPI = fileAPI
        self.localStorage = localStorage
        self.databaseService = databaseService
        self.syncStateManager = syncStateManager
        self.eventBus = eventBus
        self.idMappingRegistry = idMappingRegistry
    }

    // MARK: - 网络状态检查

    /// 检查网络是否连接
    ///
    /// 由于 NetworkMonitor 是 @MainActor 隔离的，需要在主线程上访问
    private func isNetworkConnected() async -> Bool {
        await MainActor.run { NetworkMonitor.shared.isConnected }
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
        guard await apiClient.isAuthenticated() else {
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
        guard await apiClient.isAuthenticated() else {
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

            // noteCreate 和 cloudUpload 都必须等同一笔记的文件上传全部完成后再执行，
            // 否则会把包含临时 fileId 的 XML 上传到云端
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
                // 标记为处理中
                try operationQueue.markProcessing(operation.id)

                // 执行操作
                try await executeOperation(operation)

                // 标记为完成
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

        // 处理过程中可能有新操作入队（如 imageUpload 成功后入队 cloudUpload），
        // 检查并处理这些新操作
        let remainingOperations = operationQueue.getPendingOperations()
        if !remainingOperations.isEmpty, await isNetworkConnected() {
            LogService.shared.debug(.sync, "发现新入队的操作，继续处理: \(remainingOperations.count)")
            for operation in remainingOperations {
                guard await isNetworkConnected() else { break }
                guard operation.status != .processing else { continue }

                // 同样的文件上传等待保护
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
    func requiresUserAction(_: Error) -> Bool {
        false
    }
}

// MARK: - 重试延迟计算

public extension OperationProcessor {

    /// 计算重试延迟（指数退避 + 随机抖动）
    ///
    /// 延迟序列（含 0-25% 抖动）：~1s, ~2s, ~4s, ~8s, ~16s, ~32s, ~64s, ~128s
    ///
    /// - Parameter retryCount: 当前重试次数
    /// - Returns: 延迟时间（秒）
    ///
    func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        let baseDelay = baseRetryDelay * pow(2.0, Double(retryCount))
        let cappedDelay = min(baseDelay, maxRetryDelay)
        let jitter = cappedDelay * Double.random(in: 0 ... 0.25)
        return cappedDelay + jitter
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
        guard await apiClient.isAuthenticated() else {
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
        case .audioUpload:
            try await processAudioUpload(operation)
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
        let response = try await noteAPI.createNote(
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

        // 在保存新笔记前，用已有的文件 ID 映射替换 content 中残留的临时 fileId
        // 场景：imageUpload 先完成并注册了映射，但 updateAllFileReferences 可能因时序问题未成功替换
        var resolvedContent = note.content
        let fileMappings = idMappingRegistry.getAllMappings().filter { $0.entityType == "file" }
        for mapping in fileMappings {
            resolvedContent = resolvedContent.replacingOccurrences(of: mapping.localId, with: mapping.serverId)
        }
        if resolvedContent != note.content {
            LogService.shared.info(.sync, "noteCreate 保存前替换了 content 中的临时 fileId")
        }

        // 如果服务器返回的 ID 与本地不同，需要更新
        if note.id != serverNoteId {
            var updatedNote = Note(
                id: serverNoteId,
                title: note.title,
                content: resolvedContent,
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

            // 6. 注册 ID 映射，供后续 switchToNote 等场景解析临时 ID
            try idMappingRegistry.registerMapping(localId: note.id, serverId: serverNoteId, entityType: "note")

            // 7. 触发 ID 更新回调
            await onIdMappingCreated?(note.id, serverNoteId)

            // 8. 发送 ID 变更事件
            await eventBus.publish(NoteEvent.saved(updatedNote))

            // 9. 发布 ID 迁移事件，通知 UI 层更新引用
            await eventBus.publish(NoteEvent.idMigrated(oldId: note.id, newId: serverNoteId, note: updatedNote))

            LogService.shared.info(.sync, "OperationProcessor ID 更新完成: \(note.id) -> \(serverNoteId)")
        } else {
            // ID 相同，只更新 serverTag
            var updatedNote = note
            updatedNote.content = resolvedContent
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
        // noteCreate 成功后 pendingOperations 快照中的 noteId 可能仍是临时 ID
        let resolvedNoteId = idMappingRegistry.resolveId(operation.noteId)

        guard let note = try? localStorage.loadNote(noteId: resolvedNoteId) else {
            throw NSError(
                domain: "OperationProcessor",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "笔记不存在: \(resolvedNoteId)"]
            )
        }

        let existingTag = note.serverTag ?? note.id

        // 调用 API 更新笔记
        let response = try await noteAPI.updateNote(
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

            // 重新从 DB 加载笔记，确保使用最新的 content（可能已被 updateAllFileReferences 替换）
            let retryNote = (try? localStorage.loadNote(noteId: note.id)) ?? note

            // 使用正确的 tag 和最新 content 重新上传
            let retryResponse = try await noteAPI.updateNote(
                noteId: retryNote.id,
                title: retryNote.title,
                content: retryNote.content,
                folderId: retryNote.folderId,
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

            // 检查重试后是否仍然冲突
            let retryConflict: Bool = if let data = retryResponse["data"] as? [String: Any],
                                         let conflict = data["conflict"] as? Bool
            {
                conflict
            } else {
                false
            }

            // 提取重试后的 tag
            let retryTag: String = if let data = retryResponse["data"] as? [String: Any],
                                      let tag = data["tag"] as? String
            {
                tag
            } else {
                newTag
            }

            if retryConflict {
                // 重试后仍然冲突，保存最新 tag 后抛出错误让上层重试
                await propagateServerTag(retryTag, forNoteId: note.id)
                LogService.shared.error(.sync, "云端上传冲突重试后仍然冲突: \(operation.noteId.prefix(8))...")
                throw NSError(
                    domain: "OperationProcessor",
                    code: 409,
                    userInfo: [NSLocalizedDescriptionKey: "云端上传冲突重试后仍然冲突"]
                )
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

        let deleteData: CloudDeleteData
        do {
            deleteData = try CloudDeleteData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的删除操作数据"]
            )
        }

        // 调用 API 删除笔记
        _ = try await noteAPI.deleteNote(noteId: operation.noteId, tag: deleteData.tag, purge: false)

        LogService.shared.info(.sync, "OperationProcessor 删除成功: \(operation.noteId)")
    }

    /// 处理图片上传操作
    ///
    /// - Parameter operation: imageUpload 操作
    /// - Throws: 执行错误
    private func processImageUpload(_ operation: NoteOperation) async throws {
        // noteCreate 成功后 pendingOperations 快照中的 noteId 可能仍是临时 ID
        let resolvedNoteId = idMappingRegistry.resolveId(operation.noteId)
        LogService.shared.debug(.sync, "OperationProcessor 处理 imageUpload: \(resolvedNoteId)")

        let uploadData: FileUploadOperationData
        do {
            uploadData = try FileUploadOperationData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的图片上传操作数据"]
            )
        }

        // data JSON 内部的 noteId 也可能是临时 ID
        let resolvedUploadNoteId = idMappingRegistry.resolveId(uploadData.noteId)

        let ext = String(uploadData.mimeType.dropFirst("image/".count))
        guard let imageData = localStorage.loadPendingUpload(fileId: uploadData.temporaryFileId, extension: ext) else {
            // 本地文件丢失，无法重试
            LogService.shared.error(.sync, "图片本地文件丢失: \(uploadData.temporaryFileId)")
            try operationQueue.markFailed(operation.id, error: NSError(
                domain: "OperationProcessor", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "本地文件丢失"]
            ), errorType: .notFound)
            return
        }

        // 调用 API 上传
        let result = try await fileAPI.uploadImage(
            imageData: imageData,
            fileName: uploadData.fileName,
            mimeType: uploadData.mimeType
        )

        guard let serverFileId = result["fileId"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "上传图片响应无效"]
            )
        }

        // 注册 ID 映射
        try idMappingRegistry.registerMapping(localId: uploadData.temporaryFileId, serverId: serverFileId, entityType: "file")

        // 使用解析后的 noteId 更新笔记内容中的 fileId 引用
        try await idMappingRegistry.updateAllFileReferences(
            localId: uploadData.temporaryFileId,
            serverId: serverFileId,
            noteId: resolvedUploadNoteId
        )

        // 移动 pending 文件到正式缓存（用正式 ID）
        let fileType = String(uploadData.mimeType.dropFirst("image/".count))
        try? localStorage.movePendingUploadToCache(fileId: uploadData.temporaryFileId, extension: fileType, newFileId: serverFileId)

        // 清理图片缓存中临时 ID 的旧文件（saveImage 在入队前用临时 ID 保存了一份）
        let oldCacheURL = localStorage.imagesDirectory.appendingPathComponent("\(uploadData.temporaryFileId).\(fileType)")
        try? FileManager.default.removeItem(at: oldCacheURL)

        // 清理 pending 临时文件
        try? localStorage.deletePendingUpload(fileId: uploadData.temporaryFileId, extension: ext)

        LogService.shared.info(.sync, "图片上传成功: \(uploadData.temporaryFileId.prefix(20))... -> \(serverFileId)")
    }

    /// 处理音频上传操作
    ///
    /// - Parameter operation: audioUpload 操作
    /// - Throws: 执行错误
    private func processAudioUpload(_ operation: NoteOperation) async throws {
        // noteCreate 成功后 pendingOperations 快照中的 noteId 可能仍是临时 ID
        let resolvedNoteId = idMappingRegistry.resolveId(operation.noteId)
        LogService.shared.debug(.sync, "OperationProcessor 处理 audioUpload: \(resolvedNoteId)")

        let uploadData: FileUploadOperationData
        do {
            uploadData = try FileUploadOperationData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的音频上传操作数据"]
            )
        }

        // data JSON 内部的 noteId 也可能是临时 ID
        let resolvedUploadNoteId = idMappingRegistry.resolveId(uploadData.noteId)

        // 读取本地文件
        guard let audioData = localStorage.loadPendingUpload(fileId: uploadData.temporaryFileId, extension: "mp3") else {
            LogService.shared.error(.sync, "音频本地文件丢失: \(uploadData.temporaryFileId)")
            try operationQueue.markFailed(operation.id, error: NSError(
                domain: "OperationProcessor", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "本地文件丢失"]
            ), errorType: .notFound)
            return
        }

        // 调用 API 上传
        let result = try await fileAPI.uploadAudio(
            audioData: audioData,
            fileName: uploadData.fileName,
            mimeType: uploadData.mimeType
        )

        guard let serverFileId = result["fileId"] as? String else {
            throw NSError(
                domain: "OperationProcessor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "上传音频响应无效"]
            )
        }

        let digest = result["digest"] as? String

        // 注册 ID 映射
        try idMappingRegistry.registerMapping(localId: uploadData.temporaryFileId, serverId: serverFileId, entityType: "file")

        // 更新笔记内容中的 fileId 引用
        try await idMappingRegistry.updateAllFileReferences(
            localId: uploadData.temporaryFileId,
            serverId: serverFileId,
            noteId: resolvedUploadNoteId
        )

        // 更新笔记 settingJson 中的音频信息
        if var note = try? localStorage.loadNote(noteId: resolvedUploadNoteId) {
            var setting: [String: Any] = [
                "themeId": 0,
                "stickyTime": 0,
                "version": 0,
            ]
            if let existingSettingJson = note.settingJson,
               let jsonData = existingSettingJson.data(using: .utf8),
               let existingSetting = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            {
                setting = existingSetting
            }

            var settingData = setting["data"] as? [[String: Any]] ?? []

            // 替换临时 fileId 为正式 fileId
            var updated = false
            for i in 0 ..< settingData.count {
                if let existingFileId = settingData[i]["fileId"] as? String,
                   existingFileId == uploadData.temporaryFileId
                {
                    settingData[i]["fileId"] = serverFileId
                    if let digest {
                        settingData[i]["digest"] = digest + ".mp3"
                    }
                    updated = true
                }
            }

            // 如果没有找到临时 ID 的条目，添加新条目
            if !updated {
                let audioInfo: [String: Any] = [
                    "fileId": serverFileId,
                    "mimeType": uploadData.mimeType,
                    "digest": (digest ?? serverFileId) + ".mp3",
                ]
                settingData.append(audioInfo)
            }

            setting["data"] = settingData

            if let settingJsonData = try? JSONSerialization.data(withJSONObject: setting, options: [.sortedKeys]),
               let settingString = String(data: settingJsonData, encoding: .utf8)
            {
                note.settingJson = settingString
                try? localStorage.saveNote(note)
            }

            // 入队 cloudUpload 触发笔记重新保存
            _ = try? operationQueue.enqueueCloudUpload(
                noteId: note.id,
                title: note.title,
                content: note.content,
                folderId: note.folderId
            )
        }

        // 移动文件到正式缓存
        try? localStorage.movePendingUploadToCache(fileId: uploadData.temporaryFileId, extension: "mp3", newFileId: serverFileId)

        // 清理临时文件
        try? localStorage.deletePendingUpload(fileId: uploadData.temporaryFileId, extension: "mp3")

        LogService.shared.info(.sync, "音频上传成功: \(uploadData.temporaryFileId.prefix(20))... -> \(serverFileId)")
    }

    /// 处理创建文件夹操作
    ///
    /// - Parameter operation: folderCreate 操作
    /// - Throws: 执行错误
    private func processFolderCreate(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "OperationProcessor 处理 folderCreate: \(operation.noteId)")

        let createData: FolderCreateData
        do {
            createData = try FolderCreateData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }

        let folderName = createData.name

        // 调用 API 创建文件夹
        let response = try await folderAPI.createFolder(name: folderName)

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

        // 保存文件夹到数据库（通过 EventBus）
        let tag = extractTag(from: response, fallbackTag: entry["tag"] as? String ?? folderId)
        var folderRawData: [String: Any] = [:]
        for (key, value) in entry {
            folderRawData[key] = value
        }
        folderRawData["tag"] = tag

        let folderRawDataJson: String? = if let jsonData = try? JSONSerialization.data(withJSONObject: folderRawData, options: []) {
            String(data: jsonData, encoding: .utf8)
        } else {
            nil
        }

        let folder = Folder(
            id: folderId,
            name: subject,
            count: 0,
            isSystem: false,
            isPinned: false,
            createdAt: Date(),
            rawDataJson: folderRawDataJson
        )

        await eventBus.publish(FolderEvent.folderSaved(folder))

        // 如果服务器返回的 ID 与本地不同，需要更新本地文件夹和笔记
        if operation.noteId != folderId {
            // 发布文件夹 ID 迁移事件，NoteStore 会更新笔记的 folderId 并删除旧文件夹
            await eventBus.publish(FolderEvent.folderIdMigrated(oldId: operation.noteId, newId: folderId))
        }

        LogService.shared.info(.sync, "OperationProcessor 创建文件夹成功: \(operation.noteId) -> \(folderId)")
    }

    /// 处理重命名文件夹操作
    ///
    /// - Parameter operation: folderRename 操作
    /// - Throws: 执行错误
    private func processFolderRename(_ operation: NoteOperation) async throws {
        LogService.shared.debug(.sync, "OperationProcessor 处理 folderRename: \(operation.noteId)")

        let renameData: FolderRenameData
        do {
            renameData = try FolderRenameData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }

        let newName = renameData.name
        let existingTag = renameData.tag

        // 调用 API 重命名文件夹
        let response = try await folderAPI.renameFolder(
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
                var updatedRawData = folder.rawDataDict ?? [:]
                for (key, value) in entry {
                    updatedRawData[key] = value
                }
                updatedRawData["tag"] = extractTag(from: response, fallbackTag: existingTag)
                updatedRawData["subject"] = newName

                let updatedRawDataJson: String? = if let jsonData = try? JSONSerialization.data(withJSONObject: updatedRawData, options: []) {
                    String(data: jsonData, encoding: .utf8)
                } else {
                    folder.rawDataJson
                }

                let updatedFolder = Folder(
                    id: folder.id,
                    name: newName,
                    count: folder.count,
                    isSystem: folder.isSystem,
                    isPinned: folder.isPinned,
                    createdAt: folder.createdAt,
                    rawDataJson: updatedRawDataJson
                )

                await eventBus.publish(FolderEvent.folderSaved(updatedFolder))
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

        let deleteData: FolderDeleteData
        do {
            deleteData = try FolderDeleteData.decoded(from: operation.data)
        } catch {
            throw NSError(
                domain: "OperationProcessor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "无效的文件夹操作数据"]
            )
        }

        // 调用 API 删除文件夹
        _ = try await folderAPI.deleteFolder(folderId: operation.noteId, tag: deleteData.tag, purge: false)

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
        guard await apiClient.isAuthenticated() else {
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
