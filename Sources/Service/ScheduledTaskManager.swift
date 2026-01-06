import Foundation
import Combine

// MARK: - 任务协议

/// 定时任务协议
/// 
/// 所有定时任务都必须实现此协议
protocol ScheduledTask: AnyObject, Sendable {
    /// 任务唯一标识符
    var id: String { get }
    
    /// 任务名称（用于显示）
    var name: String { get }
    
    /// 执行间隔（秒）
    var interval: TimeInterval { get }
    
    /// 是否需要网络连接
    var requiresNetwork: Bool { get }
    
    /// 是否启用
    var enabled: Bool { get set }
    
    /// 执行任务
    /// - Returns: 任务执行结果
    func execute() async -> TaskResult
}

// MARK: - 任务结果

/// 任务执行结果
struct TaskResult: @unchecked Sendable {
    /// 任务ID
    let taskId: String
    
    /// 是否成功
    let success: Bool
    
    /// 执行时间戳
    let timestamp: Date
    
    /// 返回数据（可选）
    let data: Any?
    
    /// 错误信息（如果失败）
    let error: Error?
    
    init(taskId: String, success: Bool, timestamp: Date = Date(), data: Any? = nil, error: Error? = nil) {
        self.taskId = taskId
        self.success = success
        self.timestamp = timestamp
        self.data = data
        self.error = error
    }
}

// MARK: - 任务状态

/// 任务状态
struct TaskStatus {
    /// 任务ID
    let taskId: String
    
    /// 最后执行时间
    var lastExecutionTime: Date?
    
    /// 最后执行结果
    var lastResult: TaskResult?
    
    /// 是否正在执行
    var isExecuting: Bool = false
    
    /// 连续失败次数
    var consecutiveFailures: Int = 0
    
    /// 下次执行时间
    var nextExecutionTime: Date?
}

// MARK: - 任务管理器

/// 定时任务管理器
/// 
/// 统一管理所有后台定时任务，包括：
/// - Cookie有效性检查
/// - 轻量化同步（未来）
/// - 其他定时任务（未来）
@MainActor
class ScheduledTaskManager: ObservableObject, @unchecked Sendable {
    // MARK: - 单例实例
    
    static let shared = ScheduledTaskManager()
    
    // MARK: - 发布属性
    
    /// 所有任务状态
    @Published private(set) var taskStatuses: [String: TaskStatus] = [:]
    
    // MARK: - 私有属性
    
    /// 已注册的任务
    private var tasks: [String: ScheduledTask] = [:]
    
    /// 任务定时器
    private var timers: [String: Timer] = [:]
    
    /// 网络监控器
    private let networkMonitor = NetworkMonitor.shared
    
    /// 是否已启动
    private var isStarted = false
    
    // MARK: - 初始化
    
    private init() {
        // 注册默认任务
        registerDefaultTasks()
        
        // 监听网络状态变化
        setupNetworkMonitoring()
    }
    
    deinit {
        // 由于 deinit 不是 @MainActor 隔离的，我们不能直接访问 timers
        // 但 Timer 会在对象释放时自动失效，所以我们可以简化 deinit
        // 注意：这里我们只是清空字典，Timer 会自动失效
        // 使用 DispatchQueue.main.async 确保在主线程上执行
        DispatchQueue.main.async { [weak self] in
            self?.timers.removeAll()
        }
    }
    
    // MARK: - 公共方法
    
    /// 启动所有启用的任务
    func start() {
        guard !isStarted else { return }
        
        print("[ScheduledTaskManager] 启动定时任务管理器")
        isStarted = true
        
        for task in tasks.values {
            if task.enabled {
                startTask(task)
            }
        }
    }
    
    /// 停止所有任务
    func stop() {
        guard isStarted else { return }
        
        print("[ScheduledTaskManager] 停止定时任务管理器")
        isStarted = false
        stopAllTasks()
    }
    
    /// 注册新任务
    /// - Parameter task: 要注册的任务
    func registerTask(_ task: ScheduledTask) {
        tasks[task.id] = task
        
        // 初始化任务状态
        taskStatuses[task.id] = TaskStatus(taskId: task.id)
        
        print("[ScheduledTaskManager] 注册任务: \(task.name) (ID: \(task.id))")
        
        // 如果管理器已启动且任务启用，启动任务
        if isStarted && task.enabled {
            startTask(task)
        }
    }
    
    /// 获取任务
    /// - Parameter taskId: 任务ID
    /// - Returns: 任务实例，如果不存在则返回nil
    func getTask(_ taskId: String) -> ScheduledTask? {
        return tasks[taskId]
    }
    
    /// 手动触发任务执行
    /// - Parameter taskId: 任务ID
    /// - Returns: 任务执行结果
    func triggerTask(_ taskId: String) async -> TaskResult? {
        guard let task = tasks[taskId], task.enabled else {
            print("[ScheduledTaskManager] 任务不存在或未启用: \(taskId)")
            return nil
        }
        
        print("[ScheduledTaskManager] 手动触发任务: \(task.name)")
        return await executeTask(task)
    }
    
    /// 更新任务配置
    /// - Parameters:
    ///   - taskId: 任务ID
    ///   - enabled: 是否启用
    ///   - interval: 新的执行间隔（可选）
    func updateTask(_ taskId: String, enabled: Bool, interval: TimeInterval? = nil) {
        guard let task = tasks[taskId] else {
            print("[ScheduledTaskManager] 任务不存在: \(taskId)")
            return
        }
        
        let wasEnabled = task.enabled
        // 注意：我们不能直接修改 task.enabled，因为 task 是 let
        // 我们需要通过其他方式更新任务状态
        // 这里我们使用一个临时的可变副本
        var mutableTask = task
        mutableTask.enabled = enabled
        
        // 更新间隔（如果任务支持）
        if let interval = interval {
            // 注意：这里需要任务支持动态更新间隔
            // 对于简单实现，我们停止并重新启动任务
            print("[ScheduledTaskManager] 更新任务间隔: \(task.name) -> \(interval)秒")
        }
        
        if isStarted {
            if enabled && !wasEnabled {
                // 启用之前禁用的任务
                startTask(task)
            } else if !enabled && wasEnabled {
                // 禁用之前启用的任务
                stopTask(taskId)
            }
        }
        
        print("[ScheduledTaskManager] 更新任务: \(task.name), 启用: \(enabled)")
    }
    
    // MARK: - 私有方法
    
    /// 注册默认任务
    private func registerDefaultTasks() {
        // 注册Cookie有效性检查任务
        let cookieTask = CookieValidityCheckTask()
        registerTask(cookieTask)
        
        // 未来可以在这里注册其他默认任务
        // 例如：轻量化同步任务、健康检查任务等
    }
    
    /// 启动单个任务
    private func startTask(_ task: ScheduledTask) {
        guard task.enabled else { return }
        
        let taskId = task.id
        
        // 停止现有的定时器（如果存在）
        stopTask(taskId)
        
        print("[ScheduledTaskManager] 启动任务: \(task.name), 间隔: \(task.interval)秒")
        
        // 创建定时器
        // 注意：我们需要捕获 task 的弱引用，避免循环引用
        let timer = Timer.scheduledTimer(withTimeInterval: task.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // 重新获取任务，确保我们使用的是最新的任务实例
                if let task = self?.tasks[taskId] {
                    await self?.executeTask(task)
                }
            }
        }
        
        timers[taskId] = timer
        
        // 立即执行一次
        Task { @MainActor in
            await executeTask(task)
        }
    }
    
    /// 停止单个任务
    private func stopTask(_ taskId: String) {
        timers[taskId]?.invalidate()
        timers.removeValue(forKey: taskId)
        
        if let task = tasks[taskId] {
            print("[ScheduledTaskManager] 停止任务: \(task.name)")
        }
    }
    
    /// 停止所有任务
    private func stopAllTasks() {
        for (taskId, _) in timers {
            stopTask(taskId)
        }
        timers.removeAll()
    }
    
    /// 执行任务
    /// - Parameter task: 要执行的任务
    /// - Returns: 任务执行结果
    private func executeTask(_ task: ScheduledTask) async -> TaskResult {
        let taskId = task.id
        
        // 检查网络要求
        if task.requiresNetwork && !networkMonitor.isOnline {
            print("[ScheduledTaskManager] 网络不可用，跳过任务: \(task.name)")
            
            // 更新任务状态
            updateTaskStatus(taskId, isExecuting: false)
            return TaskResult(
                taskId: taskId,
                success: false,
                data: nil,
                error: NSError(domain: "ScheduledTaskManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "网络不可用"
                ])
            )
        }
        
        // 更新任务状态：正在执行
        updateTaskStatus(taskId, isExecuting: true)
        
        print("[ScheduledTaskManager] 开始执行任务: \(task.name)")
        
        // 执行任务
        let result = await task.execute()
        
        // 更新任务状态：执行完成
        updateTaskStatus(taskId, isExecuting: false, result: result)
        
        // 处理执行结果
        if result.success {
            print("[ScheduledTaskManager] 任务执行成功: \(task.name)")
        } else {
            print("[ScheduledTaskManager] 任务执行失败: \(task.name), 错误: \(result.error?.localizedDescription ?? "未知错误")")
        }
        
        return result
    }
    
    /// 更新任务状态
    /// - Parameters:
    ///   - taskId: 任务ID
    ///   - isExecuting: 是否正在执行
    ///   - result: 执行结果（可选）
    private func updateTaskStatus(_ taskId: String, isExecuting: Bool, result: TaskResult? = nil) {
        var status = taskStatuses[taskId] ?? TaskStatus(taskId: taskId)
        status.isExecuting = isExecuting
        
        if let result = result {
            status.lastResult = result
            status.lastExecutionTime = result.timestamp
            
            if result.success {
                status.consecutiveFailures = 0
            } else {
                status.consecutiveFailures += 1
            }
            
            // 计算下次执行时间
            if let task = tasks[taskId] {
                status.nextExecutionTime = Date().addingTimeInterval(task.interval)
            }
        }
        
        taskStatuses[taskId] = status
    }
    
    /// 设置网络监控
    private func setupNetworkMonitoring() {
        networkMonitor.$isOnline
            .sink { [weak self] isOnline in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.handleNetworkChange(isOnline)
                }
            }
            .store(in: &cancellables)
    }
    
    /// 处理网络变化
    /// - Parameter isOnline: 是否在线
    private func handleNetworkChange(_ isOnline: Bool) {
        if isOnline {
            print("[ScheduledTaskManager] 网络恢复，重新启动需要网络的任务")
            // 网络恢复时，重新启动需要网络的任务
            for task in tasks.values {
                if task.enabled && task.requiresNetwork {
                    startTask(task)
                }
            }
        } else {
            print("[ScheduledTaskManager] 网络断开，停止需要网络的任务")
            // 网络断开时，停止需要网络的任务
            for task in tasks.values {
                if task.requiresNetwork {
                    stopTask(task.id)
                }
            }
        }
    }
    
    // MARK: - Combine
    
    private var cancellables = Set<AnyCancellable>()
}

// MARK: - Cookie有效性检查任务

/// Cookie有效性检查任务
final class CookieValidityCheckTask: ScheduledTask, ObservableObject, @unchecked Sendable {
    // MARK: - ScheduledTask 协议实现
    
    let id = "cookie_validity_check"
    let name = "Cookie有效性检查"
    let interval: TimeInterval = 30.0  // 30秒检查一次
    let requiresNetwork = true
    var enabled = true
    
    // MARK: - 任务特定属性
    
    /// Cookie是否有效（供其他模块使用）
    @Published private(set) var isCookieValid: Bool = true
    
    /// 最后检查时间
    @Published private(set) var lastCheckTime: Date?
    
    /// 最后检查结果
    @Published private(set) var lastCheckResult: Bool = true
    
    // MARK: - 任务执行
    
    func execute() async -> TaskResult {
        print("[CookieValidityCheckTask] 开始检查Cookie有效性")
        
        do {
            // 调用 MiNoteService 检查Cookie有效性
            let isValid = try await MiNoteService.shared.checkCookieValidity()
            
            await MainActor.run {
                self.isCookieValid = isValid
                self.lastCheckTime = Date()
                self.lastCheckResult = isValid
            }
            
            print("[CookieValidityCheckTask] Cookie有效性检查结果: \(isValid ? "有效" : "无效")")
            
            return TaskResult(
                taskId: id,
                success: true,
                data: ["isValid": isValid],
                error: nil
            )
        } catch {
            await MainActor.run {
                self.isCookieValid = false
                self.lastCheckTime = Date()
                self.lastCheckResult = false
            }
            
            print("[CookieValidityCheckTask] Cookie有效性检查失败: \(error)")
            
            return TaskResult(
                taskId: id,
                success: false,
                data: nil,
                error: error
            )
        }
    }
}

// MARK: - 工具函数

extension ScheduledTaskManager {
    /// 获取Cookie有效性检查任务
    var cookieValidityCheckTask: CookieValidityCheckTask? {
        return getTask("cookie_validity_check") as? CookieValidityCheckTask
    }
    
    /// 获取当前Cookie是否有效（同步）
    var isCookieValid: Bool {
        return cookieValidityCheckTask?.isCookieValid ?? true
    }
}
