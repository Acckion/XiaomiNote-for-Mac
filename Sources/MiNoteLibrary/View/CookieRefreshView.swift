import SwiftUI
import WebKit

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
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏 - 参考 Obsidian 插件：显示提示信息
            VStack(spacing: 0) {
            HStack {
                Text("刷新Cookie")
                    .font(.headline)
                    .padding(.leading, 16)
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .padding(.trailing, 16)
            }
            .padding(.vertical, 12)
                
                // 参考 Obsidian 插件：添加提示信息
                HStack {
                    Text("点击【使用小米账号登录】以刷新Cookie")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 16)
                    Spacer()
                }
                .padding(.bottom, 8)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
            
            // 使用ZStack确保WebView始终被渲染
            ZStack {
                // 主内容区域
                if !isCookieRefreshed {
                    // WebView容器 - 参考 Obsidian 插件实现
                    CookieRefreshWebView(
                        onCookieExtracted: { cookieString in
                            handleCookieExtracted(cookieString: cookieString)
                        },
                        isLoading: $isLoading
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
                            dismiss()
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
        .frame(width: 960, height: 540)
        .alert("刷新失败", isPresented: $showError) {
            Button("重试") {
                isLoading = true
                isCookieRefreshed = false
            }
            Button("取消", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(errorMessage)
        }
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
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 设置自定义用户代理，模仿Chrome浏览器（参考 Obsidian 插件）
        configuration.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
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
        
        init(_ parent: CookieRefreshWebView) {
            self.parent = parent
            print("[CookieRefreshWebView] Coordinator初始化")
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

