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

        LogService.shared.info(.sync, "SyncStateManager 初始化完成")
    }

    /// 便捷初始化方法，使用默认的 shared 实例
    static func createDefault() -> SyncStateManager {
        SyncStateManager(
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
    func getCurrentSyncTag() -> String {
        let syncStatus = localStorage.loadSyncStatus()
        let syncTag = syncStatus?.syncTag ?? ""
        LogService.shared.debug(.sync, "当前 syncTag: \(syncTag.isEmpty ? "空" : syncTag)")
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
    func stageSyncTag(_ syncTag: String, hasPendingNotes: Bool) async throws {
        LogService.shared.debug(.sync, "暂存 syncTag, 有待上传笔记: \(hasPendingNotes)")

        if !hasPendingNotes {
            try await confirmSyncTag(syncTag)
        } else {
            pendingSyncTag = syncTag
            pendingSyncTagTime = Date()
            LogService.shared.debug(.sync, "syncTag 已暂存，等待确认")
        }
    }

    /// 确认暂存的 syncTag（如果存在）
    ///
    /// 将暂存的 syncTag 持久化到本地存储，并清除内存中的暂存值。
    /// 如果不存在暂存的 syncTag，不执行任何操作。
    ///
    /// - Returns: 是否确认了 syncTag（true 表示有暂存的 syncTag 被确认）
    ///
    @discardableResult
    func confirmPendingSyncTagIfNeeded() async throws -> Bool {
        guard let syncTag = pendingSyncTag else {
            LogService.shared.debug(.sync, "没有暂存的 syncTag，无需确认")
            return false
        }

        LogService.shared.debug(.sync, "确认暂存的 syncTag")
        try await confirmSyncTag(syncTag)

        pendingSyncTag = nil
        pendingSyncTagTime = nil

        LogService.shared.info(.sync, "syncTag 已确认并持久化")
        return true
    }

    /// 检查是否有暂存的 syncTag
    ///
    /// - Returns: 如果有暂存的 syncTag 返回 true
    ///
    func hasPendingSyncTag() -> Bool {
        pendingSyncTag != nil
    }

    /// 获取暂存的 syncTag
    ///
    /// - Returns: 暂存的 syncTag，如果不存在则返回 nil
    ///
    func getPendingSyncTag() -> String? {
        pendingSyncTag
    }

    /// 获取上次同步时间
    ///
    /// 从 LocalStorageService 加载 SyncStatus 并返回 lastSyncTime。
    ///
    /// - Returns: 上次同步时间，如果不存在则返回 nil
    ///
    func getLastSyncTime() -> Date? {
        let syncStatus = localStorage.loadSyncStatus()
        let lastSyncTime = syncStatus?.lastSyncTime
        LogService.shared.debug(.sync, "上次同步时间: \(lastSyncTime?.description ?? "无")")
        return lastSyncTime
    }

    /// 检查是否有待上传笔记
    ///
    /// 通过 UnifiedOperationQueue 查询是否有待上传的笔记。
    ///
    /// - Returns: 如果有待上传笔记返回 true
    ///
    func hasPendingUploadNotes() -> Bool {
        checkHasPendingUploadNotes()
    }

    /// 清除暂存的 syncTag（用于错误恢复）
    ///
    /// 在某些错误情况下，可能需要清除暂存的 syncTag 重新开始。
    ///
    func clearPendingSyncTag() {
        LogService.shared.debug(.sync, "清除暂存的 syncTag")
        pendingSyncTag = nil
        pendingSyncTagTime = nil
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
    private func confirmSyncTag(_ syncTag: String) async throws {
        let syncStatus = SyncStatus(
            lastSyncTime: Date(),
            syncTag: syncTag
        )

        do {
            try localStorage.saveSyncStatus(syncStatus)
            LogService.shared.debug(.sync, "syncTag 已持久化")
        } catch {
            LogService.shared.error(.sync, "存储操作失败: \(error.localizedDescription)")
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
    private func checkHasPendingUploadNotes() -> Bool {
        // 查询 UnifiedOperationQueue 获取待上传笔记数量
        let pendingCount = operationQueue.getPendingUploadCount()
        LogService.shared.debug(.sync, "待上传笔记数量: \(pendingCount)")

        // 返回是否大于 0
        return pendingCount > 0
    }
}

// MARK: - 错误类型

/// 同步状态管理器错误类型
///
/// 定义了 SyncStateManager 可能抛出的所有错误类型。
///
enum SyncStateError: Error, LocalizedError {
    /// 存储操作失败
    case storageOperationFailed(Error)

    /// 操作队列不可用
    case operationQueueUnavailable

    /// 无效状态
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case let .storageOperationFailed(error):
            "存储操作失败: \(error.localizedDescription)"
        case .operationQueueUnavailable:
            "操作队列不可用"
        case let .invalidState(message):
            "无效状态: \(message)"
        }
    }
}
