import Foundation
import Combine

/// 启动序列管理器
///
/// 负责协调应用启动时的各个步骤，确保按正确顺序执行：
/// 1. 加载本地数据
/// 2. 处理离线队列
/// 3. 执行完整同步
///
/// 遵循需求 2.1, 2.2, 2.3, 2.4 的规定
@MainActor
final class StartupSequenceManager: ObservableObject {
    
    // MARK: - 启动阶段枚举
    
    /// 启动序列状态
    enum StartupPhase: Equatable {
        case idle                    // 空闲
        case loadingLocalData        // 加载本地数据
        case processingOfflineQueue  // 处理离线队列
        case syncing                 // 同步中
        case completed               // 完成
        case failed(StartupError)    // 失败
        
        static func == (lhs: StartupPhase, rhs: StartupPhase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.loadingLocalData, .loadingLocalData),
                 (.processingOfflineQueue, .processingOfflineQueue),
                 (.syncing, .syncing),
                 (.completed, .completed):
                return true
            case (.failed(let lhsError), .failed(let rhsError)):
                return lhsError.phase == rhsError.phase
            default:
                return false
            }
        }
    }
    
    // MARK: - 启动状态数据结构
    
    /// 启动状态
    struct StartupState {
        /// 是否已完成本地数据加载
        var localDataLoaded: Bool = false
        
        /// 是否已处理离线队列
        var offlineQueueProcessed: Bool = false
        
        /// 是否已完成同步
        var syncCompleted: Bool = false
        
        /// 启动时间戳
        var startTime: Date = Date()
        
        /// 完成时间戳
        var completionTime: Date?
        
        /// 错误列表（每个步骤的错误）
        var errors: [StartupError] = []
        
        /// 加载的笔记数量
        var loadedNotesCount: Int = 0
        
        /// 加载的文件夹数量
        var loadedFoldersCount: Int = 0
        
        /// 处理的离线操作数量
        var processedOfflineOperationsCount: Int = 0
        
        /// 同步的笔记数量
        var syncedNotesCount: Int = 0
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
            return lhs.phase == rhs.phase && lhs.message == rhs.message
        }
    }
    
    // MARK: - Published 属性
    
    /// 当前阶段
    @Published var currentPhase: StartupPhase = .idle
    
    /// 启动序列是否完成
    @Published var isCompleted: Bool = false
    
    /// 错误信息
    @Published var errorMessage: String?
    
    /// 启动状态
    @Published private(set) var startupState: StartupState = StartupState()
    
    /// 状态消息（用于UI显示）
    @Published var statusMessage: String = ""
    
    // MARK: - 依赖服务
    
    private let localStorage = LocalStorageService.shared
    private let onlineStateManager = OnlineStateManager.shared
    private let offlineProcessor = OfflineOperationProcessor.shared
    private let offlineQueue = OfflineOperationQueue.shared
    private let syncService = SyncService.shared
    private let miNoteService = MiNoteService.shared
    
    // MARK: - Combine 订阅
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    init() {
        print("[StartupSequenceManager] 初始化")
    }
    
    // MARK: - 公共方法
    
    /// 执行启动序列
    ///
    /// 按顺序执行：加载本地数据 → 处理离线队列 → 执行同步
    /// 遵循需求 2.1, 2.2, 2.3
    func executeStartupSequence() async {
        print("[StartupSequenceManager] 🚀 开始执行启动序列")
        
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
        print("[StartupSequenceManager] 状态已重置")
    }
    
    // MARK: - 私有方法 - 启动序列步骤
    
    /// 加载本地数据
    private func executeLoadLocalData() async {
        print("[StartupSequenceManager] 📂 步骤 1: 加载本地数据")
        currentPhase = .loadingLocalData
        statusMessage = "正在加载本地数据..."
        
        do {
            try await loadLocalData()
            startupState.localDataLoaded = true
            print("[StartupSequenceManager] ✅ 本地数据加载完成")
        } catch {
            let startupError = StartupError(phase: .loadingLocalData, error: error)
            startupState.errors.append(startupError)
            print("[StartupSequenceManager] ⚠️ 本地数据加载失败: \(error.localizedDescription)")
            // 记录错误但继续执行后续步骤（需求 2.3）
        }
    }
    
    /// 处理离线队列
    private func executeProcessOfflineQueue() async {
        print("[StartupSequenceManager] 📤 步骤 2: 处理离线队列")
        currentPhase = .processingOfflineQueue
        statusMessage = "正在处理离线操作..."
        
        do {
            try await processOfflineQueue()
            startupState.offlineQueueProcessed = true
            print("[StartupSequenceManager] ✅ 离线队列处理完成")
        } catch {
            let startupError = StartupError(phase: .processingOfflineQueue, error: error)
            startupState.errors.append(startupError)
            print("[StartupSequenceManager] ⚠️ 离线队列处理失败: \(error.localizedDescription)")
            // 记录错误但继续执行后续步骤（需求 2.3）
        }
    }
    
    /// 执行同步
    private func executePerformSync() async {
        print("[StartupSequenceManager] 🔄 步骤 3: 执行同步")
        currentPhase = .syncing
        statusMessage = "正在同步数据..."
        
        do {
            try await performSync()
            startupState.syncCompleted = true
            print("[StartupSequenceManager] ✅ 同步完成")
        } catch {
            let startupError = StartupError(phase: .syncing, error: error)
            startupState.errors.append(startupError)
            print("[StartupSequenceManager] ⚠️ 同步失败: \(error.localizedDescription)")
            // 记录错误但继续（需求 2.3）
        }
    }
    
    /// 完成启动序列
    private func completeStartupSequence() {
        startupState.completionTime = Date()
        
        // 检查是否有错误
        if !startupState.errors.isEmpty {
            // 有错误但仍然完成（需求 2.3 - 错误容忍）
            let errorMessages = startupState.errors.map { $0.message }.joined(separator: "; ")
            errorMessage = errorMessages
            currentPhase = .failed(startupState.errors.first!)
            print("[StartupSequenceManager] ⚠️ 启动序列完成，但有错误: \(errorMessages)")
        } else {
            currentPhase = .completed
            print("[StartupSequenceManager] ✅ 启动序列完成，无错误")
        }
        
        isCompleted = true
        statusMessage = "启动完成"
        
        // 发送启动完成通知（需求 2.4）
        NotificationCenter.default.post(
            name: .startupSequenceCompleted,
            object: nil,
            userInfo: [
                "success": startupState.errors.isEmpty,
                "errors": startupState.errors.map { $0.message },
                "duration": startupState.completionTime?.timeIntervalSince(startupState.startTime) ?? 0
            ]
        )
        
        let duration = startupState.completionTime?.timeIntervalSince(startupState.startTime) ?? 0
        print("[StartupSequenceManager] 📊 启动序列统计:")
        print("[StartupSequenceManager]   - 耗时: \(String(format: "%.2f", duration)) 秒")
        print("[StartupSequenceManager]   - 加载笔记: \(startupState.loadedNotesCount) 条")
        print("[StartupSequenceManager]   - 加载文件夹: \(startupState.loadedFoldersCount) 个")
        print("[StartupSequenceManager]   - 处理离线操作: \(startupState.processedOfflineOperationsCount) 个")
        print("[StartupSequenceManager]   - 同步笔记: \(startupState.syncedNotesCount) 条")
        print("[StartupSequenceManager]   - 错误数: \(startupState.errors.count)")
    }
    
    // MARK: - 私有方法 - 具体实现
    
    /// 加载本地数据
    ///
    /// 从本地数据库加载笔记和文件夹数据
    private func loadLocalData() async throws {
        print("[StartupSequenceManager] 开始加载本地数据...")
        
        // 加载笔记
        let notes = try localStorage.getAllLocalNotes()
        startupState.loadedNotesCount = notes.count
        print("[StartupSequenceManager] 加载了 \(notes.count) 条笔记")
        
        // 加载文件夹
        let folders = try localStorage.loadFolders()
        startupState.loadedFoldersCount = folders.count
        print("[StartupSequenceManager] 加载了 \(folders.count) 个文件夹")
    }
    
    /// 处理离线队列
    ///
    /// 只在网络可用且 Cookie 有效时处理队列（需求 3.1, 3.2, 3.3）
    private func processOfflineQueue() async throws {
        print("[StartupSequenceManager] 检查离线队列...")
        
        // 获取待处理的操作
        let pendingOperations = offlineQueue.getPendingOperations()
        
        if pendingOperations.isEmpty {
            print("[StartupSequenceManager] 离线队列为空，跳过处理")
            return
        }
        
        print("[StartupSequenceManager] 发现 \(pendingOperations.count) 个待处理操作")
        
        // 检查网络和 Cookie 状态（需求 3.1, 3.2, 3.3）
        guard onlineStateManager.isOnline else {
            print("[StartupSequenceManager] 网络不可用或 Cookie 无效，保留队列中的操作")
            return
        }
        
        // 处理离线队列
        await offlineProcessor.processOperations()
        
        // 更新处理数量
        let remainingOperations = offlineQueue.getPendingOperations()
        startupState.processedOfflineOperationsCount = pendingOperations.count - remainingOperations.count
        
        print("[StartupSequenceManager] 处理了 \(startupState.processedOfflineOperationsCount) 个离线操作")
    }
    
    /// 执行同步
    ///
    /// 只在网络可用且 Cookie 有效时执行同步（需求 4.1, 4.2, 4.3）
    private func performSync() async throws {
        print("[StartupSequenceManager] 检查同步条件...")
        
        // 检查是否已认证
        guard miNoteService.isAuthenticated() else {
            print("[StartupSequenceManager] 用户未登录，跳过同步")
            return
        }
        
        // 检查网络和 Cookie 状态（需求 4.2, 4.3）
        guard onlineStateManager.isOnline else {
            print("[StartupSequenceManager] 网络不可用或 Cookie 无效，跳过同步")
            return
        }
        
        // 执行完整同步（需求 4.1）
        print("[StartupSequenceManager] 开始执行完整同步...")
        let result = try await syncService.performFullSync()
        
        startupState.syncedNotesCount = result.syncedNotes
        print("[StartupSequenceManager] 同步完成，同步了 \(result.syncedNotes) 条笔记")
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    /// 启动序列完成通知
    static let startupSequenceCompleted = Notification.Name("startupSequenceCompleted")
}
