import Combine
import Foundation

// MARK: - 任务协议

/// 定时任务协议
protocol ScheduledTask: AnyObject, Sendable {
    var id: String { get }
    var name: String { get }
    var interval: TimeInterval { get }
    var requiresNetwork: Bool { get }
    var enabled: Bool { get set }
    func execute() async -> TaskResult
}

// MARK: - 任务结果

struct TaskResult: @unchecked Sendable {
    let taskId: String
    let success: Bool
    let timestamp: Date
    let data: Any?
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

struct TaskStatus {
    let taskId: String
    var lastExecutionTime: Date?
    var lastResult: TaskResult?
    var isExecuting = false
    var consecutiveFailures = 0
    var nextExecutionTime: Date?
}

// MARK: - 任务管理器

@MainActor
public class ScheduledTaskManager: ObservableObject, @unchecked Sendable {
    public static let shared = ScheduledTaskManager()

    @Published private(set) var taskStatuses: [String: TaskStatus] = [:]

    private var tasks: [String: ScheduledTask] = [:]
    private var timers: [String: Timer] = [:]
    private var pausedTasks: Set<String> = []
    private var taskResumeTime: [String: Date] = [:]
    private let networkMonitor = NetworkMonitor.shared
    private var isStarted = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        registerDefaultTasks()
        setupNetworkMonitoring()
    }

    // MARK: - 公共方法

    public func start() {
        guard !isStarted else { return }

        LogService.shared.info(.core, "启动定时任务管理器")
        isStarted = true

        for task in tasks.values where task.enabled {
            startTask(task)
        }
    }

    func stop() {
        guard isStarted else { return }

        LogService.shared.info(.core, "停止定时任务管理器")
        isStarted = false
        stopAllTasks()
    }

    func registerTask(_ task: ScheduledTask) {
        tasks[task.id] = task
        taskStatuses[task.id] = TaskStatus(taskId: task.id)
        LogService.shared.debug(.core, "注册任务: \(task.name) (ID: \(task.id))")

        if isStarted, task.enabled {
            startTask(task)
        }
    }

    func getTask(_ taskId: String) -> ScheduledTask? {
        tasks[taskId]
    }

    func triggerTask(_ taskId: String) async -> TaskResult? {
        guard let task = tasks[taskId], task.enabled else {
            LogService.shared.debug(.core, "任务不存在或未启用: \(taskId)")
            return nil
        }
        return await executeTask(task)
    }

    func updateTask(_ taskId: String, enabled: Bool, interval: TimeInterval? = nil) {
        guard let task = tasks[taskId] else {
            LogService.shared.debug(.core, "任务不存在: \(taskId)")
            return
        }

        let wasEnabled = task.enabled
        var mutableTask = task
        mutableTask.enabled = enabled

        if let interval {
            LogService.shared.debug(.core, "更新任务间隔: \(task.name) -> \(interval)秒")
        }

        if isStarted {
            if enabled, !wasEnabled {
                startTask(task)
            } else if !enabled, wasEnabled {
                stopTask(taskId)
            }
        }
    }

    // MARK: - 任务暂停/恢复

    func pauseTask(_ taskId: String) {
        guard let task = tasks[taskId] else { return }

        pausedTasks.insert(taskId)
        stopTask(taskId)
        LogService.shared.debug(.core, "暂停任务: \(task.name)")
    }

    func resumeTask(_ taskId: String, gracePeriod: TimeInterval = 0) {
        guard pausedTasks.contains(taskId) else { return }

        pausedTasks.remove(taskId)

        if gracePeriod > 0 {
            taskResumeTime[taskId] = Date().addingTimeInterval(gracePeriod)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(gracePeriod * 1_000_000_000))

                if !self.pausedTasks.contains(taskId) {
                    if let task = self.tasks[taskId], task.enabled {
                        self.startTask(task)
                        LogService.shared.debug(.core, "任务已恢复: \(task.name)")
                    }
                }
                self.taskResumeTime.removeValue(forKey: taskId)
            }
        } else {
            if let task = tasks[taskId], task.enabled {
                startTask(task)
                LogService.shared.debug(.core, "任务已恢复: \(task.name)")
            }
        }
    }

    func isTaskPaused(_ taskId: String) -> Bool {
        pausedTasks.contains(taskId)
    }

    // MARK: - 私有方法

    private func registerDefaultTasks() {
        registerTask(CookieValidityCheckTask())
    }

    private func startTask(_ task: ScheduledTask) {
        guard task.enabled else { return }

        let taskId = task.id
        stopTask(taskId)

        let timer = Timer.scheduledTimer(withTimeInterval: task.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if let task = self?.tasks[taskId] {
                    await self?.executeTask(task)
                }
            }
        }

        timers[taskId] = timer

        Task { @MainActor in
            await executeTask(task)
        }
    }

    private func stopTask(_ taskId: String) {
        timers[taskId]?.invalidate()
        timers.removeValue(forKey: taskId)
    }

    private func stopAllTasks() {
        for taskId in timers.keys {
            stopTask(taskId)
        }
        timers.removeAll()
    }

    @discardableResult
    private func executeTask(_ task: ScheduledTask) async -> TaskResult {
        let taskId = task.id

        if task.requiresNetwork, !networkMonitor.isConnected {
            updateTaskStatus(taskId, isExecuting: false)
            return TaskResult(
                taskId: taskId,
                success: false,
                data: nil,
                error: NSError(domain: "ScheduledTaskManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "网络不可用",
                ])
            )
        }

        updateTaskStatus(taskId, isExecuting: true)
        let result = await task.execute()
        updateTaskStatus(taskId, isExecuting: false, result: result)

        if !result.success {
            LogService.shared.debug(.core, "任务执行失败: \(task.name), 错误: \(result.error?.localizedDescription ?? "未知错误")")
        }

        return result
    }

    private func updateTaskStatus(_ taskId: String, isExecuting: Bool, result: TaskResult? = nil) {
        var status = taskStatuses[taskId] ?? TaskStatus(taskId: taskId)
        status.isExecuting = isExecuting

        if let result {
            status.lastResult = result
            status.lastExecutionTime = result.timestamp

            if result.success {
                status.consecutiveFailures = 0
            } else {
                status.consecutiveFailures += 1
            }

            if let task = tasks[taskId] {
                status.nextExecutionTime = Date().addingTimeInterval(task.interval)
            }
        }

        taskStatuses[taskId] = status
    }

    private func setupNetworkMonitoring() {
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                Task { @MainActor in
                    guard let self else { return }
                    self.handleNetworkChange(isConnected)
                }
            }
            .store(in: &cancellables)
    }

    private func handleNetworkChange(_ isConnected: Bool) {
        if isConnected {
            for task in tasks.values where task.enabled && task.requiresNetwork {
                startTask(task)
            }
        } else {
            for task in tasks.values where task.requiresNetwork {
                stopTask(task.id)
            }
        }
    }
}

// MARK: - Cookie 有效性检查任务

final class CookieValidityCheckTask: ScheduledTask, ObservableObject, @unchecked Sendable {
    let id = "cookie_validity_check"
    let name = "Cookie有效性检查"
    let interval: TimeInterval = 30.0
    let requiresNetwork = true
    var enabled = true

    @Published private(set) var isCookieValid = true
    @Published private(set) var lastCheckTime: Date?
    @Published private(set) var lastCheckResult = true

    /// 跳过检查的条件：未存储 passToken 或任务已暂停
    private func shouldSkipCheck() async -> Bool {
        let hasPassToken = await PassTokenManager.shared.hasStoredPassToken()
        if !hasPassToken { return true }

        return await MainActor.run {
            ScheduledTaskManager.shared.isTaskPaused(self.id)
        }
    }

    func setCookieValid(_ isValid: Bool) {
        isCookieValid = isValid
        lastCheckTime = Date()
        lastCheckResult = isValid
    }

    func execute() async -> TaskResult {
        if await shouldSkipCheck() {
            return TaskResult(
                taskId: id,
                success: true,
                data: ["skipped": true, "reason": "refresh_in_progress"],
                error: nil
            )
        }

        do {
            let isValid = try await MiNoteService.shared.checkCookieValidity()

            await MainActor.run {
                self.isCookieValid = isValid
                self.lastCheckTime = Date()
                self.lastCheckResult = isValid
            }

            if !isValid {
                await triggerSilentRefresh()
            }

            return TaskResult(
                taskId: id,
                success: true,
                data: ["isValid": isValid, "skipped": false],
                error: nil
            )
        } catch {
            await MainActor.run {
                self.isCookieValid = false
                self.lastCheckTime = Date()
                self.lastCheckResult = false
            }

            LogService.shared.debug(.core, "Cookie 有效性检查失败: \(error.localizedDescription)")
            await triggerSilentRefresh()

            return TaskResult(
                taskId: id,
                success: false,
                data: ["skipped": false],
                error: error
            )
        }
    }

    private func triggerSilentRefresh() async {
        do {
            try await PassTokenManager.shared.refreshServiceToken()

            await MainActor.run {
                self.isCookieValid = true
                self.lastCheckResult = true
                ScheduledTaskManager.shared.setCookieValid(true)
            }
        } catch {
            LogService.shared.error(.core, "PassToken 刷新失败: \(error.localizedDescription)")

            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("CookieRefreshFailed"),
                    object: nil,
                    userInfo: ["reason": error.localizedDescription]
                )
            }
        }
    }
}

// MARK: - 工具扩展

extension ScheduledTaskManager {
    var cookieValidityCheckTask: CookieValidityCheckTask? {
        getTask("cookie_validity_check") as? CookieValidityCheckTask
    }

    var isCookieValid: Bool {
        cookieValidityCheckTask?.isCookieValid ?? true
    }

    func setCookieValid(_ isValid: Bool) {
        cookieValidityCheckTask?.setCookieValid(isValid)
    }
}
