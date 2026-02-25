import Foundation

/// 操作队列统一配置
///
/// OperationProcessor 和 UnifiedOperationQueue 共享此配置，
/// 消除重试参数分散定义的问题。
public struct OperationQueueConfig: Sendable {
    /// 最大重试次数
    public let maxRetryCount: Int
    /// 基础重试延迟（秒）
    public let baseRetryDelay: TimeInterval
    /// 最大重试延迟（秒）
    public let maxRetryDelay: TimeInterval

    public init(
        maxRetryCount: Int = 8,
        baseRetryDelay: TimeInterval = 1.0,
        maxRetryDelay: TimeInterval = 300.0
    ) {
        self.maxRetryCount = maxRetryCount
        self.baseRetryDelay = baseRetryDelay
        self.maxRetryDelay = maxRetryDelay
    }

    public static let `default` = OperationQueueConfig()
}
