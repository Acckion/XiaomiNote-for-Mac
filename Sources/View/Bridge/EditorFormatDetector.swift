//
//  EditorFormatDetector.swift
//  MiNoteMac
//
//  NativeEditorContext 的格式检测扩展
//  从 NativeEditorContext.swift 提取，负责格式状态更新、混合格式检测、段落样式查询
//

import AppKit

/// NativeEditorContext 的格式检测扩展
extension NativeEditorContext {
    // MARK: - 格式状态更新

    /// 根据当前光标位置更新格式状态
    func updateCurrentFormats() {

        let errorHandler = FormatErrorHandler.shared

        guard !nsAttributedText.string.isEmpty else {
            clearAllFormats()
            clearMixedFormatStates()
            return
        }

        // 确保位置有效
        let position = min(cursorPosition, nsAttributedText.length - 1)
        guard position >= 0 else {
            clearAllFormats()
            clearMixedFormatStates()
            return
        }

        // 如果有选中范围，检测混合格式状态
        if selectedRange.length > 0 {
            updateMixedFormatStates()
        } else {
            clearMixedFormatStates()
        }

        // 获取当前位置的属性
        var attributePosition = position
        if selectedRange.length == 0, position > 0 {
            // 光标模式：获取光标前一个字符的属性
            attributePosition = position - 1
        }

        let attributes = nsAttributedText.attributes(at: attributePosition, effectiveRange: nil)

        // 检测所有格式类型
        var detectedFormats: Set<TextFormat> = []
        // 1. 检测字体属性（加粗、斜体、标题）
        let fontFormats = detectFontFormats(from: attributes)
        detectedFormats.formUnion(fontFormats)

        // 2. 检测文本装饰（下划线、删除线、高亮）
        let decorationFormats = detectTextDecorations(from: attributes)
        detectedFormats.formUnion(decorationFormats)

        // 3. 检测段落格式（对齐方式）
        let paragraphFormats = detectParagraphFormats(from: attributes)
        detectedFormats.formUnion(paragraphFormats)

        // 4. 检测列表格式（无序、有序、复选框）
        let listFormats = detectListFormats(at: attributePosition)
        detectedFormats.formUnion(listFormats)

        // 5. 检测特殊元素格式（引用块、分割线）
        let specialFormats = detectSpecialElementFormats(at: attributePosition)
        detectedFormats.formUnion(specialFormats)

        if selectedRange.length > 0 {
            let activeFormats = detectActiveInlineFormats(in: nsAttributedText, range: selectedRange)
            detectedFormats.formUnion(activeFormats)
        }

        // 更新状态并验证
        updateFormatsWithValidation(detectedFormats)
    }

    /// 异步更新当前格式状态
    func updateCurrentFormatsAsync() {
        Task { @MainActor in
            updateCurrentFormats()
        }
    }

    // MARK: - 混合格式状态

    /// 更新混合格式状态
    private func updateMixedFormatStates() {
        let inlineFormats: [TextFormat] = [.bold, .italic, .underline, .strikethrough, .highlight]

        var newPartiallyActive: Set<TextFormat> = []
        var newRatios: [TextFormat: Double] = [:]

        let effectiveRange = NSRange(
            location: selectedRange.location,
            length: min(selectedRange.length, nsAttributedText.length - selectedRange.location)
        )

        guard effectiveRange.length > 0 else {
            partiallyActiveFormats.removeAll()
            formatActivationRatios.removeAll()
            return
        }

        for format in inlineFormats {
            var activeCount = 0
            let totalCount = effectiveRange.length

            nsAttributedText.enumerateAttributes(in: effectiveRange, options: []) { attributes, attrRange, _ in
                if self.isInlineFormatActive(format, in: attributes) {
                    activeCount += attrRange.length
                }
            }

            let ratio = Double(activeCount) / Double(totalCount)
            newRatios[format] = ratio

            // 部分激活：既非全部激活也非全部未激活
            if activeCount > 0, activeCount < totalCount {
                newPartiallyActive.insert(format)
            }
        }

        partiallyActiveFormats = newPartiallyActive
        formatActivationRatios = newRatios
    }

    /// 清除混合格式状态
    private func clearMixedFormatStates() {
        partiallyActiveFormats.removeAll()
        formatActivationRatios.removeAll()
    }

    // MARK: - 内联格式检测辅助

    /// 检测选中范围内应显示为激活的内联格式集合
    private func detectActiveInlineFormats(in attributedString: NSAttributedString, range: NSRange) -> Set<TextFormat> {
        let inlineFormats: [TextFormat] = [.bold, .italic, .underline, .strikethrough, .highlight]
        var activeFormats: Set<TextFormat> = []

        let effectiveRange = NSRange(
            location: range.location,
            length: min(range.length, attributedString.length - range.location)
        )

        guard effectiveRange.length > 0 else { return activeFormats }

        for format in inlineFormats {
            var activeCount = 0

            attributedString.enumerateAttributes(in: effectiveRange, options: []) { attributes, attrRange, _ in
                if self.isInlineFormatActive(format, in: attributes) {
                    activeCount += attrRange.length
                }
            }

            // 只要有任意字符激活就显示为激活
            if activeCount > 0 {
                activeFormats.insert(format)
            }
        }

        return activeFormats
    }

    /// 检测属性中是否包含指定内联格式
    private func isInlineFormatActive(_ format: TextFormat, in attributes: [NSAttributedString.Key: Any]) -> Bool {
        switch format {
        case .bold:
            guard let font = attributes[.font] as? NSFont else { return false }
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) { return true }
            let fontName = font.fontName.lowercased()
            if fontName.contains("bold") || fontName.contains("-bold") { return true }
            if let weightTrait = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
               let weight = weightTrait[.weight] as? CGFloat, weight >= 0.4 { return true }
            return false
        case .italic:
            guard let font = attributes[.font] as? NSFont else { return false }
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.italic) { return true }
            let fontName = font.fontName.lowercased()
            return fontName.contains("italic") || fontName.contains("oblique")
        case .underline:
            if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 { return true }
            return false
        case .strikethrough:
            if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 { return true }
            return false
        case .highlight:
            if let backgroundColor = attributes[.backgroundColor] as? NSColor {
                if backgroundColor.alphaComponent > 0.1, backgroundColor != .clear, backgroundColor != .white { return true }
            }
            return false
        default:
            return false
        }
    }

    // MARK: - 字体格式检测

    /// 检测字体格式（加粗、斜体、标题）
    ///
    /// - 23pt = 大标题
    /// - 20pt = 二级标题
    /// - 17pt = 三级标题
    /// - 14pt = 正文
    ///
    /// 使用 FontSizeManager 统一检测逻辑
    private func detectFontFormats(from attributes: [NSAttributedString.Key: Any]) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []

        guard let font = attributes[.font] as? NSFont else {
            return formats
        }

        let fontSize = font.pointSize

        // 检测字体特性
        let traits = font.fontDescriptor.symbolicTraits

        // 使用 FontSizeManager 的统一检测逻辑
        let detectedFormat = FontSizeManager.shared.detectParagraphFormat(fontSize: fontSize)
        switch detectedFormat {
        case .heading1:
            formats.insert(.heading1)
        case .heading2:
            formats.insert(.heading2)
        case .heading3:
            formats.insert(.heading3)
        default:
            break
        }

        // 加粗检测
        // 方法 1: 检查 symbolicTraits
        var isBold = traits.contains(.bold)

        // 方法 2: 检查字体名称是否包含 "Bold"（备用检测）
        if !isBold {
            let fontName = font.fontName.lowercased()
            isBold = fontName.contains("bold") || fontName.contains("-bold")
            if isBold {}
        }

        // 方法 3: 检查字体 weight（备用检测）
        if !isBold {
            if let weightTrait = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any],
               let weight = weightTrait[.weight] as? CGFloat
            {
                // NSFontWeight.bold 的值约为 0.4
                isBold = weight >= 0.4
                if isBold {}
            }
        }

        if isBold {
            formats.insert(.bold)
        }

        // 斜体检测
        // 方法 1: 检查 symbolicTraits
        var isItalic = traits.contains(.italic)

        // 方法 2: 检查字体名称是否包含 "Italic" 或 "Oblique"（备用检测）
        if !isItalic {
            let fontName = font.fontName.lowercased()
            isItalic = fontName.contains("italic") || fontName.contains("oblique")
            if isItalic {}
        }

        if isItalic {
            formats.insert(.italic)
        }

        return formats
    }

    /// 检测斜体格式（使用 obliqueness 属性）
    ///
    /// 由于中文字体（如苹方）通常没有真正的斜体变体，
    /// 我们使用 obliqueness 属性来实现和检测斜体效果
    private func detectItalicFromObliqueness(from attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let obliqueness = attributes[.obliqueness] as? Double, obliqueness > 0 {
            return true
        }
        return false
    }

    // MARK: - 文本装饰检测

    /// 检测文本装饰（下划线、删除线、高亮、斜体）
    private func detectTextDecorations(from attributes: [NSAttributedString.Key: Any]) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []

        // 斜体检测 - 使用 obliqueness 属性
        // 这是为了支持中文斜体，因为中文字体通常没有真正的斜体变体
        if detectItalicFromObliqueness(from: attributes) {
            formats.insert(.italic)
        }

        // 下划线检测
        if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
            formats.insert(.underline)
        }

        // 删除线检测
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
            formats.insert(.strikethrough)
        }

        // 高亮检测
        if let backgroundColor = attributes[.backgroundColor] as? NSColor {
            if backgroundColor.alphaComponent > 0.1, backgroundColor != .clear, backgroundColor != .white {
                formats.insert(.highlight)
            }
        }

        return formats
    }

    // MARK: - 段落格式检测

    /// 检测段落格式（对齐方式）
    private func detectParagraphFormats(from attributes: [NSAttributedString.Key: Any]) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []

        guard let paragraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle else {
            return formats
        }

        switch paragraphStyle.alignment {
        case .center:
            formats.insert(.alignCenter)
        case .right:
            formats.insert(.alignRight)
        default:
            break
        }

        currentIndentLevel = Int(paragraphStyle.firstLineHeadIndent / 20) + 1

        return formats
    }

    // MARK: - 列表格式检测

    /// 检测列表格式（无序、有序、复选框）
    private func detectListFormats(at position: Int) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []

        // 获取当前行的范围
        let lineRange = getLineRange(at: position)
        guard lineRange.location < nsAttributedText.length else {
            return formats
        }

        // 检查当前行开头的属性
        let lineAttributes = nsAttributedText.attributes(at: lineRange.location, effectiveRange: nil)

        // 方法 1: 检查 listType 自定义属性（最可靠的方式）
        if let listType = lineAttributes[.listType] {
            // listType 可能是 ListType 枚举或字符串
            if let listTypeEnum = listType as? ListType {
                switch listTypeEnum {
                case .bullet:
                    formats.insert(.bulletList)
                case .ordered:
                    formats.insert(.numberedList)
                case .checkbox:
                    formats.insert(.checkbox)
                case .none:
                    break
                }
            } else if let listTypeString = listType as? String {
                if listTypeString == "bullet" {
                    formats.insert(.bulletList)
                } else if listTypeString == "ordered" || listTypeString == "order" {
                    formats.insert(.numberedList)
                } else if listTypeString == "checkbox" {
                    formats.insert(.checkbox)
                }
            }
        }
        return formats
    }

    // MARK: - 特殊元素检测

    /// 检测特殊元素格式（引用块、分割线）
    private func detectSpecialElementFormats(at position: Int) -> Set<TextFormat> {
        var formats: Set<TextFormat> = []

        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)

        // 检测引用块
        if let isQuote = attributes[.quoteBlock] as? Bool, isQuote {
            formats.insert(.quote)
        }

        // 检测分割线
        if let attachment = attributes[.attachment] as? NSTextAttachment {
            if attachment is HorizontalRuleAttachment {
                formats.insert(.horizontalRule)
            }
        }

        return formats
    }

    /// 检测光标位置的特殊元素
    func detectSpecialElementAtCursor() {
        guard !nsAttributedText.string.isEmpty else {
            currentSpecialElement = nil
            return
        }

        let position = min(cursorPosition, nsAttributedText.length - 1)
        guard position >= 0 else {
            currentSpecialElement = nil
            return
        }

        // 检查是否有附件
        let attributes = nsAttributedText.attributes(at: position, effectiveRange: nil)

        if let attachment = attributes[.attachment] as? NSTextAttachment {
            // 识别附件类型
            if let checkboxAttachment = attachment as? InteractiveCheckboxAttachment {
                currentSpecialElement = .checkbox(
                    checked: checkboxAttachment.isChecked,
                    level: checkboxAttachment.level
                )
                // 更新工具栏状态
                toolbarButtonStates[.checkbox] = true
            } else if attachment is HorizontalRuleAttachment {
                currentSpecialElement = .horizontalRule
            } else if let bulletAttachment = attachment as? BulletAttachment {
                currentSpecialElement = .bulletPoint(indent: bulletAttachment.indent)
                toolbarButtonStates[.bulletList] = true
            } else if let orderAttachment = attachment as? OrderAttachment {
                currentSpecialElement = .numberedItem(
                    number: orderAttachment.number,
                    indent: orderAttachment.indent
                )
                toolbarButtonStates[.numberedList] = true
            } else if let imageAttachment = attachment as? ImageAttachment {
                currentSpecialElement = .image(
                    fileId: imageAttachment.fileId,
                    src: imageAttachment.src
                )
            } else {
                currentSpecialElement = nil
            }
        } else {
            currentSpecialElement = nil
            // 清除特殊元素相关的工具栏状态
            toolbarButtonStates[.checkbox] = false
            toolbarButtonStates[.bulletList] = false
            toolbarButtonStates[.numberedList] = false
        }
    }

    // MARK: - 工具方法

    /// 获取指定位置所在行的范围
    private func getLineRange(at position: Int) -> NSRange {
        let string = nsAttributedText.string as NSString
        return string.lineRange(for: NSRange(location: position, length: 0))
    }

    /// 更新格式状态并验证
    private func updateFormatsWithValidation(_ detectedFormats: Set<TextFormat>) {
        let errorHandler = FormatErrorHandler.shared

        do {
            let validatedFormats = validateMutuallyExclusiveFormats(detectedFormats)
            let previousFormats = currentFormats
            let previousParagraphStyle = detectParagraphStyleFromFormats(previousFormats)
            batchUpdateState {
                currentFormats = validatedFormats
                for format in TextFormat.allCases {
                    toolbarButtonStates[format] = validatedFormats.contains(format)
                }
            }

            // 检测新的段落样式并发送通知（如果变化）
            let newParagraphStyle = detectParagraphStyleFromFormats(validatedFormats)
            if previousParagraphStyle != newParagraphStyle {
                postParagraphStyleNotification(newParagraphStyle)
            }

            // 验证状态更新是否成功
            if currentFormats != validatedFormats {
                // 状态不一致，记录错误
                let context = FormatErrorContext(
                    operation: "updateFormatsWithValidation",
                    format: nil,
                    selectedRange: selectedRange,
                    textLength: nsAttributedText.length,
                    cursorPosition: cursorPosition,
                    additionalInfo: [
                        "previousFormats": previousFormats.map(\.displayName),
                        "expectedFormats": validatedFormats.map(\.displayName),
                        "actualFormats": currentFormats.map(\.displayName),
                    ]
                )
                errorHandler.handleError(
                    .stateInconsistency(
                        expected: validatedFormats.map(\.displayName).joined(separator: ", "),
                        actual: currentFormats.map(\.displayName).joined(separator: ", ")
                    ),
                    context: context
                )
            }
            errorHandler.resetErrorCount()
        } catch {
            let context = FormatErrorContext(
                operation: "updateFormatsWithValidation",
                format: nil,
                selectedRange: selectedRange,
                textLength: nsAttributedText.length,
                cursorPosition: cursorPosition,
                additionalInfo: nil
            )
            let result = errorHandler.handleError(
                .stateSyncFailed(reason: error.localizedDescription),
                context: context
            )

            // 根据恢复操作执行相应处理
            if result.recoveryAction == .forceStateUpdate {
                // 清除所有格式并重新检测
                clearAllFormats()
            }
        }
    }

    /// 验证互斥格式，确保只保留一个
    private func validateMutuallyExclusiveFormats(_ formats: Set<TextFormat>) -> Set<TextFormat> {
        var validated = formats

        // 标题格式互斥 - 优先保留最大的标题
        let headings: [TextFormat] = [.heading1, .heading2, .heading3]
        let detectedHeadings = headings.filter { formats.contains($0) }
        if detectedHeadings.count > 1 {
            // 保留第一个（最大的）标题
            for heading in detectedHeadings.dropFirst() {
                validated.remove(heading)
            }
        }

        // 对齐格式互斥 - 优先保留居中
        let alignments: [TextFormat] = [.alignCenter, .alignRight]
        let detectedAlignments = alignments.filter { formats.contains($0) }
        if detectedAlignments.count > 1 {
            // 保留第一个对齐方式
            for alignment in detectedAlignments.dropFirst() {
                validated.remove(alignment)
            }
        }

        // 列表格式互斥 - 优先保留复选框
        let lists: [TextFormat] = [.checkbox, .bulletList, .numberedList]
        let detectedLists = lists.filter { formats.contains($0) }
        if detectedLists.count > 1 {
            // 保留第一个列表类型
            for list in detectedLists.dropFirst() {
                validated.remove(list)
            }
        }

        return validated
    }

    // MARK: - 段落样式查询

    /// 获取当前段落样式字符串
    ///
    /// 根据当前格式集合返回对应的段落样式字符串
    /// 用于菜单栏勾选状态同步
    ///
    /// - Returns: 段落样式字符串（heading, subheading, subtitle, body, orderedList, unorderedList, blockQuote）
    public func getCurrentParagraphStyleString() -> String {
        detectParagraphStyleFromFormats(currentFormats)
    }

    /// 从格式集合中检测段落样式
    private func detectParagraphStyleFromFormats(_ formats: Set<TextFormat>) -> String {
        if formats.contains(.heading1) {
            "heading"
        } else if formats.contains(.heading2) {
            "subheading"
        } else if formats.contains(.heading3) {
            "subtitle"
        } else if formats.contains(.numberedList) {
            "orderedList"
        } else if formats.contains(.bulletList) {
            "unorderedList"
        } else if formats.contains(.quote) {
            "blockQuote"
        } else {
            "body"
        }
    }

    /// 发送段落样式变化通知
    private func postParagraphStyleNotification(_ paragraphStyleRaw: String) {
        NotificationCenter.default.post(
            name: .paragraphStyleDidChange,
            object: self,
            userInfo: ["paragraphStyle": paragraphStyleRaw]
        )
    }

    // MARK: - 性能统计

    /// 获取格式状态同步器的性能统计信息
    /// - Returns: 性能统计信息字典
    func getFormatSyncPerformanceStats() -> [String: Any] {
        formatStateSynchronizer.getPerformanceStats()
    }

    /// 重置格式状态同步器的性能统计信息
    func resetFormatSyncPerformanceStats() {
        formatStateSynchronizer.resetPerformanceStats()
    }

    /// 打印格式状态同步器的性能统计信息
    func printFormatSyncPerformanceStats() {
        formatStateSynchronizer.printPerformanceStats()
    }
}
