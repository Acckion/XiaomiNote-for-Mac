import Foundation

// MARK: - ID 映射记录

/// ID 映射记录
///
/// 记录临时 ID 和正式 ID 的映射关系。
/// 当用户离线创建笔记时，系统会生成临时 ID（格式：local_xxx），
/// 网络恢复后上传成功会获取云端下发的正式 ID。
///
/// **使用场景**：
/// - 离线创建笔记后，记录临时 ID 到正式 ID 的映射
/// - 应用重启时恢复未完成的映射
/// - 更新所有引用临时 ID 的地方
public struct IdMapping: Codable, Sendable {
    /// 临时 ID（格式：local_xxx）
    public let localId: String
    
    /// 云端下发的正式 ID
    public let serverId: String
    
    /// 实体类型（"note" 或 "folder"）
    public let entityType: String
    
    /// 创建时间
    public let createdAt: Date
    
    /// 是否已完成（所有引用都已更新）
    public var completed: Bool
    
    /// 创建新的 ID 映射记录
    ///
    /// - Parameters:
    ///   - localId: 临时 ID
    ///   - serverId: 正式 ID
    ///   - entityType: 实体类型
    ///   - createdAt: 创建时间，默认为当前时间
    ///   - completed: 是否已完成，默认为 false
    public init(
        localId: String,
        serverId: String,
        entityType: String,
        createdAt: Date = Date(),
        completed: Bool = false
    ) {
        self.localId = localId
        self.serverId = serverId
        self.entityType = entityType
        self.createdAt = createdAt
        self.completed = completed
    }
}

// MARK: - Equatable

extension IdMapping: Equatable {
    public static func == (lhs: IdMapping, rhs: IdMapping) -> Bool {
        return lhs.localId == rhs.localId && lhs.serverId == rhs.serverId
    }
}

// MARK: - Hashable

extension IdMapping: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(localId)
        hasher.combine(serverId)
    }
}
