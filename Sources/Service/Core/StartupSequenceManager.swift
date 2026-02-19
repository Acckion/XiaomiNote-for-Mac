import Combine
import Foundation
import OSLog

/// 启动序列管理器
///
/// 负责协调应用启动时的各个步骤，确保按正确顺序执行：
/// 1. 加载本地数据
/// 2. 处理离线队列
/// 3. 执行完整同步
///
@MainActor
final class StartupSequenceManager: ObservableObject {

    // MARK: - 启动阶段枚举

    /// 启动序列状态
    enum StartupPhase: Equatable {
        case idle // 空闲
        case loadingLocalData // 加载本地数据
        case processingOfflineQueue // 处理离线队列
        case syncing // 同步中
        case completed // 完成
        case failed(StartupError) // 失败

        static func == (lhs: StartupPhase, rhs: StartupPhase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.loadingLocalData, .loadingLocalData),
                 (.processingOfflineQueue, .processingOfflineQueue),
                 (.syncing, .syncing),
                 (.completed, .completed):
                true
            case let (.failed(lhsError), .failed(rhsError)):
                lhsError.phase == rhsError.phase
            default:
                false
            }
        }
    }

    // MARK: - 启动状态数据结构

    /// 启动状态
    struct StartupState {
        /// 是否已完成本地数据加载
        var localDataLoaded = false

        /// 是否已处理离线队列
        var offlineQueueProcessed = false

        /// 是否已完成同步
        var syncCompleted = false

        /// 启动时间戳
        var startTime = Date()

        /// 完成时间戳
        var completionTime: Date?

        /// 错误列表（每个步骤的错误）
        var errors: [StartupError] = []

        /// 加载的笔记数量
        var loadedNotesCount = 0

        /// 加载的文件夹数量
        var loadedFoldersCount = 0

        /// 处理的离线操作数量
        var processedOfflineOperationsCount = 0

        /// 同步的笔记数量
        var syncedNotesCount = 0
    }

    /// 启动错误
    struct StartupError: Error, Equatable {
        let phase: String
        let message: String
        let timestamp: Date

        init(phase: StartupPhase, error: Error) {
            switch phase {
            case .loadingLocalData:
                self.phase = "loadingLocalData"
            case .processingOfflineQueue:
                self.phase = "processingOfflineQueue"
            case .syncing:
                self.phase = "syncing"
            default:
                self.phase = "unknown"
            }
            self.message = error.localizedDescription
            self.timestamp = Date()
        }

        init(phase: String, message: String) {
            self.phase = phase
            self.message = message
            self.timestamp = Date()
        }

        static func == (lhs: StartupError, rhs: StartupError) -> Bool {
            lhs.phase == rhs.phase && lhs.message == rhs.message
        }
    }

    // MARK: - Published 属性

    /// 当前阶段
    @Published var currentPhase: StartupPhase = .idle

    /// 启动序列是否完成
    @Published var isCompleted = false

    /// 错误信息
    @Published var errorMessage: String?

    /// 启动状态
    @Published private(set) var startupState = StartupState()

    /// 状态消息（用于UI显示）
    @Published var statusMessage = ""

    // MARK: - 依赖服务

    private let localStorage = LocalStorageService.shared
    private let onlineStateManager = OnlineStateManager.shared
    /// 新的操作处理器（替代旧的 OfflineOperationProcessor）
    private let operationProcessor = OperationProcessor.shared
    /// 统一操作队列（替代旧的 OfflineOperationQueue）
    private let unifiedQueue = UnifiedOperationQueue.shared
    private let syncService = SyncService.shared
    private let miNoteService = MiNoteService.shared

    // MARK: - Combine 订阅

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    init() {
        LogService.shared.debug(.core, "StartupSequenceManager 初始化")
    }

    // MARK: - 公共方法

    /// 执行启动序列
    ///
    /// 按顺序执行：加载本地数据 → 处理离线队列 → 执行同步
    func executeStartupSequence() async {
        LogService.shared.info(.core, "开始执行启动序列")

        // 重置状态
        startupState = StartupState()
        startupState.startTime = Date()
        isCompleted = false
        errorMessage = nil

        // 步骤 1: 加载本地数据
        await executeLoadLocalData()

        // 步骤 2: 处理离线队列（即使步骤1失败也继续）
        await executeProcessOfflineQueue()

        // 步骤 3: 执行同步（即使前面步骤失败也继续）
        await executePerformSync()

        // 完成启动序列
        completeStartupSequence()
    }

    /// 重置启动序列状态
    func reset() {
        currentPhase = .idle
        isCompleted = false
        errorMessage = nil
        startupState = StartupState()
        statusMessage = ""
        LogService.shared.debug(.core, "StartupSequenceManager 状态已重置")
    }

    // MARK: - 私有方法 - 启动序列步骤

    private func executeLoadLocalData() async {
        LogService.shared.info(.core, "步骤1: 加载本地数据")
        currentPhase = .loadingLocalData
        statusMessage = "正在加载本地数据..."

        do {
            try await loadLocalData()
            startupState.localDataLoaded = true
            LogService.shared.info(.core, "本地数据加载完成")
        } catch {
            let startupError = StartupError(phase: .loadingLocalData, error: error)
            startupState.errors.append(startupError)
            LogService.shared.warning(.core, "本地数据加载失败: \(error.localizedDescription)")
        }
    }

    private func executeProcessOfflineQueue() async {
        LogService.shared.info(.core, "步骤2: 处理离线队列")
        currentPhase = .processingOfflineQueue
        statusMessage = "正在处理离线操作..."

        do {
            try await processOfflineQueue()
            startupState.offlineQueueProcessed = true
            LogService.shared.info(.core, "离线队列处理完成")
        } catch {
            let startupError = StartupError(phase: .processingOfflineQueue, error: error)
            startupState.errors.append(startupError)
            LogService.shared.warning(.core, "离线队列处理失败: \(error.localizedDescription)")
        }
    }

    private func executePerformSync() async {
        LogService.shared.info(.core, "步骤3: 执行同步")
        currentPhase = .syncing
        statusMessage = "正在同步数据..."

        do {
            try await performSync()
            startupState.syncCompleted = true
            LogService.shared.info(.core, "同步完成")
        } catch {
            let startupError = StartupError(phase: .syncing, error: error)
            startupState.errors.append(startupError)
            LogService.shared.warning(.core, "同步失败: \(error.localizedDescription)")
        }
    }

    private func completeStartupSequence() {
        startupState.completionTime = Date()
        let duration = startupState.completionTime?.timeIntervalSince(startupState.startTime) ?? 0

        if !startupState.errors.isEmpty {
            let errorMessages = startupState.errors.map(\.message).joined(separator: "; ")
            errorMessage = errorMessages
            currentPhase = .failed(startupState.errors.first!)
            LogService.shared.warning(.core, "启动序列完成，有错误: \(errorMessages)")
        } else {
            currentPhase = .completed
            LogService.shared.info(
                .core,
                "启动序列完成，耗时 \(String(format: "%.2f", duration))s，笔记 \(startupState.loadedNotesCount) 条，文件夹 \(startupState.loadedFoldersCount) 个"
            )
        }

        isCompleted = true
        statusMessage = "启动完成"
        NotificationCenter.default.post(
            name: .startupSequenceCompleted,
            object: nil,
            userInfo: [
                "success": startupState.errors.isEmpty,
                "errors": startupState.errors.map(\.message),
                "duration": duration,
            ]
        )
    }

    // MARK: - 私有方法 - 具体实现

    private func loadLocalData() async throws {
        let notes = try localStorage.getAllLocalNotes()
        startupState.loadedNotesCount = notes.count

        let folders = try localStorage.loadFolders()
        startupState.loadedFoldersCount = folders.count
    }

    private func processOfflineQueue() async throws {
        let pendingOperations = unifiedQueue.getPendingOperations()

        if pendingOperations.isEmpty {
            return
        }

        LogService.shared.debug(.core, "发现 \(pendingOperations.count) 个待处理操作")

        guard onlineStateManager.isOnline else {
            LogService.shared.debug(.core, "网络不可用，保留队列中的操作")
            return
        }

        await operationProcessor.processQueue()

        let stats = unifiedQueue.getStatistics()
        let processedCount = (stats["total"] ?? 0) - pendingOperations.count
        startupState.processedOfflineOperationsCount = max(0, processedCount)

        let remainingOperations = unifiedQueue.getPendingOperations()
        if !remainingOperations.isEmpty {
            LogService.shared.debug(.core, "还有 \(remainingOperations.count) 个操作待处理")
        }
    }

    private func performSync() async throws {
        guard miNoteService.isAuthenticated() else {
            LogService.shared.debug(.core, "用户未登录，跳过同步")
            return
        }

        guard onlineStateManager.isOnline else {
            LogService.shared.debug(.core, "网络不可用，跳过同步")
            return
        }

        let result = try await syncService.performSmartSync()
        startupState.syncedNotesCount = result.syncedNotes
    }
}

// MARK: - 通知扩展

public extension Notification.Name {
    /// 启动序列完成通知
    static let startupSequenceCompleted = Notification.Name("startupSequenceCompleted")
}
