//
//  NativeTextView.swift
//  MiNoteMac
//
//  自定义 NSTextView 子类 - 核心类定义和属性声明
//

import AppKit

/// 扩展了光标位置限制功能，确保光标不能移动到列表标记区域内
class NativeTextView: NSTextView {

    /// 复选框点击回调
    var onCheckboxClick: ((InteractiveCheckboxAttachment, Int) -> Void)?

    /// 图片存储管理器（由外部注入）
    var imageStorageManager: ImageStorageManager?

    /// 自定义渲染器（由外部注入）
    var customRenderer: CustomRenderer?

    /// 统一格式管理器（由外部注入）
    var unifiedFormatManager: UnifiedFormatManager?

    /// 附件选择管理器（由外部注入）
    var attachmentSelectionManager: AttachmentSelectionManager?

    /// 附件键盘处理器（由外部注入）
    var attachmentKeyboardHandler: AttachmentKeyboardHandler?

    /// 列表状态管理器
    private var listStateManager = ListStateManager()

    /// 是否启用列表光标限制
    /// 默认启用，可以在需要时临时禁用
    var enableListCursorRestriction = true

    /// 是否正在内部调整选择范围（防止递归）
    private var isAdjustingSelection = false

    // MARK: - Cursor Position Restriction

    /// 重写 setSelectedRange 方法，限制光标位置
    /// 确保光标不能移动到列表标记区域内
    override func setSelectedRange(_ charRange: NSRange) {

        // 先调用父类方法
        super.setSelectedRange(charRange)

        // 通知附件选择管理器（仅在非递归调用时）
        if !isAdjustingSelection {
            attachmentSelectionManager?.handleSelectionChange(charRange)
        }

        // 如果禁用限制、没有 textStorage 或有选择范围，不进行列表光标限制
        guard enableListCursorRestriction,
              let textStorage,
              charRange.length == 0,
              !isAdjustingSelection
        else {
            return
        }

        // 调整光标位置，确保不在列表标记区域内
        let adjustedPosition = ListBehaviorHandler.adjustCursorPosition(
            in: textStorage,
            from: charRange.location
        )

        let adjustedRange = NSRange(location: adjustedPosition, length: 0)
        if adjustedRange.location != charRange.location {
            isAdjustingSelection = true
            super.setSelectedRange(adjustedRange)
            // 通知附件选择管理器调整后的位置
            attachmentSelectionManager?.handleSelectionChange(adjustedRange)
            isAdjustingSelection = false
        }
    }
}

// MARK: - ListStateManager

/// 列表状态管理器 - 跟踪和管理列表的连续性和编号
class ListStateManager {

    /// 有序列表编号缓存
    private var orderedListNumbers: [Int: Int] = [:] // [lineIndex: number]

    /// 重置状态
    func reset() {
        orderedListNumbers.removeAll()
    }

    /// 获取指定行的有序列表编号
    func getOrderedListNumber(for lineIndex: Int, in textStorage: NSTextStorage) -> Int {
        if let cached = orderedListNumbers[lineIndex] {
            return cached
        }

        let number = calculateOrderedListNumber(for: lineIndex, in: textStorage)
        orderedListNumbers[lineIndex] = number
        return number
    }

    /// 计算有序列表编号
    private func calculateOrderedListNumber(for lineIndex: Int, in _: NSTextStorage) -> Int {
        lineIndex + 1
    }

    /// 更新编号（当列表发生变化时）
    func updateNumbers(from lineIndex: Int, in _: NSTextStorage) {
        orderedListNumbers = orderedListNumbers.filter { $0.key < lineIndex }
    }
}
