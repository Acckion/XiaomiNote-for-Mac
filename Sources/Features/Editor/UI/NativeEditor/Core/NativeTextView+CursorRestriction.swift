//
//  NativeTextView+CursorRestriction.swift
//  MiNoteMac
//
//  列表光标位置限制和选择范围限制
//

import AppKit

extension NativeTextView {

    // MARK: - Cursor Position Restriction

    /// 重写 moveLeft 方法，处理左移光标到上一行
    /// 当光标在列表项（包括 checkbox）内容起始位置时，左移应跳到上一行末尾
    override func moveLeft(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveLeft(sender)
            return
        }

        let currentRange = selectedRange()
        let currentPosition = currentRange.location

        // 检查当前位置是否在列表项内容起始位置（包括 checkbox）
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: currentPosition) {
            if currentPosition == listInfo.contentStartPosition {
                // 光标在内容起始位置，跳到上一行末尾
                if listInfo.lineRange.location > 0 {
                    let prevLineEnd = listInfo.lineRange.location - 1
                    setSelectedRange(NSRange(location: prevLineEnd, length: 0))
                    return
                }
            }
        }

        // 执行默认左移
        super.moveLeft(sender)

        // 检查移动后的位置是否在列表标记区域内（包括 checkbox）
        let newPosition = selectedRange().location
        if ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: newPosition) {
            // 调整到内容起始位置
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: newPosition)
            super.setSelectedRange(NSRange(location: adjustedPosition, length: 0))
        }
    }

    /// 重写 moveToBeginningOfLine 方法，移动到内容起始位置
    /// 对于列表项（包括 checkbox），移动到内容区域起始位置而非行首
    override func moveToBeginningOfLine(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveToBeginningOfLine(sender)
            return
        }

        let currentPosition = selectedRange().location

        // 检查当前行是否是列表项（包括 checkbox）
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: currentPosition) {
            // 移动到内容起始位置
            setSelectedRange(NSRange(location: listInfo.contentStartPosition, length: 0))
            return
        }

        // 非列表行，使用默认行为
        super.moveToBeginningOfLine(sender)
    }

    /// 重写 moveWordLeft 方法，处理 Option+左方向键
    /// 确保不会移动到列表标记区域内（包括 checkbox）
    override func moveWordLeft(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveWordLeft(sender)
            return
        }

        let currentPosition = selectedRange().location

        // 检查当前位置是否在列表项内容起始位置（包括 checkbox）
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: currentPosition) {
            if currentPosition == listInfo.contentStartPosition {
                // 光标在内容起始位置，跳到上一行末尾
                if listInfo.lineRange.location > 0 {
                    let prevLineEnd = listInfo.lineRange.location - 1
                    setSelectedRange(NSRange(location: prevLineEnd, length: 0))
                    return
                }
            }
        }

        // 执行默认单词左移
        super.moveWordLeft(sender)

        // 检查移动后的位置是否在列表标记区域内（包括 checkbox）
        let newPosition = selectedRange().location
        if ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: newPosition) {
            // 调整到内容起始位置
            let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: newPosition)
            super.setSelectedRange(NSRange(location: adjustedPosition, length: 0))
        }
    }

    // MARK: - Selection Restriction

    /// 重写 moveLeftAndModifySelection 方法，处理 Shift+左方向键选择
    /// 当选择起点在列表项内容起始位置时，向左扩展选择应跳到上一行而非选中列表标记
    override func moveLeftAndModifySelection(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveLeftAndModifySelection(sender)
            return
        }

        let currentRange = selectedRange()
        let selectionStart = currentRange.location
        let selectionEnd = currentRange.location + currentRange.length

        // 检查选择的起始位置是否在列表项内容起始位置
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: selectionStart) {
            if selectionStart == listInfo.contentStartPosition {
                // 选择起点在内容起始位置，扩展选择到上一行末尾
                if listInfo.lineRange.location > 0 {
                    let prevLineEnd = listInfo.lineRange.location - 1
                    // 计算新的选择范围：从上一行末尾到当前选择末尾
                    let newLength = selectionEnd - prevLineEnd
                    super.setSelectedRange(NSRange(location: prevLineEnd, length: newLength))
                    return
                }
            }
        }

        // 执行默认选择扩展
        super.moveLeftAndModifySelection(sender)

        // 检查选择后的起始位置是否在列表标记区域内
        let newRange = selectedRange()
        let newStart = newRange.location

        if ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: newStart) {
            // 调整选择起始位置到内容起始位置
            let adjustedStart = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: newStart)
            let adjustedLength = newRange.length - (adjustedStart - newStart)
            if adjustedLength >= 0 {
                super.setSelectedRange(NSRange(location: adjustedStart, length: adjustedLength))
            }
        }
    }

    /// 重写 moveToBeginningOfLineAndModifySelection 方法，处理 Cmd+Shift+左方向键选择
    /// 对于列表项，选择到内容区域起始位置而非行首
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveToBeginningOfLineAndModifySelection(sender)
            return
        }

        let currentRange = selectedRange()
        let selectionEnd = currentRange.location + currentRange.length

        // 检查当前行是否是列表项
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: selectionEnd) {
            // 选择到内容起始位置
            let contentStart = listInfo.contentStartPosition
            let newLength = selectionEnd - contentStart
            if newLength >= 0 {
                super.setSelectedRange(NSRange(location: contentStart, length: newLength))
                return
            }
        }

        // 非列表行，使用默认行为
        super.moveToBeginningOfLineAndModifySelection(sender)
    }

    /// 重写 moveWordLeftAndModifySelection 方法，处理 Option+Shift+左方向键选择
    /// 确保选择不会包含列表标记
    override func moveWordLeftAndModifySelection(_ sender: Any?) {
        guard enableListCursorRestriction,
              let textStorage
        else {
            super.moveWordLeftAndModifySelection(sender)
            return
        }

        let currentRange = selectedRange()
        let selectionStart = currentRange.location
        let selectionEnd = currentRange.location + currentRange.length

        // 检查选择的起始位置是否在列表项内容起始位置
        if let listInfo = ListBehaviorHandler.getListItemInfo(in: textStorage, at: selectionStart) {
            if selectionStart == listInfo.contentStartPosition {
                // 选择起点在内容起始位置，扩展选择到上一行末尾
                if listInfo.lineRange.location > 0 {
                    let prevLineEnd = listInfo.lineRange.location - 1
                    let newLength = selectionEnd - prevLineEnd
                    super.setSelectedRange(NSRange(location: prevLineEnd, length: newLength))
                    return
                }
            }
        }

        // 执行默认单词选择扩展
        super.moveWordLeftAndModifySelection(sender)

        // 检查选择后的起始位置是否在列表标记区域内
        let newRange = selectedRange()
        let newStart = newRange.location

        if ListBehaviorHandler.isInListMarkerArea(in: textStorage, at: newStart) {
            // 调整选择起始位置到内容起始位置
            let adjustedStart = ListBehaviorHandler.adjustCursorPosition(in: textStorage, from: newStart)
            let adjustedLength = newRange.length - (adjustedStart - newStart)
            if adjustedLength >= 0 {
                super.setSelectedRange(NSRange(location: adjustedStart, length: adjustedLength))
            }
        }
    }
}
