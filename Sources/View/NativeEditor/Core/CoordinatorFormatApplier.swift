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

    /// 应用格式到选中文本
    func applyFormat(_ format: TextFormat) {
        // 开始性能测量
        let performanceOptimizer = FormatApplicationPerformanceOptimizer.shared
        let errorHandler = FormatErrorHandler.shared
        let consistencyChecker = FormatApplicationConsistencyChecker.shared

        // 1. 预检查 - 验证编辑器状态
        guard let textView else {
            let context = FormatErrorContext(
                operation: "applyFormat",
                format: format.displayName,
                selectedRange: nil,
                textLength: nil,
                cursorPosition: nil,
                additionalInfo: nil
            )
            errorHandler.handleError(.textViewUnavailable, context: context)
            return
        }

        guard let textStorage = textView.textStorage else {
            let context = FormatErrorContext(
                operation: "applyFormat",
                format: format.displayName,
                selectedRange: nil,
                textLength: nil,
                cursorPosition: nil,
                additionalInfo: nil
            )
            errorHandler.handleError(.textStorageUnavailable, context: context)
            return
        }

        let selectedRange = textView.selectedRange()
        let textLength = textStorage.length

        // 记录应用前的格式状态
        let beforeState = parent.editorContext.currentFormats

        // 开始性能测量
        let measurementContext = performanceOptimizer.beginMeasurement(
            format: format,
            selectedRange: selectedRange
        )

        // 2. 处理空选择范围的情况
        // 对于内联格式，如果没有选中文本，则不应用格式
        // 对于块级格式，即使没有选中文本也可以应用到当前行
        if selectedRange.length == 0, format.isInlineFormat {
            performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: "内联格式需要选中文本")
            let context = FormatErrorContext(
                operation: "applyFormat",
                format: format.displayName,
                selectedRange: selectedRange,
                textLength: textLength,
                cursorPosition: selectedRange.location,
                additionalInfo: nil
            )
            errorHandler.handleError(.emptySelectionForInlineFormat(format: format.displayName), context: context)
            return
        }

        // 3. 验证范围有效性
        let effectiveRange: NSRange
        if selectedRange.length > 0 {
            effectiveRange = selectedRange
        } else {
            // 块级格式：使用当前行的范围
            let lineRange = (textStorage.string as NSString).lineRange(for: selectedRange)
            effectiveRange = lineRange
        }

        guard effectiveRange.location + effectiveRange.length <= textLength else {
            performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: "选择范围超出文本长度")
            errorHandler.handleRangeError(range: effectiveRange, textLength: textLength)
            return
        }

        // MARK: - Paper-Inspired Integration (Task 19.3)

        // 4. 应用格式
        do {
            // 检查是否为段落级格式
            if format.category == .blockTitle || format.category == .blockList || format.category == .blockQuote {
                // 使用 ParagraphManager 应用段落格式

                // 将 TextFormat 转换为 ParagraphType
                let paragraphType = convertTextFormatToParagraphType(format)
                formatParagraphManager.applyParagraphFormat(paragraphType, to: effectiveRange, in: textStorage)
            } else {
                // 内联格式：使用原有逻辑
                try applyFormatSafely(format, to: effectiveRange, in: textStorage)
            }

            // 5. 更新编辑器上下文状态
            updateContextAfterFormatApplication(format)

            // 6. 通知内容变化
            textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

            // 7. 记录成功日志和性能数据
            performanceOptimizer.endMeasurement(measurementContext, success: true)

            // 8. 记录一致性检查数据
            let afterState = parent.editorContext.currentFormats
            // 优先使用显式设置的方式，否则从 editorContext 获取
            let applicationMethod = currentApplicationMethod ?? parent.editorContext.currentApplicationMethod
            consistencyChecker.recordFormatApplication(
                method: applicationMethod,
                format: format,
                selectedRange: selectedRange,
                textLength: textLength,
                beforeState: beforeState,
                afterState: afterState,
                success: true
            )

            // 9. 重置错误计数（成功后重置）
            errorHandler.resetErrorCount()
        } catch {
            // 9. 错误处理
            performanceOptimizer.endMeasurement(measurementContext, success: false, errorMessage: error.localizedDescription)

            // 记录一致性检查数据（失败情况）
            let afterState = parent.editorContext.currentFormats
            // 优先使用显式设置的方式，否则从 editorContext 获取
            let applicationMethod = currentApplicationMethod ?? parent.editorContext.currentApplicationMethod
            consistencyChecker.recordFormatApplication(
                method: applicationMethod,
                format: format,
                selectedRange: selectedRange,
                textLength: textLength,
                beforeState: beforeState,
                afterState: afterState,
                success: false,
                errorMessage: error.localizedDescription
            )

            // 记录错误并尝试恢复
            let result = errorHandler.handleFormatApplicationError(
                format: format,
                range: effectiveRange,
                textLength: textLength,
                underlyingError: error
            )

            // 根据恢复操作执行相应处理
            handleFormatErrorRecovery(result, format: format)

            // 触发状态重新同步
            parent.editorContext.updateCurrentFormats()
        }
    }

    // MARK: - 安全格式应用

    /// 将 TextFormat 转换为 ParagraphType
    /// - Parameter format: 文本格式
    /// - Returns: 段落类型
    private func convertTextFormatToParagraphType(_ format: TextFormat) -> ParagraphType {
        switch format {
        case .heading1:
            .heading(level: 1)
        case .heading2:
            .heading(level: 2)
        case .heading3:
            .heading(level: 3)
        case .bulletList:
            .list(.bullet)
        case .numberedList:
            .list(.ordered)
        case .checkbox:
            .list(.checkbox)
        case .quote:
            .quote
        default:
            .normal
        }
    }

    /// 处理格式错误恢复
    /// - Parameters:
    ///   - result: 错误处理结果
    ///   - format: 格式类型
    private func handleFormatErrorRecovery(_ result: FormatErrorHandlingResult, format _: TextFormat) {
        switch result.recoveryAction {
        case .retryWithFallback:
            break

        case .forceStateUpdate:
            // 强制更新状态
            parent.editorContext.forceUpdateFormats()

        case .refreshEditor:
            // 刷新编辑器
            NotificationCenter.default.post(name: .nativeEditorNeedsRefresh, object: nil)

        default:
            // 其他情况不做额外处理
            break
        }
    }

    /// 安全地应用格式（带错误处理）
    /// - Parameters:
    ///   - format: 格式类型
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    /// - Throws: 格式应用错误
    private func applyFormatSafely(_ format: TextFormat, to range: NSRange, in textStorage: NSTextStorage) throws {
        // 开始编辑
        textStorage.beginEditing()

        defer {
            // 确保无论如何都结束编辑
            textStorage.endEditing()
        }

        // 特殊处理：列表格式使用 ListFormatHandler
        if format == .bulletList || format == .numberedList {

            if format == .bulletList {
                // 使用 ListFormatHandler 切换无序列表
                ListFormatHandler.toggleBulletList(to: textStorage, range: range)
            } else {
                // 使用 ListFormatHandler 切换有序列表
                ListFormatHandler.toggleOrderedList(to: textStorage, range: range)
            }

            return
        }

        // 使用 UnifiedFormatManager 统一处理其他格式应用
        if UnifiedFormatManager.shared.isRegistered {
            // 根据格式类型调用对应的处理器
            switch format.category {
            case .inline:
                // 内联格式：使用 InlineFormatHandler
                InlineFormatHandler.apply(format, to: range, in: textStorage, toggle: true)

            case .blockTitle, .blockList, .blockQuote:
                // 块级格式：使用 BlockFormatHandler
                BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: true)

            case .alignment:
                // 对齐格式：使用 BlockFormatHandler
                BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: true)
            }

        } else {
            // 回退到旧的处理逻辑（兼容性）
            // 注意：applyFontTrait 和 toggleAttribute 逻辑已整合到 UnifiedFormatManager
            // 直接使用 InlineFormatHandler 和 BlockFormatHandler
            switch format.category {
            case .inline:
                InlineFormatHandler.apply(format, to: range, in: textStorage, toggle: true)

            case .blockTitle, .blockList, .blockQuote:
                // 块级格式：使用 BlockFormatHandler
                BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: true)

            case .alignment:
                // 对齐格式：使用 BlockFormatHandler
                BlockFormatHandler.apply(format, to: range, in: textStorage, toggle: true)
            }

        }
    }

    /// 更新编辑器上下文状态
    /// - Parameter format: 应用的格式
    private func updateContextAfterFormatApplication(_: TextFormat) {
        // 延迟更新状态，避免在视图更新中修改 @Published 属性
        parent.editorContext.updateCurrentFormatsAsync()
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

        let formatManager = FormatManager.shared

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
    ///
    /// 使用 ListFormatHandler.toggleCheckboxList 实现复选框列表的切换
    /// 这确保了：
    /// 1. 如果当前行已经是复选框列表，则移除格式
    /// 2. 如果当前行是其他列表类型，则转换为复选框列表
    /// 3. 如果当前行不是列表，则应用复选框列表格式
    ///
    private func insertCheckbox(checked _: Bool, level _: Int, at location: Int, in textStorage: NSTextStorage) {
        // 使用 ListFormatHandler.toggleCheckboxList 实现复选框列表切换
        // 这会正确处理：
        // 1. 在行首插入 InteractiveCheckboxAttachment
        // 2. 设置列表类型属性
        // 3. 处理标题格式互斥
        // 4. 处理其他列表类型的转换
        let range = NSRange(location: location, length: 0)
        ListFormatHandler.toggleCheckboxList(to: textStorage, range: range)
    }

    /// 插入分割线
    private func insertHorizontalRule(at location: Int, in textStorage: NSTextStorage) {
        let renderer = CustomRenderer.shared
        let attachment = renderer.createHorizontalRuleAttachment()
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(string: "\n")
        result.append(attachmentString)
        result.append(NSAttributedString(string: "\n"))

        textStorage.insert(result, at: location)
    }

    /// 插入项目符号
    private func insertBulletPoint(indent: Int, at location: Int, in textStorage: NSTextStorage) {
        let renderer = CustomRenderer.shared
        let attachment = renderer.createBulletAttachment(indent: indent)
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(attributedString: attachmentString)

        textStorage.insert(result, at: location)
    }

    /// 插入编号列表项
    private func insertNumberedItem(number: Int, indent: Int, at location: Int, in textStorage: NSTextStorage) {
        let renderer = CustomRenderer.shared
        let attachment = renderer.createOrderAttachment(number: number, indent: indent)
        let attachmentString = NSAttributedString(attachment: attachment)

        let result = NSMutableAttributedString(attributedString: attachmentString)

        textStorage.insert(result, at: location)
    }

    /// 插入引用块
    private func insertQuote(content: String, at location: Int, in textStorage: NSTextStorage) {
        let renderer = CustomRenderer.shared
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
            attachment = CustomRenderer.shared.createImageAttachment(
                src: src,
                fileId: fileId,
                folderId: parent.editorContext.currentFolderId
            )
        } else if let fileId, let folderId = parent.editorContext.currentFolderId {
            // 从本地存储加载
            if let image = ImageStorageManager.shared.loadImage(fileId: fileId, folderId: folderId) {
                attachment = CustomRenderer.shared.createImageAttachment(
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
