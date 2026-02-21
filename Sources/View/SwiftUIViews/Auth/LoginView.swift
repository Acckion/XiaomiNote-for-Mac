import SwiftUI
import WebKit

struct LoginView: View {
    @ObservedObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var isLoggedIn = false
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var statusMessage = ""

    private func closeSheet() {
        dismiss()
        DispatchQueue.main.async {
            if let window = NSApp.keyWindow,
               let sheetParent = window.sheetParent
            {
                sheetParent.endSheet(window)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if !isLoggedIn, !isRefreshing {
                    WebView(
                        url: URL(string: "https://account.xiaomi.com/fe/service/login/qrcode")!,
                        onPassTokenExtracted: { passToken, userId in
                            handlePassTokenExtracted(passToken: passToken, userId: userId)
                        },
                        isLoading: $isLoading
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // 正在通过三步流程获取 serviceToken
                if isRefreshing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text(statusMessage.isEmpty ? "正在获取访问凭证..." : statusMessage)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                }

                if isLoggedIn {
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)

                        Text("登录成功")
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

                if isLoading, !isLoggedIn, !isRefreshing {
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
        .padding(.top, 1)
        .alert("登录失败", isPresented: $showError) {
            Button("重试") {
                isRefreshing = false
                isLoading = false
                isLoggedIn = false
            }
            Button("取消", role: .cancel) {
                closeSheet()
            }
        } message: {
            Text(errorMessage)
        }
    }

    /// 从小米账号页面获取到 passToken 后的处理
    private func handlePassTokenExtracted(passToken: String, userId: String) {
        let maskedToken = String(passToken.prefix(8)) + "..." + String(passToken.suffix(4))
        LogService.shared.debug(.core, "登录页面提取到 passToken=\(maskedToken) (长度:\(passToken.count)), userId=\(userId)")

        withAnimation {
            isRefreshing = true
            statusMessage = "正在存储凭据..."
        }

        Task {
            // 存储 passToken
            await PassTokenManager.shared.storeCredentials(passToken: passToken, userId: userId)

            // 通过三步流程获取 serviceToken
            await MainActor.run {
                statusMessage = "正在通过 PassToken 获取 serviceToken..."
            }

            do {
                let serviceToken = try await PassTokenManager.shared.refreshServiceToken()
                let maskedST = String(serviceToken.prefix(8)) + "..." + String(serviceToken.suffix(4))
                LogService.shared.debug(.core, "三步流程成功, serviceToken=\(maskedST) (长度:\(serviceToken.count))")

                await MainActor.run {
                    withAnimation {
                        isRefreshing = false
                        isLoggedIn = true
                    }
                }

                // 通过 AuthState 处理登录成功逻辑（包括获取用户信息、发布事件等）
                await authState.handleLoginSuccess()
            } catch {
                LogService.shared.error(.core, "三步流程失败: \(error.localizedDescription)")
                await MainActor.run {
                    isRefreshing = false
                    errorMessage = "获取访问凭证失败: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

/// 小米账号登录 WebView
///
/// 只负责在小米账号页面完成登录，提取 passToken 和 userId，
/// 不再跳转到任何小米笔记页面
struct WebView: NSViewRepresentable {
    let url: URL
    let onPassTokenExtracted: (String, String) -> Void
    @Binding var isLoading: Bool

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        LogService.shared.debug(.core, "WebView 加载小米账号登录页")
        webView.load(request)
        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        private var hasExtracted = false

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            let currentURL = webView.url

            DispatchQueue.main.async {
                self.parent.isLoading = false
            }

            // 登录成功后会重定向到 account.xiaomi.com/fe/service/account
            guard let urlString = currentURL?.absoluteString,
                  urlString.contains("account.xiaomi.com/fe/service/account"),
                  !self.hasExtracted
            else {
                return
            }

            LogService.shared.info(.core, "检测到登录成功重定向，开始提取 passToken")
            hasExtracted = true

            // 从 WKWebView cookie store 提取 passToken 和 userId
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let passToken = cookies.first(where: { $0.name == "passToken" })?.value
                let userId = cookies.first(where: { $0.name == "userId" })?.value

                let cookieNames = cookies.map(\.name)
                LogService.shared.debug(.core, "WebView 获取到 cookie 列表: \(cookieNames.joined(separator: ", "))")

                guard let passToken, !passToken.isEmpty,
                      let userId, !userId.isEmpty
                else {
                    LogService.shared.warning(.core, "未找到 passToken 或 userId")
                    return
                }

                DispatchQueue.main.async {
                    self.parent.onPassTokenExtracted(passToken, userId)
                }
            }
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            LogService.shared.error(.core, "WebView 导航失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            LogService.shared.error(.core, "WebView 加载失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(
            _: WKWebView,
            decidePolicyFor _: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }
    }
}

#Preview {
    LoginView(authState: AuthState())
}
