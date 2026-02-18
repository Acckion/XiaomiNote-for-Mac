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

    /// 是否在线（从 OnlineStateManager 同步，但受用户选择的离线模式影响）
    @Published var isOnline = true

    /// Cookie是否失效
    @Published var isCookieExpired = false

    /// 是否已显示Cookie失效提示（避免重复提示）
    @Published var cookieExpiredShown = false

    /// 是否显示Cookie失效弹窗
    @Published var showCookieExpiredAlert = false

    /// 是否保持离线模式（用户点击"取消"后设置为true，阻止后续请求）
    @Published var shouldStayOffline = false

    /// 是否显示登录视图
    @Published var showLoginView = false

    // MARK: - 静默刷新状态属性

    /// 是否正在刷新Cookie
    ///
    /// 当静默刷新正在进行时为 true，用于 UI 显示刷新状态指示
    @Published var isRefreshingCookie = false

    /// 刷新状态消息
    ///
    /// 显示当前刷新操作的状态信息，如"正在刷新登录状态..."
    @Published var refreshStatusMessage = ""

    // MARK: - 失败计数和防重入机制

    /// 连续刷新失败次数计数器
    private var consecutiveFailures = 0

    /// 最大连续失败次数限制
    private let maxConsecutiveFailures = 3

    /// 刷新周期标志，防止重入
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

    /// 设置在线状态同步
    ///
    /// 从 OnlineStateManager 同步在线状态，但需要考虑用户选择的离线模式
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

    /// 从 OnlineStateManager 更新在线状态
    private func updateOnlineStatusFromManager(_ onlineStatus: Bool) {
        if shouldStayOffline {
            if isOnline {
                isOnline = false
            }
            return
        }

        if cookieExpiredShown {
            if isOnline {
                isOnline = false
            }
            return
        }

        isOnline = onlineStatus
    }

    /// 更新 Cookie 失效状态
    private func updateCookieExpiredStatus(isValid: Bool) {
        if shouldStayOffline {
            return
        }

        if cookieExpiredShown {
            return
        }

        if !isValid {
            isCookieExpired = true
            print("[AuthenticationStateManager] Cookie失效，标记为失效状态")
        } else {
            if isCookieExpired {
                isCookieExpired = false
                print("[AuthenticationStateManager] Cookie恢复有效，清除失效状态")
            }
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

    /// 处理Cookie过期（支持静默刷新）
    func handleCookieExpired() {
        let silentRefreshEnabled: Bool = if UserDefaults.standard.object(forKey: "silentRefreshOnFailure") != nil {
            UserDefaults.standard.bool(forKey: "silentRefreshOnFailure")
        } else {
            true
        }
        print("[AuthenticationStateManager] 处理Cookie失效，silentRefreshOnFailure: \(silentRefreshEnabled)")

        isOnline = false
        isCookieExpired = true

        if !shouldStayOffline, !cookieExpiredShown {
            cookieExpiredShown = true

            if silentRefreshEnabled {
                print("[AuthenticationStateManager] 静默刷新已启用，开始静默刷新流程")
                Task {
                    await attemptSilentRefresh()
                }
            } else {
                print("[AuthenticationStateManager] 静默刷新未启用，直接显示弹窗")
                showCookieExpiredAlert = true
            }
        } else if shouldStayOffline {
            cookieExpiredShown = true
            print("[AuthenticationStateManager] Cookie失效，用户已选择保持离线模式，不再处理")
        } else {
            print("[AuthenticationStateManager] Cookie失效，已处理过，只更新离线状态")
        }
    }

    /// 尝试静默刷新Cookie
    ///
    /// 通过 PassTokenManager 执行三步流程刷新 serviceToken
    private func attemptSilentRefresh() async {
        // 防重入检查
        guard !isInRefreshCycle else {
            print("[AuthenticationStateManager] 已在刷新周期中，跳过重复请求")
            return
        }

        // 检查是否已达到最大失败次数
        guard consecutiveFailures < maxConsecutiveFailures else {
            print("[AuthenticationStateManager] 已达到最大失败次数 (\(maxConsecutiveFailures))，不再自动刷新")
            showCookieExpiredAlert = true
            return
        }

        isInRefreshCycle = true
        defer { isInRefreshCycle = false }

        print("[AuthenticationStateManager] 开始静默刷新流程")
        print(
            "[AuthenticationStateManager] 当前状态: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired), consecutiveFailures=\(consecutiveFailures)"
        )

        // 暂停定时检查任务，避免刷新期间触发检查
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")

        do {
            print("[AuthenticationStateManager] 调用 PassTokenManager.refreshServiceToken()...")
            _ = try await PassTokenManager.shared.refreshServiceToken()
            print("[AuthenticationStateManager] PassTokenManager 刷新成功，开始验证Cookie有效性...")

            let isValid = try await MiNoteService.shared.checkCookieValidity()
            print("[AuthenticationStateManager] checkCookieValidity() 返回: \(isValid)")

            if isValid {
                consecutiveFailures = 0
                restoreOnlineStatusAfterValidation(isValid: true)
                print("[AuthenticationStateManager] 刷新并验证成功")
            } else {
                handleRefreshSuccessButValidationFailed()
            }
        } catch let passTokenError as PassTokenError {
            switch passTokenError {
            case .noPassToken, .noUserId:
                print("[AuthenticationStateManager] passToken 不存在，提示重新登录")
                await handlePassTokenInvalid()
            default:
                print("[AuthenticationStateManager] 静默刷新失败: \(passTokenError)")
                handleRefreshFailure()
            }
        } catch {
            print("[AuthenticationStateManager] 静默刷新失败: \(error)")
            handleRefreshFailure()
        }

        // 恢复定时检查任务（带 30 秒宽限期）
        ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
    }

    /// 静默处理Cookie失效（由ContentView调用）
    func handleCookieExpiredSilently() async {
        print("[AuthenticationStateManager] 静默处理Cookie失效")
        await attemptSilentRefresh()
    }

    /// 尝试静默刷新Cookie（带状态更新）
    ///
    /// 通过 PassTokenManager 刷新 serviceToken，在刷新过程中更新状态属性
    ///
    /// - Returns: 刷新是否成功
    func attemptSilentRefreshWithStatus() async -> Bool {
        // 防重入检查
        guard !isInRefreshCycle else {
            print("[AuthenticationStateManager] 已在刷新周期中，跳过重复请求")
            return false
        }

        // 检查是否已达到最大失败次数
        guard consecutiveFailures < maxConsecutiveFailures else {
            print("[AuthenticationStateManager] 已达到最大失败次数 (\(maxConsecutiveFailures))，不再自动刷新")
            showCookieExpiredAlert = true
            return false
        }

        isInRefreshCycle = true

        // 更新刷新状态
        isRefreshingCookie = true
        refreshStatusMessage = "正在刷新登录状态..."

        print("[AuthenticationStateManager] 开始静默刷新流程（带状态更新）")
        print(
            "[AuthenticationStateManager] 当前状态: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired), consecutiveFailures=\(consecutiveFailures)"
        )

        // 暂停定时检查任务
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")

        defer {
            isInRefreshCycle = false
            isRefreshingCookie = false
            refreshStatusMessage = ""
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }

        do {
            refreshStatusMessage = "正在连接服务器..."
            print("[AuthenticationStateManager] 调用 PassTokenManager.refreshServiceToken()...")

            let _ = try await PassTokenManager.shared.refreshServiceToken()
            print("[AuthenticationStateManager] PassTokenManager 刷新成功，开始验证Cookie有效性...")

            refreshStatusMessage = "正在验证Cookie有效性..."
            let isValid = try await MiNoteService.shared.checkCookieValidity()
            print("[AuthenticationStateManager] checkCookieValidity() 返回: \(isValid)")

            if isValid {
                consecutiveFailures = 0
                refreshStatusMessage = "登录状态已恢复"
                restoreOnlineStatusAfterValidation(isValid: true)
                print("[AuthenticationStateManager] 刷新并验证成功")
                return true
            } else {
                refreshStatusMessage = "验证失败，请重新登录"
                handleRefreshSuccessButValidationFailed()
                return false
            }
        } catch let passTokenError as PassTokenError {
            switch passTokenError {
            case .noPassToken, .noUserId:
                print("[AuthenticationStateManager] passToken 不存在，提示重新登录")
                refreshStatusMessage = "需要重新登录"
                await handlePassTokenInvalid()
            default:
                print("[AuthenticationStateManager] 静默刷新失败: \(passTokenError)")
                refreshStatusMessage = "刷新失败: \(passTokenError.localizedDescription)"
                handleRefreshFailure()
            }
            return false
        } catch {
            print("[AuthenticationStateManager] 静默刷新发生未知错误: \(error)")
            refreshStatusMessage = "刷新失败: \(error.localizedDescription)"
            handleRefreshFailure()
            return false
        }
    }

    // MARK: - 刷新失败处理

    /// 处理刷新成功但验证失败的情况
    private func handleRefreshSuccessButValidationFailed() {
        consecutiveFailures += 1
        print("[AuthenticationStateManager] 刷新成功但验证失败，失败次数: \(consecutiveFailures)/\(maxConsecutiveFailures)")

        if consecutiveFailures >= maxConsecutiveFailures {
            print("[AuthenticationStateManager] 达到最大失败次数，提示重新登录")
            showCookieExpiredAlert = true
        }
    }

    /// 处理刷新失败
    private func handleRefreshFailure() {
        consecutiveFailures += 1
        print("[AuthenticationStateManager] 刷新失败，失败次数: \(consecutiveFailures)/\(maxConsecutiveFailures)")

        if consecutiveFailures >= maxConsecutiveFailures {
            print("[AuthenticationStateManager] 达到最大失败次数，提示重新登录")
            showCookieExpiredAlert = true
            isCookieExpired = true
            isOnline = false
        }
    }

    /// 处理 passToken 失效
    ///
    /// 清除凭据并提示用户重新登录
    private func handlePassTokenInvalid() async {
        print("[AuthenticationStateManager] passToken 失效，清除凭据并提示重新登录")
        await PassTokenManager.shared.clearCredentials()
        isCookieExpired = true
        isOnline = false
        showLoginView = true
    }

    /// 验证后恢复在线状态
    private func restoreOnlineStatusAfterValidation(isValid: Bool) {
        guard isValid else {
            print("[AuthenticationStateManager] Cookie 无效，不恢复在线状态")
            return
        }

        print("[AuthenticationStateManager] Cookie 验证通过，恢复在线状态")

        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false
        showCookieExpiredAlert = false
        isOnline = true

        onlineStateManager.refreshStatus()

        print("[AuthenticationStateManager] 状态已更新: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired)")
    }

    // MARK: - 公共方法

    /// 恢复在线状态
    ///
    /// 当Cookie恢复有效时调用此方法
    func restoreOnlineStatus() {
        let hasValidCookie = ScheduledTaskManager.shared.isCookieValid

        guard hasValidCookie else {
            print("[AuthenticationStateManager] Cookie仍然无效，不能恢复在线状态")
            return
        }

        print("[AuthenticationStateManager] 恢复在线状态")
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false
        showCookieExpiredAlert = false

        onlineStateManager.refreshStatus()

        if isOnline {
            print("[AuthenticationStateManager] 已恢复在线状态")
        }
    }

    /// 处理Cookie失效弹窗的"刷新"选项
    ///
    /// 改为清除 passToken 并显示登录视图，让用户重新登录
    func handleCookieExpiredRefresh() {
        print("[AuthenticationStateManager] 用户选择重新登录")
        shouldStayOffline = false

        // 清除 passToken 并显示登录视图
        Task {
            await PassTokenManager.shared.clearCredentials()
            showLoginView = true
        }
    }

    /// 处理响应式刷新（401 错误触发）
    ///
    /// 当检测到 Cookie 失效（401 错误）时调用，通过 PassTokenManager 刷新 serviceToken
    ///
    /// - Returns: 刷新是否成功
    func handleReactiveRefresh() async -> Bool {
        print("[AuthenticationStateManager] 响应式刷新：检测到 401 错误，立即刷新")

        // 防重入检查
        guard !isInRefreshCycle else {
            print("[AuthenticationStateManager] 已在刷新周期中，跳过响应式刷新")
            return false
        }

        isInRefreshCycle = true
        defer { isInRefreshCycle = false }

        // 更新刷新状态
        isRefreshingCookie = true
        refreshStatusMessage = "检测到登录失效，正在刷新..."

        // 暂停定时检查任务
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")

        defer {
            isRefreshingCookie = false
            refreshStatusMessage = ""
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }

        do {
            print("[AuthenticationStateManager] 调用 PassTokenManager.refreshServiceToken()")

            let _ = try await PassTokenManager.shared.refreshServiceToken()
            print("[AuthenticationStateManager] PassTokenManager 刷新成功，开始验证 Cookie 有效性...")

            refreshStatusMessage = "正在验证 Cookie 有效性..."
            let isValid = try await MiNoteService.shared.checkCookieValidity()
            print("[AuthenticationStateManager] checkCookieValidity() 返回: \(isValid)")

            if isValid {
                consecutiveFailures = 0
                refreshStatusMessage = "登录状态已恢复"
                restoreOnlineStatusAfterValidation(isValid: true)
                print("[AuthenticationStateManager] 响应式刷新并验证成功")
                return true
            } else {
                refreshStatusMessage = "验证失败"
                handleRefreshSuccessButValidationFailed()
                return false
            }
        } catch let passTokenError as PassTokenError {
            switch passTokenError {
            case .noPassToken, .noUserId:
                print("[AuthenticationStateManager] passToken 不存在，提示重新登录")
                refreshStatusMessage = "需要重新登录"
                await handlePassTokenInvalid()
            default:
                print("[AuthenticationStateManager] 响应式刷新失败: \(passTokenError)")
                refreshStatusMessage = "刷新失败: \(passTokenError.localizedDescription)"
                handleRefreshFailure()
            }
            return false
        } catch {
            print("[AuthenticationStateManager] 响应式刷新发生未知错误: \(error)")
            refreshStatusMessage = "刷新失败: \(error.localizedDescription)"
            handleRefreshFailure()
            return false
        }
    }

    /// 处理手动刷新
    ///
    /// 当用户手动触发刷新时调用，重置失败计数器，通过 PassTokenManager 刷新
    ///
    /// - Returns: 刷新是否成功
    @discardableResult
    func handleManualRefresh() async -> Bool {
        print("[AuthenticationStateManager] 手动刷新：重置失败计数器")

        // 防重入检查
        guard !isInRefreshCycle else {
            print("[AuthenticationStateManager] 已在刷新周期中，跳过手动刷新")
            return false
        }

        isInRefreshCycle = true
        defer { isInRefreshCycle = false }

        // 重置失败计数器
        consecutiveFailures = 0
        cookieExpiredShown = false

        // 更新刷新状态
        isRefreshingCookie = true
        refreshStatusMessage = "正在手动刷新登录状态..."

        // 暂停定时检查任务
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")

        defer {
            isRefreshingCookie = false
            refreshStatusMessage = ""
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }

        do {
            print("[AuthenticationStateManager] 调用 PassTokenManager.refreshServiceToken()")

            let _ = try await PassTokenManager.shared.refreshServiceToken()
            print("[AuthenticationStateManager] PassTokenManager 刷新成功，开始验证 Cookie 有效性...")

            refreshStatusMessage = "正在验证 Cookie 有效性..."
            let isValid = try await MiNoteService.shared.checkCookieValidity()
            print("[AuthenticationStateManager] checkCookieValidity() 返回: \(isValid)")

            if isValid {
                consecutiveFailures = 0
                refreshStatusMessage = "登录状态已恢复"
                restoreOnlineStatusAfterValidation(isValid: true)
                print("[AuthenticationStateManager] 手动刷新并验证成功")
                return true
            } else {
                refreshStatusMessage = "验证失败"
                handleRefreshSuccessButValidationFailed()
                return false
            }
        } catch let passTokenError as PassTokenError {
            switch passTokenError {
            case .noPassToken, .noUserId:
                print("[AuthenticationStateManager] passToken 不存在，提示重新登录")
                refreshStatusMessage = "需要重新登录"
                await handlePassTokenInvalid()
            default:
                print("[AuthenticationStateManager] 手动刷新失败: \(passTokenError)")
                refreshStatusMessage = "刷新失败: \(passTokenError.localizedDescription)"
                handleRefreshFailure()
            }
            return false
        } catch {
            print("[AuthenticationStateManager] 手动刷新发生未知错误: \(error)")
            refreshStatusMessage = "刷新失败: \(error.localizedDescription)"
            handleRefreshFailure()
            return false
        }
    }

    /// 处理Cookie失效弹窗的"取消"选项
    func handleCookieExpiredCancel() {
        print("[AuthenticationStateManager] 用户选择保持离线模式")
        shouldStayOffline = true
        isOnline = false
        isCookieExpired = true
        print("[AuthenticationStateManager] 已设置为离线模式，后续请求将不会发送")
    }

    /// 处理Cookie刷新完成
    ///
    /// Cookie刷新成功后调用此方法
    func handleCookieRefreshed() {
        print("[AuthenticationStateManager] Cookie刷新完成")
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false
        showCookieExpiredAlert = false

        // 重置失败计数器
        consecutiveFailures = 0

        // 立即更新 ScheduledTaskManager 的 Cookie 有效性状态
        ScheduledTaskManager.shared.setCookieValid(true)

        // 延迟恢复在线状态，确保 Cookie 完全生效
        Task { @MainActor in
            print("[AuthenticationStateManager] 延迟 1.5 秒后恢复在线状态，确保 Cookie 完全生效")
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            self.restoreOnlineStatus()

            print("[AuthenticationStateManager] Cookie刷新完成，状态已更新: isOnline=\(self.isOnline), isCookieExpired=\(self.isCookieExpired)")
        }
    }

    /// 显示登录视图
    func showLogin() {
        showLoginView = true
    }

    /// 关闭登录视图
    func dismissLogin() {
        showLoginView = false
    }

    // MARK: - Cookie刷新通知处理

    /// 设置Cookie刷新成功通知监听
    private func setupCookieRefreshNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCookieRefreshedNotification(_:)),
            name: NSNotification.Name("CookieRefreshedSuccessfully"),
            object: nil
        )
    }

    /// 处理Cookie刷新成功通知
    @objc private func handleCookieRefreshedNotification(_: Notification) {
        print("[AuthenticationStateManager] 收到Cookie刷新成功通知")
        handleCookieRefreshed()
        onlineStateManager.refreshStatus()
    }
}
