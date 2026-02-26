//
//  UnifiedFormatManager+BlockFormat.swift
//  MiNoteMac
//
//  块级格式应用逻辑（标题、对齐、换行处理等）
//
//

import AppKit

// MARK: - 块级格式应用

public extension UnifiedFormatManager {

    /// 应用块级格式到选中文本
    ///
    /// 使用 BlockFormatHandler 统一处理所有块级格式
    ///
    /// - Parameters:
    ///   - format: 要应用的块级格式
    ///   - range: 应用范围
    ///   - toggle: 是否切换模式（默认 true）
    func applyBlockFormat(_ format: TextFormat, to range: NSRange, toggle: Bool = true) {
        guard let textStorage = currentTextStorage else {
            return
        }

        guard BlockFormatHandler.isBlockFormat(format) else {
            return
        }

        BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: toggle)
    }

    /// 检测指定位置的块级格式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 当前位置的块级格式（如果有）
    func detectBlockFormat(at position: Int) -> TextFormat? {
        guard let textStorage = currentTextStorage else {
            return nil
        }

        return BlockFormatHandler.detect(at: position, in: textStorage)
    }

    /// 检测指定位置的对齐方式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 当前位置的对齐方式
    func detectAlignment(at position: Int) -> NSTextAlignment {
        guard let textStorage = currentTextStorage else {
            return .left
        }

        return BlockFormatHandler.detectAlignment(at: position, in: textStorage)
    }

    /// 移除块级格式
    ///
    /// - Parameters:
    ///   - range: 移除范围
    func removeBlockFormat(from range: NSRange) {
        guard let textStorage = currentTextStorage else {
            return
        }

        BlockFormatHandler.removeBlockFormat(from: range, in: textStorage)
    }

    /// 检测列表项是否为空
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 是否为空列表项
    func isListItemEmpty(at position: Int) -> Bool {
        guard let textStorage = currentTextStorage else {
            return false
        }

        return BlockFormatHandler.isListItemEmpty(at: position, in: textStorage)
    }

    /// 获取指定位置的列表类型
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 列表类型（bulletList、numberedList、checkbox 或 nil）
    func getListType(at position: Int) -> TextFormat? {
        guard let textStorage = currentTextStorage else {
            return nil
        }

        return BlockFormatHandler.getListType(at: position, in: textStorage)
    }

    /// 检测是否是列表格式
    ///
    /// - Parameters:
    ///   - position: 检测位置
    /// - Returns: 是否是列表格式
    func isList(at position: Int) -> Bool {
        guard let textStorage = currentTextStorage else {
            return false
        }

        return BlockFormatHandler.isList(at: position, in: textStorage)
    }

    /// 构建换行上下文
    ///
    /// - Parameters:
    ///   - position: 当前光标位置
    /// - Returns: 换行上下文
    func buildNewLineContext(at position: Int) -> NewLineContext {
        guard let textStorage = currentTextStorage else {
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

        // 使用安全位置来检测格式
        let blockFormat: TextFormat? = if safePositionForLineRange < textStorage.length {
            BlockFormatHandler.detect(at: safePositionForLineRange, in: textStorage)
        } else if safePositionForLineRange > 0 {
            BlockFormatHandler.detect(at: safePositionForLineRange - 1, in: textStorage)
        } else {
            nil
        }

        let alignment: NSTextAlignment = if safePositionForLineRange < textStorage.length {
            BlockFormatHandler.detectAlignment(at: safePositionForLineRange, in: textStorage)
        } else if safePositionForLineRange > 0 {
            BlockFormatHandler.detectAlignment(at: safePositionForLineRange - 1, in: textStorage)
        } else {
            .left
        }

        let isListEmpty = BlockFormatHandler.isListItemEmpty(at: position, in: textStorage)

        return NewLineContext(
            currentLineRange: lineRange,
            currentBlockFormat: blockFormat,
            currentAlignment: alignment,
            isListItemEmpty: isListEmpty
        )
    }

    /// 处理换行
    ///
    /// 根据当前行的格式类型决定换行行为：
    /// - 内联格式：清除，不继承
    /// - 标题格式：清除，新行变为普通正文
    /// - 列表格式：非空时继承，空时取消格式
    /// - 引用格式：继承
    /// - 对齐属性：继承
    ///
    /// - Returns: 是否已处理换行（true 表示已处理，调用方不需要执行默认行为）
    func handleNewLine() -> Bool {
        guard let textView = currentTextView else {
            return false
        }

        // 构建换行上下文
        let context = NewLineContext.build(from: textView)

        // 调用 NewLineHandler 处理换行
        return NewLineHandler.handleNewLine(context: context, textView: textView)
    }
}
