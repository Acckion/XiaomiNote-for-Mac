import Foundation
import Combine

/// 错误恢复服务
/// 
/// 统一管理网络错误的恢复机制，包括：
/// - 网络错误时自动添加到离线队列
/// - 重试限制和失败标记
/// - 失败操作通知用户
/// 
/// 遵循需求 8.1, 8.7
@MainActor
public final class ErrorRecoveryService: ObservableObject {
    public static let shared = ErrorRecoveryService()
    
    // MARK: - 配置
    
    /// 最大重试次数
    public var maxRetryCount: Int = 3
    
    /// 初始重试延迟（秒）
    public var initialRetryDelay: TimeInterval = 5.0
    
    /// 最大重试延迟（秒）
    public var maxRetryDelay: TimeInterval = 60.0
    
    /// 重试退避倍数
    public var retryBackoffMultiplier: Double = 2.0
    
    // MARK: - 依赖服务
    
    /// 统一操作队列（新的队列，用于主要功能）
    private let unifiedQueue = UnifiedOperationQueue.shared
    /// 旧的离线操作队列（已废弃，仅用于兼容旧的错误恢复逻辑）
    @available(*, deprecated, message: "使用 unifiedQueue 替代")
    private let legacyOfflineQueue = OfflineOperationQueue.shared
    private let networkErrorHandler = NetworkErrorHandler.shared
    private let onlineStateManager = OnlineStateManager.shared
    
    // MARK: - 状态
    
    /// 失败的操作列表（超过最大重试次数）
    @Published public private(set) var permanentlyFailedOperations: [FailedOperation] = []
    
    /// 是否有需要用户关注的失败操作
    @Published public private(set) var hasFailedOperations: Bool = false
    
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
    /// 遵循需求 8.1
    /// 
    /// - Parameters:
    ///   - error: 发生的错误
    ///   - operationType: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - operationData: 操作数据
    ///   - currentRetryCount: 当前重试次数
    /// - Returns: 错误处理结果
    public func handleNetworkError(
        _ error: Error,
        operationType: OfflineOperationType,
        noteId: String,
        operationData: [String: Any],
        currentRetryCount: Int = 0
    ) -> ErrorRecoveryResult {
        // 分类错误
        let errorType = networkErrorHandler.classifyError(error)
        let handlingResult = networkErrorHandler.handleError(error, retryCount: currentRetryCount)
        
        print("[ErrorRecoveryService] 处理错误: \(error.localizedDescription)")
        print("[ErrorRecoveryService] 错误类型: \(errorType), 重试次数: \(currentRetryCount)")
        
        // 检查是否超过最大重试次数（需求 8.7）
        if currentRetryCount >= maxRetryCount {
            return handleMaxRetryExceeded(
                error: error,
                operationType: operationType,
                noteId: noteId,
                operationData: operationData,
                retryCount: currentRetryCount
            )
        }
        
        // 根据错误类型决定处理策略
        switch errorType {
        case .networkError:
            // 网络错误：添加到离线队列（需求 8.1）
            return addToOfflineQueue(
                operationType: operationType,
                noteId: noteId,
                operationData: operationData,
                retryCount: currentRetryCount,
                error: error
            )
            
        case .authenticationError:
            // 认证错误：添加到离线队列，等待Cookie刷新
            return addToOfflineQueue(
                operationType: operationType,
                noteId: noteId,
                operationData: operationData,
                retryCount: currentRetryCount,
                error: error,
                requiresAuth: true
            )
            
        case .serverError:
            // 服务器错误：如果可重试，添加到离线队列
            if handlingResult.shouldRetry {
                return addToOfflineQueue(
                    operationType: operationType,
                    noteId: noteId,
                    operationData: operationData,
                    retryCount: currentRetryCount,
                    error: error
                )
            } else {
                return .noRetry(message: handlingResult.userMessage ?? "服务器错误")
            }
            
        case .clientError, .businessError:
            // 客户端错误或业务错误：不重试
            return .noRetry(message: handlingResult.userMessage ?? error.localizedDescription)
        }
    }
    
    /// 添加操作到离线队列
    /// 
    /// 遵循需求 8.1
    /// 
    /// - Parameters:
    ///   - operationType: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - operationData: 操作数据
    ///   - retryCount: 当前重试次数
    ///   - error: 错误信息
    ///   - requiresAuth: 是否需要认证
    /// - Returns: 错误处理结果
    private func addToOfflineQueue(
        operationType: OfflineOperationType,
        noteId: String,
        operationData: [String: Any],
        retryCount: Int,
        error: Error,
        requiresAuth: Bool = false
    ) -> ErrorRecoveryResult {
        do {
            // 编码操作数据
            let data = try JSONSerialization.data(withJSONObject: operationData, options: [])
            
            // 创建离线操作
            let operation = OfflineOperation(
                type: operationType,
                noteId: noteId,
                data: data,
                priority: OfflineOperation.calculatePriority(for: operationType),
                retryCount: retryCount,
                lastError: error.localizedDescription,
                status: .pending
            )
            
            // 添加到队列
            try legacyOfflineQueue.addOperation(operation)
            
            print("[ErrorRecoveryService] ✅ 操作已添加到离线队列: \(operationType.rawValue), noteId: \(noteId)")
            
            let message = requiresAuth 
                ? "操作已保存，将在登录后自动同步"
                : "操作已保存，将在网络恢复后自动同步"
            
            return .addedToQueue(message: message)
            
        } catch {
            print("[ErrorRecoveryService] ❌ 添加到离线队列失败: \(error)")
            return .noRetry(message: "保存操作失败: \(error.localizedDescription)")
        }
    }
    
    /// 处理超过最大重试次数的情况
    /// 
    /// 遵循需求 8.7
    /// 
    /// - Parameters:
    ///   - error: 错误信息
    ///   - operationType: 操作类型
    ///   - noteId: 笔记或文件夹ID
    ///   - operationData: 操作数据
    ///   - retryCount: 重试次数
    /// - Returns: 错误处理结果
    private func handleMaxRetryExceeded(
        error: Error,
        operationType: OfflineOperationType,
        noteId: String,
        operationData: [String: Any],
        retryCount: Int
    ) -> ErrorRecoveryResult {
        print("[ErrorRecoveryService] ⚠️ 操作超过最大重试次数: \(operationType.rawValue), noteId: \(noteId), retryCount: \(retryCount)")
        
        // 创建失败操作记录
        let failedOperation = FailedOperation(
            id: UUID().uuidString,
            operationType: operationType,
            noteId: noteId,
            operationData: operationData,
            error: error.localizedDescription,
            retryCount: retryCount,
            failedAt: Date()
        )
        
        // 添加到失败列表
        permanentlyFailedOperations.append(failedOperation)
        hasFailedOperations = true
        
        // 更新离线队列中的操作状态为失败
        do {
            // 查找并更新操作状态
            let pendingOperations = legacyOfflineQueue.getPendingOperations()
            if let existingOp = pendingOperations.first(where: { $0.noteId == noteId && $0.type == operationType }) {
                try legacyOfflineQueue.updateOperationStatus(
                    operationId: existingOp.id,
                    status: .failed,
                    error: "超过最大重试次数 (\(maxRetryCount))"
                )
            }
        } catch {
            print("[ErrorRecoveryService] ❌ 更新操作状态失败: \(error)")
        }
        
        // 发送通知
        NotificationCenter.default.post(
            name: .operationPermanentlyFailed,
            object: nil,
            userInfo: [
                "operationType": operationType.rawValue,
                "noteId": noteId,
                "error": error.localizedDescription,
                "retryCount": retryCount
            ]
        )
        
        let message = "操作失败（已重试 \(retryCount) 次），请稍后手动重试"
        lastErrorMessage = message
        
        return .permanentlyFailed(message: message)
    }
    
    /// 计算重试延迟（指数退避）
    /// 
    /// - Parameter retryCount: 当前重试次数
    /// - Returns: 延迟时间（秒）
    public func calculateRetryDelay(retryCount: Int) -> TimeInterval {
        let delay = initialRetryDelay * pow(retryBackoffMultiplier, Double(retryCount))
        return min(delay, maxRetryDelay)
    }
    
    /// 重试失败的操作
    /// 
    /// - Parameter operationId: 失败操作的ID
    /// - Returns: 是否成功重新添加到队列
    public func retryFailedOperation(_ operationId: String) -> Bool {
        guard let index = permanentlyFailedOperations.firstIndex(where: { $0.id == operationId }) else {
            print("[ErrorRecoveryService] 找不到失败的操作: \(operationId)")
            return false
        }
        
        let failedOp = permanentlyFailedOperations[index]
        
        do {
            // 编码操作数据
            let data = try JSONSerialization.data(withJSONObject: failedOp.operationData, options: [])
            
            // 创建新的离线操作（重置重试次数）
            let operation = OfflineOperation(
                type: failedOp.operationType,
                noteId: failedOp.noteId,
                data: data,
                priority: OfflineOperation.calculatePriority(for: failedOp.operationType),
                retryCount: 0,  // 重置重试次数
                lastError: nil,
                status: .pending
            )
            
            // 添加到队列
            try legacyOfflineQueue.addOperation(operation)
            
            // 从失败列表中移除
            permanentlyFailedOperations.remove(at: index)
            hasFailedOperations = !permanentlyFailedOperations.isEmpty
            
            print("[ErrorRecoveryService] ✅ 失败操作已重新添加到队列: \(failedOp.operationType.rawValue)")
            return true
            
        } catch {
            print("[ErrorRecoveryService] ❌ 重试失败操作失败: \(error)")
            return false
        }
    }
    
    /// 重试所有失败的操作
    /// 
    /// - Returns: 成功重试的操作数量
    public func retryAllFailedOperations() -> Int {
        var successCount = 0
        let operationIds = permanentlyFailedOperations.map { $0.id }
        
        for operationId in operationIds {
            if retryFailedOperation(operationId) {
                successCount += 1
            }
        }
        
        print("[ErrorRecoveryService] 重试所有失败操作完成，成功: \(successCount)")
        return successCount
    }
    
    /// 清除失败操作
    /// 
    /// - Parameter operationId: 要清除的操作ID，如果为nil则清除所有
    public func clearFailedOperations(_ operationId: String? = nil) {
        if let operationId = operationId {
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
        case .addedToQueue(let message),
             .noRetry(let message),
             .permanentlyFailed(let message):
            return message
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
    public let operationType: OfflineOperationType
    public let noteId: String
    public let operationData: [String: Any]
    public let error: String
    public let retryCount: Int
    public let failedAt: Date
    
    /// 操作类型的显示名称
    public var operationTypeName: String {
        switch operationType {
        case .createNote: return "创建笔记"
        case .updateNote: return "更新笔记"
        case .deleteNote: return "删除笔记"
        case .uploadImage: return "上传图片"
        case .createFolder: return "创建文件夹"
        case .renameFolder: return "重命名文件夹"
        case .deleteFolder: return "删除文件夹"
        }
    }
    
    public init(
        id: String,
        operationType: OfflineOperationType,
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
