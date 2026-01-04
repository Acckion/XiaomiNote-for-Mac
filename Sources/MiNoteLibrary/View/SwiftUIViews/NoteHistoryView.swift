import SwiftUI
import WebKit
import OSLog

/// 笔记历史版本视图
/// 
/// 显示笔记的历史版本列表，支持查看和恢复历史版本
@available(macOS 14.0, *)
struct NoteHistoryView: View {
    @ObservedObject var viewModel: NotesViewModel
    let noteId: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var historyVersions: [NoteHistoryVersion] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var selectedVersion: NoteHistoryVersion?
    @State private var versionContent: Note?
    @State private var isLoadingContent: Bool = false
    @State private var isRestoring: Bool = false
    @State private var restoreError: String?
    
    // 日志记录器
    private let logger = Logger(subsystem: "com.xiaomi.minote.mac", category: "NoteHistoryView")
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack {
                Text("历史版本")
                    .font(.headline)
                    .padding(.leading, 16)
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .padding(.trailing, 16)
            }
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )
            
            // 主内容区域
            HSplitView {
                // 左侧：历史版本列表
                leftPanel
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
                
                // 右侧：预览区域
                rightPanel
                    .frame(minWidth: 400)
            }
        }
        .alert("恢复历史版本", isPresented: .constant(isRestoring && restoreError == nil)) {
            Button("取消", role: .cancel) {
                isRestoring = false
            }
        } message: {
            Text("正在恢复历史版本...")
        }
        .alert("恢复失败", isPresented: .constant(restoreError != nil)) {
            Button("确定", role: .cancel) {
                restoreError = nil
            }
        } message: {
            if let error = restoreError {
                Text(error)
            }
        }
        .task {
            loadHistoryVersions()
        }
        .frame(width: 1000, height: 700)
    }
    
    // MARK: - 左侧面板
    
    @ViewBuilder
    private var leftPanel: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView("加载历史版本...")
                    Text("正在加载...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("加载失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("重试") {
                        loadHistoryVersions()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if historyVersions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("暂无历史版本")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(historyVersions) { version in
                            HistoryVersionRow(
                                version: version,
                                isSelected: selectedVersion?.id == version.id,
                                onRestore: {
                                    restoreVersion(version)
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedVersion = version
                            }
                            .background(
                                selectedVersion?.id == version.id
                                    ? Color.accentColor.opacity(0.1)
                                    : Color.clear
                            )
                        }
                    }
                }
            }
        }
        .onChange(of: selectedVersion) { oldValue, newValue in
            if let version = newValue {
                viewVersion(version)
            }
        }
    }
    
    // MARK: - 右侧面板
    
    @ViewBuilder
    private var rightPanel: some View {
        Group {
            if selectedVersion == nil {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("选择一个历史版本查看内容")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoadingContent {
                VStack(spacing: 16) {
                    ProgressView("加载内容...")
                    Text("正在加载版本内容...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let content = versionContent {
                VersionPreviewView(
                    version: selectedVersion,
                    note: content,
                    onRestore: {
                        if let version = selectedVersion {
                            restoreVersion(version)
                        }
                    }
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("无法加载内容")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private func loadHistoryVersions() {
        logger.info("开始加载历史版本列表，noteId: \(self.noteId)")
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let versions = try await viewModel.getNoteHistoryTimes(noteId: noteId)
                await MainActor.run {
                    self.historyVersions = versions
                    self.isLoading = false
                    self.logger.info("成功加载历史版本列表，共 \(versions.count) 个版本")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.logger.error("加载历史版本列表失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func viewVersion(_ version: NoteHistoryVersion) {
        logger.info("开始加载历史版本内容，version: \(version.version), noteId: \(self.noteId)")
        isLoadingContent = true
        versionContent = nil
        
        Task {
            do {
                let note = try await viewModel.getNoteHistory(noteId: noteId, version: version.version)
                await MainActor.run {
                    self.versionContent = note
                    self.isLoadingContent = false
                    self.logger.info("成功加载历史版本内容，标题: \(note.title), 内容长度: \(note.content.count) 字符")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载版本内容失败: \(error.localizedDescription)"
                    self.isLoadingContent = false
                    self.logger.error("加载历史版本内容失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func restoreVersion(_ version: NoteHistoryVersion) {
        isRestoring = true
        restoreError = nil
        
        Task {
            do {
                try await viewModel.restoreNoteHistory(noteId: noteId, version: version.version)
                await MainActor.run {
                    isRestoring = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    restoreError = error.localizedDescription
                }
            }
        }
    }
}

/// 历史版本行视图
@available(macOS 14.0, *)
private struct HistoryVersionRow: View {
    let version: NoteHistoryVersion
    let isSelected: Bool
    let onRestore: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(version.formattedUpdateTime)
                    .font(.headline)
                Text("版本: \(version.version)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                onRestore()
            } label: {
                Text("恢复")
            }
            .buttonStyle(.bordered)
            .help("恢复此版本")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

/// 版本预览视图（右侧面板）
@available(macOS 14.0, *)
private struct VersionPreviewView: View {
    let version: NoteHistoryVersion?
    let note: Note
    let onRestore: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                if let version = version {
                    Text("版本时间: \(version.formattedUpdateTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    onRestore()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("恢复此版本")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
            
            // 内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(note.title)
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    // 使用 WebView 显示 HTML 内容
                    if !note.content.isEmpty {
                        HistoryContentWebView(content: note.content)
                            .frame(minHeight: 400)
                    } else {
                        Text("此版本暂无内容")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 历史版本内容 WebView（只读）
@available(macOS 14.0, *)
struct HistoryContentWebView: NSViewRepresentable {
    let content: String
    
    // 日志记录器
    private let logger = Logger(subsystem: "com.xiaomi.minote.mac", category: "HistoryContentWebView")
    
    func makeNSView(context: Context) -> WKWebView {
        logger.info("创建 WebView，内容长度: \(self.content.count) 字符")
        
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // 添加消息处理器来接收 JavaScript 错误和日志
        userContentController.add(context.coordinator, name: "historyViewBridge")
        config.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // 加载 XML 转换器脚本
        context.coordinator.loadConverterScript { script in
            context.coordinator.converterScript = script
            if script.isEmpty {
                self.logger.error("转换器脚本为空，无法转换 XML 内容")
            } else {
                self.logger.info("转换器脚本加载成功，长度: \(script.count) 字符")
            }
            self.loadContent(webView: webView, xmlContent: self.content, converterScript: script)
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // 当内容改变时，重新加载
        let script = context.coordinator.converterScript
        if !script.isEmpty {
            logger.info("内容已更新，重新加载，新内容长度: \(self.content.count) 字符")
            loadContent(webView: nsView, xmlContent: content, converterScript: script)
        } else {
            logger.warning("转换器脚本未加载，跳过内容更新")
        }
    }
    
    private func loadContent(webView: WKWebView, xmlContent: String, converterScript: String) {
        logger.debug("开始加载内容到 WebView，XML 长度: \(xmlContent.count) 字符")
        
        // 转义 XML 内容以便在 JavaScript 中使用
        let escapedContent = xmlContent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        // 创建 HTML 模板，包含转换器脚本和转换逻辑
        let htmlTemplate = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                :root {
                    color-scheme: light dark;
                }
                
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 14px;
                    line-height: 1.6;
                    color: #333;
                    padding: 20px;
                    max-width: 800px;
                    margin: 0 auto;
                    background-color: #ffffff;
                }
                
                @media (prefers-color-scheme: dark) {
                    body {
                        color: #e5e5e5;
                        background-color: #1e1e1e;
                    }
                    
                    pre {
                        background-color: #2d2d2d;
                        color: #e5e5e5;
                    }
                    
                    code {
                        background-color: #2d2d2d;
                        color: #e5e5e5;
                    }
                    
                    blockquote {
                        border-left-color: #666;
                        color: #b3b3b3;
                    }
                    
                    h1, h2, h3, h4, h5, h6 {
                        color: #e5e5e5;
                    }
                }
                
                img {
                    max-width: 100%;
                    height: auto;
                }
                
                pre {
                    background-color: #f5f5f5;
                    padding: 10px;
                    border-radius: 4px;
                    overflow-x: auto;
                }
                
                code {
                    background-color: #f5f5f5;
                    padding: 2px 4px;
                    border-radius: 3px;
                    font-family: 'Monaco', 'Menlo', monospace;
                }
                
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 1em;
                    margin-bottom: 0.5em;
                    font-weight: 600;
                }
                
                p {
                    margin: 0.5em 0;
                }
                
                ul, ol {
                    margin: 0.5em 0;
                    padding-left: 2em;
                }
                
                blockquote {
                    margin: 0.5em 0;
                    padding-left: 1em;
                    border-left: 3px solid #ddd;
                    color: #666;
                }
            </style>
            <script>
                \(converterScript)
                
                // 转换 XML 内容（在 DOM 加载完成后执行）
                function convertContent() {
                    try {
                        console.log('[HistoryView] 开始转换 XML 内容');
                        const xmlContent = `\(escapedContent)`;
                        console.log('[HistoryView] XML 内容长度:', xmlContent.length);
                        
                        if (typeof XMLToHTMLConverter === 'undefined') {
                            throw new Error('XMLToHTMLConverter 类未定义');
                        }
                        
                        const converter = new XMLToHTMLConverter();
                        const htmlContent = converter.convert(xmlContent);
                        console.log('[HistoryView] 转换成功，HTML 长度:', htmlContent.length);
                        
                        document.body.innerHTML = htmlContent;
                        
                        // 通知原生代码转换成功
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.historyViewBridge) {
                            window.webkit.messageHandlers.historyViewBridge.postMessage({
                                type: 'conversionSuccess',
                                htmlLength: htmlContent.length
                            });
                        }
                    } catch (error) {
                        console.error('[HistoryView] 转换XML失败:', error);
                        const errorMsg = error.message || String(error);
                        document.body.innerHTML = '<p style="color: red; padding: 20px;">加载内容失败: ' + errorMsg + '</p>';
                        
                        // 通知原生代码转换失败
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.historyViewBridge) {
                            window.webkit.messageHandlers.historyViewBridge.postMessage({
                                type: 'conversionError',
                                error: errorMsg
                            });
                        }
                    }
                }
                
                // 等待 DOM 加载完成后再执行转换
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', convertContent);
                } else {
                    // DOM 已经加载完成，立即执行
                    convertContent();
                }
            </script>
        </head>
        <body>
            <p>正在加载内容...</p>
        </body>
        </html>
        """
        
        webView.loadHTMLString(htmlTemplate, baseURL: nil)
        logger.debug("HTML 模板已加载到 WebView")
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(logger: logger)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var converterScript: String = ""
        private let logger: Logger
        
        init(logger: Logger) {
            self.logger = logger
        }
        
        func loadConverterScript(completion: @escaping (String) -> Void) {
            // 如果已经加载过，直接返回
            if !converterScript.isEmpty {
                logger.debug("使用已缓存的转换器脚本")
                completion(converterScript)
                return
            }
            
            logger.info("开始加载 xml-to-html.js 转换器脚本")
            
            // 尝试从 bundle 加载 xml-to-html.js
            let bundle = Bundle(for: HistoryContentWebView.Coordinator.self)
            var scriptURL: URL? = nil
            
            // 尝试多种路径
            if let url = bundle.url(forResource: "xml-to-html", withExtension: "js") {
                scriptURL = url
                logger.debug("找到脚本文件: \(url.path)")
            } else if let resourceURL = bundle.resourceURL {
                let webURL = resourceURL.appendingPathComponent("xml-to-html.js")
                if FileManager.default.fileExists(atPath: webURL.path) {
                    scriptURL = webURL
                    logger.debug("找到脚本文件: \(webURL.path)")
                } else {
                    logger.warning("在资源目录中未找到 xml-to-html.js: \(webURL.path)")
                }
            }
            
            if let scriptURL = scriptURL {
                do {
                    let script = try String(contentsOf: scriptURL, encoding: .utf8)
                    self.converterScript = script
                    logger.info("成功加载转换器脚本，长度: \(script.count) 字符")
                    completion(script)
                } catch {
                    logger.error("读取转换器脚本失败: \(error.localizedDescription)")
                    completion("")
                }
            } else {
                logger.error("无法找到 xml-to-html.js 脚本文件")
                completion("")
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // 允许所有导航（只读视图）
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logger.info("WebView 页面加载完成")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("WebView 页面加载失败: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("WebView 临时导航失败: \(error.localizedDescription)")
        }
        
        // WKScriptMessageHandler 实现
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "historyViewBridge" else { return }
            
            if let body = message.body as? [String: Any] {
                if let type = body["type"] as? String {
                    switch type {
                    case "conversionSuccess":
                        if let htmlLength = body["htmlLength"] as? Int {
                            logger.info("JavaScript 转换成功，HTML 长度: \(htmlLength) 字符")
                        }
                    case "conversionError":
                        if let error = body["error"] as? String {
                            logger.error("JavaScript 转换失败: \(error)")
                        }
                    default:
                        logger.debug("收到未知消息类型: \(type)")
                    }
                }
            }
        }
    }
}



