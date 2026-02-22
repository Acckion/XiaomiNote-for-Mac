//
//  NativeTextView.swift
//  MiNoteMac
//
//  自定义 NSTextView 子类 - 支持列表光标限制、键盘事件处理、粘贴逻辑
//

import AppKit

/// 扩展了光标位置限制功能，确保光标不能移动到列表标记区域内
class NativeTextView: NSTextView {

    /// 复选框点击回调
    var onCheckboxClick: ((InteractiveCheckboxAttachment, Int) -> Void)?

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
            AttachmentSelectionManager.shared.handleSelectionChange(charRange)
        } else {}

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
            AttachmentSelectionManager.shared.handleSelectionChange(adjustedRange)
            isAdjustingSelection = false
        }
    }

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

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // 检查是否点击了附件
        if let layoutManager,
           let textContainer,
           let textStorage
        {
            let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            if charIndex < textStorage.length {
                // 检查是否点击了复选框附件
                if let attachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? InteractiveCheckboxAttachment {
                    // 获取附件的边界
                    let glyphRange = NSRange(location: glyphIndex, length: 1)
                    let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                    // 检查点击是否在附件区域内
                    let adjustedRect = boundingRect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
                    if adjustedRect.contains(point) {
                        // 切换复选框状态
                        let newCheckedState = !attachment.isChecked
                        attachment.isChecked = newCheckedState

                        // 关键修复：强制标记 textStorage 为已修改
                        // 通过重新设置附件属性来触发 textStorage 的变化通知
                        textStorage.beginEditing()
                        textStorage.addAttribute(.attachment, value: attachment, range: NSRange(location: charIndex, length: 1))
                        textStorage.endEditing()

                        // 刷新显示
                        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: charIndex, length: 1))

                        // 触发回调
                        onCheckboxClick?(attachment, charIndex)

                        // 通知代理 - 内容已变化
                        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

                        return
                    }
                }

                // 检查是否点击了音频附件
                if let audioAttachment = textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? AudioAttachment {
                    // 获取附件的边界
                    let glyphRange = NSRange(location: glyphIndex, length: 1)
                    let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                    // 检查点击是否在附件区域内
                    let adjustedRect = boundingRect.offsetBy(dx: textContainerInset.width, dy: textContainerInset.height)
                    if adjustedRect.contains(point) {
                        // 获取文件 ID
                        guard let fileId = audioAttachment.fileId, !fileId.isEmpty else {
                            return
                        }

                        // 发送通知，让音频面板处理播放
                        NotificationCenter.default.postAudioAttachmentClicked(fileId: fileId)

                        return
                    }
                }
            }
        }

        super.mouseDown(with: event)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        // 先尝试让附件键盘处理器处理
        if AttachmentKeyboardHandler.shared.handleKeyDown(event, in: self) {
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
            if UnifiedFormatManager.shared.isRegistered {
                if UnifiedFormatManager.shared.handleNewLine() {
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
        if FormatManager.shared.isQuoteBlock(in: textStorage, at: position) {
            return handleReturnKeyForQuote()
        }

        // 使用 ListBehaviorHandler 处理列表回车
        if ListBehaviorHandler.handleEnterKey(textView: self) {
            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 检查当前行是否是列表项（回退逻辑）
        let listType = FormatManager.shared.getListType(in: textStorage, at: position)
        guard listType != .none else { return false }

        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: selectedRange)
        let lineText = string.substring(with: lineRange).trimmingCharacters(in: .newlines)

        // 检查当前行是否为空（只有列表符号）
        let isEmptyListItem = isListItemEmpty(lineText: lineText, listType: listType)

        if isEmptyListItem {
            // 空列表项，移除列表格式
            textStorage.beginEditing()
            FormatManager.shared.removeListFormat(from: textStorage, range: lineRange)
            textStorage.endEditing()

            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 非空列表项，创建新的列表项
        let indent = FormatManager.shared.getListIndent(in: textStorage, at: position)

        textStorage.beginEditing()

        // 插入换行符
        let insertionPoint = selectedRange.location
        textStorage.replaceCharacters(in: selectedRange, with: "\n")

        // 在新行应用列表格式
        let newLineStart = insertionPoint + 1
        let newLineRange = NSRange(location: newLineStart, length: 0)

        switch listType {
        case .bullet:
            FormatManager.shared.applyBulletList(to: textStorage, range: newLineRange, indent: indent)
            // 插入项目符号
            let bulletString = createBulletString(indent: indent)
            textStorage.insert(bulletString, at: newLineStart)

        case .ordered:
            let newNumber = FormatManager.shared.getListNumber(in: textStorage, at: position) + 1
            FormatManager.shared.applyOrderedList(to: textStorage, range: newLineRange, number: newNumber, indent: indent)
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
        let listType = FormatManager.shared.getListType(in: textStorage, at: position)
        guard listType != .none else { return false }

        if increase {
            FormatManager.shared.increaseListIndent(to: textStorage, range: selectedRange)
        } else {
            FormatManager.shared.decreaseListIndent(to: textStorage, range: selectedRange)
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
            FormatManager.shared.removeQuoteBlock(from: textStorage, range: lineRange)
            textStorage.endEditing()

            // 通知内容变化
            delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
            return true
        }

        // 非空行，继续引用格式
        let indent = FormatManager.shared.getQuoteIndent(in: textStorage, at: position)

        textStorage.beginEditing()

        // 插入换行符
        let insertionPoint = selectedRange.location
        textStorage.replaceCharacters(in: selectedRange, with: "\n")

        // 在新行应用引用块格式
        let newLineStart = insertionPoint + 1
        let newLineRange = NSRange(location: newLineStart, length: 0)

        FormatManager.shared.applyQuoteBlock(to: textStorage, range: newLineRange, indent: indent)

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
        let listType = ListFormatHandler.detectListType(in: textStorage, at: position)
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
            return trimmed == "•" || trimmed.isEmpty
        case .ordered:
            // 检查是否只有编号
            let pattern = "^\\d+\\.$"
            return trimmed.range(of: pattern, options: .regularExpression) != nil || trimmed.isEmpty
        case .checkbox:
            // 检查是否只有复选框（包括附件字符）
            // 附件字符是 Unicode 对象替换字符 \u{FFFC}
            let withoutAttachment = trimmed.replacingOccurrences(of: "\u{FFFC}", with: "")
            return withoutAttachment.isEmpty || trimmed == "☐" || trimmed == "☑"
        case .none:
            return trimmed.isEmpty
        }
    }

    /// 创建项目符号字符串
    private func createBulletString(indent: Int) -> NSAttributedString {
        let bullet = "• "
        var attributes: [NSAttributedString.Key: Any] = [
            .font: FontSizeManager.shared.defaultFont,
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
            .font: FontSizeManager.shared.defaultFont,
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
        let renderer = CustomRenderer.shared
        let attachment = renderer.createCheckboxAttachment(checked: false, level: 3, indent: indent)
        let attachmentString = NSMutableAttributedString(attachment: attachment)

        // 注意：不再添加空格，附件本身已有足够的间距
        // 设置列表类型属性
        let fullRange = NSRange(location: 0, length: attachmentString.length)
        attachmentString.addAttributes([
            .font: FontSizeManager.shared.defaultFont,
            .listType: ListType.checkbox,
            .listIndent: indent,
        ], range: fullRange)

        return attachmentString
    }

    /// 获取列表前缀长度
    private func getListPrefixLength(listType: ListType) -> Int {
        switch listType {
        case .bullet:
            2 // "• "
        case .ordered:
            3 // "1. " (假设单位数编号)
        case .checkbox:
            2 // 附件字符 + 空格
        case .none:
            0
        }
    }

    // MARK: - Paste Support

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // 检查是否有图片
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            // 处理图片粘贴
            insertImage(image)
            return
        }

        // 默认粘贴行为
        super.paste(sender)
    }

    /// 插入图片
    private func insertImage(_ image: NSImage) {
        guard let textStorage else { return }

        // 获取当前文件夹 ID（从编辑器上下文获取）
        // 如果没有文件夹 ID，使用默认值
        let folderId = "default"

        // 保存图片到本地存储
        guard let saveResult = ImageStorageManager.shared.saveImage(image, folderId: folderId) else {
            return
        }

        let fileId = saveResult.fileId

        // 创建图片附件
        let attachment = CustomRenderer.shared.createImageAttachment(
            image: image,
            fileId: fileId,
            folderId: folderId
        )

        let attachmentString = NSAttributedString(attachment: attachment)

        // 构建插入内容
        let result = NSMutableAttributedString()

        let selectedRange = selectedRange()
        let insertionPoint = selectedRange.location

        // 如果不在行首，先添加换行
        if insertionPoint > 0 {
            let string = textStorage.string as NSString
            let prevChar = string.character(at: insertionPoint - 1)
            if prevChar != 10 { // 10 是换行符的 ASCII 码
                result.append(NSAttributedString(string: "\n"))
            }
        }

        result.append(attachmentString)
        result.append(NSAttributedString(string: "\n"))

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: selectedRange, with: result)
        textStorage.endEditing()

        // 移动光标到图片后
        let newCursorPosition = insertionPoint + result.length
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        // 通知代理
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

    }

    // MARK: - Horizontal Rule Support

    /// 在光标位置插入分割线
    func insertHorizontalRuleAtCursor() {
        guard let textStorage else { return }

        let selectedRange = selectedRange()
        let insertionPoint = selectedRange.location

        textStorage.beginEditing()

        // 创建分割线附件
        let renderer = CustomRenderer.shared
        let attachment = renderer.createHorizontalRuleAttachment()
        let attachmentString = NSAttributedString(attachment: attachment)

        // 构建插入内容：换行 + 分割线 + 换行
        let result = NSMutableAttributedString()

        // 如果不在行首，先添加换行
        if insertionPoint > 0 {
            let string = textStorage.string as NSString
            let prevChar = string.character(at: insertionPoint - 1)
            if prevChar != 10 { // 10 是换行符的 ASCII 码
                result.append(NSAttributedString(string: "\n"))
            }
        }

        result.append(attachmentString)
        result.append(NSAttributedString(string: "\n"))

        // 删除选中内容并插入分割线
        textStorage.replaceCharacters(in: selectedRange, with: result)

        textStorage.endEditing()

        // 移动光标到分割线后
        let newCursorPosition = insertionPoint + result.length
        setSelectedRange(NSRange(location: newCursorPosition, length: 0))

        // 通知代理
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }

    /// 删除选中的分割线
    func deleteSelectedHorizontalRule() -> Bool {
        guard let textStorage else { return false }

        let selectedRange = selectedRange()

        // 检查选中位置是否是分割线
        if selectedRange.location < textStorage.length {
            if let attachment = textStorage.attribute(.attachment, at: selectedRange.location, effectiveRange: nil) as? HorizontalRuleAttachment {
                textStorage.beginEditing()

                // 删除分割线（包括可能的换行符）
                var deleteRange = NSRange(location: selectedRange.location, length: 1)

                // 检查前后是否有换行符需要一起删除
                let string = textStorage.string as NSString
                if deleteRange.location > 0 {
                    let prevChar = string.character(at: deleteRange.location - 1)
                    if prevChar == 10 {
                        deleteRange.location -= 1
                        deleteRange.length += 1
                    }
                }
                if deleteRange.location + deleteRange.length < string.length {
                    let nextChar = string.character(at: deleteRange.location + deleteRange.length)
                    if nextChar == 10 {
                        deleteRange.length += 1
                    }
                }

                textStorage.deleteCharacters(in: deleteRange)

                textStorage.endEditing()

                // 通知代理
                delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))

                return true
            }
        }

        return false
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
