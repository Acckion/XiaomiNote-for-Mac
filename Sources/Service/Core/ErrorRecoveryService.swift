import Combine
import Foundation

/// 错误恢复服务
///
/// 统一管理网络错误的恢复机制，包括：
/// - 网络错误时自动添加到离线队列
/// - 重试限制和失败标记
/// - 失败操作通知用户
///
@MainActor
public final class ErrorRecoveryService: ObservableObject {
    public static let shared = ErrorRecoveryService()

    // MARK: - 配置

    /// 最大重试次数
    public var maxRetryCount = 3

    /// 初始重试延迟（秒）
    public var initialRetryDelay: TimeInterval = 5.0

    /// 最大重试延迟（秒）
    public var maxRetryDelay: TimeInterval = 60.0

    /// 重试退避倍数
    public var retryBackoffMultiplier = 2.0

    // MARK: - 依赖服务

    /// 统一操作队列
    private let unifiedQueue = UnifiedOperationQueue.shared
    private let networkErrorHandler = NetworkErrorHandler.shared
    private let onlineStateManager = OnlineStateManager.shared

    // MARK: - 状态

    /// 失败的操作列表（超过最大重试次数）
    @Published public private(set) var permanentlyFailedOperations: [FailedOperation] = []

    /// 是否有需要用户关注的失败操作
    @Published public private(set) var hasFailedOperations = false

    /// 最后一次错误消息
    @Published public var lastErrorMessage: String?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    private init() {
        setupNotificationObservers()
    }

    // MARK: - 通知监听

    /// 设置通知监听
    private func setupNotificationObservers() {
        // 监听离线操作失败通知
        NotificationCenter.default.publisher(for: NSNotification.Name("OfflineOperationsFailed"))
            .sink { [weak self] notification in
                Task { @MainActor in
                    if let count = notification.userInfo?["count"] as? Int, count > 0 {
                        self?.hasFailedOperations = true
                        self?.lastErrorMessage = "有 \(count) 个操作失败，请检查网络连接后重试"
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 公共方法

    /// 处理网络错误并决定是否添加到离线队列
    ///
    /// 根据错误类型和重试次数决定处理策略：
    /// - 网络错误：添加到离线队列
    /// - Cookie过期：添加到离线队列，等待Cookie刷新
    /// - 其他错误：根据是否可重试决定
    ///
    ///
    /// - Parameters:
    ///   - operation: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - data: 操作数据
    ///   - error: 发生的错误
    ///   - context: 错误上下文描述
    /// - Returns: 错误处理结果
    public func handleNetworkError(
        operation: OperationType,
        noteId: String,
        data: Data,
        error: Error,
        context: String
    ) -> ErrorRecoveryResult {
        // 分类错误
        let errorType = networkErrorHandler.classifyError(error)

        // 根据错误类型决定处理策略
        switch errorType {
        case .networkError:
            // 网络错误：添加到统一队列
            return addToUnifiedQueue(
                operation: operation,
                noteId: noteId,
                data: data,
                error: error,
                context: context
            )

        case .authenticationError:
            // 认证错误：添加到统一队列，等待Cookie刷新
            return addToUnifiedQueue(
                operation: operation,
                noteId: noteId,
                data: data,
                error: error,
                context: context,
                requiresAuth: true
            )

        case .serverError:
            // 服务器错误：如果可重试，添加到统一队列
            let handlingResult = networkErrorHandler.handleError(error, retryCount: 0)
            if handlingResult.shouldRetry {
                return addToUnifiedQueue(
                    operation: operation,
                    noteId: noteId,
                    data: data,
                    error: error,
                    context: context
                )
            } else {
                return .noRetry(message: handlingResult.userMessage ?? "服务器错误")
            }

        case .clientError, .businessError:
            // 客户端错误或业务错误：不重试
            let handlingResult = networkErrorHandler.handleError(error, retryCount: 0)
            return .noRetry(message: handlingResult.userMessage ?? error.localizedDescription)
        }
    }

    /// 添加操作到统一队列
    ///
    ///
    /// - Parameters:
    ///   - operation: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - data: 操作数据
    ///   - error: 错误信息
    ///   - context: 错误上下文
    ///   - requiresAuth: 是否需要认证
    /// - Returns: 错误处理结果
    private func addToUnifiedQueue(
        operation: OperationType,
        noteId: String,
        data: Data,
        error: Error,
        context _: String,
        requiresAuth: Bool = false
    ) -> ErrorRecoveryResult {
        do {
            let noteOperation = NoteOperation(
                type: operation,
                noteId: noteId,
                data: data,
                status: .pending,
                priority: determinePriority(for: operation),
                retryCount: 0,
                lastError: error.localizedDescription
            )

            try unifiedQueue.enqueue(noteOperation)
            LogService.shared.debug(.core, "操作已添加到统一队列: \(operation.rawValue)")

            let message = requiresAuth
                ? "操作已保存，将在登录后自动同步"
                : "操作已保存，将在网络恢复后自动同步"

            return .addedToQueue(message: message)
        } catch {
            LogService.shared.error(.core, "添加到统一队列失败: \(error)")
            return .noRetry(message: "保存操作失败: \(error.localizedDescription)")
        }
    }

    /// 确定操作优先级
    ///
    /// - Parameter operation: 操作类型
    /// - Returns: 优先级数值（数字越大优先级越高）
    private func determinePriority(for operation: OperationType) -> Int {
        switch operation {
        case .cloudDelete:
            10 // 删除操作最高优先级
        case .noteCreate:
            8 // 创建笔记高优先级
        case .cloudUpload:
            5 // 上传笔记中等优先级
        case .folderDelete:
            7 // 删除文件夹高优先级
        case .folderRename:
            4 // 重命名文件夹中等优先级
        case .folderCreate:
            6 // 创建文件夹较高优先级
        case .imageUpload:
            3 // 图片上传低优先级
        case .audioUpload:
            3 // 音频上传低优先级
        }
    }

    /// 计算重试延迟（指数退避）
    ///
    /// - Parameter retryCount: 当前重试次数
    /// - Returns: 延迟时间（秒）
    public func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        let delay = initialRetryDelay * pow(retryBackoffMultiplier, Double(retryCount))
        return min(delay, maxRetryDelay)
    }

    /// 清除失败操作
    ///
    /// - Parameter operationId: 要清除的操作ID，如果为nil则清除所有
    public func clearFailedOperations(_ operationId: String? = nil) {
        if let operationId {
            permanentlyFailedOperations.removeAll { $0.id == operationId }
        } else {
            permanentlyFailedOperations.removeAll()
        }
        hasFailedOperations = !permanentlyFailedOperations.isEmpty

        if permanentlyFailedOperations.isEmpty {
            lastErrorMessage = nil
        }
    }
}

// MARK: - 错误恢复结果

/// 错误恢复结果
public enum ErrorRecoveryResult {
    /// 已添加到离线队列
    case addedToQueue(message: String)

    /// 不重试
    case noRetry(message: String)

    /// 永久失败（超过最大重试次数）
    case permanentlyFailed(message: String)

    /// 获取用户消息
    public var message: String {
        switch self {
        case let .addedToQueue(message),
             let .noRetry(message),
             let .permanentlyFailed(message):
            message
        }
    }

    /// 是否已添加到队列
    public var isAddedToQueue: Bool {
        if case .addedToQueue = self {
            return true
        }
        return false
    }

    /// 是否永久失败
    public var isPermanentlyFailed: Bool {
        if case .permanentlyFailed = self {
            return true
        }
        return false
    }
}

// MARK: - 失败操作记录

/// 失败操作记录
public struct FailedOperation: Identifiable {
    public let id: String
    public let operationType: OperationType
    public let noteId: String
    public let operationData: [String: Any]
    public let error: String
    public let retryCount: Int
    public let failedAt: Date

    /// 操作类型的显示名称
    public var operationTypeName: String {
        switch operationType {
        case .noteCreate: "创建笔记"
        case .cloudUpload: "更新笔记"
        case .cloudDelete: "删除笔记"
        case .imageUpload: "上传图片"
        case .audioUpload: "上传音频"
        case .folderCreate: "创建文件夹"
        case .folderRename: "重命名文件夹"
        case .folderDelete: "删除文件夹"
        }
    }

    public init(
        id: String,
        operationType: OperationType,
        noteId: String,
        operationData: [String: Any],
        error: String,
        retryCount: Int,
        failedAt: Date
    ) {
        self.id = id
        self.operationType = operationType
        self.noteId = noteId
        self.operationData = operationData
        self.error = error
        self.retryCount = retryCount
        self.failedAt = failedAt
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    /// 操作永久失败通知
    static let operationPermanentlyFailed = Notification.Name("operationPermanentlyFailed")
}
