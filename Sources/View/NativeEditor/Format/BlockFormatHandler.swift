//
//  BlockFormatHandler.swift
//  MiNoteMac
//
//  块级格式处理器 - 统一处理标题、列表、引用等块级格式
//  负责格式的应用、检测、移除和互斥逻辑
//
//

import AppKit
import Foundation

// MARK: - 块级格式处理器

/// 块级格式处理器
/// 统一处理所有块级格式（标题、列表、引用）
@MainActor
public struct BlockFormatHandler {

    // MARK: - 常量

    /// 大标题字体大小 (23pt)
    /// 使用 FontSizeManager 统一管理
    public static var heading1Size: CGFloat {
        FontSizeManager.shared.heading1Size
    }

    /// 二级标题字体大小 (20pt)
    /// 使用 FontSizeManager 统一管理
    public static var heading2Size: CGFloat {
        FontSizeManager.shared.heading2Size
    }

    /// 三级标题字体大小 (17pt)
    /// 使用 FontSizeManager 统一管理
    public static var heading3Size: CGFloat {
        FontSizeManager.shared.heading3Size
    }

    /// 缩进单位（像素）
    public static let indentUnit: CGFloat = 20

    /// 列表项目符号宽度
    public static let bulletWidth: CGFloat = 24

    /// 有序列表编号宽度
    public static let orderNumberWidth: CGFloat = 28

    /// 复选框宽度
    public static let checkboxWidth: CGFloat = 24

    /// 引用块边框宽度
    public static let quoteBorderWidth: CGFloat = 3

    /// 引用块内边距
    public static let quotePadding: CGFloat = 12

    /// 默认行间距（与正文一致）
    public static let defaultLineSpacing: CGFloat = 4

    /// 默认段落间距（与正文一致）
    public static let defaultParagraphSpacing: CGFloat = 8

    /// 正文字体大小 (14pt)
    /// 使用 FontSizeManager 统一管理
    public static var bodyFontSize: CGFloat {
        FontSizeManager.shared.bodySize
    }

    /// 默认字体 (14pt)
    /// 使用 FontSizeManager 统一管理
    public static var defaultFont: NSFont {
        FontSizeManager.shared.defaultFont
    }

    // MARK: - 格式应用

    /// 应用块级格式到指定范围
    ///
    /// 统一处理所有块级格式的应用逻辑：
    /// - 标题：设置字体大小和粗细
    /// - 列表：设置列表类型和段落样式
    /// - 引用：设置引用块标记和背景
    ///
    /// 注意：应用新的块级格式会自动移除旧的块级格式（互斥）
    /// 对齐格式是独立的，不与其他块级格式互斥
    ///
    /// 互斥规则：
    /// - 标题和列表格式互斥：应用标题时移除列表，应用列表时移除标题
    /// - 列表行始终使用正文字体大小（14pt）
    ///
    /// - Parameters:
    ///   - format: 要应用的块级格式
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - toggle: 是否切换模式（true 则切换，false 则强制应用）
    public static func apply(
        _ format: TextFormat,
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool = true
    ) {
        guard isBlockFormat(format) else {
            return
        }

        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        if format.category == .alignment {
            applyAlignmentFormat(format, to: lineRange, in: textStorage, toggle: toggle)
            return
        }

        let currentFormat = detect(at: lineRange.location, in: textStorage)

        if toggle, currentFormat == format {
            removeBlockFormat(from: lineRange, in: textStorage)
            return
        }

        if isHeadingFormat(format) {
            let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)
            if listType != .none {
                ListFormatHandler.handleHeadingListMutualExclusion(in: textStorage, range: lineRange)
            }
        }

        if currentFormat != nil, currentFormat != format {
            if !isListFormat(format), !isHeadingFormat(format) {
                removeBlockFormat(from: lineRange, in: textStorage)
            } else if isHeadingFormat(format), !isListFormat(currentFormat!) {
                removeBlockFormat(from: lineRange, in: textStorage)
            } else if isListFormat(format), !isHeadingFormat(currentFormat!) {
                removeBlockFormat(from: lineRange, in: textStorage)
            }
        }

        switch format {
        case .heading1:
            applyHeading(level: 1, to: lineRange, in: textStorage)
        case .heading2:
            applyHeading(level: 2, to: lineRange, in: textStorage)
        case .heading3:
            applyHeading(level: 3, to: lineRange, in: textStorage)
        case .bulletList:
            applyBulletList(to: lineRange, in: textStorage)
        case .numberedList:
            applyNumberedList(to: lineRange, in: textStorage)
        case .checkbox:
            applyCheckbox(to: lineRange, in: textStorage)
        case .quote:
            applyQuote(to: lineRange, in: textStorage)
        case .alignCenter:
            applyAlignment(.center, to: lineRange, in: textStorage)
        case .alignRight:
            applyAlignment(.right, to: lineRange, in: textStorage)
        default:
            break
        }
    }

    // MARK: - 格式检测

    /// 检测指定位置的块级格式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 当前位置的块级格式（如果有）
    public static func detect(at position: Int, in textStorage: NSTextStorage) -> TextFormat? {
        guard position >= 0, position < textStorage.length else {
            return nil
        }

        let attributes = textStorage.attributes(at: position, effectiveRange: nil)

        // 检测标题格式
        if let headingLevel = detectHeadingLevel(from: attributes) {
            switch headingLevel {
            case 1: return .heading1
            case 2: return .heading2
            case 3: return .heading3
            default: break
            }
        }

        // 检测列表格式
        if let listType = attributes[.listType] as? ListType {
            switch listType {
            case .bullet: return .bulletList
            case .ordered: return .numberedList
            case .checkbox: return .checkbox
            case .none: break
            }
        }

        // 检测引用格式
        if let isQuote = attributes[.quoteBlock] as? Bool, isQuote {
            return .quote
        }

        return nil
    }

    /// 检测指定位置的对齐方式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 当前位置的对齐方式
    public static func detectAlignment(at position: Int, in textStorage: NSTextStorage) -> NSTextAlignment {
        guard position >= 0, position < textStorage.length else {
            return .left
        }

        let attributes = textStorage.attributes(at: position, effectiveRange: nil)

        if let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle {
            return paragraphStyle.alignment
        }

        return .left
    }

    // MARK: - 格式移除

    /// 移除块级格式
    ///
    /// - Parameters:
    ///   - range: 移除范围
    ///   - textStorage: 文本存储
    public static func removeBlockFormat(from range: NSRange, in textStorage: NSTextStorage) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        // 检测当前是否有列表格式
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)

        // 如果有列表格式，使用 ListFormatHandler 移除（会正确移除附件）
        if listType != .none {
            ListFormatHandler.removeListFormat(from: textStorage, range: lineRange)
            return
        }

        textStorage.beginEditing()

        // 移除标题格式（通过设置正文字体大小）
        textStorage.addAttribute(.font, value: defaultFont, range: lineRange)

        // 移除列表格式属性（备用，以防 ListFormatHandler 未处理）
        textStorage.removeAttribute(.listType, range: lineRange)
        textStorage.removeAttribute(.listIndent, range: lineRange)
        textStorage.removeAttribute(.listNumber, range: lineRange)
        textStorage.removeAttribute(.checkboxLevel, range: lineRange)
        textStorage.removeAttribute(.checkboxChecked, range: lineRange)

        // 移除引用格式
        textStorage.removeAttribute(.quoteBlock, range: lineRange)
        textStorage.removeAttribute(.quoteIndent, range: lineRange)
        textStorage.removeAttribute(.quoteBlockId, range: lineRange)

        // 重置段落样式（保留对齐方式）
        let currentAlignment = detectAlignment(at: lineRange.location, in: textStorage)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = currentAlignment
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

        // 移除引用块背景色（但保留高亮）
        // 只有当是引用块时才移除背景色
        if let isQuote = textStorage.attribute(.quoteBlock, at: lineRange.location, effectiveRange: nil) as? Bool, isQuote {
            textStorage.removeAttribute(.backgroundColor, range: lineRange)
        }

        textStorage.endEditing()
    }

    // MARK: - 空列表项检测

    /// 检测列表项是否为空
    ///
    /// 空列表项定义：只包含列表符号（附件），没有实际内容
    ///
    /// 检测逻辑：
    /// 1. 首先获取光标所在行的范围
    /// 2. 检查该行是否有列表格式（通过检查行内任意位置的 listType 属性或列表附件）
    /// 3. 获取行内容，移除附件字符后检查是否为空
    /// 4. 如果只有附件没有其他内容，则认为是空列表项
    ///
    /// - Parameters:
    ///   - position: 检测位置（光标位置）
    ///   - textStorage: 文本存储
    /// - Returns: 是否为空列表项
    public static func isListItemEmpty(at position: Int, in textStorage: NSTextStorage) -> Bool {
        guard position >= 0 && position <= textStorage.length else {
            return false
        }

        let string = textStorage.string as NSString

        // 获取当前行范围
        // 注意：当 position 等于 textStorage.length 时（光标在文档末尾），
        // 需要使用前一个位置来获取行范围
        let safePosition: Int
        if position >= textStorage.length && textStorage.length > 0 {
            safePosition = textStorage.length - 1
        } else if position > 0 && position < textStorage.length {
            // 如果光标在换行符位置，使用前一个位置来获取当前行
            let charAtPosition = string.character(at: position)
            if charAtPosition == 0x0A { // 换行符 \n
                safePosition = position - 1
            } else {
                safePosition = position
            }
        } else {
            safePosition = max(0, min(position, textStorage.length - 1))
        }

        let lineRange = string.lineRange(for: NSRange(location: safePosition, length: 0))

        guard lineRange.length > 0 else {
            return false
        }

        // 检查整行是否有列表格式或列表附件
        var hasListFormat = false
        var hasListAttachment = false

        textStorage.enumerateAttributes(in: lineRange, options: []) { attrs, _, _ in
            // 检查是否有列表类型属性
            if let listType = attrs[.listType] as? ListType, listType != .none {
                hasListFormat = true
            }

            // 检查是否有列表附件
            if let attachment = attrs[.attachment] {
                if attachment is BulletAttachment || attachment is OrderAttachment || attachment is InteractiveCheckboxAttachment {
                    hasListAttachment = true
                }
            }
        }

        // 如果没有列表格式和列表附件，则不是列表项
        guard hasListFormat || hasListAttachment else {
            return false
        }

        // 获取行内容
        let lineContent = string.substring(with: lineRange)

        // 移除换行符
        let trimmedContent = lineContent.trimmingCharacters(in: .newlines)

        // 移除附件字符（Unicode 对象替换字符 \u{FFFC}）
        let contentWithoutAttachment = trimmedContent.replacingOccurrences(of: "\u{FFFC}", with: "")

        // 空列表项：移除附件后内容为空或只有空白字符
        let isEmpty = contentWithoutAttachment.trimmingCharacters(in: .whitespaces).isEmpty

        return isEmpty
    }

    /// 获取指定位置的列表类型
    ///
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 列表类型（bulletList、numberedList、checkbox 或 nil）
    public static func getListType(at position: Int, in textStorage: NSTextStorage) -> TextFormat? {
        guard position >= 0, position < textStorage.length else {
            return nil
        }

        let attributes = textStorage.attributes(at: position, effectiveRange: nil)

        if let listType = attributes[.listType] as? ListType {
            switch listType {
            case .bullet: return .bulletList
            case .ordered: return .numberedList
            case .checkbox: return .checkbox
            case .none: return nil
            }
        }

        return nil
    }

    /// 检测是否是列表格式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 是否是列表格式
    public static func isList(at position: Int, in textStorage: NSTextStorage) -> Bool {
        getListType(at: position, in: textStorage) != nil
    }

    /// 获取列表项的实际内容（不包含列表符号）
    ///
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 列表项内容
    public static func getListItemContent(at position: Int, in textStorage: NSTextStorage) -> String {
        guard position >= 0, position < textStorage.length else {
            return ""
        }

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        let lineContent = string.substring(with: lineRange)

        // 移除换行符
        return lineContent.trimmingCharacters(in: .newlines)
    }

    // MARK: - 辅助方法 - 格式判断

    /// 判断是否是块级格式
    ///
    /// - Parameter format: 格式类型
    /// - Returns: 是否是块级格式
    public nonisolated static func isBlockFormat(_ format: TextFormat) -> Bool {
        switch format.category {
        case .blockTitle, .blockList, .blockQuote, .alignment:
            true
        case .inline:
            false
        }
    }

    /// 判断是否是标题格式
    ///
    /// - Parameter format: 格式类型
    /// - Returns: 是否是标题格式
    public nonisolated static func isHeadingFormat(_ format: TextFormat) -> Bool {
        format.category == .blockTitle
    }

    /// 判断是否是列表格式
    ///
    /// - Parameter format: 格式类型
    /// - Returns: 是否是列表格式
    public nonisolated static func isListFormat(_ format: TextFormat) -> Bool {
        format.category == .blockList
    }

    // MARK: - 私有方法 - 标题格式

    /// 应用标题格式
    /// 使用常规字重（.regular），不默认加粗
    ///
    /// 标题格式完全通过字体大小来标识，不再使用 headingLevel 属性
    ///
    /// - Parameters:
    ///   - level: 标题级别（1-3）
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private static func applyHeading(level: Int, to range: NSRange, in textStorage: NSTextStorage) {
        let fontSize: CGFloat

        switch level {
        case 1:
            fontSize = heading1Size
        case 2:
            fontSize = heading2Size
        case 3:
            fontSize = heading3Size
        default:
            return
        }

        // 使用常规字重，标题不默认加粗
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)

        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: range)
        textStorage.endEditing()
    }

    /// 从属性中检测标题级别
    /// 完全基于字体大小检测，因为在小米笔记中字体大小和标题类型是一一对应的
    /// - Parameter attributes: 属性字典
    /// - Returns: 标题级别（1-3），如果不是标题则返回 nil
    private static func detectHeadingLevel(from attributes: [NSAttributedString.Key: Any]) -> Int? {
        // 通过字体大小判断，使用 FontSizeManager 的检测逻辑
        if let font = attributes[.font] as? NSFont {
            let level = FontSizeManager.shared.detectHeadingLevel(fontSize: font.pointSize)
            return level > 0 ? level : nil
        }

        return nil
    }

    // MARK: - 私有方法 - 列表格式

    /// 应用无序列表格式
    ///
    /// 使用 ListFormatHandler 统一处理列表格式
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - indent: 缩进级别（默认为 1）
    private static func applyBulletList(to range: NSRange, in textStorage: NSTextStorage, indent: Int = 1) {
        // 使用 ListFormatHandler 统一处理无序列表格式
        // 这确保了列表附件的正确创建和列表与标题的互斥处理
        ListFormatHandler.applyBulletList(to: textStorage, range: range, indent: indent)
    }

    /// 应用有序列表格式
    ///
    /// 使用 ListFormatHandler 统一处理列表格式
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - number: 列表编号（默认为 1）
    ///   - indent: 缩进级别（默认为 1）
    private static func applyNumberedList(to range: NSRange, in textStorage: NSTextStorage, number: Int = 1, indent: Int = 1) {
        // 使用 ListFormatHandler 统一处理有序列表格式
        // 这确保了列表附件的正确创建和列表与标题的互斥处理
        ListFormatHandler.applyOrderedList(to: textStorage, range: range, number: number, indent: indent)
    }

    /// 应用复选框格式
    ///
    /// 使用 ListFormatHandler 统一处理复选框列表格式
    /// 这确保了列表附件的正确创建和列表与标题的互斥处理
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - indent: 缩进级别（默认为 1）
    ///   - level: 复选框级别（默认为 3）
    private static func applyCheckbox(to range: NSRange, in textStorage: NSTextStorage, indent: Int = 1, level: Int = 3) {
        // 使用 ListFormatHandler 统一处理复选框列表格式
        // 这确保了：
        // 1. 在行首插入 InteractiveCheckboxAttachment
        // 2. 设置列表类型属性
        // 3. 处理标题格式互斥
        ListFormatHandler.applyCheckboxList(to: textStorage, range: range, indent: indent, level: level)
    }

    /// 创建列表段落样式
    ///
    /// - Parameters:
    ///   - indent: 缩进级别
    ///   - bulletWidth: 项目符号宽度
    /// - Returns: 段落样式
    private static func createListParagraphStyle(indent: Int, bulletWidth: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseIndent = CGFloat(indent - 1) * indentUnit

        style.firstLineHeadIndent = baseIndent
        style.headIndent = baseIndent + bulletWidth
        style.tabStops = [NSTextTab(textAlignment: .left, location: baseIndent + bulletWidth)]
        style.defaultTabInterval = indentUnit

        // 设置行间距和段落间距（与正文一致）
        style.lineSpacing = defaultLineSpacing
        style.paragraphSpacing = defaultParagraphSpacing

        return style
    }

    // MARK: - 私有方法 - 引用格式

    /// 应用引用格式
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - indent: 缩进级别（默认为 1）
    private static func applyQuote(to range: NSRange, in textStorage: NSTextStorage, indent: Int = 1) {
        textStorage.beginEditing()

        textStorage.addAttribute(.quoteBlock, value: true, range: range)
        textStorage.addAttribute(.quoteIndent, value: indent, range: range)

        let paragraphStyle = createQuoteParagraphStyle(indent: indent)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        // 设置引用块背景色
        let quoteBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
        textStorage.addAttribute(.backgroundColor, value: quoteBackgroundColor, range: range)

        textStorage.endEditing()
    }

    /// 创建引用段落样式
    ///
    /// - Parameter indent: 缩进级别
    /// - Returns: 段落样式
    private static func createQuoteParagraphStyle(indent: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseIndent = CGFloat(indent - 1) * indentUnit

        style.firstLineHeadIndent = baseIndent + quoteBorderWidth + quotePadding
        style.headIndent = baseIndent + quoteBorderWidth + quotePadding

        return style
    }

    // MARK: - 私有方法 - 对齐格式

    /// 应用对齐格式（带切换逻辑）
    ///
    /// 对齐格式是独立的，不与其他块级格式互斥
    ///
    /// - Parameters:
    ///   - format: 对齐格式
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - toggle: 是否切换模式
    private static func applyAlignmentFormat(
        _ format: TextFormat,
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool
    ) {
        let currentAlignment = detectAlignment(at: range.location, in: textStorage)

        let targetAlignment: NSTextAlignment
        switch format {
        case .alignCenter:
            targetAlignment = .center
        case .alignRight:
            targetAlignment = .right
        default:
            return
        }

        // 切换模式：如果已经是该对齐方式，则恢复左对齐
        if toggle, currentAlignment == targetAlignment {
            applyAlignment(.left, to: range, in: textStorage)
        } else {
            applyAlignment(targetAlignment, to: range, in: textStorage)
        }
    }

    /// 应用对齐格式
    ///
    /// - Parameters:
    ///   - alignment: 对齐方式
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private static func applyAlignment(_ alignment: NSTextAlignment, to range: NSRange, in textStorage: NSTextStorage) {
        textStorage.beginEditing()

        // 获取现有的段落样式或创建新的
        var existingStyle: NSMutableParagraphStyle?
        textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, _, stop in
            if let style = value as? NSParagraphStyle {
                existingStyle = style.mutableCopy() as? NSMutableParagraphStyle
                stop.pointee = true
            }
        }

        let paragraphStyle = existingStyle ?? NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment

        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        textStorage.endEditing()
    }
}

// MARK: - 块级格式集合扩展

public extension Set<TextFormat> {

    /// 获取集合中的所有块级格式
    var blockFormats: Set<TextFormat> {
        filter { BlockFormatHandler.isBlockFormat($0) }
    }

    /// 检查是否包含任何块级格式
    var hasBlockFormats: Bool {
        contains { BlockFormatHandler.isBlockFormat($0) }
    }

    /// 获取集合中的标题格式
    var headingFormat: TextFormat? {
        first { BlockFormatHandler.isHeadingFormat($0) }
    }

    /// 获取集合中的列表格式
    var listFormat: TextFormat? {
        first { BlockFormatHandler.isListFormat($0) }
    }
}
