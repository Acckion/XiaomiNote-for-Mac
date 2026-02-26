//
//  NativeTextView+KeyboardHandling.swift
//  MiNoteMac
//
//  键盘事件处理和列表快捷键逻辑
//

import AppKit

extension NativeTextView {

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        // 先尝试让附件键盘处理器处理
        if let handler = attachmentKeyboardHandler, handler.handleKeyDown(event, in: self) {
            return
        }

        // 向上方向键：光标在第一行开头时，焦点转移到标题 TextField
        if event.keyCode == 126 { // Up arrow
            let cursorLocation = selectedRange().location
            if cursorLocation == 0 {
                if let scrollView = enclosingScrollView,
                   let stackView = scrollView.documentView as? FlippedStackView,
                   let titleField = stackView.arrangedSubviews.first as? TitleTextField
                {
                    window?.makeFirstResponder(titleField)
                    // 将光标移到标题末尾
                    titleField.currentEditor()?.selectedRange = NSRange(location: titleField.stringValue.count, length: 0)
                    return
                }
            }
        }

        // 处理快捷键
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "b":
                // Cmd+B: 加粗
                NotificationCenter.default.post(name: .nativeEditorFormatCommand, object: TextFormat.bold)
                return
            case "i":
                // Cmd+I: 斜体
                NotificationCenter.default.post(name: .nativeEditorFormatCommand, object: TextFormat.italic)
                return
            case "u":
                // Cmd+U: 下划线
                NotificationCenter.default.post(name: .nativeEditorFormatCommand, object: TextFormat.underline)
                return
            default:
                break
            }

            // Cmd+Shift+- : 插入分割线
            if event.modifierFlags.contains(.shift), event.charactersIgnoringModifiers == "-" {
                insertHorizontalRuleAtCursor()
                return
            }

            // Cmd+Shift+U : 切换当前行勾选框状态
            if event.modifierFlags.contains(.shift), event.charactersIgnoringModifiers?.lowercased() == "u" {
                if toggleCurrentLineCheckboxState() {
                    return
                }
            }
        }

        // 处理回车键 - 使用 UnifiedFormatManager 统一处理换行逻辑
        if event.keyCode == 36 { // Return key
            // 关键修复：检查输入法组合状态
            // 如果用户正在使用输入法（如中文输入法输入英文），按回车应该只是确认输入，不换行
            // hasMarkedText() 返回 true 表示输入法正在组合中（如拼音未选择候选词）
            if hasMarkedText() {
                // 调用父类方法，让系统处理输入法的确认操作
                super.keyDown(with: event)
                return
            }

            // 首先尝试使用 UnifiedFormatManager 处理换行
            // 如果 UnifiedFormatManager 已注册且处理了换行，则不执行默认行为
            if let formatManager = unifiedFormatManager, formatManager.isRegistered {
                if formatManager.handleNewLine() {
                    // 通知内容变化
                    delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
                    return
                }
            }

            // 回退到旧的处理逻辑（兼容性）
            // 注意：高亮清除逻辑已整合到 UnifiedFormatManager

            if handleReturnKeyForList() {
                return
            }
        }

        // 处理 Tab 键 - 列表缩进
        if event.keyCode == 48 { // Tab key
            if handleTabKeyForList(increase: !event.modifierFlags.contains(.shift)) {
                return
            }
        }

        // 处理删除键 - 删除分割线
        if event.keyCode == 51 { // Delete key (Backspace)
            // 尝试删除分割线
            if deleteSelectedHorizontalRule() {
                return
            }

            // 然后尝试处理列表项合并
            if handleBackspaceKeyForList() {
                return
            }
        }

        super.keyDown(with: event)
    }

    // MARK: - List Handling

    /// 处理回车键创建新列表项
    /// 使用 ListBehaviorHandler 统一处理列表回车行为
    /// - Returns: 是否处理了回车键
    private func handleReturnKeyForList() -> Bool {
        guard let textStorage else { return false }

        let selectedRange = selectedRange()
        let position = selectedRange.location

        // 首先检查是否在引用块中
        if unifiedFormatManager?.isQuoteBlock(in: textStorage, at: position) == true {
            return handleReturnKeyForQuote()
        }

        // 使用 ListBehaviorHandler 处理列表回车
        if ListBehaviorHandler.handleEnterKey(textView: self) {
            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 检查当前行是否是列表项（回退逻辑）
        let listType = unifiedFormatManager?.getListType(in: textStorage, at: position) ?? .none
        guard listType != .none else { return false }

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: selectedRange)
        let lineText = string.substring(with: lineRange).trimmingCharacters(in: .newlines)

        // 检查当前行是否为空（只有列表符号）
        let isEmptyListItem = isListItemEmpty(lineText: lineText, listType: listType)

        if isEmptyListItem {
            // 空列表项，移除列表格式
            textStorage.beginEditing()
            unifiedFormatManager?.removeListFormat(from: textStorage, range: lineRange)
            textStorage.endEditing()

            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 非空列表项，创建新的列表项
        let indent = unifiedFormatManager?.getListIndent(in: textStorage, at: position) ?? 1

        textStorage.beginEditing()

        // 插入换行符
        let insertionPoint = selectedRange.location
        textStorage.replaceCharacters(in: selectedRange, with: "\n")

        // 在新行应用列表格式
        let newLineStart = insertionPoint + 1
        let newLineRange = NSRange(location: newLineStart, length: 0)

        switch listType {
        case .bullet:
            unifiedFormatManager?.applyBulletList(to: textStorage, range: newLineRange, indent: indent)
            // 插入项目符号
            let bulletString = createBulletString(indent: indent)
            textStorage.insert(bulletString, at: newLineStart)

        case .ordered:
            let newNumber = (unifiedFormatManager?.getListNumber(in: textStorage, at: position) ?? 0) + 1
            unifiedFormatManager?.applyOrderedList(to: textStorage, range: newLineRange, number: newNumber, indent: indent)
            // 插入编号
            let orderString = createOrderString(number: newNumber, indent: indent)
            textStorage.insert(orderString, at: newLineStart)

        case .checkbox:
            // 复选框列表处理
            let checkboxString = createCheckboxString(indent: indent)
            textStorage.insert(checkboxString, at: newLineStart)

        case .none:
            break
        }

        textStorage.endEditing()

        // 移动光标到新行
        let newCursorPosition = newLineStart + getListPrefixLength(listType: listType)
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        // 通知内容变化
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

        return true
    }

    /// 处理 Tab 键调整列表缩进
    /// - Parameter increase: 是否增加缩进
    /// - Returns: 是否处理了 Tab 键
    private func handleTabKeyForList(increase: Bool) -> Bool {
        guard let textStorage else { return false }

        let selectedRange = selectedRange()
        let position = selectedRange.location

        // 检查当前行是否是列表项
        let listType = unifiedFormatManager?.getListType(in: textStorage, at: position) ?? .none
        guard listType != .none else { return false }

        if increase {
            unifiedFormatManager?.increaseListIndent(to: textStorage, range: selectedRange)
        } else {
            unifiedFormatManager?.decreaseListIndent(to: textStorage, range: selectedRange)
        }

        // 通知内容变化
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

        return true
    }

    /// 处理引用块中的回车键
    /// - Returns: 是否处理了回车键
    private func handleReturnKeyForQuote() -> Bool {
        guard let textStorage else { return false }

        let selectedRange = selectedRange()
        let position = selectedRange.location

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: selectedRange)
        let lineText = string.substring(with: lineRange).trimmingCharacters(in: .newlines)

        // 检查当前行是否为空（只有空白字符）
        let isEmptyLine = lineText.trimmingCharacters(in: .whitespaces).isEmpty

        if isEmptyLine {
            // 空行，退出引用块
            textStorage.beginEditing()
            unifiedFormatManager?.removeQuoteBlock(from: textStorage, range: lineRange)
            textStorage.endEditing()

            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 非空行，继续引用格式
        let indent = unifiedFormatManager?.getQuoteIndent(in: textStorage, at: position) ?? 1

        textStorage.beginEditing()

        // 插入换行符
        let insertionPoint = selectedRange.location
        textStorage.replaceCharacters(in: selectedRange, with: "\n")

        // 在新行应用引用块格式
        let newLineStart = insertionPoint + 1
        let newLineRange = NSRange(location: newLineStart, length: 0)

        unifiedFormatManager?.applyQuoteBlock(to: textStorage, range: newLineRange, indent: indent)

        textStorage.endEditing()

        // 移动光标到新行
        setSelectedRange(NSRange(location: newLineStart, length: 0))

        // 通知内容变化
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

        return true
    }

    /// 处理删除键（Backspace）合并列表项
    /// 当光标在列表项内容起始位置时，将当前行内容合并到上一行
    /// - Returns: 是否处理了删除键
    private func handleBackspaceKeyForList() -> Bool {
        guard let textStorage else { return false }

        // 使用 ListBehaviorHandler 处理删除键
        if ListBehaviorHandler.handleBackspaceKey(textView: self) {
            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        return false
    }

    /// 切换当前行勾选框状态
    /// 使用快捷键 Cmd+Shift+U 切换当前行的勾选框状态
    /// - Returns: 是否成功切换
    private func toggleCurrentLineCheckboxState() -> Bool {
        guard let textStorage else { return false }

        let position = selectedRange().location

        // 检查当前行是否是勾选框列表
        let listType = ParagraphManager.detectListType(at: position, in: textStorage)
        guard listType == .checkbox else {
            return false
        }

        // 使用 ListBehaviorHandler 切换勾选框状态
        if ListBehaviorHandler.toggleCheckboxState(textView: self, at: position) {
            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        return false
    }

    /// 检查列表项是否为空
    private func isListItemEmpty(lineText: String, listType: ListType) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespaces)

        switch listType {
        case .bullet:
            // 检查是否只有项目符号
            return trimmed == "\u{2022}" || trimmed.isEmpty
        case .ordered:
            // 检查是否只有编号
            let pattern = "^\\d+\\.$"
            return trimmed.range(of: pattern, options: .regularExpression) != nil || trimmed.isEmpty
        case .checkbox:
            // 检查是否只有复选框（包括附件字符）
            // 附件字符是 Unicode 对象替换字符 \u{FFFC}
            let withoutAttachment = trimmed.replacingOccurrences(of: "\u{FFFC}", with: "")
            return withoutAttachment.isEmpty || trimmed == "\u{2610}" || trimmed == "\u{2611}"
        case .none:
            return trimmed.isEmpty
        }
    }

    /// 创建项目符号字符串
    private func createBulletString(indent: Int) -> NSAttributedString {
        let bullet = "\u{2022} "
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: FontSizeConstants.body),
            .listType: ListType.bullet,
            .listIndent: indent,
        ]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + 24
        attributes[.paragraphStyle] = paragraphStyle

        return NSAttributedString(string: bullet, attributes: attributes)
    }

    /// 创建有序列表编号字符串
    private func createOrderString(number: Int, indent: Int) -> NSAttributedString {
        let orderText = "\(number). "
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: FontSizeConstants.body),
            .listType: ListType.ordered,
            .listIndent: indent,
            .listNumber: number,
        ]

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = CGFloat(indent - 1) * 20
        paragraphStyle.headIndent = CGFloat(indent - 1) * 20 + 28
        attributes[.paragraphStyle] = paragraphStyle

        return NSAttributedString(string: orderText, attributes: attributes)
    }

    /// 创建复选框字符串
    private func createCheckboxString(indent: Int) -> NSAttributedString {
        // 使用 InteractiveCheckboxAttachment 创建可交互的复选框
        let renderer = customRenderer ?? CustomRenderer()
        let attachment = renderer.createCheckboxAttachment(checked: false, level: 3, indent: indent)
        let attachmentString = NSMutableAttributedString(attachment: attachment)

        // 注意：不再添加空格，附件本身已有足够的间距
        // 设置列表类型属性
        let fullRange = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttributes([
            .font: NSFont.systemFont(ofSize: FontSizeConstants.body),
            .listType: ListType.checkbox,
            .listIndent: indent,
        ], range: fullRange)

        return attachmentString
    }

    /// 获取列表前缀长度
    private func getListPrefixLength(listType: ListType) -> Int {
        switch listType {
        case .bullet:
            2 // "* "
        case .ordered:
            3 // "1. " (假设单位数编号)
        case .checkbox:
            2 // 附件字符 + 空格
        case .none:
            0
        }
    }
}
