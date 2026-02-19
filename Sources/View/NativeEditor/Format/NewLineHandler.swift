//
//  NewLineHandler.swift
//  MiNoteMac
//
//  换行处理器 - 统一处理换行时的格式继承逻辑
//  负责内联格式清除、块级格式继承、空列表项处理等
//
//

import AppKit
import Foundation

// MARK: - 换行处理器

/// 换行处理器
/// 统一处理所有换行时的格式继承逻辑
@MainActor
public struct NewLineHandler {

    // MARK: - 常量

    /// 默认字体 (14pt)
    /// 使用 FontSizeManager 统一管理
    public static var defaultFont: NSFont {
        FontSizeManager.shared.defaultFont
    }

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
    public static func handleNewLine(context: NewLineContext, textView: NSTextView) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        let selectedRange = textView.selectedRange()

        // 2. 根据块级格式类型处理
        guard let blockFormat = context.currentBlockFormat else {
            // 没有块级格式，手动处理换行以确保内联格式被清除
            return handlePlainTextNewLine(context: context, textView: textView, textStorage: textStorage)
        }

        switch blockFormat.category {
        case .blockTitle:
            // 标题格式：换行后新行变为普通正文
            return handleTitleNewLine(context: context, textView: textView, textStorage: textStorage)

        case .blockList:
            // 列表格式：根据是否为空决定行为
            if context.isListItemEmpty {
                // 空列表项：取消格式，不换行
                return handleEmptyListItem(context: context, textView: textView, textStorage: textStorage)
            } else {
                // 非空列表项：继承格式
                return handleListNewLine(context: context, textView: textView, textStorage: textStorage, format: blockFormat)
            }

        case .blockQuote:
            // 引用格式：继承
            return handleQuoteNewLine(context: context, textView: textView, textStorage: textStorage)

        case .alignment:
            // 对齐属性：手动处理换行以确保内联格式被清除
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
    private static func handlePlainTextNewLine(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool {

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

        return true
    }

    /// 判断是否应该继承格式
    ///
    /// - Parameter format: 格式类型
    /// - Returns: 是否应该继承
    public static func shouldInheritFormat(_ format: TextFormat?) -> Bool {
        guard let format else {
            return false
        }
        return format.shouldInheritOnNewLine
    }

    /// 处理空列表项回车
    ///
    /// 空列表项回车时：
    /// - 移除列表附件（BulletAttachment 或 OrderAttachment）
    /// - 移除列表格式属性
    /// - 不换行
    /// - 当前行变为普通正文
    ///
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    /// - Returns: 是否已处理
    public static func handleEmptyListItem(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool {

        let lineRange = context.currentLineRange

        textStorage.beginEditing()

        // 1. 查找并移除列表附件（BulletAttachment 或 OrderAttachment）
        var attachmentRange: NSRange?
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is BulletAttachment || value is OrderAttachment || value is InteractiveCheckboxAttachment {
                attachmentRange = attrRange
                stop.pointee = true
            }
        }

        // 移除附件
        if let range = attachmentRange {
            textStorage.deleteCharacters(in: range)
        }

        // 2. 重新计算行范围（因为可能删除了附件）
        let newLineRange: NSRange = if let range = attachmentRange {
            NSRange(location: lineRange.location, length: max(0, lineRange.length - range.length))
        } else {
            lineRange
        }

        // 3. 移除列表格式属性
        if newLineRange.length > 0 {
            textStorage.removeAttribute(.listType, range: newLineRange)
            textStorage.removeAttribute(.listIndent, range: newLineRange)
            textStorage.removeAttribute(.listNumber, range: newLineRange)
            textStorage.removeAttribute(.checkboxLevel, range: newLineRange)
            textStorage.removeAttribute(.checkboxChecked, range: newLineRange)

            let paragraphStyle = ParagraphStyleFactory.makeDefault(alignment: context.currentAlignment)
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

            // 确保使用正文字体
            textStorage.addAttribute(.font, value: defaultFont, range: newLineRange)
        }

        textStorage.endEditing()

        // 4. 更新光标位置到行首
        textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))

        // 5. 更新 typingAttributes 为普通正文
        let attrs = buildCleanTypingAttributes(alignment: context.currentAlignment)
        textView.typingAttributes = attrs

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
    public static func clearInlineFormatsFromTypingAttributes(textView: NSTextView) {
        var attrs = textView.typingAttributes

        // 使用 InlineFormatHandler 移除内联格式
        attrs = InlineFormatHandler.removeInlineFormats(from: attrs)

        textView.typingAttributes = attrs
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
    private static func handleTitleNewLine(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool {

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

        return true
    }

    // MARK: - 列表格式处理

    /// 处理非空列表项换行
    ///
    /// 非空列表项换行后继承列表格式：
    /// - 有序列表：使用 OrderAttachment，序号递增
    /// - 无序列表：使用 BulletAttachment，保持相同格式
    /// - Checkbox：保持相同格式
    ///
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    ///   - format: 列表格式类型
    /// - Returns: 是否已处理
    private static func handleListNewLine(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage,
        format: TextFormat
    ) -> Bool {

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

        switch format {
        case .bulletList:
            // 无序列表：使用 BulletAttachment 继承格式
            applyBulletAttachmentToNewLine(at: newLineStart, indent: indent, textStorage: textStorage)

        case .numberedList:
            // 有序列表：使用 OrderAttachment，序号递增
            let currentNumber = getListNumber(at: position, in: textStorage)
            let newNumber = currentNumber + 1
            applyOrderAttachmentToNewLine(at: newLineStart, number: newNumber, indent: indent, textStorage: textStorage)

        case .checkbox:
            // Checkbox：继承格式
            applyCheckboxToNewLine(at: newLineStart, indent: indent, textStorage: textStorage)

        default:
            break
        }

        textStorage.endEditing()

        // 移动光标到新行内容开始位置（附件占用 1 个字符）
        let newCursorPosition = newLineStart + 1
        textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        // 设置 typingAttributes（继承对齐属性，但清除内联格式）
        var attrs = cleanAttrs
        attrs[.listType] = getListType(for: format)
        attrs[.listIndent] = indent
        if format == .numberedList {
            let currentNumber = getListNumber(at: position, in: textStorage)
            attrs[.listNumber] = currentNumber + 1
        }
        textView.typingAttributes = attrs

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
    private static func handleQuoteNewLine(
        context: NewLineContext,
        textView: NSTextView,
        textStorage: NSTextStorage
    ) -> Bool {

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

        return true
    }

    // MARK: - 对齐属性处理

    /// 继承对齐属性
    ///
    /// - Parameters:
    ///   - context: 换行上下文
    ///   - textView: NSTextView 实例
    private static func inheritAlignment(context: NewLineContext, textView: NSTextView) {
        var attrs = textView.typingAttributes

        // 获取或创建段落样式
        let paragraphStyle: NSMutableParagraphStyle = if let existingStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
            existingStyle.mutableCopy() as! NSMutableParagraphStyle
        } else {
            NSMutableParagraphStyle()
        }

        // 设置对齐方式
        paragraphStyle.alignment = context.currentAlignment
        attrs[.paragraphStyle] = paragraphStyle

        textView.typingAttributes = attrs
    }

    // MARK: - 辅助方法 - typingAttributes 构建

    /// 构建清除内联格式后的 typingAttributes
    ///
    /// - Parameter alignment: 对齐方式
    /// - Returns: 属性字典
    public static func buildCleanTypingAttributes(alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
        var attrs = InlineFormatHandler.buildCleanTypingAttributes()

        let paragraphStyle = ParagraphStyleFactory.makeDefault(alignment: alignment)
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
        guard position >= 0, position < textStorage.length else {
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
        guard position >= 0, position < textStorage.length else {
            return 1
        }

        // 首先尝试从属性获取
        let attrs = textStorage.attributes(at: position, effectiveRange: nil)
        if let number = attrs[.listNumber] as? Int {
            return number
        }

        // 如果没有属性，尝试从 OrderAttachment 获取
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))

        var foundNumber = 1
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, stop in
            if let orderAttachment = value as? OrderAttachment {
                foundNumber = orderAttachment.number
                stop.pointee = true
            }
        }

        return foundNumber
    }

    /// 获取 ListType 枚举值
    ///
    /// - Parameter format: TextFormat
    /// - Returns: ListType
    private static func getListType(for format: TextFormat) -> ListType {
        switch format {
        case .bulletList:
            .bullet
        case .numberedList:
            .ordered
        case .checkbox:
            .checkbox
        default:
            .none
        }
    }

    /// 应用无序列表附件到新行
    ///
    /// 使用 BulletAttachment 替代文本符号 "• "
    ///
    /// - Parameters:
    ///   - position: 插入位置
    ///   - indent: 缩进级别
    ///   - textStorage: NSTextStorage 实例
    private static func applyBulletAttachmentToNewLine(at position: Int, indent: Int, textStorage: NSTextStorage) {
        // 创建 BulletAttachment
        let bulletAttachment = BulletAttachment(indent: indent)

        // 构建附件属性
        var attributes: [NSAttributedString.Key: Any] = [
            .attachment: bulletAttachment,
            .font: defaultFont,
            .listType: ListType.bullet,
            .listIndent: indent,
        ]

        let paragraphStyle = ParagraphStyleFactory.makeList(indent: indent, bulletWidth: ParagraphStyleFactory.bulletWidth)
        attributes[.paragraphStyle] = paragraphStyle

        // 创建附件字符串
        let attachmentString = NSMutableAttributedString(attachment: bulletAttachment)
        attachmentString.addAttributes(attributes, range: NSRange(location: 0, length: attachmentString.length))

        // 插入附件
        textStorage.insert(attachmentString, at: position)
    }

    /// 应用有序列表附件到新行
    ///
    /// 使用 OrderAttachment 替代文本编号 "1. "
    ///
    /// - Parameters:
    ///   - position: 插入位置
    ///   - number: 列表编号
    ///   - indent: 缩进级别
    ///   - textStorage: NSTextStorage 实例
    private static func applyOrderAttachmentToNewLine(at position: Int, number: Int, indent: Int, textStorage: NSTextStorage) {
        // 创建 OrderAttachment
        let orderAttachment = OrderAttachment(number: number, inputNumber: 0, indent: indent)

        // 构建附件属性
        var attributes: [NSAttributedString.Key: Any] = [
            .attachment: orderAttachment,
            .font: defaultFont,
            .listType: ListType.ordered,
            .listIndent: indent,
            .listNumber: number,
        ]

        let paragraphStyle = ParagraphStyleFactory.makeList(indent: indent, bulletWidth: ParagraphStyleFactory.orderNumberWidth)
        attributes[.paragraphStyle] = paragraphStyle

        // 创建附件字符串
        let attachmentString = NSMutableAttributedString(attachment: orderAttachment)
        attachmentString.addAttributes(attributes, range: NSRange(location: 0, length: attachmentString.length))

        // 插入附件
        textStorage.insert(attachmentString, at: position)
    }

    /// 应用无序列表到新行（旧方法，保留用于兼容）
    ///
    /// - Parameters:
    ///   - position: 插入位置
    ///   - indent: 缩进级别
    ///   - textStorage: NSTextStorage 实例
    @available(*, deprecated, message: "使用 applyBulletAttachmentToNewLine 替代")
    private static func applyBulletListToNewLine(at position: Int, indent: Int, textStorage: NSTextStorage) {
        applyBulletAttachmentToNewLine(at: position, indent: indent, textStorage: textStorage)
    }

    /// 应用有序列表到新行（旧方法，保留用于兼容）
    ///
    /// - Parameters:
    ///   - position: 插入位置
    ///   - number: 列表编号
    ///   - indent: 缩进级别
    ///   - textStorage: NSTextStorage 实例
    @available(*, deprecated, message: "使用 applyOrderAttachmentToNewLine 替代")
    private static func applyNumberedListToNewLine(at position: Int, number: Int, indent: Int, textStorage: NSTextStorage) {
        applyOrderAttachmentToNewLine(at: position, number: number, indent: indent, textStorage: textStorage)
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
            .checkboxLevel: 3,
        ]

        let paragraphStyle = ParagraphStyleFactory.makeList(indent: indent, bulletWidth: ParagraphStyleFactory.bulletWidth)
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
        guard position >= 0, position < textStorage.length else {
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
                .quoteIndent: indent,
            ]

            let paragraphStyle = ParagraphStyleFactory.makeQuote(indent: indent)
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

@MainActor
public extension NewLineContext {

    /// 从 textView 构建换行上下文
    ///
    /// - Parameter textView: NSTextView 实例
    /// - Returns: 换行上下文
    static func build(from textView: NSTextView) -> NewLineContext {
        guard let textStorage = textView.textStorage else {
            return .default
        }

        let selectedRange = textView.selectedRange()
        let position = selectedRange.location

        guard position >= 0, position <= textStorage.length else {
            return .default
        }

        let string = textStorage.string as NSString

        // 计算安全位置，用于获取当前行范围
        // 当光标在换行符位置时，使用前一个位置来获取当前行
        let safePositionForLineRange: Int
        if position > 0, position < textStorage.length {
            let charAtPosition = string.character(at: position)
            if charAtPosition == 0x0A { // 换行符 \n
                safePositionForLineRange = position - 1
            } else {
                safePositionForLineRange = position
            }
        } else if position >= textStorage.length, textStorage.length > 0 {
            safePositionForLineRange = textStorage.length - 1
        } else {
            safePositionForLineRange = position
        }

        let lineRange = string.lineRange(for: NSRange(location: safePositionForLineRange, length: 0))

        // 检测块级格式
        // 使用安全位置来检测格式
        let blockFormat: TextFormat? = if safePositionForLineRange < textStorage.length {
            BlockFormatHandler.detect(at: safePositionForLineRange, in: textStorage)
        } else if safePositionForLineRange > 0 {
            // 如果在文档末尾，检查前一个字符的格式
            BlockFormatHandler.detect(at: safePositionForLineRange - 1, in: textStorage)
        } else {
            nil
        }

        // 检测对齐方式
        let alignment: NSTextAlignment = if safePositionForLineRange < textStorage.length {
            BlockFormatHandler.detectAlignment(at: safePositionForLineRange, in: textStorage)
        } else if safePositionForLineRange > 0 {
            BlockFormatHandler.detectAlignment(at: safePositionForLineRange - 1, in: textStorage)
        } else {
            .left
        }

        // 检测列表项是否为空
        let isListEmpty: Bool = if let format = blockFormat, format.category == .blockList {
            BlockFormatHandler.isListItemEmpty(at: position, in: textStorage)
        } else {
            false
        }

        return NewLineContext(
            currentLineRange: lineRange,
            currentBlockFormat: blockFormat,
            currentAlignment: alignment,
            isListItemEmpty: isListEmpty
        )
    }
}
