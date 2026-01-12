import AppKit
import MiNoteLibrary
import Combine

/// 应用程序状态管理器
/// 负责应用程序的生命周期状态管理
/// 
/// 遵循需求：
/// - 2.1, 2.2, 2.3, 2.4: 启动序列管理
/// - 5.1, 5.2: 登录/Cookie刷新成功后自动同步
/// - 8.1, 8.6, 8.7: 错误恢复机制
@MainActor
class AppStateManager {
    
    // MARK: - 属性
    
    /// 应用程序启动完成时间戳
    private var launchTime: Date?
    
    /// 窗口管理器
    private let windowManager: WindowManager
    
    /// 菜单管理器
    private let menuManager: MenuManager
    
    /// 网络恢复处理器（需求 8.6）
    private var networkRecoveryHandler: NetworkRecoveryHandler?
    
    /// 错误恢复服务（需求 8.1, 8.7）
    private var errorRecoveryService: ErrorRecoveryService?
    
    /// 在线状态管理器（需求 8.6）
    private var onlineStateManager: OnlineStateManager?
    
    /// Combine 订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    /// 初始化应用程序状态管理器
    /// - Parameters:
    ///   - windowManager: 窗口管理器
    ///   - menuManager: 菜单管理器
    init(windowManager: WindowManager, menuManager: MenuManager) {
        self.windowManager = windowManager
        self.menuManager = menuManager
        print("应用程序状态管理器初始化")
        
        // 设置组件连接
        setupComponentConnections()
    }
    
    // MARK: - 公共方法
    
    /// 处理应用程序启动完成
    func handleApplicationDidFinishLaunching() {
        launchTime = Date()
        print("应用程序启动完成 - \(Date())")
        
        // 初始化错误恢复相关服务（需求 8.1, 8.6, 8.7）
        initializeErrorRecoveryServices()
        
        // 创建主窗口
        windowManager.createMainWindow()
        
        // 激活应用程序
        NSApp.activate(ignoringOtherApps: true)
        
        // 设置应用程序菜单
        menuManager.setupApplicationMenu()
        
        print("应用程序初始化完成，耗时: \(String(format: "%.2f", Date().timeIntervalSince(launchTime!)))秒")
    }
    
    /// 设置组件连接
    /// 
    /// 连接各个组件之间的通信：
    /// - OnlineStateManager 的网络状态变化回调
    /// - 登录成功通知
    /// - Cookie 刷新成功通知
    /// 
    /// _Requirements: 2.1, 5.1, 5.2, 8.6_
    private func setupComponentConnections() {
        print("[AppStateManager] 设置组件连接...")
        
        // 获取 OnlineStateManager 单例
        onlineStateManager = OnlineStateManager.shared
        
        // 监听在线状态变化（需求 8.6）
        onlineStateManager?.$isOnline
            .removeDuplicates()
            .sink { [weak self] isOnline in
                self?.handleOnlineStatusChange(isOnline: isOnline)
            }
            .store(in: &cancellables)
        
        // 监听启动序列完成通知（需求 2.4）
        NotificationCenter.default.publisher(for: .startupSequenceCompleted)
            .sink { [weak self] notification in
                self?.handleStartupSequenceCompleted(notification)
            }
            .store(in: &cancellables)
        
        // 监听网络恢复处理完成通知（需求 8.6）
        NotificationCenter.default.publisher(for: .networkRecoveryProcessingCompleted)
            .sink { [weak self] notification in
                self?.handleNetworkRecoveryProcessingCompleted(notification)
            }
            .store(in: &cancellables)
        
        print("[AppStateManager] ✅ 组件连接设置完成")
    }
    
    /// 处理在线状态变化
    /// 
    /// _Requirements: 8.6_
    private func handleOnlineStatusChange(isOnline: Bool) {
        print("[AppStateManager] 在线状态变化: \(isOnline ? "在线" : "离线")")
        
        // 在线状态变化时，NetworkRecoveryHandler 会自动处理离线队列
        // 这里可以添加额外的应用级别处理逻辑
    }
    
    /// 处理启动序列完成通知
    /// 
    /// _Requirements: 2.4_
    private func handleStartupSequenceCompleted(_ notification: Notification) {
        let success = notification.userInfo?["success"] as? Bool ?? false
        let duration = notification.userInfo?["duration"] as? TimeInterval ?? 0
        
        print("[AppStateManager] 📊 启动序列完成:")
        print("[AppStateManager]   - 成功: \(success)")
        print("[AppStateManager]   - 耗时: \(String(format: "%.2f", duration)) 秒")
    }
    
    /// 处理网络恢复处理完成通知
    /// 
    /// _Requirements: 8.6_
    private func handleNetworkRecoveryProcessingCompleted(_ notification: Notification) {
        let successCount = notification.userInfo?["successCount"] as? Int ?? 0
        let failedCount = notification.userInfo?["failedCount"] as? Int ?? 0
        
        print("[AppStateManager] 📊 网络恢复处理完成:")
        print("[AppStateManager]   - 成功: \(successCount)")
        print("[AppStateManager]   - 失败: \(failedCount)")
    }
    
    /// 初始化错误恢复相关服务
    /// 
    /// 遵循需求 8.1, 8.6, 8.7
    private func initializeErrorRecoveryServices() {
        print("[AppStateManager] 初始化错误恢复服务...")
        
        // 初始化错误恢复服务（需求 8.1, 8.7）
        errorRecoveryService = ErrorRecoveryService.shared
        print("[AppStateManager] ✅ ErrorRecoveryService 已初始化")
        
        // 初始化网络恢复处理器（需求 8.6）
        networkRecoveryHandler = NetworkRecoveryHandler.shared
        print("[AppStateManager] ✅ NetworkRecoveryHandler 已初始化")
    }
    
    /// 处理应用程序即将终止
    func handleApplicationWillTerminate() {
        print("应用程序即将终止")
        
        // 保存应用程序状态
        windowManager.saveApplicationState()
    }
    
    /// 处理应用程序重新打开
    /// - Parameters:
    ///   - hasVisibleWindows: 是否有可见窗口
    /// - Returns: 是否处理成功
    func handleApplicationReopen(hasVisibleWindows: Bool) -> Bool {
        return windowManager.handleApplicationReopen(hasVisibleWindows: hasVisibleWindows)
    }
    
    /// 判断当最后一个窗口关闭时是否终止应用程序
    /// - Returns: 是否终止应用程序
    func shouldTerminateAfterLastWindowClosed() -> Bool {
        // 当最后一个窗口关闭时不终止应用程序，符合 macOS 标准行为
        // 用户可以通过菜单或 Dock 退出应用
        return false
    }
    
    // MARK: - 清理
    
    deinit {
        print("应用程序状态管理器释放")
    }
}
