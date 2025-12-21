//
//  NewRichTextEditor.swift
//  MiNoteMac
//
//  全新的富文本编辑器实现
//  参考 RichTextKit Demo，提供完善的编辑功能
//

import SwiftUI
import RichTextKit
import AppKit

/// 全新的富文本编辑器
/// 
/// 参考 RichTextKit Demo 实现，提供：
/// - 完整的格式工具栏（macOS）
/// - Inspector 侧边栏（格式面板）
/// - 图片附件支持
/// - 与现有保存逻辑兼容
@available(macOS 14.0, *)
struct NewRichTextEditor: View {
    
    // MARK: - Bindings
    
    /// RTF 数据绑定（使用 archivedData 格式以支持图片附件）
    @Binding var rtfData: Data?
    
    /// 是否可编辑
    @Binding var isEditable: Bool
    
    /// 笔记原始数据（用于图片加载等）
    var noteRawData: [String: Any]? = nil
    
    /// XML 内容（用于向后兼容）
    var xmlContent: String? = nil
    
    /// 内容变化回调
    var onContentChange: ((Data?) -> Void)? = nil
    
    /// 外部 context（可选，用于与格式菜单等组件同步）
    var externalContext: RichTextContext? = nil
    
    // MARK: - State
    
    /// RichTextContext - 编辑器上下文（可选，如果不提供则内部创建）
    @StateObject private var internalContext = RichTextContext()
    
    /// 实际使用的 context
    private var context: RichTextContext {
        externalContext ?? internalContext
    }
    
    /// Inspector 侧边栏是否显示
    @State private var isInspectorPresented = false
    
    /// 编辑器文本内容（NSAttributedString）
    @State private var text: NSAttributedString = NSAttributedString()
    
    /// 上次保存的 RTF 数据（用于避免重复保存）
    @State private var lastSavedRTFData: Data? = nil
    
    /// 是否正在初始化
    @State private var isInitializing = true
    
    /// 防抖工作项（避免频繁保存）
    @State private var debounceWorkItem: DispatchWorkItem? = nil
    
    /// 待处理的内容变化（用于防抖）
    @State private var pendingTextChange: NSAttributedString? = nil
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // 格式工具栏（顶部）
            RichTextFormat.Toolbar(context: context)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            #endif
            
            // 编辑器主体
            RichTextEditor(
                text: $text,
                context: context,
                format: .archivedData  // 使用 archivedData 格式支持图片附件
            ) { textView in
                // 配置编辑器视图
                configureTextView(textView)
            }
            .disabled(!isEditable)
            .richTextEditorStyle(.standard)
            .richTextEditorConfig(
                .init(
                    isScrollingEnabled: true,
                    isScrollBarsVisible: false,
                    isContinuousSpellCheckingEnabled: true
                )
            )
            
            #if os(iOS)
            // iOS 键盘工具栏
            RichTextKeyboardToolbar(
                context: context,
                leadingButtons: { $0 },
                trailingButtons: { $0 },
                formatSheet: { $0 }
            )
            #endif
        }
        .inspector(isPresented: $isInspectorPresented) {
            // Inspector 侧边栏（格式面板）
            RichTextFormat.Sidebar(context: context)
                #if os(macOS)
                .inspectorColumnWidth(min: 200, ideal: 250, max: 350)
                #endif
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $isInspectorPresented) {
                    Image.richTextFormatBrush
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
                .help("显示格式面板")
            }
        }
        .focusedValue(\.richTextContext, context)
        .richTextFormatSheetConfig(.init(colorPickers: colorPickers))
        .richTextFormatSidebarConfig(
            .init(
                colorPickers: colorPickers,
                fontPicker: true  // macOS 支持字体选择器
            )
        )
        .richTextFormatToolbarConfig(.init(colorPickers: []))
        .onAppear {
            loadContent()
        }
        .onDisappear {
            // 清理防抖工作项
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
        }
        .onChange(of: rtfData) { oldValue, newValue in
            // RTF 数据从外部变化时，重新加载内容
            // 只在不是我们自己的更新时才重新加载（避免循环）
            if newValue != oldValue && newValue != lastSavedRTFData && !isInitializing {
                loadContent()
            }
        }
        .onChange(of: xmlContent) { oldValue, newValue in
            // XML 内容变化时，从 XML 重新加载（确保包含所有附件）
            if let xml = newValue, xml != oldValue, !xml.isEmpty {
                loadFromXML(xml)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSText.didChangeNotification)) { notification in
            // 监听 NSTextView 的文本变化通知（macOS）
            // 这是主要的文本变化监听，避免使用 onChange(of: text) 导致循环
            #if os(macOS)
            guard !isInitializing else { return }
            
            guard let textView = notification.object as? NSTextView else {
                return
            }
            
            // 检查输入法是否正在组合中
            if textView.hasMarkedText() {
                return
            }
            
            // 更新文本内容（使用防抖）
            let newText = textView.attributedString()
            // 只比较字符串内容，避免频繁比较完整的 NSAttributedString
            if newText.string != text.string {
                // 使用防抖机制，避免频繁处理
                pendingTextChange = newText
                scheduleDebouncedContentChange()
            }
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewRichTextEditorProcessPendingChange"))) { notification in
            // 处理防抖后的内容变化
            guard let newText = notification.object as? NSAttributedString else {
                return
            }
            handleContentChange(newText)
            pendingTextChange = nil
        }
    }
    
    // MARK: - Configuration
    
    /// 配置文本视图
    private func configureTextView(_ textView: RichTextViewComponent) {
        // 配置图片支持
        textView.imageConfiguration = RichTextImageConfiguration(
            pasteConfiguration: .enabled,  // 启用粘贴图片
            dropConfiguration: .enabled,    // 启用拖拽图片
            maxImageSize: (
                width: .points(600),        // 最大宽度 600pt
                height: .points(800)        // 最大高度 800pt
            )
        )
        
        // 设置文本容器内边距
        textView.textContentInset = CGSize(width: 30, height: 30)
        
        #if os(macOS)
        // macOS 特定的配置
        if let nsTextView = textView as? NSTextView {
            // 确保撤销功能已启用
            nsTextView.allowsUndo = true
            
            // 配置段落样式（确保行高一致）
            let systemFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let fontHeight = systemFont.ascender - systemFont.descender
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.minimumLineHeight = fontHeight
            paragraphStyle.maximumLineHeight = fontHeight
            paragraphStyle.lineSpacing = 0
            
            nsTextView.defaultParagraphStyle = paragraphStyle
            
            // 设置输入时的属性
            var typingAttributes = nsTextView.typingAttributes
            typingAttributes[.paragraphStyle] = paragraphStyle
            typingAttributes[.font] = systemFont
            nsTextView.typingAttributes = typingAttributes
        }
        #endif
    }
    
    /// 颜色选择器配置
    private var colorPickers: [RichTextColor] {
        [.foreground, .background]
    }
    
    // MARK: - Content Loading
    
    /// 加载内容（优先使用 RTF 数据，否则使用 XML）
    private func loadContent() {
        isInitializing = true
        defer { isInitializing = false }
        
        // 优先从 archivedData 加载（支持图片附件）
        if let archivedData = rtfData {
            do {
                let loadedText = try NSAttributedString(data: archivedData, format: .archivedData)
                text = loadedText
                context.setAttributedString(to: loadedText)
                lastSavedRTFData = archivedData
                print("[NewRichTextEditor] ✅ 从 archivedData 加载内容，长度: \(loadedText.length)")
                return
            } catch {
                print("[NewRichTextEditor] ⚠️ archivedData 解析失败: \(error)")
            }
        }
        
        // 如果没有存档数据或解析失败，从 XML 转换
        if let xml = xmlContent, !xml.isEmpty {
            loadFromXML(xml)
        } else {
            // 都没有，使用空内容
            text = NSAttributedString(string: "")
            context.setAttributedString(to: text)
        }
    }
    
    /// 从 XML 内容加载
    private func loadFromXML(_ xml: String) {
        print("[NewRichTextEditor] 🖼️ 从XML加载内容，长度: \(xml.count)")
        
        let loadedText = MiNoteContentParser.parseToAttributedString(xml, noteRawData: noteRawData)
        
        // 更新文本内容
        text = loadedText
        context.setAttributedString(to: loadedText)
        
        // 生成 archivedData 格式的数据（支持图片附件）
        do {
            let archivedData = try loadedText.richTextData(for: .archivedData)
            rtfData = archivedData
            lastSavedRTFData = archivedData
            print("[NewRichTextEditor] ✅ 从XML生成 archivedData，长度: \(archivedData.count)字节")
        } catch {
            print("[NewRichTextEditor] ⚠️ 生成 archivedData 失败: \(error)")
        }
    }
    
    // MARK: - Content Change Handling
    
    /// 安排防抖的内容变化处理
    private func scheduleDebouncedContentChange() {
        // 取消之前的工作项
        debounceWorkItem?.cancel()
        
        // 捕获当前待处理的文本
        let textToProcess = pendingTextChange
        
        // 创建新的防抖工作项（0.3秒延迟）
        let workItem = DispatchWorkItem {
            guard let newText = textToProcess else {
                return
            }
            
            // 通过 NotificationCenter 通知视图处理内容变化
            // 由于 struct 是值类型，我们不能在闭包中直接访问 self
            // 所以使用 NotificationCenter 来通知视图更新
            NotificationCenter.default.post(
                name: NSNotification.Name("NewRichTextEditorProcessPendingChange"),
                object: newText
            )
        }
        
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    /// 处理内容变化
    private func handleContentChange(_ newText: NSAttributedString) {
        guard !isInitializing else {
            return
        }
        
        // 更新本地 text 状态（不触发 onChange）
        text = newText
        
        // 将 NSAttributedString 转换为 archivedData 格式
        let archivedData: Data?
        do {
            archivedData = try newText.richTextData(for: .archivedData)
        } catch {
            // 如果失败，尝试使用 NSKeyedArchiver
            archivedData = try? NSKeyedArchiver.archivedData(
                withRootObject: newText,
                requiringSecureCoding: false
            )
        }
        
        guard let archivedData = archivedData else {
            print("[NewRichTextEditor] ⚠️ 无法生成 archivedData")
            return
        }
        
        // 检查内容是否真的变化了（避免仅加载笔记就触发保存）
        if let lastSaved = lastSavedRTFData, lastSaved == archivedData {
            // 数据相同，不需要触发回调
            return
        }
        
        // 内容确实变化了，更新状态并触发回调
        // 注意：不更新 rtfData binding，避免触发 onChange(of: rtfData) 导致循环
        lastSavedRTFData = archivedData
        
        // 触发回调（异步执行，避免阻塞）
        DispatchQueue.main.async {
            self.onContentChange?(archivedData)
        }
    }
}

// MARK: - Preview

#Preview {
    NewRichTextEditor(
        rtfData: .constant(nil),
        isEditable: .constant(true)
    )
    .frame(width: 800, height: 600)
}

