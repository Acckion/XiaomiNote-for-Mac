import Foundation

// MARK: - ⚠️ 废弃警告
// 此文件中的组件已被废弃，请使用新的统一操作队列系统
// 迁移指南：
// - SyncProtectionFilter -> SyncGuard
// - 同步保护检查现在由 SyncGuard 统一处理
// - SyncGuard 依赖 UnifiedOperationQueue 和 NoteOperationCoordinator

/// 同步保护过滤器
/// 
/// 在同步时过滤掉不应被更新的笔记
/// 用于 SyncService 在处理云端更新前检查笔记是否应该被跳过
/// 
/// - Important: 此结构体已废弃，请使用 `SyncGuard` 替代
/// 
/// ## 迁移指南
/// 
/// ### 旧代码
/// ```swift
/// let filter = SyncProtectionFilter()
/// let shouldSkip = await filter.shouldSkipSync(noteId: noteId, cloudTimestamp: timestamp)
/// let reason = await filter.getSkipReason(noteId: noteId, cloudTimestamp: timestamp)
/// ```
/// 
/// ### 新代码
/// ```swift
/// let guard = SyncGuard()
/// let shouldSkip = await guard.shouldSkipSync(noteId: noteId, cloudTimestamp: timestamp)
/// let reason = await guard.getSkipReason(noteId: noteId, cloudTimestamp: timestamp)
/// ```
/// 
/// 新的实现特点：
/// - 依赖 UnifiedOperationQueue 而非 PendingUploadRegistry
/// - 支持临时 ID 笔记的检查
/// - 更完整的跳过原因枚举
/// - 与新的操作队列系统完全集成
/// 
/// **需求覆盖**：
/// - 需求 2.1: 检查笔记是否在 PendingUploadRegistry 中
/// - 需求 2.2: 待上传笔记跳过同步
/// - 需求 2.3: 比较时间戳
/// - 需求 2.4: 正常笔记执行同步
/// - 需求 3.2: 活跃编辑笔记跳过同步
@available(*, deprecated, message: "请使用 SyncGuard 替代，同步保护功能已重构")
public struct SyncProtectionFilter: Sendable {
    
    // MARK: - 依赖
    
    private let coordinator: NoteOperationCoordinator
    private let registry: PendingUploadRegistry
    
    // MARK: - 初始化
    
    /// 创建同步保护过滤器
    /// 
    /// - Parameters:
    ///   - coordinator: 笔记操作协调器
    ///   - registry: 待上传注册表
    public init(
        coordinator: NoteOperationCoordinator = .shared,
        registry: PendingUploadRegistry = .shared
    ) {
        self.coordinator = coordinator
        self.registry = registry
    }
    
    // MARK: - 同步保护检查
    
    /// 检查笔记是否应该被同步跳过
    /// 
    /// 检查顺序：
    /// 1. 检查是否正在编辑（活跃编辑保护）
    /// 2. 检查是否在待上传列表中（待上传保护）
    /// 3. 比较时间戳（本地较新时跳过）
    /// 
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - cloudTimestamp: 云端时间戳
    /// - Returns: 是否应该跳过同步
    /// 
    /// **需求覆盖**：
    /// - 需求 2.1: 检查是否在 PendingUploadRegistry 中
    /// - 需求 2.2: 待上传笔记跳过同步
    /// - 需求 2.3: 本地较新时跳过
    /// - 需求 3.2: 活跃编辑笔记跳过同步
    public func shouldSkipSync(noteId: String, cloudTimestamp: Date) async -> Bool {
        // 使用协调器的统一检查方法
        let canUpdate = await coordinator.canSyncUpdateNote(noteId, cloudTimestamp: cloudTimestamp)
        return !canUpdate
    }
    
    /// 检查笔记是否正在编辑
    /// 
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否正在编辑
    /// 
    /// **需求覆盖**：
    /// - 需求 3.2: 活跃编辑笔记跳过同步
    public func isActivelyEditing(noteId: String) async -> Bool {
        return await coordinator.isNoteActivelyEditing(noteId)
    }
    
    /// 检查笔记是否在待上传列表中
    /// 
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否在待上传列表中
    /// 
    /// **需求覆盖**：
    /// - 需求 2.1: 检查是否在 PendingUploadRegistry 中
    public func isPendingUpload(noteId: String) -> Bool {
        return registry.isRegistered(noteId)
    }
    
    /// 获取笔记的本地保存时间戳
    /// 
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 本地保存时间戳，如果不在待上传列表中返回 nil
    public func getLocalSaveTimestamp(noteId: String) -> Date? {
        return registry.getLocalSaveTimestamp(noteId)
    }
    
    /// 获取跳过同步的原因
    /// 
    /// 用于日志记录和调试
    /// 
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - cloudTimestamp: 云端时间戳
    /// - Returns: 跳过原因，如果不应该跳过则返回 nil
    public func getSkipReason(noteId: String, cloudTimestamp: Date) async -> SkipReason? {
        // 1. 检查是否正在编辑
        if await coordinator.isNoteActivelyEditing(noteId) {
            return .activelyEditing
        }
        
        // 2. 检查是否在待上传列表中
        if registry.isRegistered(noteId) {
            if let localTimestamp = registry.getLocalSaveTimestamp(noteId) {
                if localTimestamp >= cloudTimestamp {
                    return .localNewer(localTimestamp: localTimestamp, cloudTimestamp: cloudTimestamp)
                } else {
                    return .pendingUpload
                }
            }
            return .pendingUpload
        }
        
        return nil
    }
}

// MARK: - 跳过原因

/// 同步跳过原因
/// 
/// - Important: 此枚举已废弃，请使用 `SyncGuard.SkipReason` 替代
@available(*, deprecated, message: "请使用 SyncGuard 中的 SkipReason 替代")
public enum SkipReason: Sendable, Equatable {
    /// 笔记正在编辑
    case activelyEditing
    /// 笔记在待上传列表中
    case pendingUpload
    /// 本地版本较新
    case localNewer(localTimestamp: Date, cloudTimestamp: Date)
    
    /// 获取描述信息
    public var description: String {
        switch self {
        case .activelyEditing:
            return "笔记正在编辑"
        case .pendingUpload:
            return "笔记在待上传列表中"
        case .localNewer(let localTimestamp, let cloudTimestamp):
            return "本地版本较新 (本地: \(localTimestamp), 云端: \(cloudTimestamp))"
        }
    }
}
