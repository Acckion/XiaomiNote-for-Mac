//
//  ListBehaviorHandler+EnterKey.swift
//  MiNoteMac
//
//  列表行为处理器 - 回车键处理和有序列表编号更新
//  从 ListBehaviorHandler.swift 拆分
//
//

import AppKit
import Foundation

// MARK: - 有序列表编号更新

public extension ListBehaviorHandler {

    /// 更新有序列表编号
    ///
    /// 从指定位置开始，更新后续所有有序列表项的编号
    /// 确保编号从 1 开始连续递增
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - startPosition: 起始位置
    static func updateOrderedListNumbers(
        in textStorage: NSTextStorage,
        from startPosition: Int
    ) {
        guard startPosition >= 0, startPosition < textStorage.length else {
            return
        }

        let string = textStorage.string as NSString
        var currentPosition = startPosition
        var expectedNumber = 1
        var currentIndent: Int?

        // 首先，向上查找同级别的有序列表项，确定起始编号
        let startLineRange = string.lineRange(for: NSRange(location: startPosition, length: 0))
        let startListType = ListFormatHandler.detectListType(in: textStorage, at: startLineRange.location)

        if startListType == .ordered {
            currentIndent = ListFormatHandler.getListIndent(in: textStorage, at: startLineRange.location)

            // 向上查找同级别的有序列表项
            var searchPosition = startLineRange.location
            while searchPosition > 0 {
                let prevLineEnd = searchPosition - 1
                let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))

                let prevListType = ListFormatHandler.detectListType(in: textStorage, at: prevLineRange.location)
                let prevIndent = ListFormatHandler.getListIndent(in: textStorage, at: prevLineRange.location)

                if prevListType == .ordered && prevIndent == currentIndent {
                    // 找到同级别的有序列表项
                    let prevNumber = ListFormatHandler.getListNumber(in: textStorage, at: prevLineRange.location)
                    expectedNumber = prevNumber + 1
                    break
                } else if prevListType == .none || prevIndent < (currentIndent ?? 1) {
                    // 遇到非列表或更低级别的缩进，停止搜索
                    break
                }

                searchPosition = prevLineRange.location
            }
        }

        // 从起始位置开始，更新后续的有序列表编号
        textStorage.beginEditing()

        while currentPosition < textStorage.length {
            let lineRange = string.lineRange(for: NSRange(location: currentPosition, length: 0))
            let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)
            let indent = ListFormatHandler.getListIndent(in: textStorage, at: lineRange.location)

            // 如果不是有序列表或缩进级别不同，停止更新
            if listType != .ordered {
                break
            }

            if currentIndent == nil {
                currentIndent = indent
            } else if indent != currentIndent {
                break
            }

            // 更新编号
            updateOrderAttachmentNumber(in: textStorage, lineRange: lineRange, newNumber: expectedNumber)
            textStorage.addAttribute(.listNumber, value: expectedNumber, range: lineRange)

            expectedNumber += 1

            // 移动到下一行
            currentPosition = lineRange.location + lineRange.length
        }

        textStorage.endEditing()
    }

    /// 从列表开头重新编号整个有序列表
    ///
    /// 找到包含指定位置的有序列表的开头，然后从 1 开始重新编号整个列表
    /// 确保编号始终从 1 开始连续递增
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 列表中的任意位置
    static func renumberOrderedListFromBeginning(
        in textStorage: NSTextStorage,
        at position: Int
    ) {
        guard position >= 0, position < textStorage.length else {
            return
        }

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)

        // 只处理有序列表
        guard listType == .ordered else {
            return
        }

        let currentIndent = ListFormatHandler.getListIndent(in: textStorage, at: lineRange.location)

        // 向上查找列表的开头
        var listStartPosition = lineRange.location
        var searchPosition = lineRange.location

        while searchPosition > 0 {
            let prevLineEnd = searchPosition - 1
            let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))

            let prevListType = ListFormatHandler.detectListType(in: textStorage, at: prevLineRange.location)
            let prevIndent = ListFormatHandler.getListIndent(in: textStorage, at: prevLineRange.location)

            if prevListType == .ordered, prevIndent == currentIndent {
                // 找到同级别的有序列表项，继续向上搜索
                listStartPosition = prevLineRange.location
                searchPosition = prevLineRange.location
            } else {
                // 遇到非有序列表或不同缩进级别，停止搜索
                break
            }
        }

        // 从列表开头开始，编号从 1 开始
        var currentPosition = listStartPosition
        var expectedNumber = 1

        textStorage.beginEditing()

        while currentPosition < textStorage.length {
            let currentLineRange = string.lineRange(for: NSRange(location: currentPosition, length: 0))
            let currentListType = ListFormatHandler.detectListType(in: textStorage, at: currentLineRange.location)
            let indent = ListFormatHandler.getListIndent(in: textStorage, at: currentLineRange.location)

            // 如果不是有序列表或缩进级别不同，停止更新
            if currentListType != .ordered || indent != currentIndent {
                break
            }

            // 更新编号
            updateOrderAttachmentNumber(in: textStorage, lineRange: currentLineRange, newNumber: expectedNumber)
            textStorage.addAttribute(.listNumber, value: expectedNumber, range: currentLineRange)

            expectedNumber += 1

            // 移动到下一行
            currentPosition = currentLineRange.location + currentLineRange.length
        }

        textStorage.endEditing()
    }

    /// 验证有序列表编号是否连续
    ///
    /// 检查包含指定位置的有序列表的编号是否从 1 开始连续递增
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 列表中的任意位置
    /// - Returns: 编号是否连续
    static func isOrderedListNumberingConsecutive(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard position >= 0, position < textStorage.length else {
            return true
        }

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)

        // 只检查有序列表
        guard listType == .ordered else {
            return true
        }

        let currentIndent = ListFormatHandler.getListIndent(in: textStorage, at: lineRange.location)

        // 向上查找列表的开头
        var listStartPosition = lineRange.location
        var searchPosition = lineRange.location

        while searchPosition > 0 {
            let prevLineEnd = searchPosition - 1
            let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))

            let prevListType = ListFormatHandler.detectListType(in: textStorage, at: prevLineRange.location)
            let prevIndent = ListFormatHandler.getListIndent(in: textStorage, at: prevLineRange.location)

            if prevListType == .ordered, prevIndent == currentIndent {
                listStartPosition = prevLineRange.location
                searchPosition = prevLineRange.location
            } else {
                break
            }
        }

        // 从列表开头开始验证编号
        var currentPosition = listStartPosition
        var expectedNumber = 1

        while currentPosition < textStorage.length {
            let currentLineRange = string.lineRange(for: NSRange(location: currentPosition, length: 0))
            let currentListType = ListFormatHandler.detectListType(in: textStorage, at: currentLineRange.location)
            let indent = ListFormatHandler.getListIndent(in: textStorage, at: currentLineRange.location)

            if currentListType != .ordered || indent != currentIndent {
                break
            }

            let actualNumber = ListFormatHandler.getListNumber(in: textStorage, at: currentLineRange.location)
            if actualNumber != expectedNumber {
                return false
            }

            expectedNumber += 1
            currentPosition = currentLineRange.location + currentLineRange.length
        }

        return true
    }

    /// 获取有序列表的所有编号
    ///
    /// 返回包含指定位置的有序列表的所有编号数组
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 列表中的任意位置
    /// - Returns: 编号数组
    static func getOrderedListNumbers(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> [Int] {
        guard position >= 0, position < textStorage.length else {
            return []
        }

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)

        guard listType == .ordered else {
            return []
        }

        let currentIndent = ListFormatHandler.getListIndent(in: textStorage, at: lineRange.location)

        // 向上查找列表的开头
        var listStartPosition = lineRange.location
        var searchPosition = lineRange.location

        while searchPosition > 0 {
            let prevLineEnd = searchPosition - 1
            let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))

            let prevListType = ListFormatHandler.detectListType(in: textStorage, at: prevLineRange.location)
            let prevIndent = ListFormatHandler.getListIndent(in: textStorage, at: prevLineRange.location)

            if prevListType == .ordered, prevIndent == currentIndent {
                listStartPosition = prevLineRange.location
                searchPosition = prevLineRange.location
            } else {
                break
            }
        }

        // 收集所有编号
        var numbers: [Int] = []
        var currentPosition = listStartPosition

        while currentPosition < textStorage.length {
            let currentLineRange = string.lineRange(for: NSRange(location: currentPosition, length: 0))
            let currentListType = ListFormatHandler.detectListType(in: textStorage, at: currentLineRange.location)
            let indent = ListFormatHandler.getListIndent(in: textStorage, at: currentLineRange.location)

            if currentListType != .ordered || indent != currentIndent {
                break
            }

            let number = ListFormatHandler.getListNumber(in: textStorage, at: currentLineRange.location)
            numbers.append(number)

            currentPosition = currentLineRange.location + currentLineRange.length
        }

        return numbers
    }

    /// 更新 OrderAttachment 的编号
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - lineRange: 行范围
    ///   - newNumber: 新编号
    private static func updateOrderAttachmentNumber(
        in textStorage: NSTextStorage,
        lineRange: NSRange,
        newNumber: Int
    ) {
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if let orderAttachment = value as? OrderAttachment {
                // 创建新的 OrderAttachment 替换旧的
                let newAttachment = OrderAttachment(
                    number: newNumber,
                    inputNumber: orderAttachment.inputNumber,
                    indent: orderAttachment.indent
                )
                textStorage.addAttribute(.attachment, value: newAttachment, range: attrRange)
                stop.pointee = true
            }
        }
    }

    // MARK: - 回车键处理

    /// 处理列表项中的回车键
    ///
    /// 根据列表项状态决定行为：
    /// - 空列表项：取消列表格式，不换行
    /// - 有内容列表项：在光标位置分割文本，创建新列表项
    ///
    /// - Parameter textView: NSTextView 实例
    /// - Returns: 是否已处理（true 表示已处理，调用方不需要执行默认行为）
    static func handleEnterKey(
        textView: NSTextView
    ) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        let selectedRange = textView.selectedRange()
        let position = selectedRange.location

        // 获取列表项信息
        guard let listInfo = getListItemInfo(in: textStorage, at: position) else {
            // 不是列表项，不处理
            return false
        }

        // 检查是否为空列表项
        if listInfo.isEmpty {
            // 空列表项：取消格式，不换行
            return handleEmptyListItemEnter(textView: textView, textStorage: textStorage, listInfo: listInfo)
        }

        // 有内容列表项：分割文本，创建新列表项
        return splitTextAtCursor(textView: textView, textStorage: textStorage, cursorPosition: position, listInfo: listInfo)
    }

    /// 处理空列表项的回车键
    ///
    /// 空列表项回车时：
    /// - 移除列表附件
    /// - 移除列表格式属性
    /// - 不换行
    /// - 当前行变为普通正文
    /// - 光标保持在当前行
    ///
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    ///   - listInfo: 列表项信息
    /// - Returns: 是否已处理
    private static func handleEmptyListItemEnter(
        textView: NSTextView,
        textStorage: NSTextStorage,
        listInfo: ListItemInfo
    ) -> Bool {
        let lineRange = listInfo.lineRange
        let lineStart = lineRange.location
        let isOrderedList = listInfo.listType == .ordered

        textStorage.beginEditing()

        // 1. 移除列表附件（序号、项目符号或勾选框）
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

            textStorage.addAttribute(.font, value: defaultFont, range: newLineRange)
        }

        textStorage.endEditing()

        // 4. 更新光标位置到行首（保持在当前行）
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

    /// 在光标位置分割文本并创建新列表项
    ///
    /// 分割逻辑：
    /// - 光标前的文本保留在当前列表项
    /// - 光标后的文本移动到新列表项
    /// - 新列表项继承列表类型和缩进级别
    /// - 有序列表编号递增
    /// - 勾选框列表新项为未勾选状态
    ///
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    ///   - cursorPosition: 光标位置
    ///   - listInfo: 列表项信息
    /// - Returns: 是否成功分割
    static func splitTextAtCursor(
        textView: NSTextView,
        textStorage: NSTextStorage,
        cursorPosition: Int,
        listInfo: ListItemInfo
    ) -> Bool {
        let lineRange = listInfo.lineRange
        let contentStart = listInfo.contentStartPosition
        let string = textStorage.string as NSString

        // 计算光标在内容区域中的相对位置
        let cursorInContent = cursorPosition - contentStart

        // 获取光标前后的文本
        let contentEndPosition = lineRange.location + lineRange.length
        let hasNewline = contentEndPosition > 0 && string.character(at: contentEndPosition - 1) == 0x0A
        let contentEnd = hasNewline ? contentEndPosition - 1 : contentEndPosition

        let textBeforeRange = NSRange(location: contentStart, length: max(0, cursorPosition - contentStart))
        let textAfterRange = NSRange(location: cursorPosition, length: max(0, contentEnd - cursorPosition))

        let textBefore = textBeforeRange.length > 0 ? string.substring(with: textBeforeRange) : ""
        let textAfter = textAfterRange.length > 0 ? string.substring(with: textAfterRange) : ""

        textStorage.beginEditing()

        // 1. 删除光标后的文本（包括换行符）
        let deleteRange = NSRange(location: cursorPosition, length: contentEndPosition - cursorPosition)
        if deleteRange.length > 0 {
            textStorage.deleteCharacters(in: deleteRange)
        }

        // 2. 插入换行符
        let newlineAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
        ]
        let newlineString = NSAttributedString(string: "\n", attributes: newlineAttrs)
        textStorage.insert(newlineString, at: cursorPosition)

        // 3. 在新行创建列表项
        let newLineStart = cursorPosition + 1
        let newListItem = createNewListItem(
            listType: listInfo.listType,
            indent: listInfo.indent,
            number: (listInfo.number ?? 0) + 1,
            textAfter: textAfter
        )
        textStorage.insert(newListItem, at: newLineStart)

        textStorage.endEditing()

        // 4. 移动光标到新行内容起始位置（附件占用 1 个字符）
        let newCursorPosition = newLineStart + 1
        textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        // 5. 更新 typingAttributes
        var attrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .listType: listInfo.listType,
            .listIndent: listInfo.indent,
        ]
        if listInfo.listType == .ordered {
            attrs[.listNumber] = (listInfo.number ?? 0) + 1
        }
        textView.typingAttributes = attrs

        // 6. 更新后续有序列表编号
        if listInfo.listType == .ordered {
            // 需要更新新行之后的编号
            let nextLineStart = newLineStart + newListItem.length
            if nextLineStart < textStorage.length {
                updateOrderedListNumbers(in: textStorage, from: nextLineStart)
            }
        }

        return true
    }

    /// 创建新的列表项
    ///
    /// 根据列表类型创建相应的列表项：
    /// - 无序列表：BulletAttachment + 文本
    /// - 有序列表：OrderAttachment + 文本
    /// - 勾选框列表：InteractiveCheckboxAttachment（未勾选）+ 文本
    ///
    /// - Parameters:
    ///   - listType: 列表类型
    ///   - indent: 缩进级别
    ///   - number: 编号（仅有序列表）
    ///   - textAfter: 光标后的文本
    /// - Returns: 新列表项的 NSAttributedString
    static func createNewListItem(
        listType: ListType,
        indent: Int,
        number: Int,
        textAfter: String
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let markerWidth: CGFloat = switch listType {
        case .bullet:
            ParagraphStyleFactory.bulletWidth
        case .ordered:
            ParagraphStyleFactory.orderNumberWidth
        case .checkbox:
            ParagraphStyleFactory.bulletWidth
        case .none:
            0
        }

        let paragraphStyle = ParagraphStyleFactory.makeList(indent: indent, bulletWidth: markerWidth)

        // 创建附件
        let attachment: NSTextAttachment
        var attributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .listType: listType,
            .listIndent: indent,
            .paragraphStyle: paragraphStyle,
        ]

        switch listType {
        case .bullet:
            attachment = BulletAttachment(indent: indent)

        case .ordered:
            attachment = OrderAttachment(number: number, inputNumber: 0, indent: indent)
            attributes[.listNumber] = number

        case .checkbox:
            // 新建勾选框默认为未勾选状态
            attachment = InteractiveCheckboxAttachment(checked: false)
            attributes[.checkboxLevel] = 3
            attributes[.checkboxChecked] = false

        case .none:
            // 不应该到达这里
            return NSAttributedString(string: textAfter, attributes: attributes)
        }

        // 添加附件
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttributes(attributes, range: NSRange(location: 0, length: attachmentString.length))
        result.append(attachmentString)

        // 添加文本内容
        if !textAfter.isEmpty {
            let textString = NSAttributedString(string: textAfter, attributes: attributes)
            result.append(textString)
        }

        return result
    }

    /// 获取文本分割结果
    ///
    /// 计算光标位置的文本分割信息，用于回车键处理
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - cursorPosition: 光标位置
    /// - Returns: 文本分割结果，如果不在列表项中则返回 nil
    static func getTextSplitResult(
        in textStorage: NSTextStorage,
        at cursorPosition: Int
    ) -> TextSplitResult? {
        guard let listInfo = getListItemInfo(in: textStorage, at: cursorPosition) else {
            return nil
        }

        let string = textStorage.string as NSString
        let lineRange = listInfo.lineRange
        let contentStart = listInfo.contentStartPosition

        // 计算内容结束位置（不包括换行符）
        let contentEndPosition = lineRange.location + lineRange.length
        let hasNewline = contentEndPosition > 0 && contentEndPosition <= textStorage.length &&
            string.character(at: contentEndPosition - 1) == 0x0A
        let contentEnd = hasNewline ? contentEndPosition - 1 : contentEndPosition

        // 获取光标前后的文本
        let textBeforeRange = NSRange(location: contentStart, length: max(0, cursorPosition - contentStart))
        let textAfterRange = NSRange(location: cursorPosition, length: max(0, contentEnd - cursorPosition))

        let textBefore = textBeforeRange.length > 0 ? string.substring(with: textBeforeRange) : ""
        let textAfter = textAfterRange.length > 0 ? string.substring(with: textAfterRange) : ""

        return TextSplitResult(
            textBefore: textBefore,
            textAfter: textAfter,
            originalLineRange: lineRange,
            cursorPosition: cursorPosition
        )
    }
}
