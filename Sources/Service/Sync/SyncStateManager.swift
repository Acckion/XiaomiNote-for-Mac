import Foundation

/// 同步状态管理器
///
/// 负责统一管理 syncTag 的获取、更新和确认，确保数据一致性。
///
/// 核心功能：
/// - syncTag 获取：从 LocalStorageService 加载当前的 syncTag
/// - syncTag 暂存：将从服务器获取的 syncTag 暂存在内存中
/// - syncTag 确认：在所有待上传操作完成后，将暂存的 syncTag 持久化
/// - 状态查询：查询是否有暂存的 syncTag、待上传笔记等
///
/// 线程安全：使用 actor 隔离确保所有状态访问都是线程安全的
///
actor SyncStateManager {
    
    // MARK: - 依赖
    
    /// 本地存储服务
    private let localStorage: LocalStorageService
    
    /// 统一操作队列
    private let operationQueue: UnifiedOperationQueue
    
    // MARK: - 内存状态
    
    /// 暂存的 syncTag（尚未确认）
    private var pendingSyncTag: String?
    
    /// 暂存 syncTag 的时间
    private var pendingSyncTagTime: Date?
    
    // MARK: - 初始化
    
    /// 初始化同步状态管理器
    ///
    /// - Parameters:
    ///   - localStorage: 本地存储服务
    ///   - operationQueue: 统一操作队列
    init(
        localStorage: LocalStorageService,
        operationQueue: UnifiedOperationQueue
    ) {
        self.localStorage = localStorage
        self.operationQueue = operationQueue
        
        print("[SyncStateManager] 初始化完成")
    }
    
    /// 便捷初始化方法，使用默认的 shared 实例
    static func createDefault() -> SyncStateManager {
        return SyncStateManager(
            localStorage: .shared,
            operationQueue: .shared
        )
    }
    
    // MARK: - 公共接口
    
    /// 获取当前的 syncTag
    ///
    /// 从 LocalStorageService 加载 SyncStatus 并返回 syncTag。
    /// 如果不存在 syncTag，返回空字符串。
    ///
    /// - Returns: 当前的 syncTag，如果不存在则返回空字符串
    ///
    /// **验证: 需求 1.1, 1.2**
    func getCurrentSyncTag() -> String {
        print("[SyncStateManager] 🔍 获取当前 syncTag")
        
        // 从 LocalStorageService 加载 SyncStatus
        let syncStatus = localStorage.loadSyncStatus()
        
        // 获取 syncTag，如果不存在返回空字符串
        let syncTag = syncStatus?.syncTag ?? ""
        
        print("[SyncStateManager] ✅ 当前 syncTag: \(syncTag.isEmpty ? "空字符串" : syncTag)")
        
        return syncTag
    }
    
    /// 暂存新的 syncTag
    ///
    /// 如果没有待上传笔记，直接确认并持久化；
    /// 如果有待上传笔记，只暂存在内存中。
    ///
    /// - Parameters:
    ///   - syncTag: 新的 syncTag
    ///   - hasPendingNotes: 是否有待上传笔记
    ///
    /// **验证: 需求 2.1, 2.2, 2.3, 2.4**
    func stageSyncTag(_ syncTag: String, hasPendingNotes: Bool) async throws {
        print("[SyncStateManager] 📝 暂存 syncTag: \(syncTag), 有待上传笔记: \(hasPendingNotes)")
        
        // 检查是否有待上传笔记
        if !hasPendingNotes {
            // 没有待上传笔记，直接确认并持久化
            print("[SyncStateManager] ✅ 没有待上传笔记，直接确认并持久化")
            try await confirmSyncTag(syncTag)
        } else {
            // 有待上传笔记，暂存到内存中
            print("[SyncStateManager] ⏳ 有待上传笔记，暂存到内存中")
            pendingSyncTag = syncTag
            pendingSyncTagTime = Date()
            print("[SyncStateManager] ✅ syncTag 已暂存，等待确认")
        }
    }
    
    /// 确认暂存的 syncTag（如果存在）
    ///
    /// 将暂存的 syncTag 持久化到本地存储，并清除内存中的暂存值。
    /// 如果不存在暂存的 syncTag，不执行任何操作。
    ///
    /// - Returns: 是否确认了 syncTag（true 表示有暂存的 syncTag 被确认）
    ///
    /// **验证: 需求 3.1, 3.2, 3.3, 3.4**
    @discardableResult
    func confirmPendingSyncTagIfNeeded() async throws -> Bool {
        print("[SyncStateManager] 🔍 检查是否有暂存的 syncTag 需要确认")
        
        // 检查是否有暂存的 syncTag
        guard let syncTag = pendingSyncTag else {
            print("[SyncStateManager] ℹ️ 没有暂存的 syncTag，无需确认")
            return false
        }
        
        print("[SyncStateManager] ✅ 发现暂存的 syncTag: \(syncTag)，开始确认")
        
        // 调用 confirmSyncTag() 持久化
        try await confirmSyncTag(syncTag)
        
        // 清除 pendingSyncTag 和 pendingSyncTagTime
        pendingSyncTag = nil
        pendingSyncTagTime = nil
        
        print("[SyncStateManager] ✅ syncTag 已确认并持久化，暂存值已清除")
        
        return true
    }
    
    /// 检查是否有暂存的 syncTag
    ///
    /// - Returns: 如果有暂存的 syncTag 返回 true
    ///
    /// **验证: 需求 7.1**
    func hasPendingSyncTag() -> Bool {
        return pendingSyncTag != nil
    }
    
    /// 获取暂存的 syncTag
    ///
    /// - Returns: 暂存的 syncTag，如果不存在则返回 nil
    ///
    /// **验证: 需求 7.2**
    func getPendingSyncTag() -> String? {
        return pendingSyncTag
    }
    
    /// 获取上次同步时间
    ///
    /// 从 LocalStorageService 加载 SyncStatus 并返回 lastSyncTime。
    ///
    /// - Returns: 上次同步时间，如果不存在则返回 nil
    ///
    /// **验证: 需求 7.3**
    func getLastSyncTime() -> Date? {
        print("[SyncStateManager] 🔍 获取上次同步时间")
        
        // 从 LocalStorageService 加载 SyncStatus
        let syncStatus = localStorage.loadSyncStatus()
        
        // 返回 lastSyncTime
        let lastSyncTime = syncStatus?.lastSyncTime
        
        if let time = lastSyncTime {
            print("[SyncStateManager] ✅ 上次同步时间: \(time)")
        } else {
            print("[SyncStateManager] ℹ️ 没有上次同步时间记录")
        }
        
        return lastSyncTime
    }
    
    /// 检查是否有待上传笔记
    ///
    /// 通过 UnifiedOperationQueue 查询是否有待上传的笔记。
    ///
    /// - Returns: 如果有待上传笔记返回 true
    ///
    /// **验证: 需求 7.4**
    func hasPendingUploadNotes() -> Bool {
        return checkHasPendingUploadNotes()
    }
    
    /// 清除暂存的 syncTag（用于错误恢复）
    ///
    /// 在某些错误情况下，可能需要清除暂存的 syncTag 重新开始。
    ///
    /// **验证: 需求 8.3**
    func clearPendingSyncTag() {
        print("[SyncStateManager] 🗑️ 清除暂存的 syncTag")
        
        if pendingSyncTag != nil {
            print("[SyncStateManager] ℹ️ 清除暂存的 syncTag: \(pendingSyncTag!)")
        }
        
        // 清除 pendingSyncTag 和 pendingSyncTagTime
        pendingSyncTag = nil
        pendingSyncTagTime = nil
        
        print("[SyncStateManager] ✅ 暂存的 syncTag 已清除")
    }
    
    // MARK: - 私有辅助方法
    
    /// 直接确认并持久化 syncTag
    ///
    /// 创建 SyncStatus 对象并将其持久化到 LocalStorageService。
    /// 如果存储操作失败，抛出 SyncStateError.storageOperationFailed。
    ///
    /// - Parameter syncTag: 要持久化的 syncTag
    /// - Throws: SyncStateError.storageOperationFailed 如果存储操作失败
    ///
    /// **验证: 需求 3.2**
    private func confirmSyncTag(_ syncTag: String) async throws {
        print("[SyncStateManager] 💾 开始确认并持久化 syncTag: \(syncTag)")
        
        // 创建 SyncStatus 对象
        let syncStatus = SyncStatus(
            lastSyncTime: Date(),
            syncTag: syncTag
        )
        
        do {
            // 调用 LocalStorageService.saveSyncStatus()
            try localStorage.saveSyncStatus(syncStatus)
            print("[SyncStateManager] ✅ syncTag 已成功持久化")
        } catch {
            // 处理存储失败的情况
            print("[SyncStateManager] ❌ 存储操作失败: \(error.localizedDescription)")
            throw SyncStateError.storageOperationFailed(error)
        }
    }
    
    /// 检查操作队列中是否有待上传笔记
    ///
    /// 查询 UnifiedOperationQueue 获取待上传笔记数量（cloudUpload 或 noteCreate 操作）。
    /// 如果操作队列不可用，记录警告并假设没有待上传笔记。
    ///
    /// - Returns: 如果有待上传笔记返回 true
    ///
    /// **验证: 需求 4.1, 4.2, 4.3, 8.2**
    private func checkHasPendingUploadNotes() -> Bool {
        // 查询 UnifiedOperationQueue 获取待上传笔记数量
        let pendingCount = operationQueue.getPendingUploadCount()
        
        print("[SyncStateManager] 🔍 检查待上传笔记数量: \(pendingCount)")
        
        // 返回是否大于 0
        return pendingCount > 0
    }
}

// MARK: - 错误类型

/// 同步状态管理器错误类型
///
/// 定义了 SyncStateManager 可能抛出的所有错误类型。
///
/// **验证: 需求 8.1, 8.2, 8.4**
enum SyncStateError: Error, LocalizedError {
    /// 存储操作失败
    case storageOperationFailed(Error)
    
    /// 操作队列不可用
    case operationQueueUnavailable
    
    /// 无效状态
    case invalidState(String)
    
    var errorDescription: String? {
        switch self {
        case .storageOperationFailed(let error):
            return "存储操作失败: \(error.localizedDescription)"
        case .operationQueueUnavailable:
            return "操作队列不可用"
        case .invalidState(let message):
            return "无效状态: \(message)"
        }
    }
}
