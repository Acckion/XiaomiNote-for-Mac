//
//  UnifiedFormatManager+TypingAttributes.swift
//  MiNoteMac
//
//  typingAttributes 同步逻辑
//
//

import AppKit

// MARK: - typingAttributes 同步

extension UnifiedFormatManager {

    /// 同步 typingAttributes
    ///
    /// 根据上下文设置 typingAttributes：
    /// - 换行后：清除内联格式，保留需要继承的格式
    /// - 光标移动后：根据当前位置的格式状态同步
    /// - 格式应用后：更新 typingAttributes 以反映新格式
    ///
    /// - Parameter newLineContext: 换行上下文（可选，用于换行后的同步）
    public func syncTypingAttributes(for newLineContext: NewLineContext? = nil) {
        guard let textView = currentTextView else {
            return
        }

        if let context = newLineContext {
            // 换行后的同步：根据继承规则设置 typingAttributes
            syncTypingAttributesAfterNewLine(context: context, textView: textView)
        } else {
            // 光标移动或格式应用后的同步
            syncTypingAttributesAtCursor(textView: textView)
        }
    }

    /// 换行后同步 typingAttributes
    ///
    /// 根据换行上下文设置新行的 typingAttributes：
    /// - 清除所有内联格式
    /// - 保留需要继承的块级格式
    /// - 保留对齐属性
    ///
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    func syncTypingAttributesAfterNewLine(context: NewLineContext, textView: NSTextView) {
        // 构建清除内联格式后的基础属性
        var attrs = InlineFormatHandler.buildCleanTypingAttributes()

        attrs[.paragraphStyle] = ParagraphStyleFactory.makeDefault(alignment: context.currentAlignment)

        // 根据块级格式设置继承属性
        if context.shouldInheritFormat, let blockFormat = context.currentBlockFormat {
            switch blockFormat {
            case .bulletList:
                attrs[.listType] = ListType.bullet
                attrs[.listIndent] = 1

            case .numberedList:
                attrs[.listType] = ListType.ordered
                attrs[.listIndent] = 1

            case .checkbox:
                attrs[.listType] = ListType.checkbox
                attrs[.listIndent] = 1
                attrs[.checkboxLevel] = 3

            case .quote:
                attrs[.quoteBlock] = true
                attrs[.quoteIndent] = 1
                // 设置引用块背景色
                let quoteBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
                attrs[.backgroundColor] = quoteBackgroundColor

            default:
                break
            }
        }

        textView.typingAttributes = attrs
    }

    /// 光标位置同步 typingAttributes
    ///
    /// 根据当前光标位置的格式状态同步 typingAttributes
    ///
    /// - Parameter textView: NSTextView 实例
    func syncTypingAttributesAtCursor(textView: NSTextView) {
        guard let textStorage = textView.textStorage else {
            return
        }

        let selectedRange = textView.selectedRange()
        let position = selectedRange.location

        // 如果有选中文本，不需要同步 typingAttributes
        if selectedRange.length > 0 {
            return
        }

        // 获取当前位置的属性
        let attrs: [NSAttributedString.Key: Any] = if position > 0, position <= textStorage.length {
            // 使用前一个字符的属性
            textStorage.attributes(at: position - 1, effectiveRange: nil)
        } else if position < textStorage.length {
            // 使用当前位置的属性
            textStorage.attributes(at: position, effectiveRange: nil)
        } else {
            // 空文档或文档末尾，使用默认属性
            InlineFormatHandler.buildCleanTypingAttributes()
        }

        textView.typingAttributes = attrs
    }
}
