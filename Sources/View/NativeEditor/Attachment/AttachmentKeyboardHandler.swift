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
        guard let characters = event.characters else {
            return false
        }

        let keyCode = event.keyCode

        // Backspace - 需要特殊处理,因为可能在没有选中附件的情况下也需要拦截
        if keyCode == 51 {
            guard let textStorage = textView.textStorage else {
                return false
            }

            let selectedRange = textView.selectedRange()

            if let (_, index, position) = selectionManager.detectAttachmentAndPosition(at: selectedRange.location, in: textStorage) {
                LogService.shared.debug(.editor, "Backspace: 检测到附件 at index=\(index), position=\(position)")

                if position == .beforeAttachment {
                    LogService.shared.debug(.editor, "Backspace: 光标在附件左边,执行移动到上一行")
                    return handleBackspaceBeforeAttachment(in: textView, attachmentIndex: index)
                } else if position == .afterAttachment {
                    LogService.shared.debug(.editor, "Backspace: 光标在附件右边,执行删除附件")
                    return handleBackspaceAfterAttachment(in: textView, attachmentIndex: index)
                }
            }

            return false
        }

        guard selectionManager.hasSelectedAttachment,
              let attachmentIndex = selectionManager.selectedAttachmentIndex
        else {
            return false
        }

        let cursorPosition = selectionManager.cursorPosition

        // Delete
        if keyCode == 117 {
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
        if keyCode == 123 {
            return handleArrowKey(.left, in: textView)
        } else if keyCode == 124 {
            return handleArrowKey(.right, in: textView)
        } else if keyCode == 125 {
            return handleArrowKey(.down, in: textView)
        } else if keyCode == 126 {
            return handleArrowKey(.up, in: textView)
        }

        // Cmd+C
        if event.modifierFlags.contains(.command), characters == "c", cursorPosition == .afterAttachment {
            return handleCopy(in: textView)
        }

        // Cmd+X
        if event.modifierFlags.contains(.command), characters == "x", cursorPosition == .afterAttachment {
            return handleCut(in: textView)
        }

        // 普通文本输入
        if !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) {
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
    func handleTextInputBeforeAttachment(_ text: String, in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        // 找到附件所在行的开头，在行开头插入新行和文本
        let lineStart = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0)).location
        let insertString = text + "\n"
        textStorage.insert(NSAttributedString(string: insertString), at: lineStart)

        let newCursorLocation = lineStart + text.count
        textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
        textView.didChangeText()

        return true
    }

    /// 处理附件左边的 Backspace
    func handleBackspaceBeforeAttachment(in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        if attachmentIndex == 0 {
            return true
        }

        let currentLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0))

        if currentLineRange.location > 0 {
            let previousLineLocation = currentLineRange.location - 1
            let previousLineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: previousLineLocation, length: 0))

            let string = textStorage.string as NSString
            var newLocation = previousLineRange.location + previousLineRange.length

            while newLocation > previousLineRange.location {
                let charIndex = newLocation - 1
                let char = string.character(at: charIndex)
                if char == 10 || char == 13 {
                    newLocation -= 1
                } else {
                    break
                }
            }

            textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        }

        return true
    }

    /// 处理附件左边的 Enter
    func handleEnterBeforeAttachment(in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        // 找到附件所在行的开头，在行开头插入换行符
        let lineStart = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0)).location
        textStorage.insert(NSAttributedString(string: "\n"), at: lineStart)

        textView.setSelectedRange(NSRange(location: lineStart, length: 0))
        textView.didChangeText()

        return true
    }

    // MARK: - 附件右边的键盘行为

    /// 处理附件右边的文本输入
    func handleTextInputAfterAttachment(_ text: String, in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0))

        let string = textStorage.string as NSString
        var lineEnd = lineRange.location + lineRange.length

        // 往回查找,跳过所有换行符
        while lineEnd > lineRange.location {
            let charIndex = lineEnd - 1
            let char = string.character(at: charIndex)
            if char == 10 || char == 13 {
                lineEnd -= 1
            } else {
                break
            }
        }

        let insertString = "\n" + text
        textStorage.insert(NSAttributedString(string: insertString), at: lineEnd)

        let newCursorLocation = lineEnd + insertString.count
        textView.setSelectedRange(NSRange(location: newCursorLocation, length: 0))
        textView.didChangeText()

        return true
    }

    /// 处理附件右边的 Backspace（删除附件）
    func handleBackspaceAfterAttachment(in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        textStorage.deleteCharacters(in: NSRange(location: attachmentIndex, length: 1))
        textView.setSelectedRange(NSRange(location: attachmentIndex, length: 0))

        selectionManager.removeHighlight()
        selectionManager.showCursor()
        textView.didChangeText()

        return true
    }

    /// 处理附件右边的 Enter
    func handleEnterAfterAttachment(in textView: NSTextView, attachmentIndex: Int) -> Bool {
        guard let textStorage = textView.textStorage else {
            return false
        }

        let lineRange = (textStorage.string as NSString).lineRange(for: NSRange(location: attachmentIndex, length: 0))

        let string = textStorage.string as NSString
        var lineEnd = lineRange.location + lineRange.length

        // 往回查找,跳过所有换行符
        while lineEnd > lineRange.location {
            let charIndex = lineEnd - 1
            let char = string.character(at: charIndex)
            if char == 10 || char == 13 {
                lineEnd -= 1
            } else {
                break
            }
        }

        textStorage.insert(NSAttributedString(string: "\n"), at: lineEnd)
        textView.setSelectedRange(NSRange(location: lineEnd + 1, length: 0))
        textView.didChangeText()

        return true
    }

    // MARK: - 通用键盘行为

    /// 处理方向键
    func handleArrowKey(_ direction: ArrowDirection, in textView: NSTextView) -> Bool {
        guard let index = selectionManager.selectedAttachmentIndex else {
            return false
        }

        let cursorPosition = selectionManager.cursorPosition
        var newLocation = index

        switch direction {
        case .left:
            if cursorPosition == .afterAttachment {
                newLocation = index
            } else {
                return false
            }
        case .right:
            if cursorPosition == .beforeAttachment {
                newLocation = index + 1
            } else {
                return false
            }
        case .up, .down:
            return false
        }

        textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        return true
    }

    /// 处理复制（Cmd+C）
    func handleCopy(in textView: NSTextView) -> Bool {
        guard let index = selectionManager.selectedAttachmentIndex,
              let textStorage = textView.textStorage
        else {
            return false
        }

        let attachmentRange = NSRange(location: index, length: 1)
        let attributedString = textStorage.attributedSubstring(from: attachmentRange)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([attributedString])

        return true
    }

    /// 处理剪切（Cmd+X）
    func handleCut(in textView: NSTextView) -> Bool {
        guard handleCopy(in: textView) else {
            return false
        }

        guard let index = selectionManager.selectedAttachmentIndex else {
            return false
        }

        return handleBackspaceAfterAttachment(in: textView, attachmentIndex: index)
    }
}
