//
//  ListBehaviorHandler.swift
//  MiNoteMac
//
//  列表行为处理器 - 数据结构定义、光标位置限制和勾选框状态切换
//  回车键处理见 ListBehaviorHandler+EnterKey.swift
//  删除键处理见 ListBehaviorHandler+DeleteKey.swift
//
//

import AppKit
import Foundation

// MARK: - 列表项信息结构

/// 列表项信息
/// 包含列表项的完整信息，用于光标限制和文本分割操作
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
        contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 文本分割结果

/// 文本分割结果
/// 用于回车键处理时的文本分割操作
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
@MainActor
public struct ListBehaviorHandler {

    // MARK: - 常量

    /// 默认字体
    /// 使用 FontSizeManager 统一管理
    public static var defaultFont: NSFont {
        FontSizeManager.shared.defaultFont
    }

    // MARK: - 光标位置限制

    /// 获取列表项内容区域的起始位置
    ///
    /// 内容区域起始位置是列表标记（附件字符）之后的第一个位置
    /// 支持无序列表、有序列表和复选框列表
    /// 对于非列表行，返回行首位置
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 当前位置
    /// - Returns: 内容区域起始位置（列表标记之后的位置）
    public static func getContentStartPosition(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Int {
        guard position >= 0, position <= textStorage.length else {
            return position
        }

        // 获取当前行范围
        let string = textStorage.string as NSString
        let safePosition = min(position, max(0, textStorage.length - 1))
        let lineRange = string.lineRange(for: NSRange(location: safePosition, length: 0))

        // 检查是否是列表行（包括 checkbox）
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)
        guard listType != .none else {
            // 非列表行，返回行首位置
            return lineRange.location
        }

        // 查找列表附件的位置（包括 InteractiveCheckboxAttachment）
        var attachmentEndPosition = lineRange.location
        textStorage.enumerateAttribute(.attachment, in: lineRange, options: []) { value, attrRange, stop in
            // 检查所有类型的列表附件，包括 checkbox
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
    /// 包括无序列表、有序列表和复选框列表的标记
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 要检查的位置
    /// - Returns: 是否在列表标记区域内
    public static func isInListMarkerArea(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard position >= 0, position <= textStorage.length else {
            return false
        }

        // 获取当前行范围
        let string = textStorage.string as NSString
        let safePosition = min(position, max(0, textStorage.length - 1))
        let lineRange = string.lineRange(for: NSRange(location: safePosition, length: 0))

        // 检查是否是列表行（包括 checkbox）
        let listType = ListFormatHandler.detectListType(in: textStorage, at: lineRange.location)
        guard listType != .none else {
            return false
        }

        // 获取内容起始位置
        let contentStart = getContentStartPosition(in: textStorage, at: position)

        // 如果位置在内容起始位置之前，则在标记区域内
        // 这包括了 checkbox、bullet 和 order 附件
        return position < contentStart
    }

    /// 调整光标位置，确保不在列表标记区域内
    ///
    /// 如果光标在列表标记区域内（包括 checkbox），将其调整到内容区域起始位置
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - position: 原始位置
    /// - Returns: 调整后的位置
    public static func adjustCursorPosition(
        in textStorage: NSTextStorage,
        from position: Int
    ) -> Int {
        guard position >= 0, position <= textStorage.length else {
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
    public static func getListItemInfo(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> ListItemInfo? {
        guard position >= 0, position <= textStorage.length else {
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
        var number: Int?
        if listType == .ordered {
            number = ListFormatHandler.getListNumber(in: textStorage, at: lineRange.location)
        }

        // 获取勾选状态（仅勾选框列表）
        var isChecked: Bool?
        var markerRange: NSRange?

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
        if contentRange.length > 0, contentRange.location + contentRange.length <= textStorage.length {
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
    /// 切换指定位置的勾选框状态
    ///
    /// - Parameters:
    ///   - textView: NSTextView 实例
    ///   - position: 勾选框位置
    /// - Returns: 是否成功切换
    public static func toggleCheckboxState(
        textView: NSTextView,
        at position: Int
    ) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        guard position >= 0, position < textStorage.length else {
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

        return true
    }

    // 检查位置是否在勾选框区域内
    //
    // 勾选框区域是勾选框附件所占的字符位置
    //
    // - Parameters:
    //   - textStorage: 文本存储
    //   - position: 要检查的位置
    // - Returns: 是否在勾选框区域内

    public static func isInCheckboxArea(
        in textStorage: NSTextStorage,
        at position: Int
    ) -> Bool {
        guard position >= 0, position < textStorage.length else {
            return false
        }

        // 检查该位置是否有勾选框附件
        if let attachment = textStorage.attribute(.attachment, at: position, effectiveRange: nil) {
            return attachment is InteractiveCheckboxAttachment
        }

        return false
    }
}
