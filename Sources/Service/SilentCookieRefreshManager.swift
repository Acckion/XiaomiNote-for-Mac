import Foundation
import WebKit
import CryptoKit

/// 静默 Cookie 刷新管理器
/// 
/// 在后台使用隐藏的 WKWebView 刷新 Cookie，不显示任何界面。
/// 复用 CookieRefreshWebView 的自动点击登录按钮逻辑。
@MainActor
final class SilentCookieRefreshManager: NSObject {
    static let shared = SilentCookieRefreshManager()
    
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Bool, Error>?
    private var isRefreshing = false
    private var cookieExtracted = false
    private var hasLoadedProfile = false
    
    private override init() {
        super.init()
    }
    
    /// 执行静默 Cookie 刷新
    /// - Returns: 是否成功刷新
    func refresh() async throws -> Bool {
        guard !isRefreshing else {
            print("[SilentCookieRefreshManager] 刷新正在进行中，忽略重复请求")
            return false
        }
        
        isRefreshing = true
        cookieExtracted = false
        hasLoadedProfile = false
        
        print("[SilentCookieRefreshManager] 🚀 开始静默 Cookie 刷新")
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.startRefresh()
            
            // 设置超时：30秒
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30秒
                if self.isRefreshing {
                    print("[SilentCookieRefreshManager] ⏰ 刷新超时（30秒）")
                    self.completeWithError(NSError(domain: "SilentCookieRefreshManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "刷新超时"]))
                }
            }
        }
    }
    
    /// 清理资源
    private func cleanup() {
        isRefreshing = false
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
                
                // 复制到 URLSession 的 cookie 存储
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
                
                // 构建完整的 Cookie 字符串
                let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                
                print("[SilentCookieRefreshManager] 构建的 Cookie 字符串（前300字符）: \(String(cookieString.prefix(300)))...")
                
                // 验证 cookie 是否有效
                let hasServiceToken = cookieString.contains("serviceToken=")
                let hasUserId = cookieString.contains("userId=")
                
                if hasServiceToken && hasUserId && !cookieString.isEmpty {
                    print("[SilentCookieRefreshManager] ✅ Cookie 验证通过，提取成功")
                    self.cookieExtracted = true
                    
                    // 更新 MiNoteService 的 cookie
                    MiNoteService.shared.setCookie(cookieString)
                    
                    // 完成刷新
                    self.continuation?.resume(returning: true)
                    self.cleanup()
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
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("[SilentCookieRefreshManager] 开始加载")
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[SilentCookieRefreshManager] 导航失败: \(error.localizedDescription)")
        completeWithError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[SilentCookieRefreshManager] 加载失败: \(error.localizedDescription)")
        completeWithError(error)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let requestURL = navigationAction.request.url
        let urlString = requestURL?.absoluteString ?? ""
        
        // 检测 profile 请求
        if urlString.contains("i.mi.com/status/lite/profile") && urlString.contains("ts=") {
            print("[SilentCookieRefreshManager] 检测到 profile 请求")
        }
        
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        // 检查响应头中是否有新的 Cookie
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let newCookie = httpResponse.allHeaderFields["Set-Cookie"] as? String {
            print("[SilentCookieRefreshManager] 🍪 从响应头获取到新Cookie")
            MiNoteService.shared.setCookie(newCookie)
            cookieExtracted = true
            completeWithSuccess()
        }
        
        decisionHandler(.allow)
    }
}
