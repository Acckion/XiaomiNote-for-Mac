import Foundation
import Combine
import AppKit

/// 认证状态管理器
/// 
/// 统一管理登录、Cookie刷新和在线状态的逻辑
/// 负责协调网络监控、Cookie状态和用户选择的离线模式
@MainActor
class AuthenticationStateManager: ObservableObject {
    // MARK: - 状态属性
    
    /// 是否在线（需要同时满足网络连接和Cookie有效）
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
    
    // MARK: - 定时器状态
    
    /// 当前检查频率（秒）
    private var currentCheckInterval: TimeInterval = 10.0
    
    /// 连续有效检查次数
    private var consecutiveValidChecks: Int = 0
    
    /// 应用是否在前台活跃
    private var isAppActive: Bool = true
    
    /// 当前定时器
    private var statusCheckTimer: Timer?
    
    // MARK: - 依赖服务
    
    private let service = MiNoteService.shared
    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    init() {
        setupAppStateMonitoring()
        setupNetworkMonitoring()
        setupCookieExpiredHandler()
        
        // 启动定时器需要在主线程上执行
        Task { @MainActor in
            startSmartTimer()
            // 立即执行一次状态检查，确保初始状态正确
            performStatusCheck()
        }
    }
    
    @MainActor
    deinit {
        // 简化 deinit，避免访问非 Sendable 属性
        // 定时器会在对象释放时自动失效
        // 不需要手动停止，因为 Timer 会随着对象的释放而自动失效
    }
    
    // MARK: - 应用状态监控
    
    private func setupAppStateMonitoring() {
        // 监听应用状态变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appDidBecomeActive() {
        print("[AuthenticationStateManager] 应用进入前台")
        isAppActive = true
        adjustCheckFrequency()
    }
    
    @objc private func appDidResignActive() {
        print("[AuthenticationStateManager] 应用进入后台")
        isAppActive = false
        adjustCheckFrequency()
    }
    
    // MARK: - 智能定时器管理
    
    /// 启动智能定时器
    private func startSmartTimer() {
        stopTimer() // 确保没有重复的定时器
        
        print("[AuthenticationStateManager] 启动智能定时器，间隔: \(currentCheckInterval)秒")
        
        statusCheckTimer = Timer.scheduledTimer(withTimeInterval: currentCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performStatusCheck()
            }
        }
    }
    
    /// 停止定时器
    private func stopTimer() {
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil
    }
    
    /// 调整检查频率
    private func adjustCheckFrequency() {
        let oldInterval = currentCheckInterval
        
        if !networkMonitor.isOnline {
            // 网络断开时暂停检查
            currentCheckInterval = 60.0 // 每分钟检查一次
            print("[AuthenticationStateManager] 网络断开，降低检查频率到60秒")
        } else if !isAppActive {
            // 应用在后台时降低频率
            currentCheckInterval = 30.0 // 每30秒检查一次
            print("[AuthenticationStateManager] 应用在后台，检查频率30秒")
        } else if consecutiveValidChecks >= 6 { // 连续6次有效（约1分钟）
            // Cookie长时间有效，降低频率
            currentCheckInterval = 30.0 // 每30秒检查一次
            print("[AuthenticationStateManager] Cookie长时间有效，检查频率30秒")
        } else if consecutiveValidChecks >= 3 { // 连续3次有效（约30秒）
            // Cookie稳定有效，中等频率
            currentCheckInterval = 15.0 // 每15秒检查一次
            print("[AuthenticationStateManager] Cookie稳定有效，检查频率15秒")
        } else {
            // 默认频率：前台活跃
            currentCheckInterval = 10.0 // 每10秒检查一次
            print("[AuthenticationStateManager] 前台活跃，检查频率10秒")
        }
        
        // 如果频率发生变化，重启定时器
        if oldInterval != currentCheckInterval {
            startSmartTimer()
        }
    }
    
    /// 执行状态检查
    private func performStatusCheck() {
        let networkOnline = networkMonitor.isOnline
        updateOnlineStatus(networkOnline: networkOnline)
    }
    
    // MARK: - 网络监控
    
    private func setupNetworkMonitoring() {
        // 计算在线状态：需要同时满足网络连接和cookie有效
        // 区分三种状态：
        // 1. 在线：网络正常且cookie有效
        // 2. Cookie失效：网络正常但cookie失效
        // 3. 离线：网络断开
        
        networkMonitor.$isOnline
            .sink { [weak self] networkOnline in
                Task { @MainActor in
                    // 网络状态变化时立即检查
                    self?.updateOnlineStatus(networkOnline: networkOnline)
                    // 调整检查频率
                    self?.adjustCheckFrequency()
                }
            }
            .store(in: &cancellables)
    }
    
    /// 更新在线状态
    private func updateOnlineStatus(networkOnline: Bool) {
        // 如果用户选择保持离线模式，不自动更新在线状态
        if shouldStayOffline {
            maintainOfflineState()
            return
        }
        
        // 如果弹窗正在显示（等待用户选择），不自动更新在线状态
        // 确保在弹窗显示期间状态保持为"Cookie失效"而不是"在线"
        if cookieExpiredShown {
            maintainCookieExpiredState()
            return
        }
        
        // 如果Cookie已经失效，不再检查（失效的Cookie不会自动恢复）
        if isCookieExpired {
            print("[AuthenticationStateManager] Cookie已失效，跳过检查，等待用户处理")
            return
        }
        
        let hasValidCookie = service.hasValidCookie()
        
        // 正常更新在线状态
        // 注意：如果用户选择了保持离线模式，即使Cookie恢复有效，也不自动清除离线模式
        // 用户需要手动刷新Cookie或重新登录才能恢复在线状态
        
        isOnline = networkOnline && hasValidCookie
        
        // 如果网络正常但cookie无效，标记为cookie失效
        if networkOnline && !hasValidCookie {
            isCookieExpired = true
            // Cookie失效时重置连续有效计数
            consecutiveValidChecks = 0
            print("[AuthenticationStateManager] Cookie失效，标记为失效状态")
        } else if hasValidCookie {
            // Cookie有效时，清除失效状态
            isCookieExpired = false
            // 增加连续有效计数
            consecutiveValidChecks += 1
            print("[AuthenticationStateManager] Cookie有效，连续有效次数: \(consecutiveValidChecks)")
        } else {
            // 网络断开时重置计数
            consecutiveValidChecks = 0
            print("[AuthenticationStateManager] 网络断开，重置连续有效计数")
        }
        
        // 根据连续有效次数调整检查频率
        adjustCheckFrequency()
    }
    
    /// 保持离线状态
    private func maintainOfflineState() {
        if isOnline {
            isOnline = false
        }
        if !isCookieExpired {
            isCookieExpired = true
        }
    }
    
    /// 保持Cookie失效状态
    private func maintainCookieExpiredState() {
        if isOnline {
            isOnline = false
        }
        if !isCookieExpired {
            isCookieExpired = true
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
    
    /// 尝试静默刷新Cookie（最多3次）
    private func attemptSilentRefresh() async {
        print("[AuthenticationStateManager] 🚀 开始静默刷新Cookie流程")
        print("[AuthenticationStateManager] 📊 当前状态: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired), cookieExpiredShown=\(cookieExpiredShown)")
        
        var attempt = 0
        let maxAttempts = 3
        var success = false
        
        while attempt < maxAttempts && !success {
            attempt += 1
            print("[AuthenticationStateManager] 🔄 静默刷新尝试 \(attempt)/\(maxAttempts)")
            
            do {
                print("[AuthenticationStateManager] 📡 调用MiNoteService.refreshCookie()...")
                // 尝试刷新Cookie
                let refreshSuccess = try await MiNoteService.shared.refreshCookie()
                print("[AuthenticationStateManager] 📡 refreshCookie()返回: \(refreshSuccess)")
                
                if refreshSuccess {
                    print("[AuthenticationStateManager] ✅ 静默刷新成功")
                    success = true
                    
                    // 恢复在线状态
                    await MainActor.run {
                        print("[AuthenticationStateManager] 🔄 恢复在线状态前检查: hasValidCookie=\(MiNoteService.shared.hasValidCookie())")
                        isCookieExpired = false
                        isOnline = true
                        cookieExpiredShown = false
                        showCookieExpiredAlert = false
                        print("[AuthenticationStateManager] ✅ 状态已更新: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired)")
                    }
                    
                    // 通知ViewModel处理待同步操作
                    // 注意：NotesViewModel 没有 shared 实例，这里需要其他方式通知
                    // 暂时注释掉，因为静默刷新成功后，用户操作时会自动触发同步
                    // await NotesViewModel.shared?.processPendingOperations()
                    break
                } else {
                    print("[AuthenticationStateManager] ⚠️ refreshCookie()返回false，但未抛出错误")
                }
            } catch {
                print("[AuthenticationStateManager] ❌ 静默刷新失败 (尝试 \(attempt)): \(error)")
            }
            
            // 如果不是最后一次尝试，等待一段时间再重试
            if attempt < maxAttempts {
                let delaySeconds = TimeInterval(attempt * 5) // 指数退避：5, 10, 15秒
                print("[AuthenticationStateManager] ⏳ 等待 \(delaySeconds) 秒后重试...")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
        
        if !success {
            print("[AuthenticationStateManager] ❌ 所有静默刷新尝试都失败，显示弹窗")
            await MainActor.run {
                showCookieExpiredAlert = true
                isCookieExpired = true
                isOnline = false
                print("[AuthenticationStateManager] 🚨 显示弹窗，状态设置为离线")
            }
        } else {
            print("[AuthenticationStateManager] 🎉 静默刷新流程完成，成功恢复在线状态")
        }
    }
    
    /// 静默处理Cookie失效（由ContentView调用）
    func handleCookieExpiredSilently() async {
        print("[AuthenticationStateManager] 静默处理Cookie失效")
        await attemptSilentRefresh()
    }
    
    // MARK: - 公共方法
    
    /// 恢复在线状态
    /// 
    /// 当Cookie恢复有效时调用此方法
    func restoreOnlineStatus() {
        guard service.hasValidCookie() else {
            print("[AuthenticationStateManager] Cookie仍然无效，不能恢复在线状态")
            return
        }
        
        print("[AuthenticationStateManager] 恢复在线状态")
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false  // 清除离线模式标志
        showCookieExpiredAlert = false  // 清除弹窗状态
        
        // 重新计算在线状态（需要网络和Cookie都有效）
        let networkOnline = networkMonitor.isOnline
        isOnline = networkOnline && service.hasValidCookie()
        
        if isOnline {
            print("[AuthenticationStateManager] ✅ 已恢复在线状态")
        }
    }
    
    /// 处理Cookie失效弹窗的"刷新Cookie"选项
    func handleCookieExpiredRefresh() {
        print("[AuthenticationStateManager] 用户选择刷新Cookie")
        shouldStayOffline = false
        showCookieRefreshView = true
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
        // 恢复在线状态
        restoreOnlineStatus()
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
        
        // 通知ViewModel执行静默刷新
        NotificationCenter.default.post(name: Notification.Name("performSilentCookieRefresh"), object: nil)
        
        // 等待一段时间让静默刷新完成（10秒）
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        
        // 检查刷新结果
        let hasValidCookie = service.hasValidCookie()
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        await MainActor.run {
            if hasValidCookie {
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
}
