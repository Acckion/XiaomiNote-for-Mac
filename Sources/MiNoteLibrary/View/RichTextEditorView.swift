import SwiftUI
import RichTextKit
import Foundation

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
            context: context
        )
        .richTextEditorStyle(.standard)
        .disabled(!isEditable)
        .preference(key: RichTextContextPreferenceKey.self, value: context)
        .onChange(of: text) { oldValue, newValue in
            // 避免循环更新 - 比较字符串内容而不是对象引用
            if oldValue.string != newValue.string || oldValue.length != newValue.length {
                print("[RichTextEditorView] 文本内容变化，更新编辑器")
                print("[RichTextEditorView] 旧长度: \(oldValue.length), 新长度: \(newValue.length)")
                print("[RichTextEditorView] 新内容预览: \(newValue.string.prefix(50))")
                // 使用 context 的 setAttributedString 方法更新编辑器
                // 因为直接改变 binding 不会更新编辑器（RichTextKit 已知问题）
                context.setAttributedString(to: newValue)
                onContentChange?(newValue)
            }
        }
        .onChange(of: context.styles) { oldValue, newValue in
            // 当格式状态变化时（光标移动或选择改变），RichTextCoordinator 会自动同步
            // FormatMenuView 通过 @ObservedObject 会自动更新
            print("🔄 [RichTextEditorView] context.styles 变化:")
            print("   - 加粗: \(newValue[RichTextStyle.bold] ?? false)")
            print("   - 斜体: \(newValue[RichTextStyle.italic] ?? false)")
            print("   - 下划线: \(newValue[RichTextStyle.underlined] ?? false)")
            print("   - 删除线: \(newValue[RichTextStyle.strikethrough] ?? false)")
        }
        .onChange(of: context.selectedRange) { oldValue, newValue in
            // 当选中范围变化时，RichTextCoordinator 会同步格式状态
            print("🔄 [RichTextEditorView] context.selectedRange 变化: location=\(newValue.location), length=\(newValue.length)")
        }
        .onAppear {
            setupContext()
            // 初始化时设置文本内容
            print("[RichTextEditorView] onAppear，设置初始文本，长度: \(text.length)")
            print("[RichTextEditorView] context 实例: \(context)")
            if text.length > 0 {
                context.setAttributedString(to: text)
            } else {
                print("[RichTextEditorView] ⚠️ 初始文本为空")
            }
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
}

/// RichTextKit编辑器的SwiftUI包装器
/// 
/// 提供与现有代码兼容的接口，内部使用RichTextKit
/// 支持RTF数据和XML格式的双向转换
@available(macOS 14.0, *)
struct RichTextEditorWrapper: View {
    /// RTF数据绑定（用于与现有代码兼容）
    @Binding var rtfData: Data?
    
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
        .onAppear {
            // 先加载内容
            loadContent()
            // 通知外部 context 已准备好
            onContextChange?(editorContext)
        }
        .onChange(of: editorContext.styles) { oldValue, newValue in
            // 当格式状态变化时，通知外部（触发格式栏更新）
            onContextChange?(editorContext)
        }
        .task {
            // 使用 task 确保在视图完全加载后再处理
            // 等待一小段时间让内容加载完成
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
            // 此时 attributedText 应该已经更新，RichTextEditorView 的 onChange 会处理
        }
        .onChange(of: rtfData) { oldValue, newValue in
            // 只在RTF数据真正改变时重新加载
            if newValue != oldValue && newValue != lastRTFData {
                print("[RichTextEditorWrapper] RTF数据变化，重新加载内容")
                loadContent()
            }
        }
        .onChange(of: xmlContent) { oldValue, newValue in
            // 如果提供了XML内容且没有RTF数据，从XML加载
            if let xml = newValue, rtfData == nil {
                print("[RichTextEditorWrapper] XML内容变化，重新加载")
                loadFromXML(xml)
            }
        }
        .onChange(of: attributedText) { oldValue, newValue in
            // 当 attributedText 改变时，确保编辑器更新
            // 这个 onChange 会在 loadContent 后触发，确保内容被正确设置
            if oldValue.string != newValue.string {
                print("[RichTextEditorWrapper] attributedText 内容变化: '\(oldValue.string.prefix(50))' -> '\(newValue.string.prefix(50))'")
            }
        }
    }
    
    /// 加载内容（优先使用RTF数据，否则使用XML）
    private func loadContent() {
        print("[RichTextEditorWrapper] 开始加载内容...")
        print("[RichTextEditorWrapper] rtfData: \(rtfData != nil ? "存在(\(rtfData!.count)字节)" : "不存在")")
        print("[RichTextEditorWrapper] xmlContent: \(xmlContent != nil ? "存在(\(xmlContent!.count)字符)" : "不存在")")
        
        if let rtfData = rtfData {
            // 从RTF数据加载
            if let loadedText = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                attributedText = loadedText
                lastRTFData = rtfData
                print("[RichTextEditorWrapper] ✅ 从RTF数据加载内容，长度: \(loadedText.length)")
                print("[RichTextEditorWrapper] 文本内容预览: \(loadedText.string.prefix(100))")
                return
            } else {
                print("[RichTextEditorWrapper] ⚠️ RTF数据解析失败")
            }
        }
        
        // 如果没有RTF数据，尝试从XML转换（向后兼容）
        if let xml = xmlContent, !xml.isEmpty {
            print("[RichTextEditorWrapper] 尝试从XML加载...")
            loadFromXML(xml)
        } else {
            // 都没有，使用空内容
            attributedText = NSAttributedString(string: "")
            print("[RichTextEditorWrapper] ⚠️ 没有可用数据，使用空内容")
        }
    }
    
    /// 从XML内容加载
    private func loadFromXML(_ xml: String) {
        print("[RichTextEditorWrapper] 从XML加载，XML长度: \(xml.count)")
        let loadedText = MiNoteContentParser.parseToAttributedString(xml, noteRawData: noteRawData)
        // 更新 attributedText，这会触发 RichTextEditorView 的 onChange
        attributedText = loadedText
        print("[RichTextEditorWrapper] ✅ 从XML加载内容，长度: \(loadedText.length)")
        print("[RichTextEditorWrapper] 文本内容预览: \(loadedText.string.prefix(100))")
        
        // 同时生成RTF数据并保存
        let rtfRange = NSRange(location: 0, length: loadedText.length)
        if let rtfData = try? loadedText.data(
            from: rtfRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            self.rtfData = rtfData
            lastRTFData = rtfData
            print("[RichTextEditorWrapper] ✅ 生成RTF数据，长度: \(rtfData.count)字节")
        } else {
            print("[RichTextEditorWrapper] ⚠️ 生成RTF数据失败")
        }
    }
    
    /// 处理内容变化
    private func handleContentChange(_ newText: NSAttributedString) {
        // 将NSAttributedString转换为RTF数据
        let rtfRange = NSRange(location: 0, length: newText.length)
        if let rtfData = try? newText.data(
            from: rtfRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            // 只在数据真正改变时更新
            if rtfData != lastRTFData {
                self.rtfData = rtfData
                lastRTFData = rtfData
                onContentChange?(rtfData)
                print("[RichTextEditorWrapper] 内容已更新，RTF数据长度: \(rtfData.count) 字节")
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

