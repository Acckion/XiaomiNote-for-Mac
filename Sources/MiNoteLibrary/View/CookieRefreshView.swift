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
            
            // 参考 Obsidian 插件：主页加载完成后，等待用户登录或自动触发 profile 请求
            // 不需要手动导航到 profile 页面，因为主页会自动加载 profile
            // 我们只需要在 decidePolicyFor 中监听请求头即可
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
        
        /// 参考 Obsidian 插件的 session.webRequest.onSendHeaders 实现
        /// 在请求发送前监听请求头，直接从请求头中提取 Cookie
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let requestURL = navigationAction.request.url
            guard let urlString = requestURL?.absoluteString else {
                decisionHandler(.allow)
                return
            }
            
            // 参考 Obsidian 插件：监听 profile 页面的请求（匹配 pattern: */status/lite/profile?ts=*）
            // Obsidian 插件使用: `urls: [\`https://${get(settingsStore).host}/status/lite/profile?ts=*\`]`
            if urlString.contains("i.mi.com/status/lite/profile") && urlString.contains("ts=") {
                print("[CookieRefreshWebView] 检测到 profile 请求: \(urlString)")
                
                // 参考 Obsidian 插件：直接从请求头的 Cookie 字段获取
                // Obsidian: `const cookie = details.requestHeaders['Cookie'];`
                if let cookieHeader = navigationAction.request.value(forHTTPHeaderField: "Cookie") {
                    print("[CookieRefreshWebView] ✅ 从请求头提取到Cookie（前300字符）: \(String(cookieHeader.prefix(300)))...")
                    
                    // 参考 Obsidian 插件：验证 cookie 是否有效
                    // Obsidian 插件: `if (cookie) { settingsStore.actions.setCookie(cookie); ... } else { this.modal.reload(); }`
                    let hasServiceToken = cookieHeader.contains("serviceToken=")
                    let hasUserId = cookieHeader.contains("userId=")
                    
                    if hasServiceToken && hasUserId && !cookieHeader.isEmpty {
                        // Cookie 有效，提取并关闭窗口（参考 Obsidian 插件）
                        cookieExtracted = true
                        DispatchQueue.main.async {
                            self.parent.isLoading = false
                            self.parent.onCookieExtracted(cookieHeader)
                        }
                        // 参考 Obsidian 插件：取消导航，因为我们已经获取到 cookie
                        decisionHandler(.cancel)
                        return
                    } else {
                        print("[CookieRefreshWebView] ⚠️ Cookie验证失败: hasServiceToken=\(hasServiceToken), hasUserId=\(hasUserId)")
                        // 参考 Obsidian 插件：如果 cookie 无效，重新加载页面
                        if retryCount < maxRetries {
                            retryCount += 1
                            print("[CookieRefreshWebView] 重试 \(retryCount)/\(maxRetries)")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                webView.reload()
                            }
                        } else {
                            print("[CookieRefreshWebView] ❌ 达到最大重试次数")
                            DispatchQueue.main.async {
                                self.parent.isLoading = false
                            }
                        }
                    }
                } else {
                    print("[CookieRefreshWebView] ⚠️ 请求头中没有 Cookie 字段")
                    // 参考 Obsidian 插件：如果没有 cookie，重新加载
                    if retryCount < maxRetries && !cookieExtracted {
                        retryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            webView.reload()
                        }
                    }
                }
            }
            
            // 允许所有其他导航
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

