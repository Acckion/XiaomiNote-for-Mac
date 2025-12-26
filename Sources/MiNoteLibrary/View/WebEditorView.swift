import SwiftUI
import WebKit
import AppKit
import Carbon

/// 自定义WKWebView，用于拦截右键菜单并确保在外部窗口打开Web Inspector
class InspectorWKWebView: WKWebView {
    weak var inspectorCoordinator: WebEditorView.Coordinator?
    
    override func menu(for event: NSEvent) -> NSMenu? {
        // 拦截系统菜单，确保"检查元素"使用外部窗口
        let menu = NSMenu()
        
        // 添加"检查元素"菜单项，使用我们的方法打开（外部窗口）
        let inspectItem = NSMenuItem(title: "检查元素", action: #selector(openInspector), keyEquivalent: "")
        inspectItem.target = self
        menu.addItem(inspectItem)
        
        print("[InspectorWKWebView] 拦截右键菜单，添加自定义'检查元素'项")
        
        return menu
    }
    
    @objc private func openInspector() {
        print("[InspectorWKWebView] 右键菜单触发，打开Web Inspector（外部窗口）")
        // 使用coordinator的方法打开Web Inspector（外部窗口）
        inspectorCoordinator?.openWebInspector()
    }
}

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
        
        // 注意：在 macOS 上，WKWebView 不支持 allowFileAccessFromFileURLs 配置
        // 使用 loadFileURL:allowingReadAccessTo: 方法已经足够允许访问本地资源
        
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
        // 使用自定义的WKWebView子类来拦截右键菜单
        let webView = InspectorWKWebView(frame: .zero, configuration: configuration)
        webView.inspectorCoordinator = context.coordinator
        
        // 启用检查器 (macOS 13.3+)
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
            print("[WebEditorView] ✅ Web Inspector已启用 (isInspectable = true)")
        } else {
            print("[WebEditorView] ⚠️ macOS版本低于13.3，无法使用isInspectable属性")
        }
        
        // 保存webView引用到coordinator，以便后续打开Web Inspector
        context.coordinator.webView = webView
        
        webView.navigationDelegate = context.coordinator
        
        // 确保在页面加载完成后再次设置isInspectable（某些情况下需要延迟设置）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if #available(macOS 13.3, *) {
                webView.isInspectable = true
                print("[WebEditorView] ✅ 延迟设置Web Inspector (isInspectable = true)")
            }
        }
        
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
            // 在 macOS 上，使用 loadHTMLString 并设置 baseURL 可以更好地处理相对路径的模块文件
            // 读取 HTML 文件内容
            if let htmlContent = try? String(contentsOf: htmlURL, encoding: .utf8) {
                // 设置 baseURL 为 Resources 目录（HTML 文件所在的目录）
                var baseURL = htmlURL.deletingLastPathComponent()
                // 如果 HTML 在 Web 子目录中，baseURL 应该是 Resources 目录
                if baseURL.lastPathComponent == "Web" {
                    baseURL = baseURL.deletingLastPathComponent()
                }
                
                // 尝试动态加载模块文件并注入到 HTML 中
                let resourcesURL = baseURL
                // 注意：xml-to-html.js 和 html-to-xml.js 必须在 converter.js 之前加载
                let moduleFiles = [
                    "logger.js",
                    "constants.js",
                    "utils.js",
                    "xml-to-html.js",  // 必须在 converter.js 之前
                    "html-to-xml.js",  // 必须在 converter.js 之前
                    "command.js",
                    "format-commands.js",
                    "dom-writer.js",
                    "converter.js",
                    "cursor.js",
                    "format.js",  // 必须在 editor-api.js 之前
                    "enter-handler.js",  // 回车键处理模块
                    "editor-core.js",
                    "editor-api.js",
                    "editor-init.js"
                ]
                
                var injectedScripts = ""
                var allModulesLoaded = true
                
                for moduleFile in moduleFiles {
                    let moduleURL = resourcesURL.appendingPathComponent(moduleFile)
                    if let moduleContent = try? String(contentsOf: moduleURL, encoding: .utf8) {
                        injectedScripts += "<script>\n\(moduleContent)\n</script>\n"
                        print("[WebEditorView] ✅ 成功加载模块: \(moduleFile)")
                    } else {
                        print("[WebEditorView] ⚠️ 无法加载模块: \(moduleFile) at \(moduleURL.path)")
                        allModulesLoaded = false
                    }
                }
                
                if allModulesLoaded {
                    // 替换 HTML 中的 <script src="..."> 标签为内联脚本
                    var modifiedHTML = htmlContent
                    // 移除原有的模块加载脚本标签
                    for moduleFile in moduleFiles {
                        let pattern = "<script[^>]*src=[\"']\(moduleFile)[\"'][^>]*></script>"
                        modifiedHTML = modifiedHTML.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                    }
                    // 在 </head> 之前插入内联脚本
                    if let headEndRange = modifiedHTML.range(of: "</head>", options: .caseInsensitive) {
                        modifiedHTML.insert(contentsOf: injectedScripts, at: headEndRange.lowerBound)
                    } else {
                        // 如果没有 </head>，在 <body> 之前插入
                        if let bodyStartRange = modifiedHTML.range(of: "<body", options: .caseInsensitive) {
                            modifiedHTML.insert(contentsOf: injectedScripts, at: bodyStartRange.lowerBound)
                        }
                    }
                    
                    print("[WebEditorView] ✅ 所有模块已内联到 HTML")
                    webView.loadHTMLString(modifiedHTML, baseURL: baseURL)
                } else {
                    // 如果部分模块加载失败，使用原始 HTML 和 baseURL
                    print("[WebEditorView] ⚠️ 部分模块加载失败，使用原始 HTML")
                    webView.loadHTMLString(htmlContent, baseURL: baseURL)
                }
            } else {
                // 如果读取失败，回退到 loadFileURL
                var resourcesURL = htmlURL.deletingLastPathComponent()
                if resourcesURL.lastPathComponent == "Web" {
                    resourcesURL = resourcesURL.deletingLastPathComponent()
                }
                print("[WebEditorView] 回退到 loadFileURL，HTML URL: \(htmlURL.path)")
                print("[WebEditorView] Allowing read access to: \(resourcesURL.path)")
                webView.loadFileURL(htmlURL, allowingReadAccessTo: resourcesURL)
            }
            
            // 页面加载完成后，输出一些测试日志到控制台
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let testLog = """
                console.log('%c========================================', 'color: green; font-size: 16px; font-weight: bold;');
                console.log('%cWeb Inspector 控制台测试', 'color: green; font-size: 14px; font-weight: bold;');
                console.log('%c如果你能看到这条消息，说明控制台工作正常', 'color: blue; font-size: 12px;');
                console.log('当前时间:', new Date().toLocaleString());
                console.log('编辑器URL:', window.location.href);
                console.log('%c========================================', 'color: green; font-size: 16px; font-weight: bold;');
                """
                webView.evaluateJavaScript(testLog) { result, error in
                    if let error = error {
                        print("[WebEditorView] 输出测试日志失败: \(error)")
                    } else {
                        print("[WebEditorView] ✅ 测试日志已输出到控制台")
                    }
                }
            }
        } else {
            // 如果找不到文件，尝试从main bundle加载（向后兼容）
            if let mainBundleURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources/Web") {
                // 允许访问整个 Resources 目录（包含 modules 子目录）
                // mainBundleURL 是 Resources/Web/editor.html
                // 需要访问 Resources 目录
                let webURL = mainBundleURL.deletingLastPathComponent() // Resources/Web
                let resourcesURL = webURL.deletingLastPathComponent() // Resources
                webView.loadFileURL(mainBundleURL, allowingReadAccessTo: resourcesURL)
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
        // 如果是来自Web的更新，跳过内容回写（避免循环更新）
        if context.coordinator.isUpdatingFromWeb {
            // 即使标志为 true，也更新 lastContent，确保下次比较时不会误判
            context.coordinator.lastContent = content
            return
        }
        
        // 当内容变化时，更新WebView中的内容
        // 注意：只有当内容真正从外部变化时才更新（比如切换到其他笔记）
        // 如果内容是从Web编辑器更新的，isUpdatingFromWeb 标志已经阻止了这里
        // 使用更精确的内容比较，避免因微小差异导致不必要的更新
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLastContent = context.coordinator.lastContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 只有当内容真正不同时才更新，避免不必要的JavaScript调用
        if normalizedContent != normalizedLastContent {
            context.coordinator.lastContent = content
            
            // 调用JavaScript函数加载内容（会保存和恢复光标位置）
            // loadContent 内部会检查内容是否真的需要重新渲染
            let javascript = "window.MiNoteWebEditor.loadContent(`\(content.escapedForJavaScript())`)"
            webView.evaluateJavaScript(javascript) { result, error in
                if let error = error {
                    print("[WebEditorView] 加载内容到WebView失败: \(error)")
                }
            }
        } else {
            // 即使内容相同，也更新 lastContent，确保下次比较时不会误判
            context.coordinator.lastContent = content
        }
        
        // 注意：深色模式检测已移除，改为使用KVO响应式监听，避免性能损耗
        // 深色模式会在以下情况自动更新：
        // 1. 页面加载完成后初始化设置（webView(_:didFinish:)）
        // 2. 系统外观变化时通过KVO自动触发（setupAppearanceObserver）
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
        weak var observedWindow: NSWindow? // 保存被观察的窗口引用
        var appearanceTimer: Timer? // 保留以防万一，虽然现在主要用KVO
        
        // 标志：是否正在处理来自Web端的更新
        var isUpdatingFromWeb: Bool = false
        
        // WebEditorContext 引用，用于更新格式状态
        weak var webEditorContext: WebEditorContext?
        
        // 操作闭包，用于从外部执行操作
        var executeFormatActionClosure: ((String, String?) -> Void)?
        var insertImageClosure: ((String, String) -> Void)?
        var getCurrentContentClosure: ((@escaping (String) -> Void) -> Void)?
        var forceSaveContentClosure: ((@escaping () -> Void) -> Void)?
        var undoClosure: (() -> Void)?
        var redoClosure: (() -> Void)?
        var highlightSearchTextClosure: ((String) -> Void)?
        
        init(_ parent: WebEditorView) {
            self.parent = parent
        }
        
        /// 打开Web Inspector（在外部窗口中打开，并确保显示在最前面）
        func openWebInspector() {
            guard let webView = webView else { 
                print("[WebEditorView] ⚠️ 无法打开Web Inspector: webView为nil")
                return 
            }
            
            print("[WebEditorView] 尝试打开 Web Inspector（外部窗口）")
            
            // 使用私有API打开Web Inspector
            let inspectorKey = "_inspector"
            
            if webView.responds(to: NSSelectorFromString(inspectorKey)) {
                if let inspector = webView.value(forKey: inspectorKey) as? NSObject {
                    print("[WebEditorView] ✅ 获取到 _inspector 对象")
                    
                    // 优先尝试 detach 方法，确保在独立窗口中打开
                    let detachSelector = NSSelectorFromString("detach")
                    if inspector.responds(to: detachSelector) {
                        print("[WebEditorView] 调用 _inspector.detach() 在独立窗口中打开")
                        inspector.perform(detachSelector)
                        
                        // 延迟一点时间，然后调用 show 确保窗口显示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            let showSelector = NSSelectorFromString("show")
                            if inspector.responds(to: showSelector) {
                                inspector.perform(showSelector)
                                print("[WebEditorView] 已调用 _inspector.show()")
                            }
                        }
                    } else {
                        // 如果没有 detach 方法，尝试 show 方法
                        print("[WebEditorView] ⚠️ _inspector 没有 detach 方法，尝试 show")
                        let showSelector = NSSelectorFromString("show")
                        if inspector.responds(to: showSelector) {
                            inspector.perform(showSelector)
                            print("[WebEditorView] 已调用 _inspector.show()")
                        }
                    }
                    
                    // 尝试将窗口带到前台
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.bringInspectorWindowToFront()
                    }
                    
                    // 额外尝试：使用 toggleInspector 方法（如果有）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        let toggleSelector = NSSelectorFromString("toggleInspector")
                        if inspector.responds(to: toggleSelector) {
                            inspector.perform(toggleSelector)
                            print("[WebEditorView] 已调用 _inspector.toggleInspector()")
                        }
                    }
                } else {
                    print("[WebEditorView] ⚠️ 无法获取 _inspector 对象")
                }
            } else {
                print("[WebEditorView] ⚠️ WebView 不响应 _inspector 选择器")
                
                // 备用方案：尝试使用 performSelector 直接调用
                let performSelector = NSSelectorFromString("performSelector:")
                if webView.responds(to: performSelector) {
                    print("[WebEditorView] 尝试备用方案：直接调用 performSelector")
                    // 尝试调用 showInspector 或 toggleInspector
                    let showInspectorSelector = NSSelectorFromString("showInspector")
                    let toggleInspectorSelector = NSSelectorFromString("toggleInspector")
                    
                    if webView.responds(to: showInspectorSelector) {
                        webView.perform(showInspectorSelector)
                        print("[WebEditorView] 已调用 showInspector")
                    } else if webView.responds(to: toggleInspectorSelector) {
                        webView.perform(toggleInspectorSelector)
                        print("[WebEditorView] 已调用 toggleInspector")
                    }
                }
            }
        }
        
        /// 将 Inspector 窗口带到前台
        private func bringInspectorWindowToFront() {
            print("[WebEditorView] 尝试将 Inspector 窗口带到前台")
            
            // 查找所有可能的 Inspector 窗口标题
            let possibleTitles = [
                "Web Inspector",
                "检查器",
                "Developer Tools",
                "— editor.html",
                "Inspector",
                "WebKit Inspector",
                "Web Inspector —",
                "Web Inspector -"
            ]
            
            for window in NSApplication.shared.windows {
                if let title = window.title as String? {
                    for possibleTitle in possibleTitles {
                        if title.contains(possibleTitle) {
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless() // 确保窗口显示在最前面
                            print("[WebEditorView] ✅ 已将 Inspector 窗口带到前台: \(title)")
                            return
                        }
                    }
                }
            }
            
            print("[WebEditorView] ⚠️ 未找到 Inspector 窗口")
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
            
            forceSaveContentClosure = { [weak self] completion in
                guard let webView = self?.webView else {
                    completion()
                    return
                }
                webView.evaluateJavaScript("window.MiNoteWebEditor.forceSaveContent()") { result, error in
                    if let error = error {
                        print("强制保存内容失败: \(error)")
                    } else {
                        print("强制保存内容成功")
                    }
                    completion()
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
            
            highlightSearchTextClosure = { [weak self] searchText in
                guard let webView = self?.webView else { return }
                let escapedText = searchText
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let javascript = "window.MiNoteWebEditor.highlightSearchText('\(escapedText)')"
                webView.evaluateJavaScript(javascript) { result, error in
                    if let error = error {
                        print("[WebEditorView] 高亮搜索文本失败: \(error)")
                    } else {
                        print("[WebEditorView] 搜索高亮已更新: \(searchText)")
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            print("[WebEditorView] ✅ WebView加载完成")
            
            // 设置操作闭包
            setupActionClosures()
            
            // 设置 WebEditorContext 的闭包（如果存在）
            if let webEditorContext = self.webEditorContext {
                webEditorContext.highlightSearchTextClosure = self.highlightSearchTextClosure
            }
            
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
            // 必须在主线程访问 NSApplication
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                if let window = NSApplication.shared.windows.first {
                    // 如果已经监听了其他窗口，先移除
                    if let oldWindow = self.observedWindow, oldWindow != window {
                        oldWindow.removeObserver(self, forKeyPath: "effectiveAppearance")
                    }
                    
                    if self.observedWindow != window {
                        window.addObserver(
                            self,
                            forKeyPath: "effectiveAppearance",
                            options: [.new, .old],
                            context: nil
                        )
                        self.observedWindow = window
                        print("[WebEditorView] ✅ 已设置窗口外观KVO监听")
                    }
                } else {
                    print("[WebEditorView] ⚠️ 未找到窗口，无法设置KVO监听")
                }
            }
        }
        
        // KVO 回调
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "effectiveAppearance" {
                print("[WebEditorView] 📢 KVO检测到窗口外观变化")
                // 在主线程更新 UI
                DispatchQueue.main.async { [weak self] in
                    self?.updateColorScheme()
                }
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
            if let window = observedWindow {
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
        weak var coordinator: WebEditorView.Coordinator?
        
        init(onContentChanged: @escaping (String) -> Void, onEditorReady: @escaping (Coordinator) -> Void) {
            self.onContentChanged = onContentChanged
            self.onEditorReady = onEditorReady
        }
        
        func setCoordinator(_ coordinator: WebEditorView.Coordinator) {
            self.coordinator = coordinator
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // 安全地处理消息体，避免 NSXPCDecoder 警告
            // 只提取我们需要的类型，而不是直接转换为 [String: Any]
            guard let bodyDict = message.body as? NSDictionary,
                  let type = bodyDict["type"] as? String else {
                return
            }
            
            // 将 NSDictionary 转换为 [String: Any]，但只提取我们需要的键
            var body: [String: Any] = [:]
            for key in bodyDict.allKeys {
                if let keyString = key as? String {
                    body[keyString] = bodyDict[keyString]
                }
            }
            
            switch type {
            case "editorReady":
                print("Web编辑器已准备就绪")
                // editorReady 现在在 didFinish 中处理，这里不需要调用
                
            case "contentChanged":
                if let content = body["content"] as? String {
                    // print("内容已更改，长度: \(content.count)")
                    
                    // 标记这是来自Web的更新，并同步 lastContent
                    // 必须在主线程上设置，确保在 SwiftUI 更新之前生效
                    if Thread.isMainThread {
                        // 已经在主线程，直接设置
                        if let coordinator = self.coordinator {
                            coordinator.isUpdatingFromWeb = true
                            coordinator.lastContent = content
                            // 先触发内容变化回调（这会更新 currentXMLContent，可能触发 SwiftUI 重新渲染）
                            self.onContentChanged(content)
                            // 延迟更长时间后重置标志，确保所有相关的 updateNSView 调用都能检测到
                            // 增加延迟时间，避免 SwiftUI 重新渲染时触发不必要的 loadContent
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                coordinator.isUpdatingFromWeb = false
                            }
                        } else {
                            self.onContentChanged(content)
                        }
                    } else {
                        // 不在主线程，切换到主线程
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            
                            if let coordinator = self.coordinator {
                                // 先设置标志，确保后续的 updateNSView 能够检测到
                                coordinator.isUpdatingFromWeb = true
                                coordinator.lastContent = content
                                
                                // 然后触发内容变化回调
                                // 这个回调可能会触发 SwiftUI 更新，但由于 isUpdatingFromWeb 已设置，会被跳过
                                self.onContentChanged(content)
                                
                                // 延迟更长时间后重置标志，确保所有相关的 updateNSView 调用都能检测到
                                // 增加延迟时间，避免 SwiftUI 重新渲染时触发不必要的 loadContent
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    coordinator.isUpdatingFromWeb = false
                                }
                            } else {
                                // 如果 coordinator 不存在，直接调用回调
                                self.onContentChanged(content)
                            }
                        }
                    }
                }
                
            case "formatStateChanged":
                // 处理格式状态变化（参考 CKEditor 5 的状态同步）
                if let formatState = body["formatState"] as? [String: Any],
                   let coordinator = self.coordinator,
                   let webEditorContext = coordinator.webEditorContext {
                    DispatchQueue.main.async {
                        // 更新文本格式状态
                        if let isBold = formatState["isBold"] as? Bool {
                            webEditorContext.isBold = isBold
                        }
                        if let isItalic = formatState["isItalic"] as? Bool {
                            webEditorContext.isItalic = isItalic
                        }
                        if let isUnderline = formatState["isUnderline"] as? Bool {
                            webEditorContext.isUnderline = isUnderline
                        }
                        if let isStrikethrough = formatState["isStrikethrough"] as? Bool {
                            webEditorContext.isStrikethrough = isStrikethrough
                        }
                        if let isHighlighted = formatState["isHighlighted"] as? Bool {
                            webEditorContext.isHighlighted = isHighlighted
                        }
                        
                        // 更新标题级别
                        if let headingLevel = formatState["headingLevel"] as? Int {
                            webEditorContext.headingLevel = headingLevel > 0 ? headingLevel : nil
                        } else if formatState["headingLevel"] is NSNull {
                            webEditorContext.headingLevel = nil
                        }
                        
                        // 更新对齐方式
                        if let alignmentString = formatState["textAlignment"] as? String {
                            webEditorContext.textAlignment = TextAlignment.fromString(alignmentString)
                        }
                        
                        // 更新列表类型
                        if let listType = formatState["listType"] as? String {
                            webEditorContext.listType = listType
                        } else if formatState["listType"] is NSNull {
                            webEditorContext.listType = nil
                        }
                        
                        // 更新引用块状态
                        if let isInQuote = formatState["isInQuote"] as? Bool {
                            webEditorContext.isInQuote = isInQuote
                        }
                    }
                }
                
            case "imagePasted":
                if let imageData = body["imageData"] as? String {
                    print("图片已粘贴，数据长度: \(imageData.count)")
                    // 这里可以处理base64图片数据
                    // 例如保存到本地并生成minote:// URL
                }
                
            case "log":
                if let message = body["message"] as? String,
                   let level = body["level"] as? String {
                    let prefix = level == "error" ? "🔴" : (level == "warn" ? "⚠️" : "📝")
                    print("[JS] \(prefix) \(message)")
                }
                
            case "formatStateChanged":
                if let formatState = body["formatState"] as? [String: Any] {
                    DispatchQueue.main.async { [weak self] in
                        // 需要访问 WebEditorContext 来更新格式状态
                        // 由于 EditorMessageHandler 没有直接访问 WebEditorContext 的引用
                        // 我们需要通过 coordinator 来访问
                        if let coordinator = self?.coordinator,
                           let webEditorContext = coordinator.webEditorContext {
                            if let isBold = formatState["isBold"] as? Bool {
                                webEditorContext.isBold = isBold
                            }
                            if let isItalic = formatState["isItalic"] as? Bool {
                                webEditorContext.isItalic = isItalic
                            }
                            if let isUnderline = formatState["isUnderline"] as? Bool {
                                webEditorContext.isUnderline = isUnderline
                            }
                            if let isStrikethrough = formatState["isStrikethrough"] as? Bool {
                                webEditorContext.isStrikethrough = isStrikethrough
                            }
                            if let isHighlighted = formatState["isHighlighted"] as? Bool {
                                webEditorContext.isHighlighted = isHighlighted
                            }
                            if let textAlignmentStr = formatState["textAlignment"] as? String {
                                webEditorContext.textAlignment = TextAlignment.fromString(textAlignmentStr)
                            }
                            if let headingLevel = formatState["headingLevel"] as? Int {
                                webEditorContext.headingLevel = headingLevel > 0 ? headingLevel : nil
                            } else if formatState["headingLevel"] is NSNull {
                                webEditorContext.headingLevel = nil
                            }
                        }
                    }
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
            // 支持多种路径格式：
            // 1. /image/{id} - 标准格式
            // 2. /{userId}.{fileId} - 用户ID.文件ID格式（如 /1315204657.iWIa7HjEEF53X3XD8vvm5Q）
            // 3. /{fileId} - 直接文件ID格式
            let path = url.path
            
            var searchFileName: String? = nil  // 完整的文件名（可能包含userId.fileId）
            var fileId: String? = nil          // 仅文件ID部分
            
            if path.hasPrefix("/image/") {
                // 标准格式: /image/{id}
                let id = String(path.dropFirst("/image/".count))
                fileId = id
                searchFileName = id
            } else if path.hasPrefix("/") {
                // 处理其他格式: /{userId}.{fileId} 或 /{fileId}
                let pathWithoutSlash = String(path.dropFirst())
                
                // 使用完整路径作为文件名（因为实际文件名是 {userId}.{fileId}.{extension}）
                searchFileName = pathWithoutSlash
                
                // 如果包含点号，可能是 {userId}.{fileId} 格式，提取 fileId 部分
                if let lastDotIndex = pathWithoutSlash.lastIndex(of: ".") {
                    // 提取点号后的部分作为 fileId
                    let potentialFileId = String(pathWithoutSlash[pathWithoutSlash.index(after: lastDotIndex)...])
                    // 验证是否是有效的文件ID格式（通常包含字母和数字，长度大于10）
                    if potentialFileId.count > 10 && potentialFileId.allSatisfy({ $0.isLetter || $0.isNumber }) {
                        fileId = potentialFileId
                        print("[ImageURLSchemeHandler] 从路径 \(path) 提取文件ID: \(potentialFileId)")
                    } else {
                        // 如果点号后的部分看起来不像文件ID，使用整个路径作为 fileId
                        fileId = pathWithoutSlash
                        print("[ImageURLSchemeHandler] 使用完整路径作为文件ID: \(pathWithoutSlash)")
                    }
                } else {
                    // 没有点号，直接使用路径作为 fileId
                    fileId = pathWithoutSlash
                    print("[ImageURLSchemeHandler] 使用路径作为文件ID: \(pathWithoutSlash)")
                }
            }
            
            guard let fileName = searchFileName, !fileName.isEmpty else {
                urlSchemeTask.didFailWithError(NSError(domain: "ImageURLSchemeHandler", code: 404, userInfo: [NSLocalizedDescriptionKey: "无效的图片URL路径: \(path)"]))
                return
            }
            
            print("[ImageURLSchemeHandler] 解析图片URL: 路径=\(path), 文件名=\(fileName), 文件ID=\(fileId ?? "无")")
            
            // 从本地存储加载图片数据
            // 尝试多种方式加载图片：
            // 1. 从 images/ 目录直接查找完整文件名（支持 {userId}.{fileId}.{extension} 格式）
            // 2. 使用新的 loadImage 方法（需要 fileType，仅 fileId）
            // 3. 尝试从 images/图片/ 目录加载（特殊目录）
            // 4. 使用旧的 getImage 方法（需要 folderId）
            
            var imageData: Data? = nil
            var contentType = "image/jpeg"
            
            let fileManager = FileManager.default
            let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appBundleID = Bundle.main.bundleIdentifier ?? "com.minote.MiNoteMac"
            let documentsDirectory = appSupportURL.appendingPathComponent(appBundleID)
            let imagesDirectory = documentsDirectory.appendingPathComponent("images")
            let imageFormats = ["jpg", "jpeg", "png", "gif"]
            
            // 首先尝试从 images/ 目录直接查找完整文件名（支持 {userId}.{fileId}.{extension} 格式）
            // 例如：1315204657.32PrHDJQJF1XECFIuBhVYw.jpeg
            if fileManager.fileExists(atPath: imagesDirectory.path) {
                for format in imageFormats {
                    let fileURL = imagesDirectory.appendingPathComponent("\(fileName).\(format)")
                    if fileManager.fileExists(atPath: fileURL.path) {
                        if let data = try? Data(contentsOf: fileURL) {
                            imageData = data
                            contentType = format == "png" ? "image/png" : 
                                         format == "gif" ? "image/gif" : 
                                         "image/jpeg"
                            print("[ImageURLSchemeHandler] 从 images/ 目录加载图片: \(fileName).\(format)")
                            break
                        }
                    }
                }
            }
            
            // 如果失败，尝试使用新的 loadImage 方法（仅 fileId，不需要 userId）
            if imageData == nil, let id = fileId {
                let localStorage = LocalStorageService.shared
                for format in imageFormats {
                    if let data = localStorage.loadImage(fileId: id, fileType: format) {
                        imageData = data
                        contentType = format == "png" ? "image/png" : 
                                     format == "gif" ? "image/gif" : 
                                     "image/jpeg"
                        print("[ImageURLSchemeHandler] 使用 loadImage 方法加载图片: \(id).\(format)")
                        break
                    }
                }
            }
            
            // 如果失败，尝试从 images/图片/ 目录加载（特殊目录）
            if imageData == nil {
                let specialImageDirectory = imagesDirectory.appendingPathComponent("图片")
                if fileManager.fileExists(atPath: specialImageDirectory.path) {
                    for format in imageFormats {
                        let fileURL = specialImageDirectory.appendingPathComponent("\(fileName).\(format)")
                        if fileManager.fileExists(atPath: fileURL.path) {
                            if let data = try? Data(contentsOf: fileURL) {
                                imageData = data
                                contentType = format == "png" ? "image/png" : 
                                             format == "gif" ? "image/gif" : 
                                             "image/jpeg"
                                print("[ImageURLSchemeHandler] 从特殊目录 images/图片/ 加载图片: \(fileName).\(format)")
                                break
                            }
                        }
                    }
                }
            }
            
            // 如果失败，尝试从数据库查找笔记的 folderId（使用旧的 getImage 方法）
            if imageData == nil, let id = fileId {
                let localStorage = LocalStorageService.shared
                // 尝试从所有可能的文件夹中查找图片
                // 这是一个回退方案，性能可能不是最优
                do {
                    let notes = try localStorage.getAllLocalNotes()
                    for note in notes {
                        if let data = localStorage.getImage(imageId: id, folderId: note.folderId) {
                            imageData = data
                            contentType = "image/jpeg"
                            print("[ImageURLSchemeHandler] 从文件夹 \(note.folderId) 加载图片: \(id)")
                            break
                        }
                    }
                } catch {
                    print("[ImageURLSchemeHandler] 查找图片时出错: \(error)")
                }
            }
            
            // 如果找到了图片数据，返回它
            if let imageData = imageData {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": contentType,
                        "Content-Length": "\(imageData.count)"
                    ]
                )!
                
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(imageData)
                urlSchemeTask.didFinish()
                return
            }
            
            // 如果找不到图片，返回占位图片
            print("[ImageURLSchemeHandler] 未找到图片: \(fileName)，返回占位图片")
                let placeholderImage = NSImage(systemSymbolName: "photo", accessibilityDescription: "图片") ?? NSImage()
                
            if let placeholderData = placeholderImage.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: placeholderData),
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
            } else {
                urlSchemeTask.didFailWithError(NSError(domain: "ImageURLSchemeHandler", code: 404, userInfo: [NSLocalizedDescriptionKey: "图片未找到: \(fileName)"]))
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
