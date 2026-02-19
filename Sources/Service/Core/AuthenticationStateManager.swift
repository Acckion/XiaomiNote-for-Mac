import AppKit
import Combine
import Foundation

/// 认证状态管理器
///
/// 统一管理登录、Token刷新和认证相关的UI状态
/// 在线状态由 OnlineStateManager 统一管理，这里只负责同步和UI状态
@MainActor
class AuthenticationStateManager: ObservableObject {
    // MARK: - 状态属性

    @Published var isOnline = true
    @Published var isCookieExpired = false
    @Published var cookieExpiredShown = false
    @Published var showCookieExpiredAlert = false
    @Published var shouldStayOffline = false
    @Published var showLoginView = false
    @Published var isRefreshingCookie = false
    @Published var refreshStatusMessage = ""

    // MARK: - 失败计数和防重入机制

    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 3
    private var isInRefreshCycle = false

    // MARK: - 依赖服务

    private let service = MiNoteService.shared
    private let onlineStateManager = OnlineStateManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - 初始化

    init() {
        setupOnlineStateSync()
        setupCookieExpiredHandler()
        setupCookieRefreshNotification()
    }

    // MARK: - 在线状态同步

    private func setupOnlineStateSync() {
        onlineStateManager.$isOnline
            .sink { [weak self] onlineStatus in
                Task { @MainActor in
                    self?.updateOnlineStatusFromManager(onlineStatus)
                }
            }
            .store(in: &cancellables)

        if let cookieTask = ScheduledTaskManager.shared.cookieValidityCheckTask {
            cookieTask.$isCookieValid
                .sink { [weak self] isValid in
                    Task { @MainActor in
                        self?.updateCookieExpiredStatus(isValid: isValid)
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func updateOnlineStatusFromManager(_ onlineStatus: Bool) {
        if shouldStayOffline {
            if isOnline { isOnline = false }
            return
        }
        if cookieExpiredShown {
            if isOnline { isOnline = false }
            return
        }
        isOnline = onlineStatus
    }

    private func updateCookieExpiredStatus(isValid: Bool) {
        if shouldStayOffline || cookieExpiredShown { return }

        if !isValid {
            isCookieExpired = true
            LogService.shared.debug(.core, "Cookie 失效，标记为失效状态")
        } else if isCookieExpired {
            isCookieExpired = false
            LogService.shared.debug(.core, "Cookie 恢复有效，清除失效状态")
        }
    }

    // MARK: - Cookie过期处理

    private func setupCookieExpiredHandler() {
        service.onCookieExpired = { [weak self] in
            Task { @MainActor in
                self?.handleCookieExpired()
            }
        }
    }

    func handleCookieExpired() {
        let silentRefreshEnabled: Bool = if UserDefaults.standard.object(forKey: "silentRefreshOnFailure") != nil {
            UserDefaults.standard.bool(forKey: "silentRefreshOnFailure")
        } else {
            true
        }

        isOnline = false
        isCookieExpired = true

        if !shouldStayOffline, !cookieExpiredShown {
            cookieExpiredShown = true
            if silentRefreshEnabled {
                Task { await attemptSilentRefresh() }
            } else {
                showCookieExpiredAlert = true
            }
        } else if shouldStayOffline {
            cookieExpiredShown = true
        }
    }

    private func attemptSilentRefresh() async {
        guard !isInRefreshCycle else {
            LogService.shared.debug(.core, "已在刷新周期中，跳过重复请求")
            return
        }
        guard consecutiveFailures < maxConsecutiveFailures else {
            LogService.shared.warning(.core, "已达到最大失败次数 (\(maxConsecutiveFailures))，不再自动刷新")
            showCookieExpiredAlert = true
            return
        }

        isInRefreshCycle = true
        defer { isInRefreshCycle = false }

        LogService.shared.info(.core, "开始静默刷新流程")
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")

        do {
            _ = try await PassTokenManager.shared.refreshServiceToken()
            let isValid = try await MiNoteService.shared.checkCookieValidity()

            if isValid {
                consecutiveFailures = 0
                restoreOnlineStatusAfterValidation(isValid: true)
                LogService.shared.info(.core, "静默刷新成功")
            } else {
                handleRefreshSuccessButValidationFailed()
            }
        } catch let passTokenError as PassTokenError {
            switch passTokenError {
            case .noPassToken, .noUserId:
                LogService.shared.warning(.core, "passToken 不存在，提示重新登录")
                await handlePassTokenInvalid()
            default:
                LogService.shared.error(.core, "静默刷新失败: \(passTokenError)")
                handleRefreshFailure()
            }
        } catch {
            LogService.shared.error(.core, "静默刷新失败: \(error)")
            handleRefreshFailure()
        }

        ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
    }

    func handleCookieExpiredSilently() async {
        await attemptSilentRefresh()
    }

    func attemptSilentRefreshWithStatus() async -> Bool {
        guard !isInRefreshCycle else {
            LogService.shared.debug(.core, "已在刷新周期中，跳过重复请求")
            return false
        }
        guard consecutiveFailures < maxConsecutiveFailures else {
            LogService.shared.warning(.core, "已达到最大失败次数 (\(maxConsecutiveFailures))，不再自动刷新")
            showCookieExpiredAlert = true
            return false
        }

        isInRefreshCycle = true
        isRefreshingCookie = true
        refreshStatusMessage = "正在刷新登录状态..."

        LogService.shared.info(.core, "开始静默刷新流程（带状态更新）")
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")

        defer {
            isInRefreshCycle = false
            isRefreshingCookie = false
            refreshStatusMessage = ""
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }

        do {
            refreshStatusMessage = "正在连接服务器..."
            _ = try await PassTokenManager.shared.refreshServiceToken()

            refreshStatusMessage = "正在验证Cookie有效性..."
            let isValid = try await MiNoteService.shared.checkCookieValidity()

            if isValid {
                consecutiveFailures = 0
                refreshStatusMessage = "登录状态已恢复"
                restoreOnlineStatusAfterValidation(isValid: true)
                LogService.shared.info(.core, "静默刷新成功")
                return true
            } else {
                refreshStatusMessage = "验证失败，请重新登录"
                handleRefreshSuccessButValidationFailed()
                return false
            }
        } catch let passTokenError as PassTokenError {
            switch passTokenError {
            case .noPassToken, .noUserId:
                LogService.shared.warning(.core, "passToken 不存在，提示重新登录")
                refreshStatusMessage = "需要重新登录"
                await handlePassTokenInvalid()
            default:
                LogService.shared.error(.core, "静默刷新失败: \(passTokenError)")
                refreshStatusMessage = "刷新失败: \(passTokenError.localizedDescription)"
                handleRefreshFailure()
            }
            return false
        } catch {
            LogService.shared.error(.core, "静默刷新失败: \(error)")
            refreshStatusMessage = "刷新失败: \(error.localizedDescription)"
            handleRefreshFailure()
            return false
        }
    }

    // MARK: - 刷新失败处理

    private func handleRefreshSuccessButValidationFailed() {
        consecutiveFailures += 1
        LogService.shared.warning(.core, "刷新成功但验证失败，失败次数: \(consecutiveFailures)/\(maxConsecutiveFailures)")
        if consecutiveFailures >= maxConsecutiveFailures {
            showCookieExpiredAlert = true
        }
    }

    private func handleRefreshFailure() {
        consecutiveFailures += 1
        LogService.shared.warning(.core, "刷新失败，失败次数: \(consecutiveFailures)/\(maxConsecutiveFailures)")
        if consecutiveFailures >= maxConsecutiveFailures {
            showCookieExpiredAlert = true
            isCookieExpired = true
            isOnline = false
        }
    }

    private func handlePassTokenInvalid() async {
        LogService.shared.warning(.core, "passToken 失效，清除凭据并提示重新登录")
        await PassTokenManager.shared.clearCredentials()
        isCookieExpired = true
        isOnline = false
        showLoginView = true
    }

    private func restoreOnlineStatusAfterValidation(isValid: Bool) {
        guard isValid else {
            LogService.shared.debug(.core, "Cookie 无效，不恢复在线状态")
            return
        }

        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false
        showCookieExpiredAlert = false
        isOnline = true
        onlineStateManager.refreshStatus()
        LogService.shared.info(.core, "Cookie 验证通过，已恢复在线状态")
    }

    // MARK: - 公共方法

    func restoreOnlineStatus() {
        let hasValidCookie = ScheduledTaskManager.shared.isCookieValid
        guard hasValidCookie else {
            LogService.shared.debug(.core, "Cookie 仍然无效，不能恢复在线状态")
            return
        }

        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false
        showCookieExpiredAlert = false
        onlineStateManager.refreshStatus()
        LogService.shared.info(.core, "已恢复在线状态")
    }

    func handleCookieExpiredRefresh() {
        LogService.shared.info(.core, "用户选择重新登录")
        shouldStayOffline = false
        Task {
            await PassTokenManager.shared.clearCredentials()
            showLoginView = true
        }
    }

    func handleReactiveRefresh() async -> Bool {
        LogService.shared.info(.core, "响应式刷新：检测到 401 错误，立即刷新")

        guard !isInRefreshCycle else {
            LogService.shared.debug(.core, "已在刷新周期中，跳过响应式刷新")
            return false
        }

        isInRefreshCycle = true
        isRefreshingCookie = true
        refreshStatusMessage = "检测到登录失效，正在刷新..."

        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")

        defer {
            isInRefreshCycle = false
            isRefreshingCookie = false
            refreshStatusMessage = ""
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }

        do {
            _ = try await PassTokenManager.shared.refreshServiceToken()

            refreshStatusMessage = "正在验证 Cookie 有效性..."
            let isValid = try await MiNoteService.shared.checkCookieValidity()

            if isValid {
                consecutiveFailures = 0
                refreshStatusMessage = "登录状态已恢复"
                restoreOnlineStatusAfterValidation(isValid: true)
                LogService.shared.info(.core, "响应式刷新成功")
                return true
            } else {
                refreshStatusMessage = "验证失败"
                handleRefreshSuccessButValidationFailed()
                return false
            }
        } catch let passTokenError as PassTokenError {
            switch passTokenError {
            case .noPassToken, .noUserId:
                LogService.shared.warning(.core, "passToken 不存在，提示重新登录")
                refreshStatusMessage = "需要重新登录"
                await handlePassTokenInvalid()
            default:
                LogService.shared.error(.core, "响应式刷新失败: \(passTokenError)")
                refreshStatusMessage = "刷新失败: \(passTokenError.localizedDescription)"
                handleRefreshFailure()
            }
            return false
        } catch {
            LogService.shared.error(.core, "响应式刷新失败: \(error)")
            refreshStatusMessage = "刷新失败: \(error.localizedDescription)"
            handleRefreshFailure()
            return false
        }
    }

    @discardableResult
    func handleManualRefresh() async -> Bool {
        LogService.shared.info(.core, "手动刷新：重置失败计数器")

        guard !isInRefreshCycle else {
            LogService.shared.debug(.core, "已在刷新周期中，跳过手动刷新")
            return false
        }

        isInRefreshCycle = true
        consecutiveFailures = 0
        cookieExpiredShown = false
        isRefreshingCookie = true
        refreshStatusMessage = "正在手动刷新登录状态..."

        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")

        defer {
            isInRefreshCycle = false
            isRefreshingCookie = false
            refreshStatusMessage = ""
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }

        do {
            _ = try await PassTokenManager.shared.refreshServiceToken()

            refreshStatusMessage = "正在验证 Cookie 有效性..."
            let isValid = try await MiNoteService.shared.checkCookieValidity()

            if isValid {
                consecutiveFailures = 0
                refreshStatusMessage = "登录状态已恢复"
                restoreOnlineStatusAfterValidation(isValid: true)
                LogService.shared.info(.core, "手动刷新成功")
                return true
            } else {
                refreshStatusMessage = "验证失败"
                handleRefreshSuccessButValidationFailed()
                return false
            }
        } catch let passTokenError as PassTokenError {
            switch passTokenError {
            case .noPassToken, .noUserId:
                LogService.shared.warning(.core, "passToken 不存在，提示重新登录")
                refreshStatusMessage = "需要重新登录"
                await handlePassTokenInvalid()
            default:
                LogService.shared.error(.core, "手动刷新失败: \(passTokenError)")
                refreshStatusMessage = "刷新失败: \(passTokenError.localizedDescription)"
                handleRefreshFailure()
            }
            return false
        } catch {
            LogService.shared.error(.core, "手动刷新失败: \(error)")
            refreshStatusMessage = "刷新失败: \(error.localizedDescription)"
            handleRefreshFailure()
            return false
        }
    }

    func handleCookieExpiredCancel() {
        LogService.shared.info(.core, "用户选择保持离线模式")
        shouldStayOffline = true
        isOnline = false
        isCookieExpired = true
    }

    func handleCookieRefreshed() {
        LogService.shared.info(.core, "Cookie 刷新完成")
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false
        showCookieExpiredAlert = false
        consecutiveFailures = 0
        ScheduledTaskManager.shared.setCookieValid(true)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self.restoreOnlineStatus()
        }
    }

    func showLogin() {
        showLoginView = true
    }

    func dismissLogin() {
        showLoginView = false
    }

    // MARK: - Cookie刷新通知处理

    private func setupCookieRefreshNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCookieRefreshedNotification(_:)),
            name: NSNotification.Name("CookieRefreshedSuccessfully"),
            object: nil
        )
    }

    @objc private func handleCookieRefreshedNotification(_: Notification) {
        LogService.shared.debug(.core, "收到 Cookie 刷新成功通知")
        handleCookieRefreshed()
        onlineStateManager.refreshStatus()
    }
}
