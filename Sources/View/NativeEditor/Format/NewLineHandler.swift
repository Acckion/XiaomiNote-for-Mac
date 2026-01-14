//
//  NewLineHandler.swift
//  MiNoteMac
//
//  换行处理器 - 统一处理换行时的格式继承逻辑
//  负责内联格式清除、块级格式继承、空列表项处理等
//
//  _Requirements: 2.1-2.6, 4.1-4.4, 5.1-5.6, 6.1-6.2, 7.1-7.3, 8.1, 8.3, 8.4_
//

import Foundation
import AppKit

// MARK: - 换行处理器

/// 换行处理器
/// 统一处理所有换行时的格式继承逻辑
/// _Requirements: 8.1, 8.3, 8.4_
public struct NewLineHandler {
    
    // MARK: - 常量
    
    /// 默认字体
    /// 注意：使用 nonisolated(unsafe) 因为 NSFont 不是 Sendable，但这里是只读常量
    /// 修复：使用 13pt（正文字体大小），与 FormatAttributesBuilder.bodyFontSize 保持一致
    /// _Requirements: 1.6, 1.7_
    nonisolated(unsafe) public static let defaultFont: NSFont = NSFont.systemFont(ofSize: 13)
    
    // MARK: - 主要方法
    
    /// 处理换行
    /// 
    /// 根据当前行的格式类型决定换行行为：
    /// - 内联格式：清除，不继承
    /// - 标题格式：清除，新行变为普通正文
    /// - 列表格式：非空时继承，空时取消格式
    /// - 引用格式：继承
    /// - 对齐属性：继承
    /// 
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    /// - Returns: 是否已处理换行（true 表示已处理，调用方不需要执行默认行为）
    /// _Requirements: 8.1, 8.3, 8.4_
    public static func handleNewLine(context: NewLineContext, textView: NSTextView) -> Bool {
        guard let textStorage = textView.textStorage else {
            print("[NewLineHandler] 警告：textStorage 不可用")
            return false
        }
        
        let selectedRange = textView.selectedRange()
        
        // 2. 根据块级格式类型处理
        guard let blockFormat = context.currentBlockFormat else {
            // 没有块级格式，手动处理换行以确保内联格式被清除
            // _Requirements: 2.1-2.6, 7.1-7.3_
            return handlePlainTextNewLine(context: context, textView: textView, textStorage: textStorage)
        }
        
        switch blockFormat.category {
        case .blockTitle:
            // 标题格式：换行后新行变为普通正文
            // _Requirements: 4.1-4.4_
            return handleTitleNewLine(context: context, textView: textView, textStorage: textStorage)
            
        case .blockList:
            // 列表格式：根据是否为空决定行为
            // _Requirements: 5.1-5.6_
            if context.isListItemEmpty {
                // 空列表项：取消格式，不换行
                return handleEmptyListItem(context: context, textView: textView, textStorage: textStorage)
            } else {
                // 非空列表项：继承格式
                return handleListNewLine(context: context, textView: textView, textStorage: textStorage, format: blockFormat)
            }
            
        case .blockQuote:
            // 引用格式：继承
            // _Requirements: 6.1, 6.2_
            return handleQuoteNewLine(context: context, textView: textView, textStorage: textStorage)
            
        case .alignment:
            // 对齐属性：手动处理换行以确保内联格式被清除
            // _Requirements: 2.1-2.6, 7.1-7.3_
            return handlePlainTextNewLine(context: context, textView: textView, textStorage: textStorage)
            
        case .inline:
            // 内联格式不应该出现在这里，但也需要手动处理换行
            return handlePlainTextNewLine(context: context, textView: textView, textStorage: textStorage)
        }
    }
    
    /// 处理普通文本换行
    /// 
    /// 普通文本（没有块级格式）换行时：
    /// - 清除所有内联格式
    /// - 继承对齐属性
    /// 
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 是否已处理
    /// _Requirements: 2.1-2.6, 7.1-7.3_
    private static func handlePlainTextNewLine(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool {
        print("[NewLineHandler] 处理普通文本换行")
        
        let selectedRange = textView.selectedRange()
        
        // 构建清除内联格式后的属性（用于换行符和新行）
        let cleanAttrs = buildCleanTypingAttributes(alignment: context.currentAlignment)
        
        textStorage.beginEditing()
        
        // 使用带有清除属性的 NSAttributedString 插入换行符
        // 这样换行符本身不会带有内联格式属性
        let newlineString = NSAttributedString(string: "\n", attributes: cleanAttrs)
        textStorage.replaceCharacters(in: selectedRange, with: newlineString)
        
        textStorage.endEditing()
        
        // 移动光标到新行
        let newPosition = selectedRange.location + 1
        textView.setSelectedRange(NSRange(location: newPosition, length: 0))
        
        // 设置新行的 typingAttributes（清除内联格式，继承对齐属性）
        textView.typingAttributes = cleanAttrs
        
        print("[NewLineHandler] 普通文本换行完成，已清除内联格式")
        return true
    }
    
    /// 判断是否应该继承格式
    /// 
    /// - Parameter format: 格式类型
    /// - Returns: 是否应该继承
    /// _Requirements: 2.1-2.6, 4.1-4.4, 5.1-5.3, 6.1-6.2, 7.1-7.3_
    public static func shouldInheritFormat(_ format: TextFormat?) -> Bool {
        guard let format = format else {
            return false
        }
        return format.shouldInheritOnNewLine
    }
    
    /// 处理空列表项回车
    /// 
    /// 空列表项回车时：
    /// - 移除列表格式
    /// - 不换行
    /// - 当前行变为普通正文
    /// 
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 是否已处理
    /// _Requirements: 5.4, 5.5, 5.6_
    public static func handleEmptyListItem(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool {
        print("[NewLineHandler] 处理空列表项回车")
        
        textStorage.beginEditing()
        
        // 移除列表格式
        BlockFormatHandler.removeBlockFormat(from: context.currentLineRange, in: textStorage)
        
        textStorage.endEditing()
        
        // 更新 typingAttributes 为普通正文
        var attrs = buildCleanTypingAttributes(alignment: context.currentAlignment)
        textView.typingAttributes = attrs
        
        print("[NewLineHandler] 空列表项已转换为普通正文")
        return true
    }
    
    // MARK: - 内联格式清除
    
    /// 清除 typingAttributes 中的所有内联格式
    /// 
    /// 换行时清除：
    /// - 加粗（字体特性）
    /// - 斜体（字体特性和 obliqueness）
    /// - 下划线
    /// - 删除线
    /// - 高亮（背景色，但保留引用块背景）
    /// 
    /// - Parameter textView: NSTextView 实例
    /// _Requirements: 2.1-2.6_
    public static func clearInlineFormatsFromTypingAttributes(textView: NSTextView) {
        var attrs = textView.typingAttributes
        
        // 使用 InlineFormatHandler 移除内联格式
        attrs = InlineFormatHandler.removeInlineFormats(from: attrs)
        
        textView.typingAttributes = attrs
        print("[NewLineHandler] 已清除 typingAttributes 中的内联格式")
    }
    
    // MARK: - 标题格式处理
    
    /// 处理标题行换行
    /// 
    /// 标题行换行后新行变为普通正文
    /// 
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 是否已处理
    /// _Requirements: 4.1-4.4_
    private static func handleTitleNewLine(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool {
        print("[NewLineHandler] 处理标题行换行")
        
        let selectedRange = textView.selectedRange()
        
        // 构建清除内联格式后的属性（用于换行符和新行）
        let cleanAttrs = buildCleanTypingAttributes(alignment: context.currentAlignment)
        
        textStorage.beginEditing()
        
        // 使用带有清除属性的 NSAttributedString 插入换行符
        let newlineString = NSAttributedString(string: "\n", attributes: cleanAttrs)
        textStorage.replaceCharacters(in: selectedRange, with: newlineString)
        
        textStorage.endEditing()
        
        // 移动光标到新行
        let newPosition = selectedRange.location + 1
        textView.setSelectedRange(NSRange(location: newPosition, length: 0))
        
        // 设置新行的 typingAttributes 为普通正文（继承对齐属性）
        textView.typingAttributes = cleanAttrs
        
        print("[NewLineHandler] 标题行换行完成，新行为普通正文")
        return true
    }
    
    // MARK: - 列表格式处理
    
    /// 处理非空列表项换行
    /// 
    /// 非空列表项换行后继承列表格式：
    /// - 有序列表：序号递增
    /// - 无序列表：保持相同格式
    /// - Checkbox：保持相同格式
    /// 
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    ///   - format: 列表格式类型
    /// - Returns: 是否已处理
    /// _Requirements: 5.1-5.3_
    private static func handleListNewLine(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage,
        format: TextFormat
    ) -> Bool {
        print("[NewLineHandler] 处理列表项换行: \(format.displayName)")
        
        let selectedRange = textView.selectedRange()
        let position = selectedRange.location
        
        // 获取当前列表的缩进级别
        let indent = getListIndent(at: position, in: textStorage)
        
        // 构建清除内联格式后的属性（用于换行符）
        let cleanAttrs = buildCleanTypingAttributes(alignment: context.currentAlignment)
        
        textStorage.beginEditing()
        
        // 使用带有清除属性的 NSAttributedString 插入换行符
        let newlineString = NSAttributedString(string: "\n", attributes: cleanAttrs)
        textStorage.replaceCharacters(in: selectedRange, with: newlineString)
        
        // 在新行应用列表格式
        let newLineStart = selectedRange.location + 1
        let newLineRange = NSRange(location: newLineStart, length: 0)
        
        switch format {
        case .bulletList:
            // 无序列表：继承格式
            applyBulletListToNewLine(at: newLineStart, indent: indent, textStorage: textStorage)
            
        case .numberedList:
            // 有序列表：序号递增
            let currentNumber = getListNumber(at: position, in: textStorage)
            let newNumber = currentNumber + 1
            applyNumberedListToNewLine(at: newLineStart, number: newNumber, indent: indent, textStorage: textStorage)
            
        case .checkbox:
            // Checkbox：继承格式
            applyCheckboxToNewLine(at: newLineStart, indent: indent, textStorage: textStorage)
            
        default:
            break
        }
        
        textStorage.endEditing()
        
        // 移动光标到新行内容开始位置
        let prefixLength = getListPrefixLength(format: format)
        let newCursorPosition = newLineStart + prefixLength
        textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        
        // 设置 typingAttributes（继承对齐属性，但清除内联格式）
        var attrs = cleanAttrs
        attrs[.listType] = getListType(for: format)
        attrs[.listIndent] = indent
        textView.typingAttributes = attrs
        
        print("[NewLineHandler] 列表项换行完成")
        return true
    }
    
    // MARK: - 引用格式处理
    
    /// 处理引用块换行
    /// 
    /// 引用块换行后继承引用格式
    /// 
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 是否已处理
    /// _Requirements: 6.1, 6.2_
    private static func handleQuoteNewLine(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool {
        print("[NewLineHandler] 处理引用块换行")
        
        let selectedRange = textView.selectedRange()
        let position = selectedRange.location
        
        // 获取当前引用的缩进级别
        let indent = getQuoteIndent(at: position, in: textStorage)
        
        // 构建清除内联格式后的属性（用于换行符）
        let cleanAttrs = buildCleanTypingAttributes(alignment: context.currentAlignment)
        
        textStorage.beginEditing()
        
        // 使用带有清除属性的 NSAttributedString 插入换行符
        let newlineString = NSAttributedString(string: "\n", attributes: cleanAttrs)
        textStorage.replaceCharacters(in: selectedRange, with: newlineString)
        
        // 在新行应用引用格式
        let newLineStart = selectedRange.location + 1
        applyQuoteToNewLine(at: newLineStart, indent: indent, textStorage: textStorage)
        
        textStorage.endEditing()
        
        // 移动光标到新行
        textView.setSelectedRange(NSRange(location: newLineStart, length: 0))
        
        // 设置 typingAttributes（继承引用格式和对齐属性，但清除内联格式）
        var attrs = cleanAttrs
        attrs[.quoteBlock] = true
        attrs[.quoteIndent] = indent
        textView.typingAttributes = attrs
        
        print("[NewLineHandler] 引用块换行完成")
        return true
    }
    
    // MARK: - 对齐属性处理
    
    /// 继承对齐属性
    /// 
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    /// _Requirements: 7.1-7.3_
    private static func inheritAlignment(context: NewLineContext, textView: NSTextView) {
        var attrs = textView.typingAttributes
        
        // 获取或创建段落样式
        let paragraphStyle: NSMutableParagraphStyle
        if let existingStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
            paragraphStyle = existingStyle.mutableCopy() as! NSMutableParagraphStyle
        } else {
            paragraphStyle = NSMutableParagraphStyle()
        }
        
        // 设置对齐方式
        paragraphStyle.alignment = context.currentAlignment
        attrs[.paragraphStyle] = paragraphStyle
        
        textView.typingAttributes = attrs
        print("[NewLineHandler] 继承对齐属性: \(context.currentAlignment.rawValue)")
    }
    
    // MARK: - 辅助方法 - typingAttributes 构建
    
    /// 构建清除内联格式后的 typingAttributes
    /// 
    /// - Parameter alignment: 对齐方式
    /// - Returns: 属性字典
    /// _Requirements: 2.1-2.6_
    public static func buildCleanTypingAttributes(alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        var attrs = InlineFormatHandler.buildCleanTypingAttributes()
        
        // 设置对齐方式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        attrs[.paragraphStyle] = paragraphStyle
        
        return attrs
    }

    
    // MARK: - 辅助方法 - 列表处理
    
    /// 获取列表缩进级别
    /// 
    /// - Parameters:
    ///   - position: 位置
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 缩进级别
    private static func getListIndent(at position: Int, in textStorage: NSTextStorage) -> Int {
        guard position >= 0 && position < textStorage.length else {
            return 1
        }
        
        let attrs = textStorage.attributes(at: position, effectiveRange: nil)
        return attrs[.listIndent] as? Int ?? 1
    }
    
    /// 获取列表编号
    /// 
    /// - Parameters:
    ///   - position: 位置
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 列表编号
    private static func getListNumber(at position: Int, in textStorage: NSTextStorage) -> Int {
        guard position >= 0 && position < textStorage.length else {
            return 1
        }
        
        let attrs = textStorage.attributes(at: position, effectiveRange: nil)
        return attrs[.listNumber] as? Int ?? 1
    }
    
    /// 获取列表前缀长度
    /// 
    /// - Parameter format: 列表格式
    /// - Returns: 前缀长度
    private static func getListPrefixLength(format: TextFormat) -> Int {
        switch format {
        case .bulletList:
            return 2 // "• "
        case .numberedList:
            return 3 // "1. " (假设单位数)
        case .checkbox:
            return 1 // 附件字符
        default:
            return 0
        }
    }
    
    /// 获取 ListType 枚举值
    /// 
    /// - Parameter format: TextFormat
    /// - Returns: ListType
    private static func getListType(for format: TextFormat) -> ListType {
        switch format {
        case .bulletList:
            return .bullet
        case .numberedList:
            return .ordered
        case .checkbox:
            return .checkbox
        default:
            return .none
        }
    }
    
    /// 应用无序列表到新行
    /// 
    /// - Parameters:
    ///   - position: 插入位置
    ///   - indent: 缩进级别
    ///   - textStorage: NSTextStorage 实例
    private static func applyBulletListToNewLine(at position: Int, indent: Int, textStorage: NSTextStorage) {
        let bullet = "• "
        var attributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .listType: ListType.bullet,
            .listIndent: indent
        ]
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + 24
        attributes[.paragraphStyle] = paragraphStyle
        
        let bulletString = NSAttributedString(string: bullet, attributes: attributes)
        textStorage.insert(bulletString, at: position)
    }
    
    /// 应用有序列表到新行
    /// 
    /// - Parameters:
    ///   - position: 插入位置
    ///   - number: 列表编号
    ///   - indent: 缩进级别
    ///   - textStorage: NSTextStorage 实例
    private static func applyNumberedListToNewLine(at position: Int, number: Int, indent: Int, textStorage: NSTextStorage) {
        let orderText = "\(number). "
        var attributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .listType: ListType.ordered,
            .listIndent: indent,
            .listNumber: number
        ]
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + 28
        attributes[.paragraphStyle] = paragraphStyle
        
        let orderString = NSAttributedString(string: orderText, attributes: attributes)
        textStorage.insert(orderString, at: position)
    }
    
    /// 应用 Checkbox 到新行
    /// 
    /// - Parameters:
    ///   - position: 插入位置
    ///   - indent: 缩进级别
    ///   - textStorage: NSTextStorage 实例
    private static func applyCheckboxToNewLine(at position: Int, indent: Int, textStorage: NSTextStorage) {
        // 创建复选框附件
        let checkbox = InteractiveCheckboxAttachment(checked: false)
        var attributes: [NSAttributedString.Key: Any] = [
            .attachment: checkbox,
            .listType: ListType.checkbox,
            .listIndent: indent,
            .checkboxLevel: 3
        ]
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + 24
        attributes[.paragraphStyle] = paragraphStyle
        
        let checkboxString = NSAttributedString(attachment: checkbox)
        let mutableCheckboxString = NSMutableAttributedString(attributedString: checkboxString)
        mutableCheckboxString.addAttributes(attributes, range: NSRange(location: 0, length: mutableCheckboxString.length))
        
        textStorage.insert(mutableCheckboxString, at: position)
    }
    
    // MARK: - 辅助方法 - 引用处理
    
    /// 获取引用缩进级别
    /// 
    /// - Parameters:
    ///   - position: 位置
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 缩进级别
    private static func getQuoteIndent(at position: Int, in textStorage: NSTextStorage) -> Int {
        guard position >= 0 && position < textStorage.length else {
            return 1
        }
        
        let attrs = textStorage.attributes(at: position, effectiveRange: nil)
        return attrs[.quoteIndent] as? Int ?? 1
    }
    
    /// 应用引用格式到新行
    /// 
    /// - Parameters:
    ///   - position: 插入位置
    ///   - indent: 缩进级别
    ///   - textStorage: NSTextStorage 实例
    private static func applyQuoteToNewLine(at position: Int, indent: Int, textStorage: NSTextStorage) {
        // 获取新行范围（可能是空的）
        let newLineRange = NSRange(location: position, length: 0)
        
        // 如果新行有内容，应用引用格式
        let string = textStorage.string as NSString
        if position < string.length {
            let lineRange = string.lineRange(for: newLineRange)
            
            var attributes: [NSAttributedString.Key: Any] = [
                .quoteBlock: true,
                .quoteIndent: indent
            ]
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20 + 3 + 12 // quoteBorderWidth + quotePadding
            paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + 3 + 12
            attributes[.paragraphStyle] = paragraphStyle
            
            // 设置引用块背景色
            let quoteBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
            attributes[.backgroundColor] = quoteBackgroundColor
            
            if lineRange.length > 0 {
                textStorage.addAttributes(attributes, range: lineRange)
            }
        }
    }
}

// MARK: - NewLineContext 扩展

extension NewLineContext {
    
    /// 从 textView 构建换行上下文
    /// 
    /// - Parameter textView: NSTextView 实例
    /// - Returns: 换行上下文
    public static func build(from textView: NSTextView) -> NewLineContext {
        guard let textStorage = textView.textStorage else {
            return .default
        }
        
        let selectedRange = textView.selectedRange()
        let position = selectedRange.location
        
        guard position >= 0 && position <= textStorage.length else {
            return .default
        }
        
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        
        // 检测块级格式
        let blockFormat: TextFormat?
        if position < textStorage.length {
            blockFormat = BlockFormatHandler.detect(at: position, in: textStorage)
        } else if position > 0 {
            // 如果在文档末尾，检查前一个字符的格式
            blockFormat = BlockFormatHandler.detect(at: position - 1, in: textStorage)
        } else {
            blockFormat = nil
        }
        
        // 检测对齐方式
        let alignment: NSTextAlignment
        if position < textStorage.length {
            alignment = BlockFormatHandler.detectAlignment(at: position, in: textStorage)
        } else if position > 0 {
            alignment = BlockFormatHandler.detectAlignment(at: position - 1, in: textStorage)
        } else {
            alignment = .left
        }
        
        // 检测列表项是否为空
        let isListEmpty: Bool
        if let format = blockFormat, format.category == .blockList {
            isListEmpty = BlockFormatHandler.isListItemEmpty(at: position, in: textStorage)
        } else {
            isListEmpty = false
        }
        
        return NewLineContext(
            currentLineRange: lineRange,
            currentBlockFormat: blockFormat,
            currentAlignment: alignment,
            isListItemEmpty: isListEmpty
        )
    }
}
