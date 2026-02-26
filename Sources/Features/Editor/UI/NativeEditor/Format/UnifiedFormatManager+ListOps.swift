//
//  UnifiedFormatManager+ListOps.swift
//  MiNoteMac
//
//  列表操作委托逻辑
//
//

import AppKit

// MARK: - 列表操作

public extension UnifiedFormatManager {

    /// 应用无序列表格式
    func applyBulletList(to textStorage: NSTextStorage, range: NSRange, indent: Int = 1) {
        ParagraphManager.applyBulletList(to: textStorage, range: range, indent: indent)
    }

    /// 应用有序列表格式
    func applyOrderedList(to textStorage: NSTextStorage, range: NSRange, number: Int = 1, indent: Int = 1) {
        ParagraphManager.applyOrderedList(to: textStorage, range: range, number: number, indent: indent)
    }

    /// 移除列表格式
    func removeListFormat(from textStorage: NSTextStorage, range: NSRange) {
        ParagraphManager.removeListFormat(from: textStorage, range: range)
    }

    /// 获取指定位置的列表类型
    func getListType(in textStorage: NSTextStorage, at position: Int) -> ListType {
        ParagraphManager.detectListType(at: position, in: textStorage)
    }

    /// 获取指定位置的列表缩进级别
    func getListIndent(in textStorage: NSTextStorage, at position: Int) -> Int {
        ParagraphManager.getListIndent(at: position, in: textStorage)
    }

    /// 获取指定位置的列表编号
    func getListNumber(in textStorage: NSTextStorage, at position: Int) -> Int {
        ParagraphManager.getListNumber(at: position, in: textStorage)
    }

    /// 增加列表缩进
    func increaseListIndent(to textStorage: NSTextStorage, range: NSRange) {
        let currentIndent = getListIndent(in: textStorage, at: range.location)
        let listType = getListType(in: textStorage, at: range.location)

        guard listType != .none else { return }

        let newIndent = min(currentIndent + 1, 6)

        textStorage.beginEditing()

        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        textStorage.addAttribute(.listIndent, value: newIndent, range: lineRange)

        let bulletWidth = listType == .ordered ? ParagraphStyleFactory.orderNumberWidth : ParagraphStyleFactory.bulletWidth
        let paragraphStyle = ParagraphStyleFactory.makeList(indent: newIndent, bulletWidth: bulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

        textStorage.endEditing()
    }

    /// 减少列表缩进
    func decreaseListIndent(to textStorage: NSTextStorage, range: NSRange) {
        let currentIndent = getListIndent(in: textStorage, at: range.location)
        let listType = getListType(in: textStorage, at: range.location)

        guard listType != .none else { return }

        if currentIndent <= 1 {
            removeListFormat(from: textStorage, range: range)
            return
        }

        let newIndent = currentIndent - 1

        textStorage.beginEditing()

        let lineRange = (textStorage.string as NSString).lineRange(for: range)
        textStorage.addAttribute(.listIndent, value: newIndent, range: lineRange)

        let bulletWidth = listType == .ordered ? ParagraphStyleFactory.orderNumberWidth : ParagraphStyleFactory.bulletWidth
        let paragraphStyle = ParagraphStyleFactory.makeList(indent: newIndent, bulletWidth: bulletWidth)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

        textStorage.endEditing()
    }
}
