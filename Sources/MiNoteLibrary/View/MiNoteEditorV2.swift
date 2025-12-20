import SwiftUI
import Foundation

/// 基于 SwiftUI 原生 TextEditor 和 AttributedString 的富文本编辑器
/// 参考 Apple WWDC 教程和官方文档实现
/// 使用 AttributedTextSelection.attributes(in:) 和 transformAttributes 方法
@available(macOS 14.0, *)
struct MiNoteEditorV2: View {
    @Binding var attributedText: AttributedString
    @Binding var isEditable: Bool
    @State private var selection = AttributedTextSelection()
    
    // 字体解析上下文（用于解析字体属性）
    @Environment(\.fontResolutionContext) private var fontResolutionContext
    
    var noteRawData: [String: Any]? = nil
    var onFormatAction: ((FormatAction) -> Void)? = nil
    
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
        // TextEditor 应该能正确显示 AttributedString 的所有格式属性
        // 不需要额外的配置，AttributedString 中的字体、颜色等属性会自动应用
        TextEditor(text: $attributedText, selection: $selection)
            .onChange(of: selection) { oldValue, newValue in
                // 选择变化时更新格式状态（延迟一小段时间，确保 TextEditor 内部状态已更新）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    updateFormatState()
                }
            }
            .onChange(of: attributedText) { oldValue, newValue in
                // 文本变化时更新格式状态（延迟更新，避免频繁触发）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    updateFormatState()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MiNoteEditorFormatAction"))) { notification in
                // 处理格式操作
                if let action = notification.object as? FormatAction {
                    handleFormatAction(action)
                }
            }
    }
    
    // MARK: - 格式状态检测
    
    /// 更新格式状态并发送通知
    /// 使用 AttributedTextSelection.attributes(in:) 和 typingAttributes(in:) 方法
    private func updateFormatState() {
        var formatState = FormatState()
        
        // 使用 AttributedTextSelection 的 attributes 方法获取格式状态
        // 这是 Apple 推荐的标准方法
        if #available(macOS 26.0, *) {
            let _ = selection.attributes(in: attributedText)
        }
        
        // 检查字体样式（加粗、斜体）
        // 使用 typingAttributes 获取输入时的属性（适用于光标位置）
        if #available(macOS 26.0, *) {
            let typingAttrs = selection.typingAttributes(in: attributedText)
            if let font = typingAttrs.font {
                // 解析字体以检查是否为加粗和斜体
                let resolvedFont = font.resolve(in: fontResolutionContext)
                formatState.isBold = resolvedFont.isBold
                
                // 检查斜体：通过字体描述符检查
                // 使用 NSAttributedString 来获取 NSFont
                let testString = NSAttributedString(string: "A", attributes: [.font: font])
                if let nsFont = testString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                    let fontDescriptor = nsFont.fontDescriptor
                    let symbolicTraits = fontDescriptor.symbolicTraits
                    formatState.isItalic = symbolicTraits.contains(.italic)
                }
            }
            
            // 检查下划线
            // Text.LineStyle 是一个枚举，需要检查其值
            if typingAttrs.underlineStyle != nil {
                formatState.isUnderline = true
            }
            
            // 检查删除线
            if typingAttrs.strikethroughStyle != nil {
                formatState.isStrikethrough = true
            }
            
            // 检查高亮（背景色）
            if typingAttrs.backgroundColor != nil {
                // SwiftUI Color 没有 alphaComponent，使用其他方式检查
                // 简化处理：如果存在背景色，就认为有高亮
                formatState.hasHighlight = true
            }
            
            // 对于选中文本，需要检查选中范围内的格式
            // 获取选中文本（可能是 DiscontiguousAttributedSubstring）
            let selectedText = attributedText[selection]
            // 检查是否有字符
            if selectedText.characters.count > 0 {
                // 有选中文本：检查选中范围内是否大部分都有该格式
                // 将 DiscontiguousAttributedSubstring 转换为 AttributedString 再检查
                let selectedAttributedString = AttributedString(selectedText)
                formatState = detectFormatStateInSelection(selectedAttributedString, currentState: formatState)
            }
            
            // 检测文本样式（标题、正文等）
            formatState.textStyle = detectTextStyle(in: typingAttrs)
        } else {
            // macOS 26.0 以下的版本使用简化逻辑
            // 这里可以添加回退逻辑，或者保持格式状态为默认值
            print("[MiNoteEditorV2] macOS 版本低于 26.0，使用简化格式检测")
        }
        
        // 发送格式状态
        sendFormatState(formatState)
    }
    
    /// 检测选中文本的格式状态
    private func detectFormatStateInSelection(_ text: AttributedString, currentState: FormatState) -> FormatState {
        var state = currentState
        
        if #available(macOS 26.0, *) {
            var boldCount = 0
            var italicCount = 0
            var underlineCount = 0
            var strikethroughCount = 0
            var highlightCount = 0
            var totalRuns = 0
            
            // 遍历所有 runs（属性段）
            for run in text.runs {
                totalRuns += 1
                
                // 检查字体样式
                if let font = run.font {
                    let resolvedFont = font.resolve(in: fontResolutionContext)
                    if resolvedFont.isBold {
                        boldCount += 1
                    }
                    // 检查斜体：通过字体描述符检查
                    let testString = NSAttributedString(string: "A", attributes: [.font: font])
                    if let nsFont = testString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                        let fontDescriptor = nsFont.fontDescriptor
                        let symbolicTraits = fontDescriptor.symbolicTraits
                        if symbolicTraits.contains(.italic) {
                            italicCount += 1
                        }
                    }
                }
                
                // 检查下划线
                if run.underlineStyle != nil {
                    underlineCount += 1
                }
                
                // 检查删除线
                if run.strikethroughStyle != nil {
                    strikethroughCount += 1
                }
                
                // 检查高亮（背景色）
                if run.backgroundColor != nil {
                    highlightCount += 1
                }
            }
            
            // 如果大部分 runs 都有该格式，则认为该格式是激活的
            if totalRuns > 0 {
                state.isBold = boldCount > totalRuns / 2
                state.isItalic = italicCount > totalRuns / 2
                state.isUnderline = underlineCount > totalRuns / 2
                state.isStrikethrough = strikethroughCount > totalRuns / 2
                state.hasHighlight = highlightCount > totalRuns / 2
            }
        } else {
            // macOS 26.0 以下的版本使用简化逻辑
            print("[MiNoteEditorV2] macOS 版本低于 26.0，使用简化格式检测")
        }
        
        return state
    }
    
    /// 检测文本样式（标题、正文等）
    private func detectTextStyle(in attributes: AttributeContainer) -> FormatMenuView.TextStyle {
        if #available(macOS 26.0, *) {
            guard let font = attributes.font else {
                return .body
            }
            
            let resolvedFont = font.resolve(in: fontResolutionContext)
            // 注意：Font 没有直接的 pointSize 属性，需要通过其他方式判断
            // 这里简化处理，根据字体是否为加粗和大字体来判断
            if resolvedFont.isBold {
                // 可以根据字体大小进一步判断标题级别
                // 简化：如果加粗且字体较大，认为是标题
                return .title
            }
        }
        
        return .body
    }
    
    /// 发送格式状态通知
    private func sendFormatState(_ formatState: FormatState) {
        DispatchQueue.main.async {
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
                    "textStyle": formatState.textStyle.rawValue
                ]
            )
        }
    }
    
    // MARK: - 格式操作
    
    /// 处理格式操作
    /// 使用 transformAttributes(in:) 方法安全地更新属性
    private func handleFormatAction(_ action: FormatAction) {
        switch action {
        case .bold:
            toggleBold()
        case .italic:
            toggleItalic()
        case .underline:
            toggleUnderline()
        case .strikethrough:
            toggleStrikethrough()
        case .highlight:
            toggleHighlight()
        case .heading(let level):
            applyHeading(level: level)
        case .textAlignment(let alignment):
            applyTextAlignment(alignment: alignment)
        }
        
        // 更新格式状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            updateFormatState()
        }
    }
    
    /// 切换加粗
    /// 使用 transformAttributes(in:) 方法，这是 Apple 推荐的标准方法
    private func toggleBold() {
        if #available(macOS 26.0, *) {
            // 获取当前是否为加粗
            let typingAttrs = selection.typingAttributes(in: attributedText)
            let currentFont = typingAttrs.font ?? .default
            let resolvedFont = currentFont.resolve(in: fontResolutionContext)
            let isBold = resolvedFont.isBold
            
            // 使用 transformAttributes 安全地更新属性
            attributedText.transformAttributes(in: &selection) { attributes in
                // 获取当前字体或使用默认字体
                let font = attributes.font ?? .default
                // 切换加粗状态
                attributes.font = font.bold(!isBold)
            }
        } else {
            // macOS 26.0 以下的版本使用简化逻辑
            print("[MiNoteEditorV2] macOS 版本低于 26.0，加粗功能不可用")
        }
    }
    
    /// 切换斜体
    private func toggleItalic() {
        if #available(macOS 26.0, *) {
            // 获取当前是否为斜体
            let typingAttrs = selection.typingAttributes(in: attributedText)
            let currentFont = typingAttrs.font ?? .default
            var isItalic = false
            
            // 检查当前字体是否为斜体
            let testString = NSAttributedString(string: "A", attributes: [.font: currentFont])
            if let nsFont = testString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                let fontDescriptor = nsFont.fontDescriptor
                let symbolicTraits = fontDescriptor.symbolicTraits
                isItalic = symbolicTraits.contains(.italic)
            }
            
            attributedText.transformAttributes(in: &selection) { attributes in
                let font = attributes.font ?? .default
                // 切换斜体状态
                if isItalic {
                    // 移除斜体：使用非斜体版本
                    // 获取当前字体大小和权重
                    let testString = NSAttributedString(string: "A", attributes: [.font: font])
                    if let nsFont = testString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                        let fontSize = nsFont.pointSize
                        let fontDescriptor = nsFont.fontDescriptor
                        let symbolicTraits = fontDescriptor.symbolicTraits
                        let isBold = symbolicTraits.contains(.bold)
                        attributes.font = Font.system(size: fontSize, weight: isBold ? .bold : .regular)
                    } else {
                        // 回退：使用默认字体
                        attributes.font = Font.system(size: NSFont.systemFontSize, weight: .regular)
                    }
                } else {
                    // 添加斜体
                    attributes.font = font.italic()
                }
            }
        } else {
            // macOS 26.0 以下的版本使用简化逻辑
            print("[MiNoteEditorV2] macOS 版本低于 26.0，斜体功能不可用")
        }
    }
    
    /// 切换下划线
    private func toggleUnderline() {
        let typingAttrs = selection.typingAttributes(in: attributedText)
        let hasUnderline = typingAttrs.underlineStyle != nil
        
        attributedText.transformAttributes(in: &selection) { attributes in
            // 如果已有下划线，移除；否则添加
            if hasUnderline {
                attributes.underlineStyle = nil
            } else {
                attributes.underlineStyle = .single
            }
        }
    }
    
    /// 切换删除线
    private func toggleStrikethrough() {
        let typingAttrs = selection.typingAttributes(in: attributedText)
        let hasStrikethrough = typingAttrs.strikethroughStyle != nil
        
        attributedText.transformAttributes(in: &selection) { attributes in
            // 如果已有删除线，移除；否则添加
            if hasStrikethrough {
                attributes.strikethroughStyle = nil
            } else {
                attributes.strikethroughStyle = .single
            }
        }
    }
    
    /// 切换高亮
    private func toggleHighlight() {
        let typingAttrs = selection.typingAttributes(in: attributedText)
        let hasHighlight = typingAttrs.backgroundColor != nil
        
        attributedText.transformAttributes(in: &selection) { attributes in
            // 如果已有高亮，移除；否则添加
            if hasHighlight {
                attributes.backgroundColor = nil
            } else {
                attributes.backgroundColor = .yellow.opacity(0.5)
            }
        }
    }
    
    /// 应用标题样式
    private func applyHeading(level: Int) {
        let fontSize: CGFloat
        switch level {
        case 1:
            fontSize = 24.0
        case 2:
            fontSize = 18.0
        case 3:
            fontSize = 14.0
        default:
            fontSize = 13.0
        }
        
        attributedText.transformAttributes(in: &selection) { attributes in
            // 应用字体大小和加粗
            attributes.font = .system(size: fontSize, weight: .bold)
        }
    }
    
    /// 应用文本对齐
    private func applyTextAlignment(alignment: NSTextAlignment) {
        // 注意：AttributedString 的段落对齐需要使用 Foundation 的 API
        // 这里需要转换为 NSAttributedString 来处理段落样式
        // TODO: 实现段落对齐（需要更复杂的实现，涉及段落范围检测）
    }
    
    // MARK: - 格式状态结构
    
    struct FormatState {
        var isBold: Bool = false
        var isItalic: Bool = false
        var isUnderline: Bool = false
        var isStrikethrough: Bool = false
        var hasHighlight: Bool = false
        var textAlignment: NSTextAlignment = .left
        var textStyle: FormatMenuView.TextStyle = .body
    }
}
