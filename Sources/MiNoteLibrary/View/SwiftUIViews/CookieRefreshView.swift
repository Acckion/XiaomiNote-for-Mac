import SwiftUI
import WebKit

// 自动点击登录按钮的通知名称
extension Notification.Name {
    static let autoClickLoginButton = Notification.Name("autoClickLoginButton")
}

/// Cookie刷新视图
/// 
/// 参考 Obsidian 插件的实现：
/// 1. 打开浏览器窗口加载 https://i.mi.com
/// 2. 监听 https://i.mi.com/status/lite/profile?ts=* 的请求头
/// 3. 从请求头的Cookie中提取cookie并保存
struct CookieRefreshView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: NotesViewModel
    
    @State private var isLoading: Bool = true  // 初始状态为加载中，因为页面需要加载
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isCookieRefreshed: Bool = false
    
    // 自定义关闭方法，用于AppKit环境
    private func closeSheet() {
        // 尝试使用dismiss环境变量
        dismiss()
        
        // 如果dismiss无效，尝试通过NSApp关闭窗口
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow,
               let sheetParent = window.sheetParent {
                sheetParent.endSheet(window)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏 - 适配sheet样式
            VStack(spacing: 0) {
                HStack {
                    Text("刷新Cookie")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.leading, 20)
                    
                    Spacer()
                    
                    Button(action: {
                        closeSheet()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding(.trailing, 16)
                    .help("关闭")
                }
                .padding(.vertical, 16)
                
                HStack {
                    Text("点击[使用小米账号登录]以刷新Cookie")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                    Spacer()
                    
                    // 自动点击按钮
                    Button("自动点击登录按钮") {
                        autoClickLoginButton()
                    }
                    .buttonStyle(.bordered)
                    .padding(.trailing, 16)
                    .help("自动点击页面上的'使用小米账号登录'按钮")
                }
                .padding(.bottom, 12)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )
            
            // 使用ZStack确保WebView始终被渲染
            ZStack {
                // 主内容区域
                if !isCookieRefreshed {
                    // WebView容器 - 参考 Obsidian 插件实现
                    CookieRefreshWebView(
                        onCookieExtracted: { cookieString in
                            handleCookieExtracted(cookieString: cookieString)
                        },
                        isLoading: $isLoading,
                        autoClickLoginButton: true // 启用自动点击
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Cookie刷新成功视图
                if isCookieRefreshed {
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                        
                        Text("Cookie刷新成功！")
                            .font(.title)
                            .fontWeight(.semibold)
                        
                        Text("已成功获取新的Cookie，可以正常使用同步功能")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("完成") {
                            closeSheet()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                    .background(Color(NSColor.windowBackgroundColor))
                }
                
                // 加载指示器 - 覆盖在主内容之上
                if isLoading && !isCookieRefreshed {
                    Color(NSColor.windowBackgroundColor)
                        .opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        
                        Text("正在加载页面...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 900, minHeight: 450, idealHeight: 500, maxHeight: 550)
        .padding(.top, 1) // 避免标题栏下边框被裁剪
        .alert("刷新失败", isPresented: $showError) {
            Button("重试") {
                isLoading = true
                isCookieRefreshed = false
            }
            Button("取消", role: .cancel) {
                closeSheet()
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func autoClickLoginButton() {
        // 通知WebView自动点击登录按钮
        NotificationCenter.default.post(name: .autoClickLoginButton, object: nil)
    }
    
    private func handleCookieExtracted(cookieString: String) {
        print("[CookieRefreshView] Cookie提取成功")
        print("[CookieRefreshView] Cookie字符串（前300字符）: \(String(cookieString.prefix(300)))...")
        
        // 更新MiNoteService的cookie
        MiNoteService.shared.setCookie(cookieString)
        
        // 通知 AuthenticationStateManager Cookie刷新完成
        // 这会清除cookie失效状态并恢复在线状态
        viewModel.handleCookieRefreshed()
        
        // 更新UI
        withAnimation {
            isLoading = false
            isCookieRefreshed = true
        }
        
        // 延迟一下再加载数据，确保 cookie 完全生效
        Task {
            // 等待 1 秒，让 cookie 有时间生效
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await viewModel.loadNotesFromCloud()
        }
    }
}

/// Cookie刷新WebView
/// 
/// 参考 Obsidian 插件的实现（minoteRefreshCookieModel.ts）：
/// 1. 加载 https://i.mi.com
/// 2. 监听 https://i.mi.com/status/lite/profile?ts=* 的请求头（使用 onSendHeaders）
/// 3. 从请求头的 Cookie 字段中直接提取 cookie 字符串
/// 
/// 优化点：
/// - 简化逻辑，直接从请求头获取 Cookie（类似 Obsidian 插件的 session.webRequest.onSendHeaders）
/// - 减少不必要的步骤（不需要手动访问 profile 页面，让它自然触发）
/// - 改进错误处理和重试机制
struct CookieRefreshWebView: NSViewRepresentable {
    let onCookieExtracted: (String) -> Void
    @Binding var isLoading: Bool
    var autoClickLoginButton: Bool = false
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 设置自定义用户代理，模仿Chrome浏览器（参考 Obsidian 插件）
        configuration.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // 保存webView引用到Coordinator
        context.coordinator.setWebView(webView)
        
        // 参考 Obsidian 插件：直接加载主页
        var request = URLRequest(url: URL(string: "https://i.mi.com")!)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        
        print("[CookieRefreshWebView] 加载URL: https://i.mi.com")
        webView.load(request)
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: CookieRefreshWebView
        private var cookieExtracted = false  // 防止重复提取
        private var hasLoadedProfile = false  // 标记是否已加载profile页面
        private var retryCount = 0
        private let maxRetries = 3
        private var webView: WKWebView?
        
        init(_ parent: CookieRefreshWebView) {
            self.parent = parent
            super.init()
            print("[CookieRefreshWebView] Coordinator初始化")
            
            // 监听自动点击登录按钮的通知
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAutoClickLoginButton),
                name: .autoClickLoginButton,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        func setWebView(_ webView: WKWebView) {
            self.webView = webView
        }
        
        @objc private func handleAutoClickLoginButton() {
            print("[CookieRefreshWebView] 收到自动点击登录按钮通知")
            autoClickLoginButton()
        }
        
        private func autoClickLoginButton() {
            guard let webView = webView else {
                print("[CookieRefreshWebView] WebView未初始化，无法自动点击")
                return
            }
            
            print("[CookieRefreshWebView] 开始自动点击登录按钮")
            
            // 尝试多种方式查找并点击登录按钮
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
                    print("[CookieRefreshWebView] 执行JavaScript失败: \(error)")
                } else if let result = result as? String {
                    print("[CookieRefreshWebView] JavaScript执行结果: \(result)")
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            let url = webView.url?.absoluteString ?? "未知URL"
            print("[CookieRefreshWebView] 开始加载: \(url)")
            
            // 如果不是 profile 页面，显示加载状态
            if !url.contains("status/lite/profile") {
                DispatchQueue.main.async {
                    self.parent.isLoading = true
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let currentURL = webView.url?.absoluteString ?? "未知URL"
            print("[CookieRefreshWebView] 导航完成: \(currentURL)")
            
            // 如果已经提取过 cookie，不再处理
            if cookieExtracted {
                return
            }
            
            // 如果是 profile 页面加载完成，从 cookie store 获取 Cookie（参考 LoginView 的实现）
            if currentURL.contains("i.mi.com/status/lite/profile") {
                print("[CookieRefreshWebView] Profile 页面加载完成，从 cookie store 获取 Cookie...")
                hasLoadedProfile = true
                
                // 参考 LoginView：使用 URLSession 来获取完整的 Cookie 字符串
                // 从 WKWebView 的 cookie store 获取所有 cookie
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self = self, !self.cookieExtracted else { return }
                    
                    print("[CookieRefreshWebView] 从 WKWebView 获取到 \(cookies.count) 个 cookie")
                    
                    // 参考 LoginView：将所有 cookie 复制到 URLSession 的 cookie 存储
                    let cookieStore = HTTPCookieStorage.shared
                    cookieStore.cookieAcceptPolicy = .always
                    
                    // 清除旧的 cookie，避免冲突
                    if let oldCookies = cookieStore.cookies {
                        for oldCookie in oldCookies {
                            cookieStore.deleteCookie(oldCookie)
                        }
                    }
                    
                    // 添加新的 cookie
                    for cookie in cookies {
                        cookieStore.setCookie(cookie)
                    }
                    
                    // 使用 URLSession 发送请求，URLSession 会自动组装完整的 Cookie 字符串
                    if let profileURL = URL(string: "https://i.mi.com/status/lite/profile?ts=\(Int(Date().timeIntervalSince1970 * 1000))") {
                        var request = URLRequest(url: profileURL)
                        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
                        
                        let config = URLSessionConfiguration.default
                        config.httpCookieStorage = cookieStore
                        config.httpShouldSetCookies = true
                        let session = URLSession(configuration: config)
                        
                        // 发送请求，URLSession 会自动添加 Cookie 头
                        let task = session.dataTask(with: request) { [weak self] data, response, error in
                            guard let self = self, !self.cookieExtracted else { return }
                            
                            // 从 cookie store 获取所有相关的 cookie（URLSession 会自动过滤）
                            let relevantCookies = cookieStore.cookies(for: profileURL) ?? []
                            
                            // 构建完整的 Cookie 字符串（参考 LoginView 的实现）
                            let cookieString = relevantCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                            
                            print("[CookieRefreshWebView] 构建的 Cookie 字符串（前300字符）: \(String(cookieString.prefix(300)))...")
                            print("[CookieRefreshWebView] 包含 \(relevantCookies.count) 个 cookie")
                            
                            // 验证 cookie 是否有效
                            let hasServiceToken = cookieString.contains("serviceToken=")
                            let hasUserId = cookieString.contains("userId=")
                            
                            if hasServiceToken && hasUserId && !cookieString.isEmpty {
                                print("[CookieRefreshWebView] ✅ Cookie 验证通过，提取成功")
                                self.cookieExtracted = true
                                DispatchQueue.main.async {
                                    self.parent.isLoading = false
                                    self.parent.onCookieExtracted(cookieString)
                                }
                            } else {
                                print("[CookieRefreshWebView] ⚠️ Cookie 验证失败: hasServiceToken=\(hasServiceToken), hasUserId=\(hasUserId), cookieString长度=\(cookieString.count)")
                                // Cookie 验证失败，继续等待用户登录
                            }
                        }
                        task.resume()
                    }
                }
                return
            }
            
            // 主页加载完成后，检查是否已经登录
            // 如果已经登录，直接进入获取cookie流程；否则等待用户点击"登录"按钮
            if currentURL.contains("i.mi.com") && !currentURL.contains("status/lite/profile") && !hasLoadedProfile {
                print("[CookieRefreshWebView] 主页加载完成，检查是否已经登录")
                
                // 检查是否已经登录：从 cookie store 获取 cookie，检查是否包含 serviceToken 和 userId
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self = self, !self.cookieExtracted else { return }
                    
                    print("[CookieRefreshWebView] 检查登录状态，获取到 \(cookies.count) 个 cookie")
                    
                    // 检查是否有有效的登录cookie
                    let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    let hasServiceToken = cookieString.contains("serviceToken=")
                    let hasUserId = cookieString.contains("userId=")
                    
                    if hasServiceToken && hasUserId && !cookieString.isEmpty {
                        // 已经登录，直接导航到 profile 页面获取完整 cookie
                        print("[CookieRefreshWebView] ✅ 检测到已登录，直接进入获取cookie流程")
                        DispatchQueue.main.async {
                            self.parent.isLoading = true
                            // 延迟一小段时间，确保页面完全加载
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if let profileURL = URL(string: "https://i.mi.com/status/lite/profile?ts=\(Int(Date().timeIntervalSince1970 * 1000))") {
                                    print("[CookieRefreshWebView] 访问 profile 页面: \(profileURL.absoluteString)")
                                    webView.load(URLRequest(url: profileURL))
                                }
                            }
                        }
                    } else {
                        // 未登录，等待用户点击"登录"按钮
                        print("[CookieRefreshWebView] ⚠️ 未检测到有效登录cookie，等待用户点击登录按钮")
                        DispatchQueue.main.async {
                            self.parent.isLoading = false
                        }
                        
                        // 如果启用了自动点击登录按钮，延迟一段时间后自动点击
                        if self.parent.autoClickLoginButton {
                            print("[CookieRefreshWebView] 启用自动点击登录按钮，延迟2秒后执行")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                self.autoClickLoginButton()
                            }
                        }
                    }
                }
                return
            }
            
            // 其他情况，清除加载状态
            DispatchQueue.main.async {
                self.parent.isLoading = false
                print("[CookieRefreshWebView] 页面加载完成，已清除加载状态")
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("[CookieRefreshWebView] 导航失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("[CookieRefreshWebView] 加载失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        /// 监听所有导航请求，记录 profile 请求用于调试
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let requestURL = navigationAction.request.url
            guard let urlString = requestURL?.absoluteString else {
                decisionHandler(.allow)
                return
            }
            
            // 检测 profile 请求，用于调试日志
            if urlString.contains("i.mi.com/status/lite/profile") && urlString.contains("ts=") {
                print("[CookieRefreshWebView] 检测到 profile 请求: \(urlString)")
                // 允许请求继续，等待 didFinish 回调中从 cookie store 获取 Cookie
            }
            
            // 允许所有导航继续
            decisionHandler(.allow)
        }
    }
}

/// 自定义URLSchemeHandler（当前未使用，保留用于未来可能的扩展）
/// 注意：WKURLSchemeHandler 不能拦截 https 协议，只能拦截自定义协议
/// 因此我们使用 WKNavigationDelegate 的 decidePolicyFor 方法来监听请求头
class CookieSchemeHandler: NSObject, WKURLSchemeHandler {
    let onCookieExtracted: (String) -> Void
    
    init(onCookieExtracted: @escaping (String) -> Void) {
        self.onCookieExtracted = onCookieExtracted
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // 当前未使用，保留用于未来可能的扩展
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // 停止请求处理
    }
}
