import SwiftUI
import WebKit

struct LoginView: View {
    @ObservedObject var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoggedIn: Bool = false
    @State private var isLoading: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
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
            // 使用ZStack确保WebView始终被渲染
            ZStack {
                // 主内容区域
                if !isLoggedIn {
                    // WebView容器 - 直接显示内置浏览器
                    WebView(
                        url: URL(string: "https://account.xiaomi.com/fe/service/login/qrcode")!,
                        onNavigationComplete: { cookies, url in
                            handleNavigationComplete(cookies: cookies, url: url)
                        },
                        onLoginSuccess: {
                            handleLoginSuccess()
                        },
                        isLoading: $isLoading
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // 登录成功视图
                if isLoggedIn {
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                        
                        Text("登录成功！")
                            .font(.title)
                            .fontWeight(.semibold)
                        
                        Text("已成功获取小米笔记访问权限")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("开始使用") {
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
                if isLoading && !isLoggedIn {
                    Color(NSColor.windowBackgroundColor)
                        .opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        
                        Text("正在加载登录页面...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: 800, minHeight: 500, idealHeight: 550, maxHeight: 600)
        .padding(.top, 1) // 避免标题栏下边框被裁剪
        .alert("登录失败", isPresented: $showError) {
            Button("重试") {
                isLoading = true
                isLoggedIn = false
            }
            Button("取消", role: .cancel) {
                closeSheet()
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func handleNavigationComplete(cookies: [HTTPCookie], url: URL?) {
        guard let currentURL = url else { return }
        print("导航完成，当前URL: \(currentURL.absoluteString)")
        
        // 检查是否是登录成功后的重定向
        if currentURL.absoluteString.contains("https://account.xiaomi.com/fe/service/account") {
            print("检测到登录成功重定向")
            // 登录成功，加载小米笔记页面获取cookie
            handleLoginSuccess()
        }
        
        // 检查是否是 profile 页面，如果是则获取完整 cookie（参考 Obsidian 插件）
        if currentURL.absoluteString.contains("i.mi.com/status/lite/profile") {
            print("检测到 profile 页面，开始获取完整 cookie")
            extractAndSaveCookies(cookies)
        }
    }
    
    private func handleLoginSuccess() {
        print("处理登录成功")
        // 加载小米笔记页面以获取cookie
        // 这里我们不需要立即更新UI，WebView会自动加载新页面
    }
    
    private func extractAndSaveCookies(_ cookies: [HTTPCookie]) {
        // 如果已经有保存的 cookie 字符串（从 URLSession 获取的），直接使用
        if let savedCookieString = UserDefaults.standard.string(forKey: "minote_cookie"), !savedCookieString.isEmpty {
            print("使用已保存的 Cookie 字符串（从 URLSession 获取）")
            print("Cookie 字符串（前300字符）: \(String(savedCookieString.prefix(300)))...")
            
            // 更新MiNoteService的cookie
            MiNoteService.shared.setCookie(savedCookieString)
            
            // 更新登录状态
            withAnimation {
                isLoading = false
                isLoggedIn = true
            }
            
            // 延迟一下再加载数据，确保 cookie 完全生效
            Task {
                // 等待 1 秒，让 cookie 有时间生效
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await viewModel.loadNotesFromCloud()
            }
            return
        }
        
        // 如果没有保存的 cookie 字符串，从 HTTPCookie 数组构建（回退方案）
        print("从 HTTPCookie 数组构建 Cookie 字符串（回退方案）")
        
        // 获取所有小米相关的 cookie（包括所有相关域名）
        let miNoteCookies = cookies.filter { cookie in
            cookie.domain.contains("xiaomi.com") || 
            cookie.domain.contains("mi.com") ||
            cookie.domain == ".mi.com" ||
            cookie.domain == "i.mi.com" ||
            cookie.domain == ".xiaomi.com" ||
            cookie.domain == "account.xiaomi.com"
        }
        
        print("找到 \(miNoteCookies.count) 个小米相关cookie（总共 \(cookies.count) 个）")
        
        // 去重：使用字典存储，相同名称的 cookie 保留最后一个（最新的）
        var cookieDict: [String: String] = [:]
        for cookie in miNoteCookies {
            cookieDict[cookie.name] = cookie.value
        }
        
        // 检查必要的 cookie 是否存在
        let hasServiceToken = cookieDict["serviceToken"] != nil && !cookieDict["serviceToken"]!.isEmpty
        let hasUserId = cookieDict["userId"] != nil && !cookieDict["userId"]!.isEmpty
        
        print("去重后共有 \(cookieDict.count) 个唯一 cookie")
        print("Cookie 列表: \(cookieDict.keys.sorted().joined(separator: ", "))")
        
        if !cookieDict.isEmpty && hasServiceToken && hasUserId {
            // 构建cookie字符串（格式：name1=value1; name2=value2; ...）
            // 按照名称排序以保持一致性
            let sortedCookiePairs = cookieDict.sorted { $0.key < $1.key }
            let cookieString = sortedCookiePairs.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            
            print("保存的cookie字符串（前300字符）: \(String(cookieString.prefix(300)))...")
            print("Cookie 包含 serviceToken: \(hasServiceToken)")
            print("Cookie 包含 userId: \(hasUserId)")
            print("Cookie 包含 csrfToken: \(cookieDict["csrfToken"] != nil)")
            print("Cookie 包含 i.mi.com_istrudev: \(cookieDict["i.mi.com_istrudev"] != nil)")
            
            // 保存cookie字符串到UserDefaults
            UserDefaults.standard.set(cookieString, forKey: "minote_cookie")
            
            // 更新MiNoteService的cookie
            MiNoteService.shared.setCookie(cookieString)
            
            // 更新登录状态
            withAnimation {
                isLoading = false
                isLoggedIn = true
            }
            
            // 延迟一下再加载数据，确保 cookie 完全生效
            Task {
                // 等待 1 秒，让 cookie 有时间生效
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await viewModel.loadNotesFromCloud()
            }
            
        } else {
            print("未找到有效的小米cookie 或缺少必要的 cookie")
            print("hasServiceToken: \(hasServiceToken), hasUserId: \(hasUserId)")
            if !hasServiceToken {
                print("警告：缺少 serviceToken cookie")
            }
            if !hasUserId {
                print("警告：缺少 userId cookie")
            }
            // 如果缺少 csrfToken，尝试再次访问主页
            if cookieDict["csrfToken"] == nil {
                print("警告：缺少 csrfToken cookie，可能需要访问主页")
            }
        }
    }
}

// WebView包装器
struct WebView: NSViewRepresentable {
    let url: URL
    let onNavigationComplete: ([HTTPCookie], URL?) -> Void
    let onLoginSuccess: () -> Void
    @Binding var isLoading: Bool
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // 设置自定义用户代理，模仿Chrome浏览器
        configuration.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // 配置WebView
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        
        print("WebView加载登录URL: \(url.absoluteString)")
        webView.load(request)
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        private var hasLoggedIn = false
        private var cookieString: String? = nil
        
        init(_ parent: WebView) {
            self.parent = parent
            print("WebView Coordinator初始化，登录URL: \(parent.url)")
        }
        
        func saveCookieString(_ cookieString: String) {
            self.cookieString = cookieString
            // 直接保存到 UserDefaults 和 MiNoteService
            UserDefaults.standard.set(cookieString, forKey: "minote_cookie")
            MiNoteService.shared.setCookie(cookieString)
            print("已保存 Cookie 字符串到 UserDefaults 和 MiNoteService")
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("WebView开始加载: \(webView.url?.absoluteString ?? "未知URL")")
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            print("WebView开始接收内容: \(webView.url?.absoluteString ?? "未知URL")")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let currentURL = webView.url
            print("WebView导航完成: \(currentURL?.absoluteString ?? "未知URL")")
            
            // 检查是否是登录成功后的重定向
            if let urlString = currentURL?.absoluteString,
               urlString.contains("https://account.xiaomi.com/fe/service/account") && !hasLoggedIn {
                print("检测到登录成功，准备加载小米笔记页面")
                hasLoggedIn = true
                
                // 通知父视图登录成功
                DispatchQueue.main.async {
                    self.parent.onLoginSuccess()
                }
                
                // 参考 Obsidian 插件：先加载 note/h5，然后访问 status/lite/profile 获取完整 cookie
                if let noteURL = URL(string: "https://i.mi.com/note/h5") {
                    print("加载小米笔记页面: \(noteURL.absoluteString)")
                    webView.load(URLRequest(url: noteURL))
                }
                return
            }
            
            // 如果已经加载了 note/h5，等待一下后先访问主页再访问 profile 页面获取完整 cookie
            if let urlString = currentURL?.absoluteString,
               urlString.contains("i.mi.com/note/h5") && hasLoggedIn {
                print("小米笔记页面加载完成，准备访问主页和 profile 页面获取完整 cookie")
                // 等待 2 秒让页面完全加载并设置所有 cookie
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    // 先访问主页以获取 csrfToken 等 cookie
                    if let homeURL = URL(string: "https://i.mi.com") {
                        print("访问主页: \(homeURL.absoluteString)")
                        webView.load(URLRequest(url: homeURL))
                    }
                }
                return
            }
            
            // 如果已经加载了主页，等待一下后访问 profile 页面
            if let urlString = currentURL?.absoluteString,
               urlString == "https://i.mi.com/" && hasLoggedIn {
                print("主页加载完成，准备访问 profile 页面")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if let profileURL = URL(string: "https://i.mi.com/status/lite/profile?ts=\(Int(Date().timeIntervalSince1970 * 1000))") {
                        print("访问 profile 页面: \(profileURL.absoluteString)")
                        webView.load(URLRequest(url: profileURL))
                    }
                }
                return
            }
            
            // 如果是 profile 页面加载完成，获取所有 cookie 并构建完整的 Cookie 字符串（参考 Obsidian 插件）
            if let urlString = currentURL?.absoluteString,
               urlString.contains("i.mi.com/status/lite/profile") {
                print("Profile 页面加载完成，获取完整 Cookie...")
                
                // 参考 Obsidian 插件：获取浏览器实际发送请求时使用的完整 Cookie 字符串
                // 从 WKWebView 的 cookie store 获取所有 cookie
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    print("从 WKWebView 获取到 \(cookies.count) 个 cookie")
                    
                    // 将所有 cookie 复制到 URLSession 的 cookie 存储，以便 URLSession 可以自动组装
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
                            
                            print("构建的 Cookie 字符串（前300字符）: \(String(cookieString.prefix(300)))...")
                            print("包含 \(relevantCookies.count) 个 cookie")
                            
                            DispatchQueue.main.async {
                                self.parent.isLoading = false
                                // 直接传递 Cookie 字符串，而不是 HTTPCookie 数组
                                // 我们需要修改 onNavigationComplete 的签名，或者创建一个新的回调
                                // 暂时先使用 cookies，但我们需要保存完整的 cookieString
                                self.saveCookieString(cookieString)
                                self.parent.onNavigationComplete(relevantCookies, currentURL)
                            }
                        }
                        task.resume()
                    } else {
                        // 如果 URL 无效，回退到从 WKWebView 获取
                        DispatchQueue.main.async {
                            self.parent.isLoading = false
                            self.parent.onNavigationComplete(cookies, currentURL)
                        }
                    }
                }
                return
            }
            
            // 其他页面导航完成后获取cookie
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                print("获取到 \(cookies.count) 个cookie")
                for cookie in cookies {
                    print("Cookie: \(cookie.name)=\(cookie.value) (domain: \(cookie.domain))")
                }
                DispatchQueue.main.async {
                    self.parent.isLoading = false
                    self.parent.onNavigationComplete(cookies, currentURL)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView导航失败: \(error.localizedDescription)")
            print("失败URL: \(webView.url?.absoluteString ?? "未知URL")")
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("WebView加载失败: \(error.localizedDescription)")
            print("失败URL: \(webView.url?.absoluteString ?? "未知URL")")
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let requestURL = navigationAction.request.url
            print("WebView决定导航策略: \(requestURL?.absoluteString ?? "未知URL")")
            
            // 允许所有导航
            decisionHandler(.allow)
        }
    }
}

#Preview {
    LoginView(viewModel: NotesViewModel())
}
