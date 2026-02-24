import SwiftUI

/// 认证状态管理
///
/// 替代 NotesViewModel 中的认证管理功能，
/// 负责登录状态、Cookie 管理、私密笔记和网络状态。
@MainActor
public final class AuthState: ObservableObject {
    // MARK: - 认证状态

    @Published var isLoggedIn = false
    @Published var showLoginView = false
    @Published var userProfile: UserProfile?

    // MARK: - 私密笔记

    @Published var isPrivateNotesUnlocked = false
    @Published var showPrivateNotesPasswordDialog = false

    // MARK: - 网络状态

    @Published var isOnline = true
    @Published var isCookieExpired = false
    @Published var showCookieExpiredAlert = false

    // MARK: - 依赖

    private let eventBus: EventBus
    private let apiClient: APIClient
    private let userAPI: UserAPI

    // MARK: - 事件订阅任务

    private var authEventTask: Task<Void, Never>?
    private var cookieCheckTask: Task<Void, Never>?

    /// Cookie 检查间隔（秒）
    private let cookieCheckInterval: UInt64 = 5 * 60

    // MARK: - 自动刷新 Cookie

    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - 初始化

    init(eventBus: EventBus = .shared, apiClient: APIClient, userAPI: UserAPI) {
        self.eventBus = eventBus
        self.apiClient = apiClient
        self.userAPI = userAPI
    }

    // MARK: - 生命周期

    func start() {
        Task {
            isLoggedIn = await apiClient.isAuthenticated()
            isOnline = OnlineStateManager.shared.isOnline

            authEventTask = Task { [weak self] in
                guard let self else { return }
                let stream = await eventBus.subscribe(to: AuthEvent.self)
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    handleAuthEvent(event)
                }
            }

            startCookieValidityCheck()
        }
    }

    func stop() {
        authEventTask?.cancel()
        cookieCheckTask?.cancel()
        autoRefreshTask?.cancel()
        authEventTask = nil
        cookieCheckTask = nil
        autoRefreshTask = nil
    }

    // MARK: - 登录/登出

    func handleLoginSuccess() async {
        isLoggedIn = true
        showLoginView = false
        await fetchUserProfile()
        await eventBus.publish(AuthEvent.loggedIn(userProfile ?? UserProfile(nickname: "", icon: "")))
    }

    func handleLogout() {
        isLoggedIn = false
        userProfile = nil
        isPrivateNotesUnlocked = false
        showLoginView = true
        isCookieExpired = false
        showCookieExpiredAlert = false

        Task {
            await eventBus.publish(AuthEvent.loggedOut)
        }
    }

    // MARK: - 用户信息

    func fetchUserProfile() async {
        guard await apiClient.isAuthenticated() else { return }

        do {
            let response = try await userAPI.fetchUserProfile()
            if let profile = UserProfile.fromAPIResponse(response) {
                userProfile = profile
                LogService.shared.info(.core, "用户信息获取成功")
            }
        } catch {
            LogService.shared.error(.core, "获取用户信息失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Cookie 管理

    func refreshCookie() async {
        do {
            _ = try await PassTokenManager.shared.refreshServiceToken()
            let isValid = try await userAPI.checkCookieValidity()

            if isValid {
                isCookieExpired = false
                showCookieExpiredAlert = false
                isOnline = true
                await eventBus.publish(AuthEvent.cookieRefreshed)
                LogService.shared.info(.core, "Cookie 刷新成功")
            } else {
                isCookieExpired = true
                LogService.shared.warning(.core, "Cookie 刷新后验证失败")
            }
        } catch {
            isCookieExpired = true
            LogService.shared.error(.core, "Cookie 刷新失败: \(error.localizedDescription)")
            await eventBus.publish(AuthEvent.tokenRefreshFailed(errorMessage: error.localizedDescription))
        }
    }

    func handleCookieExpiredRefresh() {
        LogService.shared.info(.core, "用户选择重新登录")
        Task {
            await PassTokenManager.shared.clearCredentials()
            showLoginView = true
        }
    }

    func handleCookieExpiredSilently() async {
        guard await apiClient.isAuthenticated() else { return }

        LogService.shared.info(.core, "静默刷新 Cookie")
        await refreshCookie()
    }

    // MARK: - 自动刷新 Cookie

    func startAutoRefreshCookieIfNeeded() {
        guard isLoggedIn else { return }
        guard autoRefreshTask == nil else { return }

        let defaults = UserDefaults.standard
        let autoRefreshCookie = defaults.bool(forKey: "autoRefreshCookie")
        let autoRefreshInterval = defaults.double(forKey: "autoRefreshInterval")

        guard autoRefreshCookie, autoRefreshInterval > 0 else { return }

        LogService.shared.info(.core, "启动自动刷新 Cookie，间隔: \(autoRefreshInterval) 秒")

        autoRefreshTask = Task { [weak self] in
            let intervalNanos = UInt64(autoRefreshInterval * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                guard !Task.isCancelled else { break }
                await self?.refreshCookie()
            }
        }
    }

    func stopAutoRefreshCookie() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - 私密笔记

    func verifyPrivateNotesPassword(_ password: String) -> Bool {
        let isValid = PrivateNotesPasswordManager.shared.verifyPassword(password)
        if isValid {
            isPrivateNotesUnlocked = true
        }
        return isValid
    }

    func unlockPrivateNotes() {
        isPrivateNotesUnlocked = true
    }

    func handlePrivateNotesPasswordCancel() {
        isPrivateNotesUnlocked = false
        showPrivateNotesPasswordDialog = false
    }

    // MARK: - Cookie 有效性定时检查

    /// 使用 Task + Task.sleep 实现定时检查，替代 ScheduledTaskManager
    private func startCookieValidityCheck() {
        cookieCheckTask = Task { [weak self] in
            guard let self else { return }
            let intervalNanos = cookieCheckInterval * 1_000_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNanos)
                guard !Task.isCancelled else { break }
                await performCookieValidityCheck()
            }
        }
    }

    private func performCookieValidityCheck() async {
        guard await apiClient.isAuthenticated() else { return }

        do {
            let isValid = try await userAPI.checkCookieValidity()
            if !isValid, !isCookieExpired {
                isCookieExpired = true
                LogService.shared.warning(.core, "定时检查发现 Cookie 已失效")
                await eventBus.publish(AuthEvent.cookieExpired)
            } else if isValid, isCookieExpired {
                isCookieExpired = false
                LogService.shared.info(.core, "定时检查发现 Cookie 已恢复有效")
            }
        } catch {
            LogService.shared.error(.core, "Cookie 有效性检查失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 事件处理（内部）

    private func handleAuthEvent(_ event: AuthEvent) {
        switch event {
        case let .loggedIn(profile):
            isLoggedIn = true
            showLoginView = false
            userProfile = profile

        case .loggedOut:
            isLoggedIn = false
            userProfile = nil
            isPrivateNotesUnlocked = false
            isCookieExpired = false
            showCookieExpiredAlert = false

        case .cookieExpired:
            isCookieExpired = true
            // 尝试静默刷新
            Task { await handleCookieExpiredSilently() }

        case .cookieRefreshed:
            isCookieExpired = false
            showCookieExpiredAlert = false
            isOnline = true

        case let .tokenRefreshFailed(errorMessage):
            isCookieExpired = true
            showCookieExpiredAlert = true
            LogService.shared.error(.core, "Token 刷新失败: \(errorMessage)")
        }
    }
}
