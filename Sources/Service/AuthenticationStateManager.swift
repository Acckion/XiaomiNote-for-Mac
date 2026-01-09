import Foundation
import Combine
import AppKit

/// 认证状态管理器
/// 
/// 统一管理登录、Cookie刷新和认证相关的UI状态
/// 在线状态由 OnlineStateManager 统一管理，这里只负责同步和UI状态
@MainActor
class AuthenticationStateManager: ObservableObject {
    // MARK: - 状态属性
    
    /// 是否在线（从 OnlineStateManager 同步，但受用户选择的离线模式影响）
    @Published var isOnline: Bool = true
    
    /// Cookie是否失效
    @Published var isCookieExpired: Bool = false
    
    /// 是否已显示Cookie失效提示（避免重复提示）
    @Published var cookieExpiredShown: Bool = false
    
    /// 是否显示Cookie失效弹窗
    @Published var showCookieExpiredAlert: Bool = false
    
    /// 是否保持离线模式（用户点击"取消"后设置为true，阻止后续请求）
    @Published var shouldStayOffline: Bool = false
    
    /// 是否显示登录视图
    @Published var showLoginView: Bool = false
    
    /// 是否显示Cookie刷新视图
    @Published var showCookieRefreshView: Bool = false
    
    // MARK: - 失败计数和防重入机制
    
    /// 连续刷新失败次数计数器
    private var consecutiveFailures: Int = 0
    
    /// 最大连续失败次数限制
    private let maxConsecutiveFailures: Int = 3
    
    /// 刷新周期标志，防止重入
    private var isInRefreshCycle: Bool = false
    
    // MARK: - 依赖服务
    
    private let service = MiNoteService.shared
    private let onlineStateManager = OnlineStateManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    init() {
        setupOnlineStateSync()
        setupCookieExpiredHandler()
        setupCookieRefreshNotification()
        
        // 启动 ScheduledTaskManager 定时任务
        Task { @MainActor in
            ScheduledTaskManager.shared.start()
            // 立即刷新一次在线状态
            onlineStateManager.refreshStatus()
        }
    }
    
    // MARK: - 在线状态同步
    
    /// 设置在线状态同步
    /// 
    /// 从 OnlineStateManager 同步在线状态，但需要考虑用户选择的离线模式
    private func setupOnlineStateSync() {
        // 监听 OnlineStateManager 的在线状态变化
        onlineStateManager.$isOnline
            .sink { [weak self] onlineStatus in
                Task { @MainActor in
                    self?.updateOnlineStatusFromManager(onlineStatus)
                }
            }
            .store(in: &cancellables)
        
        // 监听 Cookie 有效性变化，更新 Cookie 失效状态
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
        // 如果用户选择保持离线模式，强制设置为离线
        if shouldStayOffline {
            if isOnline {
                isOnline = false
            }
            return
        }
        
        // 如果弹窗正在显示（等待用户选择），保持离线状态
        if cookieExpiredShown {
            if isOnline {
                isOnline = false
            }
            return
        }
        
        // 正常同步在线状态
        isOnline = onlineStatus
    }
    
    /// 更新 Cookie 失效状态
    private func updateCookieExpiredStatus(isValid: Bool) {
        // 如果用户选择保持离线模式，不自动更新
        if shouldStayOffline {
            return
        }
        
        // 如果弹窗正在显示，不自动更新
        if cookieExpiredShown {
            return
        }
        
        // 更新 Cookie 失效状态
        if !isValid {
            isCookieExpired = true
            print("[AuthenticationStateManager] Cookie失效，标记为失效状态")
        } else {
            // Cookie 恢复有效时，清除失效状态
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
        // 检查是否启用静默刷新
        let silentRefreshEnabled = UserDefaults.standard.bool(forKey: "silentRefreshOnFailure")
        print("[AuthenticationStateManager] 处理Cookie失效，silentRefreshOnFailure: \(silentRefreshEnabled)")
        
        // 立即设置为离线状态，阻止后续请求
        isOnline = false
        isCookieExpired = true
        
        // 只有在未保持离线模式且未显示过弹窗时，才处理
        if !shouldStayOffline && !cookieExpiredShown {
            // 标记为已显示过弹窗，避免重复触发
            cookieExpiredShown = true
            
            if silentRefreshEnabled {
                print("[AuthenticationStateManager] 静默刷新已启用，开始静默刷新流程")
                // 尝试静默刷新
                Task {
                    await attemptSilentRefresh()
                }
            } else {
                print("[AuthenticationStateManager] 静默刷新未启用，直接显示弹窗")
                // 直接显示弹窗
                showCookieExpiredAlert = true
            }
        } else if shouldStayOffline {
            // 如果用户已选择保持离线模式，不再处理
            cookieExpiredShown = true
            print("[AuthenticationStateManager] Cookie失效，用户已选择保持离线模式，不再处理")
        } else {
            // 已经处理过，只更新状态
            print("[AuthenticationStateManager] Cookie失效，已处理过，只更新离线状态")
        }
    }
    
    /// 尝试静默刷新Cookie
    /// 
    /// 增强版本：添加防重入检查、暂停定时检查任务、同步等待验证完成
    private func attemptSilentRefresh() async {
        // 防重入检查
        guard !isInRefreshCycle else {
            print("[AuthenticationStateManager] ⚠️ 已在刷新周期中，跳过重复请求")
            return
        }
        
        // 检查是否已达到最大失败次数
        guard consecutiveFailures < maxConsecutiveFailures else {
            print("[AuthenticationStateManager] ⚠️ 已达到最大失败次数 (\(maxConsecutiveFailures))，不再自动刷新")
            showCookieExpiredAlert = true
            return
        }
        
        isInRefreshCycle = true
        defer { isInRefreshCycle = false }
        
        print("[AuthenticationStateManager] 🚀 开始静默刷新Cookie流程")
        print("[AuthenticationStateManager] 📊 当前状态: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired), consecutiveFailures=\(consecutiveFailures)")
        
        // 暂停定时检查任务，避免刷新期间触发检查
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")
        
        do {
            print("[AuthenticationStateManager] 📡 调用MiNoteService.refreshCookie()...")
            // 尝试刷新Cookie
            let refreshSuccess = try await MiNoteService.shared.refreshCookie()
            print("[AuthenticationStateManager] 📡 refreshCookie()返回: \(refreshSuccess)")
            
            if refreshSuccess {
                print("[AuthenticationStateManager] ✅ 静默刷新成功，开始验证Cookie有效性...")
                
                // 关键修复：同步等待验证完成
                let isValid = try await MiNoteService.shared.checkCookieValidity()
                print("[AuthenticationStateManager] 📡 checkCookieValidity()返回: \(isValid)")
                
                if isValid {
                    // Cookie 确实有效，恢复在线状态
                    consecutiveFailures = 0
                    restoreOnlineStatusAfterValidation(isValid: true)
                    print("[AuthenticationStateManager] ✅ Cookie 刷新并验证成功")
                } else {
                    // 刷新成功但验证失败
                    handleRefreshSuccessButValidationFailed()
                }
            } else {
                // 刷新返回 false
                handleRefreshFailure()
            }
        } catch {
            print("[AuthenticationStateManager] ❌ 静默刷新失败: \(error)")
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
    
    // MARK: - 刷新失败处理
    
    /// 处理刷新成功但验证失败的情况
    /// 
    /// 当 Cookie 刷新成功但服务器端验证失败时调用
    private func handleRefreshSuccessButValidationFailed() {
        consecutiveFailures += 1
        print("[AuthenticationStateManager] ⚠️ 刷新成功但验证失败，失败次数: \(consecutiveFailures)/\(maxConsecutiveFailures)")
        
        if consecutiveFailures >= maxConsecutiveFailures {
            print("[AuthenticationStateManager] ❌ 达到最大失败次数，显示弹窗")
            showCookieExpiredAlert = true
            // 不清除 cookieExpiredShown，保持离线状态
        }
        // 注意：不打印"成功恢复在线状态"，因为验证失败
    }
    
    /// 处理刷新失败
    /// 
    /// 当 Cookie 刷新本身失败时调用
    private func handleRefreshFailure() {
        consecutiveFailures += 1
        print("[AuthenticationStateManager] ❌ 刷新失败，失败次数: \(consecutiveFailures)/\(maxConsecutiveFailures)")
        
        if consecutiveFailures >= maxConsecutiveFailures {
            print("[AuthenticationStateManager] ❌ 达到最大失败次数，显示弹窗")
            showCookieExpiredAlert = true
            isCookieExpired = true
            isOnline = false
        }
    }
    
    /// 验证后恢复在线状态
    /// 
    /// 只有当 Cookie 确实有效时才恢复在线状态
    /// - Parameter isValid: Cookie 是否有效
    private func restoreOnlineStatusAfterValidation(isValid: Bool) {
        guard isValid else {
            print("[AuthenticationStateManager] ⚠️ Cookie 无效，不恢复在线状态")
            // 注意：不打印"成功恢复在线状态"
            return
        }
        
        print("[AuthenticationStateManager] ✅ Cookie 验证通过，恢复在线状态")
        
        // 只有 Cookie 有效时才清除这些标志
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false
        showCookieExpiredAlert = false
        isOnline = true
        
        // 刷新 OnlineStateManager 的状态
        onlineStateManager.refreshStatus()
        
        print("[AuthenticationStateManager] ✅ 状态已更新: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired)")
    }
    
    // MARK: - 公共方法
    
    /// 恢复在线状态
    /// 
    /// 当Cookie恢复有效时调用此方法
    func restoreOnlineStatus() {
        // 使用 ScheduledTaskManager 的实时检查结果
        let hasValidCookie = ScheduledTaskManager.shared.isCookieValid
        
        guard hasValidCookie else {
            print("[AuthenticationStateManager] Cookie仍然无效，不能恢复在线状态")
            return
        }
        
        print("[AuthenticationStateManager] 恢复在线状态")
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false  // 清除离线模式标志
        showCookieExpiredAlert = false  // 清除弹窗状态
        
        // 刷新 OnlineStateManager 的状态，然后同步
        onlineStateManager.refreshStatus()
        
        if isOnline {
            print("[AuthenticationStateManager] ✅ 已恢复在线状态")
        }
    }
    
    /// 处理Cookie失效弹窗的"刷新Cookie"选项
    func handleCookieExpiredRefresh() {
        print("[AuthenticationStateManager] 用户选择刷新Cookie")
        shouldStayOffline = false
        showCookieRefreshView = true
        
        // 手动刷新时重置计数器和冷却期
        handleManualRefresh()
    }
    
    /// 处理手动刷新
    /// 
    /// 当用户手动触发刷新时调用，重置失败计数器和冷却期
    func handleManualRefresh() {
        print("[AuthenticationStateManager] 🔄 手动刷新：重置失败计数器和冷却期")
        consecutiveFailures = 0
        SilentCookieRefreshManager.shared.resetCooldown()
        
        // 清除弹窗显示标志，允许重新触发刷新流程
        cookieExpiredShown = false
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
        // 清除cookie失效状态
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false  // 清除离线模式标志
        showCookieExpiredAlert = false  // 清除弹窗状态
        
        // 恢复在线状态
        restoreOnlineStatus()
        
        print("[AuthenticationStateManager] ✅ Cookie刷新完成，状态已更新: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired)")
    }
    
    /// 执行静默Cookie刷新（旧方法，保持兼容性）
    /// 
    /// 自动地、隐藏界面地进行刷新，如果失败则显示弹窗
    private func performSilentCookieRefresh() async {
        NetworkLogger.shared.logRequest(
            url: "silent-cookie-refresh",
            method: "POST",
            headers: nil,
            body: "开始静默Cookie刷新流程"
        )
        print("[AuthenticationStateManager] 开始执行静默Cookie刷新")
        
        // 记录开始时间
        let startTime = Date()
        
        // 直接调用 SilentCookieRefreshManager 进行刷新
        do {
            let success = try await SilentCookieRefreshManager.shared.refresh()
            let elapsedTime = Date().timeIntervalSince(startTime)
            
            await MainActor.run {
                if success {
                    NetworkLogger.shared.logResponse(
                        url: "silent-cookie-refresh",
                        method: "POST",
                        statusCode: 200,
                        headers: nil,
                        response: "静默Cookie刷新成功，耗时\(String(format: "%.2f", elapsedTime))秒",
                        error: nil
                    )
                    print("[AuthenticationStateManager] ✅ 静默Cookie刷新成功，耗时\(String(format: "%.2f", elapsedTime))秒")
                    // 恢复在线状态
                    restoreOnlineStatus()
                } else {
                    NetworkLogger.shared.logError(
                        url: "silent-cookie-refresh",
                        method: "POST",
                        error: NSError(domain: "AuthenticationStateManager", code: 401, userInfo: [
                            NSLocalizedDescriptionKey: "静默Cookie刷新失败，耗时\(String(format: "%.2f", elapsedTime))秒"
                        ])
                    )
                    print("[AuthenticationStateManager] ❌ 静默Cookie刷新失败，耗时\(String(format: "%.2f", elapsedTime))秒，显示弹窗要求手动刷新")
                    // 显示弹窗要求用户手动刷新
                    showCookieExpiredAlert = true
                }
            }
        } catch {
            let elapsedTime = Date().timeIntervalSince(startTime)
            await MainActor.run {
                NetworkLogger.shared.logError(
                    url: "silent-cookie-refresh",
                    method: "POST",
                    error: NSError(domain: "AuthenticationStateManager", code: 401, userInfo: [
                        NSLocalizedDescriptionKey: "静默Cookie刷新失败，耗时\(String(format: "%.2f", elapsedTime))秒，错误: \(error.localizedDescription)"
                    ])
                )
                print("[AuthenticationStateManager] ❌ 静默Cookie刷新失败，耗时\(String(format: "%.2f", elapsedTime))秒，错误: \(error.localizedDescription)，显示弹窗要求手动刷新")
                // 显示弹窗要求用户手动刷新
                showCookieExpiredAlert = true
            }
        }
    }
    
    /// 显示登录视图
    func showLogin() {
        showLoginView = true
    }
    
    /// 显示Cookie刷新视图
    func showCookieRefresh() {
        showCookieRefreshView = true
    }
    
    /// 关闭登录视图
    func dismissLogin() {
        showLoginView = false
    }
    
    /// 关闭Cookie刷新视图
    func dismissCookieRefresh() {
        showCookieRefreshView = false
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
    @objc private func handleCookieRefreshedNotification(_ notification: Notification) {
        print("[AuthenticationStateManager] 收到Cookie刷新成功通知")
        
        // 调用handleCookieRefreshed方法来更新状态
        handleCookieRefreshed()
        
        // 刷新 OnlineStateManager 的状态
        onlineStateManager.refreshStatus()
    }
}
