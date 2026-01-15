//
//  ListBehaviorHandler.swift
//  MiNoteMac
//
//  列表行为处理器 - 处理列表的光标限制、回车键和删除键行为
//  负责光标位置限制、文本分割、行合并、编号更新和勾选框状态切换
//
//  _Requirements: 1.1-1.5, 2.1-2.8, 3.1-3.4, 4.1-4.4, 5.1-5.2, 6.1-6.4, 7.1-7.5_
//

import Foundation
import AppKit

// MARK: - 列表项信息结构

/// 列表项信息
/// 包含列表项的完整信息，用于光标限制和文本分割操作
/// _Requirements: 1.1, 1.3, 1.4_
public struct ListItemInfo {
    /// 列表类型（无序、有序或勾选框）
    public let listType: ListType
    
    /// 缩进级别
    public let indent: Int
    
    /// 列表编号（仅有序列表）
    public let number: Int?
    
    /// 勾选状态（仅勾选框列表）
    public let isChecked: Bool?
    
    /// 行范围
    public let lineRange: NSRange
    
    /// 列表标记范围（附件字符的范围）
    public let markerRange: NSRange?
    
    /// 内容区域起始位置
    public let contentStartPosition: Int
    
    /// 内容文本
    public let contentText: String
    
    /// 是否为空列表项（只有标记没有内容）
    public var isEmpty: Bool {
        return contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 文本分割结果

/// 文本分割结果
/// 用于回车键处理时的文本分割操作
/// _Requirements: 2.1, 2.2, 2.3_
public struct TextSplitResult {
    /// 光标前的文本
    public let textBefore: String
    
    /// 光标后的文本
    public let textAfter: String
    
    /// 原始行范围
    public let originalLineRange: NSRange
    
    /// 光标位置
    public let cursorPosition: Int
}

// MARK: - 列表行为处理器

/// 列表行为处理器
/// 负责处理列表的光标限制、回车键和删除键行为
/// _Requirements: 1.1-1.5, 2.1-2.8, 3.1-3.4, 4.1-4.4, 5.1-5.2, 6.1-6.4, 7.1-7.5_
@MainActor
public struct ListBehaviorHandler {
    
    // MARK: - 常量
    
    /// 默认字体
    /// 使用 FontSizeManager 统一管理
    public static var defaultFont: NSFont { FontSizeManager.shared.defaultFont }
    
    // MARK: - 光标位置限制
    
    /// 获取列表项内容区域的起始位置
    /// 
    /// 内容区域起始位置是列表标记（附件字符）之后的第一个位置
    /// 对于非列表行，返回行首位置
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 当前位置
    /// - Returns: 内容区域起始位置（列表标记之后的位置）
    /// _Requirements: 1.1, 1.3, 1.4_
    public static func getContentStartPosition(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Int {
        guard position >= 0 && position <= textStorage.length else {
            return position
        }
        
        // 获取当前行范围
        let string = textStorage.string as NSString
        let safePosition = min(position, max(0, textStorage.length - 1))
        let lineRange = string.lineRange(for: NSRange(location: safePosition, length: 0))
        
        // 检查是否是列表行
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)
        guard listType != .none else {
            // 非列表行，返回行首位置
            return lineRange.location
        }
        
        // 查找列表附件的位置
        var attachmentEndPosition = lineRange.location
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if value is BulletAttachment || value is OrderAttachment || value is InteractiveCheckboxAttachment {
                // 内容起始位置是附件之后
                attachmentEndPosition = attrRange.location + attrRange.length
                stop.pointee = true
            }
        }
        
        return attachmentEndPosition
    }
    
    /// 检查位置是否在列表标记区域内
    /// 
    /// 列表标记区域是从行首到列表附件结束的区域
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 要检查的位置
    /// - Returns: 是否在列表标记区域内
    /// _Requirements: 1.1_
    public static func isInListMarkerArea(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard position >= 0 && position <= textStorage.length else {
            return false
        }
        
        // 获取当前行范围
        let string = textStorage.string as NSString
        let safePosition = min(position, max(0, textStorage.length - 1))
        let lineRange = string.lineRange(for: NSRange(location: safePosition, length: 0))
        
        // 检查是否是列表行
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)
        guard listType != .none else {
            return false
        }
        
        // 获取内容起始位置
        let contentStart = getContentStartPosition(in: textStorage, at: position)
        
        // 如果位置在内容起始位置之前，则在标记区域内
        return position < contentStart
    }
    
    /// 调整光标位置，确保不在列表标记区域内
    /// 
    /// 如果光标在列表标记区域内，将其调整到内容区域起始位置
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 原始位置
    /// - Returns: 调整后的位置
    /// _Requirements: 1.1, 1.3_
    public static func adjustCursorPosition(
        in textStorage: NSTextStorage,
        from position: Int
    ) -> Int {
        guard position >= 0 && position <= textStorage.length else {
            return position
        }
        
        // 检查是否在列表标记区域内
        if isInListMarkerArea(in: textStorage, at: position) {
            // 调整到内容起始位置
            return getContentStartPosition(in: textStorage, at: position)
        }
        
        return position
    }
    
    /// 获取列表项完整信息
    /// 
    /// 返回指定位置所在列表项的完整信息，包括类型、缩进、编号、内容等
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 列表项信息，如果不是列表项则返回 nil
    /// _Requirements: 1.1, 1.3, 1.4_
    public static func getListItemInfo(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> ListItemInfo? {
        guard position >= 0 && position <= textStorage.length else {
            return nil
        }
        
        // 获取当前行范围
        let string = textStorage.string as NSString
        let safePosition = min(position, max(0, textStorage.length - 1))
        let lineRange = string.lineRange(for: NSRange(location: safePosition, length: 0))
        
        // 检查是否是列表行
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)
        guard listType != .none else {
            return nil
        }
        
        // 获取缩进级别
        let indent = ListFormatHandler.getListIndent(in: textStorage, at: lineRange.location)
        
        // 获取编号（仅有序列表）
        var number: Int? = nil
        if listType == .ordered {
            number = ListFormatHandler.getListNumber(in: textStorage, at: lineRange.location)
        }
        
        // 获取勾选状态（仅勾选框列表）
        var isChecked: Bool? = nil
        var markerRange: NSRange? = nil
        
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if let checkbox = value as? InteractiveCheckboxAttachment {
                isChecked = checkbox.isChecked
                markerRange = attrRange
                stop.pointee = true
            } else if value is BulletAttachment || value is OrderAttachment {
                markerRange = attrRange
                stop.pointee = true
            }
        }
        
        // 获取内容起始位置
        let contentStart = getContentStartPosition(in: textStorage, at: position)
        
        // 获取内容文本
        let contentLength = lineRange.location + lineRange.length - contentStart
        let contentRange = NSRange(location: contentStart, length: max(0, contentLength))
        var contentText = ""
        if contentRange.length > 0 && contentRange.location + contentRange.length <= textStorage.length {
            contentText = string.substring(with: contentRange)
            // 移除换行符
            contentText = contentText.trimmingCharacters(in: .newlines)
        }
        
        return ListItemInfo(
            listType: listType,
            indent: indent,
            number: number,
            isChecked: isChecked,
            lineRange: lineRange,
            markerRange: markerRange,
            contentStartPosition: contentStart,
            contentText: contentText
        )
    }
    
    /// 检测指定位置是否为空列表项
    /// 
    /// 空列表项定义：只包含列表附件（序号、项目符号或勾选框），没有实际文本内容
    /// 只有空白字符的列表项也被视为空列表项
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 位置
    /// - Returns: 是否为空列表项
    /// _Requirements: 3.1, 3.2, 3.3, 3.4_
    public static func isEmptyListItem(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard let listInfo = getListItemInfo(in: textStorage, at: position) else {
            // 不是列表项
            return false
        }
        
        return listInfo.isEmpty
    }
    
    // MARK: - 勾选框状态切换
    
    /// 切换勾选框状态
    /// 
    /// 切换指定位置的勾选框状态（☐ ↔ ☑）
    /// 
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - position: 勾选框位置
    /// - Returns: 是否成功切换
    /// _Requirements: 7.1, 7.2, 7.3, 7.4_
    public static func toggleCheckboxState(
        textView: NSTextView,
        at position: Int
    ) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }
        
        guard position >= 0 && position < textStorage.length else {
            return false
        }
        
        // 获取当前行范围
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: NSRange(location: position, length: 0))
        
        // 查找勾选框附件
        var checkboxAttachment: InteractiveCheckboxAttachment?
        var attachmentRange: NSRange?
        
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            if let checkbox = value as? InteractiveCheckboxAttachment {
                checkboxAttachment = checkbox
                attachmentRange = attrRange
                stop.pointee = true
            }
        }
        
        guard let checkbox = checkboxAttachment, let range = attachmentRange else {
            return false
        }
        
        // 保存当前光标位置
        let currentSelection = textView.selectedRange()
        
        // 切换状态
        checkbox.isChecked.toggle()
        
        // 强制更新附件
        textStorage.beginEditing()
        textStorage.addAttribute(.attachment, value: checkbox, range: range)
        textStorage.endEditing()
        
        // 恢复光标位置
        textView.setSelectedRange(currentSelection)
        
        print("[ListBehaviorHandler] 勾选框状态切换: \(checkbox.isChecked)")
        return true
    }
    
    /// 检查位置是否在勾选框区域内
    /// 
    /// 勾选框区域是勾选框附件所占的字符位置
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 要检查的位置
    /// - Returns: 是否在勾选框区域内
    /// _Requirements: 1.5, 7.1, 7.2_
    public static func isInCheckboxArea(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard position >= 0 && position < textStorage.length else {
            return false
        }
        
        // 检查该位置是否有勾选框附件
        if let attachment = textStorage.attribute(.attachment, at: position, effectiveRange: nil) {
            return attachment is InteractiveCheckboxAttachment
        }
        
        return false
    }
    
    // MARK: - 有序列表编号更新
    
    /// 更新有序列表编号
    /// 
    /// 从指定位置开始，更新后续所有有序列表项的编号
    /// 确保编号从 1 开始连续递增
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - startPosition: 起始位置
    /// _Requirements: 6.1, 6.2, 6.3, 6.4_
    public static func updateOrderedListNumbers(
        in textStorage: NSTextStorage,
        from startPosition: Int
    ) {
        guard startPosition >= 0 && startPosition < textStorage.length else {
            return
        }
        
        let string = textStorage.string as NSString
        var currentPosition = startPosition
        var expectedNumber = 1
        var currentIndent: Int? = nil
        
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
        
        print("[ListBehaviorHandler] 更新有序列表编号完成")
    }
    
    /// 从列表开头重新编号整个有序列表
    /// 
    /// 找到包含指定位置的有序列表的开头，然后从 1 开始重新编号整个列表
    /// 确保编号始终从 1 开始连续递增
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 列表中的任意位置
    /// _Requirements: 6.4_
    public static func renumberOrderedListFromBeginning(
        in textStorage: NSTextStorage,
        at position: Int
    ) {
        guard position >= 0 && position < textStorage.length else {
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
            
            if prevListType == .ordered && prevIndent == currentIndent {
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
        
        print("[ListBehaviorHandler] 从列表开头重新编号完成，共 \(expectedNumber - 1) 项")
    }
    
    /// 验证有序列表编号是否连续
    /// 
    /// 检查包含指定位置的有序列表的编号是否从 1 开始连续递增
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 列表中的任意位置
    /// - Returns: 编号是否连续
    /// _Requirements: 6.4_
    public static func isOrderedListNumberingConsecutive(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard position >= 0 && position < textStorage.length else {
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
            
            if prevListType == .ordered && prevIndent == currentIndent {
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
    /// _Requirements: 6.4_
    public static func getOrderedListNumbers(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> [Int] {
        guard position >= 0 && position < textStorage.length else {
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
            
            if prevListType == .ordered && prevIndent == currentIndent {
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
    /// _Requirements: 2.1-2.8, 3.1-3.4_
    public static func handleEnterKey(
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
            // _Requirements: 3.1, 3.2, 3.3, 3.4_
            return handleEmptyListItemEnter(textView: textView, textStorage: textStorage, listInfo: listInfo)
        }
        
        // 有内容列表项：分割文本，创建新列表项
        // _Requirements: 2.1-2.8_
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
    /// _Requirements: 3.1, 3.2, 3.3, 3.4_
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
        // _Requirements: 3.2_
        if let markerRange = listInfo.markerRange {
            textStorage.deleteCharacters(in: markerRange)
            print("[ListBehaviorHandler] 移除列表附件, range: \(markerRange)")
        }
        
        // 2. 重新计算行范围（因为删除了附件）
        let deletedLength = listInfo.markerRange?.length ?? 0
        let newLineLength = max(0, lineRange.length - deletedLength)
        let newLineRange = NSRange(location: lineStart, length: newLineLength)
        
        // 3. 移除列表格式属性，恢复为普通正文格式
        // _Requirements: 3.3_
        if newLineRange.length > 0 {
            // 移除所有列表相关属性
            textStorage.removeAttribute(.listType, range: newLineRange)
            textStorage.removeAttribute(.listIndent, range: newLineRange)
            textStorage.removeAttribute(.listNumber, range: newLineRange)
            textStorage.removeAttribute(.checkboxLevel, range: newLineRange)
            textStorage.removeAttribute(.checkboxChecked, range: newLineRange)
            
            // 重置段落样式为默认（无缩进）
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = 0
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)
            
            // 确保使用正文字体
            textStorage.addAttribute(.font, value: defaultFont, range: newLineRange)
        }
        
        textStorage.endEditing()
        
        // 4. 更新光标位置到行首（保持在当前行）
        // _Requirements: 3.4_
        textView.setSelectedRange(NSRange(location: lineStart, length: 0))
        
        // 5. 更新 typingAttributes 为普通正文
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.headIndent = 0
        textView.typingAttributes = [
            .font: defaultFont,
            .paragraphStyle: paragraphStyle
        ]
        
        // 6. 如果是有序列表，更新后续编号
        // _Requirements: 6.2_
        if isOrderedList {
            // 计算下一行的起始位置
            let nextLineStart = lineStart + newLineLength
            if nextLineStart < textStorage.length {
                updateOrderedListNumbers(in: textStorage, from: nextLineStart)
            }
        }
        
        print("[ListBehaviorHandler] 空列表项已转换为普通正文，光标位置: \(lineStart)")
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
    /// _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8_
    public static func splitTextAtCursor(
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
        
        print("[ListBehaviorHandler] 分割文本: 前=\"\(textBefore)\", 后=\"\(textAfter)\"")
        
        textStorage.beginEditing()
        
        // 1. 删除光标后的文本（包括换行符）
        let deleteRange = NSRange(location: cursorPosition, length: contentEndPosition - cursorPosition)
        if deleteRange.length > 0 {
            textStorage.deleteCharacters(in: deleteRange)
        }
        
        // 2. 插入换行符
        let newlineAttrs: [NSAttributedString.Key: Any] = [
            .font: defaultFont
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
            .listIndent: listInfo.indent
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
        
        print("[ListBehaviorHandler] 文本分割完成，新光标位置: \(newCursorPosition)")
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
    /// _Requirements: 2.4, 2.5, 2.6_
    public static func createNewListItem(
        listType: ListType,
        indent: Int,
        number: Int,
        textAfter: String
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        
        // 创建段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        let bulletWidth: CGFloat
        
        switch listType {
        case .bullet:
            bulletWidth = 24
        case .ordered:
            bulletWidth = 28
        case .checkbox:
            bulletWidth = 24
        case .none:
            bulletWidth = 0
        }
        
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + bulletWidth
        
        // 创建附件
        let attachment: NSTextAttachment
        var attributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .listType: listType,
            .listIndent: indent,
            .paragraphStyle: paragraphStyle
        ]
        
        switch listType {
        case .bullet:
            attachment = BulletAttachment(indent: indent)
            
        case .ordered:
            attachment = OrderAttachment(number: number, inputNumber: 0, indent: indent)
            attributes[.listNumber] = number
            
        case .checkbox:
            // 新建勾选框默认为未勾选状态
            // _Requirements: 2.6_
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
    /// _Requirements: 2.1, 2.2, 2.3_
    public static func getTextSplitResult(
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
    
    // MARK: - 删除键处理
    
    /// 处理列表项中的删除键（Backspace）
    /// 
    /// 当光标在列表项内容区域起始位置按下删除键时：
    /// - 如果是空列表项：只删除列表标记，保留空行
    /// - 如果是有内容的列表项：将当前列表项的内容合并到上一行
    /// 
    /// - Parameter textView: NSTextView 实例
    /// - Returns: 是否已处理（true 表示已处理，调用方不需要执行默认行为）
    /// _Requirements: 4.1, 4.2, 4.3, 4.4_
    public static func handleBackspaceKey(
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
        
        // 如果是空列表项，只删除列表标记，保留空行
        if listInfo.isEmpty {
            return removeListMarkerOnly(textView: textView, textStorage: textStorage, listInfo: listInfo)
        }
        
        // 检查是否是文档第一行
        guard listInfo.lineRange.location > 0 else {
            // 文档第一行，不能合并到上一行，只删除列表标记
            return removeListMarkerOnly(textView: textView, textStorage: textStorage, listInfo: listInfo)
        }
        
        // 有内容的列表项：执行合并操作
        // _Requirements: 4.1, 4.2, 4.3, 4.4_
        return mergeWithPreviousLine(textView: textView, textStorage: textStorage, listInfo: listInfo)
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
            print("[ListBehaviorHandler] 删除列表标记, range: \(markerRange)")
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
            
            // 重置段落样式为默认（无缩进）
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.headIndent = 0
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: newLineRange)
            
            // 确保使用正文字体
            textStorage.addAttribute(.font, value: defaultFont, range: newLineRange)
        }
        
        textStorage.endEditing()
        
        // 4. 更新光标位置到行首
        textView.setSelectedRange(NSRange(location: lineStart, length: 0))
        
        // 5. 更新 typingAttributes 为普通正文
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.headIndent = 0
        textView.typingAttributes = [
            .font: defaultFont,
            .paragraphStyle: paragraphStyle
        ]
        
        // 6. 如果是有序列表，更新后续编号
        if isOrderedList {
            // 计算下一行的起始位置
            let nextLineStart = lineStart + newLineLength
            if nextLineStart < textStorage.length {
                updateOrderedListNumbers(in: textStorage, from: nextLineStart)
            }
        }
        
        print("[ListBehaviorHandler] 删除列表标记完成，保留空行，光标位置: \(lineStart)")
        return true
    }
    
    /// 将当前列表项与上一行合并
    /// 
    /// 合并逻辑：
    /// - 获取当前列表项的内容文本
    /// - 删除当前行的列表标记（保留换行符结构）
    /// - 将内容追加到上一行末尾
    /// - 更新光标位置到合并点
    /// - 如果是有序列表，更新后续编号
    /// 
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - textStorage: NSTextStorage 实例
    ///   - listInfo: 当前列表项信息
    /// - Returns: 是否成功合并
    /// _Requirements: 4.1, 4.2, 4.3, 4.4_
    public static func mergeWithPreviousLine(
        textView: NSTextView,
        textStorage: NSTextStorage,
        listInfo: ListItemInfo
    ) -> Bool {
        let string = textStorage.string as NSString
        let lineRange = listInfo.lineRange
        let contentStart = listInfo.contentStartPosition
        
        // 获取上一行的信息
        let prevLineEnd = lineRange.location - 1
        guard prevLineEnd >= 0 else {
            return false
        }
        
        let prevLineRange = string.lineRange(for: NSRange(location: prevLineEnd, length: 0))
        
        // 计算上一行的末尾位置（不包括换行符）
        let prevLineEndPosition: Int
        if prevLineRange.location + prevLineRange.length > 0 {
            let lastCharIndex = prevLineRange.location + prevLineRange.length - 1
            if lastCharIndex < textStorage.length && string.character(at: lastCharIndex) == 0x0A {
                prevLineEndPosition = lastCharIndex
            } else {
                prevLineEndPosition = prevLineRange.location + prevLineRange.length
            }
        } else {
            prevLineEndPosition = prevLineRange.location
        }
        
        // 获取当前列表项的内容文本（不包括列表标记）
        let contentText = listInfo.contentText
        
        // 计算当前行的结束位置
        let currentLineEnd = lineRange.location + lineRange.length
        
        // 检查当前行是否有换行符
        let currentLineHasNewline = currentLineEnd > 0 && 
                                    currentLineEnd <= textStorage.length &&
                                    currentLineEnd > lineRange.location &&
                                    string.character(at: currentLineEnd - 1) == 0x0A
        
        // 检查上一行是否是列表项
        let prevListType = ListFormatHandler.detectListType(in: textStorage, at: prevLineRange.location)
        let isOrderedList = listInfo.listType == .ordered
        
        textStorage.beginEditing()
        
        // 关键修复：只删除当前行的内容（从上一行换行符到当前行换行符之前）
        // 不要删除当前行的换行符，这样后续行会保持独立
        
        // 计算要删除的范围：从上一行末尾换行符到当前行内容结束（不包括当前行的换行符）
        let deleteStart = prevLineEndPosition  // 上一行换行符位置
        let deleteEnd: Int
        if currentLineHasNewline {
            // 当前行有换行符，删除到换行符之前
            deleteEnd = currentLineEnd - 1
        } else {
            // 当前行没有换行符（文档最后一行），删除到行尾
            deleteEnd = currentLineEnd
        }
        
        let deleteLength = deleteEnd - deleteStart
        let deleteRange = NSRange(location: deleteStart, length: deleteLength)
        
        print("[ListBehaviorHandler] 删除范围: \(deleteRange), 当前行有换行符: \(currentLineHasNewline)")
        
        if deleteRange.length > 0 && deleteRange.location + deleteRange.length <= textStorage.length {
            textStorage.deleteCharacters(in: deleteRange)
        }
        
        // 在上一行末尾插入当前行的内容
        if !contentText.isEmpty {
            // 获取上一行的属性（用于继承格式）
            var insertAttrs: [NSAttributedString.Key: Any] = [.font: defaultFont]
            
            if prevListType != .none && prevLineEndPosition > 0 {
                // 上一行是列表项，继承其属性
                let attrPosition = min(prevLineEndPosition - 1, textStorage.length - 1)
                if attrPosition >= 0 {
                    insertAttrs = textStorage.attributes(at: attrPosition, effectiveRange: nil)
                }
            } else if prevLineEndPosition > 0 {
                // 上一行是普通文本，继承其属性
                let attrPosition = min(prevLineEndPosition - 1, textStorage.length - 1)
                if attrPosition >= 0 {
                    insertAttrs = textStorage.attributes(at: attrPosition, effectiveRange: nil)
                    // 移除列表相关属性
                    insertAttrs.removeValue(forKey: .listType)
                    insertAttrs.removeValue(forKey: .listIndent)
                    insertAttrs.removeValue(forKey: .listNumber)
                    insertAttrs.removeValue(forKey: .checkboxLevel)
                    insertAttrs.removeValue(forKey: .checkboxChecked)
                }
            }
            
            let insertString = NSAttributedString(string: contentText, attributes: insertAttrs)
            textStorage.insert(insertString, at: prevLineEndPosition)
        }
        
        textStorage.endEditing()
        
        // 更新光标位置到合并点
        let newCursorPosition = prevLineEndPosition
        textView.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
        
        // 如果是有序列表，更新后续编号
        if isOrderedList {
            // 需要更新从当前位置开始的有序列表编号
            // 因为删除了一行，后续的编号需要减 1
            let nextLineStart = prevLineEndPosition + contentText.count
            if nextLineStart < textStorage.length {
                // 需要跳过换行符找到下一行
                let adjustedStart = currentLineHasNewline ? nextLineStart + 1 : nextLineStart
                if adjustedStart < textStorage.length {
                    updateOrderedListNumbers(in: textStorage, from: adjustedStart)
                }
            }
        }
        
        print("[ListBehaviorHandler] 删除键合并完成，新光标位置: \(newCursorPosition)")
        return true
    }
    
    /// 检查光标是否在列表项内容起始位置
    /// 
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 光标位置
    /// - Returns: 是否在内容起始位置
    /// _Requirements: 4.1_
    public static func isCursorAtContentStart(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard let listInfo = getListItemInfo(in: textStorage, at: position) else {
            return false
        }
        
        return position == listInfo.contentStartPosition
    }
}
