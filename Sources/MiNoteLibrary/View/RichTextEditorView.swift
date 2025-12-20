import SwiftUI
import RichTextKit
import Foundation
import Combine

/// PreferenceKey 用于在视图层次中传递 RichTextContext
@available(macOS 14.0, *)
struct RichTextContextPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: RichTextContext? = nil
    
    static func reduce(value: inout RichTextContext?, nextValue: () -> RichTextContext?) {
        value = nextValue() ?? value
    }
}

// PreferenceKey 和 Reader 已移除，改用直接回调方式

/// 基于RichTextKit的富文本编辑器
/// 
/// 这是新的编辑器实现，使用RichTextKit框架替代原有的NSTextView包装器
/// 提供更好的SwiftUI集成和更简洁的API
/// 
/// **特性**：
/// - 原生SwiftUI支持
/// - 丰富的格式操作API
/// - 更好的性能和用户体验
@available(macOS 14.0, *)
struct RichTextEditorView: View {
    /// 绑定的富文本内容
    @Binding var text: NSAttributedString
    
    /// 是否可编辑
    @Binding var isEditable: Bool
    
    /// 笔记原始数据（用于图片加载等）
    var noteRawData: [String: Any]? = nil
    
    /// 格式操作回调
    var onFormatAction: ((FormatAction) -> Void)? = nil
    
    /// 内容变化回调
    var onContentChange: ((NSAttributedString) -> Void)? = nil
    
    @State private var lastKnownAttributedString: NSAttributedString = NSAttributedString()
    @State private var contentCheckTimer: Timer?
    @State private var timerLastText: NSAttributedString = NSAttributedString()
    
    /// 格式操作类型
    enum FormatAction {
        case bold
        case italic
        case underline
        case strikethrough
        case heading(Int)
        case highlight
        case textAlignment(NSTextAlignment)
    }
    
    var body: some View {
        RichTextEditor(
            text: $text,
            context: context,
            format: .archivedData,  // 使用 archivedData 格式支持图片附件
            viewConfiguration: { textView in
                // 配置图片支持，确保图片附件能正确显示
                textView.imageConfiguration = .init(
                    pasteConfiguration: .enabled,  // 启用粘贴图片
                    dropConfiguration: .enabled,   // 启用拖拽图片
                    maxImageSize: (
                        width: .points(600),       // 最大宽度 600pt
                        height: .points(800)       // 最大高度 800pt
                    )
                )
                
                // 确保撤销功能已启用（默认已启用，这里显式设置以确保）
                #if macOS
                if let nsTextView = textView as? NSTextView {
                    nsTextView.allowsUndo = true
                }
                #endif
            }
        )
        .richTextEditorStyle(.standard)
        .richTextEditorConfig(
            .init(
                isScrollingEnabled: true,  // 启用内部滚动，让编辑器能够正常工作
                isScrollBarsVisible: false,  // 隐藏滚动条，避免显示两个滚动条
                isContinuousSpellCheckingEnabled: true
            )
        )
        .disabled(!isEditable)
        .preference(key: RichTextContextPreferenceKey.self, value: context)
        .onChange(of: text) { oldValue, newValue in
            // 当 text binding 变化时（例如从外部加载内容或用户输入），直接保存
            lastKnownAttributedString = newValue
            
            // 使用 context 的 setAttributedString 方法更新编辑器
            // 因为直接改变 binding 不会更新编辑器（RichTextKit 已知问题）
            context.setAttributedString(to: newValue)
            
            // 直接触发内容变化回调
            onContentChange?(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didChangeNotification)) { notification in
            // 监听 NSTextView 的文本变化通知（macOS）
            // 直接保存，不进行比较
            guard let textView = notification.object as? NSTextView else {
                return
            }
            
            let newText = textView.attributedString()
            
            // 更新 lastKnownAttributedString
            lastKnownAttributedString = newText
            
            // 更新 text binding（这会触发 onChange）
            text = newText
            
            // 直接触发回调（这是主要的数据流，触发保存）
            onContentChange?(newText)
        }
        .onChange(of: context.styles) { oldValue, newValue in
            // 当格式状态变化时（加粗、斜体、下划线、删除线等），触发保存
            let boldChanged = (oldValue[RichTextStyle.bold] ?? false) != (newValue[RichTextStyle.bold] ?? false)
            let italicChanged = (oldValue[RichTextStyle.italic] ?? false) != (newValue[RichTextStyle.italic] ?? false)
            let underlineChanged = (oldValue[RichTextStyle.underlined] ?? false) != (newValue[RichTextStyle.underlined] ?? false)
            let strikethroughChanged = (oldValue[RichTextStyle.strikethrough] ?? false) != (newValue[RichTextStyle.strikethrough] ?? false)
            
            guard boldChanged || italicChanged || underlineChanged || strikethroughChanged else {
                return
            }
            
            // 格式变化时，从 text binding 或 context 获取最新内容
            let currentText = text.length > 0 ? text : context.attributedString
            
            // 更新状态
            lastKnownAttributedString = currentText
            text = currentText
            
            // 触发保存
            onContentChange?(currentText)
        }
        .onChange(of: context.selectedRange) { oldValue, newValue in
            // 当选中范围变化时，RichTextCoordinator 会同步格式状态
            print("🔄 [RichTextEditorView] context.selectedRange 变化: location=\(newValue.location), length=\(newValue.length)")
        }
        .task {
            // 使用 task 确保在视图完全加载后再设置内容，避免在视图更新过程中发布更改
            print("[RichTextEditorView] task 开始，设置初始文本，长度: \(text.length)")
            print("[RichTextEditorView] context 实例: \(context)")
            print("[RichTextEditorView] 文本内容预览: '\(text.string.prefix(100))'")
            // 等待一小段时间确保视图完全初始化
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒
            // 无论文本是否为空，都设置到 context，确保编辑器初始化
            context.setAttributedString(to: text)
            lastKnownAttributedString = text
            if text.length == 0 {
                print("[RichTextEditorView] ⚠️ 初始文本为空")
            } else {
                print("[RichTextEditorView] ✅ 初始文本已设置到 context，长度: \(text.length)")
            }
            
            // 启动定时器定期检查 context.attributedString 的变化（备用方案）
            startContentCheckTimer()
        }
        .onDisappear {
            // 停止定时器
            contentCheckTimer?.invalidate()
            contentCheckTimer = nil
        }
    }
    
    // MARK: - RichTextKit Context
    
    /// RichTextKit上下文，管理编辑器的状态和操作
    /// 必须从外部传入，确保与 FormatMenuView 使用同一个实例
    @ObservedObject var context: RichTextContext
    
    init(
        text: Binding<NSAttributedString>,
        isEditable: Binding<Bool>,
        context: RichTextContext,
        noteRawData: [String: Any]? = nil,
        onFormatAction: ((FormatAction) -> Void)? = nil,
        onContentChange: ((NSAttributedString) -> Void)? = nil
    ) {
        self._text = text
        self._isEditable = isEditable
        self._context = ObservedObject(wrappedValue: context)
        self.noteRawData = noteRawData
        self.onFormatAction = onFormatAction
        self.onContentChange = onContentChange
    }
    
    /// 设置RichTextKit上下文
    private func setupContext() {
        // 配置上下文选项
        // 初始化时设置文本内容
        context.setAttributedString(to: text)
    }
    
    /// 启动内容检查定时器（备用方案，确保能捕获所有内容变化）
    /// 根据 RichTextKit 文档，text binding 应该会自动更新，但为了确保万无一失，我们添加定时器检查
    private func startContentCheckTimer() {
        contentCheckTimer?.invalidate()
        let contextRef = context  // 捕获 context 引用（RichTextContext 是 class）
        let textBinding = _text   // 捕获 Binding 的 ProjectedValue
        let onContentChangeRef = onContentChange  // 捕获回调
        
        // 初始化 timerLastText
        timerLastText = lastKnownAttributedString
        
        contentCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak contextRef] _ in
            guard let contextRef = contextRef else { return }
            let currentText = contextRef.attributedString
            
            // 在主线程上安全地访问和更新状态
            DispatchQueue.main.async {
                // 检查内容是否变化
                if currentText.string != self.timerLastText.string || currentText.length != self.timerLastText.length {
                    print("[RichTextEditorView] 📝 定时器检测到内容变化")
                    print("[RichTextEditorView] 旧长度: \(self.timerLastText.length), 新长度: \(currentText.length)")
                    print("[RichTextEditorView] 新内容预览: '\(currentText.string.prefix(50))'")
                    // 更新 text binding（这会触发 onChange(of: text)）
                    textBinding.wrappedValue = currentText
                    self.timerLastText = currentText
                    self.lastKnownAttributedString = currentText
                    // 触发回调（双重保险）
                    print("[RichTextEditorView] ✅ 从定时器调用 onContentChange 回调")
                    onContentChangeRef?(currentText)
                }
            }
        }
    }
}

/// RichTextKit编辑器的SwiftUI包装器
/// 
/// 提供与现有代码兼容的接口，内部使用RichTextKit
/// 支持RTF数据和XML格式的双向转换
@available(macOS 14.0, *)
struct RichTextEditorWrapper: View {
    /// 存档数据绑定（使用 archivedData 格式以支持图片附件）
    @Binding var rtfData: Data?  // 保持名称兼容，但实际使用 archivedData
    
    /// 是否可编辑
    @Binding var isEditable: Bool
    
    /// 笔记原始数据（用于XML转换和图片加载）
    var noteRawData: [String: Any]? = nil
    
    /// XML内容（用于向后兼容，当没有RTF数据时使用）
    var xmlContent: String? = nil
    
    /// 格式操作回调
    var onFormatAction: ((MiNoteEditor.FormatAction) -> Void)? = nil
    
    /// 内容变化回调
    var onContentChange: ((Data?) -> Void)? = nil
    
    /// Context 变化回调（用于格式栏同步）
    var onContextChange: ((RichTextContext) -> Void)? = nil
    
    /// RichTextContext（用于格式栏同步）- 从外部传入
    var editorContext: RichTextContext
    
    @State private var attributedText: NSAttributedString = NSAttributedString()
    @State private var lastRTFData: Data? = nil
    @State private var lastXMLContent: String? = nil  // 跟踪 XML 内容，避免重复加载
    
    init(
        rtfData: Binding<Data?>,
        isEditable: Binding<Bool>,
        editorContext: RichTextContext,
        noteRawData: [String: Any]? = nil,
        xmlContent: String? = nil,
        onFormatAction: ((MiNoteEditor.FormatAction) -> Void)? = nil,
        onContentChange: ((Data?) -> Void)? = nil,
        onContextChange: ((RichTextContext) -> Void)? = nil
    ) {
        self._rtfData = rtfData
        self._isEditable = isEditable
        self.editorContext = editorContext
        self.noteRawData = noteRawData
        self.xmlContent = xmlContent
        self.onFormatAction = onFormatAction
        self.onContentChange = onContentChange
        self.onContextChange = onContextChange
    }
    
    var body: some View {
        RichTextEditorView(
            text: $attributedText,
            isEditable: $isEditable,
            context: editorContext,
            noteRawData: noteRawData,
            onFormatAction: { action in
                handleFormatAction(action)
            },
            onContentChange: { newText in
                handleContentChange(newText)
            }
        )
        .task {
            // 使用 task 确保在视图完全加载后再处理
            print("[RichTextEditorWrapper] task 开始，加载内容")
            loadContent()
            // 等待一小段时间让内容加载完成
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒
            // 加载内容后，确保设置到 context（在异步任务中，避免在视图更新过程中发布更改）
            if attributedText.length > 0 {
                print("[RichTextEditorWrapper] 内容已加载，设置到 context，长度: \(attributedText.length)")
                editorContext.setAttributedString(to: attributedText)
            }
            // 通知外部 context 已准备好
            onContextChange?(editorContext)
        }
        .onChange(of: editorContext.styles) { oldValue, newValue in
            // 当格式状态变化时，通知外部（触发格式栏更新）
            // 使用 Task 避免在视图更新过程中发布更改
            Task { @MainActor in
                onContextChange?(editorContext)
            }
        }
        .onChange(of: rtfData) { oldValue, newValue in
            // 只在RTF数据真正改变时重新加载
            if newValue != oldValue && newValue != lastRTFData {
                print("[RichTextEditorWrapper] RTF数据变化，重新加载内容")
                loadContent()
            }
        }
        .onChange(of: xmlContent) { oldValue, newValue in
            // 如果XML内容变化，从XML重新加载（确保包含所有附件）
            if let xml = newValue, xml != oldValue, !xml.isEmpty {
                print("[RichTextEditorWrapper] XML内容变化，重新加载（优先使用XML以包含图片等附件）")
                loadFromXML(xml)
            }
        }
        .onChange(of: attributedText) { oldValue, newValue in
            // 当 attributedText 改变时，确保编辑器更新
            // 这个 onChange 会在 loadContent 后触发，确保内容被正确设置
            if oldValue.string != newValue.string || oldValue.length != newValue.length {
                print("[RichTextEditorWrapper] attributedText 内容变化: '\(oldValue.string.prefix(50))' -> '\(newValue.string.prefix(50))'")
                print("[RichTextEditorWrapper] 旧长度: \(oldValue.length), 新长度: \(newValue.length)")
                // 使用 Task 避免在视图更新过程中发布更改
                // 注意：RichTextEditor 从 text binding 读取内容，所以需要同时更新 context 和 text binding
                Task { @MainActor in
                    editorContext.setAttributedString(to: newValue)
                }
            }
        }
    }
    
    /// 加载内容（优先使用存档数据，否则使用XML）
    private func loadContent() {
        print("[RichTextEditorWrapper] 开始加载内容...")
        print("[RichTextEditorWrapper] rtfData (archivedData): \(rtfData != nil ? "存在(\(rtfData!.count)字节)" : "不存在")")
        print("[RichTextEditorWrapper] xmlContent: \(xmlContent != nil ? "存在(\(xmlContent!.count)字符)" : "不存在")")
        
        // 优先从 archivedData 加载（支持图片附件）
        if let archivedData = rtfData {
            do {
                // 尝试使用 RichTextKit 的方式加载 archivedData
                let loadedText = try NSAttributedString(data: archivedData, format: .archivedData)
                attributedText = loadedText
                lastRTFData = archivedData
                print("[RichTextEditorWrapper] ✅ 从 archivedData 加载内容，长度: \(loadedText.length)")
                print("[RichTextEditorWrapper] 文本内容预览: \(loadedText.string.prefix(100))")
                // 检查是否包含附件
                var attachmentCount = 0
                loadedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: loadedText.length), options: []) { (value, _, _) in
                    if value != nil { attachmentCount += 1 }
                }
                print("[RichTextEditorWrapper] 附件数量: \(attachmentCount)")
                return
            } catch {
                print("[RichTextEditorWrapper] ⚠️ archivedData 解析失败: \(error)")
                // 如果解析失败，尝试从 XML 加载
            }
        }
        
        // 如果没有存档数据或解析失败，从 XML 转换（这样可以包含图片等附件）
        if let xml = xmlContent, !xml.isEmpty, xml != lastXMLContent {
            print("[RichTextEditorWrapper] 尝试从XML加载（包含图片等附件）...")
            loadFromXML(xml)
            lastXMLContent = xml
        } else if let xml = xmlContent, !xml.isEmpty {
            print("[RichTextEditorWrapper] XML内容未变化，跳过重新加载")
        } else {
            // 都没有，使用空内容
            attributedText = NSAttributedString(string: "")
            print("[RichTextEditorWrapper] ⚠️ 没有可用数据，使用空内容")
        }
    }
    
    /// 从XML内容加载
    private func loadFromXML(_ xml: String) {
        print("[RichTextEditorWrapper] 🖼️ ========== 从XML加载内容 ==========")
        print("[RichTextEditorWrapper] XML长度: \(xml.count)")
        print("[RichTextEditorWrapper] noteRawData: \(noteRawData != nil ? "存在" : "nil")")
        
        // 检查 noteRawData 中的图片信息
        if let rawData = noteRawData,
           let setting = rawData["setting"] as? [String: Any],
           let settingData = setting["data"] as? [[String: Any]] {
            print("！！！图片处理！！！ [RichTextEditorWrapper] 🖼️ noteRawData 包含 \(settingData.count) 个图片条目")
            for (index, imgData) in settingData.enumerated() {
                if let fileId = imgData["fileId"] as? String,
                   let mimeType = imgData["mimeType"] as? String {
                    print("！！！图片处理！！！ [RichTextEditorWrapper] 🖼️ 图片 #\(index + 1): fileId=\(fileId), mimeType=\(mimeType)")
                    // 检查图片是否存在
                    let fileType = String(mimeType.dropFirst("image/".count))
                    let exists = LocalStorageService.shared.imageExists(fileId: fileId, fileType: fileType)
                    print("！！！图片处理！！！ [RichTextEditorWrapper] 🖼️    存在: \(exists)")
                }
            }
        } else {
            print("！！！图片处理！！！ [RichTextEditorWrapper] 🖼️ ⚠️ noteRawData 中没有图片信息")
        }
        
        let loadedText = MiNoteContentParser.parseToAttributedString(xml, noteRawData: noteRawData)
        // 更新 attributedText，这会触发 RichTextEditorView 的 onChange
        attributedText = loadedText
        print("[RichTextEditorWrapper] ✅ 从XML加载内容，长度: \(loadedText.length)")
        print("[RichTextEditorWrapper] 文本内容预览: \(loadedText.string.prefix(100))")
        
        // 检查是否包含附件
        var attachmentCount = 0
        var imageAttachmentCount = 0
        loadedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: loadedText.length), options: []) { (value, range, _) in
            if value != nil {
                attachmentCount += 1
                if let attachment = value as? NSTextAttachment {
                    print("！！！图片处理！！！ [RichTextEditorWrapper] 🖼️ 附件 #\(attachmentCount): 类型=\(type(of: attachment)), 位置=\(range.location), bounds=\(attachment.bounds)")
                    if let imageAttachment = attachment as? RichTextImageAttachment {
                        imageAttachmentCount += 1
                        print("！！！图片处理！！！ [RichTextEditorWrapper]    - RichTextImageAttachment: image=\(imageAttachment.image != nil ? "存在" : "nil"), attachmentCell=\(imageAttachment.attachmentCell != nil ? "存在" : "nil")")
                    }
                }
            }
        }
        print("！！！图片处理！！！ [RichTextEditorWrapper] 🖼️ 附件统计: 总数=\(attachmentCount), 图片=\(imageAttachmentCount)")
        
        // 不在这里设置 context，让 onChange(of: attributedText) 处理，避免在视图更新过程中发布更改
        
        // 生成 archivedData 格式的数据（支持图片附件），而不是 RTF
        do {
            let archivedData = try loadedText.richTextData(for: .archivedData)
            self.rtfData = archivedData
            lastRTFData = archivedData
            print("[RichTextEditorWrapper] ✅ 生成 archivedData，长度: \(archivedData.count)字节")
        } catch {
            print("[RichTextEditorWrapper] ⚠️ 生成 archivedData 失败: \(error)")
            // 如果失败，尝试使用 NSKeyedArchiver
            if let archivedData = try? NSKeyedArchiver.archivedData(
                withRootObject: loadedText,
                requiringSecureCoding: false
        ) {
                self.rtfData = archivedData
                lastRTFData = archivedData
                print("[RichTextEditorWrapper] ✅ 使用 NSKeyedArchiver 生成 archivedData，长度: \(archivedData.count)字节")
            }
        }
    }
    
    /// 处理内容变化
    /// 
    /// 将编辑器内容转换为 archivedData 格式并触发回调。
    /// 不进行比较，直接更新并触发保存。
    /// 
    /// - Parameter newText: 新的 NSAttributedString 内容
    private func handleContentChange(_ newText: NSAttributedString) {
        // 将NSAttributedString转换为 archivedData 格式（支持图片附件）
        do {
            let archivedData = try newText.richTextData(for: .archivedData)
            
            // 更新状态
            self.rtfData = archivedData
            lastRTFData = archivedData
            attributedText = newText
            
            // 触发回调
            onContentChange?(archivedData)
        } catch {
            // 如果失败，尝试使用 NSKeyedArchiver
            if let archivedData = try? NSKeyedArchiver.archivedData(
                withRootObject: newText,
                requiringSecureCoding: false
            ) {
                self.rtfData = archivedData
                lastRTFData = archivedData
                attributedText = newText
                onContentChange?(archivedData)
            } else {
                print("[RichTextEditorWrapper] ⚠️ 无法生成 archivedData: \(error)")
            }
        }
    }
    
    /// 处理格式操作
    private func handleFormatAction(_ action: RichTextEditorView.FormatAction) {
        // 使用 RichTextContext 处理格式
        switch action {
        case .bold:
            editorContext.toggleStyle(RichTextStyle.bold)
        case .italic:
            editorContext.toggleStyle(RichTextStyle.italic)
        case .underline:
            editorContext.toggleStyle(RichTextStyle.underlined)
        case .strikethrough:
            editorContext.toggleStyle(RichTextStyle.strikethrough)
        case .heading(let level):
            // TODO: 实现标题样式
            print("[RichTextEditorWrapper] 标题样式暂未实现: level=\(level)")
        case .highlight:
            // TODO: 实现高亮
            print("[RichTextEditorWrapper] 高亮暂未实现")
        case .textAlignment(let alignment):
            editorContext.paragraphStyle.alignment = alignment
        }
        
        // 同时调用回调（向后兼容）
        let miNoteAction: MiNoteEditor.FormatAction?
        switch action {
        case .bold: miNoteAction = .bold
        case .italic: miNoteAction = .italic
        case .underline: miNoteAction = .underline
        case .strikethrough: miNoteAction = .strikethrough
        case .heading(let level): miNoteAction = .heading(level)
        case .highlight: miNoteAction = .highlight
        case .textAlignment(let alignment): miNoteAction = .textAlignment(alignment)
        }
        
        if let action = miNoteAction {
            onFormatAction?(action)
        }
    }
    
    /// 获取 RichTextContext（用于格式栏同步）
    var context: RichTextContext {
        editorContext
    }
}

