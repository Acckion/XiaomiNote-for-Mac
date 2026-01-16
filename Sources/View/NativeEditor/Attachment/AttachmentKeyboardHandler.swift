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
/// 负责根据光标位置处理不同的键盘交互
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
        // 获取按键字符
        guard let characters = event.characters else {
            return false
        }
        
        // 处理特殊键
        let keyCode = event.keyCode
        
        // Backspace - 需要特殊处理,因为可能在没有选中附件的情况下也需要拦截
        if keyCode == 51 {
            // 重新检测光标位置和附件
            guard let textStorage = textView.textStorage else {
                return false
            }
            
            let selectedRange = textView.selectedRange()
            
            // 检测光标是否在附件处
            if let (_, index, position) = selectionManager.detectAttachmentAndPosition(at: selectedRange.location, in: textStorage) {
                print("[AttachmentKeyboardHandler] Backspace: 检测到附件 at index=\(index), position=\(position)")
                
                if position == .beforeAttachment {
                    print("[AttachmentKeyboardHandler] Backspace: 光标在附件左边,执行移动到上一行")
                    return handleBackspaceBeforeAttachment(in: textView, attachmentIndex: index)
                } else if position == .afterAttachment {
                    print("[AttachmentKeyboardHandler] Backspace: 光标在附件右边,执行删除附件")
                    return handleBackspaceAfterAttachment(in: textView, attachmentIndex: index)
                }
            }
            
            // 光标不在附件处,不处理
            return false
        }
        
        // 其他键盘事件需要有选中的附件才处理
        guard selectionManager.hasSelectedAttachment,
              let attachmentIndex = selectionManager.selectedAttachmentIndex else {
            return false
        }
        
        // 获取光标位置
        let cursorPosition = selectionManager.cursorPosition
        
        // Delete
        if keyCode == 117 {
            // Delete 键在附件右边时删除附件
            if cursorPosition == .afterAttachment {
                return handleBackspaceAfterAttachment(in: textView, attachmentIndex: attachmentIndex)
            }
        }
        
        // Enter/Return
        if keyCode == 36 || keyCode == 76 {
            if cursorPosition == .beforeAttachment {
                return handleEnterBeforeAttachment(in: textView, attachmentIndex: attachmentIndex)
            } else if cursorPosition == .afterAttachment {
                return handleEnterAfterAttachment(in: textView, attachmentIndex: attachmentIndex)
            }
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
        
        // Cmd+C (复制) - 仅在附件右边时
        if event.modifierFlags.contains(.command) && characters == "c" && cursorPosition == .afterAttachment {
            return handleCopy(in: textView)
        }
        
        // Cmd+X (剪切) - 仅在附件右边时
        if event.modifierFlags.contains(.command) && characters == "x" && cursorPosition == .afterAttachment {
            return handleCut(in: textView)
        }
        
        // 普通文本输入
        if !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control) {
            if cursorPosition == .beforeAttachment {
                return handleTextInputBeforeAttachment(characters, in: textView, attachmentIndex: attachmentIndex)
            } else if cursorPosition == .afterAttachment {
                return handleTextInputAfterAttachment(characters, in: textView, attachmentIndex: attachmentIndex)
            }
        }
        
        return false
    }
    
    // MARK: - 附件左边的键盘行为
    
    /// 处理附件左边的文本输入
    /// - Parameters:
    ///   - text: 输入的文本
    ///   - textView: 文本视图
    ///   - attachmentIndex: 附件索引
    /// - Returns: 是否处理了事件
    func handleTextInputBeforeAttachment(_ text: String, in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }
        
        print("[AttachmentKeyboardHandler] 附件左边输入文本: \(text)")
        
        // 在附件上方新增一行
        // 找到附件所在行的开头
        let lineStart = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0)).location
        
        // 在行开头插入新行和文本
        let insertString = text + "\n"
        textStorage.insert(NSAttributedString(string: insertString), at: lineStart)
        
        // 将光标移动到新行末尾(在换行符之前)
        let newCursorLocation = lineStart + text.count
        textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
        
        // 通知文本变化
        textView.didChangeText()
        
        return true
    }
    
    /// 处理附件左边的 Backspace
    /// - Parameters:
    ///   - textView: 文本视图
    ///   - attachmentIndex: 附件索引
    /// - Returns: 是否处理了事件
    func handleBackspaceBeforeAttachment(in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }
        
        print("[AttachmentKeyboardHandler] 附件左边按下 Backspace")
        
        // 如果附件是文档第一行,不执行任何操作
        if attachmentIndex == 0 {
            print("[AttachmentKeyboardHandler] 附件在文档开头,不执行操作")
            return true
        }
        
        // 将光标移动到上一行末尾
        // 找到附件所在行的开头
        let currentLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0))
        
        if currentLineRange.location > 0 {
            // 找到上一行的范围
            // currentLineRange.location - 1 是上一行的换行符位置
            let previousLineLocation = currentLineRange.location - 1
            let previousLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: previousLineLocation, length: 0))
            
            // 计算上一行的末尾位置(不包括换行符)
            // previousLineRange.location + previousLineRange.length 是行末尾(包括换行符)
            // 需要减去换行符的长度
            let string = textStorage.string as NSString
            var newLocation = previousLineRange.location + previousLineRange.length
            
            // 往回查找,跳过所有换行符,找到最后一个非换行符字符的后面
            while newLocation > previousLineRange.location {
                let charIndex = newLocation - 1
                let char = string.character(at: charIndex)
                if char == 10 || char == 13 { // \n 或 \r
                    newLocation -= 1
                } else {
                    break
                }
            }
            
            print("[AttachmentKeyboardHandler] 移动光标到位置: \(newLocation)")
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }
        
        return true
    }
    
    /// 处理附件左边的 Enter
    /// - Parameters:
    ///   - textView: 文本视图
    ///   - attachmentIndex: 附件索引
    /// - Returns: 是否处理了事件
    func handleEnterBeforeAttachment(in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }
        
        print("[AttachmentKeyboardHandler] 附件左边按下 Enter")
        
        // 在附件上方插入新行
        // 找到附件所在行的开头
        let lineStart = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0)).location
        
        // 在行开头插入换行符
        textStorage.insert(NSAttributedString(string: "\n"), at: lineStart)
        
        // 光标保持在原位置(新行末尾,也就是换行符之前)
        textView.setSelectedRange(NSRange(location: lineStart, length: 0))
        
        // 通知文本变化
        textView.didChangeText()
        
        return true
    }
    
    // MARK: - 附件右边的键盘行为
    
    /// 处理附件右边的文本输入
    /// - Parameters:
    ///   - text: 输入的文本
    ///   - textView: 文本视图
    ///   - attachmentIndex: 附件索引
    /// - Returns: 是否处理了事件
    func handleTextInputAfterAttachment(_ text: String, in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }
        
        print("[AttachmentKeyboardHandler] 附件右边输入文本: \(text)")
        
        // 在附件下方新增一行
        // 找到附件所在行的范围
        let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0))
        
        // 计算行末尾位置(不包括换行符)
        let string = textStorage.string as NSString
        var lineEnd = lineRange.location + lineRange.length
        
        // 往回查找,跳过所有换行符
        while lineEnd > lineRange.location {
            let charIndex = lineEnd - 1
            let char = string.character(at: charIndex)
            if char == 10 || char == 13 { // \n 或 \r
                lineEnd -= 1
            } else {
                break
            }
        }
        
        // 在行末尾(不包括换行符)插入换行符和文本
        let insertString = "\n" + text
        textStorage.insert(NSAttributedString(string: insertString), at: lineEnd)
        
        // 将光标移动到新行末尾
        let newCursorLocation = lineEnd + insertString.count
        textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
        
        print("[AttachmentKeyboardHandler] 插入位置: \(lineEnd), 新光标位置: \(newCursorLocation)")
        
        // 通知文本变化
        textView.didChangeText()
        
        return true
    }
    
    /// 处理附件右边的 Backspace(删除附件)
    /// - Parameters:
    ///   - textView: 文本视图
    ///   - attachmentIndex: 附件索引
    /// - Returns: 是否处理了事件
    func handleBackspaceAfterAttachment(in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }
        
        print("[AttachmentKeyboardHandler] 附件右边按下 Backspace,删除附件")
        
        // 删除附件
        textStorage.deleteCharacters(in: NSRange(location: attachmentIndex, length: 1))
        
        // 光标保持在该行开头
        textView.setSelectedRange(NSRange(location: attachmentIndex, length: 0))
        
        // 清除选择状态
        selectionManager.removeHighlight()
        selectionManager.showCursor()
        
        // 通知文本变化
        textView.didChangeText()
        
        return true
    }
    
    /// 处理附件右边的 Enter
    /// - Parameters:
    ///   - textView: 文本视图
    ///   - attachmentIndex: 附件索引
    /// - Returns: 是否处理了事件
    func handleEnterAfterAttachment(in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }
        
        print("[AttachmentKeyboardHandler] 附件右边按下 Enter")
        
        // 在附件下方插入新行
        // 找到附件所在行的范围
        let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0))
        
        // 计算行末尾位置(不包括换行符)
        let string = textStorage.string as NSString
        var lineEnd = lineRange.location + lineRange.length
        
        // 往回查找,跳过所有换行符
        while lineEnd > lineRange.location {
            let charIndex = lineEnd - 1
            let char = string.character(at: charIndex)
            if char == 10 || char == 13 { // \n 或 \r
                lineEnd -= 1
            } else {
                break
            }
        }
        
        // 在行末尾(不包括换行符)插入换行符
        textStorage.insert(NSAttributedString(string: "\n"), at: lineEnd)
        
        // 将光标移动到新行开头
        textView.setSelectedRange(NSRange(location: lineEnd + 1, length: 0))
        
        print("[AttachmentKeyboardHandler] 插入位置: \(lineEnd), 新光标位置: \(lineEnd + 1)")
        
        // 通知文本变化
        textView.didChangeText()
        
        return true
    }
    
    // MARK: - 通用键盘行为
    
    /// 处理方向键
    /// - Parameters:
    ///   - direction: 方向(左/右/上/下)
    ///   - textView: 文本视图
    /// - Returns: 是否处理了事件
    func handleArrowKey(_ direction: ArrowDirection, in textView: NSTextView) -> Bool {
        guard let index = selectionManager.selectedAttachmentIndex else {
            return false
        }
        
        let cursorPosition = selectionManager.cursorPosition
        var newLocation = index
        
        switch direction {
        case .left:
            // 从右边移动到左边
            if cursorPosition == .afterAttachment {
                newLocation = index
            } else {
                // 已经在左边,使用默认行为
                return false
            }
        case .right:
            // 从左边移动到右边
            if cursorPosition == .beforeAttachment {
                newLocation = index + 1
            } else {
                // 已经在右边,使用默认行为
                return false
            }
        case .up, .down:
            // 上下方向键使用默认行为
            return false
        }
        
        // 更新光标位置
        textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        
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
        
        print("[AttachmentKeyboardHandler] 复制附件")
        
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
        print("[AttachmentKeyboardHandler] 剪切附件")
        
        // 先复制
        guard handleCopy(in: textView) else {
            return false
        }
        
        // 再删除
        guard let index = selectionManager.selectedAttachmentIndex else {
            return false
        }
        
        return handleBackspaceAfterAttachment(in: textView, attachmentIndex: index)
    }
}
