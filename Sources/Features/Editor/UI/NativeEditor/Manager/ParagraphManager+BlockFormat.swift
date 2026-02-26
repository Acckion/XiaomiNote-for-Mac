import AppKit
import Foundation

// MARK: - 标题/引用/对齐格式操作

public extension ParagraphManager {

    // MARK: - 标题应用

    /// 应用标题格式
    ///
    /// 设置标题字体大小，使用 ParagraphStyleFactory 创建段落样式。
    /// 应用前会处理标题与列表的互斥关系。
    ///
    /// - Parameters:
    ///   - level: 标题级别（1-3）
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    static func applyHeading(
        level: Int,
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        let fontSize: CGFloat
        switch level {
        case 1: fontSize = FontSizeConstants.heading1
        case 2: fontSize = FontSizeConstants.heading2
        case 3: fontSize = FontSizeConstants.heading3
        default: return
        }

        // 处理标题与列表互斥
        handleHeadingListMutualExclusion(in: textStorage, range: range)

        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let alignFormat = detectAlignment(at: range.location, in: textStorage)
        let currentAlignment: NSTextAlignment = switch alignFormat {
        case .center: .center
        case .right: .right
        default: .left
        }

        textStorage.beginEditing()
        textStorage.addAttribute(.font, value: font, range: range)

        let paragraphStyle = ParagraphStyleFactory.makeDefault(alignment: currentAlignment, fontSize: fontSize)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        textStorage.endEditing()
    }

    // MARK: - 引用应用

    /// 应用引用格式
    ///
    /// 设置引用块属性、引用段落样式、引用背景色
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    static func applyQuote(
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        textStorage.beginEditing()

        textStorage.addAttribute(.quoteBlock, value: true, range: range)
        textStorage.addAttribute(.quoteIndent, value: 1, range: range)

        let paragraphStyle = ParagraphStyleFactory.makeQuote()
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        let quoteBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
        textStorage.addAttribute(.backgroundColor, value: quoteBackgroundColor, range: range)

        textStorage.endEditing()
    }

    // MARK: - 格式移除

    /// 移除所有块级格式，恢复正文样式
    ///
    /// 重置字体为正文大小、移除所有块级属性、恢复默认段落样式。
    /// 如果当前行有列表格式，会先移除列表附件。
    ///
    /// - Parameters:
    ///   - range: 移除范围
    ///   - textStorage: 文本存储
    static func removeBlockFormat(
        from range: NSRange,
        in textStorage: NSTextStorage
    ) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        // 如果有列表格式，先移除列表（包含附件删除）
        let listType = detectListType(at: lineRange.location, in: textStorage)
        if listType != .none {
            removeListFormat(from: textStorage, range: lineRange)
            return
        }

        let defaultFont = NSFont.systemFont(ofSize: FontSizeConstants.body, weight: .regular)
        let alignmentFormat = detectAlignment(at: lineRange.location, in: textStorage)
        let nsAlignment: NSTextAlignment = switch alignmentFormat {
        case .center: .center
        case .right: .right
        default: .left
        }

        textStorage.beginEditing()

        textStorage.addAttribute(.font, value: defaultFont, range: lineRange)

        // 移除列表属性（备用）
        textStorage.removeAttribute(.listType, range: lineRange)
        textStorage.removeAttribute(.listIndent, range: lineRange)
        textStorage.removeAttribute(.listNumber, range: lineRange)
        textStorage.removeAttribute(.checkboxLevel, range: lineRange)
        textStorage.removeAttribute(.checkboxChecked, range: lineRange)

        // 移除引用属性
        textStorage.removeAttribute(.quoteBlock, range: lineRange)
        textStorage.removeAttribute(.quoteIndent, range: lineRange)
        textStorage.removeAttribute(.quoteBlockId, range: lineRange)

        let paragraphStyle = ParagraphStyleFactory.makeDefault(alignment: nsAlignment)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

        textStorage.endEditing()
    }

    // MARK: - 对齐格式

    /// 切换对齐格式
    ///
    /// 已是目标对齐则恢复左对齐，否则应用目标对齐
    ///
    /// - Parameters:
    ///   - alignment: 目标对齐方式
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    static func toggleAlignment(
        _ alignment: NSTextAlignment,
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        let currentAlignmentFormat = detectAlignment(at: range.location, in: textStorage)
        let currentNSAlignment: NSTextAlignment = switch currentAlignmentFormat {
        case .center: .center
        case .right: .right
        default: .left
        }

        let targetAlignment: NSTextAlignment = if currentNSAlignment == alignment {
            .left
        } else {
            alignment
        }

        applyAlignment(targetAlignment, to: range, in: textStorage)
    }

    // MARK: - 标题与列表互斥

    /// 处理标题与列表的互斥
    ///
    /// 应用标题时查找并移除列表附件和列表属性
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    @discardableResult
    static func handleHeadingListMutualExclusion(
        in textStorage: NSTextStorage,
        range: NSRange
    ) -> Bool {
        let listType = detectListType(at: range.location, in: textStorage)
        if listType != .none {
            removeListFormat(from: textStorage, range: range)
            return true
        }
        return false
    }

    // MARK: - 私有方法

    /// 应用对齐格式
    private static func applyAlignment(
        _ alignment: NSTextAlignment,
        to range: NSRange,
        in textStorage: NSTextStorage
    ) {
        textStorage.beginEditing()

        // 获取现有段落样式并修改对齐方式
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
