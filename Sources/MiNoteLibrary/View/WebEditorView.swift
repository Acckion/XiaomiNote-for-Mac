import SwiftUI
import WebKit
import AppKit

/// Web编辑器视图，包装WKWebView来加载HTML编辑器
struct WebEditorView: NSViewRepresentable {
    @Binding var content: String
    let onContentChanged: (String) -> Void
    let onEditorReady: (Coordinator) -> Void
    
    // WebView配置
    private let configuration: WKWebViewConfiguration
    private let messageHandler: EditorMessageHandler
    
    init(content: Binding<String>, onContentChanged: @escaping (String) -> Void, onEditorReady: @escaping (Coordinator) -> Void) {
        self._content = content
        self.onContentChanged = onContentChanged
        self.onEditorReady = onEditorReady
        
        // 创建WebView配置
        let config = WKWebViewConfiguration()
        
        // 启用JavaScript
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        preferences.javaScriptCanOpenWindowsAutomatically = true
        // 启用开发者工具（允许右键 -> 检查元素）
        preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences = preferences
        
        // 添加消息处理器用于与JavaScript通信
        let userContentController = WKUserContentController()
        let handler = EditorMessageHandler(onContentChanged: onContentChanged, onEditorReady: onEditorReady)
        userContentController.add(handler, name: "editorBridge")
        config.userContentController = userContentController
        
        // 设置自定义URL方案处理图片
        config.setURLSchemeHandler(ImageURLSchemeHandler(), forURLScheme: "minote")
        
        self.configuration = config
        self.messageHandler = handler
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // 设置 coordinator 到 message handler
        messageHandler.setCoordinator(context.coordinator)
        
        // 加载本地HTML文件（从MiNoteLibrary framework的bundle）
        let bundle = Bundle(for: WebEditorView.Coordinator.self)
        
        // 尝试多种路径：先尝试直接在bundle根目录，然后尝试Web子目录
        var htmlURL: URL? = nil
        
        // 方法1: 直接在bundle根目录查找
        if let url = bundle.url(forResource: "editor", withExtension: "html") {
            htmlURL = url
        }
        // 方法2: 在Web子目录中查找
        else if let url = bundle.url(forResource: "editor", withExtension: "html", subdirectory: "Web") {
            htmlURL = url
        }
        // 方法3: 尝试从resourceURL查找
        else if let resourceURL = bundle.resourceURL {
            let webURL = resourceURL.appendingPathComponent("Web/editor.html")
            if FileManager.default.fileExists(atPath: webURL.path) {
                htmlURL = webURL
            } else {
                let directURL = resourceURL.appendingPathComponent("editor.html")
                if FileManager.default.fileExists(atPath: directURL.path) {
                    htmlURL = directURL
                }
            }
        }
        
        if let htmlURL = htmlURL {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            // 如果找不到文件，尝试从main bundle加载（向后兼容）
            if let mainBundleURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources/Web") {
                webView.loadFileURL(mainBundleURL, allowingReadAccessTo: mainBundleURL.deletingLastPathComponent())
            } else {
                // 如果还是找不到文件，加载一个简单的HTML并显示调试信息
                let resourcePath = bundle.resourceURL?.path ?? "未知"
                let bundlePath = bundle.bundlePath
                let htmlString = """
                <!DOCTYPE html>
                <html>
                <body>
                    <h1>编辑器加载失败</h1>
                    <p>请检查editor.html文件是否存在</p>
                    <p>Bundle路径: \(bundlePath)</p>
                    <p>Resource路径: \(resourcePath)</p>
                </body>
                </html>
                """
                webView.loadHTMLString(htmlString, baseURL: nil)
            }
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // 当内容变化时，更新WebView中的内容
        if context.coordinator.lastContent != content {
            context.coordinator.lastContent = content
            
            // 调用JavaScript函数加载内容
            let javascript = "window.MiNoteWebEditor.loadContent(`\(content.escapedForJavaScript())`)"
            webView.evaluateJavaScript(javascript) { result, error in
                if let error = error {
                    print("加载内容到WebView失败: \(error)")
                }
            }
        }
        
        // 检测并更新深色模式（每次updateNSView都检查，确保同步）
        let isDarkMode = detectDarkMode()
        print("[WebEditorView] updateNSView - 当前深色模式状态: \(isDarkMode), 上次状态: \(context.coordinator.lastDarkMode)")
        
        // 强制更新一次（确保初始状态正确，即使状态相同也更新一次）
        let shouldUpdate = context.coordinator.lastDarkMode != isDarkMode
        
        if shouldUpdate {
            print("[WebEditorView] 深色模式状态变化: \(context.coordinator.lastDarkMode) -> \(isDarkMode)")
            context.coordinator.lastDarkMode = isDarkMode
            let modeString = isDarkMode ? "dark" : "light"
            let javascript = "window.MiNoteWebEditor.setColorScheme('\(modeString)')"
            print("[WebEditorView] 执行JavaScript设置深色模式: \(modeString)")
            print("[WebEditorView] JavaScript代码: \(javascript)")
            
            // 使用异步方式执行，确保WebView已准备好
            DispatchQueue.main.async {
                webView.evaluateJavaScript(javascript) { result, error in
                    if let error = error {
                        print("[WebEditorView] ❌ 设置深色模式失败: \(error.localizedDescription)")
                    } else {
                        print("[WebEditorView] ✅ 深色模式已更新: \(modeString), 返回结果: \(String(describing: result))")
                    }
                }
            }
        } else {
            print("[WebEditorView] 深色模式状态未变化，跳过更新")
        }
    }
    
    // 检测系统是否处于深色模式
    private func detectDarkMode() -> Bool {
        if #available(macOS 10.14, *) {
            // 方法1: 使用 NSApp.effectiveAppearance
            let appearance = NSApp.effectiveAppearance
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            let isDark1 = bestMatch == .darkAqua
            
            // 方法2: 使用当前窗口的 effectiveAppearance（更准确）
            var isDark2 = false
            if let window = NSApplication.shared.windows.first {
                let windowAppearance = window.effectiveAppearance
                let windowBestMatch = windowAppearance.bestMatch(from: [.darkAqua, .aqua])
                isDark2 = windowBestMatch == .darkAqua
            }
            
            // 优先使用窗口的 appearance，如果没有窗口则使用 NSApp 的
            let isDark = isDark2 || isDark1
            
            print("[WebEditorView] 深色模式检测 - NSApp: \(isDark1), Window: \(isDark2), 最终结果: \(isDark)")
            return isDark
        }
        print("[WebEditorView] macOS版本低于10.14，不支持深色模式")
        return false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // 获取 Coordinator 的辅助方法
    private func getCoordinator(from context: Context) -> Coordinator? {
        return context.coordinator
    }
    
    // 执行格式操作（保留用于向后兼容，但不推荐直接使用）
    func executeFormatAction(_ action: String, value: String? = nil) {
        // 这个方法保留用于向后兼容，但应该通过闭包来使用
    }
    
    // 插入图片（保留用于向后兼容）
    func insertImage(_ imageUrl: String, altText: String = "图片") {
        // 这个方法保留用于向后兼容，但应该通过闭包来使用
    }
    
    // 获取当前内容（保留用于向后兼容）
    func getCurrentContent(completion: @escaping (String) -> Void) {
        // 这个方法保留用于向后兼容，但应该通过闭包来使用
        completion("")
    }
    
    // 撤销操作（保留用于向后兼容）
    func undo() {
        // 这个方法保留用于向后兼容，但应该通过闭包来使用
    }
    
    // 重做操作（保留用于向后兼容）
    func redo() {
        // 这个方法保留用于向后兼容，但应该通过闭包来使用
    }
    
    // Coordinator类
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebEditorView
        var lastContent: String = ""
        var lastDarkMode: Bool = false
        weak var webView: WKWebView?
        
        // 操作闭包，用于从外部执行操作
        var executeFormatActionClosure: ((String, String?) -> Void)?
        var insertImageClosure: ((String, String) -> Void)?
        var getCurrentContentClosure: ((@escaping (String) -> Void) -> Void)?
        var undoClosure: (() -> Void)?
        var redoClosure: (() -> Void)?
        
        init(_ parent: WebEditorView) {
            self.parent = parent
        }
        
        // 设置操作闭包
        func setupActionClosures() {
            executeFormatActionClosure = { [weak self] action, value in
                guard let webView = self?.webView else { return }
                let javascript: String
                if let value = value {
                    javascript = "window.MiNoteWebEditor.executeFormatAction('\(action)', '\(value)')"
                } else {
                    javascript = "window.MiNoteWebEditor.executeFormatAction('\(action)')"
                }
                webView.evaluateJavaScript(javascript) { result, error in
                    if let error = error {
                        print("执行格式操作失败: \(error)")
                    }
                }
            }
            
            insertImageClosure = { [weak self] imageUrl, altText in
                guard let webView = self?.webView else { return }
                let javascript = "window.MiNoteWebEditor.insertImage('\(imageUrl)', '\(altText)')"
                webView.evaluateJavaScript(javascript) { result, error in
                    if let error = error {
                        print("插入图片失败: \(error)")
                    }
                }
            }
            
            getCurrentContentClosure = { [weak self] completion in
                guard let webView = self?.webView else {
                    completion("")
                    return
                }
                webView.evaluateJavaScript("window.MiNoteWebEditor.getContent()") { result, error in
                    if let error = error {
                        print("获取内容失败: \(error)")
                        completion("")
                    } else if let content = result as? String {
                        completion(content)
                    } else {
                        completion("")
                    }
                }
            }
            
            undoClosure = { [weak self] in
                guard let webView = self?.webView else { return }
                webView.evaluateJavaScript("document.execCommand('undo', false, null)") { result, error in
                    if let error = error {
                        print("撤销失败: \(error)")
                    } else {
                        self?.getCurrentContentClosure? { content in
                            self?.parent.onContentChanged(content)
                        }
                    }
                }
            }
            
            redoClosure = { [weak self] in
                guard let webView = self?.webView else { return }
                webView.evaluateJavaScript("document.execCommand('redo', false, null)") { result, error in
                    if let error = error {
                        print("重做失败: \(error)")
                    } else {
                        self?.getCurrentContentClosure? { content in
                            self?.parent.onContentChanged(content)
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            print("[WebEditorView] ✅ WebView加载完成")
            
            // 设置操作闭包
            setupActionClosures()
            
            // 通知外部编辑器已准备好，传递 coordinator
            parent.onEditorReady(self)
            
            // 设置外观变化监听器
            setupAppearanceObserver()
            
            // 初始设置深色模式（延迟一点确保DOM已完全加载）
            print("[WebEditorView] 开始初始设置深色模式")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                print("[WebEditorView] 延迟后设置深色模式（确保DOM已加载）")
                self.updateColorScheme(webView: webView, force: true)
            }
            
            // 初始加载内容
            if !lastContent.isEmpty {
                let javascript = "window.MiNoteWebEditor.loadContent(`\(lastContent.escapedForJavaScript())`)"
                webView.evaluateJavaScript(javascript) { result, error in
                    if let error = error {
                        print("[WebEditorView] ❌ 初始加载内容失败: \(error)")
                    } else {
                        print("[WebEditorView] ✅ 初始内容加载成功")
                    }
                }
            }
        }
        
        // 设置外观变化监听器（仅使用KVO，不使用定时器）
        private func setupAppearanceObserver() {
            // 监听窗口外观变化（使用 KVO）
            if let window = NSApplication.shared.windows.first {
                window.addObserver(
                    self,
                    forKeyPath: "effectiveAppearance",
                    options: [.new, .old],
                    context: nil
                )
                print("[WebEditorView] ✅ 已设置窗口外观KVO监听")
            } else {
                print("[WebEditorView] ⚠️ 未找到窗口，无法设置KVO监听")
            }
        }
        
        // KVO 回调
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "effectiveAppearance" {
                print("[WebEditorView] 📢 KVO检测到窗口外观变化")
                updateColorScheme()
            } else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            }
        }
        
        // 更新颜色方案
        private func updateColorScheme(webView: WKWebView? = nil, force: Bool = false) {
            guard let webView = webView ?? self.webView else {
                print("[WebEditorView] ⚠️ updateColorScheme: webView为nil，无法更新")
                return
            }
            
            let isDarkMode = parent.detectDarkMode()
            print("[WebEditorView] updateColorScheme - 检测到深色模式: \(isDarkMode), 上次状态: \(lastDarkMode), 强制更新: \(force)")
            
            // 如果强制更新或模式改变，则更新
            let shouldUpdate = force || (lastDarkMode != isDarkMode)
            
            if shouldUpdate {
                if !force {
                    print("[WebEditorView] 深色模式状态变化，开始更新: \(lastDarkMode) -> \(isDarkMode)")
                } else {
                    print("[WebEditorView] 强制更新深色模式: \(isDarkMode)")
                }
                lastDarkMode = isDarkMode
                let modeString = isDarkMode ? "dark" : "light"
                let modeJavascript = "window.MiNoteWebEditor.setColorScheme('\(modeString)')"
                print("[WebEditorView] 执行JavaScript: \(modeJavascript)")
                
                webView.evaluateJavaScript(modeJavascript) { result, error in
                    if let error = error {
                        print("[WebEditorView] ❌ 设置深色模式失败: \(error.localizedDescription)")
                    } else {
                        print("[WebEditorView] ✅ 深色模式已更新: \(modeString), JavaScript返回: \(String(describing: result))")
                    }
                }
            } else {
                print("[WebEditorView] 深色模式状态未变化，跳过更新")
            }
        }
        
        deinit {
            // 移除KVO监听器
            if let window = NSApplication.shared.windows.first {
                window.removeObserver(self, forKeyPath: "effectiveAppearance")
                print("[WebEditorView] 已移除窗口外观KVO监听")
            }
            print("[WebEditorView] Coordinator已释放，移除外观监听器")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView导航失败: \(error)")
        }
    }
    
    // 消息处理器
    class EditorMessageHandler: NSObject, WKScriptMessageHandler {
        let onContentChanged: (String) -> Void
        let onEditorReady: (Coordinator) -> Void
        weak var coordinator: Coordinator?
        
        init(onContentChanged: @escaping (String) -> Void, onEditorReady: @escaping (Coordinator) -> Void) {
            self.onContentChanged = onContentChanged
            self.onEditorReady = onEditorReady
        }
        
        func setCoordinator(_ coordinator: Coordinator) {
            self.coordinator = coordinator
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else {
                return
            }
            
            switch type {
            case "editorReady":
                print("Web编辑器已准备就绪")
                // editorReady 现在在 didFinish 中处理，这里不需要调用
                
            case "contentChanged":
                if let content = body["content"] as? String {
                    print("内容已更改，长度: \(content.count)")
                    onContentChanged(content)
                }
                
            case "imagePasted":
                if let imageData = body["imageData"] as? String {
                    print("图片已粘贴，数据长度: \(imageData.count)")
                    // 这里可以处理base64图片数据
                    // 例如保存到本地并生成minote:// URL
                }
                
            default:
                print("收到未知消息类型: \(type)")
            }
        }
    }
    
    // 图片URL方案处理器
    class ImageURLSchemeHandler: NSObject, WKURLSchemeHandler {
        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(NSError(domain: "ImageURLSchemeHandler", code: 400, userInfo: nil))
                return
            }
            
            // 解析minote://image/{id}格式的URL
            let path = url.path
            if path.hasPrefix("/image/") {
                let imageId = String(path.dropFirst("/image/".count))
                
                // 这里应该从本地存储加载图片数据
                // 暂时返回一个占位图片
                let placeholderImage = NSImage(systemSymbolName: "photo", accessibilityDescription: "图片") ?? NSImage()
                
                if let imageData = placeholderImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: imageData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    
                    let response = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Content-Type": "image/png",
                            "Content-Length": "\(pngData.count)"
                        ]
                    )!
                    
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(pngData)
                    urlSchemeTask.didFinish()
                }
            } else {
                urlSchemeTask.didFailWithError(NSError(domain: "ImageURLSchemeHandler", code: 404, userInfo: nil))
            }
        }
        
        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
            // 停止任务
        }
    }
}

// 字符串扩展，用于JavaScript转义
extension String {
    func escapedForJavaScript() -> String {
        return self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
