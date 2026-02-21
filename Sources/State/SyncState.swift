import SwiftUI

/// 同步状态管理
///
/// 替代 NotesViewModel 中的同步状态管理功能，
/// 负责同步进度、离线队列、离线模式和启动序列的状态跟踪。
@MainActor
public final class SyncState: ObservableObject {
    // MARK: - 同步状态

    @Published var isSyncing = false
    @Published var syncProgress: Double = 0
    @Published var syncStatusMessage = ""
    @Published var lastSyncTime: Date?
    @Published var lastSyncedNotesCount = 0

    // MARK: - 离线队列

    @Published var isProcessingOfflineQueue = false
    @Published var offlineQueueProgress: Double = 0
    @Published var offlineQueueStatusMessage = ""
    @Published var offlineQueuePendingCount = 0

    // MARK: - 离线模式

    @Published var isOfflineMode = false
    @Published var offlineModeReason = ""

    // MARK: - 启动序列

    @Published var startupPhase: StartupSequenceManager.StartupPhase = .idle
    @Published var startupStatusMessage = ""

    // MARK: - 本地数据加载

    @Published var isLoadingLocalData = false
    @Published var localDataLoadingMessage = ""

    // MARK: - 计算属性

    var currentStatusMessage: String {
        if isOfflineMode {
            return "离线模式" + (offlineModeReason.isEmpty ? "" : "：\(offlineModeReason)")
        }
        if !startupStatusMessage.isEmpty, startupPhase != .completed, startupPhase != .idle {
            return startupStatusMessage
        }
        if isLoadingLocalData {
            return localDataLoadingMessage.isEmpty ? "正在加载本地数据..." : localDataLoadingMessage
        }
        if isProcessingOfflineQueue {
            return offlineQueueStatusMessage.isEmpty ? "正在处理离线操作..." : offlineQueueStatusMessage
        }
        if isSyncing {
            return syncStatusMessage.isEmpty ? "正在同步..." : syncStatusMessage
        }
        if lastSyncedNotesCount > 0 {
            return "已同步 \(lastSyncedNotesCount) 条笔记"
        }
        return ""
    }

    var isAnyOperationInProgress: Bool {
        isSyncing || isProcessingOfflineQueue || isLoadingLocalData
    }

    // MARK: - 离线操作队列（从 UnifiedOperationQueue 获取）

    /// 待处理的离线操作数量
    var pendingOperationsCount: Int {
        UnifiedOperationQueue.shared.getPendingOperations().count
    }

    /// 统一操作队列待上传数量
    var unifiedPendingUploadCount: Int {
        UnifiedOperationQueue.shared.getPendingUploadCount()
    }

    /// 临时 ID 笔记数量（离线创建的笔记）
    var temporaryIdNoteCount: Int {
        UnifiedOperationQueue.shared.getTemporaryIdNoteCount()
    }

    /// 离线队列失败操作数量
    var offlineQueueFailedCount: Int {
        let stats = UnifiedOperationQueue.shared.getStatistics()
        return stats["failed"] ?? 0
    }

    /// 检查笔记是否有待处理上传
    func hasPendingUpload(for noteId: String) -> Bool {
        UnifiedOperationQueue.shared.hasPendingUpload(for: noteId)
    }

    /// 检查笔记是否使用临时 ID（离线创建）
    func isTemporaryIdNote(_ noteId: String) -> Bool {
        NoteOperation.isTemporaryId(noteId)
    }

    // MARK: - 依赖

    private let eventBus: EventBus

    // MARK: - 事件订阅任务

    private var syncEventTask: Task<Void, Never>?

    // MARK: - 初始化

    init(eventBus: EventBus = .shared) {
        self.eventBus = eventBus
    }

    // MARK: - 生命周期

    func start() {
        syncEventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await eventBus.subscribe(to: SyncEvent.self)
            for await event in stream {
                guard !Task.isCancelled else { break }
                handleSyncEvent(event)
            }
        }
    }

    func stop() {
        syncEventTask?.cancel()
        syncEventTask = nil
    }

    // MARK: - 同步请求

    func requestSync(mode: SyncMode) {
        Task {
            await eventBus.publish(SyncEvent.requested(mode: mode))
        }
    }

    func requestFullSync(mode: FullSyncMode) {
        Task {
            await eventBus.publish(SyncEvent.requested(mode: .full(mode)))
        }
    }

    func updateSyncInterval(_ newInterval: Double) {
        LogService.shared.info(.sync, "更新同步间隔: \(newInterval) 秒")
    }

    // MARK: - 事件处理（内部）

    private func handleSyncEvent(_ event: SyncEvent) {
        switch event {
        case .started:
            isSyncing = true
            syncProgress = 0
            syncStatusMessage = "正在同步..."

        case let .progress(message, percent):
            syncStatusMessage = message
            syncProgress = percent

        case let .completed(result):
            isSyncing = false
            syncProgress = 1.0
            lastSyncTime = Date()
            lastSyncedNotesCount = result.downloadedCount
            syncStatusMessage = ""

        case let .failed(errorMessage):
            isSyncing = false
            syncProgress = 0
            syncStatusMessage = errorMessage
            LogService.shared.error(.sync, "同步失败: \(errorMessage)")

        case .requested, .noteDownloaded, .tagUpdated:
            break
        }
    }
}
