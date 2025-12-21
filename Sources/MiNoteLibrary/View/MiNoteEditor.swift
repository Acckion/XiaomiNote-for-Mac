import SwiftUI
import AppKit

/// 基于 NSTextView 的富文本编辑器（macOS 26 原生存储）
@available(macOS 26.0, *)
struct MiNoteEditor: View {
    @Binding var rtfData: Data?  // macOS 26 原生存储：RTF 格式的 AttributedString
    @Binding var isEditable: Bool
    var noteRawData: [String: Any]? = nil
    var onTextViewCreated: ((NSTextView) -> Void)? = nil
    var updatedAt: Date? = nil  // 笔记更新日期（仅用于显示，不用于编辑）
    
    // 格式操作回调
    var onFormatAction: ((FormatAction) -> Void)? = nil
    
    // 向后兼容：如果提供了 xmlContent，自动转换为 RTF
    init(rtfData: Binding<Data?>, isEditable: Binding<Bool>, noteRawData: [String: Any]? = nil, onTextViewCreated: ((NSTextView) -> Void)? = nil, updatedAt: Date? = nil, onFormatAction: ((FormatAction) -> Void)? = nil) {
        self._rtfData = rtfData
        self._isEditable = isEditable
        self.noteRawData = noteRawData
        self.onTextViewCreated = onTextViewCreated
        self.updatedAt = updatedAt
        self.onFormatAction = onFormatAction
    }
    
    enum FormatAction {
        case bold
        case italic
        case underline
        case strikethrough
        case heading(Int)
        case fontSize(CGFloat)
        case highlight
        case checkbox
        case image
        case textAlignment(NSTextAlignment)
    }
    
    var body: some View {
        MiNoteEditorRepresentable(
            rtfData: $rtfData,
            isEditable: $isEditable,
            noteRawData: noteRawData,
            onTextViewCreated: onTextViewCreated,
            onFormatAction: onFormatAction,
            updatedAt: updatedAt
        )
            .padding(.vertical, 10)
    }
}

/// NSTextView 的 SwiftUI 包装器（macOS 26 原生存储）
@available(macOS 26.0, *)
struct MiNoteEditorRepresentable: NSViewRepresentable {
    @Binding var rtfData: Data?  // macOS 26 原生存储：RTF 格式的 AttributedString
    @Binding var isEditable: Bool
    var noteRawData: [String: Any]? = nil
    var onTextViewCreated: ((NSTextView) -> Void)? = nil
    var onFormatAction: ((MiNoteEditor.FormatAction) -> Void)? = nil
    var updatedAt: Date? = nil  // 笔记更新日期（仅用于显示，不用于编辑）
    
    func makeNSView(context: Context) -> NSView {
        // 创建一个容器视图（不使用滚动视图，让外部的 ScrollView 控制滚动）
        let containerView = NSView()
        
        // 创建文本视图（不使用滚动视图）
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 10)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.allowsUndo = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.heightTracksTextView = false  // 不跟踪文本视图高度，让内容自然增长
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        
        // 将文本视图添加到容器
        containerView.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        // 存储容器视图引用，以便后续更新高度
        context.coordinator.containerView = containerView
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: containerView.topAnchor),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // 设置容器视图的初始高度约束（允许内容增长）
        let heightConstraint = containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 400)
        heightConstraint.priority = .defaultLow
        heightConstraint.isActive = true
        context.coordinator.heightConstraint = heightConstraint
        
        context.coordinator.textView = textView
        context.coordinator.parent = self
        context.coordinator.lastRTFData = rtfData
        
        // 设置初始内容
        context.coordinator.updateContent()
        
        textView.isEditable = isEditable
        
        // 监听选择变化通知
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewSelectionDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification,
            object: textView
        )
        
        // 监听格式操作通知
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleFormatAction(_:)),
            name: NSNotification.Name("MiNoteEditorFormatAction"),
            object: nil
        )
        
        onTextViewCreated?(textView)
        
        NotificationCenter.default.post(name: NSNotification.Name("MiNoteEditorTextViewCreated"), object: textView)
        
        // 初始化时更新格式状态
        DispatchQueue.main.async {
            context.coordinator.updateFormatState()
        }
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.textBackgroundColor
        
        // 更新 Coordinator 的 parent 引用（因为 NSViewRepresentable 可能被重新创建）
        context.coordinator.parent = self
        
        // 更新内容（只在真正改变时）
        if rtfData != context.coordinator.lastRTFData {
            context.coordinator.updateContent()
        }
        
        textView.isEditable = isEditable
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
        @MainActor class Coordinator: NSObject, NSTextViewDelegate {
            var parent: MiNoteEditorRepresentable?
            var textView: NSTextView?
            var containerView: NSView?
            var heightConstraint: NSLayoutConstraint?
            var lastRTFData: Data? = nil  // macOS 26 原生存储：RTF 格式
            var isUpdatingFromExternal: Bool = false
            private var pendingUpdateTask: Task<Void, Never>?
        
        // 只读属性键
        private let readOnlyAttributeKey = NSAttributedString.Key("MiNoteReadOnly")
        
        // 格式状态
        struct FormatState {
            var isBold: Bool = false
            var isItalic: Bool = false
            var isUnderline: Bool = false
            var isStrikethrough: Bool = false
            var hasHighlight: Bool = false
            var textAlignment: NSTextAlignment = .left
            var textStyle: TextStyle = .body
        }
        
        // 文本样式枚举（用于格式状态检测）
        enum TextStyle: String, CaseIterable {
            case title = "标题"
            case subtitle = "小标题"
            case subheading = "副标题"
            case body = "正文"
            case bulletList = "无序列表"
            case numberedList = "有序列表"
        }
        
        // 检查指定范围是否为只读区域
        private func isReadOnlyRange(_ range: NSRange) -> Bool {
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  range.location < textStorage.length else {
                return false
            }
            
            let effectiveRange = NSRange(location: range.location, length: min(range.length, textStorage.length - range.location))
            var isReadOnly = false
            
            textStorage.enumerateAttribute(readOnlyAttributeKey, in: effectiveRange, options: []) { (value, _, stop) in
                if let readOnly = value as? Bool, readOnly {
                    isReadOnly = true
                    stop.pointee = true
                }
            }
            
            return isReadOnly
        }
        
        // NSTextViewDelegate: 阻止编辑只读区域
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let textStorage = textView.textStorage else { return true }
            
            // 检查是否尝试编辑只读区域
            if isReadOnlyRange(affectedCharRange) {
                return false
            }
            
            // 处理删除操作（replacementString 为空或 nil）
            if replacementString == nil || replacementString!.isEmpty {
                // 删除操作：检查删除范围是否包含只读区域
                if isReadOnlyRange(affectedCharRange) {
                    return false
                }
                
                // 检查删除操作是否会影响到只读区域
                // 如果删除范围紧邻只读区域，需要检查
                let deleteEnd = affectedCharRange.location + affectedCharRange.length
                
                // 检查删除后的位置是否在只读区域内
                if deleteEnd < textStorage.length {
                    let checkRange = NSRange(location: deleteEnd, length: 1)
                    if isReadOnlyRange(checkRange) {
                        return false
                    }
                }
                
                // 检查删除范围之前的位置是否在只读区域内
                if affectedCharRange.location > 0 {
                    let beforeRange = NSRange(location: affectedCharRange.location - 1, length: 1)
                    if isReadOnlyRange(beforeRange) {
                        // 如果删除位置紧邻只读区域，阻止删除
                        return false
                    }
                }
                
                // 检查删除操作是否会跨越只读区域（防止删除只读区域前后的内容导致只读区域移动）
                // 如果删除范围跨越了只读区域的边界，阻止删除
                let deleteStart = affectedCharRange.location
                let deleteLength = affectedCharRange.length
                
                // 检查删除范围内的每个字符，看是否在只读区域内
                for i in 0..<deleteLength {
                    let checkLocation = deleteStart + i
                    if checkLocation < textStorage.length {
                        let checkRange = NSRange(location: checkLocation, length: 1)
                        if isReadOnlyRange(checkRange) {
                            return false
                        }
                    }
                }
            } else {
                // 插入操作：如果插入位置在只读区域内，也阻止
                let insertRange = NSRange(location: affectedCharRange.location, length: replacementString!.count)
                if isReadOnlyRange(insertRange) {
                    return false
                }
                
                // 检查插入位置是否紧邻只读区域（防止在只读区域前后插入）
                if affectedCharRange.location > 0 {
                    let beforeRange = NSRange(location: affectedCharRange.location - 1, length: 1)
                    if isReadOnlyRange(beforeRange) {
                        return false
                    }
                }
            }
            
            return true
        }
        
        // NSTextViewDelegate: 阻止选择只读区域
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let textStorage = textView.textStorage else { return }
            
            let selectedRange = textView.selectedRange()
            
            // 更新格式状态（当光标移动时）
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05秒，增加延迟确保状态已更新
                self.updateFormatState()
            }
            
            // 如果选择范围包含只读区域，调整选择范围
            if isReadOnlyRange(selectedRange) {
                // 将选择移动到只读区域之后
                var newLocation = selectedRange.location
                while newLocation < textStorage.length {
                    let checkRange = NSRange(location: newLocation, length: 1)
                    if !isReadOnlyRange(checkRange) {
                        break
                    }
                    newLocation += 1
                }
                
                if newLocation < textStorage.length {
                    textView.setSelectedRange(NSRange(location: newLocation, length: 0))
                } else {
                    // 如果只读区域在末尾，移动到只读区域之前
                    var beforeLocation = selectedRange.location - 1
                    while beforeLocation >= 0 {
                        let checkRange = NSRange(location: beforeLocation, length: 1)
                        if !isReadOnlyRange(checkRange) {
                            textView.setSelectedRange(NSRange(location: beforeLocation + 1, length: 0))
                            break
                        }
                        beforeLocation -= 1
                    }
                }
            }
        }
        
        func updateContent() {
            guard let parent = parent,
                  let textView = textView,
                  let textStorage = textView.textStorage else { return }
            
            // 如果内容没有改变，跳过更新
            if parent.rtfData == lastRTFData {
                return
            }
            
        isUpdatingFromExternal = true
        defer { isUpdatingFromExternal = false }
        
            // 从 archivedData 加载
            if let rtfData = parent.rtfData {
                // 从 archivedData 创建 NSAttributedString
                if let attributedString = try? NSAttributedString(data: rtfData, format: .archivedData) {
                    textStorage.setAttributedString(attributedString)
                    lastRTFData = rtfData
                    print("[MiNoteEditor] 从 archivedData 加载内容，长度: \(rtfData.count) 字节")
                } else {
                    print("[MiNoteEditor] ⚠️ 无法从 archivedData 创建 NSAttributedString")
                    // 如果解析失败，创建一个空的 AttributedString
                    textStorage.setAttributedString(NSAttributedString(string: ""))
                    lastRTFData = nil
                }
            } else {
                // 向后兼容：如果没有 RTF 数据，尝试从 XML 转换（首次加载时）
                // 这应该只在同步时发生，正常情况下不应该进入这里
                print("[MiNoteEditor] ⚠️ 没有 RTF 数据，使用空内容（应该在同步时从 XML 生成 RTF）")
                textStorage.setAttributedString(NSAttributedString(string: ""))
                lastRTFData = nil
            }
        }
        
        
        @objc func textViewSelectionDidChange(_ notification: Notification) {
            // 当选择改变时（包括光标移动），立即更新格式状态
            // 使用 DispatchQueue 而不是 Task.sleep，减少延迟
            DispatchQueue.main.async { [weak self] in
                // 稍微延迟以确保文本视图内部状态已更新（但延迟更短）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    self?.updateFormatState()
                }
            }
        }
        
        @objc func handleFormatAction(_ notification: Notification) {
            guard let action = notification.object as? MiNoteEditor.FormatAction,
                  let textView = textView,
                  let textStorage = textView.textStorage else { return }
            
            let range = textView.selectedRange()
            
            // 对齐操作不需要选中文本，可以使用光标位置
            if case .textAlignment(let alignment) = action {
                let cursorLocation = range.location
                let effectiveRange = NSRange(location: max(0, cursorLocation), length: 0)
                applyTextAlignment(in: textView, textStorage: textStorage, range: effectiveRange, alignment: alignment)
                
                // 操作完成后立即更新格式状态
                DispatchQueue.main.async { [weak self] in
                    // 立即更新一次
                    self?.updateFormatState()
                    // 再延迟更新一次，确保状态同步
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self?.updateFormatState()
                    }
                }
                return
            }
            
            // 标题操作不需要选中文本，可以使用光标位置
            if case .heading(let level) = action {
                let cursorLocation = range.location
                let effectiveRange = NSRange(location: max(0, cursorLocation), length: 0)
                applyHeading(in: textView, textStorage: textStorage, range: effectiveRange, level: level)
                
                // 操作完成后立即更新格式状态
                DispatchQueue.main.async { [weak self] in
                    // 立即更新一次
                    self?.updateFormatState()
                    // 再延迟更新一次，确保状态同步
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self?.updateFormatState()
                    }
                }
                return
            }
            
            guard range.length > 0 && range.location < textStorage.length else { return }
            
            let effectiveRange = NSRange(location: range.location, length: min(range.length, textStorage.length - range.location))
            
            switch action {
            case .bold:
                toggleBold(in: textView, textStorage: textStorage, range: effectiveRange)
            case .italic:
                toggleItalic(in: textView, textStorage: textStorage, range: effectiveRange)
            case .underline:
                toggleUnderline(in: textView, textStorage: textStorage, range: effectiveRange)
            case .strikethrough:
                toggleStrikethrough(in: textView, textStorage: textStorage, range: effectiveRange)
            case .highlight:
                toggleHighlight(in: textView, textStorage: textStorage, range: effectiveRange)
            default:
                break
            }
            
            // 操作完成后立即更新格式状态
            DispatchQueue.main.async { [weak self] in
                // 立即更新一次
                self?.updateFormatState()
                // 再延迟更新一次，确保状态同步
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self?.updateFormatState()
                }
            }
        }
        
        private func toggleBold(in textView: NSTextView, textStorage: NSTextStorage, range: NSRange) {
            // 检查当前是否加粗
            var shouldBold = true
            if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    shouldBold = false
                }
            }
            
            // 应用或移除加粗
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range, options: []) { (value, subrange, _) in
                if let oldFont = value as? NSFont {
                    let fontSize = oldFont.pointSize
                    let newFont: NSFont
                    if shouldBold {
                        newFont = NSFont.boldSystemFont(ofSize: fontSize)
                    } else {
                        var fontDescriptor = oldFont.fontDescriptor
                        var traits = fontDescriptor.symbolicTraits
                        traits.remove(.bold)
                        fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
                        newFont = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                    }
                    textStorage.addAttribute(.font, value: newFont, range: subrange)
                } else {
                    let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    let newFont = shouldBold ? NSFont.boldSystemFont(ofSize: baseFont.pointSize) : baseFont
                    textStorage.addAttribute(.font, value: newFont, range: subrange)
                }
            }
            textStorage.endEditing()
            textView.didChangeText()
        }
        
        private func toggleItalic(in textView: NSTextView, textStorage: NSTextStorage, range: NSRange) {
            // 检查当前是否斜体
            var shouldItalic = true
            if let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
                if font.fontDescriptor.symbolicTraits.contains(.italic) {
                    shouldItalic = false
                }
            }
            
            // 应用或移除斜体
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range, options: []) { (value, subrange, _) in
                if let oldFont = value as? NSFont {
                    let fontSize = oldFont.pointSize
                    var fontDescriptor = oldFont.fontDescriptor
                    var traits = fontDescriptor.symbolicTraits
                    if shouldItalic {
                        traits.insert(.italic)
                    } else {
                        traits.remove(.italic)
                    }
                    fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
                    let newFont = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
                    textStorage.addAttribute(.font, value: newFont, range: subrange)
            } else {
                    let baseFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    var fontDescriptor = baseFont.fontDescriptor
                    if shouldItalic {
                        fontDescriptor = fontDescriptor.withSymbolicTraits([.italic])
                    }
                    let newFont = NSFont(descriptor: fontDescriptor, size: baseFont.pointSize) ?? baseFont
                    textStorage.addAttribute(.font, value: newFont, range: subrange)
                }
            }
            textStorage.endEditing()
            textView.didChangeText()
        }
        
        private func toggleHighlight(in textView: NSTextView, textStorage: NSTextStorage, range: NSRange) {
            // 检查是否已经有高亮
            var hasHighlight = false
            textStorage.enumerateAttribute(.backgroundColor, in: range, options: []) { (value, _, _) in
                if value != nil {
                    hasHighlight = true
                }
            }
            
            if hasHighlight {
                // 移除高亮
                textStorage.removeAttribute(.backgroundColor, range: range)
            } else {
                // 添加高亮
                let highlightColor = NSColor.yellow.withAlphaComponent(0.5)
                textStorage.addAttribute(.backgroundColor, value: highlightColor, range: range)
            }
            textView.didChangeText()
        }
        
        private func toggleUnderline(in textView: NSTextView, textStorage: NSTextStorage, range: NSRange) {
            // 检查是否已经有下划线
            var hasUnderline = false
            textStorage.enumerateAttribute(.underlineStyle, in: range, options: []) { (value, _, _) in
                if let underlineStyle = value as? Int, underlineStyle != 0 {
                    hasUnderline = true
                }
            }
            
            if hasUnderline {
                // 移除下划线
                textStorage.removeAttribute(.underlineStyle, range: range)
            } else {
                // 添加下划线
                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            textView.didChangeText()
        }
        
        private func toggleStrikethrough(in textView: NSTextView, textStorage: NSTextStorage, range: NSRange) {
            // 检查是否已经有删除线
            var hasStrikethrough = false
            textStorage.enumerateAttribute(.strikethroughStyle, in: range, options: []) { (value, _, _) in
                if let strikethroughStyle = value as? Int, strikethroughStyle != 0 {
                    hasStrikethrough = true
                }
            }
            
            if hasStrikethrough {
                // 移除删除线
                textStorage.removeAttribute(.strikethroughStyle, range: range)
            } else {
                // 添加删除线
                textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            textView.didChangeText()
        }
        
        private func applyTextAlignment(in textView: NSTextView, textStorage: NSTextStorage, range: NSRange, alignment: NSTextAlignment) {
            // 获取当前段落范围
            let string = textStorage.string
            let paragraphRange = (string as NSString).paragraphRange(for: range)
            
            // 获取当前段落样式或创建新的
            let paragraphStyle = textStorage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
            let mutableParagraphStyle = (paragraphStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            
            // 设置对齐方式
            mutableParagraphStyle.alignment = alignment
            
            // 应用段落样式
            textStorage.addAttribute(.paragraphStyle, value: mutableParagraphStyle, range: paragraphRange)
            textView.didChangeText()
        }
        
        private func applyHeading(in textView: NSTextView, textStorage: NSTextStorage, range: NSRange, level: Int) {
            // 获取当前段落范围
            let string = textStorage.string
            let paragraphRange = (string as NSString).paragraphRange(for: range)
            
            // 确定字体大小
            let fontSize: CGFloat
            switch level {
            case 1:
                fontSize = 24.0  // h1FontSize (减小一级标题大小)
            case 2:
                fontSize = 18.0  // h2FontSize
            case 3:
                fontSize = 14.0  // h3FontSize
            default:
                fontSize = NSFont.systemFontSize
            }
            
            // 应用字体大小和加粗
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: paragraphRange, options: []) { (value, subrange, _) in
                if let oldFont = value as? NSFont {
                    var fontDescriptor = oldFont.fontDescriptor
                    var traits = fontDescriptor.symbolicTraits
                    traits.insert(.bold)
                    fontDescriptor = fontDescriptor.withSymbolicTraits(traits)
                    let newFont = NSFont(descriptor: fontDescriptor, size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
                    textStorage.addAttribute(.font, value: newFont, range: subrange)
                } else {
                    let newFont = NSFont.boldSystemFont(ofSize: fontSize)
                    textStorage.addAttribute(.font, value: newFont, range: subrange)
                }
            }
            textStorage.endEditing()
            textView.didChangeText()
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let parent = parent,
                  !isUpdatingFromExternal else { return }
            
            // 更新容器视图高度以匹配文本内容
            updateContainerHeight()
            
            // 更新格式状态（延迟更新，确保文本视图状态已更新）
            DispatchQueue.main.async { [weak self] in
                // 稍微延迟以确保文本视图内部状态已更新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    self?.updateFormatState()
                }
            }
            
            // 取消之前的待处理更新任务
            pendingUpdateTask?.cancel()
            
            // 异步处理内容更新，避免在视图更新期间修改状态
            pendingUpdateTask = Task { @MainActor in
                // 将 NSAttributedString 转换为 archivedData
                let attributedString = textView.attributedString()
                
                // 将 NSAttributedString 转换为 archivedData
                if let rtfData = try? attributedString.richTextData(for: .archivedData) {
                    // 只在内容真正改变时才更新
                    if rtfData != lastRTFData {
                        isUpdatingFromExternal = true
                        
                        // 更新 archivedData
                        parent.rtfData = rtfData
                        lastRTFData = rtfData
                        
                        print("[MiNoteEditor] 保存 archivedData，长度: \(rtfData.count) 字节")
                        
                        isUpdatingFromExternal = false
                    }
                } else {
                    print("[MiNoteEditor] ⚠️ 无法生成 archivedData")
                }
            }
        }
        
        // 更新格式状态并发送通知
        @MainActor func updateFormatState() {
            guard let textView = textView,
                  let textStorage = textView.textStorage else { return }
            
            let range = textView.selectedRange()
            var formatState = FormatState()
            
            // 确保位置有效
            guard range.location >= 0 && range.location <= textStorage.length else { return }
            
            // 获取检查位置（如果有选中文本，使用选中范围；否则使用光标位置）
            let checkLocation = range.location
            var effectiveRange: NSRange
            
            if range.length > 0 {
                // 有选中文本，检查选中范围
                effectiveRange = NSRange(location: checkLocation, length: min(range.length, textStorage.length - checkLocation))
            } else {
                // 只有光标，检查光标位置的字符
                if checkLocation >= textStorage.length {
                    // 光标在末尾，检查最后一个字符
                    if textStorage.length > 0 {
                        let lastLocation = textStorage.length - 1
                        effectiveRange = NSRange(location: lastLocation, length: 1)
                    } else {
                        // 文本为空，使用默认值
                        effectiveRange = NSRange(location: 0, length: 0)
                    }
                } else {
                    effectiveRange = NSRange(location: checkLocation, length: 1)
                }
            }
            
            // 检查格式状态（加粗、斜体、下划线、删除线、高亮）
            if effectiveRange.location < textStorage.length {
                if range.length > 0 {
                    // 有选中文本：检查选中范围内是否大部分字符都有该格式
                    var boldCount = 0
                    var italicCount = 0
                    var underlineCount = 0
                    var strikethroughCount = 0
                    var highlightCount = 0
                    let totalLength = min(effectiveRange.length, textStorage.length - effectiveRange.location)
                    
                    if totalLength > 0 {
                        for i in 0..<totalLength {
                            let checkLocation = effectiveRange.location + i
                            if checkLocation < textStorage.length {
                                if let font = textStorage.attribute(.font, at: checkLocation, effectiveRange: nil) as? NSFont {
                                    if font.fontDescriptor.symbolicTraits.contains(.bold) {
                                        boldCount += 1
                                    }
                                    if font.fontDescriptor.symbolicTraits.contains(.italic) {
                                        italicCount += 1
                                    }
                                }
                                
                                if let underlineStyle = textStorage.attribute(.underlineStyle, at: checkLocation, effectiveRange: nil) as? Int, underlineStyle != 0 {
                                    underlineCount += 1
                                }
                                
                                if let strikethroughStyle = textStorage.attribute(.strikethroughStyle, at: checkLocation, effectiveRange: nil) as? Int, strikethroughStyle != 0 {
                                    strikethroughCount += 1
                                }
                                
                                if let backgroundColor = textStorage.attribute(.backgroundColor, at: checkLocation, effectiveRange: nil) as? NSColor, backgroundColor.alphaComponent > 0 {
                                    highlightCount += 1
                                }
                            }
                        }
                        
                        // 如果选中范围内大部分字符都有该格式，则认为该格式是激活的
                        formatState.isBold = boldCount > totalLength / 2
                        formatState.isItalic = italicCount > totalLength / 2
                        formatState.isUnderline = underlineCount > totalLength / 2
                        formatState.isStrikethrough = strikethroughCount > totalLength / 2
                        formatState.hasHighlight = highlightCount > totalLength / 2
                    }
                } else {
                    // 只有光标：检查光标位置的格式
                    // 光标在字符之间时，应该检查前一个字符的格式（因为这是即将输入的位置）
                    var checkLocation = effectiveRange.location
                    
                    // 如果光标在文本末尾，检查最后一个字符
                    if checkLocation >= textStorage.length {
                        if textStorage.length > 0 {
                            checkLocation = textStorage.length - 1
                        } else {
                            // 文本为空，使用默认格式
                            checkLocation = -1
                        }
                    }
                    
                    // 如果光标在开头，检查第一个字符（如果有）
                    if checkLocation < 0 {
                        if textStorage.length > 0 {
                            checkLocation = 0
                        } else {
                            // 文本为空，使用默认格式
                            checkLocation = -1
                        }
                    }
                    
                    // 光标在字符之间时，检查前一个字符的格式（更符合用户期望）
                    if checkLocation > 0 && checkLocation < textStorage.length {
                        // 检查前一个字符的格式（光标即将输入的位置）
                        let prevLocation = checkLocation - 1
                        if prevLocation >= 0 && prevLocation < textStorage.length {
                            var effectiveRange = NSRange(location: prevLocation, length: 1)
                            if let font = textStorage.attribute(.font, at: prevLocation, effectiveRange: &effectiveRange) as? NSFont {
                                formatState.isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                                formatState.isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                            }
                            
                            // 检查下划线
                            effectiveRange = NSRange(location: prevLocation, length: 1)
                            if let underlineStyle = textStorage.attribute(.underlineStyle, at: prevLocation, effectiveRange: &effectiveRange) as? Int {
                                formatState.isUnderline = underlineStyle != 0
                            }
                            
                            // 检查删除线
                            effectiveRange = NSRange(location: prevLocation, length: 1)
                            if let strikethroughStyle = textStorage.attribute(.strikethroughStyle, at: prevLocation, effectiveRange: &effectiveRange) as? Int {
                                formatState.isStrikethrough = strikethroughStyle != 0
                            }
                            
                            // 检查高亮（背景色）
                            effectiveRange = NSRange(location: prevLocation, length: 1)
                            if let backgroundColor = textStorage.attribute(.backgroundColor, at: prevLocation, effectiveRange: &effectiveRange) as? NSColor {
                                formatState.hasHighlight = backgroundColor.alphaComponent > 0
                            }
                        }
                    } else if checkLocation >= 0 && checkLocation < textStorage.length {
                        // 光标正好在字符上，检查该字符的格式
                        var effectiveRange = NSRange(location: checkLocation, length: 1)
                        if let font = textStorage.attribute(.font, at: checkLocation, effectiveRange: &effectiveRange) as? NSFont {
                            formatState.isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                            formatState.isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
                        }
                        
                        // 检查下划线
                        effectiveRange = NSRange(location: checkLocation, length: 1)
                        if let underlineStyle = textStorage.attribute(.underlineStyle, at: checkLocation, effectiveRange: &effectiveRange) as? Int {
                            formatState.isUnderline = underlineStyle != 0
                        }
                        
                        // 检查删除线
                        effectiveRange = NSRange(location: checkLocation, length: 1)
                        if let strikethroughStyle = textStorage.attribute(.strikethroughStyle, at: checkLocation, effectiveRange: &effectiveRange) as? Int {
                            formatState.isStrikethrough = strikethroughStyle != 0
                        }
                        
                        // 检查高亮（背景色）
                        effectiveRange = NSRange(location: checkLocation, length: 1)
                        if let backgroundColor = textStorage.attribute(.backgroundColor, at: checkLocation, effectiveRange: &effectiveRange) as? NSColor {
                            formatState.hasHighlight = backgroundColor.alphaComponent > 0
                        }
                    }
                    // 如果 checkLocation == -1（文本为空），formatState 保持默认值（false）
                }
            }
            
            // 检查对齐方式（段落样式）- 使用光标位置所在的段落
            let cursorLocation = range.location
            var detectedAlignment: NSTextAlignment = .left
            
            if cursorLocation <= textStorage.length {
                // 获取光标所在段落的范围
                let string = textStorage.string
                let checkLocation = min(cursorLocation, max(0, textStorage.length - 1))
                let paragraphRange = (string as NSString).paragraphRange(for: NSRange(location: checkLocation, length: 0))
                
                // 检查段落样式 - 遍历段落范围内的所有字符，找到有效的段落样式
                if paragraphRange.location < textStorage.length {
                    var foundAlignment = false
                    let effectiveRange = NSRange(location: paragraphRange.location, length: min(paragraphRange.length, textStorage.length - paragraphRange.location))
                    
                    // 在段落范围内查找段落样式
                    textStorage.enumerateAttribute(.paragraphStyle, in: effectiveRange, options: []) { (value, range, stop) in
                        if let paragraphStyle = value as? NSParagraphStyle {
                            detectedAlignment = paragraphStyle.alignment
                            foundAlignment = true
                            stop.pointee = true
                        }
                    }
                    
                    // 如果没有找到段落样式，使用默认左对齐
                    if !foundAlignment {
                        detectedAlignment = .left
                    }
                } else {
                    detectedAlignment = .left
                }
            } else {
                detectedAlignment = .left
            }
            
            formatState.textAlignment = detectedAlignment
            print("🔍 [updateFormatState] 检测到对齐方式: \(detectedAlignment.rawValue) (左=0, 居中=1, 右=2)")
            
            // 检测文本样式（标题、正文、列表等）
            var detectedStyle: TextStyle = .body
            
            // 获取光标所在段落的范围（用于检测文本样式）
            let styleString = textStorage.string
            let styleParagraphRange = (styleString as NSString).paragraphRange(for: NSRange(location: checkLocation, length: 0))
            
            if styleParagraphRange.location < textStorage.length {
                // 检查段落开头的字体大小和内容
                if let font = textStorage.attribute(.font, at: styleParagraphRange.location, effectiveRange: nil) as? NSFont {
                    let fontSize = font.pointSize
                    
                    // 根据字体大小判断标题级别
                    if fontSize >= 24.0 {
                        detectedStyle = .title
                    } else if fontSize >= 18.0 {
                        detectedStyle = .subtitle
                    } else if fontSize >= 14.0 {
                        detectedStyle = .subheading
                    } else {
                        // 检查是否是列表
                        let paragraphString = textStorage.attributedSubstring(from: styleParagraphRange).string
                        let trimmedParagraph = paragraphString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        
                        if trimmedParagraph.hasPrefix("• ") {
                            detectedStyle = .bulletList
                        } else if let _ = try? NSRegularExpression(pattern: "^\\d+\\.\\s+").firstMatch(in: trimmedParagraph, options: [], range: NSRange(trimmedParagraph.startIndex..., in: trimmedParagraph)) {
                            detectedStyle = .numberedList
                        } else {
                            detectedStyle = .body
                        }
                    }
                } else {
                    // 没有字体信息，检查文本内容判断是否是列表
                    let paragraphString = textStorage.attributedSubstring(from: styleParagraphRange).string
                    let trimmedParagraph = paragraphString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    
                    if trimmedParagraph.hasPrefix("• ") {
                        detectedStyle = .bulletList
                    } else if let _ = try? NSRegularExpression(pattern: "^\\d+\\.\\s+").firstMatch(in: trimmedParagraph, options: [], range: NSRange(trimmedParagraph.startIndex..., in: trimmedParagraph)) {
                        detectedStyle = .numberedList
                    } else {
                        detectedStyle = .body
                    }
                }
            }
            
            formatState.textStyle = detectedStyle
            print("🔍 [updateFormatState] 检测到文本样式: \(detectedStyle.rawValue)")
            
            // 发送格式状态更新通知
            NotificationCenter.default.post(
                name: NSNotification.Name("MiNoteEditorFormatStateChanged"),
                object: nil,
                userInfo: [
                    "isBold": formatState.isBold,
                    "isItalic": formatState.isItalic,
                    "isUnderline": formatState.isUnderline,
                    "isStrikethrough": formatState.isStrikethrough,
                    "hasHighlight": formatState.hasHighlight,
                    "textAlignment": formatState.textAlignment.rawValue,
                    "textStyle": detectedStyle.rawValue
                ]
            )
        }
        
        // 更新容器视图高度以匹配文本内容
        private func updateContainerHeight() {
            guard let textView = textView,
                  let containerView = containerView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            
            // 计算文本内容所需的高度
            let usedRect = layoutManager.usedRect(for: textContainer)
            let minHeight: CGFloat = 400
            let newHeight = max(minHeight, usedRect.height + 40)  // 添加一些底部间距
            
            // 更新高度约束
            if let heightConstraint = heightConstraint {
                heightConstraint.constant = newHeight
            } else {
                // 如果约束不存在，创建一个新的
                let newConstraint = containerView.heightAnchor.constraint(equalToConstant: newHeight)
                newConstraint.priority = .defaultLow
                newConstraint.isActive = true
                heightConstraint = newConstraint
            }
            
            // 强制更新布局
            containerView.needsLayout = true
            containerView.layoutSubtreeIfNeeded()
        }
    }
}
