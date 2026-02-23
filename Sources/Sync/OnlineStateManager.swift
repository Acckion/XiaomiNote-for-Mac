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
    private let apiClient = APIClient.shared

    // MARK: - 内部状态

    /// Cookie 有效性状态，通过 AuthEvent 更新
    private var isCookieValid = true

    // MARK: - Combine订阅

    private var cancellables = Set<AnyCancellable>()

    // MARK: - EventBus 订阅

    private var authEventTask: Task<Void, Never>?

    // MARK: - 初始化

    private init() {
        setupStateMonitoring()
        setupAuthEventSubscription()
        updateOnlineStatus()
    }

    deinit {
        authEventTask?.cancel()
    }

    // MARK: - 状态监控设置

    /// 设置网络状态监控
    private func setupStateMonitoring() {
        networkMonitor.$isConnected
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateOnlineStatus()
                }
            }
            .store(in: &cancellables)
    }

    /// 设置 AuthEvent 订阅，监听 Cookie 状态变化
    private func setupAuthEventSubscription() {
        authEventTask = Task { [weak self] in
            let stream = await EventBus.shared.subscribe(to: AuthEvent.self)
            for await event in stream {
                guard let self else { break }
                switch event {
                case .cookieRefreshed:
                    isCookieValid = true
                    updateOnlineStatus()
                case .cookieExpired:
                    isCookieValid = false
                    updateOnlineStatus()
                default:
                    break
                }
            }
        }
    }

    // MARK: - 状态更新

    /// 更新在线状态
    ///
    /// 计算逻辑：isOnline = isConnected && isAuthenticated && isCookieValid
    private func updateOnlineStatus() {
        let isConnected = networkMonitor.isConnected
        let isAuthenticated = apiClient.isAuthenticated()
        let cookieValid = isCookieValid

        let wasOnline = isOnline
        isOnline = isConnected && isAuthenticated && cookieValid

        if wasOnline != isOnline {
            LogService.shared.info(.sync, "在线状态变化: \(isOnline ? "在线" : "离线"), 网络: \(isConnected), 认证: \(isAuthenticated), Cookie: \(cookieValid)")

            Task {
                await EventBus.shared.publish(OnlineEvent.onlineStatusChanged(isOnline: isOnline))
            }
        }
    }

    /// 手动触发状态更新（供外部调用）
    public func refreshStatus() {
        updateOnlineStatus()
    }
}
