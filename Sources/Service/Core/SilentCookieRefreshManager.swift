import Foundation
import WebKit
import CryptoKit

// MARK: - 刷新类型和数据结构

/// 刷新类型枚举
/// 定义三种不同的刷新类型，每种类型有不同的冷却期策略
public enum RefreshType {
    /// 响应式刷新 - 由 401 错误触发，忽略冷却期，立即执行
    case reactive
    
    /// 手动刷新 - 用户主动触发，重置冷却期，立即执行
    case manual
    
    /// 自动刷新 - 定时检查或应用启动触发，遵守冷却期
    case automatic
}

/// 刷新结果结构
/// 封装刷新操作的完整结果信息
public struct RefreshResult {
    /// 刷新操作是否成功
    let success: Bool
    
    /// Cookie 是否经过验证
    let verified: Bool
    
    /// 刷新类型
    let type: RefreshType
    
    /// 刷新时间戳
    let timestamp: Date
    
    /// 错误信息（如果失败）
    let error: Error?
    
    /// 创建成功的刷新结果
    static func success(type: RefreshType, verified: Bool) -> RefreshResult {
        return RefreshResult(
            success: true,
            verified: verified,
            type: type,
            timestamp: Date(),
            error: nil
        )
    }
    
    /// 创建失败的刷新结果
    static func failure(type: RefreshType, error: Error) -> RefreshResult {
        return RefreshResult(
            success: false,
            verified: false,
            type: type,
            timestamp: Date(),
            error: error
        )
    }
}

/// 冷却期状态结构
/// 管理和查询冷却期相关状态
public struct CooldownState {
    /// 上次刷新时间
    let lastRefreshTime: Date?
    
    /// 冷却期时长（秒）
    let cooldownPeriod: TimeInterval
    
    /// 是否在冷却期内
    var isInCooldown: Bool {
        guard let lastTime = lastRefreshTime else { return false }
        let elapsed = Date().timeIntervalSince(lastTime)
        return elapsed < cooldownPeriod
    }
    
    /// 剩余冷却时间（秒）
    var remainingTime: TimeInterval {
        guard let lastTime = lastRefreshTime else { return 0 }
        let elapsed = Date().timeIntervalSince(lastTime)
        return max(0, cooldownPeriod - elapsed)
    }
    
    /// 创建冷却期状态
    init(lastRefreshTime: Date?, cooldownPeriod: TimeInterval) {
        self.lastRefreshTime = lastRefreshTime
        self.cooldownPeriod = cooldownPeriod
    }
}

/// Cookie 刷新错误类型
public enum CookieRefreshError: Error, LocalizedError {
    /// 已经在刷新中
    case alreadyRefreshing
    
    /// 刷新超时
    case timeout
    
    /// 网络错误
    case networkError(Error)
    
    /// 验证失败
    case verificationFailed
    
    /// 超过最大重试次数
    case maxRetriesExceeded
    
    public var errorDescription: String? {
        switch self {
        case .alreadyRefreshing:
            return "Cookie 刷新已在进行中"
        case .timeout:
            return "Cookie 刷新超时"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .verificationFailed:
            return "Cookie 验证失败"
        case .maxRetriesExceeded:
            return "超过最大重试次数"
        }
    }
}

/// 静默 Cookie 刷新管理器
/// 
/// 在后台使用隐藏的 WKWebView 刷新 Cookie，不显示任何界面。
/// 复用 CookieRefreshWebView 的自动点击登录按钮逻辑。
@MainActor
public final class SilentCookieRefreshManager: NSObject {
    public static let shared = SilentCookieRefreshManager()
    
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Bool, Error>?
    private var _isRefreshing = false
    private var cookieExtracted = false
    private var hasLoadedProfile = false
    
    // MARK: - 冷却期相关属性
    
    /// 上次刷新完成的时间戳
    private var lastRefreshTime: Date?
    
    /// 上次刷新的结果
    private var lastRefreshResult: Bool?
    
    /// 冷却期时长（秒），两次刷新之间的最小间隔
    private let cooldownPeriod: TimeInterval = 60.0
    
    /// 公开的刷新状态属性，供其他组件查询
    public var isRefreshing: Bool {
        return _isRefreshing
    }
    
    /// 获取当前连续失败次数
    /// - Returns: 连续失败次数
    public func getConsecutiveFailures() -> Int {
        return consecutiveFailures
    }
    
    /// 获取上次失败的错误信息
    /// - Returns: 上次失败的错误，如果没有失败则返回 nil
    public func getLastFailureError() -> Error? {
        return lastFailureError
    }
    
    /// 检查是否已达到最大重试次数
    /// - Returns: 如果已达到最大重试次数返回 true
    public func hasReachedMaxRetries() -> Bool {
        return consecutiveFailures >= maxConsecutiveFailures
    }
    
    // MARK: - 刷新类型追踪属性
    
    /// 上次刷新的类型
    /// 用于追踪最近一次刷新操作的类型，帮助决策后续刷新策略
    private var lastRefreshType: RefreshType?
    
    /// 响应式刷新标志
    /// 当前刷新是否为响应式刷新（由 401 错误触发）
    /// 响应式刷新会忽略冷却期限制，立即执行
    private var isReactiveRefresh: Bool = false
    
    // MARK: - 失败计数属性
    
    /// 连续失败次数计数器
    /// 记录连续刷新失败的次数，用于决定是否继续重试
    /// 成功刷新后会重置为 0
    private var consecutiveFailures: Int = 0
    
    /// 最大连续失败次数
    /// 达到此阈值后停止自动重试，提示用户手动刷新
    private let maxConsecutiveFailures: Int = 3
    
    /// 上次失败的错误信息
    /// 记录最近一次刷新失败的详细错误信息，用于诊断和日志
    private var lastFailureError: Error?
    
    /// 上次失败的时间戳
    /// 记录最近一次刷新失败的时间，用于计算重试延迟
    private var lastFailureTime: Date?
    
    private override init() {
        super.init()
    }
    
    // MARK: - 冷却期方法
    
    /// 检查是否在冷却期内
    /// - Returns: 如果在冷却期内返回 true，否则返回 false
    public func isInCooldownPeriod() -> Bool {
        guard let lastTime = lastRefreshTime else { return false }
        let elapsed = Date().timeIntervalSince(lastTime)
        let inCooldown = elapsed < cooldownPeriod
        if inCooldown {
            print("[SilentCookieRefreshManager] 在冷却期内，已过 \(String(format: "%.1f", elapsed)) 秒，需等待 \(String(format: "%.1f", cooldownPeriod - elapsed)) 秒")
        }
        return inCooldown
    }
    
    /// 获取冷却期剩余时间
    /// - Returns: 剩余秒数，如果不在冷却期内返回 0
    public func remainingCooldownTime() -> TimeInterval {
        guard let lastTime = lastRefreshTime else { return 0 }
        let elapsed = Date().timeIntervalSince(lastTime)
        return max(0, cooldownPeriod - elapsed)
    }
    
    /// 重置冷却期（用于手动刷新时）
    public func resetCooldown() {
        print("[SilentCookieRefreshManager] 重置冷却期")
        lastRefreshTime = nil
        lastRefreshResult = nil
    }
    
    /// 检查是否应该跳过刷新
    /// 
    /// 根据刷新类型和冷却期状态决定是否应该跳过本次刷新：
    /// - 响应式刷新（reactive）：忽略冷却期，永不跳过
    /// - 手动刷新（manual）：忽略冷却期，永不跳过
    /// - 自动刷新（automatic）：遵守冷却期，冷却期内跳过
    /// 
    /// - Parameter type: 刷新类型
    /// - Returns: 如果应该跳过刷新返回 true，否则返回 false
    private func shouldSkipRefresh(type: RefreshType) -> Bool {
        switch type {
        case .reactive:
            // 响应式刷新（401 错误触发）：忽略冷却期，立即执行
            print("[SilentCookieRefreshManager] 响应式刷新，忽略冷却期")
            return false
            
        case .manual:
            // 手动刷新（用户触发）：忽略冷却期，立即执行
            print("[SilentCookieRefreshManager] 手动刷新，忽略冷却期")
            return false
            
        case .automatic:
            // 自动刷新（定时检查）：遵守冷却期
            if isInCooldownPeriod() {
                let remaining = remainingCooldownTime()
                print("[SilentCookieRefreshManager] 自动刷新在冷却期内，跳过刷新（剩余 \(String(format: "%.1f", remaining)) 秒）")
                return true
            } else {
                print("[SilentCookieRefreshManager] 自动刷新不在冷却期内，允许执行")
                return false
            }
        }
    }
    
    // MARK: - 失败记录和重试方法
    
    /// 记录刷新失败
    /// 
    /// 当刷新操作失败时调用，记录失败信息并增加失败计数
    /// 
    /// - Parameter error: 失败的错误信息
    private func recordFailure(error: Error) {
        consecutiveFailures += 1
        lastFailureError = error
        lastFailureTime = Date()
        
        print("[SilentCookieRefreshManager] ❌ 记录刷新失败 (第 \(consecutiveFailures) 次): \(error.localizedDescription)")
    }
    
    /// 重置失败计数
    /// 
    /// 当刷新成功时调用，清除所有失败记录
    private func resetFailureCount() {
        if consecutiveFailures > 0 {
            print("[SilentCookieRefreshManager] ✅ 重置失败计数（之前失败 \(consecutiveFailures) 次）")
        }
        consecutiveFailures = 0
        lastFailureError = nil
        lastFailureTime = nil
    }
    
    /// 检查是否应该重试
    /// 
    /// 根据当前失败次数判断是否应该继续重试
    /// 
    /// - Returns: 如果应该重试返回 true，否则返回 false
    private func shouldRetry() -> Bool {
        let should = consecutiveFailures < maxConsecutiveFailures
        if !should {
            print("[SilentCookieRefreshManager] ⛔️ 已达到最大重试次数 (\(maxConsecutiveFailures))，停止重试")
        }
        return should
    }
    
    /// 计算重试延迟时间（指数退避）
    /// 
    /// 使用指数退避算法计算重试延迟：
    /// - 第 1 次失败：延迟 2 秒
    /// - 第 2 次失败：延迟 4 秒
    /// - 第 3 次失败：延迟 8 秒
    /// 
    /// - Returns: 延迟时间（秒）
    private func calculateRetryDelay() -> TimeInterval {
        // 指数退避：2^n 秒，其中 n 是失败次数
        let baseDelay: TimeInterval = 2.0
        let delay = baseDelay * pow(2.0, Double(consecutiveFailures - 1))
        
        print("[SilentCookieRefreshManager] ⏱️ 计算重试延迟: \(String(format: "%.1f", delay)) 秒（失败次数: \(consecutiveFailures)）")
        
        return delay
    }
    
    /// 执行延迟重试
    /// 
    /// 在延迟后自动重试刷新操作
    /// 
    /// - Parameter type: 刷新类型
    /// - Returns: 重试是否成功
    private func retryAfterDelay(type: RefreshType) async throws -> Bool {
        // 检查是否应该重试
        guard shouldRetry() else {
            print("[SilentCookieRefreshManager] ⛔️ 达到最大重试次数，停止重试并通知用户")
            
            // 发送通知，告知达到最大重试次数，需要用户手动刷新
            NotificationCenter.default.post(
                name: NSNotification.Name("CookieRefreshMaxRetriesExceeded"),
                object: nil,
                userInfo: [
                    "consecutiveFailures": consecutiveFailures,
                    "maxRetries": maxConsecutiveFailures,
                    "lastError": lastFailureError?.localizedDescription ?? "未知错误"
                ]
            )
            
            throw CookieRefreshError.maxRetriesExceeded
        }
        
        // 计算延迟时间
        let delay = calculateRetryDelay()
        
        print("[SilentCookieRefreshManager] 🔄 将在 \(String(format: "%.1f", delay)) 秒后重试...")
        
        // 延迟执行
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        print("[SilentCookieRefreshManager] 🔄 开始重试刷新（第 \(consecutiveFailures + 1) 次尝试）")
        
        // 递归调用 refresh，但不增加失败计数（因为这是重试）
        return try await performRefresh(type: type)
    }
    
    // MARK: - Cookie 同步验证方法
    
    /// 从 Cookie 数组中提取 serviceToken
    /// - Parameter cookies: Cookie 数组
    /// - Returns: serviceToken 值，如果不存在返回空字符串
    private func extractServiceToken(from cookies: [HTTPCookie]) -> String {
        for cookie in cookies {
            if cookie.name == "serviceToken" {
                return cookie.value
            }
        }
        return ""
    }
    
    /// 从 HTTPCookieStorage 中提取 serviceToken
    /// - Returns: serviceToken 值，如果不存在返回空字符串
    private func extractServiceTokenFromHTTPStorage() -> String {
        guard let cookies = HTTPCookieStorage.shared.cookies else { return "" }
        for cookie in cookies {
            if cookie.name == "serviceToken" {
                return cookie.value
            }
        }
        return ""
    }
    
    /// 同步 Cookie 到 HTTPCookieStorage 并验证一致性
    /// - Parameter cookies: 从 WKWebView 提取的 Cookie 数组
    /// - Returns: 同步是否成功（包括验证 serviceToken 一致性）
    private func synchronizeCookiesAndVerify(cookies: [HTTPCookie]) -> Bool {
        print("[SilentCookieRefreshManager] 🔄 开始同步 Cookie 到 HTTPCookieStorage")
        
        // 获取 WKWebView 中的 serviceToken
        let webViewServiceToken = extractServiceToken(from: cookies)
        
        if webViewServiceToken.isEmpty {
            print("[SilentCookieRefreshManager] ❌ WKWebView 中未找到 serviceToken")
            return false
        }
        
        // 同步到 HTTPCookieStorage
        let cookieStore = HTTPCookieStorage.shared
        cookieStore.cookieAcceptPolicy = .always
        
        // 清除旧的 cookie
        if let oldCookies = cookieStore.cookies {
            for oldCookie in oldCookies {
                cookieStore.deleteCookie(oldCookie)
            }
        }
        
        // 添加新的 cookie
        for cookie in cookies {
            cookieStore.setCookie(cookie)
        }
        
        // 验证 serviceToken 一致性
        let httpStorageServiceToken = extractServiceTokenFromHTTPStorage()
        
        let isConsistent = webViewServiceToken == httpStorageServiceToken && !webViewServiceToken.isEmpty
        
        if isConsistent {
            print("[SilentCookieRefreshManager] ✅ Cookie 同步成功，serviceToken 一致性验证通过")
        } else {
            print("[SilentCookieRefreshManager] ❌ Cookie 同步失败: WKWebView serviceToken=\(webViewServiceToken.prefix(20))..., HTTPStorage serviceToken=\(httpStorageServiceToken.prefix(20))...")
        }
        
        return isConsistent
    }
    
    /// 执行静默 Cookie 刷新
    /// 
    /// 根据刷新类型决定是否执行刷新操作：
    /// - 响应式刷新（reactive）：忽略冷却期，立即执行
    /// - 手动刷新（manual）：忽略冷却期，立即执行
    /// - 自动刷新（automatic）：遵守冷却期，冷却期内返回缓存结果
    /// 
    /// - Parameter type: 刷新类型，默认为自动刷新
    /// - Returns: 是否成功刷新
    public func refresh(type: RefreshType = .automatic) async throws -> Bool {
        // 记录刷新类型
        print("[SilentCookieRefreshManager] 🔄 收到刷新请求，类型: \(type)")
        
        // 检查是否应该跳过刷新
        if shouldSkipRefresh(type: type) {
            // 冷却期内的自动刷新，返回上次结果
            print("[SilentCookieRefreshManager] ⏳ 跳过刷新，返回上次结果: \(lastRefreshResult ?? false)")
            return lastRefreshResult ?? false
        }
        
        // 防重入检查：确保同一时间只有一个刷新操作在执行
        guard !_isRefreshing else {
            print("[SilentCookieRefreshManager] ⚠️ 刷新正在进行中，拒绝新请求")
            throw CookieRefreshError.alreadyRefreshing
        }
        
        // 手动刷新时重置冷却期
        if type == .manual {
            resetCooldown()
        }
        
        do {
            // 执行刷新
            let result = try await performRefresh(type: type)
            
            // 刷新成功：重置失败计数
            resetFailureCount()
            
            return result
        } catch {
            // 刷新失败：记录失败信息
            recordFailure(error: error)
            
            // 判断是否应该重试
            if shouldRetry() {
                print("[SilentCookieRefreshManager] 🔄 刷新失败，准备重试...")
                
                do {
                    // 延迟重试
                    let retryResult = try await retryAfterDelay(type: type)
                    
                    // 重试成功：重置失败计数
                    resetFailureCount()
                    
                    return retryResult
                } catch {
                    // 重试也失败了
                    print("[SilentCookieRefreshManager] ❌ 重试失败: \(error.localizedDescription)")
                    throw error
                }
            } else {
                // 不应该重试（已达到最大重试次数）
                print("[SilentCookieRefreshManager] ⛔️ 达到最大重试次数，停止重试并通知用户")
                
                // 发送通知，告知达到最大重试次数，需要用户手动刷新
                NotificationCenter.default.post(
                    name: NSNotification.Name("CookieRefreshMaxRetriesExceeded"),
                    object: nil,
                    userInfo: [
                        "consecutiveFailures": consecutiveFailures,
                        "maxRetries": maxConsecutiveFailures,
                        "lastError": lastFailureError?.localizedDescription ?? "未知错误"
                    ]
                )
                
                throw CookieRefreshError.maxRetriesExceeded
            }
        }
    }
    
    /// 执行实际的刷新操作
    /// 
    /// 这是实际执行刷新的内部方法，由 refresh() 和 retryAfterDelay() 调用
    /// 
    /// - Parameter type: 刷新类型
    /// - Returns: 是否成功刷新
    private func performRefresh(type: RefreshType) async throws -> Bool {
        // 设置刷新中标志，防止并发执行
        _isRefreshing = true
        cookieExtracted = false
        hasLoadedProfile = false
        lastRefreshType = type
        
        print("[SilentCookieRefreshManager] 🚀 开始静默 Cookie 刷新（类型: \(type)）")
        
        do {
            let result = try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.startRefresh()
                
                // 设置超时：30秒
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30秒
                    // 超时检查：如果仍在刷新中，则触发超时错误
                    if self._isRefreshing {
                        print("[SilentCookieRefreshManager] ⏰ 刷新超时（30秒），清除刷新标志")
                        self.completeWithError(CookieRefreshError.timeout)
                    }
                }
            }
            
            // 刷新成功：记录完成时间和结果
            lastRefreshTime = Date()
            lastRefreshResult = result
            print("[SilentCookieRefreshManager] 📝 记录刷新结果: \(result)，时间: \(lastRefreshTime!)，类型: \(type)")
            
            return result
        } catch {
            // 刷新失败：记录时间和结果，确保标志已清除
            lastRefreshTime = Date()
            lastRefreshResult = false
            print("[SilentCookieRefreshManager] 📝 记录刷新失败，时间: \(lastRefreshTime!)，类型: \(type)")
            
            // 确保刷新标志已被清除（防御性编程）
            if _isRefreshing {
                print("[SilentCookieRefreshManager] ⚠️ 检测到刷新标志未清除，强制清除")
                _isRefreshing = false
            }
            
            throw error
        }
    }
    
    /// 清理资源
    /// 
    /// 在刷新完成（成功或失败）时调用，清除刷新中标志并释放资源
    private func cleanup() {
        print("[SilentCookieRefreshManager] 🧹 清理资源，清除刷新中标志")
        
        // 清除刷新中标志，允许后续刷新请求
        _isRefreshing = false
        
        // 清理 webView，避免内存泄漏
        webView?.stopLoading()
        webView = nil
        continuation = nil
    }
    
    private func startRefresh() {
        // 必须在主线程创建 WKWebView
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView?.navigationDelegate = self
        webView?.isHidden = true // 隐藏 WebView
        
        // 加载主页
        var request = URLRequest(url: URL(string: "https://i.mi.com")!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        
        print("[SilentCookieRefreshManager] 📡 加载主页: https://i.mi.com")
        webView?.load(request)
    }
    
    private func autoClickLoginButton() {
        guard let webView = webView else { return }
        
        print("[SilentCookieRefreshManager] 🤖 自动点击登录按钮")
        
        let javascript = """
        // 方法1：通过class选择器查找按钮
        function clickLoginButtonByClass() {
            const loginButton = document.querySelector('.miui-btn.miui-btn-primary.miui-darkmode-support.login-btn-hdPJi');
            if (loginButton) {
                console.log('通过class找到登录按钮，点击它');
                loginButton.click();
                return true;
            }
            return false;
        }
        
        // 方法2：通过文本内容查找按钮
        function clickLoginButtonByText() {
            const buttons = document.querySelectorAll('button');
            for (const button of buttons) {
                if (button.textContent.includes('使用小米账号登录')) {
                    console.log('通过文本找到登录按钮，点击它');
                    button.click();
                    return true;
                }
            }
            return false;
        }
        
        // 方法3：通过包含"登录"文本的按钮
        function clickLoginButtonByLoginText() {
            const buttons = document.querySelectorAll('button');
            for (const button of buttons) {
                if (button.textContent.includes('登录')) {
                    console.log('通过"登录"文本找到按钮，点击它');
                    button.click();
                    return true;
                }
            }
            return false;
        }
        
        // 方法4：通过包含"小米账号"文本的按钮
        function clickLoginButtonByMiAccountText() {
            const buttons = document.querySelectorAll('button');
            for (const button of buttons) {
                if (button.textContent.includes('小米账号')) {
                    console.log('通过"小米账号"文本找到按钮，点击它');
                    button.click();
                    return true;
                }
            }
            return false;
        }
        
        // 执行所有方法
        (function() {
            let clicked = false;
            clicked = clickLoginButtonByClass();
            if (!clicked) clicked = clickLoginButtonByText();
            if (!clicked) clicked = clickLoginButtonByLoginText();
            if (!clicked) clicked = clickLoginButtonByMiAccountText();
            
            if (clicked) {
                console.log('✅ 自动点击登录按钮成功');
                return 'success';
            } else {
                console.log('❌ 未找到登录按钮');
                // 输出所有按钮信息用于调试
                const buttons = document.querySelectorAll('button');
                console.log('页面上的按钮数量:', buttons.length);
                buttons.forEach((button, index) => {
                    console.log(`按钮 ${index}:`, button.outerHTML);
                });
                return 'not_found';
            }
        })();
        """
        
        webView.evaluateJavaScript(javascript) { result, error in
            if let error = error {
                print("[SilentCookieRefreshManager] 执行 JavaScript 失败: \(error)")
            } else if let result = result as? String {
                print("[SilentCookieRefreshManager] JavaScript 执行结果: \(result)")
            }
        }
    }
    
    private func extractCookieFromWebView() {
        guard let webView = webView, !cookieExtracted else { return }
        
        print("[SilentCookieRefreshManager] 🔍 从 WebView 提取 Cookie")
        
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { (cookies: [HTTPCookie]) in
            Task { @MainActor in
                guard !self.cookieExtracted else { return }
                
                print("[SilentCookieRefreshManager] 从 WKWebView 获取到 \(cookies.count) 个 cookie")
                
                // 构建完整的 Cookie 字符串
                let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                
                print("[SilentCookieRefreshManager] 构建的 Cookie 字符串（前300字符）: \(String(cookieString.prefix(300)))...")
                
                // 验证 cookie 是否有效
                let hasServiceToken = cookieString.contains("serviceToken=")
                let hasUserId = cookieString.contains("userId=")
                
                if hasServiceToken && hasUserId && !cookieString.isEmpty {
                    // 使用新的同步验证方法
                    let syncSuccess = self.synchronizeCookiesAndVerify(cookies: cookies)
                    
                    if syncSuccess {
                        print("[SilentCookieRefreshManager] ✅ Cookie 验证通过，同步成功")
                        self.cookieExtracted = true
                        
                        // 更新 MiNoteService 的 cookie
                        MiNoteService.shared.setCookie(cookieString)
                        
                        // 发送通知，告知Cookie已刷新成功
                        NotificationCenter.default.post(
                            name: NSNotification.Name("CookieRefreshedSuccessfully"),
                            object: nil,
                            userInfo: ["cookieString": cookieString]
                        )
                        
                        // 完成刷新
                        self.continuation?.resume(returning: true)
                        self.cleanup()
                    } else {
                        print("[SilentCookieRefreshManager] ❌ Cookie 同步验证失败，刷新失败")
                        self.cookieExtracted = true // 防止重复尝试
                        self.continuation?.resume(returning: false)
                        self.cleanup()
                    }
                } else {
                    print("[SilentCookieRefreshManager] ⚠️ Cookie 验证失败: hasServiceToken=\(hasServiceToken), hasUserId=\(hasUserId), cookieString长度=\(cookieString.count)")
                    // 继续等待或重试
                }
            }
        }
    }
    
    private func completeWithError(_ error: Error) {
        print("[SilentCookieRefreshManager] ❌ 刷新失败: \(error)")
        continuation?.resume(throwing: error)
        cleanup()
    }
    
    private func completeWithSuccess() {
        print("[SilentCookieRefreshManager] ✅ 刷新成功")
        continuation?.resume(returning: true)
        cleanup()
    }
}

// MARK: - WKNavigationDelegate
extension SilentCookieRefreshManager: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("[SilentCookieRefreshManager] 开始加载")
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let currentURL = webView.url?.absoluteString ?? "未知URL"
        print("[SilentCookieRefreshManager] 导航完成: \(currentURL)")
        
        // 如果已经提取过 cookie，不再处理
        if cookieExtracted {
            return
        }
        
        // 如果是 profile 页面加载完成，提取 Cookie
        if currentURL.contains("i.mi.com/status/lite/profile") {
            print("[SilentCookieRefreshManager] Profile 页面加载完成，提取 Cookie...")
            hasLoadedProfile = true
            extractCookieFromWebView()
            return
        }
        
        // 主页加载完成后，检查是否已经登录
        if currentURL.contains("i.mi.com") && !currentURL.contains("status/lite/profile") && !hasLoadedProfile {
            print("[SilentCookieRefreshManager] 主页加载完成，检查是否已经登录")
            
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { (cookies: [HTTPCookie]) in
                Task { @MainActor in
                    guard !self.cookieExtracted else { return }
                    
                    print("[SilentCookieRefreshManager] 检查登录状态，获取到 \(cookies.count) 个 cookie")
                    
                    let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    let hasServiceToken = cookieString.contains("serviceToken=")
                    let hasUserId = cookieString.contains("userId=")
                    
                    if hasServiceToken && hasUserId && !cookieString.isEmpty {
                        // 已经登录，直接导航到 profile 页面获取完整 cookie
                        print("[SilentCookieRefreshManager] ✅ 检测到已登录，直接进入获取cookie流程")
                        if let profileURL = URL(string: "https://i.mi.com/status/lite/profile?ts=\(Int(Date().timeIntervalSince1970 * 1000))") {
                            print("[SilentCookieRefreshManager] 访问 profile 页面: \(profileURL.absoluteString)")
                            webView.load(URLRequest(url: profileURL))
                        }
                    } else {
                        // 未登录，自动点击登录按钮
                        print("[SilentCookieRefreshManager] ⚠️ 未检测到有效登录cookie，自动点击登录按钮")
                        // 延迟一段时间后自动点击
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.autoClickLoginButton()
                        }
                    }
                }
            }
            return
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[SilentCookieRefreshManager] 导航失败: \(error.localizedDescription)")
        completeWithError(error)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[SilentCookieRefreshManager] 加载失败: \(error.localizedDescription)")
        completeWithError(error)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let requestURL = navigationAction.request.url
        let urlString = requestURL?.absoluteString ?? ""
        
        // 检测 profile 请求
        if urlString.contains("i.mi.com/status/lite/profile") && urlString.contains("ts=") {
            print("[SilentCookieRefreshManager] 检测到 profile 请求")
        }
        
        decisionHandler(.allow)
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        // 检查响应头中是否有新的 Cookie
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let newCookie = httpResponse.allHeaderFields["Set-Cookie"] as? String {
            print("[SilentCookieRefreshManager] 🍪 从响应头获取到新Cookie")
            MiNoteService.shared.setCookie(newCookie)
            cookieExtracted = true
            
            // 发送通知，告知Cookie已刷新成功
            NotificationCenter.default.post(
                name: NSNotification.Name("CookieRefreshedSuccessfully"),
                object: nil,
                userInfo: ["cookieString": newCookie]
            )
            
            completeWithSuccess()
        }
        
        decisionHandler(.allow)
    }
}
