import Foundation

// MARK: - 同步保护器

/// 同步保护器
///
/// 在同步时过滤掉不应被更新的笔记，防止同步覆盖本地修改。
/// 替代旧的 SyncProtectionFilter，使用 UnifiedOperationQueue 作为数据源。
///
/// **检查顺序**：
/// 1. 检查是否为临时 ID（离线创建的笔记）
/// 2. 检查是否正在编辑（活跃编辑保护）
/// 3. 检查是否有待处理上传（待上传保护）
/// 4. 比较时间戳（本地较新时跳过）
public struct SyncGuard: Sendable {
    
    // MARK: - 依赖
    
    /// 统一操作队列
    private let operationQueue: UnifiedOperationQueue
    
    /// 笔记操作协调器
    private let coordinator: NoteOperationCoordinator
    
    // MARK: - 初始化
    
    /// 创建同步保护器
    ///
    /// - Parameters:
    ///   - operationQueue: 统一操作队列
    ///   - coordinator: 笔记操作协调器
    public init(
        operationQueue: UnifiedOperationQueue = .shared,
        coordinator: NoteOperationCoordinator = .shared
    ) {
        self.operationQueue = operationQueue
        self.coordinator = coordinator
    }
}


// MARK: - 同步保护检查

extension SyncGuard {
    
    /// 检查笔记是否应该被同步跳过
    ///
    /// 检查顺序：
    /// 1. 检查是否为临时 ID（离线创建的笔记不会出现在云端）
    /// 2. 检查是否正在编辑（活跃编辑保护）
    /// 3. 检查是否有待处理上传（待上传保护）
    /// 4. 比较时间戳（本地较新时跳过）
    ///
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - cloudTimestamp: 云端时间戳
    /// - Returns: 是否应该跳过同步
    ///
    /// **需求覆盖**：
    /// - 需求 4.2: 待上传笔记跳过同步
    /// - 需求 4.3: 活跃编辑笔记跳过同步
    /// - 需求 4.4: 无待处理操作且未在编辑时允许同步
    /// - 需求 8.3: 临时 ID 笔记跳过同步
    public func shouldSkipSync(noteId: String, cloudTimestamp: Date) async -> Bool {
        // 1. 检查是否为临时 ID（离线创建的笔记）
        // 临时 ID 笔记不会出现在云端，不需要同步
        if NoteOperation.isTemporaryId(noteId) {
            print("[SyncGuard] 🛡️ 跳过同步: 临时 ID 笔记 \(noteId.prefix(8))...")
            return true
        }
        
        // 2. 检查是否正在编辑
        let isEditing = await coordinator.isNoteActivelyEditing(noteId)
        if isEditing {
            print("[SyncGuard] 🛡️ 跳过同步: 笔记正在编辑 \(noteId.prefix(8))...")
            return true
        }
        
        // 3. 检查是否有待处理上传
        if operationQueue.hasPendingUpload(for: noteId) {
            // 比较时间戳
            if let localTimestamp = operationQueue.getLocalSaveTimestamp(for: noteId) {
                if localTimestamp >= cloudTimestamp {
                    print("[SyncGuard] 🛡️ 跳过同步: 本地较新 \(noteId.prefix(8))... (本地: \(localTimestamp), 云端: \(cloudTimestamp))")
                    return true
                }
            }
            // 即使云端较新，但笔记在待上传列表中，也应该跳过（用户优先策略）
            print("[SyncGuard] 🛡️ 跳过同步: 待上传中 \(noteId.prefix(8))...")
            return true
        }
        
        // 4. 检查是否有待处理的 noteCreate 操作
        if operationQueue.hasPendingNoteCreate(for: noteId) {
            print("[SyncGuard] 🛡️ 跳过同步: 待创建中 \(noteId.prefix(8))...")
            return true
        }
        
        // 5. 无保护条件，允许同步
        return false
    }
    
    /// 检查笔记是否正在编辑
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否正在编辑
    ///
    /// **需求覆盖**：
    /// - 需求 4.3: 活跃编辑笔记跳过同步
    public func isActivelyEditing(noteId: String) async -> Bool {
        return await coordinator.isNoteActivelyEditing(noteId)
    }
    
    /// 检查笔记是否有待处理上传
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否有待处理上传
    ///
    /// **需求覆盖**：
    /// - 需求 4.1: 查询 UnifiedOperationQueue 中是否有该笔记的待处理上传
    public func hasPendingUpload(noteId: String) -> Bool {
        return operationQueue.hasPendingUpload(for: noteId)
    }
    
    /// 获取笔记的本地保存时间戳
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 本地保存时间戳，如果没有则返回 nil
    public func getLocalSaveTimestamp(noteId: String) -> Date? {
        return operationQueue.getLocalSaveTimestamp(for: noteId)
    }
    
    /// 检查笔记是否为临时 ID
    ///
    /// - Parameter noteId: 笔记 ID
    /// - Returns: 是否为临时 ID
    ///
    /// **需求覆盖**：
    /// - 需求 8.3: 临时 ID 笔记跳过同步
    public func isTemporaryId(_ noteId: String) -> Bool {
        return NoteOperation.isTemporaryId(noteId)
    }
}


// MARK: - 跳过原因

extension SyncGuard {
    
    /// 获取跳过同步的原因
    ///
    /// 用于日志记录和调试
    ///
    /// - Parameters:
    ///   - noteId: 笔记 ID
    ///   - cloudTimestamp: 云端时间戳
    /// - Returns: 跳过原因，如果不应该跳过则返回 nil
    ///
    /// **需求覆盖**：
    /// - 需求 4.2: 返回跳过原因用于日志
    public func getSkipReason(noteId: String, cloudTimestamp: Date) async -> SyncSkipReason? {
        // 1. 检查是否为临时 ID
        if NoteOperation.isTemporaryId(noteId) {
            return .temporaryId
        }
        
        // 2. 检查是否正在编辑
        if await coordinator.isNoteActivelyEditing(noteId) {
            return .activelyEditing
        }
        
        // 3. 检查是否有待处理上传
        if operationQueue.hasPendingUpload(for: noteId) {
            if let localTimestamp = operationQueue.getLocalSaveTimestamp(for: noteId) {
                if localTimestamp >= cloudTimestamp {
                    return .localNewer(localTimestamp: localTimestamp, cloudTimestamp: cloudTimestamp)
                } else {
                    return .pendingUpload
                }
            }
            return .pendingUpload
        }
        
        // 4. 检查是否有待处理的 noteCreate 操作
        if operationQueue.hasPendingNoteCreate(for: noteId) {
            return .pendingCreate
        }
        
        return nil
    }
}

// MARK: - 同步跳过原因

/// 同步跳过原因
///
/// 用于日志记录和调试，描述为什么笔记被跳过同步
public enum SyncSkipReason: Sendable, Equatable {
    /// 笔记使用临时 ID（离线创建）
    case temporaryId
    /// 笔记正在编辑
    case activelyEditing
    /// 笔记在待上传列表中
    case pendingUpload
    /// 笔记在待创建列表中
    case pendingCreate
    /// 本地版本较新
    case localNewer(localTimestamp: Date, cloudTimestamp: Date)
    
    /// 获取描述信息
    public var description: String {
        switch self {
        case .temporaryId:
            return "笔记使用临时 ID（离线创建）"
        case .activelyEditing:
            return "笔记正在编辑"
        case .pendingUpload:
            return "笔记在待上传列表中"
        case .pendingCreate:
            return "笔记在待创建列表中"
        case .localNewer(let localTimestamp, let cloudTimestamp):
            return "本地版本较新 (本地: \(localTimestamp), 云端: \(cloudTimestamp))"
        }
    }
}
