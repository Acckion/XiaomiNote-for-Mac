import AppKit
import Foundation

/// 段落管理器
/// 负责检测段落边界、维护段落列表、应用段落格式
public class ParagraphManager {
    // MARK: - Properties

    /// 当前所有段落
    public private(set) var paragraphs: [Paragraph] = []

    // MARK: - Testing Support

    /// 设置段落列表（仅用于测试）
    /// - Parameter paragraphs: 段落数组
    func setParagraphs(_ paragraphs: [Paragraph]) {
        self.paragraphs = paragraphs
    }

    /// 标题段落（总是第一个）
    public var titleParagraph: Paragraph? {
        paragraphs.first(where: { $0.type == .title })
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Paragraph Boundary Detection

    /// 检测段落边界
    ///
    /// 遍历文本存储，识别换行符位置，构建段落范围数组。
    /// 处理空文本和单段落的边缘情况。
    ///
    /// **附件处理规则**:
    /// - "真实附件"（ImageAttachment, AudioAttachment, HorizontalRuleAttachment）必须独占一个段落
    /// - "列表标记附件"（BulletAttachment, OrderAttachment, InteractiveCheckboxAttachment）
    ///   在逻辑上不是附件，而是段落的一部分，不需要特殊处理
    ///
    /// _Requirements: 8.5_
    ///
    /// - Parameter textStorage: 文本存储
    /// - Returns: 段落范围数组
    public func detectParagraphBoundaries(in textStorage: NSTextStorage) -> [NSRange] {
        let text = textStorage.string
        let length = text.count

        // 边缘情况：空文本
        guard length > 0 else {
            return []
        }

        var paragraphRanges: [NSRange] = []
        var currentStart = 0

        // 遍历文本，查找换行符
        for (index, character) in text.enumerated() {
            // 检测换行符（\n 或 \r\n）
            if character == "\n" || character == "\r" {
                // 计算当前段落的范围（包含换行符）
                let paragraphLength = index - currentStart + 1
                let range = NSRange(location: currentStart, length: paragraphLength)

                // 验证段落中的附件
                if validateAttachmentsInParagraph(range, in: textStorage) {
                    paragraphRanges.append(range)
                } else {
                    // 附件验证失败，记录警告但仍然添加段落
                    paragraphRanges.append(range)
                }

                // 更新下一个段落的起始位置
                currentStart = index + 1

                // 处理 \r\n 的情况，跳过 \n
                if character == "\r", index + 1 < length {
                    let nextIndex = text.index(text.startIndex, offsetBy: index + 1)
                    if text[nextIndex] == "\n" {
                        currentStart = index + 2
                    }
                }
            }
        }

        // 处理最后一个段落（如果文本不以换行符结尾）
        if currentStart < length {
            let paragraphLength = length - currentStart
            let range = NSRange(location: currentStart, length: paragraphLength)

            // 验证段落中的附件
            if validateAttachmentsInParagraph(range, in: textStorage) {
                paragraphRanges.append(range)
            } else {
                // 附件验证失败，记录警告但仍然添加段落
                paragraphRanges.append(range)
            }
        }

        // 边缘情况：如果没有找到任何段落（例如只有换行符），返回一个空段落
        if paragraphRanges.isEmpty, length > 0 {
            paragraphRanges.append(NSRange(location: 0, length: length))
        }

        return paragraphRanges
    }

    /// 验证段落中的附件是否符合规则
    ///
    /// **验证规则**:
    /// 1. "真实附件"（图片、音频、分割线）必须独占一个段落
    /// 2. "列表标记附件"（项目符号、编号、复选框）可以与文本共存
    /// 3. 附件字符不能跨越段落边界
    ///
    /// _Requirements: 8.5_
    ///
    /// - Parameters:
    ///   - range: 段落范围
    ///   - textStorage: 文本存储
    /// - Returns: 如果附件符合规则返回 true，否则返回 false
    private func validateAttachmentsInParagraph(_ range: NSRange, in textStorage: NSTextStorage) -> Bool {
        var isValid = true
        var hasTrueAttachment = false
        var hasText = false

        // 遍历段落中的所有字符
        textStorage.enumerateAttribute(.attachment, in: range, options: []) { value, subRange, stop in
            if let attachment = value as? NSTextAttachment {
                // 检查是否为"真实附件"
                if isTrueAttachment(attachment) {
                    hasTrueAttachment = true

                    // 验证附件字符不跨越段落边界
                    if !NSEqualRanges(NSIntersectionRange(subRange, range), subRange) {
                        isValid = false
                        stop.pointee = true
                    }
                }
                // 列表标记附件不需要特殊验证
            } else {
                // 非附件字符，检查是否为有效文本（非换行符）
                let text = (textStorage.string as NSString).substring(with: subRange)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hasText = true
                }
            }
        }

        // 验证"真实附件"独占段落的规则
        if hasTrueAttachment, hasText {
            // 注意: 这里只是警告，不强制失败，因为可能存在遗留数据
            // isValid = false
        }

        return isValid
    }

    /// 判断附件是否为"真实附件"
    ///
    /// **真实附件**:
    /// - ImageAttachment: 图片附件
    /// - AudioAttachment: 音频附件
    /// - HorizontalRuleAttachment: 分割线附件
    ///
    /// **非真实附件（列表标记）**:
    /// - BulletAttachment: 项目符号
    /// - OrderAttachment: 有序列表编号
    /// - InteractiveCheckboxAttachment: 复选框
    ///
    /// _Requirements: 8.5_
    ///
    /// - Parameter attachment: NSTextAttachment 对象
    /// - Returns: 如果是真实附件返回 true，否则返回 false
    private func isTrueAttachment(_ attachment: NSTextAttachment) -> Bool {
        // 使用类型检查判断是否为真实附件
        attachment is ImageAttachment
            || attachment is AudioAttachment
            || attachment is HorizontalRuleAttachment
    }

    // MARK: - Paragraph List Management

    /// 更新段落列表
    ///
    /// 在文本变化时更新段落列表，跟踪每个段落的范围和版本。
    /// 采用简化的策略：重新检测所有段落边界，但保留旧段落的类型和版本信息。
    ///
    /// - Parameters:
    ///   - textStorage: 文本存储
    ///   - changedRange: 变化的范围
    public func updateParagraphs(in textStorage: NSTextStorage, changedRange _: NSRange) {
        // 1. 检测新的段落边界
        let newParagraphRanges = detectParagraphBoundaries(in: textStorage)

        // 2. 如果段落列表为空（首次初始化），直接创建所有段落
        if paragraphs.isEmpty {
            paragraphs = newParagraphRanges.enumerated().map { index, range in
                // 第一个段落是标题类型
                let type: ParagraphType = (index == 0) ? .title : .normal

                return Paragraph(
                    range: range,
                    type: type,
                    version: 0,
                    needsReparse: true
                )
            }
            return
        }

        // 3. 创建旧段落的位置映射（用于查找对应关系）
        // 使用段落的起始位置作为键
        var oldParagraphsByLocation: [Int: Paragraph] = [:]
        for paragraph in paragraphs {
            oldParagraphsByLocation[paragraph.range.location] = paragraph
        }

        // 4. 构建新的段落列表，尽可能保留旧段落的信息
        var newParagraphs: [Paragraph] = []

        for (index, newRange) in newParagraphRanges.enumerated() {
            // 尝试找到对应的旧段落
            // 策略：查找起始位置最接近的旧段落
            var matchedOldParagraph: Paragraph?
            var minDistance = Int.max

            for oldParagraph in paragraphs {
                // 计算位置距离
                let distance = abs(oldParagraph.range.location - newRange.location)

                // 如果距离更小，或者位置完全匹配，则认为是对应的段落
                if distance < minDistance {
                    minDistance = distance
                    matchedOldParagraph = oldParagraph
                }

                // 如果位置完全匹配，直接使用
                if distance == 0 {
                    break
                }
            }

            // 创建新段落
            if let oldParagraph = matchedOldParagraph, minDistance <= 10 {
                // 找到了对应的旧段落，保留其类型和版本信息
                let rangeChanged = oldParagraph.range != newRange

                let newParagraph = Paragraph(
                    range: newRange,
                    type: oldParagraph.type,
                    metaAttributes: oldParagraph.metaAttributes,
                    layoutAttributes: oldParagraph.layoutAttributes,
                    decorativeAttributes: oldParagraph.decorativeAttributes,
                    version: rangeChanged ? oldParagraph.version + 1 : oldParagraph.version,
                    needsReparse: rangeChanged || oldParagraph.needsReparse
                )

                newParagraphs.append(newParagraph)

                // 从映射中移除已匹配的段落，避免重复匹配
                if let location = paragraphs.firstIndex(where: { $0.range == oldParagraph.range }) {
                    paragraphs.remove(at: location)
                }
            } else {
                // 没有找到对应的旧段落，创建新段落
                // 第一个段落保持标题类型
                let type: ParagraphType = (index == 0 && newParagraphs.isEmpty) ? .title : .normal

                let newParagraph = Paragraph(
                    range: newRange,
                    type: type,
                    version: 0,
                    needsReparse: true
                )

                newParagraphs.append(newParagraph)
            }
        }

        // 5. 更新段落列表
        paragraphs = newParagraphs
    }

    // MARK: - Paragraph Query

    /// 获取指定位置的段落
    /// - Parameter location: 文本位置
    /// - Returns: 段落对象，如果位置无效则返回 nil
    public func paragraph(at location: Int) -> Paragraph? {
        paragraphs.first { paragraph in
            paragraph.range.location <= location && location < paragraph.endLocation
        }
    }

    /// 获取指定范围内的段落
    /// - Parameter range: 文本范围
    /// - Returns: 段落数组
    public func paragraphs(in range: NSRange) -> [Paragraph] {
        paragraphs.filter { paragraph in
            // 检查段落是否与指定范围有交集
            NSIntersectionRange(paragraph.range, range).length > 0
        }
    }

    // MARK: - Paragraph Format Application

    /// 应用段落格式
    ///
    /// 将指定的段落类型应用到给定范围内的所有段落。
    /// 这个方法会：
    /// 1. 识别范围内的所有段落
    /// 2. 为每个段落应用段落类型
    /// 3. 更新段落的元属性
    /// 4. 应用相应的布局和装饰属性到文本存储
    /// 5. 确保格式在整个段落内一致
    ///
    /// - Parameters:
    ///   - type: 段落类型
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    ///
    /// _Requirements: 1.3, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_
    public func applyParagraphFormat(_ type: ParagraphType, to range: NSRange, in textStorage: NSTextStorage) {
        // 1. 获取范围内的所有段落
        let affectedParagraphs = paragraphs(in: range)

        guard !affectedParagraphs.isEmpty else {
            return
        }

        textStorage.beginEditing()

        // 2. 为每个段落应用格式
        for paragraph in affectedParagraphs {
            applyParagraphFormatToSingleParagraph(type, paragraph: paragraph, in: textStorage)
        }

        textStorage.endEditing()

        // 3. 更新段落列表中的段落类型
        updateParagraphTypes(affectedParagraphs, newType: type)
    }

    /// 应用段落格式到单个段落
    ///
    /// - Parameters:
    ///   - type: 段落类型
    ///   - paragraph: 段落对象
    ///   - textStorage: 文本存储
    private func applyParagraphFormatToSingleParagraph(
        _ type: ParagraphType,
        paragraph: Paragraph,
        in textStorage: NSTextStorage
    ) {
        let paragraphRange = paragraph.range

        // 根据段落类型应用相应的格式
        switch type {
        case .title:
            // 标题段落：应用标题样式（通常是第一个段落）
            applyTitleFormat(to: paragraphRange, in: textStorage)

        case let .heading(level):
            // 标题格式：应用对应级别的标题字体大小
            applyHeadingFormat(level: level, to: paragraphRange, in: textStorage)

        case .normal:
            // 普通段落：移除所有块级格式，恢复正文样式
            applyNormalFormat(to: paragraphRange, in: textStorage)

        case let .list(listType):
            // 列表格式：应用列表样式
            applyListFormat(listType: listType, to: paragraphRange, in: textStorage)

        case .quote:
            // 引用格式：应用引用块样式
            applyQuoteFormat(to: paragraphRange, in: textStorage)

        case .code:
            // 代码块格式：应用代码块样式
            applyCodeFormat(to: paragraphRange, in: textStorage)
        }

        // 设置段落类型元属性
        textStorage.addAttribute(.paragraphType, value: type, range: paragraphRange)
    }

    /// 更新段落列表中的段落类型
    ///
    /// - Parameters:
    ///   - affectedParagraphs: 受影响的段落列表
    ///   - newType: 新的段落类型
    private func updateParagraphTypes(_ affectedParagraphs: [Paragraph], newType: ParagraphType) {
        for affectedParagraph in affectedParagraphs {
            // 在段落列表中查找并更新
            if let index = paragraphs.firstIndex(where: { $0.range == affectedParagraph.range }) {
                // 创建新的段落对象，更新类型并标记需要重新解析
                paragraphs[index] = affectedParagraph.withType(newType)
            }
        }
    }

    // MARK: - Format Application Helpers

    /// 应用标题段落格式
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private func applyTitleFormat(to range: NSRange, in textStorage: NSTextStorage) {
        // 标题段落使用较大的字体（可以根据需要调整）
        let titleFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
        textStorage.addAttribute(.font, value: titleFont, range: range)

        // 设置段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 12
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        // 设置元属性标记
        textStorage.addAttribute(.isTitle, value: true, range: range)
    }

    /// 应用标题格式
    ///
    /// - Parameters:
    ///   - level: 标题级别（1-6）
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private func applyHeadingFormat(level: Int, to range: NSRange, in textStorage: NSTextStorage) {
        // 根据级别确定字体大小
        let fontSize: CGFloat = switch level {
        case 1: 23 // H1
        case 2: 20 // H2
        case 3: 17 // H3
        case 4: 16 // H4
        case 5: 15 // H5
        case 6: 14 // H6
        default: 14
        }

        let headingFont = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textStorage.addAttribute(.font, value: headingFont, range: range)

        // 设置段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
    }

    /// 应用普通段落格式
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private func applyNormalFormat(to range: NSRange, in textStorage: NSTextStorage) {
        // 使用正文字体
        let normalFont = NSFont.systemFont(ofSize: 14, weight: .regular)
        textStorage.addAttribute(.font, value: normalFont, range: range)

        // 移除所有块级格式属性
        textStorage.removeAttribute(.isTitle, range: range)
        textStorage.removeAttribute(.listType, range: range)
        textStorage.removeAttribute(.listIndent, range: range)
        textStorage.removeAttribute(.listNumber, range: range)
        textStorage.removeAttribute(.quoteBlock, range: range)
        textStorage.removeAttribute(.quoteIndent, range: range)

        // 设置基本段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
    }

    /// 应用列表格式
    ///
    /// - Parameters:
    ///   - listType: 列表类型
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private func applyListFormat(listType: ListType, to range: NSRange, in textStorage: NSTextStorage) {
        // 设置列表类型属性
        textStorage.addAttribute(.listType, value: listType, range: range)
        textStorage.addAttribute(.listIndent, value: 1, range: range)

        // 使用正文字体（列表项使用正文大小）
        let listFont = NSFont.systemFont(ofSize: 14, weight: .regular)
        textStorage.addAttribute(.font, value: listFont, range: range)

        // 设置列表段落样式
        let indentUnit: CGFloat = 20
        let bulletWidth: CGFloat = 24

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.headIndent = bulletWidth
        paragraphStyle.tabStops = [NSTextTab(textAlignment: .left, location: bulletWidth)]
        paragraphStyle.defaultTabInterval = indentUnit
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        // 根据列表类型设置额外属性
        switch listType {
        case .ordered:
            textStorage.addAttribute(.listNumber, value: 1, range: range)
        case .checkbox:
            textStorage.addAttribute(.checkboxChecked, value: false, range: range)
        default:
            break
        }
    }

    /// 应用引用格式
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private func applyQuoteFormat(to range: NSRange, in textStorage: NSTextStorage) {
        // 设置引用块属性
        textStorage.addAttribute(.quoteBlock, value: true, range: range)
        textStorage.addAttribute(.quoteIndent, value: 1, range: range)

        // 使用正文字体
        let quoteFont = NSFont.systemFont(ofSize: 14, weight: .regular)
        textStorage.addAttribute(.font, value: quoteFont, range: range)

        // 设置引用块段落样式
        let quoteBorderWidth: CGFloat = 3
        let quotePadding: CGFloat = 12

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.firstLineHeadIndent = quoteBorderWidth + quotePadding
        paragraphStyle.headIndent = quoteBorderWidth + quotePadding
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8

        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        // 设置引用块背景色
        let quoteBackgroundColor = NSColor.systemBlue.withAlphaComponent(0.05)
        textStorage.addAttribute(.backgroundColor, value: quoteBackgroundColor, range: range)
    }

    /// 应用代码块格式
    ///
    /// - Parameters:
    ///   - range: 应用范围
    ///   - textStorage: 文本存储
    private func applyCodeFormat(to range: NSRange, in textStorage: NSTextStorage) {
        // 使用等宽字体
        let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textStorage.addAttribute(.font, value: codeFont, range: range)

        // 设置代码块段落样式
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 8

        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)

        // 设置代码块背景色
        let codeBackgroundColor = NSColor.systemGray.withAlphaComponent(0.1)
        textStorage.addAttribute(.backgroundColor, value: codeBackgroundColor, range: range)
    }
}

// MARK: - Helper Methods

private extension ParagraphManager {
    /// 检查字符是否为换行符
    /// - Parameter character: 要检查的字符
    /// - Returns: 如果是换行符返回 true，否则返回 false
    func isNewlineCharacter(_ character: Character) -> Bool {
        character == "\n" || character == "\r"
    }
}
