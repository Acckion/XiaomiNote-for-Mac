import Combine
import Foundation

/// 在线状态管理器
///
/// 统一计算和管理应用的在线状态
/// 在线状态 = 网络连接 && 已认证 && Cookie有效
///
/// 作为单一数据源（Single Source of Truth），其他组件应该依赖此管理器获取在线状态
@MainActor
public final class OnlineStateManager: ObservableObject {
    public static let shared = OnlineStateManager()

    /// 是否在线（需要同时满足：网络连接、已认证、Cookie有效）
    @Published public private(set) var isOnline = true

    // MARK: - 依赖服务

    private let networkMonitor = NetworkMonitor.shared
    private let service = MiNoteService.shared
    private let scheduledTaskManager = ScheduledTaskManager.shared

    // MARK: - Combine订阅

    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    private init() {
        setupStateMonitoring()
        // 立即计算一次初始状态
        updateOnlineStatus()
    }

    // MARK: - 状态监控设置

    /// 设置状态监控，监听所有影响在线状态的因素
    private func setupStateMonitoring() {
        // 监听网络连接状态变化
        networkMonitor.$isConnected
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateOnlineStatus()
                }
            }
            .store(in: &cancellables)

        // 监听Cookie有效性变化
        // 使用定时检查的方式，因为 ScheduledTaskManager 的 isCookieValid 是计算属性
        // 我们通过监听任务状态变化来触发更新
        scheduledTaskManager.$taskStatuses
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateOnlineStatus()
                }
            }
            .store(in: &cancellables)

        // 监听认证状态变化（通过监听Cookie设置通知）
        NotificationCenter.default.publisher(for: NSNotification.Name("CookieRefreshedSuccessfully"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateOnlineStatus()
                }
            }
            .store(in: &cancellables)

        // 监听Cookie失效通知（由 MiNoteService 发送）
        NotificationCenter.default.publisher(for: NSNotification.Name("CookieExpired"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateOnlineStatus()
                }
            }
            .store(in: &cancellables)

        // 延迟设置Cookie有效性监听，确保 ScheduledTaskManager 已启动
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒延迟
            if let cookieTask = scheduledTaskManager.cookieValidityCheckTask {
                cookieTask.$isCookieValid
                    .sink { [weak self] _ in
                        Task { @MainActor in
                            self?.updateOnlineStatus()
                        }
                    }
                    .store(in: &cancellables)
            }
        }
    }

    // MARK: - 状态更新

    /// 更新在线状态
    ///
    /// 计算逻辑：isOnline = isConnected && isAuthenticated && isCookieValid
    private func updateOnlineStatus() {
        let isConnected = networkMonitor.isConnected
        let isAuthenticated = service.isAuthenticated()
        let isCookieValid = scheduledTaskManager.isCookieValid

        let wasOnline = isOnline
        isOnline = isConnected && isAuthenticated && isCookieValid

        if wasOnline != isOnline {
            LogService.shared.info(.sync, "在线状态变化: \(isOnline ? "在线" : "离线"), 网络: \(isConnected), 认证: \(isAuthenticated), Cookie: \(isCookieValid)")

            // 发布状态变化通知
            NotificationCenter.default.post(
                name: .onlineStatusDidChange,
                object: nil,
                userInfo: ["isOnline": isOnline]
            )
        }
    }

    /// 手动触发状态更新（供外部调用）
    public func refreshStatus() {
        updateOnlineStatus()
    }
}

// MARK: - 通知扩展

extension Notification.Name {
    /// 在线状态变化通知
    static let onlineStatusDidChange = Notification.Name("onlineStatusDidChange")
}
