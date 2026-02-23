//
//  ListBehaviorHandler+DeleteKey.swift
//  MiNoteMac
//
//  列表行为处理器 - 删除键处理
//  从 ListBehaviorHandler.swift 拆分
//
//

import AppKit
import Foundation

// MARK: - 删除键处理

public extension ListBehaviorHandler {

    /// 处理列表项中的删除键（Backspace）
    ///
    /// 当光标在列表项内容区域起始位置按下删除键时：
    /// - 如果是空列表项：只删除列表标记，保留空行
    /// - 如果是有内容的列表项：将当前列表项的内容合并到上一行
    ///
    /// - Parameter textView: NSTextView 实例
    /// - Returns: 是否已处理（true 表示已处理，调用方不需要执行默认行为）
    static func handleBackspaceKey(
        textView: NSTextView
    ) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        let selectedRange = textView.selectedRange()
        let position = selectedRange.location

        // 如果有选择范围，不处理（让默认行为删除选中内容）
        guard selectedRange.length == 0 else {
            return false
        }

        // 获取列表项信息
        guard let listInfo = getListItemInfo(in: textStorage, at: position) else {
            // 不是列表项，不处理
            return false
        }

        // 检查光标是否在内容区域起始位置
        guard position == listInfo.contentStartPosition else {
            // 光标不在内容起始位置，不处理（让默认行为删除字符）
            return false
        }

        // 无论是空列表项还是有内容的列表项，都只删除列表标记，保持行结构不变
        return removeListMarkerOnly(textView: textView, textStorage: textStorage, listInfo: listInfo)
    }

    /// 只删除列表标记，保留空行
    ///
    /// 用于空列表项按删除键时，只删除列表标记（序号、项目符号或勾选框），
    /// 保留空行结构，不合并到上一行
    ///
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    ///   - listInfo: 列表项信息
    /// - Returns: 是否成功删除
    private static func removeListMarkerOnly(
        textView: NSTextView,
        textStorage: NSTextStorage,
        listInfo: ListItemInfo
    ) -> Bool {
        let lineRange = listInfo.lineRange
        let lineStart = lineRange.location
        let isOrderedList = listInfo.listType == .ordered

        textStorage.beginEditing()

        // 1. 删除列表附件（序号、项目符号或勾选框）
        if let markerRange = listInfo.markerRange {
            textStorage.deleteCharacters(in: markerRange)
        }

        // 2. 重新计算行范围（因为删除了附件）
        let deletedLength = listInfo.markerRange?.length ?? 0
        let newLineLength = max(0, lineRange.length - deletedLength)
        let newLineRange = NSRange(location: lineStart, length: newLineLength)

        // 3. 移除列表格式属性，恢复为普通正文格式
        if newLineRange.length > 0 {
            // 移除所有列表相关属性
            textStorage.removeAttribute(.listType, range: newLineRange)
            textStorage.removeAttribute(.listIndent, range: newLineRange)
            textStorage.removeAttribute(.listNumber, range: newLineRange)
            textStorage.removeAttribute(.checkboxLevel, range: newLineRange)
            textStorage.removeAttribute(.checkboxChecked, range: newLineRange)

            let paragraphStyle = ParagraphStyleFactory.makeDefault()
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)

            // 确保使用正文字体
            textStorage.addAttribute(.font, value: defaultFont, range: newLineRange)
        }

        textStorage.endEditing()

        // 4. 更新光标位置到行首
        textView.setSelectedRange(NSRange(location: lineStart, length: 0))

        // 5. 更新 typingAttributes 为普通正文
        let defaultStyle = ParagraphStyleFactory.makeDefault()
        textView.typingAttributes = [
            .font: defaultFont,
            .paragraphStyle: defaultStyle,
        ]

        // 6. 如果是有序列表，更新后续编号
        if isOrderedList {
            // 计算下一行的起始位置
            let nextLineStart = lineStart + newLineLength
            if nextLineStart < textStorage.length {
                updateOrderedListNumbers(in: textStorage, from: nextLineStart)
            }
        }

        return true
    }

    /// 检查光标是否在列表项内容起始位置
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 光标位置
    /// - Returns: 是否在内容起始位置
    static func isCursorAtContentStart(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard let listInfo = getListItemInfo(in: textStorage, at: position) else {
            return false
        }

        return position == listInfo.contentStartPosition
    }
}
