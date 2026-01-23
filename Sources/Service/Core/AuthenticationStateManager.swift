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
    
    // MARK: - 静默刷新状态属性
    
    /// 是否正在刷新Cookie
    /// 
    /// 当静默刷新正在进行时为 true，用于 UI 显示刷新状态指示
    @Published var isRefreshingCookie: Bool = false
    
    /// 刷新状态消息
    /// 
    /// 显示当前刷新操作的状态信息，如"正在刷新登录状态..."
    @Published var refreshStatusMessage: String = ""
    
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
        
        // ScheduledTaskManager 现在由 AppStateManager 在应用启动时启动
        // 不再在这里启动，避免循环依赖和启动时机问题
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
        // 注意：UserDefaults.standard.bool(forKey:) 在键不存在时返回 false
        // 所以我们需要检查键是否存在，如果不存在则使用默认值 true
        let silentRefreshEnabled: Bool
        if UserDefaults.standard.object(forKey: "silentRefreshOnFailure") != nil {
            silentRefreshEnabled = UserDefaults.standard.bool(forKey: "silentRefreshOnFailure")
        } else {
            silentRefreshEnabled = true // 默认启用静默刷新
        }
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
    
    /// 尝试静默刷新Cookie（带状态更新）
    /// 
    /// 增强版本：在刷新过程中更新状态属性，显示"正在刷新登录状态"提示
    /// 成功后自动恢复在线状态并继续之前的操作
    /// 
    /// - Returns: 刷新是否成功
    func attemptSilentRefreshWithStatus() async -> Bool {
        // 防重入检查
        guard !isInRefreshCycle else {
            print("[AuthenticationStateManager] ⚠️ 已在刷新周期中，跳过重复请求")
            return false
        }
        
        // 检查是否已达到最大失败次数
        guard consecutiveFailures < maxConsecutiveFailures else {
            print("[AuthenticationStateManager] ⚠️ 已达到最大失败次数 (\(maxConsecutiveFailures))，不再自动刷新")
            showCookieExpiredAlert = true
            return false
        }
        
        isInRefreshCycle = true
        
        // 更新刷新状态
        isRefreshingCookie = true
        refreshStatusMessage = "正在刷新登录状态..."
        
        print("[AuthenticationStateManager] 🚀 开始静默刷新Cookie流程（带状态更新）")
        print("[AuthenticationStateManager] 📊 当前状态: isOnline=\(isOnline), isCookieExpired=\(isCookieExpired), consecutiveFailures=\(consecutiveFailures)")
        
        // 暂停定时检查任务，避免刷新期间触发检查
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")
        
        defer {
            isInRefreshCycle = false
            isRefreshingCookie = false
            refreshStatusMessage = ""
            // 恢复定时检查任务（带 30 秒宽限期）
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }
        
        do {
            refreshStatusMessage = "正在连接服务器..."
            print("[AuthenticationStateManager] 📡 调用MiNoteService.refreshCookie()...")
            
            // 尝试刷新Cookie
            let refreshSuccess = try await MiNoteService.shared.refreshCookie()
            print("[AuthenticationStateManager] 📡 refreshCookie()返回: \(refreshSuccess)")
            
            if refreshSuccess {
                refreshStatusMessage = "正在验证Cookie有效性..."
                print("[AuthenticationStateManager] ✅ 静默刷新成功，开始验证Cookie有效性...")
                
                // 关键修复：同步等待验证完成
                let isValid = try await MiNoteService.shared.checkCookieValidity()
                print("[AuthenticationStateManager] 📡 checkCookieValidity()返回: \(isValid)")
                
                if isValid {
                    // Cookie 确实有效，恢复在线状态
                    consecutiveFailures = 0
                    refreshStatusMessage = "登录状态已恢复"
                    restoreOnlineStatusAfterValidation(isValid: true)
                    print("[AuthenticationStateManager] ✅ Cookie 刷新并验证成功")
                    return true
                } else {
                    // 刷新成功但验证失败
                    refreshStatusMessage = "验证失败，请手动刷新"
                    handleRefreshSuccessButValidationFailed()
                    return false
                }
            } else {
                // 刷新返回 false
                refreshStatusMessage = "刷新失败，请手动刷新"
                handleRefreshFailure()
                return false
            }
        } catch {
            print("[AuthenticationStateManager] ❌ 静默刷新失败: \(error)")
            refreshStatusMessage = "刷新失败: \(error.localizedDescription)"
            handleRefreshFailure()
            return false
        }
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
        
        // 手动刷新时重置计数器和冷却期（异步执行）
        Task {
            await handleManualRefresh()
        }
    }
    
    /// 处理响应式刷新（401 错误触发）
    /// 
    /// 当检测到 Cookie 失效（401 错误）时调用，忽略冷却期立即执行刷新
    /// 刷新成功后验证 Cookie 有效性，确保真正恢复在线状态
    /// 
    /// - Returns: 刷新是否成功
    func handleReactiveRefresh() async -> Bool {
        print("[AuthenticationStateManager] 🚨 响应式刷新：检测到 401 错误，立即刷新")
        
        // 防重入检查
        guard !isInRefreshCycle else {
            print("[AuthenticationStateManager] ⚠️ 已在刷新周期中，跳过响应式刷新")
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
            // 恢复定时检查任务（带 30 秒宽限期）
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }
        
        do {
            print("[AuthenticationStateManager] 📡 调用 SilentCookieRefreshManager.refresh(type: .reactive)")
            
            // 调用响应式刷新，忽略冷却期
            let refreshSuccess = try await SilentCookieRefreshManager.shared.refresh(type: .reactive)
            
            print("[AuthenticationStateManager] 📡 响应式刷新返回: \(refreshSuccess)")
            
            if refreshSuccess {
                refreshStatusMessage = "正在验证 Cookie 有效性..."
                print("[AuthenticationStateManager] ✅ 响应式刷新成功，开始验证 Cookie 有效性...")
                
                // 验证刷新结果
                let isValid = try await MiNoteService.shared.checkCookieValidity()
                print("[AuthenticationStateManager] 📡 checkCookieValidity() 返回: \(isValid)")
                
                if isValid {
                    // Cookie 确实有效，恢复在线状态
                    consecutiveFailures = 0
                    refreshStatusMessage = "登录状态已恢复"
                    restoreOnlineStatusAfterValidation(isValid: true)
                    print("[AuthenticationStateManager] ✅ 响应式刷新并验证成功")
                    return true
                } else {
                    // 刷新成功但验证失败
                    refreshStatusMessage = "验证失败"
                    handleRefreshSuccessButValidationFailed()
                    return false
                }
            } else {
                // 刷新返回 false
                refreshStatusMessage = "刷新失败"
                handleRefreshFailure()
                return false
            }
        } catch {
            print("[AuthenticationStateManager] ❌ 响应式刷新失败: \(error)")
            refreshStatusMessage = "刷新失败: \(error.localizedDescription)"
            handleRefreshFailure()
            return false
        }
    }
    
    /// 处理手动刷新
    /// 
    /// 当用户手动触发刷新时调用，重置失败计数器和冷却期
    /// 使用手动刷新类型，忽略冷却期限制，立即执行刷新
    /// 
    /// - Returns: 刷新是否成功
    @discardableResult
    func handleManualRefresh() async -> Bool {
        print("[AuthenticationStateManager] 🔄 手动刷新：重置失败计数器和冷却期")
        
        // 防重入检查
        guard !isInRefreshCycle else {
            print("[AuthenticationStateManager] ⚠️ 已在刷新周期中，跳过手动刷新")
            return false
        }
        
        isInRefreshCycle = true
        defer { isInRefreshCycle = false }
        
        // 重置失败计数器
        consecutiveFailures = 0
        
        // 清除弹窗显示标志，允许重新触发刷新流程
        cookieExpiredShown = false
        
        // 更新刷新状态
        isRefreshingCookie = true
        refreshStatusMessage = "正在手动刷新登录状态..."
        
        // 暂停定时检查任务
        ScheduledTaskManager.shared.pauseTask("cookie_validity_check")
        
        defer {
            isRefreshingCookie = false
            refreshStatusMessage = ""
            // 恢复定时检查任务（带 30 秒宽限期）
            ScheduledTaskManager.shared.resumeTask("cookie_validity_check", gracePeriod: 30.0)
        }
        
        do {
            print("[AuthenticationStateManager] 📡 调用 SilentCookieRefreshManager.refresh(type: .manual)")
            
            // 调用手动刷新，重置冷却期并立即执行
            let refreshSuccess = try await SilentCookieRefreshManager.shared.refresh(type: .manual)
            
            print("[AuthenticationStateManager] 📡 手动刷新返回: \(refreshSuccess)")
            
            if refreshSuccess {
                refreshStatusMessage = "正在验证 Cookie 有效性..."
                print("[AuthenticationStateManager] ✅ 手动刷新成功，开始验证 Cookie 有效性...")
                
                // 验证刷新结果
                let isValid = try await MiNoteService.shared.checkCookieValidity()
                print("[AuthenticationStateManager] 📡 checkCookieValidity() 返回: \(isValid)")
                
                if isValid {
                    // Cookie 确实有效，恢复在线状态
                    consecutiveFailures = 0
                    refreshStatusMessage = "登录状态已恢复"
                    restoreOnlineStatusAfterValidation(isValid: true)
                    print("[AuthenticationStateManager] ✅ 手动刷新并验证成功")
                    return true
                } else {
                    // 刷新成功但验证失败
                    refreshStatusMessage = "验证失败"
                    handleRefreshSuccessButValidationFailed()
                    return false
                }
            } else {
                // 刷新返回 false
                refreshStatusMessage = "刷新失败"
                handleRefreshFailure()
                return false
            }
        } catch {
            print("[AuthenticationStateManager] ❌ 手动刷新失败: \(error)")
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
        // 清除cookie失效状态
        isCookieExpired = false
        cookieExpiredShown = false
        shouldStayOffline = false  // 清除离线模式标志
        showCookieExpiredAlert = false  // 清除弹窗状态
        
        // 重置失败计数器
        consecutiveFailures = 0
        
        // 立即更新 ScheduledTaskManager 的 Cookie 有效性状态
        // 这样 restoreOnlineStatus() 才能正确判断
        ScheduledTaskManager.shared.setCookieValid(true)
        
        // 延迟恢复在线状态，确保 Cookie 完全生效
        // 延迟 1.5 秒，给 Cookie 足够的时间在所有网络层生效
        Task { @MainActor in
            print("[AuthenticationStateManager] ⏳ 延迟 1.5 秒后恢复在线状态，确保 Cookie 完全生效")
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5秒
            
            // 恢复在线状态
            self.restoreOnlineStatus()
            
            print("[AuthenticationStateManager] ✅ Cookie刷新完成，状态已更新: isOnline=\(self.isOnline), isCookieExpired=\(self.isCookieExpired)")
        }
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
        
        // 监听达到最大重试次数的通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMaxRetriesExceededNotification(_:)),
            name: NSNotification.Name("CookieRefreshMaxRetriesExceeded"),
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
    
    /// 处理达到最大重试次数通知
    /// 
    /// 当 SilentCookieRefreshManager 达到最大重试次数时调用
    /// 停止自动重试，显示弹窗提示用户手动刷新
    @objc private func handleMaxRetriesExceededNotification(_ notification: Notification) {
        print("[AuthenticationStateManager] ⛔️ 收到达到最大重试次数通知")
        
        // 提取通知信息
        if let userInfo = notification.userInfo {
            let failures = userInfo["consecutiveFailures"] as? Int ?? 0
            let maxRetries = userInfo["maxRetries"] as? Int ?? 0
            let lastError = userInfo["lastError"] as? String ?? "未知错误"
            
            print("[AuthenticationStateManager] 📊 失败次数: \(failures)/\(maxRetries), 最后错误: \(lastError)")
        }
        
        // 更新状态：停止自动重试，显示弹窗
        Task { @MainActor in
            // 清除刷新状态
            self.isRefreshingCookie = false
            self.refreshStatusMessage = ""
            
            // 设置为离线状态
            self.isOnline = false
            self.isCookieExpired = true
            
            // 显示弹窗，提示用户手动刷新
            self.showCookieExpiredAlert = true
            
            print("[AuthenticationStateManager] ⚠️ 已达到最大重试次数，显示手动刷新提示")
        }
    }
}
