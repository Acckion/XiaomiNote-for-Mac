//
//  AttachmentKeyboardHandler.swift
//  MiNoteMac
//
//  Created by Kiro AI
//

import AppKit

/// 方向键枚举
enum ArrowDirection {
    case left
    case right
    case up
    case down
}

/// 附件键盘处理器
/// 负责处理方向键导航、删除操作、复制/剪切等键盘交互
@MainActor
class AttachmentKeyboardHandler {
    // MARK: - Properties
    
    /// 单例实例
    static let shared = AttachmentKeyboardHandler()
    
    /// 选择管理器
    private let selectionManager = AttachmentSelectionManager.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Keyboard Handling
    
    /// 处理键盘事件
    /// - Parameters:
    ///   - event: 键盘事件
    ///   - textView: 文本视图
    /// - Returns: 是否处理了事件
    func handleKeyDown(_ event: NSEvent, in textView: NSTextView) -> Bool {
        // 检查是否有选中的附件
        guard selectionManager.hasSelectedAttachment else {
            return false
        }
        
        // 获取按键字符
        guard let characters = event.characters else {
            return false
        }
        
        // 处理特殊键
        let keyCode = event.keyCode
        
        // Delete 或 Backspace
        if keyCode == 51 || keyCode == 117 {
            return handleDelete(in: textView)
        }
        
        // 方向键
        if keyCode == 123 { // 左
            return handleArrowKey(.left, in: textView)
        } else if keyCode == 124 { // 右
            return handleArrowKey(.right, in: textView)
        } else if keyCode == 125 { // 下
            return handleArrowKey(.down, in: textView)
        } else if keyCode == 126 { // 上
            return handleArrowKey(.up, in: textView)
        }
        
        // Cmd+C (复制)
        if event.modifierFlags.contains(.command) && characters == "c" {
            return handleCopy(in: textView)
        }
        
        // Cmd+X (剪切)
        if event.modifierFlags.contains(.command) && characters == "x" {
            return handleCut(in: textView)
        }
        
        // 普通文本输入
        if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
            return handleTextInput(characters, in: textView)
        }
        
        return false
    }
    
    /// 处理删除键(Delete/Backspace)
    /// - Parameter textView: 文本视图
    /// - Returns: 是否处理了事件
    func handleDelete(in textView: NSTextView) -> Bool {
        guard let index = selectionManager.selectedAttachmentIndex,
              let textStorage = textView.textStorage else {
            return false
        }
        
        // 删除附件
        textStorage.deleteCharacters(in: NSRange(location: index, length: 1))
        
        // 更新光标位置
        textView.setSelectedRange(NSRange(location: index, length: 0))
        
        // 清除选择状态
        selectionManager.removeHighlight()
        selectionManager.showCursor()
        
        // 通知文本变化
        textView.didChangeText()
        
        return true
    }
    
    /// 处理方向键
    /// - Parameters:
    ///   - direction: 方向(左/右/上/下)
    ///   - textView: 文本视图
    /// - Returns: 是否处理了事件
    func handleArrowKey(_ direction: ArrowDirection, in textView: NSTextView) -> Bool {
        guard let index = selectionManager.selectedAttachmentIndex else {
            return false
        }
        
        var newLocation = index
        
        switch direction {
        case .left:
            // 移动到附件前方
            newLocation = index
        case .right:
            // 移动到附件后方
            newLocation = index + 1
        case .up, .down:
            // 上下方向键使用默认行为
            return false
        }
        
        // 更新光标位置
        textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        
        // 清除选择状态
        selectionManager.removeHighlight()
        selectionManager.showCursor()
        
        return true
    }
    
    /// 处理复制(Cmd+C)
    /// - Parameter textView: 文本视图
    /// - Returns: 是否处理了事件
    func handleCopy(in textView: NSTextView) -> Bool {
        guard let index = selectionManager.selectedAttachmentIndex,
              let textStorage = textView.textStorage else {
            return false
        }
        
        // 获取附件的 attributed string
        let attachmentRange = NSRange(location: index, length: 1)
        let attributedString = textStorage.attributedSubstring(from: attachmentRange)
        
        // 复制到剪贴板
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([attributedString])
        
        return true
    }
    
    /// 处理剪切(Cmd+X)
    /// - Parameter textView: 文本视图
    /// - Returns: 是否处理了事件
    func handleCut(in textView: NSTextView) -> Bool {
        // 先复制
        guard handleCopy(in: textView) else {
            return false
        }
        
        // 再删除
        return handleDelete(in: textView)
    }
    
    /// 处理文本输入(替换附件)
    /// - Parameters:
    ///   - text: 输入的文本
    ///   - textView: 文本视图
    /// - Returns: 是否处理了事件
    func handleTextInput(_ text: String, in textView: NSTextView) -> Bool {
        guard let index = selectionManager.selectedAttachmentIndex,
              let textStorage = textView.textStorage else {
            return false
        }
        
        // 删除附件
        textStorage.deleteCharacters(in: NSRange(location: index, length: 1))
        
        // 插入文本
        textStorage.insert(NSAttributedString(string: text), at: index)
        
        // 更新光标位置
        textView.setSelectedRange(NSRange(location: index + text.count, length: 0))
        
        // 清除选择状态
        selectionManager.removeHighlight()
        selectionManager.showCursor()
        
        // 通知文本变化
        textView.didChangeText()
        
        return true
    }
}
