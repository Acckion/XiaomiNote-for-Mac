import Foundation
import Combine

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
    
    // MARK: - 依赖服务
    
    private let service = MiNoteService.shared
    private let networkMonitor = NetworkMonitor.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初始化
    
    init() {
        setupNetworkMonitoring()
        setupCookieExpiredHandler()
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
                    self?.updateOnlineStatus(networkOnline: networkOnline)
                }
            }
            .store(in: &cancellables)
        
        // 监听cookie变化（通过定时检查或通知）
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    let networkOnline = self?.networkMonitor.isOnline ?? false
                    self?.updateOnlineStatus(networkOnline: networkOnline)
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
        
        let hasValidCookie = service.hasValidCookie()
        
        // 如果之前是离线状态（因为Cookie过期），且现在Cookie恢复了，则恢复在线状态
        if isCookieExpired && hasValidCookie {
            restoreOnlineStatus()
            return
        }
        
        // 正常更新在线状态
        // 如果Cookie已恢复有效，且之前用户选择了保持离线，现在清除 shouldStayOffline 标志（用户可能自行重新登录了）
        if hasValidCookie && shouldStayOffline {
            print("[AuthenticationStateManager] Cookie已恢复有效，清除 shouldStayOffline 标志（用户可能自行重新登录了）")
            shouldStayOffline = false
            // 清除cookie失效状态，恢复正常状态更新
            isCookieExpired = false
            cookieExpiredShown = false
        }
        
        isOnline = networkOnline && hasValidCookie
        
        // 如果网络正常但cookie无效，标记为cookie失效
        if networkOnline && !hasValidCookie {
            isCookieExpired = true
        } else if hasValidCookie {
            // Cookie恢复有效时，清除失效状态
            isCookieExpired = false
        }
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
    
    /// 处理Cookie过期
    private func handleCookieExpired() {
        // 立即设置为离线状态，阻止后续请求（从弹窗显示开始就停止重复请求）
        isOnline = false
        isCookieExpired = true
        
        // 只有在未保持离线模式且未显示过弹窗时，才显示弹窗
        if !shouldStayOffline && !cookieExpiredShown {
            // 显示弹窗
            showCookieExpiredAlert = true
            cookieExpiredShown = true
            print("[AuthenticationStateManager] Cookie失效，立即设置为离线状态并显示弹窗提示，后续请求将被阻止")
        } else if shouldStayOffline {
            // 如果用户已选择保持离线模式，不再显示弹窗
            cookieExpiredShown = true
            print("[AuthenticationStateManager] Cookie失效，用户已选择保持离线模式，不再显示弹窗")
        } else {
            // 已经显示过弹窗，只更新状态
            print("[AuthenticationStateManager] Cookie失效，已显示过弹窗，只更新离线状态")
        }
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

