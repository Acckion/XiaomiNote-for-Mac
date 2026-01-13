//
//  BlockFormatHandler.swift
//  MiNoteMac
//
//  块级格式处理器 - 统一处理标题、列表、引用等块级格式
//  负责格式的应用、检测、移除和互斥逻辑
//
//  _Requirements: 3.1-3.7, 5.4, 5.5, 5.6_
//

import Foundation
import AppKit

// MARK: - 块级格式处理器

/// 块级格式处理器
/// 统一处理所有块级格式（标题、列表、引用）
/// _Requirements: 3.1-3.7_
public struct BlockFormatHandler {
    
    // MARK: - 常量
    
    /// 大标题字体大小
    public static let heading1Size: CGFloat = 24
    
    /// 二级标题字体大小
    public static let heading2Size: CGFloat = 20
    
    /// 三级标题字体大小
    public static let heading3Size: CGFloat = 16
    
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
    
    /// 默认字体
    /// 注意：使用 nonisolated(unsafe) 因为 NSFont 不是 Sendable，但这里是只读常量
    nonisolated(unsafe) public static let defaultFont: NSFont = NSFont.systemFont(ofSize: 15)
    
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
    /// - Parameters:
    ///   - format: 要应用的块级格式
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - toggle: 是否切换模式（true 则切换，false 则强制应用）
    /// _Requirements: 3.1-3.7_
    public static func apply(
        _ format: TextFormat,
        to range: NSRange,
        in textStorage: NSTextStorage,
        toggle: Bool = true
    ) {
        guard isBlockFormat(format) else {
            print("[BlockFormatHandler] 警告：尝试应用非块级格式 \(format.displayName)")
            return
        }
        
        // 获取整行范围
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        // 对齐格式是独立的，不与其他块级格式互斥
        if format.category == .alignment {
            applyAlignmentFormat(format, to: lineRange, in: textStorage, toggle: toggle)
            return
        }
        
        // 检测当前块级格式（不包括对齐）
        let currentFormat = detect(at: lineRange.location, in: textStorage)
        
        // 切换模式：如果已经是该格式，则移除
        if toggle && currentFormat == format {
            removeBlockFormat(from: lineRange, in: textStorage)
            print("[BlockFormatHandler] 移除块级格式: \(format.displayName)")
            return
        }
        
        // 互斥逻辑：先移除现有的块级格式（标题、列表、引用互斥）
        // _Requirements: 3.7_
        if currentFormat != nil {
            removeBlockFormat(from: lineRange, in: textStorage)
            print("[BlockFormatHandler] 互斥：移除现有格式 \(currentFormat!.displayName)，应用新格式 \(format.displayName)")
        }
        
        // 应用新格式
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
        
        print("[BlockFormatHandler] 应用块级格式: \(format.displayName), range: \(lineRange)")
    }
    
    // MARK: - 格式检测
    
    /// 检测指定位置的块级格式
    /// 
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 当前位置的块级格式（如果有）
    /// _Requirements: 3.1-3.6_
    public static func detect(at position: Int, in textStorage: NSTextStorage) -> TextFormat? {
        guard position >= 0 && position < textStorage.length else {
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
        guard position >= 0 && position < textStorage.length else {
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
    /// _Requirements: 3.7_
    public static func removeBlockFormat(from range: NSRange, in textStorage: NSTextStorage) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        // 移除标题格式
        textStorage.removeAttribute(.headingLevel, range: lineRange)
        textStorage.addAttribute(.font, value: defaultFont, range: lineRange)
        
        // 移除列表格式
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
        
        print("[BlockFormatHandler] 移除块级格式, range: \(lineRange)")
    }
    
    // MARK: - 空列表项检测
    
    /// 检测列表项是否为空
    /// 
    /// 空列表项定义：只包含列表符号，没有实际内容
    /// 
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 是否为空列表项
    /// _Requirements: 5.4, 5.5, 5.6_
    public static func isListItemEmpty(at position: Int, in textStorage: NSTextStorage) -> Bool {
        guard position >= 0 && position < textStorage.length else {
            return false
        }
        
        // 检测是否是列表
        let currentFormat = detect(at: position, in: textStorage)
        guard let format = currentFormat,
              format == .bulletList || format == .numberedList || format == .checkbox else {
            return false
        }
        
        // 获取当前行范围
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        
        // 获取行内容
        let lineContent = string.substring(with: lineRange)
        
        // 移除换行符后检查内容
        let trimmedContent = lineContent.trimmingCharacters(in: .newlines)
        
        // 空列表项：内容为空或只有空白字符
        return trimmedContent.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    /// 获取指定位置的列表类型
    /// 
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 列表类型（bulletList、numberedList、checkbox 或 nil）
    /// _Requirements: 5.4, 5.5, 5.6_
    public static func getListType(at position: Int, in textStorage: NSTextStorage) -> TextFormat? {
        guard position >= 0 && position < textStorage.length else {
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
    /// _Requirements: 5.4, 5.5, 5.6_
    public static func isList(at position: Int, in textStorage: NSTextStorage) -> Bool {
        return getListType(at: position, in: textStorage) != nil
    }
    
    /// 获取列表项的实际内容（不包含列表符号）
    /// 
    /// - Parameters:
    ///   - position: 检测位置
    ///   - textStorage: 文本存储
    /// - Returns: 列表项内容
    public static func getListItemContent(at position: Int, in textStorage: NSTextStorage) -> String {
        guard position >= 0 && position < textStorage.length else {
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
    public static func isBlockFormat(_ format: TextFormat) -> Bool {
        switch format.category {
        case .blockTitle, .blockList, .blockQuote, .alignment:
            return true
        case .inline:
            return false
        }
    }
    
    /// 判断是否是标题格式
    /// 
    /// - Parameter format: 格式类型
    /// - Returns: 是否是标题格式
    public static func isHeadingFormat(_ format: TextFormat) -> Bool {
        return format.category == .blockTitle
    }
    
    /// 判断是否是列表格式
    /// 
    /// - Parameter format: 格式类型
    /// - Returns: 是否是列表格式
    public static func isListFormat(_ format: TextFormat) -> Bool {
        return format.category == .blockList
    }
    
    // MARK: - 私有方法 - 标题格式
    
    /// 应用标题格式
    /// 
    /// - Parameters:
    ///   - level: 标题级别（1-3）
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private static func applyHeading(level: Int, to range: NSRange, in textStorage: NSTextStorage) {
        let fontSize: CGFloat
        let fontWeight: NSFont.Weight
        
        switch level {
        case 1:
            fontSize = heading1Size
            fontWeight = .bold
        case 2:
            fontSize = heading2Size
            fontWeight = .semibold
        case 3:
            fontSize = heading3Size
            fontWeight = .medium
        default:
            return
        }
        
        let font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        
        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: range)
        textStorage.addAttribute(.headingLevel, value: level, range: range)
        textStorage.endEditing()
    }
    
    /// 从属性中检测标题级别
    /// 
    /// - Parameter attributes: 属性字典
    /// - Returns: 标题级别（1-3），如果不是标题则返回 nil
    private static func detectHeadingLevel(from attributes: [NSAttributedString.Key: Any]) -> Int? {
        // 优先检查 headingLevel 属性
        if let level = attributes[.headingLevel] as? Int, level > 0 {
            return level
        }
        
        // 备用检测：通过字体大小判断
        if let font = attributes[.font] as? NSFont {
            let fontSize = font.pointSize
            if fontSize >= heading1Size {
                return 1
            } else if fontSize >= heading2Size {
                return 2
            } else if fontSize >= heading3Size && fontSize < heading2Size {
                return 3
            }
        }
        
        return nil
    }
    
    // MARK: - 私有方法 - 列表格式
    
    /// 应用无序列表格式
    /// 
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - indent: 缩进级别（默认为 1）
    private static func applyBulletList(to range: NSRange, in textStorage: NSTextStorage, indent: Int = 1) {
        textStorage.beginEditing()
        
        textStorage.addAttribute(.listType, value: ListType.bullet, range: range)
        textStorage.addAttribute(.listIndent, value: indent, range: range)
        
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: bulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        
        textStorage.endEditing()
    }
    
    /// 应用有序列表格式
    /// 
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - number: 列表编号（默认为 1）
    ///   - indent: 缩进级别（默认为 1）
    private static func applyNumberedList(to range: NSRange, in textStorage: NSTextStorage, number: Int = 1, indent: Int = 1) {
        textStorage.beginEditing()
        
        textStorage.addAttribute(.listType, value: ListType.ordered, range: range)
        textStorage.addAttribute(.listIndent, value: indent, range: range)
        textStorage.addAttribute(.listNumber, value: number, range: range)
        
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: orderNumberWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        
        textStorage.endEditing()
    }
    
    /// 应用复选框格式
    /// 
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///   - indent: 缩进级别（默认为 1）
    ///   - level: 复选框级别（默认为 3）
    private static func applyCheckbox(to range: NSRange, in textStorage: NSTextStorage, indent: Int = 1, level: Int = 3) {
        textStorage.beginEditing()
        
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: range)
        textStorage.addAttribute(.listIndent, value: indent, range: range)
        textStorage.addAttribute(.checkboxLevel, value: level, range: range)
        
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: checkboxWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        
        textStorage.endEditing()
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
        if toggle && currentAlignment == targetAlignment {
            applyAlignment(.left, to: range, in: textStorage)
            print("[BlockFormatHandler] 恢复左对齐")
        } else {
            applyAlignment(targetAlignment, to: range, in: textStorage)
            print("[BlockFormatHandler] 应用对齐格式: \(format.displayName)")
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

extension Set where Element == TextFormat {
    
    /// 获取集合中的所有块级格式
    public var blockFormats: Set<TextFormat> {
        return self.filter { BlockFormatHandler.isBlockFormat($0) }
    }
    
    /// 检查是否包含任何块级格式
    public var hasBlockFormats: Bool {
        return self.contains { BlockFormatHandler.isBlockFormat($0) }
    }
    
    /// 获取集合中的标题格式
    public var headingFormat: TextFormat? {
        return self.first { BlockFormatHandler.isHeadingFormat($0) }
    }
    
    /// 获取集合中的列表格式
    public var listFormat: TextFormat? {
        return self.first { BlockFormatHandler.isListFormat($0) }
    }
}
