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
    
    @State private var isLoading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isCookieRefreshed: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
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
        
        // 清除cookie失效状态
        viewModel.isCookieExpired = false
        viewModel.cookieExpiredShown = false
        
        // 在线状态会在 setupNetworkMonitoring 中自动更新（通过定时器检查）
        // 这里只需要清除cookie失效状态，在线状态会自动计算
        
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
/// 参考 Obsidian 插件的实现：
/// 1. 加载 https://i.mi.com
/// 2. 使用 WKURLSchemeHandler 或 WKNavigationDelegate 监听请求
/// 3. 当检测到 https://i.mi.com/status/lite/profile?ts=* 的请求时，从请求头提取Cookie
struct CookieRefreshWebView: NSViewRepresentable {
    let onCookieExtracted: (String) -> Void
    @Binding var isLoading: Bool
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 设置自定义用户代理，模仿Chrome浏览器
        configuration.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        
        // 注意：WKURLSchemeHandler 不能拦截 https 协议，只能拦截自定义协议
        // 因此我们使用 WKNavigationDelegate 的 decidePolicyFor 方法来监听请求头
        // 不需要设置 URLSchemeHandler
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // 配置WebView
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
        private var hasNavigatedToProfile = false
        
        init(_ parent: CookieRefreshWebView) {
            self.parent = parent
            print("[CookieRefreshWebView] Coordinator初始化")
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("[CookieRefreshWebView] 开始加载: \(webView.url?.absoluteString ?? "未知URL")")
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let currentURL = webView.url
            print("[CookieRefreshWebView] 导航完成: \(currentURL?.absoluteString ?? "未知URL")")
            
            // 如果已经访问过profile页面，不再重复访问
            if hasNavigatedToProfile {
                return
            }
            
            // 检查是否是主页加载完成
            if let urlString = currentURL?.absoluteString,
               urlString.contains("i.mi.com") && !urlString.contains("status/lite/profile") {
                print("[CookieRefreshWebView] 主页加载完成，准备访问 profile 页面")
                // 等待一下让页面完全加载
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if let profileURL = URL(string: "https://i.mi.com/status/lite/profile?ts=\(Int(Date().timeIntervalSince1970 * 1000))") {
                        print("[CookieRefreshWebView] 访问 profile 页面: \(profileURL.absoluteString)")
                        self.hasNavigatedToProfile = true
                        webView.load(URLRequest(url: profileURL))
                    }
                }
            }
            
            // 如果是 profile 页面加载完成，从cookie store获取cookie
            if let urlString = currentURL?.absoluteString,
               urlString.contains("i.mi.com/status/lite/profile") {
                print("[CookieRefreshWebView] Profile 页面加载完成，获取 Cookie...")
                
                // 从 WKWebView 的 cookie store 获取所有 cookie
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    print("[CookieRefreshWebView] 从 WKWebView 获取到 \(cookies.count) 个 cookie")
                    
                    // 将所有 cookie 复制到 URLSession 的 cookie 存储
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
                        
                        // 创建一个自定义的 URLSessionConfiguration，使用我们的 cookie store
                        let config = URLSessionConfiguration.default
                        config.httpCookieStorage = cookieStore
                        config.httpShouldSetCookies = true
                        let session = URLSession(configuration: config)
                        
                        // 发送请求，URLSession 会自动添加 Cookie 头
                        let task = session.dataTask(with: request) { data, response, error in
                            // 从 cookie store 获取所有相关的 cookie（URLSession 会自动过滤）
                            let relevantCookies = cookieStore.cookies(for: profileURL) ?? []
                            
                            // 构建完整的 Cookie 字符串（按照浏览器发送的顺序）
                            // 参考 Obsidian 插件：直接使用浏览器组装的格式
                            let cookieString = relevantCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                            
                            print("[CookieRefreshWebView] 构建的 Cookie 字符串（前300字符）: \(String(cookieString.prefix(300)))...")
                            print("[CookieRefreshWebView] 包含 \(relevantCookies.count) 个 cookie")
                            
                            // 验证cookie是否包含必要的字段
                            let hasServiceToken = relevantCookies.contains { $0.name == "serviceToken" }
                            let hasUserId = relevantCookies.contains { $0.name == "userId" }
                            
                            if hasServiceToken && hasUserId && !cookieString.isEmpty {
                                DispatchQueue.main.async {
                                    self.parent.isLoading = false
                                    self.parent.onCookieExtracted(cookieString)
                                }
                            } else {
                                print("[CookieRefreshWebView] Cookie验证失败: hasServiceToken=\(hasServiceToken), hasUserId=\(hasUserId)")
                                DispatchQueue.main.async {
                                    self.parent.isLoading = false
                                    // 如果cookie无效，重新加载页面
                                    webView.reload()
                                }
                            }
                        }
                        task.resume()
                    }
                }
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
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let requestURL = navigationAction.request.url
            print("[CookieRefreshWebView] 决定导航策略: \(requestURL?.absoluteString ?? "未知URL")")
            
            // 参考 Obsidian 插件：监听 profile 页面的请求头
            if let urlString = requestURL?.absoluteString,
               urlString.contains("i.mi.com/status/lite/profile") {
                // 从请求头中提取Cookie（参考 Obsidian 插件）
                if let cookieHeader = navigationAction.request.value(forHTTPHeaderField: "Cookie") {
                    print("[CookieRefreshWebView] 从请求头提取到Cookie（前300字符）: \(String(cookieHeader.prefix(300)))...")
                    
                    // 验证cookie是否包含必要的字段
                    let hasServiceToken = cookieHeader.contains("serviceToken=")
                    let hasUserId = cookieHeader.contains("userId=")
                    
                    if hasServiceToken && hasUserId && !cookieHeader.isEmpty {
                        DispatchQueue.main.async {
                            self.parent.isLoading = false
                            self.parent.onCookieExtracted(cookieHeader)
                        }
                        decisionHandler(.cancel) // 取消导航，因为我们已经获取到cookie
                        return
                    }
                }
            }
            
            // 允许所有导航
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

