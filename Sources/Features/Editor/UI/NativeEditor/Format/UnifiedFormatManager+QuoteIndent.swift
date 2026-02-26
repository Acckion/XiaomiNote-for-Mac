//
//  UnifiedFormatManager+QuoteIndent.swift
//  MiNoteMac
//
//  引用操作和缩进操作逻辑
//
//

import AppKit

// MARK: - 引用操作

public extension UnifiedFormatManager {

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

    /// 应用引用块格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    ///   - indent: 缩进级别（默认为 1）
    func applyQuoteBlock(to textStorage: NSTextStorage, range: NSRange, indent: Int = 1) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        textStorage.beginEditing()

        textStorage.addAttribute(.quoteBlock, value: true, range: lineRange)
        textStorage.addAttribute(.quoteIndent, value: indent, range: lineRange)

        let paragraphStyle = ParagraphStyleFactory.makeQuote(indent: indent)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

        let quoteBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
        textStorage.addAttribute(.backgroundColor, value: quoteBackgroundColor, range: lineRange)

        textStorage.endEditing()
    }

    /// 移除引用块格式
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - range: 应用范围
    func removeQuoteBlock(from textStorage: NSTextStorage, range: NSRange) {
        let lineRange = (textStorage.string as NSString).lineRange(for: range)

        textStorage.beginEditing()

        textStorage.removeAttribute(.quoteBlock, range: lineRange)
        textStorage.removeAttribute(.quoteIndent, range: lineRange)
        textStorage.removeAttribute(.backgroundColor, range: lineRange)

        let paragraphStyle = ParagraphStyleFactory.makeDefault()
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

        textStorage.endEditing()
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
}

// MARK: - 缩进操作

public extension UnifiedFormatManager {

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
}
