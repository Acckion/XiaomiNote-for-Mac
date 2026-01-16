import Foundation

// MARK: - 操作类型

/// 笔记操作类型
///
/// 定义统一操作队列支持的所有操作类型
public enum OperationType: String, Codable, Sendable, CaseIterable {
    /// 创建笔记（离线创建时使用）
    case noteCreate = "noteCreate"
    /// 上传笔记到云端
    case cloudUpload = "cloudUpload"
    /// 从云端删除笔记
    case cloudDelete = "cloudDelete"
    /// 上传图片
    case imageUpload = "imageUpload"
    /// 创建文件夹
    case folderCreate = "folderCreate"
    /// 重命名文件夹
    case folderRename = "folderRename"
    /// 删除文件夹
    case folderDelete = "folderDelete"
}

// MARK: - 操作状态

/// 操作状态
///
/// 表示操作在队列中的当前状态
public enum OperationStatus: String, Codable, Sendable {
    /// 待处理
    case pending = "pending"
    /// 处理中
    case processing = "processing"
    /// 已完成
    case completed = "completed"
    /// 失败（可重试）
    case failed = "failed"
    /// 认证失败（需用户处理）
    case authFailed = "authFailed"
    /// 超过最大重试次数
    case maxRetryExceeded = "maxRetryExceeded"
}

// MARK: - 错误类型

/// 错误类型
///
/// 用于分类操作失败的原因，决定是否可以重试
public enum OperationErrorType: String, Codable, Sendable {
    /// 网络错误（可重试）
    case network = "network"
    /// 超时（可重试）
    case timeout = "timeout"
    /// 服务器错误（可重试）
    case serverError = "serverError"
    /// 认证过期（不可重试）
    case authExpired = "authExpired"
    /// 资源不存在（不可重试）
    case notFound = "notFound"
    /// 冲突（需特殊处理）
    case conflict = "conflict"
    /// 未知错误
    case unknown = "unknown"
    
    /// 判断错误是否可重试
    public var isRetryable: Bool {
        switch self {
        case .network, .timeout, .serverError:
            return true
        case .authExpired, .notFound, .conflict, .unknown:
            return false
        }
    }
}

// MARK: - 笔记操作

/// 笔记操作
///
/// 统一操作队列中的操作记录，包含本地保存和云端同步的所有信息
public struct NoteOperation: Codable, Identifiable, Sendable {
    /// 操作 ID
    public let id: String
    
    /// 操作类型
    public let type: OperationType
    
    /// 笔记 ID（文件夹操作时为 folderId）
    /// 注意：可能是临时 ID（local_xxx）或正式 ID
    public var noteId: String
    
    /// 操作数据（JSON 编码）
    public let data: Data
    
    /// 创建时间
    public let createdAt: Date
    
    /// 本地保存时间戳（用于同步保护）
    public var localSaveTimestamp: Date?
    
    /// 操作状态
    public var status: OperationStatus
    
    /// 优先级（数字越大优先级越高）
    public var priority: Int
    
    /// 重试次数
    public var retryCount: Int
    
    /// 下次重试时间
    public var nextRetryAt: Date?
    
    /// 最后错误信息
    public var lastError: String?
    
    /// 错误类型
    public var errorType: OperationErrorType?
    
    /// 是否使用临时 ID（离线创建的笔记）
    public var isLocalId: Bool
    
    // MARK: - 初始化
    
    /// 创建新的笔记操作
    ///
    /// - Parameters:
    ///   - id: 操作 ID，默认生成新的 UUID
    ///   - type: 操作类型
    ///   - noteId: 笔记 ID
    ///   - data: 操作数据
    ///   - createdAt: 创建时间，默认为当前时间
    ///   - localSaveTimestamp: 本地保存时间戳
    ///   - status: 操作状态，默认为 pending
    ///   - priority: 优先级，默认根据操作类型计算
    ///   - retryCount: 重试次数，默认为 0
    ///   - nextRetryAt: 下次重试时间
    ///   - lastError: 最后错误信息
    ///   - errorType: 错误类型
    ///   - isLocalId: 是否使用临时 ID
    public init(
        id: String = UUID().uuidString,
        type: OperationType,
        noteId: String,
        data: Data,
        createdAt: Date = Date(),
        localSaveTimestamp: Date? = nil,
        status: OperationStatus = .pending,
        priority: Int? = nil,
        retryCount: Int = 0,
        nextRetryAt: Date? = nil,
        lastError: String? = nil,
        errorType: OperationErrorType? = nil,
        isLocalId: Bool = false
    ) {
        self.id = id
        self.type = type
        self.noteId = noteId
        self.data = data
        self.createdAt = createdAt
        self.localSaveTimestamp = localSaveTimestamp
        self.status = status
        self.priority = priority ?? Self.calculatePriority(for: type)
        self.retryCount = retryCount
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
        self.errorType = errorType
        self.isLocalId = isLocalId
    }
    
    // MARK: - 临时 ID 相关
    
    /// 临时 ID 前缀
    private static let temporaryIdPrefix = "local_"
    
    /// 检查是否为临时 ID
    ///
    /// - Parameter id: 要检查的 ID
    /// - Returns: 如果是临时 ID 返回 true
    public static func isTemporaryId(_ id: String) -> Bool {
        return id.hasPrefix(temporaryIdPrefix)
    }
    
    /// 生成临时 ID
    ///
    /// 格式：local_<UUID>
    /// 示例：local_550e8400-e29b-41d4-a716-446655440000
    ///
    /// - Returns: 新生成的临时 ID
    public static func generateTemporaryId() -> String {
        return "\(temporaryIdPrefix)\(UUID().uuidString)"
    }
    
    // MARK: - 优先级计算
    
    /// 计算操作优先级（基于操作类型）
    ///
    /// 优先级规则：
    /// - noteCreate: 4（最高优先级，确保先获取正式 ID）
    /// - cloudDelete, folderDelete: 3
    /// - cloudUpload, folderRename: 2
    /// - imageUpload, folderCreate: 1
    ///
    /// - Parameter type: 操作类型
    /// - Returns: 优先级数值
    public static func calculatePriority(for type: OperationType) -> Int {
        switch type {
        case .noteCreate:
            return 4  // 最高优先级
        case .cloudDelete, .folderDelete:
            return 3
        case .cloudUpload, .folderRename:
            return 2
        case .imageUpload, .folderCreate:
            return 1
        }
    }
    
    // MARK: - 状态检查
    
    /// 检查操作是否可以处理
    ///
    /// 只有 pending 或 failed 状态的操作可以处理
    public var canProcess: Bool {
        return status == .pending || status == .failed
    }
    
    /// 检查操作是否需要重试
    ///
    /// 检查是否到达重试时间
    public var isReadyForRetry: Bool {
        guard status == .failed else { return false }
        guard let nextRetryAt = nextRetryAt else { return true }
        return Date() >= nextRetryAt
    }
}

// MARK: - Equatable

extension NoteOperation: Equatable {
    public static func == (lhs: NoteOperation, rhs: NoteOperation) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension NoteOperation: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - 操作历史记录

/// 操作历史记录
///
/// 记录已完成的操作，用于调试和审计
public struct OperationHistoryEntry: Codable, Identifiable, Sendable {
    /// 操作 ID
    public let id: String
    
    /// 操作类型
    public let type: OperationType
    
    /// 笔记 ID
    public let noteId: String
    
    /// 操作数据
    public let data: Data
    
    /// 创建时间
    public let createdAt: Date
    
    /// 完成时间
    public let completedAt: Date
    
    /// 最终状态
    public let status: OperationStatus
    
    /// 重试次数
    public let retryCount: Int
    
    /// 最后错误信息（如果有）
    public let lastError: String?
    
    /// 错误类型（如果有）
    public let errorType: OperationErrorType?
    
    /// 初始化
    public init(
        id: String,
        type: OperationType,
        noteId: String,
        data: Data,
        createdAt: Date,
        completedAt: Date,
        status: OperationStatus,
        retryCount: Int,
        lastError: String? = nil,
        errorType: OperationErrorType? = nil
    ) {
        self.id = id
        self.type = type
        self.noteId = noteId
        self.data = data
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.status = status
        self.retryCount = retryCount
        self.lastError = lastError
        self.errorType = errorType
    }
    
    /// 操作是否成功
    public var isSuccess: Bool {
        return status == .completed
    }
    
    /// 操作耗时（秒）
    public var duration: TimeInterval {
        return completedAt.timeIntervalSince(createdAt)
    }
}
