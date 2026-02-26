//
//  CoordinatorFormatApplier.swift
//  MiNoteMac
//
//  Coordinator 的格式应用扩展
//  将所有格式应用相关方法从 NativeEditorCoordinator.swift 中分离
//  从 NativeEditorCoordinator.swift 提取，保持为 NativeEditorView.Coordinator 的 extension
//

import AppKit

// MARK: - 格式应用

extension NativeEditorView.Coordinator {

    // MARK: - 格式应用入口

    /// 应用格式（带应用方式标识）
    /// - Parameters:
    ///   - method: 应用方式
    ///   - format: 格式类型
    func applyFormatWithMethod(_ method: FormatApplicationMethod, format: TextFormat) {
        // 临时存储应用方式，供 applyFormat 使用
        currentApplicationMethod = method
        applyFormat(format)
        currentApplicationMethod = nil
    }

    /// 应用格式到选中文本（单级分发）
    func applyFormat(_ format: TextFormat) {
        guard let textView else {
            LogService.shared.error(.editor, "格式操作错误: textView 不可用, 上下文: applyFormat(\(format.displayName))")
            return
        }

        guard let textStorage = textView.textStorage else {
            LogService.shared.error(.editor, "格式操作错误: textStorage 不可用, 上下文: applyFormat(\(format.displayName))")
            return
        }

        let selectedRange = textView.selectedRange()
        let textLength = textStorage.length

        // 内联格式需要选中文本
        if selectedRange.length == 0, format.isInlineFormat {
            LogService.shared.error(.editor, "格式操作错误: 内联格式 '\(format.displayName)' 需要选中文本, 上下文: applyFormat")
            return
        }

        let effectiveRange: NSRange = if selectedRange.length > 0 {
            selectedRange
        } else {
            (textStorage.string as NSString).lineRange(for: selectedRange)
        }

        guard effectiveRange.location + effectiveRange.length <= textLength else {
            LogService.shared.error(.editor, "格式操作错误: 选择范围超出文本长度, 范围: \(effectiveRange), 文本长度: \(textLength)")
            return
        }

        // 单级分发
        switch format.category {
        case .inline:
            textStorage.beginEditing()
            InlineFormatHandler.apply(format, to: effectiveRange, in: textStorage, toggle: true)
            textStorage.endEditing()

        case .blockTitle, .blockList, .blockQuote:
            if let paragraphType = ParagraphType.from(format) {
                formatParagraphManager.toggleParagraphFormat(paragraphType, to: effectiveRange, in: textStorage)
            }

        case .alignment:
            let alignment: NSTextAlignment = (format == .alignCenter) ? .center : .right
            ParagraphManager.toggleAlignment(alignment, to: effectiveRange, in: textStorage)
        }

        // 统一触发格式状态刷新
        Task { @MainActor in
            self.parent.editorContext.cursorFormatManager?.forceRefresh()
        }
        textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
    }

    // MARK: - 特殊元素插入

    /// 插入特殊元素
    func insertSpecialElement(_ element: SpecialElement) {
        guard let textView,
              let textStorage = textView.textStorage else { return }

        let selectedRange = textView.selectedRange()
        let insertionPoint = selectedRange.location

        textStorage.beginEditing()

        switch element {
        case let .checkbox(checked, level):
            insertCheckbox(checked: checked, level: level, at: insertionPoint, in: textStorage)
        case .horizontalRule:
            insertHorizontalRule(at: insertionPoint, in: textStorage)
        case let .bulletPoint(indent):
            insertBulletPoint(indent: indent, at: insertionPoint, in: textStorage)
        case let .numberedItem(number, indent):
            insertNumberedItem(number: number, indent: indent, at: insertionPoint, in: textStorage)
        case let .quote(content):
            insertQuote(content: content, at: insertionPoint, in: textStorage)
        case let .image(fileId, src):
            insertImage(fileId: fileId, src: src, at: insertionPoint, in: textStorage)
        case let .audio(fileId, digest, mimeType):
            insertAudio(fileId: fileId, digest: digest, mimeType: mimeType, at: insertionPoint, in: textStorage)
        }

        textStorage.endEditing()

        // 通知内容变化
        textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        // 图片/音频插入后必须立即同步内容并保存到 DB，
        // 不能等 textDidChange 的 50ms + 2秒防抖链路，
        // 否则上传完成时 DB 中的 XML 还不包含临时 fileId
        if element.isFileAttachment {
            syncContentToContext()
            Task { @MainActor in
                await self.parent.editorContext.autoSaveManager.saveImmediately()
            }
        }
    }

    // MARK: - 缩进操作

    /// 应用缩进操作
    func applyIndentOperation(_ operation: IndentOperation) {
        guard let textView,
              let textStorage = textView.textStorage
        else {
            return
        }

        let selectedRange = textView.selectedRange()

        textStorage.beginEditing()

        guard let formatManager = parent.editorContext.unifiedFormatManager else { return }

        switch operation {
        case .increase:
            formatManager.increaseIndent(to: textStorage, range: selectedRange)
        case .decrease:
            formatManager.decreaseIndent(to: textStorage, range: selectedRange)
        }

        textStorage.endEditing()

        // 更新缩进级别状态
        let newIndentLevel = formatManager.getCurrentIndentLevel(in: textStorage, at: selectedRange.location)
        parent.editorContext.currentIndentLevel = newIndentLevel

        // 通知内容变化
        textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

    }

    /// 插入复选框
    private func insertCheckbox(checked _: Bool, level _: Int, at location: Int, in textStorage: NSTextStorage) {
        let range = NSRange(location: location, length: 0)
        formatParagraphManager.toggleParagraphFormat(.list(.checkbox), to: range, in: textStorage)
    }

    /// 插入分割线
    private func insertHorizontalRule(at location: Int, in textStorage: NSTextStorage) {
        let renderer = parent.editorContext.customRenderer
        let attachment = renderer.createHorizontalRuleAttachment()
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(string: "\n")
        result.append(attachmentString)
        result.append(NSAttributedString(string: "\n"))

        textStorage.insert(result, at: location)
    }

    /// 插入项目符号
    private func insertBulletPoint(indent: Int, at location: Int, in textStorage: NSTextStorage) {
        let renderer = parent.editorContext.customRenderer
        let attachment = renderer.createBulletAttachment(indent: indent)
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(attributedString: attachmentString)

        textStorage.insert(result, at: location)
    }

    /// 插入编号列表项
    private func insertNumberedItem(number: Int, indent: Int, at location: Int, in textStorage: NSTextStorage) {
        let renderer = parent.editorContext.customRenderer
        let attachment = renderer.createOrderAttachment(number: number, indent: indent)
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(attributedString: attachmentString)

        textStorage.insert(result, at: location)
    }

    /// 插入引用块
    private func insertQuote(content: String, at location: Int, in textStorage: NSTextStorage) {
        let renderer = parent.editorContext.customRenderer
        let quoteString = renderer.createQuoteAttributedString(content: content.isEmpty ? " " : content, indent: 1)

        let result = NSMutableAttributedString(string: "\n")
        result.append(quoteString)
        result.append(NSAttributedString(string: "\n"))

        textStorage.insert(result, at: location)
    }

    /// 插入图片
    private func insertImage(fileId: String?, src: String?, at location: Int, in textStorage: NSTextStorage) {
        // 创建图片附件
        let attachment: ImageAttachment

        if let src {
            // 从 URL 创建（延迟加载）
            attachment = parent.editorContext.customRenderer.createImageAttachment(
                src: src,
                fileId: fileId,
                folderId: parent.editorContext.currentFolderId
            )
        } else if let fileId, let folderId = parent.editorContext.currentFolderId {
            // 从本地存储加载
            if let image = parent.editorContext.imageStorageManager?.loadImage(fileId: fileId, folderId: folderId) {
                attachment = parent.editorContext.customRenderer.createImageAttachment(
                    image: image,
                    fileId: fileId,
                    folderId: folderId
                )
            } else {
                // 创建占位符附件
                attachment = ImageAttachment(src: "minote://\(fileId)", fileId: fileId, folderId: folderId)
            }
        } else {
            // 无法创建图片，插入占位符文本
            let placeholder = NSAttributedString(string: "[图片]")
            textStorage.insert(placeholder, at: location)
            return
        }

        let attachmentString = NSAttributedString(attachment: attachment)

        // 构建插入内容：换行 + 图片 + 换行
        let result = NSMutableAttributedString()

        // 如果不在行首，先添加换行
        if location > 0 {
            let string = textStorage.string as NSString
            let prevChar = string.character(at: location - 1)
            if prevChar != 10 { // 10 是换行符的 ASCII 码
                result.append(NSAttributedString(string: "\n"))
            }
        }

        result.append(attachmentString)
        result.append(NSAttributedString(string: "\n"))

        textStorage.insert(result, at: location)

        // 刷新布局以确保图片附件正确显示
        // 不刷新的话，NSTextView 在非焦点状态下不会渲染新插入的附件
        if let layoutManager = textView?.layoutManager {
            let insertedRange = NSRange(location: location, length: result.length)
            layoutManager.invalidateLayout(forCharacterRange: insertedRange, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: insertedRange)
        }

        // 将光标移动到插入内容之后
        let newCursorPosition = location + result.length
        textView?.setSelectedRange(NSRange(location: newCursorPosition, length: 0))
    }

    /// 插入语音录音
    /// - Parameters:
    ///   - fileId: 语音文件 ID
    ///   - digest: 文件摘要（可选）
    ///   - mimeType: MIME 类型（可选）
    ///   - location: 插入位置
    ///   - textStorage: 文本存储
    private func insertAudio(fileId: String, digest: String?, mimeType: String?, at location: Int, in textStorage: NSTextStorage) {

        // 创建音频附件
        let attachment = AudioAttachment(fileId: fileId, digest: digest, mimeType: mimeType)
        let attachmentString = NSAttributedString(attachment: attachment)

        // 构建插入内容：换行 + 音频 + 换行
        let result = NSMutableAttributedString()

        // 如果不在行首，先添加换行
        if location > 0 {
            let string = textStorage.string as NSString
            let prevChar = string.character(at: location - 1)
            if prevChar != 10 { // 10 是换行符的 ASCII 码
                result.append(NSAttributedString(string: "\n"))
            }
        }

        result.append(attachmentString)
        result.append(NSAttributedString(string: "\n"))

        textStorage.insert(result, at: location)

        // 刷新布局以确保附件正确显示
        if let layoutManager = textView?.layoutManager {
            let insertedRange = NSRange(location: location, length: result.length)
            layoutManager.invalidateLayout(forCharacterRange: insertedRange, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: insertedRange)
        }

        // 将光标移动到插入内容之后
        let newCursorPosition = location + result.length
        textView?.setSelectedRange(NSRange(location: newCursorPosition, length: 0))

    }
}
