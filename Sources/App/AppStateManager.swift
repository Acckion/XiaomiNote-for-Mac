import AppKit
import Combine
import MiNoteLibrary

/// 应用程序状态管理器
@MainActor
class AppStateManager {

    // MARK: - 属性

    /// 应用程序启动完成时间戳
    private var launchTime: Date?

    /// 窗口管理器
    private let windowManager: WindowManager

    /// 菜单管理器
    private let menuManager: MenuManager

    /// 网络恢复处理器
    private var networkRecoveryHandler: NetworkRecoveryHandler?

    /// 错误恢复服务
    private var errorRecoveryService: ErrorRecoveryService?

    /// 在线状态管理器
    private var onlineStateManager: OnlineStateManager?

    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()

    /// 启动事件订阅 Task
    private var startupEventTask: Task<Void, Never>?

    // MARK: - 初始化

    /// 初始化应用程序状态管理器
    /// - Parameters:
    ///   - windowManager: 窗口管理器
    ///   - menuManager: 菜单管理器
    init(windowManager: WindowManager, menuManager: MenuManager) {
        self.windowManager = windowManager
        self.menuManager = menuManager

        // 设置组件连接
        setupComponentConnections()
    }

    // MARK: - 公共方法

    /// 处理应用程序启动完成
    func handleApplicationDidFinishLaunching() {
        launchTime = Date()

        // 初始化错误恢复相关服务
        initializeErrorRecoveryServices()

        // 启动后台服务（在创建主窗口之前）
        startBackgroundServices()

        // 创建主窗口
        windowManager.createMainWindow()

        // 激活应用程序
        NSApp.activate(ignoringOtherApps: true)

        // 设置应用程序菜单
        menuManager.setupApplicationMenu()

        LogService.shared.info(.app, "应用程序初始化完成，耗时: \(String(format: "%.2f", Date().timeIntervalSince(launchTime!)))秒")
    }

    /// 设置组件连接
    ///
    /// 连接各个组件之间的通信：
    /// - OnlineStateManager 的网络状态变化回调
    /// - 登录成功通知
    /// - Cookie 刷新成功通知
    private func setupComponentConnections() {
        // 获取 OnlineStateManager 单例
        onlineStateManager = OnlineStateManager.shared

        // 监听在线状态变化
        onlineStateManager?.$isOnline
            .removeDuplicates()
            .sink { [weak self] isOnline in
                self?.handleOnlineStatusChange(isOnline: isOnline)
            }
            .store(in: &cancellables)

        // 监听启动序列完成事件
        startupEventTask = Task { [weak self] in
            let stream = await EventBus.shared.subscribe(to: StartupEvent.self)
            for await event in stream {
                guard let self else { break }
                switch event {
                case let .startupCompleted(success, _, duration):
                    LogService.shared.info(.app, "启动序列完成: 成功=\(success), 耗时=\(String(format: "%.2f", duration))秒")
                }
            }
        }

        // 监听网络恢复处理完成通知
        NotificationCenter.default.publisher(for: .networkRecoveryProcessingCompleted)
            .sink { [weak self] notification in
                self?.handleNetworkRecoveryProcessingCompleted(notification)
            }
            .store(in: &cancellables)

    }

    private func handleOnlineStatusChange(isOnline: Bool) {
        LogService.shared.info(.app, "在线状态变化: \(isOnline ? "在线" : "离线")")
    }

    /// 处理网络恢复处理完成通知
    private func handleNetworkRecoveryProcessingCompleted(_ notification: Notification) {
        let successCount = notification.userInfo?["successCount"] as? Int ?? 0
        let failedCount = notification.userInfo?["failedCount"] as? Int ?? 0
        LogService.shared.info(.app, "网络恢复处理完成: 成功=\(successCount), 失败=\(failedCount)")
    }

    /// 初始化错误恢复相关服务
    private func initializeErrorRecoveryServices() {
        errorRecoveryService = ErrorRecoveryService.shared
        networkRecoveryHandler = NetworkRecoveryHandler.shared
    }

    /// 启动后台服务
    private func startBackgroundServices() {
        onlineStateManager?.refreshStatus()
    }

    /// 处理应用程序即将终止
    func handleApplicationWillTerminate() {
        LogService.shared.info(.app, "应用程序即将终止")

        // 保存应用程序状态
        windowManager.saveApplicationState()
    }

    /// 处理应用程序重新打开
    /// - Parameters:
    ///   - hasVisibleWindows: 是否有可见窗口
    /// - Returns: 是否处理成功
    func handleApplicationReopen(hasVisibleWindows: Bool) -> Bool {
        windowManager.handleApplicationReopen(hasVisibleWindows: hasVisibleWindows)
    }

    func resetApplication() async throws {
        // TODO: 实现应用重置逻辑
    }

    /// 判断当最后一个窗口关闭时是否终止应用程序
    func shouldTerminateAfterLastWindowClosed() -> Bool {
        false
    }

    // MARK: - 清理

    deinit {
        startupEventTask?.cancel()
    }
}
