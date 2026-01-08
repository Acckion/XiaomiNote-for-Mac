//
//  FormatManager.swift
//  MiNoteMac
//
//  格式管理器 - 处理富文本格式的应用和转换
//  需求: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7
//

import AppKit
import SwiftUI

// MARK: - 列表类型枚举

/// 列表类型
enum ListType: Equatable {
    case bullet     // 无序列表
    case ordered    // 有序列表
    case checkbox   // 复选框列表
    case none       // 非列表
}

/// 标题级别
enum HeadingLevel: Int {
    case none = 0
    case h1 = 1     // 大标题
    case h2 = 2     // 二级标题
    case h3 = 3     // 三级标题
}

// MARK: - FormatManager

/// 格式管理器 - 负责处理富文本格式的应用
@MainActor
class FormatManager {
    
    // MARK: - Singleton
    
    static let shared = FormatManager()
    
    private init() {}
    
    // MARK: - Properties
    
    /// 默认字体
    var defaultFont: NSFont = NSFont.systemFont(ofSize: 15)
    
    /// 默认文本颜色
    var defaultTextColor: NSColor = .textColor
    
    /// 高亮背景色（小米笔记格式）
    var highlightColor: NSColor = NSColor(hex: "#9affe8af") ?? NSColor.systemYellow
    
    /// 大标题字体大小
    var heading1Size: CGFloat = 24
    
    /// 二级标题字体大小
    var heading2Size: CGFloat = 20
    
    /// 三级标题字体大小
    var heading3Size: CGFloat = 16
    
    /// 缩进单位（像素）
    var indentUnit: CGFloat = 20
    
    /// 列表项目符号宽度
    var bulletWidth: CGFloat = 24
    
    /// 有序列表编号宽度
    var orderNumberWidth: CGFloat = 28
    
    /// 复选框宽度
    var checkboxWidth: CGFloat = 24
    
    // MARK: - Public Methods - 格式应用
    
    /// 应用加粗格式 (需求 2.1)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - toggle: 是否切换（true 则切换，false 则强制应用）
    func applyBold(to textStorage: NSTextStorage, range: NSRange, toggle: Bool = true) {
        applyFontTrait(.bold, to: textStorage, range: range, toggle: toggle)
    }
    
    /// 应用斜体格式 (需求 2.2)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - toggle: 是否切换
    func applyItalic(to textStorage: NSTextStorage, range: NSRange, toggle: Bool = true) {
        applyFontTrait(.italic, to: textStorage, range: range, toggle: toggle)
    }
    
    /// 应用下划线格式 (需求 2.3)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - toggle: 是否切换
    func applyUnderline(to textStorage: NSTextStorage, range: NSRange, toggle: Bool = true) {
        toggleAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            in: textStorage,
            range: range,
            toggle: toggle
        )
    }
    
    /// 应用删除线格式 (需求 2.4)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - toggle: 是否切换
    func applyStrikethrough(to textStorage: NSTextStorage, range: NSRange, toggle: Bool = true) {
        toggleAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            in: textStorage,
            range: range,
            toggle: toggle
        )
    }
    
    /// 应用高亮格式 (需求 2.5)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - color: 高亮颜色（默认使用小米笔记的高亮色）
    ///   - toggle: 是否切换
    func applyHighlight(to textStorage: NSTextStorage, range: NSRange, color: NSColor? = nil, toggle: Bool = true) {
        let highlightColor = color ?? self.highlightColor
        toggleAttribute(
            .backgroundColor,
            value: highlightColor,
            in: textStorage,
            range: range,
            toggle: toggle
        )
    }
    
    /// 应用居中对齐 (需求 2.6)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func applyCenterAlignment(to textStorage: NSTextStorage, range: NSRange) {
        applyAlignment(.center, to: textStorage, range: range)
    }
    
    /// 应用右对齐 (需求 2.7)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func applyRightAlignment(to textStorage: NSTextStorage, range: NSRange) {
        applyAlignment(.right, to: textStorage, range: range)
    }
    
    /// 应用左对齐（默认）
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func applyLeftAlignment(to textStorage: NSTextStorage, range: NSRange) {
        applyAlignment(.left, to: textStorage, range: range)
    }
    
    /// 设置缩进级别 (需求 2.8)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - level: 缩进级别（1 = 无缩进，2 = 一级缩进，以此类推）
    func setIndentLevel(to textStorage: NSTextStorage, range: NSRange, level: Int) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        let paragraphStyle = NSMutableParagraphStyle()
        let indentValue = CGFloat(max(0, level - 1)) * indentUnit
        paragraphStyle.firstLineHeadIndent = indentValue
        paragraphStyle.headIndent = indentValue
        
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 增加缩进
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func increaseIndent(to textStorage: NSTextStorage, range: NSRange) {
        let currentLevel = getCurrentIndentLevel(in: textStorage, at: range.location)
        setIndentLevel(to: textStorage, range: range, level: currentLevel + 1)
    }
    
    /// 减少缩进
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func decreaseIndent(to textStorage: NSTextStorage, range: NSRange) {
        let currentLevel = getCurrentIndentLevel(in: textStorage, at: range.location)
        setIndentLevel(to: textStorage, range: range, level: max(1, currentLevel - 1))
    }
    
    // MARK: - Public Methods - 标题格式
    
    /// 应用大标题格式 (需求 6.3)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func applyHeading1(to textStorage: NSTextStorage, range: NSRange) {
        applyHeadingStyle(to: textStorage, range: range, size: heading1Size, weight: .bold, level: .h1)
    }
    
    /// 应用二级标题格式 (需求 6.4)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func applyHeading2(to textStorage: NSTextStorage, range: NSRange) {
        applyHeadingStyle(to: textStorage, range: range, size: heading2Size, weight: .semibold, level: .h2)
    }
    
    /// 应用三级标题格式 (需求 6.5)
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func applyHeading3(to textStorage: NSTextStorage, range: NSRange) {
        applyHeadingStyle(to: textStorage, range: range, size: heading3Size, weight: .medium, level: .h3)
    }
    
    /// 移除标题格式（恢复正常文本）
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func removeHeading(from textStorage: NSTextStorage, range: NSRange) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: defaultFont, range: lineRange)
        textStorage.removeAttribute(.headingLevel, range: lineRange)
        textStorage.endEditing()
    }
    
    // MARK: - Public Methods - 列表格式 (需求 6.1, 6.2, 6.6, 6.7)
    
    /// 应用无序列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    func applyBulletList(to textStorage: NSTextStorage, range: NSRange, indent: Int = 1) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.bullet, range: lineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: lineRange)
        
        // 设置段落样式
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: bulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 应用有序列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - number: 列表编号
    ///   - indent: 缩进级别（默认为 1）
    func applyOrderedList(to textStorage: NSTextStorage, range: NSRange, number: Int = 1, indent: Int = 1) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.ordered, range: lineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: lineRange)
        textStorage.addAttribute(.listNumber, value: number, range: lineRange)
        
        // 设置段落样式
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: orderNumberWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 移除列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func removeListFormat(from textStorage: NSTextStorage, range: NSRange) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        // 移除列表相关属性
        textStorage.removeAttribute(.listType, range: lineRange)
        textStorage.removeAttribute(.listIndent, range: lineRange)
        textStorage.removeAttribute(.listNumber, range: lineRange)
        
        // 重置段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 切换无序列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func toggleBulletList(to textStorage: NSTextStorage, range: NSRange) {
        let currentListType = getListType(in: textStorage, at: range.location)
        
        if currentListType == .bullet {
            removeListFormat(from: textStorage, range: range)
        } else {
            // 如果是其他列表类型，先移除再应用
            if currentListType != .none {
                removeListFormat(from: textStorage, range: range)
            }
            applyBulletList(to: textStorage, range: range)
        }
    }
    
    /// 切换有序列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func toggleOrderedList(to textStorage: NSTextStorage, range: NSRange) {
        let currentListType = getListType(in: textStorage, at: range.location)
        
        if currentListType == .ordered {
            removeListFormat(from: textStorage, range: range)
        } else {
            // 如果是其他列表类型，先移除再应用
            if currentListType != .none {
                removeListFormat(from: textStorage, range: range)
            }
            // 计算编号
            let number = calculateListNumber(in: textStorage, at: range.location)
            applyOrderedList(to: textStorage, range: range, number: number)
        }
    }
    
    // MARK: - Public Methods - 复选框列表格式 (需求 3.1, 3.2, 3.3, 3.6)
    
    /// 应用复选框列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    ///   - level: 复选框级别（默认为 3，对应 XML 中的 level 属性）
    func applyCheckboxList(to textStorage: NSTextStorage, range: NSRange, indent: Int = 1, level: Int = 3) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: ListType.checkbox, range: lineRange)
        textStorage.addAttribute(.listIndent, value: indent, range: lineRange)
        textStorage.addAttribute(.checkboxLevel, value: level, range: lineRange)
        
        // 设置段落样式
        let paragraphStyle = createListParagraphStyle(indent: indent, bulletWidth: checkboxWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 切换复选框列表格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func toggleCheckboxList(to textStorage: NSTextStorage, range: NSRange) {
        let currentListType = getListType(in: textStorage, at: range.location)
        
        if currentListType == .checkbox {
            removeListFormat(from: textStorage, range: range)
        } else {
            // 如果是其他列表类型，先移除再应用
            if currentListType != .none {
                removeListFormat(from: textStorage, range: range)
            }
            applyCheckboxList(to: textStorage, range: range)
        }
    }
    
    /// 检测指定位置是否是复选框列表
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否是复选框列表
    func isCheckboxList(in textStorage: NSTextStorage, at position: Int) -> Bool {
        return getListType(in: textStorage, at: position) == .checkbox
    }
    
    /// 获取指定位置的复选框级别
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 复选框级别（默认为 3）
    func getCheckboxLevel(in textStorage: NSTextStorage, at position: Int) -> Int {
        guard position < textStorage.length else { return 3 }
        
        if let level = textStorage.attribute(.checkboxLevel, at: position, effectiveRange: nil) as? Int {
            return level
        }
        
        return 3
    }
    
    // MARK: - Public Methods - 引用块格式 (需求 5.1, 5.3, 5.4, 5.6)
    
    /// 应用引用块格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    func applyQuoteBlock(to textStorage: NSTextStorage, range: NSRange, indent: Int = 1) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        // 标记为引用块
        textStorage.addAttribute(.quoteBlock, value: true, range: lineRange)
        textStorage.addAttribute(.quoteIndent, value: indent, range: lineRange)
        
        // 设置段落样式
        let paragraphStyle = createQuoteParagraphStyle(indent: indent)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        // 设置引用块背景色（可选，用于视觉提示）
        let quoteBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
        textStorage.addAttribute(.backgroundColor, value: quoteBackgroundColor, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 切换引用块格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func toggleQuoteBlock(to textStorage: NSTextStorage, range: NSRange) {
        let isQuote = isQuoteBlock(in: textStorage, at: range.location)
        
        if isQuote {
            removeQuoteBlock(from: textStorage, range: range)
        } else {
            applyQuoteBlock(to: textStorage, range: range)
        }
    }
    
    /// 移除引用块格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func removeQuoteBlock(from textStorage: NSTextStorage, range: NSRange) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        // 移除引用块属性
        textStorage.removeAttribute(.quoteBlock, range: lineRange)
        textStorage.removeAttribute(.quoteIndent, range: lineRange)
        textStorage.removeAttribute(.backgroundColor, range: lineRange)
        
        // 重置段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 检测指定位置是否是引用块
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否是引用块
    func isQuoteBlock(in textStorage: NSTextStorage, at position: Int) -> Bool {
        guard position < textStorage.length else { return false }
        
        if let isQuote = textStorage.attribute(.quoteBlock, at: position, effectiveRange: nil) as? Bool {
            return isQuote
        }
        
        return false
    }
    
    /// 获取指定位置的引用块缩进级别
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 缩进级别（默认为 1）
    func getQuoteIndent(in textStorage: NSTextStorage, at position: Int) -> Int {
        guard position < textStorage.length else { return 1 }
        
        if let indent = textStorage.attribute(.quoteIndent, at: position, effectiveRange: nil) as? Int {
            return indent
        }
        
        return 1
    }
    
    /// 创建引用块段落样式
    /// - Parameter indent: 缩进级别
    /// - Returns: 段落样式
    private func createQuoteParagraphStyle(indent: Int) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseIndent = CGFloat(indent - 1) * indentUnit
        
        // 设置左侧边距（为引用块边框留出空间）
        let quoteBorderWidth: CGFloat = 3
        let quotePadding: CGFloat = 12
        
        style.firstLineHeadIndent = baseIndent + quoteBorderWidth + quotePadding
        style.headIndent = baseIndent + quoteBorderWidth + quotePadding
        
        return style
    }
    
    /// 增加列表缩进
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func increaseListIndent(to textStorage: NSTextStorage, range: NSRange) {
        let currentIndent = getListIndent(in: textStorage, at: range.location)
        let listType = getListType(in: textStorage, at: range.location)
        
        guard listType != .none else { return }
        
        let newIndent = min(currentIndent + 1, 6) // 最大 6 级缩进
        
        textStorage.beginEditing()
        
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        textStorage.addAttribute(.listIndent, value: newIndent, range: lineRange)
        
        // 更新段落样式
        let bulletWidth = listType == .ordered ? orderNumberWidth : self.bulletWidth
        let paragraphStyle = createListParagraphStyle(indent: newIndent, bulletWidth: bulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 减少列表缩进
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func decreaseListIndent(to textStorage: NSTextStorage, range: NSRange) {
        let currentIndent = getListIndent(in: textStorage, at: range.location)
        let listType = getListType(in: textStorage, at: range.location)
        
        guard listType != .none else { return }
        
        if currentIndent <= 1 {
            // 如果已经是最小缩进，移除列表格式
            removeListFormat(from: textStorage, range: range)
            return
        }
        
        let newIndent = currentIndent - 1
        
        textStorage.beginEditing()
        
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        textStorage.addAttribute(.listIndent, value: newIndent, range: lineRange)
        
        // 更新段落样式
        let bulletWidth = listType == .ordered ? orderNumberWidth : self.bulletWidth
        let paragraphStyle = createListParagraphStyle(indent: newIndent, bulletWidth: bulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    // MARK: - Public Methods - 标题格式 (需求 6.3, 6.4, 6.5)
    
    /// 切换标题格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - level: 标题级别
    func toggleHeading(to textStorage: NSTextStorage, range: NSRange, level: HeadingLevel) {
        let currentLevel = getHeadingLevelEnum(in: textStorage, at: range.location)
        
        if currentLevel == level {
            // 如果已经是该级别标题，移除标题格式
            removeHeading(from: textStorage, range: range)
        } else {
            // 应用新的标题级别
            switch level {
            case .h1:
                applyHeading1(to: textStorage, range: range)
            case .h2:
                applyHeading2(to: textStorage, range: range)
            case .h3:
                applyHeading3(to: textStorage, range: range)
            case .none:
                removeHeading(from: textStorage, range: range)
            }
        }
    }
    
    // MARK: - Public Methods - 格式检测
    
    /// 检测指定位置是否有加粗格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否有加粗格式
    func isBold(in textStorage: NSTextStorage, at position: Int) -> Bool {
        return hasFontTrait(.bold, in: textStorage, at: position)
    }
    
    /// 检测指定位置是否有斜体格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否有斜体格式
    func isItalic(in textStorage: NSTextStorage, at position: Int) -> Bool {
        return hasFontTrait(.italic, in: textStorage, at: position)
    }
    
    /// 检测指定位置是否有下划线格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否有下划线格式
    func isUnderlined(in textStorage: NSTextStorage, at position: Int) -> Bool {
        guard position < textStorage.length else { return false }
        let value = textStorage.attribute(.underlineStyle, at: position, effectiveRange: nil) as? Int
        return value != nil && value != 0
    }
    
    /// 检测指定位置是否有删除线格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否有删除线格式
    func isStrikethrough(in textStorage: NSTextStorage, at position: Int) -> Bool {
        guard position < textStorage.length else { return false }
        let value = textStorage.attribute(.strikethroughStyle, at: position, effectiveRange: nil) as? Int
        return value != nil && value != 0
    }
    
    /// 检测指定位置是否有高亮格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否有高亮格式
    func isHighlighted(in textStorage: NSTextStorage, at position: Int) -> Bool {
        guard position < textStorage.length else { return false }
        return textStorage.attribute(.backgroundColor, at: position, effectiveRange: nil) != nil
    }
    
    /// 获取指定位置的对齐方式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 对齐方式
    func getAlignment(in textStorage: NSTextStorage, at position: Int) -> NSTextAlignment {
        guard position < textStorage.length else { return .left }
        
        if let paragraphStyle = textStorage.attribute(.paragraphStyle, at: position, effectiveRange: nil) as? NSParagraphStyle {
            return paragraphStyle.alignment
        }
        
        return .left
    }
    
    /// 获取指定位置的缩进级别
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 缩进级别
    func getCurrentIndentLevel(in textStorage: NSTextStorage, at position: Int) -> Int {
        guard position < textStorage.length else { return 1 }
        
        if let paragraphStyle = textStorage.attribute(.paragraphStyle, at: position, effectiveRange: nil) as? NSParagraphStyle {
            return Int(paragraphStyle.firstLineHeadIndent / indentUnit) + 1
        }
        
        return 1
    }
    
    /// 获取指定位置的标题级别
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 标题级别（0 = 无标题，1 = 大标题，2 = 二级标题，3 = 三级标题）
    func getHeadingLevel(in textStorage: NSTextStorage, at position: Int) -> Int {
        guard position < textStorage.length else { return 0 }
        
        if let font = textStorage.attribute(.font, at: position, effectiveRange: nil) as? NSFont {
            let fontSize = font.pointSize
            if fontSize >= heading1Size {
                return 1
            } else if fontSize >= heading2Size {
                return 2
            } else if fontSize >= heading3Size && fontSize < heading2Size {
                return 3
            }
        }
        
        return 0
    }
    
    /// 获取指定位置的标题级别（枚举）
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 标题级别枚举
    func getHeadingLevelEnum(in textStorage: NSTextStorage, at position: Int) -> HeadingLevel {
        return HeadingLevel(rawValue: getHeadingLevel(in: textStorage, at: position)) ?? .none
    }
    
    /// 获取指定位置的列表类型
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 列表类型
    func getListType(in textStorage: NSTextStorage, at position: Int) -> ListType {
        guard position < textStorage.length else { return .none }
        
        if let listType = textStorage.attribute(.listType, at: position, effectiveRange: nil) as? ListType {
            return listType
        }
        
        return .none
    }
    
    /// 获取指定位置的列表缩进级别
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 缩进级别
    func getListIndent(in textStorage: NSTextStorage, at position: Int) -> Int {
        guard position < textStorage.length else { return 1 }
        
        if let indent = textStorage.attribute(.listIndent, at: position, effectiveRange: nil) as? Int {
            return indent
        }
        
        return 1
    }
    
    /// 获取指定位置的列表编号
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 列表编号
    func getListNumber(in textStorage: NSTextStorage, at position: Int) -> Int {
        guard position < textStorage.length else { return 1 }
        
        if let number = textStorage.attribute(.listNumber, at: position, effectiveRange: nil) as? Int {
            return number
        }
        
        return 1
    }
    
    /// 检测指定位置是否是无序列表
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否是无序列表
    func isBulletList(in textStorage: NSTextStorage, at position: Int) -> Bool {
        return getListType(in: textStorage, at: position) == .bullet
    }
    
    /// 检测指定位置是否是有序列表
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否是有序列表
    func isOrderedList(in textStorage: NSTextStorage, at position: Int) -> Bool {
        return getListType(in: textStorage, at: position) == .ordered
    }
    
    // MARK: - Public Methods - 格式应用（通用）
    
    /// 应用格式
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func applyFormat(_ format: TextFormat, to textStorage: NSTextStorage, range: NSRange) {
        switch format {
        case .bold:
            applyBold(to: textStorage, range: range)
        case .italic:
            applyItalic(to: textStorage, range: range)
        case .underline:
            applyUnderline(to: textStorage, range: range)
        case .strikethrough:
            applyStrikethrough(to: textStorage, range: range)
        case .highlight:
            applyHighlight(to: textStorage, range: range)
        case .heading1:
            toggleHeading(to: textStorage, range: range, level: .h1)
        case .heading2:
            toggleHeading(to: textStorage, range: range, level: .h2)
        case .heading3:
            toggleHeading(to: textStorage, range: range, level: .h3)
        case .alignCenter:
            applyCenterAlignment(to: textStorage, range: range)
        case .alignRight:
            applyRightAlignment(to: textStorage, range: range)
        case .bulletList:
            toggleBulletList(to: textStorage, range: range)
        case .numberedList:
            toggleOrderedList(to: textStorage, range: range)
        case .checkbox:
            toggleCheckboxList(to: textStorage, range: range)
        case .quote:
            toggleQuoteBlock(to: textStorage, range: range)
        default:
            break
        }
    }
    
    /// 检测格式是否激活
    /// - Parameters:
    ///   - format: 格式类型
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否激活
    func isFormatActive(_ format: TextFormat, in textStorage: NSTextStorage, at position: Int) -> Bool {
        switch format {
        case .bold:
            return isBold(in: textStorage, at: position)
        case .italic:
            return isItalic(in: textStorage, at: position)
        case .underline:
            return isUnderlined(in: textStorage, at: position)
        case .strikethrough:
            return isStrikethrough(in: textStorage, at: position)
        case .highlight:
            return isHighlighted(in: textStorage, at: position)
        case .heading1:
            return getHeadingLevel(in: textStorage, at: position) == 1
        case .heading2:
            return getHeadingLevel(in: textStorage, at: position) == 2
        case .heading3:
            return getHeadingLevel(in: textStorage, at: position) == 3
        case .alignCenter:
            return getAlignment(in: textStorage, at: position) == .center
        case .alignRight:
            return getAlignment(in: textStorage, at: position) == .right
        case .bulletList:
            return isBulletList(in: textStorage, at: position)
        case .numberedList:
            return isOrderedList(in: textStorage, at: position)
        case .checkbox:
            return isCheckboxList(in: textStorage, at: position)
        case .quote:
            return isQuoteBlock(in: textStorage, at: position)
        default:
            return false
        }
    }
    
    // MARK: - Private Methods
    
    /// 应用字体特性
    private func applyFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, to textStorage: NSTextStorage, range: NSRange, toggle: Bool) {
        guard range.length > 0 else { return }
        
        let fontManager = NSFontManager.shared
        
        textStorage.beginEditing()
        
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            let font = (value as? NSFont) ?? defaultFont
            let currentTraits = font.fontDescriptor.symbolicTraits
            let hasTrait = currentTraits.contains(trait)
            
            var newFont: NSFont?
            
            // 使用 NSFontManager 来正确处理字体特性转换
            if trait == .italic {
                if toggle && hasTrait {
                    // 移除斜体
                    newFont = fontManager.convert(font, toNotHaveTrait: .italicFontMask)
                } else if !hasTrait {
                    // 添加斜体
                    newFont = fontManager.convert(font, toHaveTrait: .italicFontMask)
                } else {
                    newFont = font
                }
            } else if trait == .bold {
                if toggle && hasTrait {
                    // 移除粗体
                    newFont = fontManager.convert(font, toNotHaveTrait: .boldFontMask)
                } else if !hasTrait {
                    // 添加粗体
                    newFont = fontManager.convert(font, toHaveTrait: .boldFontMask)
                } else {
                    newFont = font
                }
            } else {
                // 其他特性使用原来的方法
                var newTraits = currentTraits
                if toggle {
                    if hasTrait {
                        newTraits.remove(trait)
                    } else {
                        newTraits.insert(trait)
                    }
                } else {
                    newTraits.insert(trait)
                }
                let newDescriptor = font.fontDescriptor.withSymbolicTraits(newTraits)
                newFont = NSFont(descriptor: newDescriptor, size: font.pointSize)
            }
            
            if let finalFont = newFont {
                textStorage.addAttribute(.font, value: finalFont, range: attrRange)
            }
        }
        
        textStorage.endEditing()
    }
    
    /// 检测是否有字体特性
    private func hasFontTrait(_ trait: NSFontDescriptor.SymbolicTraits, in textStorage: NSTextStorage, at position: Int) -> Bool {
        guard position < textStorage.length else { return false }
        
        if let font = textStorage.attribute(.font, at: position, effectiveRange: nil) as? NSFont {
            return font.fontDescriptor.symbolicTraits.contains(trait)
        }
        
        return false
    }
    
    /// 切换属性
    private func toggleAttribute(_ key: NSAttributedString.Key, value: Any, in textStorage: NSTextStorage, range: NSRange, toggle: Bool) {
        guard range.length > 0 else { return }
        
        textStorage.beginEditing()
        
        var hasAttribute = false
        
        if toggle {
            // 检查是否已有该属性
            textStorage.enumerateAttribute(key, in: range, options: []) { existingValue, _, stop in
                if existingValue != nil {
                    hasAttribute = true
                    stop.pointee = true
                }
            }
        }
        
        if hasAttribute {
            textStorage.removeAttribute(key, range: range)
        } else {
            textStorage.addAttribute(key, value: value, range: range)
        }
        
        textStorage.endEditing()
    }
    
    /// 应用标题样式
    private func applyHeadingStyle(to textStorage: NSTextStorage, range: NSRange, size: CGFloat, weight: NSFont.Weight, level: HeadingLevel = .none) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        
        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: lineRange)
        
        // 设置标题级别属性
        if level != .none {
            textStorage.addAttribute(.headingLevel, value: level.rawValue, range: lineRange)
        }
        
        textStorage.endEditing()
    }
    
    /// 应用对齐方式
    private func applyAlignment(_ alignment: NSTextAlignment, to textStorage: NSTextStorage, range: NSRange) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        
        textStorage.beginEditing()
        
        // 获取现有的段落样式或创建新的
        var existingStyle: NSMutableParagraphStyle?
        textStorage.enumerateAttribute(.paragraphStyle, in: lineRange, options: []) { value, _, stop in
            if let style = value as? NSParagraphStyle {
                existingStyle = style.mutableCopy() as? NSMutableParagraphStyle
                stop.pointee = true
            }
        }
        
        let paragraphStyle = existingStyle ?? NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
        
        textStorage.endEditing()
    }
    
    /// 创建列表段落样式
    /// - Parameters:
    ///   - indent: 缩进级别
    ///   - bulletWidth: 项目符号宽度
    /// - Returns: 段落样式
    private func createListParagraphStyle(indent: Int, bulletWidth: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let baseIndent = CGFloat(indent - 1) * indentUnit
        
        // 设置首行缩进（为项目符号留出空间）
        style.firstLineHeadIndent = baseIndent
        // 设置后续行缩进（与项目符号后的文本对齐）
        style.headIndent = baseIndent + bulletWidth
        // 设置制表位
        style.tabStops = [NSTextTab(textAlignment: .left, location: baseIndent + bulletWidth)]
        style.defaultTabInterval = indentUnit
        
        return style
    }
    
    /// 计算列表编号
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 列表编号
    private func calculateListNumber(in textStorage: NSTextStorage, at position: Int) -> Int {
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        
        // 向上查找同级别的有序列表项
        var number = 1
        var searchPosition = lineRange.location
        let currentIndent = getListIndent(in: textStorage, at: position)
        
        while searchPosition > 0 {
            // 获取上一行的范围
            let prevLineEnd = searchPosition - 1
            let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))
            
            // 检查上一行是否是有序列表
            if prevLineRange.location < textStorage.length {
                let prevListType = getListType(in: textStorage, at: prevLineRange.location)
                let prevIndent = getListIndent(in: textStorage, at: prevLineRange.location)
                
                if prevListType == .ordered && prevIndent == currentIndent {
                    // 找到同级别的有序列表项，编号加 1
                    let prevNumber = getListNumber(in: textStorage, at: prevLineRange.location)
                    number = prevNumber + 1
                    break
                } else if prevListType == .none || prevIndent < currentIndent {
                    // 遇到非列表或更低级别的缩进，停止搜索
                    break
                }
                // 如果是更高级别的缩进，继续向上搜索
            }
            
            searchPosition = prevLineRange.location
        }
        
        return number
    }
    
    /// 更新有序列表编号（当列表发生变化时）
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - fromPosition: 起始位置
    func updateOrderedListNumbers(in textStorage: NSTextStorage, fromPosition: Int) {
        let string = textStorage.string as NSString
        var currentPosition = fromPosition
        var currentNumber = 1
        var lastIndent = 1
        
        // 先找到当前位置的编号
        let lineRange = string.lineRange(for: NSRange(location: fromPosition, length: 0))
        if lineRange.location > 0 {
            currentNumber = calculateListNumber(in: textStorage, at: lineRange.location)
        }
        
        // 从当前位置向下更新编号
        while currentPosition < textStorage.length {
            let lineRange = string.lineRange(for: NSRange(location: currentPosition, length: 0))
            let listType = getListType(in: textStorage, at: lineRange.location)
            let indent = getListIndent(in: textStorage, at: lineRange.location)
            
            if listType == .ordered {
                if indent == lastIndent {
                    // 同级别，更新编号
                    textStorage.addAttribute(.listNumber, value: currentNumber, range: lineRange)
                    currentNumber += 1
                } else if indent > lastIndent {
                    // 更深的缩进，重新开始编号
                    textStorage.addAttribute(.listNumber, value: 1, range: lineRange)
                    currentNumber = 2
                } else {
                    // 更浅的缩进，需要重新计算
                    currentNumber = calculateListNumber(in: textStorage, at: lineRange.location)
                    textStorage.addAttribute(.listNumber, value: currentNumber, range: lineRange)
                    currentNumber += 1
                }
                lastIndent = indent
            } else if listType == .none {
                // 遇到非列表项，停止更新
                break
            }
            
            // 移动到下一行
            let nextLineStart = lineRange.location + lineRange.length
            if nextLineStart >= textStorage.length {
                break
            }
            currentPosition = nextLineStart
        }
    }
    
    /// 获取 inputNumber 值（用于 XML 转换）
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: inputNumber 值（第一项为实际值，后续项为 0）
    func getInputNumber(in textStorage: NSTextStorage, at position: Int) -> Int {
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        let currentIndent = getListIndent(in: textStorage, at: position)
        
        // 检查是否是连续列表的第一项
        if lineRange.location == 0 {
            // 文档开头，返回实际编号
            return getListNumber(in: textStorage, at: position)
        }
        
        // 检查上一行
        let prevLineEnd = lineRange.location - 1
        let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))
        let prevListType = getListType(in: textStorage, at: prevLineRange.location)
        let prevIndent = getListIndent(in: textStorage, at: prevLineRange.location)
        
        if prevListType == .ordered && prevIndent == currentIndent {
            // 连续列表，返回 0
            return 0
        } else {
            // 新列表开始，返回实际编号
            return getListNumber(in: textStorage, at: position)
        }
    }
}


// MARK: - NSAttributedString.Key 扩展

extension NSAttributedString.Key {
    /// 列表类型属性键
    static let listType = NSAttributedString.Key("listType")
    
    /// 列表缩进级别属性键
    static let listIndent = NSAttributedString.Key("listIndent")
    
    /// 列表编号属性键
    static let listNumber = NSAttributedString.Key("listNumber")
    
    /// 标题级别属性键
    static let headingLevel = NSAttributedString.Key("headingLevel")
    
    /// 复选框级别属性键（对应 XML 中的 level 属性）
    static let checkboxLevel = NSAttributedString.Key("checkboxLevel")
    
    /// 复选框选中状态属性键（仅编辑器显示，不保存到 XML）
    static let checkboxChecked = NSAttributedString.Key("checkboxChecked")
}
